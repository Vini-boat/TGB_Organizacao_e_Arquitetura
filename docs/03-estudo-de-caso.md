# 3. Estudo de caso: balanceamento de carga e alta disponibilidade com LXD

Arquitetura do estudo de caso do Trabalho GB, montada **só com contêineres** LXD dentro
da VM `lxd-host` (ver [01-configuracao-ambiente.md](01-configuracao-ambiente.md)).

> **Status:** projeto da arquitetura. Os trechos de configuração são esboços; os scripts
> de montagem e os testes no ambiente real vêm na próxima etapa.

---

## 3.1 Decisões

| Decisão | Escolha | Motivo |
|---|---|---|
| Tecnologia | Contêineres LXD, **nenhuma VM** além da `lxd-host` | Foco do trabalho no LXC; a `lxd-host` só existe porque o Windows não tem núcleo Linux |
| Quantidade | **6 contêineres**: `lb1`, `lb2`, `app1`, `app2`, `db1`, `db2` | Cada camada tem redundância: não há ponto único de falha dentro da VM |
| Balanceador | HAProxy | Balanceia o HTTP dos apps e direciona o banco para o primário |
| Redundância do balanceador | keepalived (VRRP unicast) com **IP virtual** | O IP de entrada passa de `lb1` para `lb2` se o `lb1` cair |
| Banco | PostgreSQL 16 com replicação em *streaming* | Replicação nativa, sem extensão |
| Failover do banco | **Patroni**, sem script próprio | Ferramenta padrão; promove a réplica, reintegra o nó antigo e evita dois primários |
| Consenso | **etcd com 3 membros**: `db1`, `db2`, `lb1` | Maioria de 3 tolera 1 falha. 5 membros tolerariam 2, mas não compensa a complexidade |

---

## 3.2 Arquitetura

```
Windows ──► IP da VM :8080 ──(network forward do LXD)──► IP VIRTUAL :80
                                                │ keepalived
                         ┌──────────────────────┴──────────────────────┐
                        lb1 (MASTER)                              lb2 (BACKUP)
                        HAProxy + keepalived + etcd               HAProxy + keepalived
                         └──────────────────────┬──────────────────────┘
                                   :80 leastconn        :5000 só o primário
                                  ┌─────────┴─────────┐
                                app1                app2
                                  └─────────┬─────────┘
                                            │ IP VIRTUAL :5000
                         ┌──────────────────┴──────────────────┐
                        db1                                   db2
                        PostgreSQL + Patroni + etcd           PostgreSQL + Patroni + etcd
                        (líder)          ⇄ replicação ⇄       (réplica)
```

### Endereços (sugestão)

A sub-rede da `lxdbr0` é sorteada no `lxd init` (`10.X.Y.0/24`). Os contêineres recebem
IPs fixos e o DHCP fica restrito à faixa `.100–.200`, para não colidir com eles.

| Contêiner | IP | Serviços | Membro do etcd |
|---|---|---|---|
| (IP virtual) | `10.X.Y.10` | ponto de entrada (HTTP `:80`, banco `:5000`) | — |
| `lb1` | `10.X.Y.11` | HAProxy, keepalived (MASTER, prioridade 150) | **sim** |
| `lb2` | `10.X.Y.12` | HAProxy, keepalived (BACKUP, prioridade 100) | não |
| `app1` | `10.X.Y.21` | app web | não |
| `app2` | `10.X.Y.22` | app web | não |
| `db1` | `10.X.Y.31` | PostgreSQL, Patroni | **sim** |
| `db2` | `10.X.Y.32` | PostgreSQL, Patroni | **sim** |

```bash
lxc network set lxdbr0 ipv4.dhcp.ranges 10.X.Y.100-10.X.Y.200
lxc config device override lb1 eth0 ipv4.address=10.X.Y.11
```

---

## 3.3 Componentes

### keepalived (`lb1`, `lb2`)

Os dois `lb` combinam pelo protocolo VRRP quem é o MASTER. O MASTER recebe o IP virtual.
Se o HAProxy parar, o `lb` perde prioridade e entrega o IP mesmo estando ligado.

```
# /etc/keepalived/keepalived.conf (lb1; no lb2: state BACKUP, priority 100, IPs trocados)
global_defs {
    enable_script_security
    script_user root
}

vrrp_script chk_haproxy {
    script "/usr/bin/pgrep haproxy"
    interval 2
    fall 2
    rise 2
    weight -60
}

vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 150
    advert_int 1
    unicast_src_ip 10.X.Y.11
    unicast_peer {
        10.X.Y.12
    }
    virtual_ipaddress {
        10.X.Y.10/24 dev eth0
    }
    track_script {
        chk_haproxy
    }
}
```

- **Unicast** (`unicast_peer`) evita depender de multicast na bridge.
- `weight -60`: com o HAProxy parado, o `lb1` cai de 150 para 90, abaixo do `lb2` (100).

### HAProxy (igual em `lb1` e `lb2`)

```
frontend web
    bind *:80
    default_backend apps

backend apps
    balance leastconn          # reage a servidores lentos (ver doc 04, seção 4.4.2)
    option httpchk GET /health
    server app1 10.X.Y.21:8000 check
    server app2 10.X.Y.22:8000 check

listen postgres
    mode tcp
    bind *:5000
    option httpchk OPTIONS /primary
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server db1 10.X.Y.31:5432 maxconn 100 check port 8008
    server db2 10.X.Y.32:5432 maxconn 100 check port 8008

listen stats
    mode http
    bind *:8404
    stats enable
    stats uri /
```

- `bind *:80`: o HAProxy escuta em todos os endereços, então funciona igual no `lb`
  que tem o IP virtual e no que não tem.
- O bloco `postgres` segue o modelo oficial do Patroni: o HAProxy consulta a API do
  Patroni (porta 8008) e só manda conexões para o nó que responde 200 em `/primary`.

### etcd (`db1`, `db2`, `lb1`)

Pacote `etcd-server` do Ubuntu 24.04 (versão 3.4). Cada membro conhece os outros dois:

```
ETCD_NAME="db1"
ETCD_INITIAL_CLUSTER="db1=http://10.X.Y.31:2380,db2=http://10.X.Y.32:2380,lb1=http://10.X.Y.11:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_LISTEN_PEER_URLS="http://10.X.Y.31:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.X.Y.31:2380"
ETCD_LISTEN_CLIENT_URLS="http://10.X.Y.31:2379,http://127.0.0.1:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://10.X.Y.31:2379"
```

### Patroni + PostgreSQL (`db1`, `db2`)

Pacotes `postgresql` (16) e `patroni` (3.2.2) do Ubuntu 24.04. **O Patroni é quem inicia
o PostgreSQL**, então o cluster padrão criado pelo pacote precisa ser desligado e removido
antes (`systemctl disable --now postgresql`, `pg_dropcluster 16 main --stop`).

```yaml
# /etc/patroni/config.yml (db1; no db2 trocar name e IPs)
scope: tgb
name: db1

restapi:
  listen: 0.0.0.0:8008
  connect_address: 10.X.Y.31:8008

etcd3:
  hosts: 10.X.Y.31:2379,10.X.Y.32:2379,10.X.Y.11:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    postgresql:
      use_pg_rewind: true
  initdb:
    - encoding: UTF8
  pg_hba:
    - host replication replicador 10.X.Y.0/24 scram-sha-256
    - host all all 10.X.Y.0/24 scram-sha-256

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 10.X.Y.31:5432
  data_dir: /var/lib/postgresql/16/tgb
  bin_dir: /usr/lib/postgresql/16/bin
  authentication:
    superuser:   { username: postgres,    password: "..." }
    replication: { username: replicador,  password: "..." }
```

- O `db1` inicia primeiro e cria o banco. O `db2`, ao iniciar, **copia os dados sozinho**
  (`pg_basebackup`) e vira réplica.
- `ttl: 30`, `loop_wait: 10` e `retry_timeout: 10` são os padrões. Regra do Patroni:
  `loop_wait + 2 × retry_timeout ≤ ttl`. O failover leva até cerca de `ttl` segundos.
- `use_pg_rewind: true` (padrão `false`): o antigo primário volta como réplica sem ser
  recriado do zero.

### App (`app1`, `app2`)

Um app web mínimo (por exemplo, Flask na porta 8000) com duas rotas:

| Rota | Resposta |
|---|---|
| `/` | grava uma visita e responde `servidor: app1 \| banco: db1 \| visitas: 42` |
| `/health` | `200 OK` (usada pelo health check do HAProxy) |
| `/trabalho` | gasta ~10–20 ms de CPU e responde o nome do servidor; usada pelo gerador de carga para o limite de CPU (cgroup) fazer diferença |

O app roda com `gunicorn -w 2` (dois processos), para aproveitar a CPU liberada.

O app se conecta ao banco por `10.X.Y.10:5000` (IP virtual → HAProxy → primário) e
abre uma conexão nova a cada requisição, para se recuperar sozinho depois de um failover.
O nome do banco vem de `SELECT inet_server_addr()`.

### Acesso pelo Windows

O acesso usa um **network forward** do LXD na `lxdbr0`: a porta 8080 do IP da VM vai para
a porta 80 do IP virtual. Diferente do *proxy device*, ele não fica preso a um contêiner
e continua funcionando quando o IP virtual muda de `lb`.

```bash
lxc network forward create lxdbr0 <IP-da-VM>
lxc network forward port add lxdbr0 <IP-da-VM> tcp 8080 10.X.Y.10 80
lxc network forward port add lxdbr0 <IP-da-VM> tcp 8404 10.X.Y.10 8404
```

> O IP da VM pode mudar depois de reiniciar o Windows (ver guia 01). Nesse caso, o
> forward precisa ser recriado com o IP novo.

---

## 3.4 Tolerância a falhas

| Cai | O que acontece | Tempo esperado |
|---|---|---|
| `lb1` | keepalived passa o IP virtual para o `lb2`; etcd fica com 2 de 3 | 1 a 3 s |
| `lb2` | Nada visível (é o BACKUP) | 0 |
| `app1` ou `app2` | HAProxy tira o servidor do balanceamento | ~6 s (3 checks de 2 s) |
| `db1` (líder) | Patroni elege o `db2`; HAProxy segue o novo `/primary` | até ~30 s (`ttl`) |
| `db2` (réplica) | Nada visível; o líder continua | 0 |

### Falhas duplas

Com 2 contêineres de cada tipo, só pares de **tipos diferentes** podem ser tolerados
(12 pares). Com o etcd em `db1`, `db2` e `lb1`:

| Par | Resultado |
|---|---|
| `lb1` + `db1` ou `lb1` + `db2` | **Não tolerado:** o etcd fica com 1 de 3, sem maioria. O Patroni deixa o banco **sem primário** em vez de arriscar dois. O HTTP continua respondendo, mas sem gravar |
| Os outros 10 pares | Tolerados |

> Essa é uma limitação **aceita** do projeto: 5 membros do etcd tolerariam qualquer falha
> dupla, mas a complexidade extra não compensa no trabalho. Vale um slide: "por que 3
> votos e não 4" (4 membros também só toleram 1 falha).

---

## 3.5 Onde o LXC/LXD aparece na montagem

| Passo | Recurso | Slide da aula |
|---|---|---|
| Perfis `lb`, `app` e `db` com limites de CPU e memória | Perfis, cgroups | 48 |
| `lxc copy lb1 lb2`, `lxc copy app1 app2` e `lxc copy db1 db2` (antes de iniciar o Patroni) | Clone com cópia na escrita (ZFS) | 40, 49 |
| IPs fixos com `lxc config device override` | Rede virtual (bridge) | 41 |
| `lxc exec lb2 -- ip -br a` mostrando o IP virtual mudar de contêiner | Namespace de rede | 47 |
| `ps -ef` no `lxd-host` mostrando HAProxy, Patroni e PostgreSQL dos contêineres | Namespace PID; contêiner = processos | 46, 47 |
| `lxc snapshot` dos 6 antes dos testes de falha | Snapshots | 40 |
| Network forward da VM para o IP virtual | Encaminhamento de porta | 41 |
| `lxc pause app1`: simula um servidor **travado** (processos existem mas não executam), diferente de `lxc stop` (desligado) | Freezer do cgroup | 48 |
| `lxc config set app1 limits.cpu.allowance ...` **com o contêiner rodando**, sob carga | Cgroups aplicados ao vivo | 48 |
| `boot.autostart` e `boot.autostart.priority`: depois de reiniciar a VM, os `db` (etcd + banco) ligam antes dos `app` e dos `lb` | Ordem de inicialização gerenciada pelo LXD | — |
| `lxc monitor --type=lifecycle`: eventos de parada/início dos contêineres em tempo real | API de eventos do LXD | — |

---

## 3.6 Demonstrações

| # | Teste | Comando | Resultado esperado |
|---|---|---|---|
| 1 | Balanceamento | laço de `curl` no PowerShell | `app1` e `app2` alternando |
| 2 | Estatísticas | navegador em `http://<IP-da-VM>:8404` | Servidores e contagem de requisições |
| 3 | Estado do banco | `lxc exec db1 -- patronictl -c /etc/patroni/config.yml list` | Leader/Replica, *timeline*, atraso |
| 4 | Troca planejada | `patronictl ... switchover` | Primário muda sem perda de dados |
| 5 | Queda de um app | `lxc stop app1 --force` | Só `app2` responde |
| 6 | Queda do balanceador | `lxc stop lb1 --force` | IP virtual vai para o `lb2` |
| 7 | Queda do primário | `lxc stop db1 --force` | `db2` vira líder; contador continua |
| 8 | Volta automática | `lxc start db1` | `db1` volta como réplica (`pg_rewind`) |
| 9 | Falha dupla tolerada | `lxc stop lb2 --force` + `lxc stop db1 --force` | Serviço continua |
| 10 | Falha dupla não tolerada | `lxc stop lb1 --force` + `lxc stop db1 --force` | Banco sem primário, de propósito |
| 11 | Medir indisponibilidade | script com uma requisição a cada 0,5 s | Tempo sem resposta em cada cenário |

---

## 3.7 Limitações

- **Falha dupla com o `lb1`** (seção 3.4).
- **Replicação assíncrona:** escritas feitas logo antes da queda do líder podem se perder.
  O Patroni oferece `synchronous_mode` para evitar isso, ao custo de latência.
- **Tudo roda numa VM só:** uma falha do `lxd-host`, do Windows ou do notebook derruba
  tudo. Alta disponibilidade real exigiria hosts físicos diferentes (cluster LXD).

---

## 3.8 Validação nas fontes oficiais

Conferido em novembro de 2026:

| O que foi validado | Fonte |
|---|---|
| Bloco `postgres` do HAProxy (`httpchk`, porta 8008, `on-marked-down shutdown-sessions`) | Patroni: [haproxy.cfg](https://github.com/patroni/patroni/blob/master/haproxy.cfg) |
| `/primary` responde 200 só no primário com a trava de líder | Patroni: [rest_api.rst](https://github.com/patroni/patroni/blob/master/docs/rest_api.rst) |
| Padrões `ttl` 30, `loop_wait` 10, `retry_timeout` 10; regra entre eles; `use_pg_rewind` padrão `false`; `synchronous_mode` | Patroni: [dynamic_configuration.rst](https://github.com/patroni/patroni/blob/v3.2.2/docs/dynamic_configuration.rst) |
| `etcd3` usa a API v3 do etcd por HTTP/JSON (funciona com o etcd 3.4 sem habilitar a API v2) | Patroni: [etcd3.py](https://github.com/patroni/patroni/blob/v3.2.2/patroni/dcs/etcd3.py) |
| Ubuntu 24.04: `patroni` 3.2.2 (universe) e `etcd-server` 3.4.30 | [packages.ubuntu.com/noble/patroni](https://packages.ubuntu.com/noble/patroni), [etcd-server](https://packages.ubuntu.com/noble/etcd-server) |
| Sintaxe do keepalived: `vrrp_script`, `unicast_src_ip`, `unicast_peer`, `track_script`, `enable_script_security` | [keepalived.conf(5), Ubuntu noble](https://manpages.ubuntu.com/manpages/noble/man5/keepalived.conf.5.html) |
| Network forward em bridge (`lxc network forward create` / `port add`) | LXD: [network_forwards.md](https://github.com/canonical/lxd/blob/main/doc/howto/network_forwards.md) |

**A confirmar no teste real:**

- O keepalived conseguir adicionar o IP virtual dentro de um contêiner **sem privilégio**
  (deveria, porque ele tem `CAP_NET_ADMIN` no próprio namespace de rede).
- O network forward aceitar o IP virtual como destino (a documentação fala em "IP dentro
  da sub-rede da bridge", sem exigir que seja de um contêiner) e o IP da VM como endereço
  de escuta. Alternativa: regra de DNAT no `lxd-host`.
- O formato do arquivo `/etc/default/etcd` e a unidade systemd do Patroni no pacote do
  Ubuntu (a integração do Debian com o `postgresql-common` não pôde ser consultada:
  salsa.debian.org fora da rede desta sessão).

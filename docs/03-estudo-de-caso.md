# 3. Estudo de caso: balanceamento de carga e alta disponibilidade com Incus

Arquitetura do estudo de caso do Trabalho GB, montada **só com contêineres** Incus dentro
da VM `incus-host` (ver [01-configuracao-ambiente.md](01-configuracao-ambiente.md)).

> **Status:** projeto da arquitetura. A montagem, comando a comando e em fases, está no
> [doc 05](05-montagem-passo-a-passo.md) (fase 1 escrita). Os arquivos de configuração
> reais ficam em `config/` no repositório.

---

## 3.1 Decisões

| Decisão | Escolha | Motivo |
|---|---|---|
| Tecnologia | Contêineres Incus, **nenhuma VM** além da `incus-host` | Foco do trabalho no LXC; a `incus-host` só existe porque o Windows não tem núcleo Linux |
| Quantidade | **6 contêineres**: `lb1`, `lb2`, `app1`, `app2`, `db1`, `db2` | Cada camada tem redundância: não há ponto único de falha dentro da VM |
| Balanceador | HAProxy | Balanceia o HTTP dos apps e direciona o banco para o primário |
| Redundância do balanceador | keepalived (VRRP unicast) com **IP virtual** | O IP de entrada passa de `lb1` para `lb2` se o `lb1` cair |
| Banco | PostgreSQL 16 com replicação em *streaming* | Replicação nativa, sem extensão |
| Failover do banco | **Patroni**, sem script próprio | Ferramenta padrão; promove a réplica, reintegra o nó antigo e evita dois primários |
| Consenso | **etcd com 3 membros**: `db1`, `db2`, `lb1` | Maioria de 3 tolera 1 falha. 5 membros tolerariam 2, mas não compensa a complexidade |

---

## 3.2 Arquitetura

```
Windows ──► localhost:8080 ──(VirtualBox NAT)──► VM 10.0.2.15:8080 ──(network forward do Incus)──► IP VIRTUAL :80
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

A sub-rede da `incusbr0` é fixada em `10.10.10.0/24` (doc 05, passo 1.2). Os contêineres
recebem IPs fixos e o DHCP fica restrito à faixa `.100–.200`, para não colidir com eles.

| Contêiner | IP | Serviços | Membro do etcd |
|---|---|---|---|
| (IP virtual) | `10.10.10.10` | ponto de entrada (HTTP `:80`, banco `:5000`) | — |
| `lb1` | `10.10.10.11` | HAProxy, keepalived (MASTER, prioridade 150) | **sim** |
| `lb2` | `10.10.10.12` | HAProxy, keepalived (BACKUP, prioridade 100) | não |
| `app1` | `10.10.10.21` | app web | não |
| `app2` | `10.10.10.22` | app web | não |
| `db1` | `10.10.10.31` | PostgreSQL, Patroni | **sim** |
| `db2` | `10.10.10.32` | PostgreSQL, Patroni | **sim** |

```bash
incus network set incusbr0 ipv4.dhcp.ranges 10.10.10.100-10.10.10.200
incus config device override lb1 eth0 ipv4.address=10.10.10.11
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
    unicast_src_ip 10.10.10.11
    unicast_peer {
        10.10.10.12
    }
    virtual_ipaddress {
        10.10.10.10/24 dev eth0
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
    server app1 10.10.10.21:8080 check
    server app2 10.10.10.22:8080 check

listen postgres
    mode tcp
    bind *:5000
    option httpchk OPTIONS /primary
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server db1 10.10.10.31:5432 maxconn 100 check port 8008
    server db2 10.10.10.32:5432 maxconn 100 check port 8008

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
ETCD_INITIAL_CLUSTER="db1=http://10.10.10.31:2380,db2=http://10.10.10.32:2380,lb1=http://10.10.10.11:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_LISTEN_PEER_URLS="http://10.10.10.31:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.10.10.31:2380"
ETCD_LISTEN_CLIENT_URLS="http://10.10.10.31:2379,http://127.0.0.1:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://10.10.10.31:2379"
```

### Patroni + PostgreSQL (`db1`, `db2`)

Pacotes `postgresql` (16) e `patroni` (3.2.2) do Ubuntu 24.04 (os contêineres `db`,
`app` e `lb` usam a imagem `images:ubuntu/24.04`; só a VM é Alpine). **O Patroni é quem
inicia o PostgreSQL**, então o cluster padrão criado pelo pacote precisa ser desligado e
removido antes (`systemctl disable --now postgresql`, `pg_dropcluster 16 main --stop`).

O pacote do Debian/Ubuntu traz a unidade **`patroni@.service`**, que lê
`/etc/patroni/<instância>.yml` e roda como `postgres`. Com a instância `16-main`, o
arquivo é `/etc/patroni/16-main.yml` e o serviço sobe com
`systemctl enable --now patroni@16-main`. (A outra unidade, `patroni.service`, lê
`/etc/patroni.yml`; não usamos.)

```yaml
# /etc/patroni/16-main.yml (db1; no db2 trocar name e IPs)
scope: tgb
name: db1

restapi:
  listen: 0.0.0.0:8008
  connect_address: 10.10.10.31:8008

etcd3:
  hosts: 10.10.10.31:2379,10.10.10.32:2379,10.10.10.11:2379

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
    - host replication replicador 10.10.10.0/24 scram-sha-256
    - host all all 10.10.10.0/24 scram-sha-256

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 10.10.10.31:5432
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

Um app web mínimo em **FastAPI** com página Jinja, na porta **8080** (código em
`config/app`, montagem no doc 05). Rotas (a fase 1 tem só `/` com o nome do servidor e
`/health`; as outras entram nas fases 3 e 4):

| Rota | Resposta |
|---|---|
| `/` | grava uma visita e responde `servidor: app1 \| banco: db1 \| visitas: 42` |
| `/health` | `200 OK` (usada pelo health check do HAProxy) |
| `/trabalho` | gasta ~10–20 ms de CPU e responde o nome do servidor; usada pelo gerador de carga para o limite de CPU (cgroup) fazer diferença |

O app roda com `uvicorn --workers 2` (dois processos), para aproveitar a CPU liberada.
FastAPI, uvicorn e Jinja vêm do `apt` do Ubuntu, dentro do contêiner (um venv feito no
Alpine não roda no Ubuntu: doc 05, 1.12).

O app se conecta ao banco por `10.10.10.10:5000` (IP virtual → HAProxy → primário) e
abre uma conexão nova a cada requisição, para se recuperar sozinho depois de um failover.
O nome do banco vem de `SELECT inet_server_addr()`.

### Acesso pelo Windows

São duas etapas. O VirtualBox encaminha `localhost:8080` do Windows para a porta 8080
da VM (guia 01, seção 1.3). Dentro da VM, um **network forward** do Incus na `incusbr0` leva
a porta 8080 do IP da VM (`10.0.2.15`, o endereço fixo que o NAT do VirtualBox dá a ela)
para a porta 80 do IP virtual. Diferente do *proxy device*, ele não fica preso a um contêiner
e continua funcionando quando o IP virtual muda de `lb`.

```bash
incus network forward create incusbr0 10.0.2.15
incus network forward port add incusbr0 10.0.2.15 tcp 8080 10.10.10.10 80
incus network forward port add incusbr0 10.0.2.15 tcp 8404 10.10.10.10 8404
```

> Confira o IP da VM com `ip -4 addr show eth0`. No NAT do VirtualBox ele é sempre
> `10.0.2.15` e não muda ao reiniciar, então o forward é criado uma vez só. No Windows,
> o site fica em <http://localhost:8080> e as estatísticas em <http://localhost:8404>.

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
| `incus copy lb1 lb2`, `incus copy app1 app2` e `incus copy db1 db2` (antes de iniciar o Patroni) | Clone com cópia na escrita (btrfs) | 40, 49 |
| IPs fixos com `incus config device override` | Rede virtual (bridge) | 41 |
| `incus exec lb2 -- ip -br a` mostrando o IP virtual mudar de contêiner | Namespace de rede | 47 |
| `ps -ef` no `incus-host` mostrando HAProxy, Patroni e PostgreSQL dos contêineres | Namespace PID; contêiner = processos | 46, 47 |
| `incus snapshot create` dos 6 antes dos testes de falha | Snapshots | 40 |
| Network forward da VM para o IP virtual | Encaminhamento de porta | 41 |
| `incus pause app1`: simula um servidor **travado** (processos existem mas não executam), diferente de `incus stop` (desligado) | Freezer do cgroup | 48 |
| `incus config set app1 limits.cpu.allowance ...` **com o contêiner rodando**, sob carga | Cgroups aplicados ao vivo | 48 |
| `boot.autostart` e `boot.autostart.priority`: depois de reiniciar a VM, os `db` (etcd + banco) ligam antes dos `app` e dos `lb` | Ordem de inicialização gerenciada pelo Incus | — |
| `incus monitor --type=lifecycle`: eventos de parada/início dos contêineres em tempo real | API de eventos do Incus | — |

---

## 3.6 Demonstrações

| # | Teste | Comando | Resultado esperado |
|---|---|---|---|
| 1 | Balanceamento | laço de `curl` no PowerShell | `app1` e `app2` alternando |
| 2 | Estatísticas | navegador em `http://localhost:8404` | Servidores e contagem de requisições |
| 3 | Estado do banco | `incus exec db1 -- patronictl -c /etc/patroni/16-main.yml list` | Leader/Replica, *timeline*, atraso |
| 4 | Troca planejada | `patronictl -c /etc/patroni/16-main.yml switchover tgb --leader db1 --candidate db2` | Primário muda sem perda de dados |
| 5 | Queda de um app | `incus stop app1 --force` | Só `app2` responde |
| 6 | Queda do balanceador | `incus stop lb1 --force` | IP virtual vai para o `lb2` |
| 7 | Queda do primário | `incus stop db1 --force` | `db2` vira líder; contador continua |
| 8 | Volta automática | `incus start db1` | `db1` volta como réplica (`pg_rewind`) |
| 9 | Falha dupla tolerada | `incus stop lb2 --force` + `incus stop db1 --force` | Serviço continua |
| 10 | Falha dupla não tolerada | `incus stop lb1 --force` + `incus stop db1 --force` | Banco sem primário, de propósito |
| 11 | Medir indisponibilidade | script com uma requisição a cada 0,5 s | Tempo sem resposta em cada cenário |

---

## 3.7 Limitações

- **Falha dupla com o `lb1`** (seção 3.4).
- **Replicação assíncrona:** escritas feitas logo antes da queda do líder podem se perder.
  O Patroni oferece `synchronous_mode` para evitar isso, ao custo de latência.
- **Tudo roda numa VM só:** uma falha do `incus-host`, do Windows ou do notebook derruba
  tudo. Alta disponibilidade real exigiria hosts físicos diferentes (cluster Incus).

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
| Network forward em bridge (`incus network forward create` / `port add`; o destino precisa estar na sub-rede da bridge) | Incus v7.0.1: `doc/howto/network_forwards.md` |
| Unidade `patroni@.service` lê `/etc/patroni/%i.yml` e roda como `postgres`; `pg_createconfig_patroni`; o `postgresql@` não pode mais ser usado | Debian: [README.Debian e patroni@.service](https://salsa.debian.org/postgresql/patroni/-/tree/master/debian) |
| `etcd.service` do Debian carrega `/etc/default/etcd` (`EnvironmentFile=-/etc/default/%p`) | Debian: `etcd-server.etcd.service`, tag `debian/3.4.30-1` em salsa.debian.org |
| etcd 3.4: endpoint `/health` (e `/livez`, `/readyz` desde 3.4.29) | [etcd v3.4 monitoring](https://etcd.io/docs/v3.4/op-guide/monitoring/) |
| `GET /cluster` do Patroni traz `role`, `timeline` e `lag`; `patronictl -c <arquivo> list`; `switchover [cluster] --leader <nó> --candidate <nó> [--force]` | Patroni v3.2.2: `docs/rest_api.rst`, `docs/patronictl.rst` |
| Ubuntu 24.04: `postgresql` 16 (`16+257build1`), binários em `/usr/lib/postgresql/16/bin`; `haproxy` 2.8.30 | packages.ubuntu.com (noble) |
| HAProxy 2.8: `roundrobin`, `leastconn` (o manual o desaconselha para sessões curtas como HTTP); colunas do CSV de estatísticas (`pxname`, `svname`, `scur`, `stot`, `status`, `weight`, `lbtot`, `rate`, `check_status`, `check_duration`...) | HAProxy v2.8.0: `doc/configuration.txt` (balance), `doc/management.txt` (seção 9.1, CSV) |
| A API de execução do HAProxy **não** troca o algoritmo de balanceamento (só `set server ... weight/state/health/addr`) | HAProxy v2.8.0: `doc/management.txt` (seção 9.3) |
| Incus: `limits.cpu.allowance` com tempo (`20ms/100ms`) é limite rígido e com `%` é flexível; `boot.autostart`, `.priority`, `.delay`; `ipv4.dhcp.ranges`; `ipv4.address` no NIC; eventos `instance-stopped`, `instance-paused`, `instance-resumed`, `instance-started`, `instance-snapshot-created` (tipo `lifecycle`); estado `Frozen` (código 110) no `pause`; socket em `/var/lib/incus/unix.socket`; mapa de IDs `1000000` + `1000000000` | Incus v7.0.1: `doc/reference/instance_options.md`, `doc/config_options.txt`, `doc/events.md`, `doc/rest-api.md`, `doc/userns-idmap.md`, `internal/server/sys/os.go` |
| Migração ao vivo de contêineres: suporte limitado, via CRIU instalado nos dois hosts | Incus v7.0.1: `doc/howto/move_instances.md` |
| Imagem `ubuntu:noble` (amd64) disponível no servidor `images:` do Incus | `images.linuxcontainers.org/streams/v1/index.json` |

> No Incus, o nome do evento de snapshot é **`instance-snapshot-created`** (no LXD
> era `snapshot-created`). O doc 04 já usa o nome novo.

---

## 3.9 Testes que só o ambiente responde

Não há documentação que responda: conferir durante a montagem e anotar o resultado aqui.

| # | Pergunta | Onde importa |
|---|---|---|
| [ ] T1 | **Primeiro teste:** usuário sem admin cria a VM, o disco e as regras de NAT com `VBoxManage` (`scripts/criar-vm.ps1`)? | doc 01 |
| [ ] T2 | A máquina tem Hyper-V/VBS ligado (tartaruga verde)? Se sim, a VM aguenta os 6 contêineres? | doc 01, doc 04 |
| [ ] T3 | Opções do `VBoxManage` na versão instalada (ex.: `--audio-enabled`) e telas do `setup-alpine` 3.24 (opção do repositório community) | doc 01 |
| [ ] T4 | Ordem das perguntas do `incus admin init` (o texto foi conferido) | doc 01 |
| [ ] T5 | O keepalived consegue pôr o IP virtual num contêiner **sem privilégio**? (deveria: `CAP_NET_ADMIN` no próprio namespace de rede) | 3.3 |
| [ ] T6 | VRRP unicast entre `lb1` e `lb2` funciona pela `incusbr0` | 3.3 |
| [ ] T7 | O network forward aceita o **IP virtual** como destino e o IP da VM (`10.0.2.15`) como escuta? (14/11: com o IP do `lb1` como destino **funciona**, evidências 10 e 11; falta o IP virtual, fase 2) Alternativa: DNAT com `nft` no `incus-host` | 3.3 |
| [ ] T8 | Clonar o `db1` com `incus copy` **antes** de iniciar o Patroni e só trocar nome/IP no `db2` | 3.5 |
| [ ] T9 | Caminho do cgroup de um contêiner (`cat /proc/<pid>/cgroup` no host; esperado `/lxc.payload.<nome>`) | doc 02, doc 04 |
| [ ] T10 | Com `leastconn` + limite de CPU, a divisão do tráfego muda de forma visível? | doc 04 (4.4.2) |
| [ ] T11 | Restaurar os snapshots dos 6 contêineres juntos deixa Patroni e etcd coerentes | doc 04 |
| [ ] T12 | Tempos reais de failover (app, balanceador, banco) | 3.4, doc 04 |
| [ ] T13 | O gerador de carga no Windows alcança a concorrência desejada e o NAT do VirtualBox não vira o gargalo | doc 04 |
| [ ] T14 | Atalhos do reveal.js não interferem na digitação no terminal (`ttyd` em `iframe`) | doc 04 |
| [ ] T15 | Computador de laboratório: há espaço na pasta do usuário e ela não é apagada ao sair? | doc 01 |
| [ ] T16 | `cat /sys/kernel/security/lsm` no `incus-host` não lista `apparmor` (esperado pelo `CONFIG_LSM` do núcleo `virt`) | doc 02 (segurança) |
| [ ] T17 | 2 GB de RAM bastam para os 6 contêineres Ubuntu com Patroni, PostgreSQL e etcd? (`free -m` no host com tudo ligado; se faltar, subir a VM para 3 GB com `modifyvm --memory 3072`) | doc 01 |
| [x] T18 | O `systemctl enable /srv/app/app.service` aceita a unit numa pasta compartilhada só para leitura, com dono `nobody` (mapa de IDs)? **Sim** (14/11: `systemctl cat app` mostra a unit, serviço `running`) | doc 05, 1.4 |

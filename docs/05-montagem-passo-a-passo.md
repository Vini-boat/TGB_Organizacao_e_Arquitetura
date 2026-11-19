# 5. Montagem passo a passo

Roteiro de montagem do estudo de caso ([doc 03](03-estudo-de-caso.md)), **comando a
comando**, em fases. Cada fase termina funcionando e testada antes da próxima. É a base do
"passo a passo para reprodução" da entrega.

Pré-requisito: o ambiente do [guia 01](01-configuracao-ambiente.md) pronto (Incus
inicializado, `incus list` funcionando). Todos os comandos são **dentro da VM**, como root
(`su -`) ou como o usuário `vinibezerra` (que está no grupo `incus`), salvo os marcados como
Windows.

| Fase | Contêineres | Resultado |
|---|---|---|
| **1. Balanceamento** ✅ | `lb1`, `app1`, `app2` | site em `localhost:8080` alternando entre `app1` e `app2` (o ambiente pedido na aula) |
| 2. Balanceador redundante | `+ lb2` | keepalived com IP virtual; o site sobrevive à queda do `lb1` |
| 3. Banco replicado | `+ db1`, `db2` | PostgreSQL + Patroni + etcd; o app grava visitas |
| 4. Dados sintéticos | gerador | carga contínua; falhas e limites de CPU com tráfego rodando |

### Endereços (fixos)

A sub-rede da bridge é fixada em `10.10.10.0/24` (em vez da sorteada pelo `incus admin
init`), para os arquivos de configuração terem IPs certos sem precisar editar.

| Contêiner | IP | Porta | Fase |
|---|---|---|---|
| bridge `incusbr0` (gateway) | `10.10.10.1` | — | 1 |
| IP virtual | `10.10.10.10` | 80 | 2 |
| `lb1` / `lb2` | `10.10.10.11` / `.12` | 80 (site), 8404 (estatísticas) | 1 / 2 |
| `app1` / `app2` | `10.10.10.21` / `.22` | **8080** | 1 |
| `db1` / `db2` | `10.10.10.31` / `.32` | 5432 | 3 |
| DHCP (outros contêineres) | `10.10.10.100–200` | — | 1 |

> A porta 8080 aparece em dois lugares sem conflito: no `incus-host` (entrada do
> encaminhamento para o `lb1`) e dentro do `app1`/`app2` (o uvicorn). Cada contêiner tem a
> **própria pilha de rede** (namespace `net`, slide 47), então a mesma porta em
> contêineres diferentes, ou no host, são portas diferentes.

### Arquivos

```
config/                       (no repositório)        = /srv/... na VM = /srv/... no contêiner
├── app/                                              /srv/app  (app1, app2)
│   ├── main.py               # FastAPI: "/" mostra o nome do contêiner; "/health" para o HAProxy
│   ├── templates/index.html  # página (Jinja) com o {{ hostname }}
│   ├── app.service           # unit do systemd: uvicorn com 2 workers na porta 8080
│   ├── setup.sh              # instala FastAPI/uvicorn/Jinja pelo apt e liga a unit
│   └── requirements.txt      # só para rodar fora do contêiner (venv); o contêiner usa o apt
├── lb/                                               /srv/lb   (lb1, lb2)
│   ├── haproxy.cfg           # balanceador
│   ├── keepalived.conf       # fase 2: IP virtual (linhas @lb1/@lb2 por contêiner)
│   └── setup.sh              # instala HAProxy e keepalived, liga os arquivos da pasta e reinicia
├── db/                                               /srv/db   (db1, db2)       fase 3
│   ├── setup.sh              # só instala PostgreSQL 16, Patroni e etcd
│   ├── patroni-db1.yml       # Patroni de cada db (só nome e IP mudam)
│   ├── patroni-db2.yml
│   └── placar.sql            # usuário, banco e tabela do placar
└── etcd/                                             /srv/etcd (db1, db2, lb1)  fase 3
    ├── etcd-db1              # variáveis do etcd de cada votante
    ├── etcd-db2
    └── etcd-lb1
```

A pasta **tem o mesmo caminho na VM e dentro do contêiner** (`/srv/app` → `/srv/app`): o
que se vê no `ls` do host é o que o contêiner vê. Ela é montada **só para leitura**.

Os arquivos são editados **direto na VM pelo VS Code (Remote - SSH)**, conectado ao
`incus-host`: salvou, os contêineres já enxergam. O `config/` do repositório é a cópia
para versionar e entregar (para levar de volta à VM: `scp -r config/app config/lb incus-host:/srv/`).

---

## Fase 1: balanceamento (`lb1`, `app1`, `app2`)

```
Windows ─ localhost:8080 ─(NAT VirtualBox)─► VM 10.0.2.15:8080 ─(network forward)─► lb1 10.10.10.11:80
                                                                                     │ HAProxy (rodízio)
                                                                        ┌────────────┴────────────┐
                                                                  app1 10.10.10.21:8080    app2 10.10.10.22:8080
                                                                        └──── /srv/app (só leitura) ────┘
                                                                                = /srv/app na VM
```

### 1.1 Fixar a sub-rede da bridge

```sh
incus network set incusbr0 ipv4.address=10.10.10.1/24
incus network set incusbr0 ipv4.dhcp.ranges=10.10.10.100-10.10.10.200
incus network show incusbr0
```

| Comando | O que faz | Aula |
|---|---|---|
| `ipv4.address` | Endereço da VM **na bridge** (gateway dos contêineres) e a sub-rede `/24` | Redes virtuais: a bridge é um switch em software (slide 41) |
| `ipv4.dhcp.ranges` | O DHCP (dnsmasq) só distribui de `.100` a `.200`; abaixo disso ficam os IPs fixos | — |

### 1.2 Pastas compartilhadas na VM

Como root:

```sh
mkdir -p /srv/app /srv/lb
chown vinibezerra:vinibezerra /srv/app /srv/lb
ls -l /srv
```

O dono é o `vinibezerra` para o VS Code (que entra por SSH com esse usuário) gravar
direto. Depois disso, criar os arquivos de `config/app` e `config/lb` nas pastas (pelo VS
Code ou pelo `scp` acima) e conferir: `ls -lR /srv` (evidência 03).

### 1.3 Perfis `app` e `lb`

Um perfil junta a configuração comum de um tipo de contêiner. Cada contêiner usa
**dois** perfis: o `default` (disco raiz + placa na bridge) e o da sua função.

```sh
incus profile create app
incus profile set app limits.cpu=1 limits.memory=256MiB boot.autostart=true
incus profile device add app src disk source=/srv/app path=/srv/app readonly=true

incus profile create lb
incus profile set lb limits.cpu=1 limits.memory=256MiB boot.autostart=true
incus profile device add lb cfg disk source=/srv/lb path=/srv/lb readonly=true

incus profile show app
incus profile show lb
```

| Configuração | O que faz | Aula |
|---|---|---|
| `limits.cpu=1` | O contêiner enxerga e usa 1 vCPU (cgroup `cpuset`) | Cgroups (slide 48) |
| `limits.memory=256MiB` | Teto de memória (cgroup `memory.max`); o `lxcfs` faz o `free` lá dentro mostrar 256 MiB | Cgroups (slide 48) |
| `boot.autostart=true` | O contêiner liga sozinho quando a VM liga | — |
| disk device `src`/`cfg`: `source=... path=... readonly=true` | *Bind mount* da pasta da VM dentro do contêiner, no namespace `mnt` dele; nada é copiado | Namespaces (slide 47) |

Como o disk device está **no perfil**, todo contêiner com o perfil `app` (inclusive os
clones) já nasce com a pasta montada. E mudar o device no perfil muda em **todos** os
contêineres que usam o perfil (foi assim que o caminho foi corrigido na montagem, ver 1.12).

### 1.4 `app1`

```sh
incus init images:ubuntu/24.04 app1 --profile default --profile app
incus config device override app1 eth0 ipv4.address=10.10.10.21
incus start app1
incus list
```

| Comando | O que faz |
|---|---|
| `incus init` | **Cria** o contêiner sem ligar (o `launch` é `init` + `start`). Na primeira vez baixa a imagem do Ubuntu (~142 MB); nas próximas usa o cache |
| `config device override ... eth0` | Copia a placa `eth0` do perfil para o contêiner e muda só nela o IP: o dnsmasq passa a entregar sempre `.21` para esse contêiner |
| `incus start` | Cria os namespaces e o cgroup e roda o `systemd` do Ubuntu como PID 1 (doc 02, 2.2.2) |

Instalar as dependências e ligar o app com o script da pasta compartilhada:

```sh
incus exec app1 -- ls -l /srv/app
incus exec app1 -- bash /srv/app/setup.sh
incus exec app1 -- systemctl status app --no-pager
incus exec app1 -- curl -s localhost:8080/health
incus exec app1 -- curl -s localhost:8080
```

O `/health` responde `{"status":"ok"}` e a página mostra **app1** no cartão.

O `setup.sh` ([config/app/setup.sh](../config/app/setup.sh)):

```sh
apt update
apt install -y python3-fastapi python3-uvicorn python3-jinja2
systemctl enable --now /srv/app/app.service
```

| Comando | O que faz |
|---|---|
| `ls -l /srv/app` | Os arquivos aparecem com dono `nobody`: o UID do `vinibezerra` na VM está fora do mapa de IDs do contêiner (namespace `user`, slide 47). Leitura funciona porque são legíveis por todos |
| `bash /srv/app/setup.sh` | Roda o script **dentro** do contêiner (o `bash` é o do Ubuntu). `bash` explícito porque a pasta é só leitura e o arquivo não precisa de `+x` |
| `apt install python3-fastapi ...` | FastAPI, uvicorn e Jinja **do Ubuntu**, compilados para o Ubuntu: sem `pip` e sem venv (por quê: 1.12, problema 1). **Sem `apt upgrade`**: preserva o compartilhamento de blocos do clone (1.12, problema 5) |
| `systemctl enable --now /srv/app/app.service` | Cria o link `/etc/systemd/system/app.service` → `/srv/app/app.service`, liga no boot e sobe agora. Funciona no boot porque o Incus monta o `/srv/app` **antes** de iniciar o `systemd` |
| `systemctl status app` | `active (running)`; a unit vem da pasta compartilhada (evidência 06 mostra o `systemctl cat app`) |

A unit ([config/app/app.service](../config/app/app.service)):

```ini
[Service]
User=www-data
WorkingDirectory=/srv/app
ExecStart=/usr/bin/python3 -m uvicorn main:app --host 0.0.0.0 --port 8080 --workers 2
Restart=always
RestartSec=2
```

| Linha | O que faz |
|---|---|
| `User=www-data` | O app não roda como root dentro do contêiner |
| `WorkingDirectory=/srv/app` | De onde o uvicorn importa `main.py` e o Jinja acha `templates/` |
| `--host 0.0.0.0 --port 8080` | Escuta em todos os endereços do contêiner (o HAProxy chega pela bridge) |
| `--workers 2` | Dois processos, para aproveitar a CPU (que o cgroup limita a 1) |
| `Restart=always`, `RestartSec=2` | Se o processo morrer, o systemd sobe de novo em 2 s (teste em 1.10) |

O app ([config/app/main.py](../config/app/main.py)) tem duas rotas: `/` devolve o
`index.html` com `socket.gethostname()`, que é o nome do contêiner (namespace UTS), e
`/health` devolve `{"status": "ok"}` para o HAProxy.

### 1.5 `app2` como clone do `app1`

```sh
incus stop app1
time incus copy app1 app2
incus config device set app2 eth0 ipv4.address=10.10.10.22
incus start app1 app2
incus list
incus exec app2 -- curl -s localhost:8080
```

A página mostra **app2**.

| Comando | O que faz | Aula |
|---|---|---|
| `incus stop app1` | Para copiar um sistema de arquivos parado, sem gravação no meio | — |
| `incus copy` | Clona o contêiner: no btrfs é um **snapshot do subvolume**, instantâneo (o `time` mostra); os blocos são compartilhados até alguém escrever | Cópia na escrita (slides 40, 49) |
| `config device set app2 eth0 ...` | O clone herdou a placa com o IP `.21`; aqui troca para `.22`. (`set`, não `override`, porque a placa já é do contêiner) | — |
| página com `app2` | O Incus ajusta o nome na cópia: o mesmo `main.py` responde `app2` | Namespace UTS (slide 47) |

Tudo o que foi instalado no `app1` (pacotes, o link da unit) veio junto: não precisa
rodar o `setup.sh` de novo.

### 1.6 `lb1`

```sh
incus init images:ubuntu/24.04 lb1 --profile default --profile lb
incus config device override lb1 eth0 ipv4.address=10.10.10.11
incus start lb1
incus exec lb1 -- ls -l /srv/lb
incus exec lb1 -- bash /srv/lb/setup.sh
incus exec lb1 -- systemctl status haproxy --no-pager
```

O `setup.sh` ([config/lb/setup.sh](../config/lb/setup.sh)):

```sh
apt update
apt install -y haproxy curl
ln -sf /srv/lb/haproxy.cfg /etc/haproxy/haproxy.cfg
haproxy -c -f /etc/haproxy/haproxy.cfg
systemctl restart haproxy
```

| Comando | O que faz |
|---|---|
| `ln -sf` | O `/etc/haproxy/haproxy.cfg` passa a ser um link para o arquivo compartilhado (mesmo esquema da unit do app) |
| `haproxy -c` | Só confere a sintaxe, sem aplicar: evita derrubar o balanceador com um erro de digitação (1.12, problema 3) |
| `systemctl restart haproxy` | Sobe com a configuração nova |

O que importa no [haproxy.cfg](../config/lb/haproxy.cfg):

```
backend apps
    balance roundrobin
    option httpchk GET /health
    default-server inter 2s fall 3 rise 2
    server app1 10.10.10.21:8080 check
    server app2 10.10.10.22:8080 check
```

| Linha | O que faz |
|---|---|
| `balance roundrobin` | Rodízio: uma requisição para cada servidor |
| `option httpchk GET /health` + `inter 2s fall 3 rise 2` | A cada 2 s o HAProxy chama `/health` em cada app; 3 falhas seguidas tiram o servidor, 2 sucessos o devolvem |
| `listen stats` / `bind *:8404` | Página de estatísticas (evidência 10) |

Testar de dentro da VM (o `lb1` responde na bridge):

```sh
for i in 1 2 3 4; do curl -s 10.10.10.11 | grep ">app"; echo; done
```

Deve alternar `app2` / `app1` (evidência 09).

### 1.7 Acesso pelo Windows (network forward)

```sh
incus network forward create incusbr0 10.0.2.15
incus network forward port add incusbr0 10.0.2.15 tcp 8080 10.10.10.11 80
incus network forward port add incusbr0 10.0.2.15 tcp 8404 10.10.10.11 8404
incus network forward show incusbr0 10.0.2.15
```

O `10.0.2.15` é o IP da VM no NAT do VirtualBox (confira com `ip -4 addr show eth0`). O
forward faz o núcleo da VM redirecionar (DNAT, com nftables) o que chega nas portas 8080 e
8404 para o `lb1`. Na fase 2 o destino muda para o IP virtual.

São **duas camadas de encaminhamento**: o VirtualBox leva `localhost:8080` do Windows para
`10.0.2.15:8080` da VM, e o Incus leva daí para `10.10.10.11:80` do `lb1`.

No **Windows**: abra <http://localhost:8080> (F5 algumas vezes: o nome no cartão alterna,
evidência 11) e <http://localhost:8404> (estatísticas do HAProxy, evidência 10).

### 1.8 Evidências da fase 1

Arquivos em [`evidencias/fase1/`](../evidencias/fase1/).

| # | Arquivo | Comando | Mostra | Aula |
|---|---|---|---|---|
| 01 | `01-incus-list.png` | `incus list` | `app1`, `app2`, `lb1` `RUNNING` com `.21`, `.22`, `.11` | Contêineres no Incus |
| 02 | `02-perfis-app-lb.png` | `incus profile show app` / `lb` | limites de CPU/memória (cgroups) e o disk device só leitura; `used_by` lista quem usa o perfil | Cgroups (48), namespaces (47) |
| 03 | `03-pasta-srv-na-vm.png` | `ls -lR /srv` | os arquivos do app e do balanceador na VM, compartilhados com os contêineres | Namespace `mnt` |
| 04 | `04-main-py.png` | `cat /srv/app/main.py` | o app: o nome do servidor vem de `socket.gethostname()` | Namespace UTS |
| 05 | `05-servicos-app1.png` | `incus exec app1 -- systemctl list-units --type=service --state=running` | o `systemd` do Ubuntu rodando dentro do contêiner, com o `app.service` | Contêiner de sistema |
| 06 | `06-unit-app.png` | `incus exec app1 -- systemctl cat app` | a unit vinda da pasta compartilhada e, embaixo, o *drop-in* `zzz-lxc-service.conf` (em `/run`), que desliga proteções do systemd (`ProtectKernelTunables`, `PrivateNetwork`...) que não funcionam num contêiner sem privilégio | Contêiner sem privilégio |
| 07 | `07-curl-app1.png` | `curl -s 10.10.10.21:8080` | página com `app1` | "páginas diferentes" pedidas na aula |
| 08 | `08-curl-app2.png` | `curl -s 10.10.10.22:8080` | página com `app2` | idem |
| 09 | `09-rodizio-lb1.png` | `for i in 1 2 3 4; do curl -s 10.10.10.11 \| grep ">app"; echo; done` | `app2`, `app1`, `app2`, `app1`: o rodízio | Balanceamento |
| 10 | `10-haproxy-stats-8404.webp` | navegador em `localhost:8404` | `app1` e `app2` UP, health check `L7OK/200`, sessões divididas (17/16) | Balanceamento |
| 11 | `11-navegador-8080-rodizio.mp4` | navegador em `localhost:8080` + F5 | o nome alternando, visto do Windows | Encaminhamento de portas (41) |
| — | `historico-root.txt`, `historico-vinibezerra.txt` | `cat ~/.ash_history` | todos os comandos da montagem, na ordem (inclusive os erros da 1.12) | — |

Ainda faltam (bons para o relatório):

| Comando | Deve mostrar |
|---|---|
| `incus info app1` | estado, PID, uso de CPU/memória |
| `uname -r` e `incus exec app1 -- uname -r` | o **mesmo núcleo** (Alpine) num contêiner Ubuntu |
| `cat /etc/os-release \| head -2` e `incus exec app1 -- cat /etc/os-release \| head -2` | sistemas diferentes por cima do mesmo núcleo |
| `incus network forward show incusbr0 10.0.2.15` | as duas portas encaminhadas para o `lb1` |
| `ps -ef \| grep uvicorn` (na VM) | os processos do contêiner aparecem no host como processos comuns |

### 1.9 Atualizar o app sem tirar o site do ar

Editou `main.py` ou `index.html` no VS Code (já está na VM e nos contêineres). Reiniciar
**um de cada vez**:

```sh
incus exec app1 -- systemctl restart app
curl -s 10.10.10.11:8404/\;csv | grep -E '^apps,app[12]' | cut -d, -f2,18   # app1 UP de novo?
incus exec app2 -- systemctl restart app
```

Enquanto um reinicia, o HAProxy manda tudo para o outro (*rolling update*). Se mudou o
`app.service`, rode `systemctl daemon-reload` antes do `restart`. Mudou o `haproxy.cfg`:
`incus exec lb1 -- haproxy -c -f /etc/haproxy/haproxy.cfg` e depois `systemctl reload haproxy`.

### 1.10 Testes rápidos de falha da fase 1

| Teste | Comando | Esperado |
|---|---|---|
| Processo morre | `incus exec app1 -- pkill -9 -f uvicorn` | o **systemd** sobe de novo em ~2 s (`Restart=always`) |
| Contêiner para | `incus stop app1 --force` | em ~6 s o HAProxy tira o `app1` (vermelho no 8404); só `app2` responde |
| Contêiner trava | `incus pause app1` (volta com `incus resume app1`) | processos congelados pelo cgroup (`FROZEN`); o health check falha igual |
| Volta | `incus start app1` | em ~4 s o `app1` volta ao rodízio |

### 1.11 Snapshot da fase 1

```sh
incus snapshot create lb1 fase1
incus snapshot create app1 fase1
incus snapshot create app2 fase1
incus list
```

A coluna `SNAPSHOTS` passa de 0 para 1. Voltar um contêiner: `incus snapshot restore app1
fase1`. Também vale um snapshot da VM inteira (guia 01, 1.8) com o nome `fase1`.

### 1.12 Problemas encontrados na montagem

Do histórico de comandos (`evidencias/fase1/historico-root.txt`). Servem para o relatório
e para a apresentação: cada um mostra um conceito da aula.

**1. O venv criado na VM não roda no contêiner.** O primeiro plano era um venv
(`python3 -m venv .venv` + `pip install -r requirements.txt`) criado na VM, em `/srv/app`,
e usado pelo contêiner pela pasta compartilhada. O app subia na VM, mas no `app1` não:
`head -1 .venv/bin/uvicorn` mostra que o venv aponta para o Python **do Alpine** (3.14,
compilado com **musl**), que não existe no Ubuntu (Python 3.12, **glibc**).
*Conceito:* o contêiner **compartilha o núcleo** com o host, mas **não o espaço de
usuário** (bibliotecas, interpretadores). É a diferença para uma VM, ao contrário: lá
nem o núcleo é compartilhado. *Solução:* instalar FastAPI/uvicorn/Jinja **pelo `apt` do
Ubuntu, dentro do contêiner** (`setup.sh`); o `requirements.txt` ficou só para rodar fora.

**2. Caminho de montagem.** O disk device começou em `/opt/app`, passou por `/src/app`
(erro de digitação) e ficou em `/srv/app`, igual ao caminho na VM. A troca é no perfil
(`incus profile device rm app src` + `add` com o `path` novo) e vale para todos os
contêineres do perfil. O `app1` foi recriado do zero depois disso, para o passo a passo
sair limpo.

**3. `haproxy.cfg` sem quebra de linha no fim.** O HAProxy recusou o arquivo porque a
última linha não terminava com `\n` (o editor não adicionou). O `haproxy -c` aponta o
erro; o `journalctl -xeu haproxy.service` mostra por que o serviço não subiu. *Solução:*
terminar o arquivo com uma linha em branco; no VS Code, ligar
`"files.insertFinalNewline": true`.

**4. `setup.sh` do app com `systemct`.** A última linha estava com erro de digitação
(`systemct enable ...`), então o `enable` foi rodado à mão. Corrigido em
`config/app/setup.sh`.

**5. `apt upgrade` dentro dos contêineres desfaz o copy-on-write.** Cada contêiner
passou a ocupar **~700 MB próprios**, e o `.ova` da fase 1 ficou com **2 GB**. O clone
btrfs compartilha os blocos com a origem até alguém escrever; o `apt upgrade` reescreve
centenas de arquivos de `/usr`, e cada contêiner paga a sua cópia. E o VDI dinâmico só
cresce. Explicação completa e gancho com a aula: doc 04, seção 4.6.2. *Solução:* os
`setup.sh` fazem só `apt update` + `apt install` do necessário, **nunca `apt upgrade`**; os
contêineres serão recriados assim (1.13).

### 1.13 Pendências para fechar a fase 1

Ordem sugerida. Os itens 1 a 4 aproveitam o estado atual, inchado, como evidência do
"antes"; não pule direto para a recriação.

- [ ] **1. Print do "antes" (copy-on-write perdido).** Na VM, como root:
  ```sh
  btrfs filesystem du -s /var/lib/incus/storage-pools/default/containers/*
  incus storage info default
  ```
  No `btrfs filesystem du`, a coluna `Exclusive` é o que cada contêiner ocupa **só para
  ele** (deve dar ~700 MB) e `Set shared` é o que ainda divide com os outros. Salvar como
  `evidencias/fase1/12-cow-antes.png`.
- [x] **2. Corrigir o `/srv/app/setup.sh`** na VM (`systemct` → `systemctl`), igual ao
  `config/app/setup.sh`.
- [x] **3. Apagar a sobra do teste no Alpine:** `rm -rf /srv/app/.venv /srv/app/__pycache__`
  (o `.venv` tem 54 MB e aparece dentro dos contêineres).
> **Feito em 17/11/2026 (itens 4, 5 e 9).** O "antes" do btrfs se perdeu (os contêineres
> foram recriados antes do print); a evidência do "antes" passou a ser o tamanho do `.vdi`.
> Resultado: `Exclusive` de **8 MiB** por app (737 MiB compartilhados), `.vdi` de
> **5,7 GB → 3,2 GB** após `fstrim` + `dd` + `--compact`, e `.ova` novo
> (`incus-host-fase1-v2.ova`) com **1,0 GB** (o antigo tinha 2 GB). Prints 12 a 16.

- [x] **4. Recriar os contêineres sem `apt upgrade`.** Perfis, rede e forward continuam;
  só os contêineres saem:
  ```sh
  incus delete app1 app2 lb1 --force
  ```
  E refazer 1.4 → 1.5 → 1.6 (o `incus init` usa a imagem já baixada, sem download). Testar
  com o laço do `curl` (1.6) e `localhost:8080` no Windows.
- [x] **5. Print do "depois":** os mesmos comandos do item 1 →
  `evidencias/fase1/13-cow-depois.png`. O `Exclusive` do `app2` deve ficar pequeno (é
  clone do `app1`), e o total, bem abaixo do "antes". Os dois prints lado a lado são o
  slide da lição 4.6.2.
- [ ] **6. Prints que faltam** (tabela "Ainda faltam" da 1.8): `incus info app1`,
  `uname -r` na VM e no `app1`, `os-release` dos dois, `incus network forward show
  incusbr0 10.0.2.15`, `ps -ef | grep uvicorn`. Numerar a partir de `14-...` (o 12 e o
  13 são os do copy-on-write).
- [ ] **7. Testes de falha** (1.10), com print de cada um, em especial o 8404 com o `app1`
  vermelho.
- [ ] **8. Snapshot `fase1`** dos três contêineres (1.11), com print do `incus list`
  mostrando `SNAPSHOTS 1`.
- [x] **9. Compactar o VDI e exportar um `.ova` novo** (guia 01, seção 1.9, "Compactar
  antes de exportar"). Apagar o `incus-host-fase1.ova` antigo (2 GB) só depois que o novo
  importar sem erro.
- [ ] **10. Commit** de `config/`, `docs/` e `evidencias/` (o `.ova` fica fora do git).

---

## Fase 2: balanceador redundante (`lb2` + keepalived)

```
Windows ─ localhost:8080 ─(NAT)─► VM 10.0.2.15:8080 ─(network forward)─► IP virtual 10.10.10.10:80
                                                                      │ quem tiver o IP agora
                                                     ┌────────────────┴────────────────┐
                                    lb1 10.10.10.11 (MASTER, 150)     lb2 10.10.10.12 (BACKUP, 100)
                                    HAProxy + keepalived ◄── VRRP ──► HAProxy + keepalived
                                                     └──────── /srv/lb (só leitura) ───┘
                                                                  │
                                                         app1 e app2 (fase 1)
```

O site deixa de apontar para o `lb1` e passa a apontar para um **IP virtual**
(`10.10.10.10`), que não pertence a nenhum contêiner fixo. O keepalived roda nos dois `lb` e
eles combinam, pelo protocolo **VRRP**, quem fica com o IP: normalmente o `lb1`. Se o `lb1`
cair (ou o HAProxy dele parar), o `lb2` assume o IP em segundos e o site continua.

### 2.0 Snapshot antes de mexer

É o item 8 da 1.13. Se algo der errado na fase 2, dá para voltar:

```sh
incus snapshot create lb1 fase1
incus snapshot create app1 fase1
incus snapshot create app2 fase1
incus list
```

A coluna `SNAPSHOTS` mostra 1 nos três (print `evidencias/fase1/17-snapshots-fase1.png`).

### 2.1 Configuração do keepalived (um arquivo para os dois)

Criar o [`/srv/lb/keepalived.conf`](../config/lb/keepalived.conf) na VM, pelo VS Code ou
com `scp config/lb/keepalived.conf incus-host:/srv/lb/` (no Windows):

```
global_defs {
    enable_script_security
    script_user root
}

vrrp_script chk_haproxy {
    script "/usr/bin/pgrep -x haproxy"
    interval 2
    fall 2
    rise 2
    weight -60
}

vrrp_instance VI_1 {
    interface eth0
    virtual_router_id 51
    advert_int 1
@lb1 state MASTER
@lb1 priority 150
@lb1 unicast_src_ip 10.10.10.11
@lb2 state BACKUP
@lb2 priority 100
@lb2 unicast_src_ip 10.10.10.12
    unicast_peer {
@lb1     10.10.10.12
@lb2     10.10.10.11
    }
    virtual_ipaddress {
        10.10.10.10/24 dev eth0
    }
    track_script {
        chk_haproxy
    }
}
```

| Trecho | O que faz | Aula |
|---|---|---|
| `@lb1 ...` / `@lb2 ...` | **Linha condicional**: só vale se o nome do contêiner (`uname -n`) for `lb1` ou `lb2`; nos outros, é ignorada. Por isso **um arquivo só** na pasta compartilhada serve para os dois, e o clone `lb2` funciona sem editar nada | Namespace UTS: cada contêiner tem o seu nome (slide 47) |
| `vrrp_instance VI_1` + `virtual_router_id 51` | O "grupo" VRRP. Os dois `lb` precisam do mesmo número para disputar o mesmo IP | — |
| `state` / `priority` | Quem começa como dono do IP. Ganha sempre a **maior prioridade** que estiver viva: `lb1` 150, `lb2` 100 | — |
| `advert_int 1` | O dono do IP manda um "estou vivo" (anúncio VRRP) por segundo. Sem anúncio por ~3 s, o outro assume | — |
| `unicast_src_ip` / `unicast_peer` | Manda o anúncio direto para o IP do outro `lb`, em vez de multicast (que nem toda rede virtual entrega) | Bridge (slide 41) |
| `virtual_ipaddress 10.10.10.10/24 dev eth0` | O IP que vai e volta. O MASTER o **acrescenta** à `eth0` dele; o BACKUP não tem | Namespace `net`: o IP aparece só no contêiner que é MASTER |
| `vrrp_script chk_haproxy` | A cada 2 s roda `pgrep -x haproxy`. Com 2 falhas seguidas, a prioridade cai **60**: o `lb1` vai de 150 para **90**, abaixo do `lb2` (100), e entrega o IP **mesmo estando ligado**. Não adianta ter o IP sem o HAProxy para atender | — |
| `enable_script_security` + `script_user root` | O keepalived só roda scripts de arquivos que um usuário comum não consegue alterar; o `pgrep` do sistema atende | — |

O `haproxy.cfg` **não muda**: ele escuta em `*:80`, então atende também no IP virtual
quando o contêiner o recebe.

### 2.2 keepalived no `lb1`

O HAProxy já está instalado (fase 1). Falta o keepalived:

```sh
incus exec lb1 -- apt install -y keepalived
incus exec lb1 -- ln -sf /srv/lb/keepalived.conf /etc/keepalived/keepalived.conf
incus exec lb1 -- keepalived -t -f /etc/keepalived/keepalived.conf
incus exec lb1 -- systemctl enable keepalived
incus exec lb1 -- systemctl restart keepalived
incus exec lb1 -- systemctl status keepalived --no-pager
```

| Comando | O que faz |
|---|---|
| `apt install keepalived` | Só o pacote, **sem `apt upgrade`** (1.12, problema 5). Se der erro 404, rode antes `incus exec lb1 -- apt update` |
| `ln -sf ...` | O `/etc/keepalived/keepalived.conf` vira um link para o arquivo compartilhado (mesmo esquema do `haproxy.cfg`) |
| `keepalived -t` | Só confere a sintaxe e sai, como o `haproxy -c`. Sem mensagem de erro = ok |
| `systemctl enable` + `restart` | Liga no boot e sobe agora com a configuração. (Logo depois do `apt install` o serviço não sobe porque ainda não havia arquivo de configuração) |

Conferir se o `lb1` pegou o IP virtual:

```sh
incus exec lb1 -- ip -br a
incus exec lb1 -- journalctl -u keepalived -n 15 --no-pager
for i in 1 2 3 4; do curl -s 10.10.10.10 | grep ">app"; echo; done
```

- `ip -br a`: a `eth0` do `lb1` mostra **dois** IPs, `10.10.10.11/24` e
  `10.10.10.10/24`. É o teste T5 do doc 03: o keepalived consegue mexer na rede de um
  contêiner **sem privilégio**, porque tem `CAP_NET_ADMIN` dentro do **próprio** namespace
  de rede (e só nele: não mexe na rede da VM).
- `journalctl`: `(VI_1) Entering MASTER STATE`.
- O `curl` no IP virtual alterna `app1`/`app2`, como no `lb1` direto.

Para a reprodução do zero, o [`setup.sh`](../config/lb/setup.sh) já faz tudo isso (instala
HAProxy **e** keepalived, cria os dois links, confere e reinicia).

### 2.3 `lb2` como clone do `lb1`

```sh
incus stop lb1
time incus copy lb1 lb2 --instance-only
incus config device set lb2 eth0 ipv4.address=10.10.10.12
incus start lb1 lb2
incus list
```

| Comando | O que faz | Aula |
|---|---|---|
| `incus stop lb1` | O site fica fora do ar por alguns segundos (ainda não há redundância) | — |
| `incus copy ... --instance-only` | Clone btrfs instantâneo, como o `app2`. O `--instance-only` não copia o snapshot `fase1` do `lb1` | Cópia na escrita (40, 49) |
| `config device set lb2 eth0 ...` | Troca o IP herdado (`.11`) para `.12` | — |
| `incus start lb1 lb2` | O `lb2` sobe com o nome `lb2`: o keepalived dele lê as linhas `@lb2` e entra como BACKUP. Nada para editar | Namespace UTS |

O `lb2` já tem HAProxy, keepalived e os dois links: veio tudo do `lb1`.

### 2.4 Conferir os dois

```sh
incus exec lb1 -- ip -br a
incus exec lb2 -- ip -br a
incus exec lb2 -- journalctl -u keepalived -n 10 --no-pager
```

O `10.10.10.10` aparece **só no `lb1`**. O log do `lb2` mostra `(VI_1) Entering BACKUP
STATE`. Os dois prints lado a lado são o slide do IP virtual (evidência 01 da fase 2).

Opcional, para **ver** os anúncios VRRP passando pela bridge (na VM, como root):

```sh
apk add tcpdump
tcpdump -ni incusbr0 vrrp -c 5
```

Uma linha por segundo, sempre `10.10.10.11 > 10.10.10.12: VRRPv2, Advertisement, vrid 51,
prio 150`. É o "estou vivo" do `lb1` (T6 do doc 03).

### 2.5 Site pelo IP virtual (network forward)

O forward da fase 1 aponta para o `lb1` (`10.10.10.11`). Troca o destino para o IP virtual:

```sh
incus network forward port remove incusbr0 10.0.2.15 tcp 8080
incus network forward port remove incusbr0 10.0.2.15 tcp 8404
incus network forward port add incusbr0 10.0.2.15 tcp 8080 10.10.10.10 80
incus network forward port add incusbr0 10.0.2.15 tcp 8404 10.10.10.10 8404
incus network forward show incusbr0 10.0.2.15
```

No Windows, <http://localhost:8080> continua alternando `app1`/`app2`, e o
<http://localhost:8404> mostra as estatísticas **do `lb` que estiver com o IP** (T7 do
doc 03).

### 2.6 Testes de failover

Deixe um laço rodando **numa janela** da VM, uma requisição a cada 0,5 s, com a hora:

```sh
while true; do r=$(curl -s -m 1 10.10.10.10 | grep -o 'app[12]' | head -1); echo "$(date +%T) ${r:-FALHOU}"; sleep 0.5; done
```

O `-m 1` desiste depois de 1 s. Se não veio nome, `${r:-FALHOU}` imprime `FALHOU`. Para
parar: Ctrl+C.

E faça cada teste **em outra janela**, olhando o laço e o `ip -br a`:

| # | Teste | Comando | Esperado |
|---|---|---|---|
| 1 | `lb1` desligado com calma | `incus stop lb1` | O keepalived do `lb1` avisa que está saindo (prioridade 0) e o `lb2` assume na hora: ~1 s de falha ou nenhuma |
| 2 | `lb1` volta | `incus start lb1` | O `lb1` tem prioridade maior e **retoma** o IP (outra piscada curta) |
| 3 | `lb1` derrubado | `incus stop lb1 --force` | Sem aviso: o `lb2` espera ~3 s sem anúncios e assume. Alguns `FALHOU` no laço |
| 4 | HAProxy do `lb1` para | `incus start lb1`, depois `incus exec lb1 -- systemctl stop haproxy` | Em ~4 s o script falha 2 vezes, o `lb1` cai para 90 e entrega o IP **ligado** (`journalctl -u keepalived` no `lb1`: `Script ... failed`) |
| 5 | HAProxy volta | `incus exec lb1 -- systemctl start haproxy` | Prioridade volta a 150, o `lb1` retoma o IP |
| 6 | `lb2` cai | `incus stop lb2 --force` | Nada visível: ele era o BACKUP. Depois `incus start lb2` |

Em cada teste: `incus exec lb1 -- ip -br a` e `incus exec lb2 -- ip -br a` mostram onde o IP
está, e o tempo sem resposta sai das horas do laço (T12 do doc 03).

### 2.7 Snapshot da fase 2

```sh
incus snapshot create lb1 fase2
incus snapshot create lb2 fase2
incus snapshot create app1 fase2
incus snapshot create app2 fase2
```

### 2.8 Evidências da fase 2

Em `evidencias/fase2/`:

| # | Comando | Mostra |
|---|---|---|
| 01 | `ip -br a` no `lb1` e no `lb2` | O IP virtual só no MASTER |
| 02 | `journalctl -u keepalived` nos dois | `MASTER STATE` / `BACKUP STATE` |
| 03 | `incus list` | quatro contêineres, `lb2` com `.12` |
| 04 | `btrfs filesystem du -s .../containers/*` | `lb2` com `Exclusive` pequeno (clone) |
| 05 | `incus network forward show incusbr0 10.0.2.15` | portas apontando para `10.10.10.10` |
| 06 | `tcpdump -ni incusbr0 vrrp` (opcional) | anúncios VRRP do `lb1` |
| 07 | laço + `incus stop lb1 --force` | os `FALHOU` e o tempo até o `lb2` assumir |
| 08 | `ip -br a` depois do teste 3 | o IP virtual agora no `lb2` |
| 09 | teste 4 (HAProxy parado) | o `lb1` ligado, mas sem o IP |
| 10 | vídeo do navegador em `localhost:8080` durante o teste 3 | o site continua, visto do Windows |

## Fase 3: banco replicado (`db1`, `db2`)

```
                       app1 / app2 (placar) ── 10.10.10.10:5000 ──► HAProxy (lb1 ou lb2)
                                                                     │ só manda para quem responde
                                                                     │ 200 em :8008/primary
                                       ┌─────────────────────────────┴───────────────┐
                    db1 10.10.10.31 (primário)  ── replicação (streaming) ──►  db2 10.10.10.32 (réplica)
                    PostgreSQL 16 + Patroni + etcd                              PostgreSQL 16 + Patroni + etcd
                                       └──────────── etcd: db1, db2, lb1 ────────────┘
                                         (3 votos: quem é o líder do banco?)
```

- **PostgreSQL 16:** o banco. O primário aceita escritas; a réplica recebe uma cópia
  contínua delas (*streaming replication*) e só aceita leitura.
- **Patroni:** roda em cada `db`, liga e desliga o PostgreSQL dele e decide quem é
  primário. Se o primário some, promove a réplica.
- **etcd:** um "cartório" de chave/valor replicado em 3 contêineres. O Patroni grava lá
  "o líder é o `db1`" com validade de 30 s (`ttl`) e renova a cada 10 s. Só vale o que a
  **maioria** (2 de 3) confirma, então dois `db` nunca se acham líderes ao mesmo tempo. O
  3º voto fica no `lb1` para não precisar de um 7º contêiner.
- **HAProxy (porta 5000):** pergunta à API do Patroni de cada `db` (`:8008/primary`) quem é
  o primário e só manda as conexões para ele. O app nem sabe que existem dois bancos.

Ordem da fase: **`db1` + etcd do `lb1`** → **placar no app** → **`db2`**. O cluster do etcd
**nasce com 2 membros** (`db1` e `lb1`) e o `db2` é **adicionado** no fim; o Patroni do
`db2` copia os dados sozinho. Os votantes rodam o `etcd/setup.sh` e os `db` rodam também o `db/setup.sh`:
os scripts escolhem os arquivos pelo nome do contêiner (`hostname`), sem nenhum `ln` à mão.

| Arquivo (`config/` → `/srv/` na VM) | Contêineres | Para quê |
|---|---|---|
| `etcd/etcd-db1`, `etcd-db2`, `etcd-lb1` | `db1`, `db2`, `lb1` (perfil `etcd`) | configuração do etcd de cada votante |
| `etcd/setup.sh` | `db1`, `db2`, `lb1` | instala o etcd, liga o `etcd-<hostname>` e espera a maioria |
| `db/setup.sh` | `db1`, `db2` | instala PostgreSQL e Patroni e liga o `patroni-<hostname>.yml` (depois do etcd) |
| `db/patroni-db1.yml`, `patroni-db2.yml` | `db1`, `db2` (perfil `db`) | configuração do Patroni de cada `db` |
| `db/placar.sql` | `db1` | cria o usuário, o banco e a tabela do placar |
| `lb/haproxy.cfg` (bloco `postgres`) | `lb1`, `lb2` | porta 5000 → primário |
| `app/main.py`, `app/templates/index.html` | `app1`, `app2` | o placar |

### 3.1 Pastas e arquivos

Como root na VM:

```sh
mkdir -p /srv/db /srv/etcd
chown vinibezerra:vinibezerra /srv/db /srv/etcd
```

E levar os arquivos novos e alterados (no Windows, na pasta do repositório):

```powershell
scp -r config/db config/etcd incus-host:/srv/
scp config/lb/haproxy.cfg incus-host:/srv/lb/
scp config/app/main.py config/app/setup.sh incus-host:/srv/app/
scp config/app/templates/index.html incus-host:/srv/app/templates/
```

O `haproxy.cfg` e o app mudam **na hora** dentro dos contêineres (é a mesma pasta), mas
só valem depois do `reload`/`restart` (3.6 e 3.7). Até lá o site segue como na fase 2.

Um arquivo de etcd para cada votante, só o nome e o IP mudam. O do `db1`
([config/etcd/etcd-db1](../config/etcd/etcd-db1)):

```sh
ETCD_NAME="db1"
ETCD_DATA_DIR="/var/lib/etcd/tgb"
ETCD_INITIAL_CLUSTER="db1=http://10.10.10.31:2380,lb1=http://10.10.10.11:2380"
ETCD_INITIAL_CLUSTER_TOKEN="tgb"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_LISTEN_PEER_URLS="http://10.10.10.31:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.10.10.31:2380"
ETCD_LISTEN_CLIENT_URLS="http://10.10.10.31:2379,http://127.0.0.1:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://10.10.10.31:2379"
```

| Linha | O que faz |
|---|---|
| `ETCD_NAME` | Nome deste membro; tem que bater com o da lista abaixo |
| `ETCD_DATA_DIR` | Onde o etcd guarda os dados. Uma pasta **nova** (`tgb`), separada da que o pacote criou ao ser instalado |
| `ETCD_INITIAL_CLUSTER` | Os membros **fundadores** (`db1` e `lb1`) e onde cada um conversa com os outros (porta **2380**, entre membros) |
| `ETCD_INITIAL_CLUSTER_STATE="new"` | Cluster novo. No `etcd-db2` é `"existing"` e a lista tem os 3: ele **entra** num cluster que já existe (3.8) |
| `LISTEN_CLIENT_URLS` / `ADVERTISE_CLIENT_URLS` | Porta **2379**, onde os clientes (Patroni, `etcdctl`) falam com ele |

O Patroni do `db1` ([config/db/patroni-db1.yml](../config/db/patroni-db1.yml)):

```yaml
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

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 10.10.10.31:5432
  data_dir: /var/lib/postgresql/16/tgb
  bin_dir: /usr/lib/postgresql/16/bin
  pg_hba:
    - local all all peer
    - host all all 127.0.0.1/32 scram-sha-256
    - host replication replicador 10.10.10.0/24 scram-sha-256
    - host all all 10.10.10.0/24 scram-sha-256
  authentication:
    superuser:
      username: postgres
      password: tgb-super
    replication:
      username: replicador
      password: tgb-repl
```

| Trecho | O que faz |
|---|---|
| `scope: tgb` | Nome do cluster; os dois `db` usam o mesmo |
| `restapi` (porta **8008**) | API do Patroni. O HAProxy pergunta `/primary` aqui |
| `etcd3: hosts` | Os 3 etcd; o Patroni usa o que responder |
| `ttl: 30`, `loop_wait: 10`, `retry_timeout: 10` | O líder renova a "posse" a cada 10 s; se parar de renovar, em até 30 s a réplica assume. São os padrões, e respeitam a regra `loop_wait + 2 × retry_timeout ≤ ttl` |
| `use_pg_rewind: true` | O primário antigo, quando volta, vira réplica sem ser copiado do zero |
| `initdb` | Só no primeiro `db` a subir: o Patroni cria o banco vazio |
| `data_dir` / `bin_dir` | Pasta dos dados e programas do PostgreSQL 16 do Ubuntu |
| `pg_hba` | Quem pode conectar: localmente pelo usuário do sistema (`peer`) e pela rede `10.10.10.0/24` com senha (inclusive a replicação) |
| `authentication` | Usuários que o Patroni cria e usa: `postgres` (administra, `pg_rewind`) e `replicador` (a réplica copia por ele) |

> As senhas ficam em texto puro na pasta compartilhada. Num laboratório tudo bem; vai
> para as limitações do relatório.

### 3.2 Perfis `db` e `etcd`

```sh
incus profile create db
incus profile set db limits.cpu=1 limits.memory=512MiB boot.autostart=true
incus profile device add db db disk source=/srv/db path=/srv/db readonly=true

incus profile create etcd
incus profile device add etcd etcd disk source=/srv/etcd path=/srv/etcd readonly=true
```

| Configuração | O que faz | Aula |
|---|---|---|
| `limits.memory=512MiB` | O dobro dos outros: PostgreSQL + Patroni + etcd no mesmo contêiner | Cgroups (48) |
| perfil `etcd` só com o disk device | Não tem limites: só marca **quem vota** no etcd. Os votantes ficam com 3 perfis (`default`, o da função e `etcd`), e `incus profile show etcd` lista em `used_by` exatamente os 3 votantes | Perfis |
| device chamado `etcd` (não `cfg`) | Num contêiner com dois perfis, um device de **mesmo nome** no segundo perfil substitui o do primeiro. Se fosse `cfg`, o `lb1` perderia o `/srv/lb` | — |

### 3.3 Limpar a primeira tentativa (só se ela foi feita)

Na primeira tentativa (17/11) o etcd foi criado com os **3** membros na lista, e o Patroni
não subia:

```
WARNING - Detected Etcd version 3.0.0 is lower than 3.1.0, watches are not supported
ERROR - Failed to get list of machines from http://10.10.10.31:2379/v3alpha: ... '404 page not found'
```

O etcd só define a **versão do cluster** quando **todos** os membros da lista respondem.
Com o `db2` na lista sem existir (`No route to host`), ela ficou em `3.0.0`, e o Patroni
usou o caminho antigo da API (`/v3alpha`), que o etcd 3.4 não tem mais. Solução: o cluster
nasce só com `db1` e `lb1`, e o `db2` é **adicionado** quando existir (3.8). Print:
`evidencias/fase3/problema-etcd-v3alpha.png`.

Para recomeçar daquele estado (não há dados a perder: o Patroni nunca chegou a criar o
banco), o `db1` é apagado (com os snapshots dele) e o etcd do `lb1` perde a pasta de dados,
que guardava o cluster de 3 membros. Os perfis `db` e `etcd` ficam:

```sh
incus delete db1 --force
incus exec lb1 -- systemctl stop etcd
incus exec lb1 -- rm -rf /var/lib/etcd/tgb
```

E copiar de novo as pastas `etcd` e `db` (3.1). Quem está começando do zero pula
esta seção.

### 3.4 `db1` e o 3º voto no `lb1`

```sh
incus init images:ubuntu/24.04 db1 --profile default --profile db --profile etcd
incus config device override db1 eth0 ipv4.address=10.10.10.31
incus start db1
incus profile add lb1 etcd
incus exec db1 -- ls /srv/db /srv/etcd
incus exec lb1 -- ls /srv/lb /srv/etcd
```

O `lb1` ganha o perfil `etcd` **ligado**: a pasta aparece na hora, e o `ls` mostra que o
`/srv/lb` continua lá (é o problema do nome do device, 3.2).

O etcd só funciona com **maioria**. Com os 2 fundadores, precisa dos 2 de pé, então o
`etcd/setup.sh` roda nos dois **ao mesmo tempo**, cada um numa janela da VM:

```sh
incus exec lb1 -- bash /srv/etcd/setup.sh
```

```sh
incus exec db1 -- bash /srv/etcd/setup.sh
```

Os dois param em `Esperando a maioria do etcd...` até o outro subir; aí terminam com o
`member list` mostrando `db1` e `lb1`. O script é um só: o `hostname` decide qual arquivo
cada um lê.

O [`etcd/setup.sh`](../config/etcd/setup.sh):

```sh
. /srv/etcd/etcd-$(hostname)
apt update
apt install -y etcd-server etcd-client curl
systemctl stop etcd
find /var/lib/etcd -mindepth 1 -maxdepth 1 ! -name tgb -exec rm -rf {} +
ln -sf /srv/etcd/etcd-$(hostname) /etc/default/etcd
if [ "$ETCD_INITIAL_CLUSTER_STATE" = existing ] && [ ! -d "$ETCD_DATA_DIR" ]; then
    etcdctl --endpoints=http://10.10.10.31:2379,http://10.10.10.11:2379 \
        member add "$ETCD_NAME" --peer-urls="$ETCD_INITIAL_ADVERTISE_PEER_URLS"
fi
systemctl enable etcd
systemctl start --no-block etcd
until curl -s 127.0.0.1:2379/version | grep -q '"etcdcluster":"3.4'; do sleep 2; done
etcdctl member list -w table
```

| Comando | O que faz |
|---|---|
| `. /srv/etcd/etcd-$(hostname)` | Lê as variáveis **do próprio contêiner**: o `hostname` (namespace UTS) escolhe o arquivo |
| `systemctl stop etcd` + `find ... rm` | O pacote sobe sozinho um etcd de **um membro só**, noutra pasta. Para e apaga tudo menos a nossa pasta `tgb` |
| `ln -sf ... /etc/default/etcd` | O serviço do etcd do Ubuntu lê as variáveis desse arquivo (`systemctl cat etcd`, linha `EnvironmentFile`) |
| `member add` | Só para quem **entra depois** (`existing`, o `db2`): os membros atuais aprovam a entrada |
| `start --no-block` | O etcd fica esperando a maioria antes de dizer ao systemd que subiu; sem o `--no-block` o script ficaria preso ali |
| `until curl ... "etcdcluster":"3.4"` | Espera o cluster fechar a versão 3.4. Sem isso, o Patroni podia ver `3.0.0` e cair no erro da 3.3 |

Com o etcd de pé, o PostgreSQL e o Patroni no `db1`:

```sh
incus exec db1 -- bash /srv/db/setup.sh
```

O [`db/setup.sh`](../config/db/setup.sh):

```sh
apt update
apt install -y postgresql-16 patroni curl
pg_dropcluster 16 main --stop 2>/dev/null || true
systemctl disable --now postgresql
ln -sf /srv/db/patroni-$(hostname).yml /etc/patroni/16-main.yml
systemctl enable patroni@16-main
systemctl restart patroni@16-main
until curl -sf 127.0.0.1:8008/health > /dev/null; do sleep 2; done
patronictl -c /etc/patroni/16-main.yml list
```

| Comando | O que faz |
|---|---|
| `apt install postgresql-16 patroni` | PostgreSQL 16 e Patroni 3.2 (que traz o `python3-etcd` e o `python3-psycopg2`). Sem `apt upgrade` |
| `pg_dropcluster 16 main --stop` | O pacote cria e liga um banco padrão (`16/main`). Quem cria e liga o banco é o **Patroni**, então esse sai. O `\|\| true` deixa rodar o script de novo sem erro |
| `ln -sf ... /etc/patroni/16-main.yml` | O serviço `patroni@16-main` do Ubuntu lê esse arquivo e roda como o usuário `postgres` |
| `restart patroni@16-main` | O Patroni sobe, vê que não há líder no etcd, pega a liderança, roda o `initdb` e liga o PostgreSQL como primário |
| `until curl ... :8008/health` | A API do Patroni responde 200 quando o PostgreSQL está rodando |

O script do `db1` termina com o `patronictl list`: `db1` como **Leader**, `running`.

### 3.5 Conferir o etcd e o Patroni

```sh
incus exec db1 -- etcdctl member list -w table
incus exec db1 -- etcdctl --endpoints=10.10.10.31:2379,10.10.10.11:2379 endpoint status -w table
incus exec db1 -- journalctl -u patroni@16-main -n 20 --no-pager
incus exec db1 -- patronictl -c /etc/patroni/16-main.yml list
```

- `member list`: `db1` e `lb1`, `started`.
- `endpoint status`: versão 3.4.30 e um deles com `IS LEADER true`. É o líder **do etcd**,
  que não tem nada a ver com o líder do banco.
- `journalctl`: `initialized a new cluster` e depois `no action. I am (db1), the leader with
  the lock` a cada 10 s.

Ver o que o Patroni gravou no etcd (é por aqui que os `db` combinam quem manda):

```sh
incus exec db1 -- etcdctl get --prefix /service/tgb --keys-only
incus exec db1 -- etcdctl get /service/tgb/leader
```

O `leader` vale `db1`. Se o Patroni do `db1` parar de renovar essa chave, ela expira e
quem estiver vivo a pega.

### 3.6 Banco do placar e porta 5000

Criar o usuário, o banco e a tabela ([config/db/placar.sql](../config/db/placar.sql)):

```sh
incus exec db1 -- su postgres -c "psql -f /srv/db/placar.sql"
```

```sql
CREATE USER app PASSWORD 'app';
CREATE DATABASE placar OWNER app;
\c placar
CREATE TABLE cliques (
    id     serial PRIMARY KEY,
    quando timestamptz DEFAULT now(),
    app    text,
    banco  text
);
ALTER TABLE cliques OWNER TO app;
```

`su postgres` porque o `pg_hba` libera a conexão local para o usuário do sistema com o
mesmo nome (`peer`): o `postgres` do Linux entra como `postgres` do banco, sem senha.

O bloco novo do [haproxy.cfg](../config/lb/haproxy.cfg) (já copiado em 3.1):

```
listen postgres
    mode tcp
    option tcplog
    bind *:5000
    option httpchk OPTIONS /primary
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server db1 10.10.10.31:5432 maxconn 100 check port 8008
    server db2 10.10.10.32:5432 maxconn 100 check port 8008
```

| Linha | O que faz |
|---|---|
| `mode tcp` | O HAProxy só repassa os bytes; não entende o protocolo do PostgreSQL |
| `option httpchk OPTIONS /primary` + `check port 8008` | A verificação não é na 5432: é na **API do Patroni**. Só o primário responde 200 em `/primary`; a réplica responde 503 e fica "DOWN" de propósito |
| `on-marked-down shutdown-sessions` | Quando o primário muda, derruba as conexões abertas com o antigo |
| `server db2 ...` | Já fica no arquivo: até o `db2` existir, aparece DOWN no 8404 |

Aplicar nos **dois** `lb` (o arquivo é o mesmo) e testar:

```sh
incus exec lb1 -- haproxy -c -f /etc/haproxy/haproxy.cfg
incus exec lb1 -- systemctl reload haproxy
incus exec lb2 -- systemctl reload haproxy
incus exec db1 -- psql "host=10.10.10.10 port=5000 dbname=placar user=app password=app" -c "SELECT inet_server_addr(), count(*) FROM cliques"
```

O `psql` atravessa o IP virtual e o HAProxy e chega no `db1` (`10.10.10.31`, `0`
cliques). No <http://localhost:8404> aparece o bloco `postgres` com `db1` UP e `db2` DOWN.

### 3.7 Placar no app

O app precisa da biblioteca do PostgreSQL. Um de cada vez, para o site não cair:

```sh
incus exec app1 -- apt install -y python3-psycopg2
incus exec app1 -- systemctl restart app
incus exec app2 -- apt install -y python3-psycopg2
incus exec app2 -- systemctl restart app
```

(404 no `apt install`: rode antes o `apt update` no contêiner. O `setup.sh` do app já
inclui o `python3-psycopg2`, para a reprodução do zero.)

O [main.py](../config/app/main.py) ganhou duas rotas e uma função:

| Parte | O que faz |
|---|---|
| `sql()` | Abre uma conexão **nova** em `10.10.10.10:5000` a cada comando e fecha no fim. Depois de um failover, a próxima já cai no primário novo |
| `POST /clique` | Grava uma linha: hora, **qual app** atendeu e **qual banco** gravou (`inet_server_addr()`, o IP do PostgreSQL que respondeu) |
| `GET /api/estado` | Total de cliques, o banco que respondeu e os 10 últimos cliques. Se o banco não responde, devolve **503** |
| `/health` | **Não** consulta o banco, de propósito: se o banco cair, o HAProxy não pode tirar os dois apps, senão o site inteiro some em vez de mostrar "banco indisponível" |

A [página](../config/app/templates/index.html) mantém o cartão da fase 1 e acrescenta o
total, o botão **Clicar**, a caixa **automático** (um clique a cada 0,5 s) e a lista dos
últimos cliques (`hora app → banco`). Um JavaScript de poucas linhas chama
`/api/estado` **a cada segundo**; com o banco fora, a linha de status fica vermelha.

No Windows, <http://localhost:8080>: marcar **automático** e ver o total subir, com
`app1`/`app2` alternando e sempre `→ db1`.

> O `<h1 class="hostname">` continua igual, então o laço `grep ">app"` das fases 1 e 2
> segue funcionando.

### 3.8 `db2`

```sh
incus init images:ubuntu/24.04 db2 --profile default --profile db --profile etcd
incus config device override db2 eth0 ipv4.address=10.10.10.32
incus start db2
incus exec db2 -- bash /srv/etcd/setup.sh
incus exec db2 -- bash /srv/db/setup.sh
```

Os mesmos scripts do `db1`, mas o `hostname` agora é `db2`:

| Etapa | O que acontece no `db2` |
|---|---|
| etcd | O `etcd-db2` tem `existing`: o script faz o `member add db2` (o `db1` e o `lb1` aprovam) e sobe o etcd, que **entra** no cluster. Agora são 3 votos, e a maioria continua 2 |
| Patroni | Vê que já existe líder (`db1`), roda `pg_basebackup` para **copiar os dados** do primário e sobe como réplica. O script espera essa cópia terminar |

O `db2` não é clone do `db1`: um clone levaria junto a identidade do `db1` (membro do
etcd, dados do primário). Mesmo assim ele divide com os outros os blocos da imagem do
Ubuntu (btrfs); só os pacotes do banco são dele.

Conferir:

```sh
incus exec db1 -- patronictl -c /etc/patroni/16-main.yml list
incus exec db1 -- etcdctl --endpoints=10.10.10.31:2379,10.10.10.32:2379,10.10.10.11:2379 endpoint status -w table
incus exec db2 -- su postgres -c "psql -d placar -c 'SELECT count(*) FROM cliques'"
incus profile show etcd
```

- `patronictl list`: `db1` **Leader**, `db2` **Replica** `streaming`, `Lag in MB` 0.
- `endpoint status`: os 3 etcd.
- O `count(*)` no `db2` dá o mesmo total do placar: os cliques chegaram pela replicação.
- `profile show etcd`: `used_by` com `db1`, `db2` e `lb1` (os votantes).

### 3.9 Testes de failover do banco

Deixe o placar aberto no Windows com **automático** marcado.

| # | Teste | Comando | Esperado no placar |
|---|---|---|---|
| 1 | Troca planejada | `incus exec db1 -- patronictl -c /etc/patroni/16-main.yml switchover tgb --leader db1 --candidate db2 --force` | Um ou dois segundos vermelhos; depois `→ db2`. O `db1` vira réplica |
| 2 | Volta | o mesmo com `--leader db2 --candidate db1` | `→ db1` de novo |
| 3 | Primário derrubado | `incus stop db1 --force` | Vermelho por até ~30 s (o `ttl`); depois `→ db2` e o total **continua** de onde parou |
| 4 | Antigo primário volta | `incus start db1` | Nada no placar. `patronictl list`: `db1` volta como **Replica** (`pg_rewind`) |
| 5 | Réplica cai | `incus stop db2 --force` | Nada visível. Depois `incus start db2` |
| 6 | 3º voto cai | `incus stop lb1 --force` | O IP virtual vai para o `lb2` (fase 2) e o etcd fica com 2 de 3: o banco segue |

Durante cada teste, em outra janela:

```sh
watch -n1 'incus exec db2 -- patronictl -c /etc/patroni/16-main.yml list'
```

(No teste 3, rode o `patronictl` no `db2`, já que o `db1` está desligado.)

### 3.10 Snapshot da fase 3

```sh
for c in lb1 lb2 app1 app2 db1 db2; do incus snapshot create $c fase3; done
incus list
```

### 3.11 Evidências da fase 3

Em `evidencias/fase3/`:

| # | Comando | Mostra |
|---|---|---|
| 01 | `incus profile show db` e `incus profile show etcd` | limites do `db`; `used_by` do `etcd` = os 3 votantes |
| 02 | `incus list` | os 6 contêineres |
| 03 | `etcdctl member list -w table` + `endpoint status -w table` | os 3 membros do etcd e o líder deles |
| 04 | `patronictl list` | `db1` Leader, `db2` Replica |
| 05 | `etcdctl get /service/tgb/leader` | a "posse" do líder no etcd |
| 06 | navegador em `localhost:8404` | bloco `postgres`: só o primário UP |
| 07 | `incus exec db2 -- etcdctl member list -w table` | os 3 membros depois do `member add` |
| 08 | vídeo do placar durante o teste 3 | vermelho, depois `→ db2`, sem perder cliques |
| 09 | `patronictl list` depois do teste 4 | `db1` de volta como réplica |

## Fase 4: dados sintéticos e carga

A escrever. Planejamento: doc 04, seções 4.4.2 e 4.4.3.

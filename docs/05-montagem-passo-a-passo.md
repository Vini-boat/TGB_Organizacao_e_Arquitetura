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
└── lb/                                               /srv/lb   (lb1, lb2)
    ├── haproxy.cfg           # balanceador
    └── setup.sh              # instala o HAProxy, liga o haproxy.cfg da pasta e reinicia
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
- [ ] **2. Corrigir o `/srv/app/setup.sh`** na VM (`systemct` → `systemctl`), igual ao
  `config/app/setup.sh`.
- [ ] **3. Apagar a sobra do teste no Alpine:** `rm -rf /srv/app/.venv /srv/app/__pycache__`
  (o `.venv` tem 54 MB e aparece dentro dos contêineres).
- [ ] **4. Recriar os contêineres sem `apt upgrade`.** Perfis, rede e forward continuam;
  só os contêineres saem:
  ```sh
  incus delete app1 app2 lb1 --force
  ```
  E refazer 1.4 → 1.5 → 1.6 (o `incus init` usa a imagem já baixada, sem download). Testar
  com o laço do `curl` (1.6) e `localhost:8080` no Windows.
- [ ] **5. Print do "depois":** os mesmos comandos do item 1 →
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
- [ ] **9. Compactar o VDI e exportar um `.ova` novo** (guia 01, seção 1.9, "Compactar
  antes de exportar"). Apagar o `incus-host-fase1.ova` antigo (2 GB) só depois que o novo
  importar sem erro.
- [ ] **10. Commit** de `config/`, `docs/` e `evidencias/` (o `.ova` fica fora do git).

---

## Fase 2: balanceador redundante (`lb2` + keepalived)

A escrever. Configuração planejada: doc 03, seção 3.3 (keepalived).

## Fase 3: banco replicado (`db1`, `db2`)

A escrever. Configuração planejada: doc 03, seção 3.3 (etcd, Patroni + PostgreSQL).

## Fase 4: dados sintéticos e carga

A escrever. Planejamento: doc 04, seções 4.4.2 e 4.4.3.

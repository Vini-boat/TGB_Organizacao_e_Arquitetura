# 2. Paralelos entre a aula e o trabalho (LXC/LXD)

Este documento liga o conteúdo da aula **"Arquiteturas Virtualizadas"** (Organização e
Arquitetura de Computadores, Unisinos) ao estudo de caso do Trabalho GB (Assunto 3:
servidores com contêineres LXC/LXD).

Os números entre parênteses são as páginas do PDF da aula.

> O slide **"Trabalho GB"** (p. 57) só tem o título; os requisitos do trabalho não estão no PDF.

Ambiente de referência (ver [01-configuracao-ambiente.md](01-configuracao-ambiente.md)):

```
Windows (host físico)
 └── VirtualBox (hipervisor tipo 2, usa VT-x/AMD-V)
      └── VM Alpine "incus-host"                     ← virtualiza a ISA
           └── Incus → liblxc → núcleo do incus-host   ← virtualiza a ABI
                └── contêineres Ubuntu (lb1, app1, db1, ...)
```

---

## 2.1 O que é o LXC

O LXC (*Linux Containers*) é a camada mais baixa. Tem duas partes:

- a **`liblxc`**: biblioteca em C que pede ao núcleo do Linux para criar os **namespaces**
  e os **cgroups** (p. 47–48) e aplica as proteções **AppArmor** e **seccomp**;
- as ferramentas `lxc-create`, `lxc-start`, `lxc-attach` e outras.

Ele cria **contêineres de sistema**: o primeiro processo dentro do contêiner (PID 1) é o
sistema de inicialização da distribuição (`systemd` no Ubuntu, `openrc` no Alpine), e lá
dentro existem usuários, serviços, `apt` e SSH. O contêiner parece uma VM, mas é um grupo
de processos no núcleo do hospedeiro.

O Docker é o caso oposto: **contêiner de aplicação**, em geral um único processo, com
imagens em camadas (p. 49).

## 2.2 O que é o Incus (e o LXD)

O Incus é um **gerenciador** construído em cima da `liblxc`. Funciona como um serviço em
segundo plano (*daemon*, o `incusd`) com uma API REST. O comando `incus` é o cliente
dessa API. É o *fork* comunitário do **LXD**: mesma arquitetura e quase os mesmos
comandos (no LXD, o cliente se chama `lxc`, sem hífen, o que confunde com as ferramentas
`lxc-*` do LXC puro). O enunciado aceita os dois.

| Recurso do Incus | O que faz |
|---|---|
| Imagens (`images:ubuntu/24.04`) | Baixa e guarda sistemas prontos (seção 2.2.1) |
| Storage pools (btrfs, ZFS, LVM, `dir`) | Snapshots e clones com cópia na escrita |
| Redes (`incusbr0`) | Bridge com DHCP, DNS e NAT |
| Perfis | Configuração reutilizável |
| Limites (`limits.cpu`, `limits.memory`) | Interface simples para os cgroups |
| Clustering e `incus move` | Vários hosts e migração |
| VMs (`incus launch --vm`) | Usa **QEMU + KVM** (p. 33); precisa do pacote `incus-vm` e de `/dev/kvm` |

### Camadas, lado a lado com a pilha do Docker (p. 49)

```
Docker:  docker     → containerd   → runc   → núcleo (namespaces + cgroups)
Incus:   incus (CLI) → incusd       → liblxc → núcleo (namespaces + cgroups)
LXD:     lxc (CLI)   → lxd (daemon) → liblxc → núcleo (namespaces + cgroups)
```

O Incus e o Docker usam os **mesmos mecanismos do núcleo**. O que muda é o modelo de uso:
contêiner de sistema no Incus, contêiner de aplicação no Docker.

### Histórico (para a introdução)

| Ano | Fato |
|---|---|
| 2008 | O LXC fica pronto |
| 2013–2014 | O Docker usa o LXC como base e depois o troca pela `libcontainer` (origem do `runc`) |
| 2015 | A Canonical lança o LXD |
| 2023 | A Canonical tira o LXD do projeto linuxcontainers.org; a comunidade cria o fork **Incus** |
| 2024 | Incus 6.0, primeira versão LTS |
| 2026 | Incus 7.0 LTS (a usada no trabalho, pacote do Alpine 3.24) |

O slide 48 cita o **Incus** ("Docker e Incus usam os dois"): o trabalho usa exatamente
a ferramenta citada na aula.

### 2.2.1 Contêiner Ubuntu num host Alpine: como funciona

A VM é Alpine, mas os contêineres do estudo de caso são Ubuntu 24.04. **Não há ISO nem
instalação**:

1. `incus launch images:ubuntu/24.04 app1` baixa do servidor `images.linuxcontainers.org`
   uma **imagem de contêiner**: só o sistema de arquivos do Ubuntu (`root.squashfs`,
   ~142 MB; o do Alpine tem ~4 MB) mais um arquivo de metadados. Não tem núcleo nem
   carregador de boot.
2. A imagem fica em cache. Cada contêiner novo é um **clone CoW** dela no btrfs: o
   segundo, o terceiro e o sexto contêiner Ubuntu saem em segundos e quase sem disco.
3. Ao iniciar, o Incus cria os namespaces e cgroups e roda o `/sbin/init` do Ubuntu
   (o `systemd`) como PID 1 **dentro deles**, usando o **núcleo do Alpine**.

Do lado de dentro, é "um Ubuntu": `apt`, `systemd`, `/etc/os-release` do Ubuntu, os
pacotes `postgresql-16` e `patroni` do Ubuntu. O que não é do Ubuntu é o núcleo:

```
incus exec app1 -- cat /etc/os-release   # Ubuntu 24.04
incus exec app1 -- uname -r              # 6.18.x-virt  ← núcleo do Alpine
uname -r                                 # 6.18.x-virt  ← o mesmo, no incus-host
```

Funciona porque a interface entre o Ubuntu e o núcleo é a **ABI** do Linux (chamadas de
sistema), que é estável: binários do Ubuntu rodam em qualquer núcleo Linux recente. É a
demonstração mais direta do slide 16 (contêiner virtualiza a ABI, não a ISA) e da
limitação do slide 46: dá para trocar a distribuição, **não** o núcleo (nada de Windows
nem de módulo de núcleo próprio dentro do contêiner).


### 2.2.2 Por dentro: "jail" = namespaces + cgroups + restrições

**Jail** é o nome do FreeBSD (2000) para um ambiente isolado: um objeto único do núcleo
que prende um grupo de processos. O Linux **não tem uma "jail" pronta**. Ele tem peças
separadas, e o contêiner é a soma delas, montada pela `liblxc`:

| Peça | Pergunta que responde | Exemplo no `app1` |
|---|---|---|
| **Namespaces** | O que o processo **enxerga**? | só os próprios processos, a própria `eth0`, o próprio hostname |
| **Cgroups** | Quanto ele pode **consumir**? | 1 CPU, 256 MiB de memória |
| `pivot_root` | Qual é a **raiz** do sistema de arquivos? | o subvolume btrfs com o Ubuntu |
| Namespace `user` (mapa de IDs) | **Quem** ele é fora dali? | root dentro, UID 1000000 na VM |
| Capabilities + seccomp | O que ele pode **pedir** ao núcleo? | não carrega módulo, não muda o relógio da VM |

Histórico curto: `chroot` (Unix, 1979) → jails do FreeBSD (2000) → Zones do Solaris
(2004) → namespaces e cgroups no Linux (2002–2013) → LXC (2008) → Docker, LXD, Incus.

#### O que acontece num `incus start app1`

1. O `incusd` lê a configuração (perfis `default` + `app` + o que é do contêiner) e
   chama a `liblxc`.
2. A `liblxc` cria o primeiro processo com `clone()` e as flags `CLONE_NEWPID`,
   `CLONE_NEWNET`, `CLONE_NEWNS`, `CLONE_NEWUTS`, `CLONE_NEWIPC`, `CLONE_NEWUSER` e
   `CLONE_NEWCGROUP`: um namespace novo de cada tipo.
3. Escreve o mapa de IDs (`0 1000000 1000000000`): o root lá dentro é o UID 1000000 aqui
   fora.
4. Cria o **cgroup** do contêiner e grava nele os limites (`limits.memory=256MiB` vira
   `memory.max`).
5. Cria um par `veth`: uma ponta vai para o namespace de rede do contêiner com o nome
   `eth0`, a outra fica na `incusbr0`.
6. Monta a raiz (o subvolume btrfs), os disk devices (`/srv/app`), o `/proc`, o `/sys` e
   o `lxcfs` por cima de `/proc/meminfo` e `/proc/cpuinfo`, e troca a raiz (`pivot_root`).
7. Corta capabilities, aplica o filtro seccomp e executa o `/sbin/init`: o `systemd` do
   Ubuntu vira o PID 1 **dentro** dos namespaces.

Não existe "máquina" nenhuma: é um processo comum da VM, com uma visão restrita do sistema
e um limite de recursos.

#### Ver as peças no `incus-host`

Ferramentas: `apk add util-linux-misc` (traz o `lsns` e o `nsenter`).

```sh
PID=$(incus info app1 | awk '/^PID:/ {print $2}')   # o PID 1 do contêiner, visto da VM
grep -E '^(Name|Uid):' /proc/$PID/status           # systemd, com o UID 1000000
ls -l /proc/$PID/ns                                 # um link por namespace
lsns -p $PID                                        # os namespaces dele x os da VM
nsenter -t $PID -n ip -br a                         # entra SÓ no namespace de rede: vê a eth0 do app1
```

O `nsenter` mostra que "entrar no contêiner" é só **juntar-se aos namespaces** dele; o
`incus exec` faz isso (com todos os namespaces e o cgroup).

#### Cgroups: os limites em arquivos

Os cgroups são uma árvore de pastas em `/sys/fs/cgroup` (v2, ligado no guia 01 com
`rc_cgroup_mode="unified"`). Cada contêiner tem a sua pasta; o nome esperado é
`lxc.payload.<nome>`:

```sh
CG=$(find /sys/fs/cgroup -maxdepth 3 -type d -name 'lxc.payload.app1')
echo $CG
cat $CG/memory.max $CG/memory.current     # limite e uso de memória, em bytes
cat $CG/cpu.max $CG/cpuset.cpus.effective # limite de tempo de CPU e CPUs permitidas
cat $CG/pids.current                      # quantos processos existem lá dentro
```

| Configuração do Incus | Arquivo do cgroup | Efeito |
|---|---|---|
| `limits.memory=256MiB` | `memory.max` = `268435456` | acima disso, o núcleo recupera memória e, no limite, mata um processo (OOM) **só desse contêiner** |
| `limits.cpu=1` | `cpuset.cpus` | o contêiner só roda num núcleo |
| `limits.cpu.allowance=20ms/100ms` | `cpu.max` = `20000 100000` | 20 ms de CPU a cada 100 ms: o exemplo do slide 48 |
| `limits.cpu.allowance=50%` | `cpu.weight` | peso relativo, só vale quando há disputa |
| `limits.processes=200` | `pids.max` | barra *fork bombs* |
| `incus pause` | `cgroup.freeze` = `1` | congela todos os processos de uma vez (estado `FROZEN`) |

Teste ao vivo: `incus config set app1 limits.memory=128MiB` com o contêiner ligado e
`cat $CG/memory.max` de novo: o arquivo muda na hora, sem reiniciar nada. Dentro do
contêiner, `incus exec app1 -- free -m` mostra os 128 MiB graças ao `lxcfs`.

> O caminho exato da pasta depende de onde o OpenRC põe o `incusd` na árvore; por isso o
> `find`. Anotar o caminho real (doc 03, teste T9).
---

## 2.3 Paralelos slide a slide

| Slide (tema) | Paralelo com o trabalho |
|---|---|
| **Motivação / consolidação** (13) | Os 6 contêineres do estudo de caso (`lb1`, `lb2`, `app1`, `app2`, `db1`, `db2`) rodam numa única VM em vez de seis máquinas: consolidação com contêineres. |
| **Interfaces API/ABI/ISA** (16) | Os dois níveis existem no ambiente: a VM do VirtualBox virtualiza a **ISA**; os contêineres Incus virtualizam a **ABI** (chamadas de sistema do núcleo do `incus-host`). Prova direta: os contêineres são **Ubuntu** e rodam sobre o núcleo do **Alpine** (`uname -r` igual dentro e fora; seção 2.2.1). Vira um slide próprio (doc 04, 4.6.1). |
| **Tipos de VM** (17) | Contêiner = "VM de processo, com ressalvas". A ressalva no Incus: como é contêiner de sistema, tem `systemd` e parece uma VM inteira, mas continua sendo uma árvore de processos. |
| **Popek e Goldberg** (19) | Um contêiner **não é um VMM**. A *eficiência* é máxima (zero VM exits). A *equivalência* vale só no nível da ABI: não roda Windows nem outro núcleo. |
| **Tradução binária / paravirtualização / VT-x** (21–25) | O contêiner não precisa de nenhuma das três. Quem usa **VT-x/AMD-V** é o VirtualBox, para a VM `incus-host`; por isso o guia pede virtualização ativada na BIOS. |
| **Memória: GVA → GPA → HPA** (27–28) | Um processo dentro do contêiner tem a **mesma** tradução em dois níveis da VM (EPT/SLAT, usado pelo VirtualBox). O contêiner **não acrescenta** um terceiro nível. |
| **E/S: emulação / virtio** (29) | A VM do VirtualBox usa placa de rede e disco emulados (ou `virtio`, se configurado). Dentro dela, a rede do contêiner é só um par `veth` ligado à bridge, sem emulação. |
| **Hipervisor tipo 1 × tipo 2** (32) | O **VirtualBox é tipo 2**: roda como programa sobre o Windows. O slide 41 ("com Hyper-V ativo, o VirtualBox roda sobre o Hyper-V") aparece na prática: se a máquina tiver Hyper-V/VBS ligado, o VirtualBox mostra a **tartaruga verde** e fica mais lento (ver guia 01, seção 1.11). Sem permissão de administrador não dá para desligar, então o ambiente mostra o caso do slide. |
| **KVM e QEMU** (33–34) | `incus launch images:ubuntu/24.04 vm1 --vm` cria uma VM QEMU/KVM pelo **mesmo** Incus. Contraste: cada VM é um processo QEMU; os processos de um contêiner aparecem direto no `ps` do `incus-host` (ex.: o `uvicorn` do `app1`). |
| **Proxmox VE** (37) | O Proxmox usa o **LXC direto** (comando `pct`), não o Incus. Mesma `liblxc`, outro gerenciador. |
| **Composição de uma VM** (39) | Equivalentes no Incus: `.vbox` → `incus config show app1`; `.vdi` → subvolume btrfs no storage pool; `.ova` → `incus export app1` (tar.gz) ou `incus publish` (gera uma imagem). |
| **Snapshots e clones (CoW)** (40) | `incus snapshot create app1 antes`, `incus snapshot restore app1 antes`, `incus copy app1 app3`. O clone btrfs é instantâneo e compartilha os blocos com a origem (cópia na escrita), mas, diferente do clone **vinculado** do slide, não depende dela: o original pode ser apagado. Na outra camada, o `VBoxManage snapshot incus-host take` faz o mesmo para a VM inteira. |
| **Imagens em camadas** (49) | O Incus **não** usa overlay em camadas como o Docker: usa uma imagem base mais um clone CoW por contêiner (btrfs). Mesmo princípio (cópia na escrita), outra implementação. |
| **Redes virtuais** (41) | A `incusbr0` com NAT junta os modos "NAT" e "rede interna" do VirtualBox: os contêineres se falam e saem para a internet. O **proxy device** (`listen=tcp:0.0.0.0:8080`) é o encaminhamento de porta do slide (exemplo `ssh -p 2231`), e o próprio ambiente usa o encaminhamento do VirtualBox (`ssh -p 2222 aluno@localhost`): **duas camadas de port forwarding**, uma em cada nível. |
| **Migração ao vivo** (42) | O Incus faz `incus move` entre membros de um cluster. Para contêineres, a migração ao vivo depende do CRIU e é limitada; para VMs é mais madura. No trabalho, a **disponibilidade vem da redundância** (réplicas + balanceador), não da migração: duas estratégias para o mesmo objetivo. |
| **Virtualização aninhada** (43) | **Argumento para a escolha de contêineres.** O `incus-host` já é uma VM (L1). Uma VM Incus dentro dela seria L2: exigiria VT-x aninhado e `/dev/kvm`, e cada saída passaria pelo L0. Contêineres dispensam isso e têm custo quase nulo dentro da VM. |
| **Contêineres / VM × contêiner** (45–46) | A tabela de partida e tamanho pode virar **medição própria**: `time incus launch` × tempo de boot da VM no VirtualBox; `incus storage info default` / `btrfs subvolume list /var/lib/incus/storage-pools/default` × disco de 16 GB da VM. |
| **Namespaces** (47) | Cada linha da tabela pode ser demonstrada (seção 2.4). |
| **Cgroups** (48) | O exemplo do slide (`cpu.max 20000 100000`, `memory.max 512M`) é **exatamente** o que o Incus gera com os limites da seção 2.4. |
| **Graus de isolamento / Segurança** (50–52) | No Incus os contêineres são **sem privilégio** por padrão (namespace `user`: root dentro, usuário comum fora), com filtro **seccomp** (a defesa da linha "falha no núcleo" do slide 52). No Ubuntu o
Incus/LXD acrescenta o **AppArmor**; no núcleo do Alpine o AppArmor vem compilado mas
**desligado** (`CONFIG_LSM` sem `apparmor`), então aqui a proteção é namespace `user` +
seccomp + cgroups. Bom ponto para a apresentação: a segurança do contêiner depende do
núcleo do host, não da imagem. O ambiente ainda tem **defesa em profundidade**: uma fuga do contêiner atinge só a VM `incus-host`, não o Windows. |
| **Computação em nuvem** (53) | Um cluster Incus (ou LXD) é uma "nuvem privada" pequena; o cenário com balanceador é a versão em miniatura de um serviço web na nuvem. |

---

## 2.4 Comandos de demonstração

Executados no `incus-host`, com os contêineres do estudo de caso (Ubuntu) criados.

### Namespaces (p. 47)

| Comando | Namespace | O que mostra |
|---|---|---|
| `incus exec app1 -- ps -ef \| head -3` | PID | `systemd` com PID 1 |
| `incus exec app1 -- hostname` | UTS | hostname próprio |
| `incus exec app1 -- ip -br a` | net | interface e IP próprios |
| `incus exec app1 -- cat /proc/self/uid_map` | user | `0 1000000 1000000000`: o root do contêiner é o UID 1000000 no host |
| `ps -ef \| grep uvicorn` (no host) | — | os processos do contêiner são processos comuns do host |
| `incus exec app1 -- uname -r` e `uname -r` (no host) | — | o **mesmo núcleo** (o do Alpine) num contêiner Ubuntu (2.2.1) |

### Cgroups (p. 48)

```bash
incus config set app1 limits.cpu.allowance 20ms/100ms
incus config set app1 limits.memory 512MiB
cat /sys/fs/cgroup/lxc.payload.app1/cpu.max /sys/fs/cgroup/lxc.payload.app1/memory.max
```

> `limits.cpu.allowance 20%` é um limite *flexível* (peso). O formato `20ms/100ms` é que
> gera o `cpu.max 20000 100000` do slide.

### Cópia na escrita (p. 40 e 49)

```bash
time incus copy app1 app3
btrfs subvolume list /var/lib/incus/storage-pools/default
```

O clone ocupa quase nada até ser modificado.

---

## 2.5 Fio condutor sugerido para a apresentação

1. **Duas camadas, dois níveis de virtualização:** VM (ISA, VirtualBox tipo 2 com VT-x) e
   contêiner (ABI, namespaces + cgroups).
2. **LXC é o mecanismo, Incus (fork do LXD) é o gerenciador.** Comparar com runc/Docker e com Proxmox/`pct`.
3. **Por que contêiner dentro de VM:** evita virtualização aninhada, parte em
   milissegundos, usa clones CoW.
4. **Disponibilidade:** redundância com balanceador em vez de migração ao vivo.
5. **Segurança:** núcleo compartilhado (ponto fraco) compensado por contêiner sem
   privilégio, seccomp e a VM como segunda barreira (AppArmor desligado no núcleo do
   Alpine: a proteção depende do host, seção 2.3).

> Os números de partida e espaço usados nos slides devem vir de **medições próprias**
> (o aviso de [referencias.md](referencias.md) também vale aqui).

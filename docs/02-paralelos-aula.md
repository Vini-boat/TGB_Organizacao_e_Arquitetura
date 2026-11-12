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
      └── VM Ubuntu "lxd-host"                       ← virtualiza a ISA
           └── LXD → liblxc → núcleo do lxd-host     ← virtualiza a ABI
                └── contêineres (web1, web2, lb, ...)
```

---

## 2.1 O que é o LXC

O LXC (*Linux Containers*) é a camada mais baixa. Tem duas partes:

- a **`liblxc`**: biblioteca em C que pede ao núcleo do Linux para criar os **namespaces**
  e os **cgroups** (p. 47–48) e aplica as proteções **AppArmor** e **seccomp**;
- as ferramentas `lxc-create`, `lxc-start`, `lxc-attach` e outras.

Ele cria **contêineres de sistema**: o primeiro processo dentro do contêiner (PID 1) é o
`systemd`, e lá dentro existem usuários, serviços, `apt` e SSH. O contêiner parece uma VM,
mas é um grupo de processos no núcleo do hospedeiro.

O Docker é o caso oposto: **contêiner de aplicação**, em geral um único processo, com
imagens em camadas (p. 49).

## 2.2 O que é o LXD

O LXD é um **gerenciador** construído em cima da `liblxc`. Funciona como um serviço em
segundo plano (*daemon*) com uma API REST. O comando `lxc` (sem hífen) é o cliente
dessa API.

| Recurso do LXD | O que faz |
|---|---|
| Imagens (`ubuntu:24.04`) | Baixa e guarda sistemas prontos |
| Storage pools (ZFS/btrfs) | Snapshots e clones com cópia na escrita |
| Redes (`lxdbr0`) | Bridge com DHCP, DNS e NAT |
| Perfis | Configuração reutilizável |
| Limites (`limits.cpu`, `limits.memory`) | Interface simples para os cgroups |
| Clustering e `lxc move` | Vários hosts e migração |
| VMs (`lxc launch --vm`) | Usa **QEMU + KVM** (p. 33) |

### Camadas, lado a lado com a pilha do Docker (p. 49)

```
Docker:  docker     → containerd   → runc   → núcleo (namespaces + cgroups)
LXD:     lxc (CLI)  → lxd (daemon) → liblxc → núcleo (namespaces + cgroups)
```

O LXD e o Docker usam os **mesmos mecanismos do núcleo**. O que muda é o modelo de uso:
contêiner de sistema no LXD, contêiner de aplicação no Docker.

### Histórico (para a introdução)

| Ano | Fato |
|---|---|
| 2008 | O LXC fica pronto |
| 2013–2014 | O Docker usa o LXC como base e depois o troca pela `libcontainer` (origem do `runc`) |
| 2015 | A Canonical lança o LXD |
| 2023 | A Canonical tira o LXD do projeto linuxcontainers.org; a comunidade cria o fork **Incus** |

O slide 48 cita o **Incus** ("Docker e Incus usam os dois"): na apresentação, explicar
que **Incus ≈ LXD**.

---

## 2.3 Paralelos slide a slide

| Slide (tema) | Paralelo com o trabalho |
|---|---|
| **Motivação / consolidação** (13) | `web1`, `web2` e `lb` rodam numa única VM em vez de três máquinas: consolidação com contêineres. |
| **Interfaces API/ABI/ISA** (16) | Os dois níveis existem no ambiente: a VM do VirtualBox virtualiza a **ISA**; os contêineres LXD virtualizam a **ABI** (chamadas de sistema do núcleo do `lxd-host`). |
| **Tipos de VM** (17) | Contêiner = "VM de processo, com ressalvas". A ressalva no LXD: como é contêiner de sistema, tem `systemd` e parece uma VM inteira, mas continua sendo uma árvore de processos. |
| **Popek e Goldberg** (19) | Um contêiner **não é um VMM**. A *eficiência* é máxima (zero VM exits). A *equivalência* vale só no nível da ABI: não roda Windows nem outro núcleo. |
| **Tradução binária / paravirtualização / VT-x** (21–25) | O contêiner não precisa de nenhuma das três. Quem usa **VT-x/AMD-V** é o VirtualBox, para a VM `lxd-host`; por isso o guia pede virtualização ativada na BIOS. |
| **Memória: GVA → GPA → HPA** (27–28) | Um processo dentro do contêiner tem a **mesma** tradução em dois níveis da VM (EPT/SLAT, usado pelo VirtualBox). O contêiner **não acrescenta** um terceiro nível. |
| **E/S: emulação / virtio** (29) | A VM do VirtualBox usa placa de rede e disco emulados (ou `virtio`, se configurado). Dentro dela, a rede do contêiner é só um par `veth` ligado à bridge, sem emulação. |
| **Hipervisor tipo 1 × tipo 2** (32) | O **VirtualBox é tipo 2**: roda como programa sobre o Windows. O slide 41 ("com Hyper-V ativo, o VirtualBox roda sobre o Hyper-V") aparece na prática: se a máquina tiver Hyper-V/VBS ligado, o VirtualBox mostra a **tartaruga verde** e fica mais lento (ver guia 01, seção 1.10). Sem permissão de administrador não dá para desligar, então o ambiente mostra o caso do slide. |
| **KVM e QEMU** (33–34) | `lxc launch ubuntu:24.04 vm1 --vm` cria uma VM QEMU/KVM pelo **mesmo** LXD. Contraste: cada VM é um processo QEMU; os processos de um contêiner aparecem direto no `ps` do `lxd-host` (ex.: o `nginx` do `web1`). |
| **Proxmox VE** (37) | O Proxmox usa o **LXC direto** (comando `pct`), não o LXD. Mesma `liblxc`, outro gerenciador. |
| **Composição de uma VM** (39) | Equivalentes no LXD: `.vbox` → `lxc config show web1`; `.vdi` → dataset ZFS no storage pool; `.ova` → `lxc export web1` (tar.gz) ou `lxc publish` (gera uma imagem). |
| **Snapshots e clones (CoW)** (40) | `lxc snapshot web1 antes`, `lxc restore web1 antes`, `lxc copy web1 web3`. O clone ZFS é instantâneo e **vinculado**, como no slide. Na outra camada, o `VBoxManage snapshot lxd-host take` faz o mesmo para a VM inteira. |
| **Imagens em camadas** (49) | O LXD **não** usa overlay em camadas como o Docker: usa uma imagem base mais um clone CoW por contêiner (ZFS). Mesmo princípio (cópia na escrita), outra implementação. |
| **Redes virtuais** (41) | A `lxdbr0` com NAT junta os modos "NAT" e "rede interna" do VirtualBox: os contêineres se falam e saem para a internet. O **proxy device** (`listen=tcp:0.0.0.0:8080`) é o encaminhamento de porta do slide (exemplo `ssh -p 2231`), e o próprio ambiente usa o encaminhamento do VirtualBox (`ssh -p 2222 aluno@localhost`): **duas camadas de port forwarding**, uma em cada nível. |
| **Migração ao vivo** (42) | O LXD faz `lxc move` entre membros de um cluster. Para contêineres, a migração ao vivo depende do CRIU e é limitada; para VMs é mais madura. No trabalho, a **disponibilidade vem da redundância** (réplicas + balanceador), não da migração: duas estratégias para o mesmo objetivo. |
| **Virtualização aninhada** (43) | **Argumento para a escolha de contêineres.** O `lxd-host` já é uma VM (L1). Uma VM LXD dentro dela seria L2: exigiria VT-x aninhado e `/dev/kvm`, e cada saída passaria pelo L0. Contêineres dispensam isso e têm custo quase nulo dentro da VM. |
| **Contêineres / VM × contêiner** (45–46) | A tabela de partida e tamanho pode virar **medição própria**: `time lxc launch` × tempo de boot da VM no VirtualBox; `lxc storage info default` / `zfs list` × disco de 30 GB da VM. |
| **Namespaces** (47) | Cada linha da tabela pode ser demonstrada (seção 2.4). |
| **Cgroups** (48) | O exemplo do slide (`cpu.max 20000 100000`, `memory.max 512M`) é **exatamente** o que o LXD gera com os limites da seção 2.4. |
| **Graus de isolamento / Segurança** (50–52) | No LXD os contêineres são **sem privilégio** por padrão (namespace `user`: root dentro, usuário comum fora), com **AppArmor + seccomp** (a defesa da linha "falha no núcleo" do slide 52). O ambiente ainda tem **defesa em profundidade**: uma fuga do contêiner atinge só a VM `lxd-host`, não o Windows. |
| **Computação em nuvem** (53) | Um cluster LXD (ou Incus) é uma "nuvem privada" pequena; o cenário com balanceador é a versão em miniatura de um serviço web na nuvem. |

---

## 2.4 Comandos de demonstração

Executados no `lxd-host`, com os contêineres do estudo de caso criados.

### Namespaces (p. 47)

| Comando | Namespace | O que mostra |
|---|---|---|
| `lxc exec web1 -- ps -ef \| head -3` | PID | `systemd` com PID 1 |
| `lxc exec web1 -- hostname` | UTS | hostname próprio |
| `lxc exec web1 -- ip -br a` | net | interface e IP próprios |
| `lxc exec web1 -- cat /proc/self/uid_map` | user | típico `0 1000000 1000000000`: o root do contêiner é o UID 1000000 no host |
| `ps -ef \| grep nginx` (no host) | — | os processos do contêiner são processos comuns do host |

### Cgroups (p. 48)

```bash
lxc config set web1 limits.cpu.allowance 20ms/100ms
lxc config set web1 limits.memory 512MiB
cat /sys/fs/cgroup/lxc.payload.web1/cpu.max /sys/fs/cgroup/lxc.payload.web1/memory.max
```

> `limits.cpu.allowance 20%` é um limite *flexível* (peso). O formato `20ms/100ms` é que
> gera o `cpu.max 20000 100000` do slide.

### Cópia na escrita (p. 40 e 49)

```bash
time lxc copy web1 web3
zfs list -t all
```

O clone ocupa quase nada até ser modificado.

---

## 2.5 Fio condutor sugerido para a apresentação

1. **Duas camadas, dois níveis de virtualização:** VM (ISA, VirtualBox tipo 2 com VT-x) e
   contêiner (ABI, namespaces + cgroups).
2. **LXC é o mecanismo, LXD é o gerenciador.** Comparar com runc/Docker e com Proxmox/`pct`.
3. **Por que contêiner dentro de VM:** evita virtualização aninhada, parte em
   milissegundos, usa clones CoW.
4. **Disponibilidade:** redundância com balanceador em vez de migração ao vivo.
5. **Segurança:** núcleo compartilhado (ponto fraco) compensado por contêiner sem
   privilégio, seccomp/AppArmor e a VM como segunda barreira.

> Os números de partida e espaço usados nos slides devem vir de **medições próprias**
> (o aviso de [referencias.md](referencias.md) também vale aqui).

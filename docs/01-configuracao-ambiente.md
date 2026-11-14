# 1. Configuração do ambiente (Windows + VirtualBox + Alpine + Incus, sem administrador)

Este guia prepara o ambiente usado no estudo de caso do Trabalho GB
(Assunto 3: servidores com contêineres LXC/LXD).

- **Sem administrador no Windows**: a VM é criada no **VirtualBox** já instalado, com
  `VBoxManage`, e a rede usa **só NAT com encaminhamento de portas**.
- **VM leve**: **Alpine Linux** (ISO de 67 MB, ~150 MB de RAM em uso, sobe em segundos).
  O Ubuntu Server era pesado demais, principalmente com o Hyper-V ligado (modo lesma).
- **Incus** no lugar do LXD: é o *fork* comunitário do LXD, mantido pela equipe do
  linuxcontainers.org (a mesma do LXC). O enunciado da aula aceita os dois
  ("LXD ou Incus instalado numa VM Linux"). Os comandos são quase iguais: `lxc ...`
  vira `incus ...`.

Arquitetura final do ambiente:

```
Windows (host físico, usuário comum)
 └── VirtualBox (hipervisor tipo 2, já instalado)
      └── VM Alpine Linux 3.24 "incus-host"
           ├── eth0 → NAT (10.0.2.15): internet + portas encaminhadas do Windows
           └── Incus 7.0 LTS (gerenciador de contêineres, usa a liblxc)
                └── incusbr0 (10.x.x.x) → contêineres Linux (web1, web2, lb, ...)

Windows ──► localhost:2222 ──(port forwarding do VirtualBox)──► VM:22   (SSH)
Windows ──► localhost:8080 ──(port forwarding do VirtualBox)──► VM:8080 (cenário)
```

> O caminho principal é rodar **comando a comando**, entendendo cada um (é o que vai
> para o passo a passo da entrega). Os mesmos comandos estão juntos em
> [`scripts/criar-vm.ps1`](../scripts/criar-vm.ps1) e
> [`scripts/preparar-incus.sh`](../scripts/preparar-incus.sh), só para refazer o
> ambiente rápido depois (outro PC, VM apagada).

---

## 1.0 O que funciona sem administrador

| Item | Sem admin? | Observação |
|---|---|---|
| Usar o VirtualBox já instalado | ✅ | Os drivers foram instalados junto com ele |
| Criar e rodar VMs | ✅ | Os arquivos ficam em `%USERPROFILE%\VirtualBox VMs` |
| Rede **NAT** com encaminhamento de portas acima de 1024 | ✅ | É o que este guia usa |
| Exportar/importar a VM (`.ova`) | ✅ | Leva o ambiente pronto para outro PC (seção 1.9) |
| Criar ou alterar rede **Host-only** | ⚠️ | Mexe em adaptadores de rede do Windows; provavelmente exige admin. **Não usamos** |
| Rede em modo **Bridge** | ⚠️ | Depende do driver e da rede da instituição. **Não usamos** |
| Desligar Hyper-V / Integridade da memória | ❌ | Se a VM ficar lenta por causa disso, veja a seção 1.11 |
| Liberar porta no Firewall do Windows | ❌ | Por isso as portas são abertas só em `127.0.0.1`, que não aciona o firewall |

> Dentro da VM somos `root` normalmente: a falta de admin vale só para o **Windows**.

---

## 1.1 Requisitos

| Item | Mínimo | Recomendado |
|---|---|---|
| VirtualBox | 7.x (já instalado) | — |
| RAM do computador | 4 GB | 8 GB |
| Espaço livre (na pasta do usuário) | 10 GB | 20 GB |
| Virtualização na BIOS/UEFI | Ativada (Intel VT-x / AMD-V) | — |

Contêineres **não** precisam de virtualização aninhada: eles usam o núcleo da VM, sem
hipervisor. Só a VM em si precisa de VT-x/AMD-V.

Para conferir (sem admin): **Gerenciador de Tarefas → Desempenho → CPU** e procure
**"Virtualização: Habilitado"**.

---

## 1.2 Baixar o Alpine

Arquivo: **`alpine-virt-3.24.4-x86_64.iso`** (67 MB, versão estável mais recente em
novembro de 2026). A variante **virt** tem um núcleo enxuto, feito para VMs.

```powershell
cd "$env:USERPROFILE\Downloads"
curl.exe -L -C - -O https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/x86_64/alpine-virt-3.24.4-x86_64.iso
(Get-FileHash .\alpine-virt-3.24.4-x86_64.iso).Hash
```

O SHA-256 deve ser (fonte: o arquivo `.sha256` ao lado da ISO):

```
157D353F8E54252CAD2D9812A0D56BB7FA2231FC154A110E1D180D7480EF8B4F
```

> Use `curl.exe` (com `.exe`): no PowerShell antigo, `curl` sozinho é outro comando.
> Se sair uma versão 3.24.x mais nova, troque o número nos comandos e confira o hash
> em <https://alpinelinux.org/downloads/>.

---

## 1.3 Criar a VM (pela linha de comando)

Tudo é feito com o `VBoxManage.exe`, que vem com o VirtualBox. **Ler e executar** de
`C:\Program Files\Oracle\VirtualBox\` não precisa de admin. Use o **PowerShell** comum.

```powershell
$vbm  = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
$base = "$env:USERPROFILE\VirtualBox VMs"
$iso  = "$env:USERPROFILE\Downloads\alpine-virt-3.24.4-x86_64.iso"
$vm   = "incus-host"
& $vbm --version
```

```powershell
# 1. Cria e registra a VM
& $vbm createvm --name $vm --ostype Linux_64 --basefolder "$base" --register

# 2. Hardware: 2 GB de RAM e 2 CPUs (subir para 3072 se o cenário completo do doc 03 apertar)
& $vbm modifyvm $vm --memory 2048 --cpus 2 --ioapic on `
    --graphicscontroller vmsvga --vram 16 --audio-enabled off `
    --boot1 dvd --boot2 disk --boot3 none --boot4 none

# 3. Rede: só NAT na placa 1
& $vbm modifyvm $vm --nic1 nat

# 4. Disco de 16 GB (dinâmico: começa com poucas centenas de MB) e a ISO
& $vbm storagectl $vm --name SATA --add sata --controller IntelAhci --portcount 2
& $vbm createmedium disk --filename "$base\$vm\$vm.vdi" --size 16384 --format VDI
& $vbm storageattach $vm --storagectl SATA --port 0 --device 0 --type hdd --medium "$base\$vm\$vm.vdi"
& $vbm storageattach $vm --storagectl SATA --port 1 --device 0 --type dvddrive --medium "$iso"
```

| Comando | O que faz |
|---|---|
| `createvm --register` | Cria a pasta e o arquivo `.vbox` e registra a VM |
| `modifyvm --memory/--cpus` | RAM em MB e número de vCPUs; `--ioapic on` é necessário para mais de 1 CPU |
| `modifyvm --nic1 nat` | Placa 1 em modo NAT: internet sem mexer na rede do Windows |
| `storagectl` / `createmedium` / `storageattach` | Controladora SATA, disco `.vdi` dinâmico e a ISO no drive de DVD |

> - `Linux_64` é o tipo "Other Linux (64-bit)". Se a sua versão tiver um tipo próprio
>   para Alpine, ele aparece em `& $vbm list ostypes | Select-String -Context 0,1 Alpine`.
> - Para recomeçar do zero: `& $vbm unregistervm $vm --delete`.

### Encaminhamento de portas

Com a VM **desligada**:

```powershell
& $vbm modifyvm $vm --nat-pf1 "ssh,tcp,127.0.0.1,2222,,22"
& $vbm modifyvm $vm --nat-pf1 "cenario,tcp,127.0.0.1,8080,,8080"
& $vbm modifyvm $vm --nat-pf1 "stats,tcp,127.0.0.1,8404,,8404"
& $vbm modifyvm $vm --nat-pf1 "painel,tcp,127.0.0.1,9000,,9000"
& $vbm modifyvm $vm --nat-pf1 "terminal,tcp,127.0.0.1,7681,,7681"
```

| Nome | Windows | VM | Uso |
|---|---|---|---|
| `ssh` | `127.0.0.1:2222` | `22` | Terminal da VM pelo Windows |
| `cenario` | `127.0.0.1:8080` | `8080` | Site do estudo de caso (balanceador) |
| `stats` | `127.0.0.1:8404` | `8404` | Estatísticas do HAProxy |
| `painel` | `127.0.0.1:9000` | `9000` | Apresentação (doc 04) |
| `terminal` | `127.0.0.1:7681` | `7681` | Terminal projetado, ttyd (doc 04) |

> - **IP `127.0.0.1` no Windows:** a porta só abre para o próprio Windows; o Firewall não
>   pede autorização (o que exigiria admin).
> - Com a VM **ligada**, use `controlvm`:
>   `& $vbm controlvm $vm natpf1 "teste,tcp,127.0.0.1,8081,,8081"`.

### Ligar para instalar

```powershell
& $vbm startvm $vm --type gui
```

---

## 1.4 Instalar o Alpine no disco

A ISO inicia um Alpine que roda **da memória**. Entre como `root` (sem senha) e rode o
instalador:

```sh
setup-alpine
```

| Pergunta | Resposta |
|---|---|
| Keyboard layout / variant | `br` / `br` (o `br` básico já é o ABNT2, com Ç; as outras variantes são `br-nativo`, `br-nodeadkeys`, `br-thinkpad`, `br-dvorak`...) |
| Hostname | `incus-host` |
| Interface | `eth0`, `dhcp`, sem configuração manual (`n`) |
| Root password | defina e anote |
| Timezone | `America/Sao_Paulo` |
| Proxy | `none` (ou o proxy da instituição, se houver) |
| NTP client | `chrony` |
| APK mirror | `f` (testa e escolhe o mais rápido). Se houver a opção `c`, use-a também para **habilitar o repositório community** |
| Setup a user | `aluno` (nome completo à vontade, senha anotada) |
| SSH server | `openssh` |
| Allow root ssh login | `prohibit-password` (o padrão) |
| Disk & install | `sda`, modo **`sys`**, confirmar apagar o disco (`y`) |

> **Cuidado na pergunta do disco:** responder `none` (ou não escolher o `sda`) deixa o
> Alpine **só na memória** (modo *diskless*): tudo some ao desligar. Os modos `data` e
> `lvm` também não servem aqui. Tem que ser **`sda` + `sys`**.
>
> Para conferir antes de desligar: `df -h /` deve mostrar `/dev/sda3` (e não `tmpfs`).
> Se errou, não precisa refazer tudo: `setup-disk -m sys /dev/sda` instala no disco
> aproveitando o que já foi configurado.

Quando terminar, desligue, tire a ISO e ligue sem janela:

```sh
poweroff
```

```powershell
& $vbm storageattach $vm --storagectl SATA --port 1 --device 0 --type dvddrive --medium emptydrive
& $vbm startvm $vm --type headless
```

> Com Hyper-V ligado no Windows (modo lesma, tartaruga verde), o Alpine ainda instala em
> poucos minutos: quase não há o que copiar.

---

## 1.5 Acessar a VM pelo Windows (SSH)

```powershell
ssh -p 2222 aluno@localhost
```

> **Por que `localhost:2222` e não o IP da VM?** O IP da VM (`10.0.2.15`) existe só
> dentro do NAT do VirtualBox: o Windows não alcança esse endereço. Para ter um IP da VM
> acessível pelo Windows seria preciso uma rede Host-only (exige admin para criar o
> adaptador) ou Bridge (a VM vira um PC na rede da instituição). A porta `2222` também
> não conflita com um servidor SSH que o Windows já tenha na porta `22`. Se a `2222`
> estiver ocupada, `Get-NetTCPConnection -LocalPort 2222` mostra; troque a regra para
> outra porta (ex.: `2223`).

Atalho opcional: crie (ou edite) o arquivo `%USERPROFILE%\.ssh\config` com

```
Host incus
    HostName 127.0.0.1
    Port 2222
    User aluno
```

e daí em diante basta `ssh incus` (vale também para `scp arquivo incus:`).

Vire `root` com `su -` (senha do root). A partir daqui, os comandos são **dentro da VM,
como root**.

> Para não precisar de senha: no Windows, `ssh-keygen` (Enter em tudo) e depois
> `type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh -p 2222 aluno@localhost "mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys"`.

---

## 1.6 Instalar o Incus

O roteiro está em [`scripts/preparar-incus.sh`](../scripts/preparar-incus.sh)
(copie com `scp -P 2222 scripts/preparar-incus.sh aluno@localhost:` e rode como root).
Passo a passo:

```sh
# 1. Repositório community (onde está o Incus): descomenta a linha .../community
sed -i 's|^#\(.*/v3\.24/community\)$|\1|' /etc/apk/repositories
apk update && apk upgrade

# 2. Pacotes: servidor, cliente, lxcfs e o necessário para o storage btrfs
apk add incus incus-client lxcfs btrfs-progs losetup bash curl

# 3. cgroups v2 puro (padrão do Alpine atual; garante que está assim)
grep -q '^rc_cgroup_mode="unified"' /etc/rc.conf || echo 'rc_cgroup_mode="unified"' >> /etc/rc.conf

# 4. Serviços no boot e já agora
rc-update add cgroups && rc-update add dbus && rc-update add lxcfs && rc-update add incusd
rc-service cgroups start; rc-service dbus start; rc-service lxcfs start; rc-service incusd start

# 5. Permite ao usuário comum usar o incus sem ser root
addgroup aluno incus
```

| Peça | Função |
|---|---|
| `incus` | o servidor `incusd` (API REST, banco de dados, imagens, redes, storage) |
| `incus-client` | o comando `incus` (cliente da API) |
| `lxc` (dependência) | a **liblxc**, que de fato cria namespaces e cgroups de cada contêiner |
| `lxcfs` | faz `free`, `top` e `/proc/cpuinfo` dentro do contêiner mostrarem os **limites** dele, não os da VM |
| `/etc/subuid`, `/etc/subgid` | o pacote reserva `root:1000000:1000000000`: o root do contêiner é o UID 1000000 na VM (contêiner **sem privilégio**) |
| grupo `incus` | dono do socket `/var/lib/incus/unix.socket` (definido em `/etc/conf.d/incusd`) |

Confira:

```sh
incus version
rc-service incusd status
```

> Depois de entrar no grupo, o `aluno` precisa sair e entrar no SSH de novo.

---

## 1.7 Inicializar o Incus (`incus admin init`)

```sh
incus admin init
```

| Pergunta | Resposta |
|---|---|
| Would you like to use clustering? | `no` |
| Do you want to configure a new storage pool? | `yes` |
| Name of the new storage pool | `default` |
| Name of the storage backend to use | `btrfs` |
| Create a new BTRFS pool? | `yes` |
| Would you like to use an existing empty block device? | `no` |
| Size in GiB of the new loop device | `10GiB` |
| Would you like to create a new local network bridge? | `yes` |
| What should the new bridge be called? | `incusbr0` |
| What IPv4 address should be used? | `auto` |
| Would you like to NAT IPv4 traffic on your bridge? | `yes` |
| What IPv6 address should be used? | `none` |
| Would you like the server to be available over the network? | `no` |
| Would you like stale cached images to be updated automatically? | `yes` |
| Would you like a YAML "init" preseed to be printed? | `no` |

Atalho sem perguntas: `incus admin init --auto --storage-backend btrfs --storage-create-loop 10`
(o `--auto` também cria a `incusbr0`).

> **Por que btrfs e não ZFS?** O ZFS no Alpine exige o módulo `zfs-virt`, compilado à
> parte do núcleo. O btrfs já vem no núcleo e também tem **snapshots e cópias
> instantâneas (copy-on-write)**, que é o que o trabalho explora. Se o btrfs falhar, use
> `dir` (funciona sempre, mas copia arquivo por arquivo).

| Recurso | Ver com | Função |
|---|---|---|
| Storage pool `default` (btrfs) | `incus storage list` | sistemas de arquivos dos contêineres, com snapshots CoW |
| Bridge `incusbr0` | `incus network list` | switch virtual com DHCP/DNS (dnsmasq) e NAT |
| Perfil `default` | `incus profile show default` | disco raiz + placa na `incusbr0` para todo contêiner novo |

---

## 1.8 Testar: o ambiente pedido na aula de 12/nov

O slide "Assunto 3" pede: Incus inicializado, **dois contêineres web com páginas
diferentes** e **um terceiro para o balanceador**. Este teste usa a imagem do Alpine
(~4 MB, sobe em segundos); os contêineres do estudo de caso (doc 03) usam
`images:ubuntu/24.04` (~142 MB, baixada uma vez só). Como um contêiner Ubuntu roda sobre
o núcleo do Alpine: doc 02, seção 2.2.1.

```sh
# Dois servidores web, cada um com uma página diferente
for n in 1 2; do
  incus launch images:alpine/3.24 web$n
  incus exec web$n -- apk add --no-cache nginx
  incus exec web$n -- sh -c "mkdir -p /var/www/html && echo '<h1>Servidor web$n</h1>' > /var/www/html/index.html"
  incus exec web$n -- sh -c 'printf "server {\n  listen 80 default_server;\n  root /var/www/html;\n}\n" > /etc/nginx/http.d/default.conf'
  incus exec web$n -- rc-update add nginx
  incus exec web$n -- rc-service nginx start
done

# Limites (cgroups) para aparecerem no incus info
incus config set web1 limits.cpu=1 limits.memory=128MiB

# Balanceador (o HAProxy é configurado no estudo de caso, doc 03)
incus launch images:alpine/3.24 lb
incus exec lb -- apk add --no-cache haproxy
incus config device add lb http proxy listen=tcp:0.0.0.0:8080 connect=tcp:127.0.0.1:80
```

### Evidências (prints com o comando e a saída)

| Comando | Deve mostrar |
|---|---|
| `incus list` | três contêineres `RUNNING`, cada um com IPv4 `10.x.x.x` |
| `curl http://<IP do web1>` e `curl http://<IP do web2>` | `Servidor web1` / `Servidor web2` |
| `incus info web1` | estado, PID, limites e uso de CPU/memória |
| `uname -r` na VM e `incus exec web1 -- uname -r` | **o mesmo núcleo** (contêiner não tem núcleo próprio) |

> O DNS da `incusbr0` também resolve os nomes: `incus exec lb -- wget -qO- http://web1.incus`.

### Snapshot da VM (item 4 do checklist)

```sh
poweroff
```

```powershell
& $vbm snapshot $vm take incus-pronto --description "Incus + web1, web2, lb"
```

Voltar: `& $vbm snapshot $vm restore incus-pronto` (VM desligada). É o mesmo conceito do
`incus snapshot create` (copy-on-write), uma camada abaixo.

---

## 1.9 Portabilidade: levar a VM pronta

A VM inteira cabe num `.ova` de poucas centenas de MB, que importa em qualquer
VirtualBox (sem admin):

```powershell
& $vbm export $vm -o "$env:USERPROFILE\Desktop\incus-host.ova"
# no outro PC:
& $vbm import incus-host.ova
```

As regras de encaminhamento vão junto. Foi assim que o cluster da aula chegou a cada
PC ("uma VM é um conjunto de arquivos").

### Compactar antes de exportar

O VDI dinâmico **só cresce**: o que é apagado dentro da VM continua ocupando espaço no
Windows. Por isso o `.ova` da fase 1 ficou com 2 GB (doc 04, 4.6.2). Para encolher, é
preciso deixar o espaço livre **zerado** e depois mandar o VirtualBox descartar os blocos
zerados. São duas camadas, como sempre:

**Na VM** (como root), depois de apagar o que não serve:

```sh
fstrim -v /var/lib/incus/storage-pools/default
dd if=/dev/zero of=/zero bs=1M; sync; rm /zero
poweroff
```

| Comando | O que faz |
|---|---|
| `fstrim` no pool | O pool btrfs mora num **arquivo** (`/var/lib/incus/disks/default.img`, *loop*). O btrfs libera os blocos dos contêineres apagados, mas o arquivo continua grande; o `fstrim` avisa o *loop*, que abre "buracos" no arquivo (arquivo esparso) e devolve o espaço ao ext4 da VM |
| `dd ... of=/zero` | Enche o espaço livre do disco da VM com zeros até acabar (o erro `No space left on device` no fim é **esperado**); o `rm` apaga o arquivo. Os blocos livres ficam zerados |
| `poweroff` | A compactação só funciona com a VM desligada |

**No Windows** (PowerShell, com `$vbm` e `$vm` da seção 1.3):

```powershell
& $vbm snapshot $vm list
& $vbm modifymedium disk "$env:USERPROFILE\VirtualBox VMs\$vm\$vm.vdi" --compact
Get-Item "$env:USERPROFILE\VirtualBox VMs\$vm\$vm.vdi" | Select-Object Name, Length
& $vbm export $vm -o "$env:USERPROFILE\Desktop\incus-host-fase1.ova"
```

| Comando | O que faz |
|---|---|
| `snapshot list` | Se a VM tiver snapshots do VirtualBox, o estado atual está num disco **diferencial** e compactar o `.vdi` base adianta pouco. Nesse caso, apague os snapshots antigos antes (`& $vbm snapshot $vm delete <nome>`), sabendo que não dá para voltar a eles |
| `modifymedium --compact` | Remove do `.vdi` os blocos que estão inteiros zerados: o arquivo encolhe |
| `Get-Item ... Length` | Tamanho do `.vdi` depois (anote antes e depois: é evidência da lição 4.6.2) |
| `export` | Gera o `.ova`, que também comprime os discos |

---

## 1.10 Comandos do dia a dia

### Windows (PowerShell, com `$vbm` e `$vm` da seção 1.3)

| Comando | O que faz |
|---|---|
| `& $vbm startvm $vm --type headless` | Liga a VM sem janela |
| `ssh -p 2222 aluno@localhost` | Abre o terminal da VM |
| `& $vbm controlvm $vm acpipowerbutton` | Desliga de forma limpa |
| `& $vbm controlvm $vm savestate` | Salva o estado e fecha; `startvm` retoma de onde parou |
| `& $vbm snapshot $vm take <nome>` / `restore <nome>` / `list` | Snapshots da VM |
| `& $vbm export $vm -o arquivo.ova` | Exporta a VM |

### Na VM (Alpine, OpenRC)

| Comando | O que faz |
|---|---|
| `poweroff` / `reboot` | Desliga / reinicia |
| `apk add <pacote>` / `apk search <termo>` | Instala / procura pacotes |
| `rc-service <serviço> start\|stop\|status` | Controla um serviço (equivale ao `systemctl`) |
| `rc-update add <serviço>` | Liga o serviço no boot |
| `df -h` / `free -m` | Disco / memória |

### Incus

| Comando | O que faz |
|---|---|
| `incus launch images:alpine/3.24 <nome>` | Cria e inicia um contêiner (`images:debian/12` para Debian) |
| `incus list` | Contêineres, estado e IPs |
| `incus exec <nome> -- sh` | Terminal no contêiner (`bash` em imagens Debian) |
| `incus stop` / `start` / `restart` / `pause <nome>` | Ciclo de vida |
| `incus delete <nome> --force` | Apaga |
| `incus info <nome>` | Detalhes e uso de recursos |
| `incus snapshot create <nome> <snap>` / `incus snapshot restore <nome> <snap>` | Snapshots do contêiner |
| `incus copy <origem> <novo>` | Clona (instantâneo no btrfs) |

> **LXD × Incus:** `lxc launch` → `incus launch`; `lxd init` → `incus admin init`;
> `lxdbr0` → `incusbr0`; `lxc snapshot c s` → `incus snapshot create c s`. O comando
> `lxc` do LXD não tem relação com as ferramentas `lxc-*` do LXC puro; no Incus essa
> confusão some.

---

## 1.11 Problemas comuns

| Problema | Solução |
|---|---|
| `VT-x is not available` / `AMD-V is disabled` | Virtualização desligada na BIOS: só quem administra a máquina resolve |
| VM lenta, **tartaruga verde** na barra da janela | VirtualBox sobre o Hyper-V (WSL2, Integridade da memória, VBS). Desligar exige admin. Com o Alpine continua usável; ligue com `--type headless` |
| `ssh: ... port 2222: Connection refused` | VM desligada (`& $vbm list runningvms`), ainda iniciando, ou falta a regra `ssh`. Na janela da VM: `rc-service sshd status` |
| `apk add incus` diz que o pacote não existe | Repositório community desligado: confira `/etc/apk/repositories` e rode `apk update` |
| `incus: permission denied` no socket | Entre no grupo (`addgroup aluno incus`), saia e entre de novo; ou use `su -` |
| `incusd` não sobe | `tail /var/log/incus/incusd.log` (ou `rc-service incusd start` no terminal); confira `rc-service cgroups status` e `rc-service dbus status` |
| `losetup: unrecognized option: find` no `incus admin init` | O `losetup` do BusyBox é limitado: `apk add losetup` (versão do util-linux) e rode o `incus admin init` de novo |
| `btrfs` falha no `incus admin init` | `modprobe btrfs`; se não houver o módulo, use o backend `dir` |
| Contêiner sem IPv4 | Aguarde e rode `incus list` de novo; confira `rc-service incusd status` e `incus network show incusbr0` |
| Contêiner sem internet | Teste a VM (`wget -qO- https://alpinelinux.org >/dev/null && echo ok`); o `ping` pode falhar no NAT do VirtualBox (ICMP limitado) |
| Página não abre no navegador do Windows | Confira a regra de encaminhamento, `incus config device show lb` e se o serviço está rodando no contêiner |
| A VM volta para o instalador | A ISO ainda está no drive: `storageattach ... --medium emptydrive` |
| Porta do Windows em uso | Troque a porta do hospedeiro na regra (ex.: `18080`) |

---

## 1.12 Validação nas fontes oficiais

Conferido em 14/11/2026.

| O que foi validado | Fonte |
|---|---|
| Alpine 3.24.4 é a estável atual; nome, endereço e SHA-256 da ISO `virt` (70.254.592 bytes) | <https://alpinelinux.org/downloads/> e o arquivo `.sha256` em `dl-cdn.alpinelinux.org` |
| Incus 7.0.1 (LTS) no repositório **community** do 3.24; subpacotes `incus-client`, `incus-openrc`, `incus-vm`; dependências (`lxc>=6`, `dnsmasq`, `nftables`, `shadow-subids`...) | aports, branch `3.24-stable`: `community/incus/APKBUILD` |
| O pacote cria os grupos `incus`/`incus-user` e grava `root:1000000:1000000000` em `/etc/subuid` e `/etc/subgid` | aports: `community/incus/incus.pre-install` |
| Serviço `incusd` (OpenRC) depende de `net`, `cgroups`, `dbus` e usa `lxcfs`; socket do grupo `incus` | aports: `community/incus/incusd.initd`, `incusd.confd` |
| Perguntas do `incus admin init` (texto de cada uma) | Incus v7.0.1: `cmd/incus/admin_init_interactive.go` |
| O núcleo `virt` do Alpine tem btrfs como módulo (`CONFIG_BTRFS_FS=m`) e não tem ZFS | aports `3.24-stable`: `main/linux-lts/virt.x86_64.config` |
| Imagens `alpine:3.24`, `debian:bookworm` e `debian:trixie` (amd64) existem no servidor `images:` | <https://images.linuxcontainers.org/streams/v1/index.json> |
| Comandos do `VBoxManage` e encaminhamento de portas | código-fonte do VirtualBox, `doc/manual` (validado na versão anterior do guia) |

**Ainda não conferido** (só o teste responde; lista completa em
[03-estudo-de-caso.md, seção 3.9](03-estudo-de-caso.md#39-testes-que-só-o-ambiente-responde)):
as telas exatas do `setup-alpine` 3.24 (principalmente a opção do repositório community)
e a **ordem** das perguntas do `incus admin init` (o texto foi conferido; a ordem da
tabela segue a do LXD).

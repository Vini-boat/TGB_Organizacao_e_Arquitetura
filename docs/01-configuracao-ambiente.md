# 1. Configuração do ambiente (Windows + VirtualBox + LXD, sem administrador)

Este guia prepara o ambiente usado no estudo de caso do Trabalho GB
(Assunto 3: servidores com contêineres LXC/LXD).

A máquina usada **não dá permissão de administrador**, mas já tem o **VirtualBox
instalado**. Por isso a VM Linux é criada no VirtualBox e a rede usa **só o modo NAT
com encaminhamento de portas**, que não precisa de admin.

Arquitetura final do ambiente:

```
Windows (host físico, usuário comum)
 └── VirtualBox (hipervisor tipo 2, já instalado)
      └── VM Ubuntu Server 24.04 "lxd-host"
           ├── enp0s3 → NAT (10.0.2.15): internet + portas encaminhadas do Windows
           └── LXD 6 LTS (gerenciador de contêineres, usa a liblxc)
                └── lxdbr0 (10.x.x.x) → contêineres Linux (lb1, lb2, app1, ...)

Windows ──► localhost:2222 ──(port forwarding do VirtualBox)──► VM:22   (SSH)
Windows ──► localhost:8080 ──(port forwarding do VirtualBox)──► VM:8080 (cenário)
```

> **Por que não Multipass nem Docker?** Os dois precisam de administrador para instalar
> (e para ligar a Plataforma de Máquina Virtual). O Docker, além disso, trocaria o tema:
> é contêiner de **aplicação**, e o trabalho é sobre contêiner de **sistema** (LXC/LXD).

---

## 1.0 O que funciona sem administrador

| Item | Sem admin? | Observação |
|---|---|---|
| Usar o VirtualBox já instalado | ✅ | Os drivers foram instalados junto com ele |
| Criar e rodar VMs | ✅ | Os arquivos ficam em `%USERPROFILE%\VirtualBox VMs` |
| Rede **NAT** com encaminhamento de portas acima de 1024 | ✅ | É o que este guia usa |
| Criar ou alterar rede **Host-only** | ⚠️ | Mexe em adaptadores de rede do Windows; provavelmente exige admin. **Não usamos** |
| Rede em modo **Bridge** | ⚠️ | Depende do driver e da rede da instituição. **Não usamos** |
| Desligar Hyper-V / Integridade da memória | ❌ | Se a VM ficar lenta por causa disso, veja a seção 1.10 |
| Liberar porta no Firewall do Windows | ❌ | Por isso as portas são abertas só em `127.0.0.1`, que não aciona o firewall |

> **Cuidado com computadores de laboratório:** confira se a pasta do usuário é
> apagada ao sair (perfil temporário) e se há espaço nela (cota). A VM ocupa até ~30 GB.
> Se o perfil for apagado, guarde a pasta da VM num disco externo ou em outra unidade.

---

## 1.1 Requisitos

| Item | Mínimo | Recomendado |
|---|---|---|
| VirtualBox | 7.x (já instalado) | — |
| RAM do computador | 8 GB | 16 GB |
| Espaço livre (na pasta do usuário) | 35 GB | 50 GB |
| Virtualização na BIOS/UEFI | Ativada (Intel VT-x / AMD-V) | — |

Para conferir (sem admin): **Gerenciador de Tarefas → Desempenho → CPU** e procure
**"Virtualização: Habilitado"**. Se estiver desabilitado, só quem administra a máquina
consegue ativar na BIOS.

Confira a versão do VirtualBox em **Ajuda → Sobre o VirtualBox**.

---

## 1.2 Baixar o Ubuntu Server

**Ubuntu Server 24.04 LTS** (arquivo `.iso`, ~2,6 GB):
<https://ubuntu.com/download/server> → *Download Ubuntu Server 24.04 LTS*.

Baixar arquivo não precisa de admin. Salve numa pasta sua (ex.: `Downloads`).

---

## 1.3 Criar a VM (pela linha de comando)

Tudo é feito com o `VBoxManage.exe`, a ferramenta de linha de comando que vem com o
VirtualBox. Ele fica na pasta de instalação, normalmente `C:\Program Files\Oracle\VirtualBox\`,
e **ler e executar** de lá não precisa de admin. Use o **PowerShell** (não o Prompt de
Comando), sem "Executar como administrador".

### Preparar as variáveis

Ajuste o caminho da ISO para o nome exato do arquivo baixado:

```powershell
$vbm  = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
$base = "$env:USERPROFILE\VirtualBox VMs"
$iso  = "$env:USERPROFILE\Downloads\ubuntu-24.04.3-live-server-amd64.iso"
& $vbm --version
```

> As variáveis valem só para a janela atual do PowerShell. Se abrir outra, rode o bloco
> de novo.

### Criar e configurar

```powershell
# 1. Cria e registra a VM (só o arquivo de configuração, ainda sem disco)
& $vbm createvm --name lxd-host --ostype Ubuntu_64 --basefolder "$base" --register

# 2. Hardware: 4 GB de RAM (3072 se o computador tiver 8 GB), 2 CPUs, vídeo e boot
& $vbm modifyvm lxd-host --memory 4096 --cpus 2 --ioapic on `
    --graphicscontroller vmsvga --vram 16 --audio-enabled off `
    --boot1 dvd --boot2 disk --boot3 none --boot4 none

# 3. Rede: só NAT na placa 1
& $vbm modifyvm lxd-host --nic1 nat

# 4. Controladora SATA, disco de 30 GB (alocação dinâmica) e a ISO no drive de DVD
& $vbm storagectl lxd-host --name SATA --add sata --controller IntelAhci --portcount 2
& $vbm createmedium disk --filename "$base\lxd-host\lxd-host.vdi" --size 30720 --format VDI
& $vbm storageattach lxd-host --storagectl SATA --port 0 --device 0 --type hdd --medium "$base\lxd-host\lxd-host.vdi"
& $vbm storageattach lxd-host --storagectl SATA --port 1 --device 0 --type dvddrive --medium "$iso"
```

| Comando | O que faz |
|---|---|
| `createvm --register` | Cria a pasta `lxd-host` e o arquivo `.vbox` e registra a VM (ela aparece na janela do VirtualBox) |
| `modifyvm --memory/--cpus` | RAM em MB e número de vCPUs; `--ioapic on` é necessário para mais de 1 CPU |
| `modifyvm --nic1 nat` | Placa 1 em modo NAT: internet sem mexer na rede do Windows |
| `storagectl` | Cria a controladora de disco SATA (AHCI) |
| `createmedium disk` | Cria o disco virtual `.vdi` de 30 GB, que só ocupa o que for usado |
| `storageattach` | Liga o disco (porta 0) e a ISO do Ubuntu (porta 1) à controladora |

> - `Ubuntu_64` existe em todas as versões 7.x. Para ver os tipos disponíveis:
>   `& $vbm list ostypes | Select-String Ubuntu`.
> - Se algum comando der `Access denied`, troque `$base` por uma pasta onde seu usuário
>   possa gravar.
> - Para recomeçar do zero: `& $vbm unregistervm lxd-host --delete`.

### Encaminhamento de portas

As regras ligam portas do Windows a portas da VM (a VM precisa estar **desligada**):

```powershell
& $vbm modifyvm lxd-host --nat-pf1 "ssh,tcp,127.0.0.1,2222,,22"
& $vbm modifyvm lxd-host --nat-pf1 "cenario,tcp,127.0.0.1,8080,,8080"
& $vbm modifyvm lxd-host --nat-pf1 "stats,tcp,127.0.0.1,8404,,8404"
& $vbm modifyvm lxd-host --nat-pf1 "painel,tcp,127.0.0.1,9000,,9000"
& $vbm modifyvm lxd-host --nat-pf1 "terminal,tcp,127.0.0.1,7681,,7681"
```

Formato: `"nome,protocolo,IP-do-Windows,porta-do-Windows,IP-da-VM,porta-da-VM"`
(IP da VM vazio = o IP que o NAT der a ela).

| Nome | Windows | VM | Uso |
|---|---|---|---|
| `ssh` | `127.0.0.1:2222` | `22` | Terminal da VM pelo Windows |
| `cenario` | `127.0.0.1:8080` | `8080` | Site do estudo de caso (doc 03) |
| `stats` | `127.0.0.1:8404` | `8404` | Estatísticas do HAProxy (doc 03) |
| `painel` | `127.0.0.1:9000` | `9000` | Apresentação (doc 04) |
| `terminal` | `127.0.0.1:7681` | `7681` | Terminal projetado, ttyd (doc 04) |

> - **IP `127.0.0.1` no Windows:** a porta só é aberta para o próprio Windows. Assim
>   ninguém na rede acessa a VM e o Firewall do Windows não pede autorização (o que
>   exigiria admin).
> - Portas **acima de 1024** não precisam de privilégio.
> - O Windows sempre acessa a VM por `localhost`: o endereço **não muda** ao reiniciar.
> - Com a VM **ligada**, use `controlvm` no lugar de `modifyvm`:
>   `& $vbm controlvm lxd-host natpf1 "teste,tcp,127.0.0.1,8081,,8081"`.
> - Apagar uma regra: `& $vbm modifyvm lxd-host --nat-pf1 delete ssh`.

Confira tudo:

```powershell
& $vbm showvminfo lxd-host --machinereadable | Select-String "memory|cpus|nic1|Forwarding|SATA"
```

### Ligar para instalar

O instalador do Ubuntu é interativo, então esta vez a VM abre **com janela**:

```powershell
& $vbm startvm lxd-host --type gui
```

---

## 1.4 Instalar o Ubuntu Server

Inicie a VM (**Iniciar**). Use as setas e o Enter para navegar no instalador.

| Tela do instalador | O que escolher |
|---|---|
| *Try or Install Ubuntu Server* | Enter |
| Language | `English` (os comandos e mensagens de erro ficam mais fáceis de pesquisar) |
| Installer update available | `Continue without updating` |
| Keyboard configuration | Layout: `Portuguese (Brazil)` (teclado ABNT2) |
| Type of installation | `Ubuntu Server` |
| Network configuration | Deve aparecer **uma** interface, `enp0s3`, com IP `10.0.2.15`. Done |
| Proxy configuration | Deixar vazio (se a rede da instituição exigir proxy, coloque-o aqui). Done |
| Ubuntu archive mirror | Aguardar o teste do espelho. Done |
| Guided storage configuration | `Use an entire disk`, e **desmarcar** `Set up this disk as an LVM group` (assim todo o disco fica disponível) |
| Storage configuration | Done → Continue |
| Profile configuration | Nome: o seu · Server name: `lxd-host` · Username: ex. `aluno` · Senha (anote!) |
| Upgrade to Ubuntu Pro | `Skip for now` |
| SSH configuration | ✅ **Install OpenSSH server** |
| Featured server snaps | Não marcar nada. Done |

Aguarde a instalação. Quando aparecer **Reboot Now**, selecione e pressione Enter.
Se aparecer *"Please remove the installation medium"*, apenas pressione Enter
(o VirtualBox ejeta a ISO sozinho).

Faça login com o usuário e a senha criados para conferir, desligue com `sudo poweroff`
e, no PowerShell, tire a ISO do drive para a VM não tentar instalar de novo:

```powershell
& $vbm storageattach lxd-host --storagectl SATA --port 1 --device 0 --type dvddrive --medium emptydrive
```

Daqui em diante, ligue a VM **sem janela** e use só o SSH:

```powershell
& $vbm startvm lxd-host --type headless
```

> Dentro da VM, você é administrador (`sudo`) normalmente: a falta de admin vale só
> para o **Windows**.

---

## 1.5 Acessar a VM pelo Windows (SSH)

Usar SSH é bem mais prático que a janela do VirtualBox: dá para copiar e colar
comandos. O cliente `ssh` já vem no Windows 10/11 e não precisa de admin.

No **PowerShell** ou no **Terminal** do Windows:

```powershell
ssh -p 2222 aluno@localhost
```

Na primeira vez, digite `yes` para aceitar a chave e depois a senha.

> Logo depois de ligar, o SSH pode recusar a conexão por alguns segundos, enquanto a VM
> termina de iniciar. Espere um pouco e tente de novo.

A partir daqui, **todos os comandos são executados dentro da VM** (o prompt fica
`aluno@lxd-host:~$`).

Atualize o sistema:

```bash
sudo apt update && sudo apt upgrade -y
```

---

## 1.6 Instalar o LXD

```bash
sudo snap install lxd --channel=6/stable
```

> Sem o `--channel`, o snap também instala a LTS atual (track `6`). O parâmetro só
> deixa a versão explícita. Se aparecer `snap "lxd" is already installed`, confira
> a versão com `snap list lxd` (a coluna *Tracking* deve mostrar `6/stable`). Se
> não mostrar, rode `sudo snap refresh lxd --channel=6/stable`.

Dê permissão ao seu usuário para usar o LXD sem `sudo`
(comando da documentação oficial):

```bash
getent group lxd | grep -qwF "$USER" || sudo usermod -aG lxd "$USER"
newgrp lxd
```

Confira:

```bash
lxd --version
```

---

## 1.7 Inicializar o LXD (`lxd init`)

```bash
lxd init
```

As perguntas aparecem nesta ordem (LXD 6). Respostas sugeridas:

| # | Pergunta | Resposta |
|---|---|---|
| 1 | Would you like to use LXD clustering? | `no` (Enter) |
| 2 | Do you want to configure a new storage pool? | `yes` (Enter) |
| 3 | Name of the new storage pool | `default` (Enter) |
| 4 | Name of the storage backend to use (...) | `zfs` |
| 5 | Create a new ZFS pool? | `yes` (Enter) |
| 6 | Would you like to use an existing empty block device (e.g. a disk or partition)? | `no` (Enter) |
| 7 | Size in GiB of the new loop device (1GiB minimum) | `15GiB` |
| 8 | Would you like to create a new local network bridge? | `yes` (Enter) |
| 9 | What should the new bridge be called? | `lxdbr0` (Enter) |
| 10 | What IPv4 address should be used? | `auto` (Enter) |
| 11 | Would you like LXD to NAT IPv4 traffic on your bridge? | `yes` (Enter) |
| 12 | What IPv6 address should be used? | `none` |
| 13 | Would you like the LXD server to be available over the network? | `no` (Enter) |
| 14 | Would you like stale cached images to be updated automatically? | `yes` (Enter) |
| 15 | Would you like a YAML "lxd init" preseed to be printed? | `no` (Enter) |

> - Se aparecer *"Would you like to create an initial LXD UI access link?"*, responda `no`.
> - Se `zfs` **não** aparecer na lista de backends da pergunta 4, use `btrfs`
>   (também suporta snapshots e cópias rápidas).
> - Com `auto`, o LXD sorteia uma sub-rede `10.x.y.0/24` que não colida com a `10.0.2.0/24`
>   do NAT do VirtualBox. Confira com `lxc network show lxdbr0`.

> **Atalho (sem perguntas)**, com os mesmos parâmetros principais:
> ```bash
> lxd init --auto --storage-backend zfs --storage-create-loop 15
> ```

### O que foi criado

| Recurso | Comando para ver | Função |
|---|---|---|
| Storage pool `default` (ZFS) | `lxc storage list` | Onde ficam os sistemas de arquivos dos contêineres; o ZFS permite snapshots e cópias rápidas |
| Bridge `lxdbr0` | `lxc network list` | Switch virtual com DHCP/DNS/NAT que liga os contêineres entre si e à internet |
| Perfil `default` | `lxc profile show default` | Configuração aplicada a todo contêiner novo (disco raiz + placa de rede na `lxdbr0`) |

---

## 1.8 Testar o ambiente

1. Criar um contêiner de teste:

   ```bash
   lxc launch ubuntu:24.04 teste
   ```

2. Listar os contêineres (o `teste` deve estar `RUNNING` e com um IPv4 `10.x.x.x`):

   ```bash
   lxc list
   ```

3. Testar a internet de dentro do contêiner:

   ```bash
   lxc exec teste -- apt update
   ```

   > O `ping` pode falhar mesmo com a internet funcionando: o NAT do VirtualBox tem
   > suporte limitado a ICMP. Prefira testar com `apt update` ou `curl`.

4. Abrir um terminal dentro do contêiner (saia com `exit`):

   ```bash
   lxc exec teste -- bash
   ```

5. Testar o acesso pelo **navegador do Windows** (simula o que será feito com o
   balanceador no estudo de caso):

   ```bash
   lxc exec teste -- apt install -y nginx
   lxc config device add teste http proxy listen=tcp:0.0.0.0:8080 connect=tcp:127.0.0.1:80
   ```

   O caminho completo é: `localhost:8080` no Windows → encaminhamento do VirtualBox →
   porta `8080` da VM → *proxy device* do LXD → porta `80` do contêiner.

   No Windows, abra <http://localhost:8080>. Deve aparecer a página
   **"Welcome to nginx!"**.

6. Apagar o contêiner de teste:

   ```bash
   lxc delete teste --force
   ```

Se todos os passos funcionaram, o ambiente está pronto para o estudo de caso.

### Snapshot de segurança da VM

Com tudo funcionando, desligue a VM (`sudo poweroff`) e, no PowerShell, tire um
snapshot:

```powershell
& $vbm snapshot lxd-host take lxd-pronto --description "LXD instalado e testado"
```

Se algo quebrar mais tarde, com a VM desligada:

```powershell
& $vbm snapshot lxd-host restore lxd-pronto
```

> É o mesmo conceito do `lxc snapshot` (slide 40), só que na camada de baixo: aqui o
> snapshot é da VM inteira; no LXD, de cada contêiner.

---

## 1.9 Comandos do dia a dia

### Windows (PowerShell, com `$vbm` da seção 1.3)

| Comando | O que faz |
|---|---|
| `& $vbm startvm lxd-host --type headless` | Liga a VM sem janela |
| `ssh -p 2222 aluno@localhost` | Abre o terminal da VM |
| `& $vbm list runningvms` | Lista as VMs ligadas |
| `& $vbm controlvm lxd-host acpipowerbutton` | Desliga a VM de forma limpa (como apertar o botão) |
| `& $vbm controlvm lxd-host poweroff` | Desliga na hora (como tirar da tomada; só se travar) |
| `& $vbm snapshot lxd-host take <nome>` | Snapshot da VM |
| `& $vbm snapshot lxd-host list` | Lista os snapshots |
| `& $vbm snapshot lxd-host restore <nome>` | Volta a VM para um snapshot (VM desligada) |
| `& $vbm showvminfo lxd-host --machinereadable \| Select-String Forwarding` | Mostra as regras de encaminhamento |
| `& $vbm unregistervm lxd-host --delete` | Apaga a VM e o disco (recomeçar do zero) |

### Na VM (Ubuntu)

| Comando | O que faz |
|---|---|
| `sudo poweroff` | Desliga a VM |
| `sudo reboot` | Reinicia a VM |
| `df -h` / `free -h` | Espaço em disco / memória livre |

### LXD (dentro da VM)

| Comando | O que faz |
|---|---|
| `lxc launch ubuntu:24.04 <nome>` | Cria e inicia um contêiner |
| `lxc list` | Lista contêineres, estado e IPs |
| `lxc exec <nome> -- bash` | Abre um terminal no contêiner |
| `lxc stop <nome>` / `lxc start <nome>` | Para / inicia o contêiner |
| `lxc delete <nome> --force` | Apaga o contêiner |
| `lxc info <nome>` | Detalhes e uso de recursos |
| `lxc image list` | Imagens já baixadas (cache local) |

> **Atenção:** o comando `lxc` (sem hífen) é o **cliente do LXD**. Ele não é o
> mesmo que as ferramentas antigas do LXC puro (`lxc-create`, `lxc-start`, ...).

---

## 1.10 Problemas comuns

| Problema | Solução |
|---|---|
| Erro `VT-x is not available` / `AMD-V is disabled` ao iniciar a VM | A virtualização está desligada na BIOS. Sem admin, só quem administra a máquina resolve; use outro computador |
| VM muito lenta e uma **tartaruga verde** na barra de status da janela da VM | O VirtualBox está rodando sobre o Hyper-V do Windows (WSL2, Integridade da memória ou VBS ligados). Desligar isso exige admin. Para o trabalho a VM ainda funciona, só mais devagar: reduza para 3 GB de RAM, ligue com `--type headless` e feche outros programas |
| VM nem inicia por causa do Hyper-V | Peça ao suporte para desligar a *Integridade da memória*, ou use outro computador |
| `ssh: connect to host localhost port 2222: Connection refused` | A VM está desligada (`& $vbm list runningvms`), ainda iniciando, ou falta a regra `ssh` (seção 1.3). Confira se o OpenSSH foi instalado: ligue com `--type gui` e rode `systemctl status ssh` |
| `VBoxManage.exe` não encontrado | Confira a pasta de instalação (`Get-ChildItem "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"`) e ajuste `$vbm` |
| `Unknown option` em algum `modifyvm` | Versão diferente do VirtualBox: confira com `& $vbm --version` e `& $vbm modifyvm` (sem argumentos, lista as opções) |
| A VM volta para o instalador ao ligar | A ISO ainda está no drive: rode o `storageattach ... --medium emptydrive` da seção 1.4 |
| Erro ao iniciar a VM falando de porta em uso | Outro programa usa a porta do Windows (ex.: `8080`). Troque a **porta do hospedeiro** na regra (ex.: `18080`) e use o novo número no navegador |
| `Access denied` ao criar a VM ou o disco | Escolha uma pasta onde seu usuário pode gravar (ex.: dentro de `%USERPROFILE%`) |
| VM sem internet | A rede da instituição pode exigir proxy: configure em `/etc/environment` na VM (`http_proxy`/`https_proxy`) e no snap (`sudo snap set system proxy.https=...`) |
| Teclado com acentos/símbolos trocados na janela do VirtualBox | Rode `sudo dpkg-reconfigure keyboard-configuration` ou use o SSH pelo Windows |
| `permission denied` ao usar `lxc` | Rode `newgrp lxd` ou saia (`exit`) e entre de novo na VM |
| `zfs` não aparece no `lxd init` | Use `btrfs` como backend |
| Contêiner sem IPv4 em `lxc list` | Aguarde alguns segundos e rode `lxc list` de novo; se continuar, `lxc restart <nome>` |
| Contêiner sem internet | Verifique se a VM tem internet (`curl -I https://ubuntu.com`) e `lxc network show lxdbr0` (deve ter `ipv4.nat: "true"`) |
| Página não abre no navegador do Windows | Confira a regra de encaminhamento (seção 1.3), o proxy device com `lxc config device show <nome>` e se o Nginx está rodando no contêiner |
| Falta espaço no storage pool | `lxc storage info default`; apague contêineres e imagens que não usa (`lxc image list`, `lxc image delete <id>`) |

---

## 1.11 Validação nas fontes oficiais

Conferido em novembro de 2026. O site do VirtualBox (`virtualbox.org`, `docs.oracle.com`)
estava fora da rede da sessão, então o manual foi lido no **código-fonte oficial**
(<https://github.com/VirtualBox/virtualbox>, pasta `doc/manual/en_US/dita/topics`).

| O que foi validado | Fonte |
|---|---|
| `createvm`, `modifyvm` (`--memory`, `--cpus`, `--ioapic`, `--graphicscontroller`, `--vram`, `--audio-enabled`, `--bootN`, `--nicN`), `storagectl`, `createmedium`, `storageattach` (incl. `emptydrive`), `startvm --type gui/headless`, `controlvm acpipowerbutton`, `snapshot take/restore/list` | VirtualBox: páginas `man_VBoxManage-*.xml` em `doc/manual/en_US` |
| Encaminhamento de portas no NAT; sintaxe `--nat-pf1 "nome,tcp,ip-host,porta-host,ip-convidado,porta-convidado"` e `--natpf1 delete` | VirtualBox: `natforward.dita` |
| Portas abaixo de 1024 exigem privilégio (por isso usamos portas altas); ICMP limitado no NAT (o `ping` pode falhar) | VirtualBox: `nat-limitations.dita` |
| Com Hyper-V ativo, o VirtualBox usa o Hyper-V como motor, com perda de desempenho; ícone da tartaruga verde | VirtualBox: `hyperv-support.dita`, `vm-status-bar.dita` |
| `snap install lxd` instala a LTS atual (track `6`); comando do grupo `lxd` | LXD: [installing.md](https://github.com/canonical/lxd/blob/main/doc/installing.md), [substitutions.yaml](https://github.com/canonical/lxd/blob/main/doc/substitutions.yaml) |
| Perguntas e ordem do `lxd init`; flags `--auto`, `--storage-backend`, `--storage-create-loop` | LXD (código, branch `stable-6`): [main_init_interactive.go](https://github.com/canonical/lxd/blob/stable-6/lxd/main_init_interactive.go), [main_init.go](https://github.com/canonical/lxd/blob/stable-6/lxd/main_init.go) |
| Sintaxe do *proxy device* | LXD: [devices_proxy.md](https://github.com/canonical/lxd/blob/main/doc/reference/devices_proxy.md) |
| `lxc launch ubuntu:24.04`, `lxc list`, `lxc exec`, `lxc info` | LXD: [first_steps.md](https://github.com/canonical/lxd/blob/main/doc/tutorial/first_steps.md) |

**Itens não confirmados na documentação** (confira na hora; também em
[validacoes-pendentes.md](validacoes-pendentes.md)):

- Se um usuário **sem admin** consegue criar VMs e regras de encaminhamento nessa máquina
  (esperado que sim; é o primeiro teste a fazer).
- As páginas de manual lidas são do código mais recente (outubro de 2026). Se a sua
  versão for mais antiga, alguma opção pode ter outro nome (ex.: `--audio none` em vez
  de `--audio-enabled off`); confira com `& $vbm --version`.
- Disponibilidade do ZFS no núcleo do Ubuntu Server 24.04. Por isso o guia indica o
  `btrfs` como alternativa.

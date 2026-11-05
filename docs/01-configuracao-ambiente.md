# 1. Configuração do ambiente (Windows Home + VirtualBox + LXD)

Este guia prepara o ambiente usado no estudo de caso do Trabalho GB
(Assunto 3: servidores com contêineres LXC/LXD).

O Windows **Home** não tem Hyper-V, então a VM Linux é criada no **VirtualBox**.

Arquitetura final do ambiente:

```
Windows Home (host físico)
 └── VirtualBox (hipervisor tipo 2)
      └── VM Ubuntu Server 24.04 "lxd-host"
           ├── enp0s3 → NAT       (internet)
           ├── enp0s8 → Host-only (acesso pelo Windows: 192.168.56.x)
           └── LXD (gerenciador de contêineres, usa a liblxc)
                └── lxdbr0 (10.x.x.x) → contêineres Linux (web1, web2, lb, ...)
```

---

## 1.1 Requisitos

| Item | Mínimo | Recomendado |
|---|---|---|
| Sistema | Windows 10/11 Home 64 bits | — |
| RAM do notebook | 8 GB | 16 GB |
| Espaço livre em disco | 35 GB | 50 GB |
| Virtualização na BIOS/UEFI | Ativada (Intel VT-x / AMD-V) | — |

Para conferir se a virtualização está ativada: abra o **Gerenciador de Tarefas →
Desempenho → CPU** e procure **"Virtualização: Habilitado"**. Se estiver
desabilitado, ative na BIOS/UEFI (opção *Intel Virtualization Technology*, *VT-x*
ou *SVM Mode*).

---

## 1.2 Baixar e instalar

1. **VirtualBox** (versão 7.x para Windows):
   <https://www.virtualbox.org/wiki/Downloads> → *Windows hosts*.
   Instale com as opções padrão (aceite instalar os drivers de rede).
   Se o instalador pedir *Python Core / win32api*, pode ignorar.

2. **Ubuntu Server 24.04 LTS** (arquivo `.iso`, ~2,6 GB):
   <https://ubuntu.com/download/server> → *Download Ubuntu Server 24.04 LTS*.

---

## 1.3 Conferir a rede Host-only do VirtualBox

A rede Host-only permite que o Windows acesse a VM por um IP fixo
(`192.168.56.x`), sem depender da rede Wi-Fi.

1. No VirtualBox: **Arquivo → Ferramentas → Gerenciador de Rede**
   (*File → Tools → Network Manager*), aba **Host-only Networks**.
2. Deve existir uma rede (ex.: *VirtualBox Host-Only Ethernet Adapter*) com:
   - IPv4: `192.168.56.1` / máscara `255.255.255.0`
   - **DHCP Server: habilitado**
3. Se não existir, clique em **Criar** (*Create*) e confira os valores acima.

---

## 1.4 Criar a VM

1. Clique em **Novo** (*New*) e preencha:

   | Campo | Valor |
   |---|---|
   | Nome | `lxd-host` |
   | Imagem ISO | o arquivo `ubuntu-24.04.x-live-server-amd64.iso` |
   | Tipo / Versão | Linux / Ubuntu (64-bit) |
   | **Pular instalação desassistida** (*Skip Unattended Installation*) | ✅ **marcar** |

   > Marque essa opção para fazer a instalação manualmente e controlar as escolhas.

2. **Hardware:**

   | Campo | Valor |
   |---|---|
   | Memória base | `4096 MB` (use `3072 MB` se o notebook tiver só 8 GB) |
   | Processadores | `2` |

3. **Disco rígido:** criar um disco virtual de **30 GB** (VDI, alocado dinamicamente).

4. Clique em **Finalizar**.

### Configurar as duas placas de rede

Selecione a VM → **Configurações** (*Settings*) → **Rede** (*Network*):

| Aba | Habilitar | Conectado a | Nome |
|---|---|---|---|
| **Adaptador 1** | ✅ | **NAT** | — |
| **Adaptador 2** | ✅ | **Placa de rede exclusiva de hospedeiro** (*Host-only Adapter*) | *VirtualBox Host-Only Ethernet Adapter* |

---

## 1.5 Instalar o Ubuntu Server

Inicie a VM (**Iniciar**). Use as setas e o Enter para navegar no instalador.

| Tela do instalador | O que escolher |
|---|---|
| *Try or Install Ubuntu Server* | Enter |
| Language | `English` (os comandos e mensagens de erro ficam mais fáceis de pesquisar) |
| Installer update available | `Continue without updating` |
| Keyboard configuration | Layout: `Portuguese (Brazil)` (teclado ABNT2) |
| Type of installation | `Ubuntu Server` |
| Network configuration | Devem aparecer **duas** interfaces com IP: `enp0s3` (10.0.2.15) e `enp0s8` (192.168.56.x). **Anote o IP da `enp0s8`.** Done |
| Proxy configuration | Deixar vazio. Done |
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

Faça login com o usuário e a senha criados.

---

## 1.6 Acessar a VM pelo Windows (SSH)

Usar SSH é bem mais prático que a janela do VirtualBox: dá para copiar e colar
comandos.

1. **Na VM**, confira o IP da placa Host-only (`enp0s8`):

   ```bash
   ip -4 addr show enp0s8
   ```

   Normalmente é `192.168.56.101`.

2. **No Windows**, abra o **PowerShell** ou o **Terminal** e conecte:

   ```powershell
   ssh aluno@192.168.56.101
   ```

   Na primeira vez, digite `yes` para aceitar a chave e depois a senha.

> **Dica:** dá para deixar a VM rodando sem janela: no VirtualBox, clique na seta
> ao lado de **Iniciar** → **Início sem interface** (*Headless Start*) e use só o SSH.

A partir daqui, **todos os comandos são executados dentro da VM** (o prompt fica
`aluno@lxd-host:~$`).

Atualize o sistema:

```bash
sudo apt update && sudo apt upgrade -y
```

---

## 1.7 Instalar o LXD

```bash
sudo snap install lxd
```

> Se aparecer `snap "lxd" is already installed`, está tudo certo.

Dê permissão ao seu usuário para usar o LXD sem `sudo`:

```bash
sudo usermod -aG lxd $USER
newgrp lxd
```

Confira:

```bash
lxd --version
```

---

## 1.8 Inicializar o LXD (`lxd init`)

```bash
lxd init
```

Respostas sugeridas para as perguntas:

| Pergunta | Resposta |
|---|---|
| Would you like to use LXD clustering? | `no` |
| Do you want to configure a new storage pool? | `yes` |
| Name of the new storage pool | `default` |
| Name of the storage backend to use | `zfs` |
| Create a new ZFS pool? | `yes` |
| Would you like to use an existing empty block device? | `no` |
| Size in GiB of the new loop device | `15GiB` |
| Would you like to connect to a MAAS server? | `no` |
| Would you like to create a new local network bridge? | `yes` |
| What should the new bridge be called? | `lxdbr0` |
| What IPv4 address should be used? | `auto` |
| What IPv6 address should be used? | `none` |
| Would you like the LXD server to be available over the network? | `no` |
| Would you like stale cached images to be updated automatically? | `yes` |
| Would you like a YAML "lxd init" preseed to be printed? | `no` |

> **Atalho (sem perguntas):**
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

## 1.9 Testar o ambiente

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
   lxc exec teste -- ping -c 3 8.8.8.8
   lxc exec teste -- apt update
   ```

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

   No Windows, abra `http://192.168.56.101:8080` (use o IP da sua `enp0s8`).
   Deve aparecer a página **"Welcome to nginx!"**.

6. Apagar o contêiner de teste:

   ```bash
   lxc delete teste --force
   ```

Se todos os passos funcionaram, o ambiente está pronto para o estudo de caso.

### Snapshot de segurança da VM

Com tudo funcionando, desligue a VM (`sudo poweroff`) e, no VirtualBox, tire um
snapshot: selecione a VM → ícone de menu ☰ → **Snapshots** → **Tirar** (*Take*),
com o nome `lxd-pronto`. Se algo quebrar mais tarde, é só restaurar.

---

## 1.10 Comandos do dia a dia

### Na VM (Ubuntu)

| Comando | O que faz |
|---|---|
| `ip -4 addr show enp0s8` | Mostra o IP da VM na rede Host-only |
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
| `lxc image list images: ubuntu` | Lista imagens disponíveis |

> **Atenção:** o comando `lxc` (sem hífen) é o **cliente do LXD**. Ele não é o
> mesmo que as ferramentas antigas do LXC puro (`lxc-create`, `lxc-start`, ...).

---

## 1.11 Problemas comuns

| Problema | Solução |
|---|---|
| Erro `VT-x is not available` / `AMD-V is disabled` ao iniciar a VM | Ative a virtualização na BIOS/UEFI do notebook |
| VM muito lenta e uma **tartaruga verde** no canto da janela da VM | O VirtualBox está rodando sobre a camada do Hyper-V do Windows. Em *Ativar ou desativar recursos do Windows*, desmarque **Plataforma de Máquina Virtual** (desativa o WSL2) e em *Segurança do Windows → Segurança do dispositivo → Isolamento de núcleo*, desative **Integridade da memória**. Reinicie o notebook |
| Só aparece uma interface de rede no instalador | Confira se o **Adaptador 2** está habilitado como *Host-only* (seção 1.4) |
| `enp0s8` sem IP (`192.168.56.x`) | Confira se o DHCP da rede Host-only está habilitado (seção 1.3) e rode `sudo netplan apply` |
| `ssh: connect to host ... Connection timed out` | Confira o IP com `ip -4 addr show enp0s8` e se a VM está ligada |
| Teclado com acentos/símbolos trocados na janela do VirtualBox | Rode `sudo dpkg-reconfigure keyboard-configuration` ou use o SSH pelo Windows |
| `permission denied` ao usar `lxc` | Rode `newgrp lxd` ou saia (`exit`) e entre de novo na VM |
| Contêiner sem IPv4 em `lxc list` | Aguarde alguns segundos e rode `lxc list` de novo; se continuar, `lxc restart <nome>` |
| Contêiner sem internet | Verifique se a própria VM tem internet (`ping 8.8.8.8`) e `lxc network show lxdbr0` (deve ter `ipv4.nat: "true"`) |
| Página não abre no navegador do Windows | Confira o proxy device com `lxc config device show <nome>` e se o Nginx está rodando no contêiner |
| Falta espaço no storage pool | `lxc storage info default`; apague contêineres e imagens que não usa (`lxc image list`, `lxc image delete <id>`) |

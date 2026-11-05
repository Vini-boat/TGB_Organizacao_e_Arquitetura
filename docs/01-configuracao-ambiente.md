# 1. Configuração do ambiente (Windows + Multipass + LXD)

Este guia prepara o ambiente usado no estudo de caso do Trabalho GB
(Assunto 3: servidores com contêineres LXC/LXD).

Arquitetura final do ambiente:

```
Windows (host físico)
 └── Hyper-V / VirtualBox (hipervisor)
      └── VM Ubuntu 24.04 "lxd-host"  (criada pelo Multipass)
           └── LXD (gerenciador de contêineres, usa a liblxc)
                └── contêineres Linux (web1, web2, lb, ...)
```

---

## 1.1 Requisitos

| Item | Mínimo | Recomendado |
|---|---|---|
| Sistema | Windows 10/11 64 bits | Windows 11 |
| RAM do PC | 8 GB | 16 GB |
| Espaço livre em disco | 30 GB | 40 GB |
| Virtualização na BIOS/UEFI | Ativada (Intel VT-x / AMD-V) | — |

Para conferir se a virtualização está ativada: abra o **Gerenciador de Tarefas →
Desempenho → CPU** e procure **"Virtualização: Habilitado"**.

---

## 1.2 Instalar o Multipass

O Multipass (da Canonical) cria VMs Ubuntu com um único comando.

1. Abra o **PowerShell** e execute:

   ```powershell
   winget install Canonical.Multipass
   ```

   (ou baixe o instalador em <https://multipass.run/install>)

2. Durante a instalação, escolha o hipervisor:
   - **Windows Pro / Enterprise / Education:** use **Hyper-V** (o instalador ativa se necessário).
   - **Windows Home:** não tem Hyper-V. Instale antes o
     [VirtualBox](https://www.virtualbox.org/wiki/Downloads) e escolha **VirtualBox**.

3. Reinicie o computador se o instalador pedir.

4. Confira a instalação:

   ```powershell
   multipass version
   ```

---

## 1.3 Criar a VM Ubuntu

No PowerShell:

```powershell
multipass launch 24.04 --name lxd-host --cpus 2 --memory 4G --disk 25G
```

| Parâmetro | Significado |
|---|---|
| `24.04` | Ubuntu 24.04 LTS |
| `--name lxd-host` | Nome da VM |
| `--cpus 2` | 2 vCPUs |
| `--memory 4G` | 4 GB de RAM (use `3G` se o PC tiver só 8 GB) |
| `--disk 25G` | Disco virtual de 25 GB |

Confira se a VM está rodando e anote o **IPv4** dela (vai ser usado para acessar
os serviços pelo navegador do Windows):

```powershell
multipass list
```

---

## 1.4 Entrar na VM

```powershell
multipass shell lxd-host
```

A partir daqui, **todos os comandos são executados dentro da VM** (o prompt fica
`ubuntu@lxd-host:~$`).

Atualize o sistema:

```bash
sudo apt update && sudo apt upgrade -y
```

---

## 1.5 Instalar o LXD

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

## 1.6 Inicializar o LXD (`lxd init`)

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

## 1.7 Testar o ambiente

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

5. Apagar o contêiner de teste:

   ```bash
   lxc delete teste --force
   ```

Se todos os passos funcionaram, o ambiente está pronto para o estudo de caso.

---

## 1.8 Comandos do dia a dia

### Multipass (no PowerShell do Windows)

| Comando | O que faz |
|---|---|
| `multipass list` | Lista as VMs e seus IPs |
| `multipass shell lxd-host` | Abre o terminal da VM |
| `multipass stop lxd-host` | Desliga a VM |
| `multipass start lxd-host` | Liga a VM |
| `multipass info lxd-host` | Mostra CPU, RAM, disco e IP da VM |
| `multipass delete lxd-host` + `multipass purge` | Apaga a VM (recomeçar do zero) |

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

## 1.9 Problemas comuns

| Problema | Solução |
|---|---|
| `launch failed: ... Hyper-V` ou VM não inicia | Confirme que a virtualização está ativada na BIOS e que o Hyper-V está habilitado (Windows Pro) |
| Windows Home e o Multipass não cria a VM | Instale o VirtualBox e rode `multipass set local.driver=virtualbox` |
| `launch failed: timed out` | Rode o comando de novo; a primeira execução baixa a imagem do Ubuntu e pode demorar |
| `permission denied` ao usar `lxc` | Rode `newgrp lxd` ou saia (`exit`) e entre de novo na VM |
| Contêiner sem IPv4 em `lxc list` | Aguarde alguns segundos e rode `lxc list` de novo; se continuar, `lxc restart <nome>` |
| Contêiner sem internet | Verifique `lxc network show lxdbr0` (deve ter `ipv4.nat: "true"`) e se a própria VM tem internet (`ping 8.8.8.8`) |
| Falta espaço no storage pool | `lxc storage info default`; apague contêineres e imagens que não usa (`lxc image list`, `lxc image delete <id>`) |

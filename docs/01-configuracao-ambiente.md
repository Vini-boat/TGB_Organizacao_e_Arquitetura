# 1. Configuração do ambiente (Windows Home + Multipass + LXD)

Este guia prepara o ambiente usado no estudo de caso do Trabalho GB
(Assunto 3: servidores com contêineres LXC/LXD).

Arquitetura final do ambiente:

```
Windows 10/11 Home (host físico)
 └── Plataforma de Máquina Virtual (hipervisor do Windows, API HCS)
      └── VM Ubuntu 24.04 "lxd-host"  (criada e gerenciada pelo Multipass)
           └── LXD 6 LTS (gerenciador de contêineres, usa a liblxc)
                └── lxdbr0 (10.x.x.x) → contêineres Linux (web1, web2, lb, ...)
```

> **Por que não VirtualBox?** A partir da versão 1.18, o Multipass não suporta mais
> o VirtualBox. No Windows ele usa o driver `hcs` (Host Compute System), que funciona
> nas edições **Home**, Pro e Enterprise. Ele usa a mesma base do WSL2, a
> **Plataforma de Máquina Virtual**.

---

## 1.1 Requisitos

| Item | Valor |
|---|---|
| Sistema | Windows 10 ou 11 (Home, Pro ou Enterprise), versão **1809** ou mais nova |
| Recurso do Windows | **Plataforma de Máquina Virtual** ativada (seção 1.2) |
| Virtualização na BIOS/UEFI | Ativada (Intel VT-x / AMD-V) |
| RAM do notebook | 8 GB no mínimo (16 GB recomendado) |
| Espaço livre em disco | 30 GB no mínimo |

Para conferir se a virtualização está ativada na BIOS: abra o **Gerenciador de
Tarefas → Desempenho → CPU** e procure **"Virtualização: Habilitado"**.

---

## 1.2 Ativar a Plataforma de Máquina Virtual

**Opção A (interface gráfica):**

1. Pressione a tecla Windows e digite **"Ativar ou desativar recursos do Windows"**.
2. Marque **Plataforma de Máquina Virtual** (*Virtual Machine Platform*).
3. Clique em OK e **reinicie** o computador.

**Opção B (PowerShell como Administrador):**

```powershell
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
```

Depois **reinicie** o computador.

> Se você já usa o WSL2, esse recurso provavelmente já está ativado.

---

## 1.3 Instalar o Multipass

1. Baixe o instalador `.msi` em <https://canonical.com/multipass/download/windows>
   ou instale pelo PowerShell:

   ```powershell
   winget install Canonical.Multipass
   ```

2. Execute o instalador (ele pede permissão de Administrador) e siga as telas.

3. Abra um **novo** PowerShell e confira:

   ```powershell
   multipass version
   ```

   A versão deve ser **1.17 ou mais nova**.

4. Confira se o driver é o `hcs` (o padrão em instalações novas):

   ```powershell
   multipass get local.driver
   ```

   Se aparecer `hyperv` (instalação antiga), troque com:

   ```powershell
   multipass set local.driver=hcs
   ```

---

## 1.4 Criar a VM Ubuntu

No PowerShell:

```powershell
multipass launch 24.04 --name lxd-host --cpus 2 --memory 4G --disk 30G
```

| Parâmetro | Significado | Padrão do Multipass |
|---|---|---|
| `24.04` | Ubuntu 24.04 LTS (a mesma versão usada nos tutoriais oficiais do LXD) | última LTS |
| `--name lxd-host` | Nome da VM | nome aleatório |
| `--cpus 2` | 2 vCPUs | 1 |
| `--memory 4G` | 4 GB de RAM (use `3G` se o notebook tiver só 8 GB) | 1G |
| `--disk 30G` | Disco virtual de 30 GB | 5G (pouco para o LXD) |

> A primeira execução baixa a imagem do Ubuntu e pode demorar alguns minutos.

Confira se a VM está rodando e **anote o IPv4** dela:

```powershell
multipass list
```

> **Atenção:** a VM usa a *Default Switch* do Windows, e o IP pode mudar depois
> de reiniciar o notebook. Sempre confira com `multipass list` antes de usar.

---

## 1.5 Entrar na VM

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

## 1.6 Instalar o LXD

```bash
sudo snap install lxd --channel=6/stable
```

> Sem o `--channel`, o snap também instala a LTS atual (track `6`). O parâmetro só
> deixa a versão explícita. Se aparecer `snap "lxd" is already installed`, confira
> a versão com `snap list lxd` (a coluna *Tracking* deve mostrar `6/stable`). Se
> não mostrar, rode `sudo snap refresh lxd --channel=6/stable`.

Dê permissão ao usuário `ubuntu` para usar o LXD sem `sudo`
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

   O *proxy device* faz a porta `8080` da VM encaminhar para a porta `80` do contêiner.
   No Windows, abra `http://<IP-da-VM>:8080` (o IP do `multipass list`).
   Deve aparecer a página **"Welcome to nginx!"**.

6. Apagar o contêiner de teste:

   ```bash
   lxc delete teste --force
   ```

Se todos os passos funcionaram, o ambiente está pronto para o estudo de caso.

### Snapshot de segurança da VM

Com tudo funcionando, tire um snapshot da VM. Ele **só pode ser feito com a VM
parada**. No PowerShell:

```powershell
multipass stop lxd-host
multipass snapshot lxd-host --name lxd-pronto
multipass start lxd-host
```

Se algo quebrar mais tarde, restaure com o comando abaixo (ele pergunta se você quer
salvar o estado atual antes; pode responder `n`):

```powershell
multipass restore lxd-host.lxd-pronto
```

---

## 1.9 Comandos do dia a dia

### Multipass (no PowerShell do Windows)

| Comando | O que faz |
|---|---|
| `multipass list` | Lista as VMs, o estado e os IPs |
| `multipass shell lxd-host` | Abre o terminal da VM |
| `multipass info lxd-host` | Mostra CPU, RAM, disco, IP e snapshots da VM |
| `multipass stop lxd-host` / `multipass start lxd-host` | Desliga / liga a VM |
| `multipass snapshot lxd-host --name <nome>` | Snapshot da VM (precisa estar parada) |
| `multipass restore lxd-host.<nome>` | Volta a VM para um snapshot |
| `multipass delete lxd-host` + `multipass purge` | Apaga a VM de vez (recomeçar do zero) |

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
| `multipass launch` falha logo no início | Confira se a **Plataforma de Máquina Virtual** está ativada (seção 1.2) e se a virtualização está habilitada na BIOS |
| `launch failed: timed out` | Rode o comando de novo; a primeira execução baixa a imagem e pode demorar |
| VM sem internet ou conexão instável | Antivírus/segurança (Symantec, ESET, Kaspersky, Malwarebytes...) e **VPNs** podem bloquear o tráfego das VMs. Desative temporariamente para testar |
| Upload muito lento pelo Wi-Fi | No **Gerenciador de Dispositivos → Adaptadores de rede → Hyper-V Virtual Ethernet Adapter → Propriedades → Avançado**, desative *Large Send Offload v2 (IPv4)* e *(IPv6)* |
| O IP da VM mudou | Normal depois de reiniciar o Windows. Confira com `multipass list` |
| `permission denied` ao usar `lxc` | Rode `newgrp lxd` ou saia (`exit`) e entre de novo com `multipass shell lxd-host` |
| `zfs` não aparece no `lxd init` | Use `btrfs` como backend |
| Contêiner sem IPv4 em `lxc list` | Aguarde alguns segundos e rode `lxc list` de novo; se continuar, `lxc restart <nome>` |
| Contêiner sem internet | Verifique se a VM tem internet (`ping 8.8.8.8`) e `lxc network show lxdbr0` (deve ter `ipv4.nat: "true"`) |
| Página não abre no navegador do Windows | Confira o IP com `multipass list`, o proxy device com `lxc config device show <nome>` e se o Nginx está rodando no contêiner |
| Falta espaço no storage pool | `lxc storage info default`; apague contêineres e imagens que não usa (`lxc image list`, `lxc image delete <id>`) |

---

## 1.11 Validação nas fontes oficiais

Os passos acima foram conferidos em novembro de 2026 na documentação e no código-fonte oficiais:

| O que foi validado | Fonte |
|---|---|
| Windows Home suportado; exige versão 1809+ e Plataforma de Máquina Virtual | Multipass: [install-multipass.md](https://github.com/canonical/multipass/blob/main/docs/how-to-guides/install-multipass.md), [platform.md](https://github.com/canonical/multipass/blob/main/docs/explanation/platform.md) |
| Driver padrão `hcs`; VirtualBox removido na 1.18; `hyperv` obsoleto na 1.17 | Multipass: [driver.md](https://github.com/canonical/multipass/blob/main/docs/explanation/driver.md), [local-driver.md](https://github.com/canonical/multipass/blob/main/docs/reference/settings/local-driver.md) |
| Opções `--cpus`, `--memory`, `--disk`, `--name` e imagem `24.04` | Multipass: [launch.md](https://github.com/canonical/multipass/blob/main/docs/reference/command-line-interface/launch.md) |
| Snapshot só com a VM parada; sintaxe do `restore` (`<vm>.<snapshot>`) e `get local.driver` | Multipass: [snapshot.md](https://github.com/canonical/multipass/blob/main/docs/reference/command-line-interface/snapshot.md), [restore.md](https://github.com/canonical/multipass/blob/main/docs/reference/command-line-interface/restore.md), [get.md](https://github.com/canonical/multipass/blob/main/docs/reference/command-line-interface/get.md) |
| Acesso pelo navegador do Windows ao IP da VM; rede pela *Default Switch*; antivírus e Wi-Fi | Multipass: [getting-started.md](https://github.com/canonical/multipass/blob/main/docs/tutorial/getting-started.md), [troubleshoot-networking.md](https://github.com/canonical/multipass/blob/main/docs/how-to-guides/troubleshoot/troubleshoot-networking.md) |
| `snap install lxd` instala a LTS atual (track `6`); comando do grupo `lxd` | LXD: [installing.md](https://github.com/canonical/lxd/blob/main/doc/installing.md), [substitutions.yaml](https://github.com/canonical/lxd/blob/main/doc/substitutions.yaml) |
| Perguntas e ordem do `lxd init`; flags `--auto`, `--storage-backend`, `--storage-create-loop` | LXD (código, branch `stable-6`): [main_init_interactive.go](https://github.com/canonical/lxd/blob/stable-6/lxd/main_init_interactive.go), [main_init.go](https://github.com/canonical/lxd/blob/stable-6/lxd/main_init.go) |
| Sintaxe do *proxy device* | LXD: [devices_proxy.md](https://github.com/canonical/lxd/blob/main/doc/reference/devices_proxy.md) |
| `lxc launch ubuntu:24.04`, `lxc list`, `lxc exec`, `lxc info` | LXD: [first_steps.md](https://github.com/canonical/lxd/blob/main/doc/tutorial/first_steps.md) |

**Itens não confirmados na documentação** (confira na hora):

- O identificador `Canonical.Multipass` no `winget`. Se não funcionar, use o instalador `.msi` do site.
- Disponibilidade do ZFS no kernel da imagem Ubuntu do Multipass. Por isso o guia indica o `btrfs` como alternativa.

# Validações pendentes

Lista do que ainda **não foi conferido** nas documentações oficiais, para retomar
quando houver acesso à rede necessária (ex.: a partir do PC do autor).

Atualizado em novembro de 2026. Ao validar um item, marque `[x]` e mova a fonte para a
tabela de validação do documento correspondente (seções 1.11 e 3.8).

---

## A. Tentativas bloqueadas pela rede

Foram tentadas, mas o site estava **fora da rede permitida** da sessão em nuvem
(`getaddrinfo ENOTFOUND`).

| # | Site bloqueado | O que conferir | Onde é usado |
|---|---|---|---|
| [ ] A1 | `salsa.debian.org` | Integração do pacote `patroni` do Debian/Ubuntu com o `postgresql-common`: `README.Debian`, `pg_createconfig_patroni`, unidades systemd (`patroni.service` × `patroni@.service`) e caminho do arquivo de configuração (`/etc/patroni/...`). URL tentada: <https://salsa.debian.org/postgresql/patroni/-/raw/master/debian/README.Debian> | doc 03, seção "Patroni + PostgreSQL" |
| [ ] A2 | `docs.haproxy.org` | Descrição oficial de `balance leastconn` e `balance roundrobin`. URL tentada: <https://docs.haproxy.org/2.8/configuration.html> | doc 03 (HAProxy), doc 04 (seção 4.4.2) |
| [ ] A3 | `docs.haproxy.org` | Se a **API de execução** (*runtime API*) permite trocar o algoritmo de balanceamento sem recarregar. Se não permitir, a demonstração usa recarga do HAProxy | doc 04 (seção 4.4.2) |
| [ ] A4 | `docs.haproxy.org` | Formato CSV das estatísticas (`/;csv`): nomes das colunas de estado, sessões/s e resultado do health check | doc 04 (seção 4.4, fontes do painel) |

| [ ] A5 | `revealjs.com` | Documentação de destaque de linhas (`/code/`) e exportação para PDF (`/pdf-export/`). **Parcialmente contornado:** conferido no código do pacote `reveal.js` 6.0.2 do npm (ver nota abaixo) | doc 04 (seções 4.3.1 e 4.5) |

> **Conferido no pacote `reveal.js` 6.0.2 (npm), sem o site:** delimitador de passos `|`
> em `data-line-numbers` (plugin Highlight, exemplo `data-line-numbers="|4,8-11|17|22-24"`
> no `demo.html`); `data-ln-start-from`; `pdfSeparateFragments` com padrão `true` e
> `showNotes` com padrão `false` (`js/config.ts`); `?print-pdf` ainda aceito, mas marcado
> no código como *legacy support*. Falta ver no site qual é a forma atual recomendada de
> exportar.

> Ao liberar o acesso, verificar também a versão do HAProxy no Ubuntu 24.04
> (<https://packages.ubuntu.com/noble/haproxy>) e usar a documentação **dessa** versão.

---

## B. Afirmações ainda não conferidas (nem tentadas)

Estão nos documentos com base em conhecimento prévio. Fonte sugerida ao lado.

### LXD (doc 02, 03 e 04)

| # | Afirmação | Fonte sugerida |
|---|---|---|
| [ ] B1 | Mapa de IDs padrão de contêiner sem privilégio no snap: `uid_map` = `0 1000000 1000000000` | LXD: `doc/userns-idmap.md` |
| [ ] B2 | Caminho do cgroup de um contêiner: `/sys/fs/cgroup/lxc.payload.<nome>/` | Teste no ambiente |
| [ ] B3 | `limits.cpu.allowance 20%` é limite flexível; `20ms/100ms` gera `cpu.max 20000 100000` | LXD: `doc/reference/instance_options.md` |
| [ ] B4 | `lxc pause` usa o freezer do cgroup e o estado vira `FROZEN` | LXD: `doc/reference/manpages/lxc/pause.md` |
| [ ] B5 | `boot.autostart`, `boot.autostart.priority`, `boot.autostart.delay` | LXD: `doc/reference/instance_options.md` |
| [ ] B6 | API de eventos `/1.0/events?type=lifecycle` e nomes dos eventos (`instance-stopped`, `instance-paused`, `instance-started`, `snapshot-created`) | LXD: `doc/events.md` |
| [ ] B7 | `/1.0/instances/<nome>/state` traz CPU, memória, nº de processos, endereços e contadores de rede | LXD: `doc/rest-api.yaml` |
| [ ] B8 | Socket do LXD no snap: `/var/snap/lxd/common/lxd/unix.socket` | LXD: `doc/rest-api.md` |
| [ ] B9 | `lxc network set lxdbr0 ipv4.dhcp.ranges` e `lxc config device override <c> eth0 ipv4.address=` | LXD: `doc/reference/network_bridge.md`, `doc/reference/devices_nic.md` |
| [ ] B10 | Migração ao vivo de contêineres depende do CRIU e é limitada | LXD: `doc/howto/move_instances.md` |

### Patroni e etcd (doc 03)

| # | Afirmação | Fonte sugerida |
|---|---|---|
| [ ] B11 | `GET /cluster` da API do Patroni traz líder, réplicas, *timeline* e atraso | Patroni: `docs/rest_api.rst` (seção cluster) |
| [ ] B12 | `patronictl switchover` e `patronictl list` (sintaxe com `-c`) | Patroni: `docs/patronictl.rst` |
| [ ] B13 | Pacote `etcd-server` do Ubuntu lê variáveis `ETCD_*` de `/etc/default/etcd` | Arquivo instalado pelo pacote (teste) ou `salsa.debian.org` |
| [ ] B14 | Endpoint `/health` do etcd 3.4 | etcd: <https://etcd.io/docs/v3.4/op-guide/monitoring/> |
| [ ] B15 | PostgreSQL do Ubuntu 24.04 é a versão 16, com binários em `/usr/lib/postgresql/16/bin` | <https://packages.ubuntu.com/noble/postgresql> |

### Apresentação (doc 04)

| # | Afirmação | Fonte sugerida |
|---|---|---|
| [ ] B16 | `ttyd -c usuario:senha` (autenticação básica) e opção para escutar só num endereço | `man ttyd` (Ubuntu noble) |
| [ ] B17 | Forma atual de exportar o reveal.js para PDF (`?print-pdf` é legado no 6.0.2) e alternativa com `decktape` | <https://revealjs.com/pdf-export/> (ver A5) |
| [ ] B18 | Locust em modo `--headless` | <https://docs.locust.io/> |

### Guia de configuração (doc 01), já listados lá

| # | Afirmação | Fonte sugerida |
|---|---|---|
| [ ] B19 | Identificador `Canonical.Multipass` no `winget` | `winget search multipass` no Windows |
| [ ] B20 | ZFS disponível no núcleo da imagem Ubuntu do Multipass | Teste no ambiente |

---

## C. Só o teste no ambiente real responde

| # | Pergunta | Onde |
|---|---|---|
| [ ] C1 | O keepalived consegue adicionar o IP virtual num contêiner **sem privilégio**? | doc 03 |
| [ ] C2 | O network forward aceita o **IP virtual** como destino e o **IP da VM** como endereço de escuta? (alternativa: DNAT no `lxd-host`) | doc 03 |
| [ ] C3 | VRRP unicast entre `lb1` e `lb2` funciona pela `lxdbr0` | doc 03 |
| [ ] C4 | Clonar o `db1` com `lxc copy` **antes** de iniciar o Patroni e só trocar nome/IP no `db2` | doc 03 |
| [ ] C5 | Com `leastconn` + limite de CPU, a divisão do tráfego muda de forma visível | doc 04 |
| [ ] C6 | O gerador de carga no Windows alcança a concorrência desejada pelo network forward, e o painel recebe os números dele (`GET`/`POST /carga`) | doc 04 |
| [ ] C7 | Atalhos do reveal.js não interferem na digitação no terminal (`ttyd` em `iframe`) | doc 04 |
| [ ] C8 | Restaurar os snapshots dos 6 contêineres juntos deixa Patroni e etcd coerentes | doc 04 |
| [ ] C9 | Tempos reais de failover (app, balanceador, banco) | doc 03, doc 04 |

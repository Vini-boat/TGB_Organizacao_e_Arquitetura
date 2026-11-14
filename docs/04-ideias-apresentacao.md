# 4. Ideias para a apresentação

> **Status:** proposta, ainda não implementada. **Secundário:** só depois que o estudo de
> caso (doc 03) estiver montado e funcionando. Se faltar tempo, a apresentação é slides
> comuns + terminal + o vídeo da demonstração.

## 4.1 Objetivo

Uma apresentação **interativa numa página web**, no estilo de um *notebook*:

1. os slides mostram comandos (`incus stop db1 --force`, `patronictl list`...) que podem
   ser **executados ali mesmo**, com a saída aparecendo logo abaixo;
2. um **painel de estado ao vivo**, sempre visível, mostra quem está de pé e quem está
   se comunicando com quem (tráfego, health checks, replicação, votos do etcd).

A ideia é que a plateia **veja** o failover acontecer: o `db1` fica vermelho, as setas
de health check falham, o IP virtual pula de contêiner e o `db2` ganha a coroa de líder.

---

## 4.1.1 Princípio: LXC/LXD em primeiro plano

O assunto do trabalho são as **ferramentas LXC/LXD**. Balanceamento e alta
disponibilidade são o **cenário** onde elas aparecem, não o tema principal.

Regras que decorrem disso:

| Regra | Na prática |
|---|---|
| **Todo comando ao vivo é um comando `lxc`** | Falhas são provocadas com `incus stop`, `incus pause`, `incus config set`; inspeção com `incus list`, `incus info`, `incus exec`. HAProxy, Patroni e keepalived aparecem pelo efeito, quase nunca pelo comando |
| **O painel é a "visão do Incus"** | Cada nó mostra primeiro o que o Incus sabe dele (estado, CPU, memória, processos, IPs, snapshots, perfil) e só depois o papel no cenário (líder, MASTER) |
| **A linha do tempo vem dos eventos do Incus** | Os eventos de ciclo de vida da API (`instance-stopped`, `instance-paused`, `instance-started`, `instance-snapshot-created`) alimentam a faixa de eventos: é o mesmo fluxo do `incus monitor` |
| **A própria apresentação é um cliente do Incus** | O servidor da página fala com a mesma API REST que o comando `lxc`. Vale um slide mostrando isso |
| **Proporção do tempo** | Cerca de 2/3 sobre LXC/LXD (conceitos, mecanismos do núcleo, recursos da ferramenta); 1/3 sobre o cenário de balanceamento e alta disponibilidade |

---

## 4.2 Arquitetura da solução

```
Navegador (Windows / projetor)
   │  http://localhost:9000  (encaminhado pelo VirtualBox)
   ▼
┌──────────────────────────── incus-host (VM) ────────────────────────────┐
│                                                                       │
│  servidor da apresentação (Python, roda NO HOST, fora dos contêineres)│
│   ├── GET  /            → página (slides + painel)                    │
│   ├── POST /run/<id>    → executa um comando da lista permitida       │
│   ├── GET  /stream/<id> → saída do comando em tempo real (SSE)        │
│   └── GET  /status      → JSON com o estado dos 6 contêineres         │
│          │                                                            │
│          ├── API do Incus (socket unix)  → contêiner ligado/desligado,  │
│          │                               IPs (quem tem o IP virtual)  │
│          ├── HAProxy :8404/;csv        → estado e tráfego dos apps/dbs│
│          ├── Patroni :8008/cluster     → líder, réplica, atraso       │
│          └── etcd :2379/health         → membros do etcd vivos        │
│                                                                       │
│  lb1  lb2  app1  app2  db1  db2   (contêineres)                       │
└───────────────────────────────────────────────────────────────────────┘
```

**Decisão importante:** o servidor da apresentação roda **no `incus-host`, não num
contêiner**. Ele é o "observador externo": continua funcionando enquanto os contêineres
são derrubados de propósito, e só ele tem acesso ao comando `lxc`.

---

## 4.3 Execução dos comandos (o "notebook")

- Cada bloco de comando no slide tem um botão **▶ (play) ao lado**, como uma célula de
  notebook:

  ```
  ┌──────────────────────────────────────────────┐
  │ $ incus stop db1 --force                       │  [▶]
  └──────────────────────────────────────────────┘
    saída aparece aqui...                  ✓ 0,8 s
  ```

  | Estado do botão | Significado |
  |---|---|
  | ▶ | pronto para executar |
  | ■ | executando; clicar interrompe (comandos em laço) |
  | ✓ / ✗ | terminou com sucesso / com erro (código de saída), com o tempo gasto |
  | ⏱ | comando que provoca failover: abre o cronômetro (4.4.1) |

- O botão manda **só o identificador** do comando (`/run/derruba-db1`), não o texto.
  O servidor tem uma **lista fechada** de comandos permitidos. Isso evita:
  - executar qualquer coisa vinda do navegador;
  - erro de digitação ao vivo.
- A saída aparece **em tempo real** abaixo do bloco (Server-Sent Events), como num
  terminal. Comandos longos (`patronictl list` em laço, `curl` em laço) podem ser
  interrompidos com um botão **■ Parar**.
- Um botão fixo **↺ Reiniciar cenário** devolve tudo ao estado inicial (ver 4.7).

Exemplo de definição de comando no servidor:

```python
COMANDOS = {
    "derruba-db1":   ["incus", "stop", "db1", "--force"],
    "liga-db1":      ["incus", "start", "db1"],
    "patroni-list":  ["incus", "exec", "db2", "--", "patronictl", "-c", "/etc/patroni/16-main.yml", "list"],
    "uid-map":       ["incus", "exec", "app1", "--", "cat", "/proc/self/uid_map"],
}
```

## 4.3.1 Configurações nos slides com destaque de linha

As configurações (perfil do Incus, `haproxy.cfg`, `keepalived.conf`, `16-main.yml` do
Patroni) aparecem nos slides com **destaque da linha que está sendo explicada**. A cada
seta do teclado, o destaque passa para o próximo trecho.

Recurso nativo do reveal.js (plugin **Highlight**):

```html
<pre><code class="language-ini" data-trim data-line-numbers="|1-2|4-6|7|9-10">
<script type="text/template">
vrrp_instance VI_1 {
    state MASTER
    ...
</script>
</code></pre>
```

- `data-line-numbers="|1-2|4-6|7|9-10"`: cada trecho separado por `|` é um passo.
  O primeiro passo vazio mostra o arquivo inteiro antes de começar a destacar.
- Os passos funcionam como *fragments* do reveal.js: a seta avança o destaque antes de
  avançar o slide, e o bloco rola sozinho até a linha destacada.
- `<script type="text/template">` evita ter de escapar `<`, `>` e `&` da configuração.
- **Animação entre slides** (*auto-animate*): dois slides seguidos com o mesmo bloco
  (`data-id` igual) e uma linha diferente animam a mudança. Serve para mostrar
  `balance roundrobin` virando `balance leastconn`.

### Fonte única também para as configurações

O servidor da apresentação **lê os arquivos de configuração reais do repositório** (os
mesmos que os scripts de montagem enviam aos contêineres) e os insere nos slides ao
gerar a página. Assim, o slide nunca fica diferente do que está rodando.

Cada configuração pode ter, ao lado, um ▶ para mostrar a versão **dentro do contêiner**
(ex.: `incus exec lb1 -- cat /etc/keepalived/keepalived.conf`) ou o efeito dela
(ex.: `incus exec lb1 -- ip -br a` mostrando o IP virtual).

### No PDF

- Por padrão, o reveal.js gera **uma página por passo de destaque**
  (`pdfSeparateFragments: true`). Uma configuração com 5 passos viraria 5 páginas.
- Para a entrega, exportar com `pdfSeparateFragments: false`: **uma página por slide**,
  com o arquivo inteiro.
- O botão ▶ não funciona no PDF; os slides com comandos mostram uma saída de exemplo
  capturada num ensaio (4.5).

---

## 4.4 Painel de estado ao vivo

### Fontes dos dados (consultadas a cada ~1 s pelo `/status`)

| Informação | Fonte | Observação |
|---|---|---|
| Contêiner ligado/parado/**congelado** | API do Incus: `/1.0/instances?recursion=1` | Pelo socket `/var/lib/incus/unix.socket` |
| **CPU, memória, nº de processos, tráfego de rede** de cada contêiner | API do Incus: `/1.0/instances/<nome>/state` | São os contadores dos **cgroups** e da interface `veth`: o painel mostra o slide 48 da aula ao vivo |
| **Eventos** (parou, congelou, ligou, snapshot) | API do Incus: `/1.0/events?type=lifecycle` | Mesmo fluxo do `incus monitor --type=lifecycle`; alimenta a linha do tempo sem polling |
| **Snapshots e perfil** de cada contêiner | API do Incus: `/1.0/instances/<nome>?recursion=1` | Mostra no cartão do nó: perfil `db`, 2 snapshots |
| Quem tem o IP virtual | API do Incus: `/1.0/instances/lbX/state` (endereços da `eth0`) | Mostra o keepalived em ação sem entrar no contêiner |
| Apps no ar e tráfego por app | HAProxy: `http://lbX:8404/;csv` | Estado do health check e sessões/s de cada servidor |
| Banco: líder, réplica, *timeline*, atraso | Patroni: `GET /cluster` em qualquer `db` vivo | Um único pedido traz os dois nós |
| Membros do etcd vivos | etcd: `GET /health` em cada membro | Mostra se ainda há maioria (2 de 3) |

### O que o desenho mostra

```
                  [Windows]
                      │  tráfego HTTP (espessura = requisições/s)
                 ( IP virtual )  ── selo no lb que é o MASTER
                 ╱            ╲
             [lb1]  ⇠ VRRP ⇢  [lb2]
              │ ╲            ╱ │      pulsos = health checks (a cada 2–3 s)
           [app1]          [app2]
                 ╲        ╱
              [db1 👑] ══► [db2]       seta dupla = replicação (+ atraso em bytes)
                 ╲   etcd   ╱
                  ( 2/3 votos )        anel do etcd: membros vivos e maioria
```

| Elemento | Codificação visual |
|---|---|
| Contêiner | Verde (ligado), vermelho (parado), **azul (congelado, `incus pause`)**, amarelo (ligado mas falhando no health check) |
| **Cartão do nó (visão do Incus)** | Nome, IP, perfil, barras de **CPU e memória com o limite do cgroup**, nº de processos, nº de snapshots. O papel no cenário (👑 líder, selo do IP virtual) vem por cima |
| Tráfego real | Linha tracejada animada; espessura e velocidade pela taxa de requisições do HAProxy |
| Health checks | Pulsos periódicos do `lb` até cada servidor, no intervalo configurado; vermelho quando falha |
| IP virtual | Selo que muda de `lb1` para `lb2` |
| Líder do banco | Coroa; muda de `db1` para `db2` no failover |
| Replicação | Seta do líder para a réplica, com o atraso |
| etcd | Anel com os 3 membros e o contador "2/3 — maioria ok" ou "1/3 — sem maioria" |
| Linha do tempo | Faixa embaixo com os eventos (“14:03:12 db1 parou”, “14:03:41 db2 virou líder”) |

> **Honestidade do desenho:** os estados (ligado, líder, IP virtual, tráfego) vêm de dados
> reais. Os pulsos de health check e de VRRP são **animações no intervalo configurado**,
> coloridas pelo resultado real do último check. Vale dizer isso na apresentação.

### Layout

Slide ocupando ~60 % da tela e painel fixo à direita (~40 %). Em slides só teóricos, o
painel pode ser recolhido.

---

## 4.4.1 Cronômetros de failover

Os comandos que provocam failover ganham um **cronômetro** no painel.

| Comando | O cronômetro começa | O cronômetro para quando |
|---|---|---|
| `incus stop app1 --force` / `incus pause app1` | evento `instance-stopped` / `instance-paused` do Incus | o HAProxy marca o `app1` como DOWN |
| `incus stop lb1 --force` | evento `instance-stopped` | o IP virtual aparece no `lb2` (API do Incus) |
| `incus stop db1 --force` | evento `instance-stopped` | o `/cluster` do Patroni mostra outro líder **e** o HAProxy aponta para ele |

- O início vem dos **eventos do Incus**, não do botão. Assim o cronômetro funciona também
  quando o comando é digitado no terminal (4.4.3).
- Durante a espera, o painel mostra o que está acontecendo ("aguardando o líder expirar:
  `ttl` 30 s") para a espera virar explicação.
- Cada tempo medido vai para uma tabela que pode ser exportada e usada nos slides de
  conclusão (RTO de cada cenário).

## 4.4.2 Cgroups ao vivo mudando o balanceamento

Objetivo: mudar os limites de CPU do `app1` e do `app2` com `incus config set` durante a
apresentação e **ver o balanceamento reagir**.

### Cuidado: com `roundrobin`, o balanceamento não reage

O `roundrobin` distribui as requisições **em rodízio**, sem olhar o desempenho do
servidor. Com o `app1` limitado a 10 % de CPU, ele continuaria recebendo metade das
requisições; só ficaria **mais lento**. O que mudaria é o tempo de resposta, não a
divisão.

Para o efeito aparecer, o backend dos apps usa **`balance leastconn`**: cada requisição
nova vai para o servidor com **menos conexões abertas**. Um servidor lento segura as
conexões por mais tempo e, por isso, recebe menos requisições novas.

| Momento | Comando | O que o painel mostra |
|---|---|---|
| Início | carga ligada, sem limites | ~50 % / ~50 %; tempos de resposta iguais |
| Limitar o `app1` | `incus config set app1 limits.cpu.allowance 10ms/100ms` | barra de CPU do `app1` no teto; tráfego migra para o `app2` (ex.: 15 % / 85 %) |
| Inverter | limita o `app2`, libera o `app1` | tráfego migra de volta |
| Comparação | trocar para `roundrobin` **recarregando o HAProxy** (a API de execução não troca o algoritmo: só muda peso e estado de cada servidor, com `set server ... weight` / `state`) | divisão volta a 50/50, mas o tempo de resposta do `app1` dispara |

> O manual do HAProxy 2.8 diz que o `leastconn` "não é muito adequado" para sessões
> curtas como HTTP: com pouca concorrência, quase nunca há conexões abertas para
> comparar. Por isso o gerador precisa manter várias requisições simultâneas (abaixo).
> Se mesmo assim o efeito for fraco, a alternativa é baixar o **peso** do servidor
> limitado pela API de execução (`set server apps/app1 weight 20%`), que muda a divisão
> sem recarregar.

O contraste `roundrobin` × `leastconn` mostra que **o cgroup muda o desempenho** e que
**o algoritmo de balanceamento decide se isso afeta a divisão**.

### Requisitos para funcionar

- **O app precisa gastar CPU** em cada requisição. Uma rota `/trabalho` que faz um
  cálculo de ~10–20 ms (ex.: um laço de hash). Sem isso, o limite de CPU quase não
  muda nada.
- **Concorrência:** o gerador precisa manter várias requisições **ao mesmo tempo**
  (ex.: 20). Com uma de cada vez, nunca há "conexões abertas" para o `leastconn` comparar.
- O app roda com mais de um processo (ex.: `gunicorn -w 2`), para usar a CPU liberada.

## 4.4.3 Gerador de carga

### Opções em Python

| Opção | Como é | Prós | Contras |
|---|---|---|---|
| **Script próprio com `asyncio` + `httpx`/`aiohttp`** (recomendado) | ~40 linhas: N tarefas em laço fazendo GET em `/trabalho` e contando respostas por servidor | Controlado pela página (botões **ligar/desligar**, concorrência) e mandando os números para o painel | Precisa escrever (pouco) |
| **Locust** (`pip install locust`) | Ferramenta pronta; o comportamento do usuário é uma classe Python | Interface web com gráficos de requisições/s e tempos de resposta; modo sem interface (`--headless`) | É mais uma tela; integrar ao painel exige ler as estatísticas dele |
| `multiprocessing` + `requests` | Processos fazendo requisições síncronas | Simples de entender | Pesado: um processo por "usuário"; gasta a CPU que queremos medir |

Fora do Python, existem `hey`, `wrk`, `ab` (pacote `apache2-utils`) e `k6`, mas eles só
mostram o resultado no fim ou no terminal, sem integração com o painel.

**Recomendação:** script próprio com `asyncio` + `httpx`. Cada resposta do app já diz
`servidor: app1`, então o gerador conta a divisão real das requisições e o tempo de
resposta por servidor.

### Onde rodar o gerador: no Windows, num venv (decidido)

O gerador roda **no Windows**, num ambiente virtual Python próprio, **fora do
`incus-host`**. Assim ele não disputa a CPU da VM com os contêineres que estão sendo
medidos.

```
Windows                                         incus-host (VM)
┌──────────────────────────┐                   ┌─────────────────────────────────┐
│ venv: gerador.py         │── GET /trabalho ─►│ :8080 → network forward → IP     │
│  (asyncio + httpx)       │   (~20 ao mesmo   │ virtual :80 → HAProxy → app1/app2│
│                          │    tempo)         │                                 │
│                          │◄─ GET /carga ─────│ servidor da apresentação :9000  │
│                          │   (ligar/desligar,│  (painel e botões)              │
│                          │    concorrência)  │                                 │
│                          │── POST /carga ───►│  (números para o painel)        │
└──────────────────────────┘   estatísticas    └─────────────────────────────────┘
```

- **Alvo:** `http://localhost:8080/trabalho`, o mesmo caminho de um usuário de verdade
  (encaminhamento do VirtualBox → forward do Incus → IP virtual → HAProxy).
- **Controle pela página:** o gerador consulta o servidor da apresentação a cada
  segundo (`GET /carga`) para saber se deve estar ligado e com qual concorrência. Os
  botões **ligar/desligar** e o controle de concorrência continuam na página.
- **Números para o painel:** o gerador envia a cada segundo (`POST /carga`) as
  requisições/s e o tempo de resposta por servidor. Se esse envio falhar, o painel
  ainda tem as estatísticas do próprio HAProxy (sessões e tempos por servidor).
- **Sem a página:** o gerador também funciona sozinho pela linha de comando, com a
  saída no próprio terminal do Windows (útil para testar e para o vídeo).

### Preparar o venv no Windows (PowerShell)

```powershell
cd carga
py -m venv .venv
.venv\Scripts\python.exe -m pip install -r requirements.txt
.venv\Scripts\python.exe gerador.py --alvo http://localhost:8080 --painel http://localhost:9000
```

> Chamar `.venv\Scripts\python.exe` direto evita o `Activate.ps1`, que costuma ser
> bloqueado pela política de execução do PowerShell.

### Observações

- `--alvo` e `--painel` são parâmetros, não valores fixos no código, para o caso de a
  porta do Windows precisar mudar (porta ocupada, ver guia 01).
- O Windows e a VM **ainda dividem os núcleos físicos** do notebook (o VirtualBox
  distribui as vCPUs entre eles). Com concorrência moderada (~20) e um gerador
  assíncrono (um único processo), o efeito é pequeno, mas convém fechar outros
  programas durante a apresentação.
- O tempo de resposta medido inclui o caminho Windows → VM (NAT do VirtualBox e forward do Incus). O NAT do VirtualBox roda em software e pode limitar a vazão com muita concorrência; por isso a concorrência fica moderada. Para
  comparar `app1` × `app2` isso não importa, porque o caminho é o mesmo para os dois.

## 4.4.4 Terminal projetado

Dá para ter um terminal de verdade **dentro da página**, sem alternar janelas:

- **ttyd** (pacote `ttyd` do repositório community do Alpine 3.24, versão 1.7.7): serve
  um terminal do `incus-host` pelo navegador. Rodar com
  `ttyd -p 7681 -i eth0 -W -c usuario:senha sh`: o **`-W` é obrigatório**, porque sem
  ele o terminal é só leitura; `-i eth0` prende o ttyd à placa do NAT do VirtualBox. A página o mostra num `iframe`, como uma **gaveta** que abre embaixo
  (estilo terminal do VS Code), com fonte grande.
- Tudo o que for digitado aparece no painel, porque o painel lê o estado do Incus (eventos
  e API), não os botões. Os cronômetros também disparam (4.4.1).

| Cuidado | Solução |
|---|---|
| O terminal é um shell completo, diferente dos botões (lista fechada) | A porta do `ttyd` só é encaminhada para `127.0.0.1` do Windows (guia 01), e ainda com senha (`-c usuario:senha`); só existe durante a apresentação |
| Atalhos do reveal.js (setas, espaço) interferindo na digitação | Com o foco no `iframe` do terminal, as teclas vão para ele; um atalho (ex.: `Esc`) devolve o foco aos slides. Testar |
| Pouco espaço no projetor (1280×720) | Gaveta recolhível; painel encolhe quando o terminal abre |
| Erro de digitação ao vivo | Comandos importantes continuam também como botões; o terminal é para mostrar que é "de verdade" e para perguntas da plateia |

---

## 4.5 Tecnologias sugeridas

| Parte | Sugestão | Por quê |
|---|---|---|
| Slides | **reveal.js** | Slides em HTML; navegação por teclado; exporta para PDF (`?print-pdf`) para entregar |
| Servidor | **Python + FastAPI** (ou Flask) | Pouco código; `asyncio` para transmitir a saída dos comandos |
| Painel | **SVG + JavaScript puro** (D3 opcional) | Posições fixas dos 6 nós; só mudam cores, selos e animações |
| Saída dos comandos | Server-Sent Events | Mais simples que WebSocket para fluxo só servidor → navegador |
| Gerador de carga | `asyncio` + `httpx`, no Windows, num venv próprio | Ver 4.4.3 |
| Terminal | `ttyd` num `iframe` | Ver 4.4.4 |

### Slides: fonte única

Os slides de teoria e referências são **entregues** junto com o vídeo **e** exibidos
pelo site durante a apresentação. Para não manter duas versões:

- os slides são escritos **uma vez**, em reveal.js, dentro do site;
- o arquivo entregue é o **PDF exportado** deles (`?print-pdf` no navegador, ou a
  ferramenta `decktape`);
- nos slides com comandos, o PDF mostra o comando e uma saída de exemplo fixa (capturada
  num ensaio), já que a parte interativa não existe no PDF.

> Se o professor exigir `.pptx`, inverter: escrever no PowerPoint e exibir no site como
> imagens exportadas. Perde-se a integração com os comandos nesses slides.

### Alternativas consideradas

| Alternativa | Prós | Contras |
|---|---|---|
| **reveal.js + servidor próprio** (recomendada) | Controle total do visual e do painel; comandos seguros por lista | Mais código para escrever |
| Jupyter + RISE (slides a partir do notebook) com kernel bash | Execução de células "de graça" | Painel ao vivo difícil de fazer; visual de notebook, não de apresentação; o kernel executa qualquer comando |
| Terminal ao vivo + Grafana | Ferramentas prontas | Sem slides integrados; alternar janelas na frente da turma; muito para instalar |

---

## 4.6 Roteiro sugerido

**Parte 1: LXC/LXD (~2/3 do tempo)**

| Bloco | Conteúdo | Comandos ao vivo | Painel |
|---|---|---|---|
| 1. Contexto | Da aula: VM × contêiner, ISA × ABI; contêiner de sistema × de aplicação (Docker) | — | recolhido |
| 1b. Um Ubuntu sem núcleo de Ubuntu | Contêiner virtualiza a **ABI**: distribuição Ubuntu sobre o núcleo do Alpine (4.6.1) | `cat /etc/os-release` e `uname -r` no `app1` e no host | recolhido |
| 2. LXC e Incus | LXC = `liblxc` + `lxc-*` (mecanismo); Incus = daemon `incusd` + API REST + cliente `incus` (gerenciador), fork do LXD; Proxmox usa LXC | Um contêiner com `lxc-create -t download`/`lxc-attach` (LXC puro; no Alpine, `apk add lxc-download`) ao lado do mesmo com `incus launch` | — |
| 3. Ambiente | Windows → VirtualBox → VM → Incus; `incus admin init`: storage pool, bridge, perfil | `incus storage list`, `incus network list`, `incus profile show default` | — |
| 4. Por dentro do contêiner: namespaces | PID, net, mnt, UTS, user; contêiner sem privilégio | `incus exec app1 -- ps -ef`, `hostname`, `ip -br a`, `uid_map`; `ps -ef` no host | aparece, ainda sem o cenário |
| 5. Cgroups ao vivo | Limites de CPU e memória aplicados com o contêiner rodando | `incus config set app1 limits.cpu.allowance 20ms/100ms` + carga; `cat .../cpu.max` | barra de CPU do `app1` batendo no limite |
| 6. Congelar ≠ parar | `incus pause` usa o **freezer** do cgroup: processos existem mas não rodam | `incus pause app1`, `incus start app1` | `app1` azul; ver bloco 9 |
| 7. Montagem com Incus | Perfis, clones CoW, IPs fixos, network forward | `time incus copy app1 app3`, `btrfs subvolume list /var/lib/incus/storage-pools/default`, `incus profile show app` | `app3` surge em segundos |
| 8. Snapshots | Cópia na escrita; o "Reiniciar cenário" da apresentação é um `incus snapshot restore` | `incus snapshot create`, `incus info app1` (lista os snapshots) | contador de snapshots nos cartões |

### 4.6.1 Slide: "um Ubuntu sem núcleo de Ubuntu" (ABI na prática)

Liga o slide 16 da aula (interfaces API/ABI/ISA) ao ambiente real: a VM é **Alpine**, os
contêineres do estudo de caso são **Ubuntu 24.04**, e o núcleo é um só (doc 02, 2.2.1).

**Montagem do slide:** à esquerda, a pilha de interfaces do slide 16 (aplicações → API →
bibliotecas → ABI → SO → ISA → hardware); à direita, a mesma pilha preenchida com o
ambiente, com uma linha cortando na altura da ABI:

```
        app1 (contêiner)                     incus-host (VM)
  ┌───────────────────────────┐
  │ gunicorn, PostgreSQL      │  ← binários compilados para Ubuntu
  │ glibc, apt, systemd       │  ← espaço de usuário do Ubuntu 24.04
  ├────────── ABI ────────────┤  ← chamadas de sistema do Linux (estáveis)
  │ núcleo Linux 6.18 (Alpine)│  ← o MESMO núcleo da VM
  ├────────── ISA ────────────┤  ← x86-64, virtualizada pelo VirtualBox (VT-x)
  │ hardware virtual          │
  └───────────────────────────┘
```

**Demonstração (3 comandos, ▶ ou terminal):**

```
incus exec app1 -- cat /etc/os-release   # PRETTY_NAME="Ubuntu 24.04..."
incus exec app1 -- uname -r              # 6.18.x-0-virt
uname -r                                 # 6.18.x-0-virt  (no incus-host)
```

**Fala sugerida:** "Lá dentro tem `apt`, `systemd` e os pacotes do Ubuntu. Mas o núcleo
é o do Alpine. Funciona porque o Ubuntu só fala com o núcleo pela ABI, que o Linux
mantém estável. É o que o slide 16 diz: o contêiner virtualiza a ABI. A VM, uma camada
abaixo, virtualiza a ISA."

**Ganchos com a aula:**

| Slide da aula | Gancho |
|---|---|
| 16 (Interfaces API/ABI/ISA) | o corte acontece na ABI: tudo acima é Ubuntu, tudo abaixo é o host |
| 17 (Tipos de VM) | contêiner = "VM de processo, com ressalvas": mesma ISA, ABI compartilhada |
| 46 (VM × contêiner, "mesmo núcleo do hospedeiro") | dá para trocar a distribuição, não o núcleo: nada de Windows nem de módulo de núcleo próprio |
| 49 (Imagens em camadas) | a imagem Ubuntu tem só o sistema de arquivos (~142 MB, sem núcleo); os 6 contêineres são clones CoW dela |
| 52 (Segurança, "falha no núcleo atinge todos") | os 6 contêineres Ubuntu dependem do núcleo e das proteções do **Alpine** (sem AppArmor, doc 02) |

**Contraste para fechar:** o mesmo `incus launch` com `--vm` traria o núcleo do Ubuntu
junto (VM QEMU/KVM), e aí `uname -r` mudaria. No ambiente isso exigiria virtualização
aninhada (slide 43), por isso fica só como comentário.

**Parte 2: o cenário com balanceamento e alta disponibilidade (~1/3)**

| Bloco | Conteúdo | Comandos ao vivo | Painel |
|---|---|---|---|
| 9. Balanceamento | 6 contêineres, HAProxy (brevemente) | laço de `curl`; `incus pause app1` (congelado não responde ao health check) | tráfego alternando; depois todo no `app2` |
| 10. Falha do balanceador | keepalived; o IP virtual muda de **namespace de rede** | `incus stop lb1 --force`; `incus list` mostra o IP virtual no `lb2` | selo do IP virtual pula |
| 11. Falha do banco | Patroni + etcd (brevemente: maioria de 3) | `incus stop db1 --force` | coroa passa para o `db2` em ~30 s; cronômetro |
| 12. Volta e limite | `incus start db1` volta como réplica; falha dupla `lb1` + `db1` | `incus start`, dois `incus stop` | etcd "1/3 — sem maioria" |
| 13. Conclusão | O que o Incus deu ao projeto (tabela abaixo), tempos medidos, limitações | — | — |

Tabela de fechamento sugerida: **"o que cada recurso do Incus fez no projeto"**

| Recurso do Incus | Uso no projeto |
|---|---|
| Imagens + `incus launch` | Criar os servidores em segundos |
| Perfis | Configuração por função (`lb`, `app`, `db`) |
| `incus copy` (clone CoW) | `lb2`, `app2`, `db2` a partir dos primeiros |
| Limites (cgroups) | CPU e memória por contêiner |
| `incus pause` (freezer) | Simular servidor travado |
| Snapshots | Reiniciar o cenário entre os testes |
| Bridge + IPs fixos + network forward | Rede do cenário e acesso pelo Windows |
| `boot.autostart` + prioridade | Religar tudo na ordem certa depois de reiniciar a VM |
| API REST + eventos | Painel da própria apresentação |

---

## 4.6.2 Lição da montagem: `apt upgrade` desfaz o copy-on-write

O que aconteceu: rodar `apt upgrade` dentro dos contêineres fez cada um ocupar **~700 MB
próprios**, só com os pacotes atualizados. Já na fase 1 (3 contêineres) o `.ova` da VM
ficou com **2 GB**; com 6 contêineres, o disco da VM (VDI dinâmico) cresceria demais.
Evidência: `btrfs filesystem du` antes e depois de recriar (doc 05, 1.13, itens 1 e 5).

Por quê: cada contêiner nasce como **clone CoW** da imagem Ubuntu no btrfs e, no começo,
compartilha todos os blocos com ela (por isso o clone é instantâneo e quase não ocupa
espaço). O `apt upgrade` reescreve centenas de arquivos de `/usr`, e cada bloco
reescrito vira **cópia própria** daquele contêiner. Os 6 atualizam os mesmos pacotes,
mas cada um paga a sua cópia: o compartilhamento se perde. E o VDI dinâmico só cresce:
apagar arquivos depois não devolve o espaço ao Windows.

Decisão: **recriar** os contêineres (e a VM) **sem `apt upgrade`**, só com
`apt update` + `apt install` do que cada função precisa. O VDI fica pequeno e o
`.ova` continua fácil de copiar.

**Gancho com a aula:** slides 40 (snapshots e clones) e 49 (imagens em camadas). O
ganho do CoW vale enquanto ninguém escreve; o custo aparece por contêiner, na escrita.
É o mesmo motivo de, no Docker, a atualização ir para uma **imagem nova** em vez de
cada contêiner se atualizar sozinho.

---

## 4.7 Riscos e mitigações

| Risco | Mitigação |
|---|---|
| Demonstração falhar ao vivo | **Vídeo** (já planejado) e **modo gravado:** o servidor grava a sequência de `/status` nos ensaios e o painel reproduz sem os contêineres |
| Failover de ~30 s parecer "travado" | Mostrar um cronômetro no painel e o `ttl` do Patroni; aproveitar para explicar a espera |
| Ambiente bagunçado depois de um teste | **Reiniciar cenário:** parar os 6, `incus snapshot restore` de todos no mesmo snapshot (o etcd está nos snapshots, então o estado fica coerente) e ligar de novo |
| Computador da apresentação sem admin / com Hyper-V (VirtualBox lento, "tartaruga") | Ensaiar **no mesmo computador**; VM ligada com `--type headless`; se ficar lento demais, apresentar do notebook pessoal ou usar o vídeo |
| Notebook lento com tudo ligado | VM Alpine de 2–3 GB comporta os 6 contêineres (doc 03, T17); fechar outros programas; ensaiar no mesmo notebook |
| Projetor com resolução baixa | Layout testado em 1280×720; fonte grande no painel |

---

## 4.8 Esforço estimado

| Parte | Tamanho aproximado |
|---|---|
| Servidor (comandos, SSE, `/status`) | 200–300 linhas de Python |
| Painel (SVG + animação) | 300–500 linhas de JS/CSS |
| Slides (reveal.js) | Conteúdo; o código é pouco |
| Modo gravado | +100 linhas |

Depende de o estudo de caso (doc 03) estar montado e funcionando: o painel só pode ser
testado com os 6 contêineres no ar.

---

## 4.9 Decisões tomadas

- **Entregas:** slides de teoria e referências + vídeo + apresentação. Os slides são
  exibidos pelo site e entregues em **PDF exportado pelo reveal.js** (fonte única, 4.5).
- **Botão ▶ ao lado** de cada comando (4.3).
- **Configurações nos slides com destaque de linha** passo a passo, lidas dos arquivos
  reais do repositório (4.3.1).
- **Vídeo** de reserva, caso a demonstração ao vivo falhe.
- **Terminal projetado** dentro da página (ttyd, 4.4.4).
- **Cronômetros** nos comandos que provocam failover (4.4.1).
- **Cgroups ao vivo** no `app1`/`app2` com `leastconn` e gerador de carga (4.4.2, 4.4.3).
- **Gerador de carga no Windows**, num venv separado, fora do `incus-host` (4.4.3).
- **Contêineres sem `apt upgrade`**, para não perder o compartilhamento CoW nem inchar
  o VDI (4.6.2).

## 4.10 Em aberto

- Painel em **SVG simples** ou algo mais elaborado (D3, animações de pacotes)?
- Comparação `roundrobin` × `leastconn` por recarga do HAProxy ou por peso na API de
  execução (4.4.2): decidir depois do teste T10 do doc 03.

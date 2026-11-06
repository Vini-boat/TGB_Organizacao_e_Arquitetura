# 4. Ideias para a apresentação

> **Status:** proposta, ainda não implementada.

## 4.1 Objetivo

Uma apresentação **interativa numa página web**, no estilo de um *notebook*:

1. os slides mostram comandos (`lxc stop db1 --force`, `patronictl list`...) que podem
   ser **executados ali mesmo**, com a saída aparecendo logo abaixo;
2. um **painel de estado ao vivo**, sempre visível, mostra quem está de pé e quem está
   se comunicando com quem (tráfego, health checks, replicação, votos do etcd).

A ideia é que a plateia **veja** o failover acontecer: o `db1` fica vermelho, as setas
de health check falham, o IP virtual pula de contêiner e o `db2` ganha a coroa de líder.

---

## 4.2 Arquitetura da solução

```
Navegador (Windows / projetor)
   │  http://<IP-da-VM>:9000
   ▼
┌──────────────────────────── lxd-host (VM) ────────────────────────────┐
│                                                                       │
│  servidor da apresentação (Python, roda NO HOST, fora dos contêineres)│
│   ├── GET  /            → página (slides + painel)                    │
│   ├── POST /run/<id>    → executa um comando da lista permitida       │
│   ├── GET  /stream/<id> → saída do comando em tempo real (SSE)        │
│   └── GET  /status      → JSON com o estado dos 6 contêineres         │
│          │                                                            │
│          ├── API do LXD (socket unix)  → contêiner ligado/desligado,  │
│          │                               IPs (quem tem o IP virtual)  │
│          ├── HAProxy :8404/;csv        → estado e tráfego dos apps/dbs│
│          ├── Patroni :8008/cluster     → líder, réplica, atraso       │
│          └── etcd :2379/health         → membros do etcd vivos        │
│                                                                       │
│  lb1  lb2  app1  app2  db1  db2   (contêineres)                       │
└───────────────────────────────────────────────────────────────────────┘
```

**Decisão importante:** o servidor da apresentação roda **no `lxd-host`, não num
contêiner**. Ele é o "observador externo": continua funcionando enquanto os contêineres
são derrubados de propósito, e só ele tem acesso ao comando `lxc`.

---

## 4.3 Execução dos comandos (o "notebook")

- Cada bloco de comando no slide tem um botão **▶ Executar**.
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
    "derruba-db1":   ["lxc", "stop", "db1", "--force"],
    "liga-db1":      ["lxc", "start", "db1"],
    "patroni-list":  ["lxc", "exec", "db2", "--", "patronictl", "-c", "/etc/patroni/config.yml", "list"],
    "uid-map":       ["lxc", "exec", "app1", "--", "cat", "/proc/self/uid_map"],
}
```

---

## 4.4 Painel de estado ao vivo

### Fontes dos dados (consultadas a cada ~1 s pelo `/status`)

| Informação | Fonte | Observação |
|---|---|---|
| Contêiner ligado/desligado | API do LXD: `/1.0/instances?recursion=1` | Pelo socket `/var/snap/lxd/common/lxd/unix.socket` |
| Quem tem o IP virtual | API do LXD: `/1.0/instances/lbX/state` (endereços da `eth0`) | Mostra o keepalived em ação sem entrar no contêiner |
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
| Contêiner | Verde (ligado), vermelho (parado), amarelo (ligado mas falhando no health check) |
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

## 4.5 Tecnologias sugeridas

| Parte | Sugestão | Por quê |
|---|---|---|
| Slides | **reveal.js** | Slides em HTML; navegação por teclado; exporta para PDF (`?print-pdf`) para entregar |
| Servidor | **Python + FastAPI** (ou Flask) | Pouco código; `asyncio` para transmitir a saída dos comandos |
| Painel | **SVG + JavaScript puro** (D3 opcional) | Posições fixas dos 6 nós; só mudam cores, selos e animações |
| Saída dos comandos | Server-Sent Events | Mais simples que WebSocket para fluxo só servidor → navegador |

### Alternativas consideradas

| Alternativa | Prós | Contras |
|---|---|---|
| **reveal.js + servidor próprio** (recomendada) | Controle total do visual e do painel; comandos seguros por lista | Mais código para escrever |
| Jupyter + RISE (slides a partir do notebook) com kernel bash | Execução de células "de graça" | Painel ao vivo difícil de fazer; visual de notebook, não de apresentação; o kernel executa qualquer comando |
| Terminal ao vivo + Grafana | Ferramentas prontas | Sem slides integrados; alternar janelas na frente da turma; muito para instalar |

---

## 4.6 Roteiro sugerido

| Bloco | Conteúdo | Comandos ao vivo | Painel |
|---|---|---|---|
| 1. Contexto | Da aula: VM × contêiner, ISA × ABI | — | recolhido |
| 2. Ambiente | Windows → Hyper-V → VM → LXD → contêineres | `lxc list`, `multipass info` | aparece com os 6 verdes |
| 3. Por dentro do contêiner | Namespaces, cgroups, contêiner sem privilégio | `ps -ef`, `uid_map`, `cpu.max` | — |
| 4. Montagem com LXD | Perfis, clones CoW, snapshots | `lxc copy`, `zfs list` | — |
| 5. Balanceamento | HAProxy, round-robin | laço de `curl` | tráfego alternando entre `app1`/`app2` |
| 6. Falha de app | — | `lxc stop app1 --force` | `app1` vermelho; tráfego todo no `app2` |
| 7. Falha do balanceador | keepalived, VRRP | `lxc stop lb1 --force` | IP virtual pula para o `lb2` |
| 8. Falha do banco | Patroni, etcd, quórum | `lxc stop db1 --force` | coroa passa para o `db2` em ~30 s |
| 9. Volta | `pg_rewind` | `lxc start db1` | `db1` volta como réplica |
| 10. Limite do projeto | Falha dupla `lb1` + `db1` | os dois `stop` | etcd "1/3 — sem maioria" |
| 11. Conclusão | Tabela de tempos medidos; limitações | — | — |

---

## 4.7 Riscos e mitigações

| Risco | Mitigação |
|---|---|
| Demonstração falhar ao vivo | **Modo gravado:** o servidor grava a sequência de `/status` nos ensaios e o painel reproduz sem os contêineres. Ter também um vídeo curto de cada demo |
| Failover de ~30 s parecer "travado" | Mostrar um cronômetro no painel e o `ttl` do Patroni; aproveitar para explicar a espera |
| Ambiente bagunçado depois de um teste | **Reiniciar cenário:** parar os 6, `lxc restore` de todos no mesmo snapshot (o etcd está nos snapshots, então o estado fica coerente) e ligar de novo |
| IP da VM mudar depois de reiniciar o Windows | Conferir `multipass list` antes de apresentar; a página usa endereços relativos |
| Notebook lento com tudo ligado | VM de 4 GB comporta os 6 contêineres; fechar outros programas; ensaiar no mesmo notebook |
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

## 4.9 Em aberto

- Os slides vão ser **entregues** em algum formato (PDF, .pptx)? O reveal.js exporta
  PDF, mas sem a parte interativa.
- Vai haver uma **projeção do terminal** além da página, ou tudo pela página?
- Painel em **SVG simples** ou algo mais elaborado (D3, animações de pacotes)?

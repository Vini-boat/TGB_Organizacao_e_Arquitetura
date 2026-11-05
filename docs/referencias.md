# Referências para estudo

Referências levantadas para o referencial teórico do Trabalho GB
(Assunto 3: servidores com contêineres LXC/LXD, balanceamento de carga e disponibilidade).

As marcadas com ⭐ são as prioritárias.

> **Aviso:** desta lista, só os resumos e metadados foram conferidos.
> Antes de colocar números de benchmark nos slides, confira no texto completo.

---

## Ordem de leitura sugerida

1. Popek & Goldberg (só a introdução) e o capítulo de virtualização do Tanenbaum
2. Kerrisk: *Namespaces in operation*
3. Felter et al. (IBM)
4. Silva, Rafael & Fonte (MDPI 2024) e Mendes & Duarte (ERBASE 2019)

---

## 1. Fundamentos de virtualização

| Referência | Uso no trabalho |
|---|---|
| ⭐ Popek & Goldberg (1974) | Definição formal de máquina virtual e de VMM (hipervisor). Abertura do referencial |
| Tanenbaum & Bos | Base didática em português: hipervisores tipo 1/2 e contêineres |
| Smith & Nair (2005) | Livro de referência sobre máquinas virtuais |

- ⭐ POPEK, Gerald J.; GOLDBERG, Robert P. Formal requirements for virtualizable third generation architectures. **Communications of the ACM**, v. 17, n. 7, p. 412–421, 1974. DOI: 10.1145/361011.361073. Disponível em: <https://cs.umb.edu/~hdeblois/1974Popek.pdf>.
- TANENBAUM, Andrew S.; BOS, Herbert. **Sistemas operacionais modernos**. 4. ed. São Paulo: Pearson, 2016. Capítulo 7: Virtualização e a nuvem.
- SMITH, James E.; NAIR, Ravi. **Virtual machines**: versatile platforms for systems and processes. San Francisco: Morgan Kaufmann, 2005.

## 2. Contêineres vs. máquinas virtuais

| Referência | Uso no trabalho |
|---|---|
| ⭐ Soltesz et al. (2007) | Artigo fundador da virtualização em nível de SO (Linux-VServer vs. Xen) |
| ⭐ Felter et al. (2015) | Artigo mais citado: contêineres igualam ou superam as VMs (KVM) em quase todos os casos |
| Morabito et al. (2015) | KVM vs. LXC vs. Docker vs. OSv: CPU, memória, disco e rede |
| Bernstein (2014) | Evolução histórica LXC → Docker → Kubernetes (linha do tempo) |
| Dua et al. (2014) | Contêineres no contexto de nuvem (PaaS) |

- ⭐ SOLTESZ, Stephen et al. Container-based operating system virtualization: a scalable, high-performance alternative to hypervisors. In: EUROPEAN CONFERENCE ON COMPUTER SYSTEMS (EuroSys), 2007, Lisboa. **Proceedings** [...]. New York: ACM, 2007. p. 275–287. DOI: 10.1145/1272996.1273025. Disponível em: <https://www.cs.jhu.edu/~huang/cs718/spring20/readings/container.pdf>.
- ⭐ FELTER, Wes et al. An updated performance comparison of virtual machines and Linux containers. In: IEEE INTERNATIONAL SYMPOSIUM ON PERFORMANCE ANALYSIS OF SYSTEMS AND SOFTWARE (ISPASS), 2015, Philadelphia. **Proceedings** [...]. IEEE, 2015. p. 171–172. DOI: 10.1109/ISPASS.2015.7095802. Relatório completo disponível em: <https://www.read.seas.harvard.edu/~kohler/class/cs260r-s19/containerperf14.pdf>.
- MORABITO, Roberto; KJÄLLMAN, Jimmy; KOMU, Miika. Hypervisors vs. lightweight virtualization: a performance comparison. In: IEEE INTERNATIONAL CONFERENCE ON CLOUD ENGINEERING (IC2E), 2015, Tempe. **Proceedings** [...]. IEEE, 2015. p. 386–393. DOI: 10.1109/IC2E.2015.74. Disponível em: <https://faculty.washington.edu/wlloyd/courses/tcss562/research_papers/T3_Hypervisors_vs_Lightweight_Virtualization_A_Performance_Comparison.pdf>.
- BERNSTEIN, David. Containers and cloud: from LXC to Docker to Kubernetes. **IEEE Cloud Computing**, v. 1, n. 3, p. 81–84, set. 2014. DOI: 10.1109/MCC.2014.51.
- DUA, Rajdeep; RAJA, A. Reddy; KAKADIA, Dharmesh. Virtualization vs containerization to support PaaS. In: IEEE INTERNATIONAL CONFERENCE ON CLOUD ENGINEERING (IC2E), 2014, Boston. **Proceedings** [...]. IEEE, 2014. p. 610–614. DOI: 10.1109/IC2E.2014.41.

## 3. LXC/LXD (aprofundamento)

| Referência | Uso no trabalho |
|---|---|
| ⭐ Silva, Rafael & Fonte (2024) | **Mais alinhado ao tema.** Contêiner de sistema (LXD) vs. de aplicação (Docker); LXD com desempenho mais estável |
| ⭐ Mendes & Duarte (2019) | **Em português (SBC).** Comparativo Docker vs. LXC/LXD |
| Xavier et al. (2013) | LXC vs. OpenVZ vs. VServer vs. Xen em HPC; autores brasileiros (PUCRS) |
| Azevedo Neto (2025) | **Em português.** LXC e Docker dentro de VMs (AWS), parecido com o cenário no Multipass |
| Aqasizade et al. (2024) | Contêineres rodando sobre VMs, a mesma arquitetura do trabalho (Windows → Hyper-V → VM → LXD) |
| Shrestha (2019) | Dissertação de mestrado (não revisada por pares): KVM vs. LXC/LXD |
| Canonical (2015) | Benchmark **do próprio fabricante** (LXD vs. KVM); citar deixando isso claro |

- ⭐ SILVA, Daniel; RAFAEL, João; FONTE, Alexandre. Toward optimal virtualization: an updated comparative analysis of Docker and LXD container technologies. **Computers**, v. 13, n. 4, art. 94, 2024. DOI: 10.3390/computers13040094. Disponível em: <https://www.mdpi.com/2073-431X/13/4/94>.
- ⭐ MENDES, Antonio; DUARTE, Angelo. Comparativo entre Docker e LXC/LXD para a virtualização. In: ESCOLA REGIONAL DE COMPUTAÇÃO BAHIA, ALAGOAS E SERGIPE (ERBASE), 2019, Ilhéus. **Anais** [...]. Porto Alegre: SBC, 2019. p. 295–303. Disponível em: <https://sol.sbc.org.br/index.php/erbase/article/view/8990>.
- XAVIER, Miguel G. et al. Performance evaluation of container-based virtualization for high performance computing environments. In: EUROMICRO INTERNATIONAL CONFERENCE ON PARALLEL, DISTRIBUTED AND NETWORK-BASED PROCESSING (PDP), 21., 2013, Belfast. **Proceedings** [...]. IEEE, 2013. p. 233–240. DOI: 10.1109/PDP.2013.41.
- AZEVEDO NETO, Paulo Aragão de. **Análise de desempenho de contêineres LXC e Docker em ambiente virtual**. 2025. 44 f. Trabalho de Conclusão de Curso (Graduação em Redes de Computadores) – Universidade Federal do Ceará, Campus Quixadá, 2025. Disponível em: <http://repositorio.ufc.br/handle/riufc/82629>.
- AQASIZADE, Hossein et al. **Experimental assessment of containers running on top of virtual machines**. arXiv:2401.07539, 2024. Disponível em: <https://arxiv.org/abs/2401.07539>.
- SHRESTHA, Salina. **A performance comparison between hypervisors and lightweight virtualization**. 2019. Dissertação (Mestrado) – Tribhuvan University, Nepal, 2019. Disponível em: <https://elibrary.tucl.edu.np/items/24e81f64-1c12-49a5-b4b3-08bf39571b82>.
- CANONICAL. **LXD crushes KVM in density and speed**. 2015. Disponível em: <https://canonical.com/blog/lxd-crushes-kvm-in-density-and-speed>.

## 4. Mecanismos do kernel Linux (namespaces e cgroups)

- ⭐ KERRISK, Michael. Namespaces in operation, part 1: namespaces overview. **LWN.net**, 4 jan. 2013. Disponível em: <https://lwn.net/Articles/531114/>. (Série completa, partes 1 a 7: <https://man7.org/articles/>.)
- LINUX MAN-PAGES PROJECT. **namespaces(7)** e **cgroups(7)**. Disponível em: <https://man7.org/linux/man-pages/man7/namespaces.7.html> e <https://man7.org/linux/man-pages/man7/cgroups.7.html>.
- THE LINUX KERNEL DOCUMENTATION. **Control Group v2**. Disponível em: <https://docs.kernel.org/admin-guide/cgroup-v2.html>.

## 5. Documentação oficial e material prático

- CANONICAL. **LXD documentation**. Disponível em: <https://documentation.ubuntu.com/lxd/>. (Instâncias, perfis, storage, redes, clustering.)
- LINUX CONTAINERS. **LXC e Incus**. Disponível em: <https://linuxcontainers.org/>.
- HAPROXY TECHNOLOGIES. **HAProxy documentation**. Disponível em: <https://docs.haproxy.org/>. (Algoritmos de balanceamento e *health checks*.)
- Tutorial: **Conquer the Web with a Powerful Server Squad: Building a Load-Balanced LXC/LXD Container Cluster**. Hashnode. Disponível em: <https://hashnode.com/posts/conquer-the-web-with-a-powerful-server-squad/63de17af2f21c58845cbdb6a>. (Cenário parecido com o estudo de caso.)

---

## Lacunas conhecidas

- Não foi encontrado artigo revisado por pares sobre **HAProxy + keepalived** (balanceamento + alta disponibilidade).
  Para essa parte, usar a documentação oficial do HAProxy e livros de SO e redes.
- Os artigos da IEEE (Felter, Morabito, Bernstein, Dua, Xavier) podem ser acessados pelo
  **Portal de Periódicos CAPES** usando a rede ou o login da Unisinos.

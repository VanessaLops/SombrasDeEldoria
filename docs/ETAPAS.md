# Etapas de desenvolvimento: Sombras de Eldoria

MOBA 5v5 para iOS (mecânica no estilo League of Legends: Wild Rift), ambientado no universo do livro
*Sombras de Eldoria: O Despertar das Sombras* (Wattpad, VanessaLP777). O mapa **não** é o Summoner's Rift:
ele segue a geografia e os eventos do livro (ver [MAPA e personagens](PERSONAGENS.md)).

Documento vivo. É atualizado ao fim de cada fase e consolidado na **Fase 7**.

**Legenda:** ✅ concluído · 🔄 em andamento · ⬜ pendente

| Fase | Nome | Duração estimada | Status |
|---|---|---|---|
| 0 | Pré-produção e decisões técnicas | 2 semanas | ⬜ |
| 1 | Protótipo: 1 herói, 1 arena | 3–4 semanas | ⬜ |
| 2 | Combate e habilidades (1v1 contra bot) | 4 semanas | ⬜ |
| 3 | Mapa de Aetheria, objetivos e 5v5 contra bots | 5–6 semanas | ⬜ |
| 4 | Roster, itens e economia | 5–6 semanas | ⬜ |
| 5 | Multiplayer online | 6–8 semanas | ⬜ |
| 6 | Meta-jogo, progressão e loja | 4–5 semanas | ⬜ |
| 7 | Arte final, áudio, beta e lançamento | 6–8 semanas | ⬜ |

---

## Definição de pronto (vale para toda fase)

- [ ] Testes automatizados passam e toda regra nova do núcleo de simulação tem teste
- [ ] Build sem **nenhum** warning
- [ ] Jogado no Simulador **e** em um iPhone físico
- [ ] 60 fps estáveis (iPhone 12 ou mais recente) no Instruments; consumo de bateria e temperatura medidos
- [ ] Números de balanceamento só em arquivos de dados/tuning, nunca espalhados no código
- [ ] `docs/ARQUITETURA.md` atualizado se a estrutura mudou
- [ ] Este documento atualizado (status, entregas, aprendizados)

---

## Premissas de design

- **Partida:** 5v5, 15 a 20 minutos, vitória ao destruir a **Torre da Convergência** inimiga (equivalente ao Nexus).
- **Facções:** *Guardiões da Luz* (base em Aetherheart) contra *Sombras do Abismo* (base no Deserto das Tempestades).
  Ambas jogáveis: o livro diz que os dez heróis são as duas coisas ao mesmo tempo.
- **Controles mobile:** joystick virtual à esquerda; à direita, ataque básico, 3 habilidades, ultimate, feitiços
  de invocador (2) e loja; mira por arrasto; ping e chat rápido.
- **Arquitetura (mesmo princípio do Últimos Dias):** `SimCore` (pacote Swift puro, determinístico, sem UI,
  100% testável) → `GameEngine` (render, input, áudio) → `App` (menus, SwiftUI). O mesmo `SimCore` roda no
  servidor e no cliente.
- **Servidor autoritativo** com predição no cliente. Nada de confiar no aparelho para dano, ouro ou posição.

> ⚠️ **Fidelidade ao livro:** o texto lido tem 9 capítulos e apenas 7 heróis nomeados (a sinopse promete 10),
> além de inconsistências (Eldoria × Aetheria; Kaelith é mulher nos caps. 4–6 e vilão masculino no cap. 7).
> Os heróis que faltam são **criação nossa**, marcados como tal em `PERSONAGENS.md`. Decisões de adaptação
> ficam registradas na Fase 0.

---

## Fase 0: Pré-produção e decisões técnicas ⬜

**Pergunta que a fase responde:** o que exatamente vamos construir, com qual tecnologia, e o que cabe em um time pequeno?

### Entregas
- [ ] **ADR 001: motor.** Opções: (a) Swift nativo + SpriteKit/Metal, coerente com o Últimos Dias, controle total e
      iOS-only; (b) Unity, melhor para câmera 3D/MOBA, animação e Android futuro. Decidir com um teste de 1 semana
      de 10 unidades em tela em ambos. Critérios: fps em iPhone 12, custo de arte 3D vs 2D, plano Android
- [ ] **ADR 002: rede.** Servidor autoritativo (UDP/QUIC), tick de 30 Hz, snapshots delta, predição e reconciliação
- [ ] **ADR 003: estilo visual** (2D isométrico estilizado vs 3D low-poly) alinhado ao orçamento de arte
- [ ] **Documento de design do jogo (GDD)**: loop da partida, economia, regras de torre/objetivos, condições de vitória
- [ ] **Bíblia do livro** (`PERSONAGENS.md`): personagens, locais, facções e itens; lista das lacunas a preencher
- [ ] **Decisão de adaptação** das contradições (Kaelith, Eldoria × Aetheria, Herdeiro × Herdeira)
- [ ] Estrutura do repositório, CI, testes, lint e política de zero warnings
- [ ] Estimativa de custos de servidor e plano de monetização ética (sem pay-to-win)

### Riscos
- Escopo de MOBA é enorme; mitigação: cortar para 10 heróis, 1 mapa e 1 modo no lançamento.

---

## Fase 1: Protótipo, 1 herói em 1 arena ⬜

**Pergunta que a fase responde:** mover e atacar com o dedo, em tela de celular, já é gostoso?

### Entregas
- [ ] Pacote `SimCore` com ECS próprio, relógio de simulação em passo fixo (30 Hz) e geração de eventos
- [ ] Herói jogável: **Alaric, o Tecelão de Éter** (movimento, ataque básico com alcance, vida e mana)
- [ ] Câmera de MOBA (seguindo o herói, com zoom e arrasto para espiar)
- [ ] Joystick virtual + botão de ataque; alvo automático no inimigo mais próximo e toque para escolher alvo
- [ ] Pathfinding (navmesh ou grade) com desvio de obstáculos e colisão entre unidades
- [ ] Névoa de guerra básica (visão por unidade)
- [ ] Boneco de treino que causa dano; HUD de vida/mana
- [ ] Testes: matemática, colisão, pathfinding, passo fixo determinístico (mesma semente → mesmo resultado)

### Validação
- Jogar 5 minutos no iPhone físico e anotar incômodos de controle.

---

## Fase 2: Combate e habilidades (1v1 contra bot) ⬜

**Pergunta que a fase responde:** as habilidades criam duelos com decisão, contra-jogo e habilidade?

### Entregas
- [ ] Sistema de habilidades orientado a dados: alvo, direcional, área, passiva, dash, canalizada
- [ ] Recursos: mana/energia, recarga, redução de recarga, custo
- [ ] Efeitos de status: atordoar, lentidão, silêncio, escudo, cura, derrubada, marcação
- [ ] Projéteis, áreas e colisões com tempo de conjuração e cancelamento
- [ ] Indicadores de mira por arrasto (cone, linha, círculo) com *quick cast*
- [ ] Alaric completo: passiva, 3 habilidades e ultimate; segundo herói de teste (**Lyara**, guerreira) para validar contra-jogo
- [ ] Fórmulas de dano (físico, mágico, verdadeiro), armadura, resistência mágica, crítico, roubo de vida
- [ ] IA de bot básica (lane, trocar golpes, fugir com pouca vida)
- [ ] Esbirros com ondas, XP e níveis 1–15 (pontos de habilidade)
- [ ] Números flutuantes de dano, barras de vida, efeitos visuais e sons provisórios
- [ ] Testes de cada regra de dano/status e partida simulada sem interface

---

## Fase 3: Mapa de Aetheria, objetivos e 5v5 contra bots ⬜

**Pergunta que a fase responde:** o mapa do livro cria estratégia própria, sem copiar o Rift?

### Entregas
- [ ] **Mapa "Aetheria"** (simétrico, ver proposta em `PERSONAGENS.md`):
      - Base Guardiões: **Aetherheart** / Base Sombras: **Torre da Convergência**
      - Duas rotas principais longas (**Rota de Eryndor**, floresta, e **Rota das Planícies Cinzentas**)
        e uma **zona central, o Véu**, com portais que ligam pontos do mapa (mecânica de teleporte tática)
      - Torres, inibidores e esbirros de cada rota, selva com monstros neutros
- [ ] **Quatro Relíquias do Círculo de Eternidade** como objetivos neutros nos quadrantes
      (Luz, Sombra, Vida, Morte), cada uma com buff de equipe diferente, mais um objetivo final
      que reúne as quatro (**Fissura / Coração de Aether**)
- [ ] Monstros da selva e guardiões de objetivo (Horrores do Véu, espectros de Tharlin)
- [ ] Loja na base, recall, regeneração na fonte, respawn com tempo crescente
- [ ] Névoa de guerra completa, arbustos/esconderijos, sentinelas de visão
- [ ] Pings e comunicação rápida (perigo, ajuda, indo, falta de mana)
- [ ] IA de bots para 5 papéis (rotas, selva, apoio) com 3 níveis de dificuldade
- [ ] Minimapa, placar, tela de vitória/derrota com estatísticas
- [ ] Partida 5v5 completa contra bots e tutorial guiado de 8 minutos
- [ ] Desempenho: 10 heróis + 60 esbirros + efeitos a 60 fps em iPhone 12

### Validação
- Partida completa em aparelho físico e telemetria de duração (alvo 15–20 min).

---

## Fase 4: Roster, itens e economia ⬜

**Pergunta que a fase responde:** cada herói é único, e o conjunto é equilibrado?

### Entregas
- [ ] **10 heróis jogáveis no lançamento** (7 do livro + 3 expandidos), cada um com papel e kit próprios:

| Herói | Papel | Facção | Origem |
|---|---|---|---|
| Alaric, Tecelão de Éter | Mago / Controle | Luz | Livro |
| Lyara | Guerreira / Frontal | Luz | Livro |
| Kaelith, Herdeira das Sombras | Atiradora (arco) | Luz | Livro |
| Eryon, Portador do Fluxo | Assassino / Mobilidade (tempo e espaço) | Luz | Livro |
| Saria | Suporte / Alquimista | Luz | Livro |
| Kael, o Arqueiro | Atirador de alcance | Luz | Livro |
| Nyssa, a Druida | Suporte-Controle / Invocadora | Luz | Livro |
| Nyx, a Sombra que Caminha | Assassina / Furtividade | Sombras | Livro (guia ambígua) |
| Kallindra, Alta-Maga | Maga de dano em área | Sombras | Livro (aliada ambígua) |
| Korrath, General das Sombras | Tanque / Iniciador | Sombras | Livro (vilão final) |

      Reserva para pós-lançamento: Valen, Serak, Lorde Maerok, o Arquidruida, o Guardião de Aether.
- [ ] Cada herói: passiva, 3 habilidades, ultimate, 4 visuais de habilidade, fala e falas de eliminação
- [ ] **Itens:** ~60 itens em 3 níveis (ataque, magia, defesa, utilitários, botas), árvore de receita, loja com recomendação
- [ ] **Ouro:** passivo, abates, esbirros, objetivos, assistências, bounty
- [ ] **Feitiços de invocador** (Salto, Cura, Barreira, Purificar, Fantasma, Punir)
- [ ] Runas/talentos simples, 1 página no lançamento
- [ ] Ferramenta de balanceamento: simulação em lote (bot × bot, milhares de partidas) com tabela de taxa de vitória
- [ ] Modo treino com bonecos e rotação gratuita semanal

---

## Fase 5: Multiplayer online ⬜

**Pergunta que a fase responde:** 10 pessoas jogam bem em 4G e Wi-Fi, sem trapaça?

### Entregas
- [ ] Servidor de partida (reaproveita `SimCore`), tick 30 Hz, snapshots delta, lag compensation
- [ ] Predição do cliente, reconciliação e interpolação das outras unidades
- [ ] Reconexão no meio da partida, tratamento de abandono e substituição por bot
- [ ] Contas (Sign in with Apple, Game Center), perfil e amigos
- [ ] **Matchmaking** por MMR com filas (rápida e ranqueada), seleção de herói e banimentos
- [ ] Lobby, pré-partida (escolha, runas, feitiços), espectador simples
- [ ] Anti-cheat de servidor, validação de comandos, limite de taxa, logs de partida e replay
- [ ] Sistema de denúncias, silenciar jogadores, filtro de chat
- [ ] Testes de carga (milhares de partidas simuladas), perda de pacote e latência artificiais (200 ms, 5% de perda)
- [ ] Observabilidade: métricas de tick, ping médio, desconexões, crash

### Validação
- Teste fechado com 20 pessoas, partidas reais em redes diferentes.

---

## Fase 6: Meta-jogo, progressão e loja ⬜

**Pergunta que a fase responde:** por que o jogador volta amanhã, sem pagar para vencer?

### Entregas
- [ ] Nível de conta, maestria por herói, missões diárias e semanais
- [ ] Ranque (Ferro → Diamante → Lenda de Eldoria), temporadas e recompensas
- [ ] Loja: visuais (skins), efeitos de abate, emotes, passe de temporada; **nenhum poder vendido**
- [ ] Moeda gratuita e premium, pacotes via StoreKit 2, restauração de compras
- [ ] **Modo Campanha cooperativa** (PvE) baseado no livro: os 9 capítulos como missões contra bots,
      com cenas narradas (Vozes do Além, Ruínas de Velanthir, Coração das Sombras)
- [ ] Biblioteca de lore: livro adaptado, fichas de personagem, mapa interativo
- [ ] Notificações (Apple Push), eventos sazonais, ofertas de retorno
- [ ] Analytics respeitando privacidade (ATT), painel de métricas, testes A/B de balanceamento
- [ ] Acessibilidade: tamanho de texto, daltonismo, controles configuráveis, vibração opcional

---

## Fase 7: Arte final, áudio, beta e lançamento ⬜

**Pergunta que a fase responde:** está bonito, estável e pronto para a App Store?

### Entregas
- [ ] Arte final: heróis, mapa, esbirros, monstros, interface, ícones, ilustrações de carregamento
- [ ] Animação e efeitos das habilidades, cinemáticas curtas de abertura e de vitória
- [ ] Trilha original, dublagem/falas dos heróis, sons posicionais, mixagem
- [ ] Localização: PT-BR, EN, ES
- [ ] Otimização final: tamanho do app, carregamento de partida, uso de memória, térmica, bateria
- [ ] **Beta aberto (TestFlight)**, correção de bugs, ajuste de balanceamento com dados reais
- [ ] Revisão de privacidade, classificação etária (violência fantasiosa), termos de uso, política de privacidade
- [ ] Metadados da App Store: capturas, vídeo, descrição, palavras-chave
- [ ] Plano de lançamento escalonado por país e de patches pós-lançamento
- [ ] **Consolidação deste documento** com o que mudou em relação ao plano, métricas finais e backlog pós-lançamento

---

## Backlog pós-lançamento

Heróis adicionais (Valen, Serak, Maerok, Arquidruida), modo ARAM no Véu, modo 3v3, Android,
espectador com replay, torneios, mapa novo baseado em outras regiões do livro.

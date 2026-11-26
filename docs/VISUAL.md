# Visual

Como o jogo é desenhado e onde mexer em cada efeito. Os números ficam em
`Config.ART`, `Config.FX` e `Config.JUICE`, em [src/config.lua](../src/config.lua).

## Onde mexer no visual

Cada entidade concentra **todo** o seu desenho num único método `:draw()`;
mudar o visual é uma mudança local, sem tocar em lógica:

| O que | Arquivo |
|-------|---------|
| Jogador (nave recolorida, contorno, chama, crosshair, bolha, drone, escudo, anel e marcador de respawn) | [src/entities/player.lua](../src/entities/player.lua) → `Player:draw` / `Player.drawShip` |
| Inimigos e sub-bosses (todos os tipos, flash de dano, barras de HP, linhas de mira, aura de sub-boss, contorno de elite) | [src/entities/enemy.lua](../src/entities/enemy.lua) → `Enemy:draw` / `Enemy:drawTelegraph` |
| Boss (nave recolorida, fogo nos bocais de cada nave, flash, pulso de fúria, tremor na morte, escudo da entrada) | [src/entities/boss.lua](../src/entities/boss.lua) → `Boss:draw`; shader do escudo em [src/shaders.lua](../src/shaders.lua) |
| Balas, mísseis e brilho dos tiros | [src/entities/bullet.lua](../src/entities/bullet.lua) → `Bullet:draw` / `Bullet:drawGlow` |
| Ícone de power-up (chão, HUD e briefing) | [src/entities/pickup.lua](../src/entities/pickup.lua) → `Pickup.drawIcon` |
| Explosões (clarão, fogo, faíscas, fumaça, destroços), faíscas de impacto e rastro de míssil | [src/entities/particle.lua](../src/entities/particle.lua); presets em `Config.JUICE.explosions` (ver "Explosões") |
| Portas e telégrafo | [src/systems/spawner.lua](../src/systems/spawner.lua) → `Spawner.draw` |
| Fundo: nebulosa, estrelas em camadas, objetos distantes, brilhos, estrelas cadentes, paleta por bloco de waves entre bosses (vermelha na wave de boss) e grade com ondas | [src/background.lua](../src/background.lua) (tuning em `Config.ART.background`) |
| Arena, banners de wave | [src/states/game.lua](../src/states/game.lua) → `Game:draw` |
| HUD (score contando, socos no score e no combo, COMBO PERDIDO caindo) | [src/hud.lua](../src/hud.lua) → `Hud.update` / `Hud.draw` (ver "Juice da interface") |
| Banners de wave (entrada, faixa de luz, bônus contando) | [src/states/game.lua](../src/states/game.lua) → `drawBannerText` |
| Painéis, abas, barras das telas | [src/ui.lua](../src/ui.lua) (`UI.window`, `UI.tab`, `UI.bar`, `UI.text`...) |
| Pós-processamento (brilho, sombras, shockwave, aberração, vinheta) | [src/post.lua](../src/post.lua) + o `:drawGlow()` / `:drawShadow()` de cada entidade |
| Véu do céu e marcas de queimado na arena | [src/states/game.lua](../src/states/game.lua) → `Game:draw`, `world:scorch` |
| Clarão no cano, rastro dos tiros, fita do motor, ecos dos runners | `Player:draw` / `Bullet:drawTrail` / `Enemy:drawEchoes` / `Boss:draw` (ver "Tiro e movimento") |

Cores de jogo em `Config.COLORS`; sprites, tamanhos, fontes e ajustes visuais
em `Config.ART`.

As cores dos jogadores vêm da paleta `Config.PLAYER_PALETTE` (8 cores, sem o
rosa dos tiros inimigos; os nomes ficam em `S.color_name`, em `src/lang/`). O
lobby escreve a cor escolhida de
cada slot em `Config.PLAYER_COLORS`, que é a lista que todo visual de jogador
lê (nave, tiros, HUD, pausa, game over). A cor inicial de cada slot fica em
`Config.PLAYER_DEFAULT_COLOR`, e a escolha é salva como `color1`/`color2` no
`highscores.dat`. Para adicionar uma cor, basta uma entrada nova na paleta.

## Explosões

Cada explosão vem de um preset em `Config.JUICE.explosions` (`small`, `tank`,
`player`, `bossBlast`, `boss`, `missile`, `salvo`) e mistura cinco tipos de
partícula, todos do mesmo pool:

| Tipo | O que é | Camada |
|---|---|---|
| Clarão | círculo branco de poucos frames no centro | acima de tudo, aditivo, brilha |
| Fogo | puffs aditivos que nascem branco/amarelo e esfriam para a cor de quem explodiu (`Config.JUICE.ramp`) | acima de tudo, brilha |
| Faíscas | traços esticados na direção do movimento | acima de tudo, brilha |
| Fumaça | puffs escuros tingidos com a cor, curtos | abaixo dos inimigos |
| Destroços | os 4 quadrantes do sprite voando e girando (só tank, jogador e boss) | abaixo dos inimigos |

- Tank, jogador e boss também soltam um ring fino. Jogador e boss explodem
  em estágios: depois da explosão grande vêm 2–3 estouros menores em volta
  (`Config.JUICE.stages`), no tempo do jogo (ficam em câmera lenta no game
  over).
- Tiro que acerta e não mata solta 2 faíscas ricocheteando na cor do tiro
  (`Config.JUICE.impact`).
- O pool tem 320 partículas em `high` e 160 em `low`/`off`
  (`Config.FX.particles`). Fumaça, destroços, faíscas de impacto e rastros de
  míssil são os primeiros a sair quando o pool aperta (`Config.JUICE.poolShare`),
  então as explosões em si nunca ficam sem partícula.

## Profundidade

A arena funciona como um chão abaixo das naves:

- **Sombras:** jogadores, inimigos, boss e pickups projetam uma sombra suave
  para baixo-direita (luz fixa de cima-esquerda), mais longe quanto maior o
  sprite. Cada um desenha a silhueta em `:drawShadow()`; todas vão para uma
  camada pequena borrada (como o brilho), que escurece o que está embaixo.
  Força, direção e distância em `Config.FX.shadow`. Tiros, partículas e
  destroços não projetam sombra.
- **Véu:** durante a partida o céu fica 25% mais escuro (`Config.FX.veil`),
  para o gameplay se destacar. O lobby e a tela de game over mostram o céu
  sem véu.
- **Marcas de queimado:** tank, jogador e boss (e os estouros secundários do
  boss) deixam uma marca escura e suave no chão, que some em ~4 s
  (`Config.FX.scorch`). Elas são desenhadas na camada de sombra, então nunca
  ficam mais escuras que uma sombra.

## Tiro e movimento

- **Clarão no cano:** a cada tiro, um clarão curto na frente da nave, na cor
  do jogador (dura `Config.PLAYER.muzzleTime`). O boss solta um clarão rosa a
  cada rajada, avisando o perigo. Tamanhos em `Config.FX.muzzle`.
- **Rastro dos tiros:** tiro simples, spread e drone deixam um rastro curto
  (~10 px) na cor do dono. Mísseis continuam só com a fumaça.
- **Fita do motor:** cada nave de jogador arrasta uma fita fina na sua cor,
  com ~0,25 s de histórico, afinando e sumindo. Com a nave parada, ela
  recolhe; no respawn, recomeça do zero.
- **Ecos dos runners:** os inimigos rápidos deixam 3 cópias apagadas do
  sprite atrás de si.
- Tudo em `Config.FX.trail`; força no brilho em `Config.FX.emit`
  (`muzzle`, `shotTrail`, `ribbon`).

## Juice da interface

- **Score:** o número do HUD corre até o valor real em ~0,4 s e dá um soco
  (cresce e clareia) a cada ganho. Ganhos de 1000 ou mais socam mais forte.
  É só exibição: o resumo do game over e os recordes usam o valor real.
- **Combo:** cada kill dá um soco no texto. Quando o multiplicador sobe, o
  soco é maior, a barra brilha e um "x2!", "x3!"... sobe sobre a nave.
  "COMBO PERDIDO" treme e escorrega para baixo enquanto some.
- **Banners de wave:** "WAVE N" e "WAVE N COMPLETA" entram grandes e
  assentam, e uma faixa de luz atravessa as letras (o shader de sheen em
  espaço de tela, `Shaders.sheenAt`). O BÔNUS conta de 0 até o valor.
- Tempos e escalas em `Config.FX.hud`.

## Transições de tela

As trocas grandes de tela têm uma varredura diagonal de 0,35 s (de
cima-esquerda para baixo-direita): uma "foto" da tela anterior se desfaz atrás
de uma frente branco-azulada brilhante, revelando a nova, com um whoosh
suave. Isso vale para:

- lobby → partida;
- partida → resultados;
- resultados → lobby;
- BACK no briefing → lobby;
- abandonar pela pausa → lobby.

Pausa, fechar o briefing e a tela de teste de input continuam com corte seco.

A transição é **só visual**: a troca de estado acontece na hora (o input e o
roteiro do smoke test não esperam nada). [src/transition.lua](../src/transition.lua)
copia o último frame (o canvas da tela ainda o guarda no instante da troca) e
o desenha por cima da tela nova através de um shader. Sem o shader, a foto
some num fade simples. Tempo e cores em `Config.FX.transition`; o som é
`transition` em `Config.SFX`.

## Surgir e sumir

Um shader de dissolve ([src/shaders.lua](../src/shaders.lua), `Shaders.dissolve`)
faz as coisas se formarem ou se desfazerem atrás de uma frente brilhante, com
ruído gerado no próprio shader (sem textura).

- **Portal:** durante os 0,4 s em que a porta pisca, uma elipse vermelha
  abre na boca da porta. Quando o lote sai, ela fecha com um flash
  (`Config.FX.portal`).
- **Inimigos:** saem da porta se materializando em ~0,3 s, com a borda no
  vermelho do aviso. É só visual: desde o primeiro frame eles já colidem,
  ferem e podem ser mortos.
- **Respawn:** um feixe de luz na cor do jogador desce sobre o marcador e a
  nave se monta de cima para baixo (`Config.FX.beam`). O jogador já controla
  a nave, e a invulnerabilidade é a de sempre. No início da partida as naves
  ficam escondidas durante o briefing e descem no feixe quando alguém aperta
  START.
- **Pickups:** piscam em branco no fim da vida e se desfazem na cor do
  power-up (ver [Power-ups no chão](#power-ups-no-chão)).
- Sem o shader, tudo isso vira um fade simples. Tempos em
  `Config.FX.dissolve`.

## Pós-processamento

A arena (do céu ao brilho) é desenhada num canvas de cena e passa por um
shader de composição antes de ir para a tela. Banners, textos e HUD são
desenhados depois, nítidos e sem distorção. Tudo fica em
[src/post.lua](../src/post.lua), com o tuning em `Config.FX`.

**Brilho (bloom seletivo).** Só o que emite luz brilha: tiros, estrelas
inimigas, mísseis, faíscas, chamas dos motores, rings, pickups, lâmpadas das
portas, escudos e o flash de dano. Nebulosa, planetas e HUD ficam de fora.
Cada entidade desenha a sua luz em `:drawGlow()`, chamado por `Game:draw`
entre `Post.beginGlow()` e `Post.endGlow()`. A camada é desenhada num canvas
pequeno, de tamanho fixo em resolução lógica (o custo não cresce com a
janela), passa por um blur gaussiano e é somada à cena. Força de cada emissor
em `Config.FX.emit`; ganho e raio em `Config.FX.glow`.

**Shockwave, aberração cromática e vinheta** (no shader de composição):

| Efeito | Quando | Tuning |
|---|---|---|
| Shockwave (anel que distorce a imagem) | morte de tank, NOVA, salvo, bolha estourando, morte do jogador, final do boss | `Config.FX.shock` |
| Aberração cromática (split RGB nas bordas) | morte do jogador, final do boss | `Config.FX.aberration` |
| Vinheta (bordas da arena mais escuras) | sempre; pulsa vermelha quando um jogador morre | `Config.FX.vignette` |

Os efeitos correm no tempo do jogo: congelam no hit-stop e ficam em câmera
lenta no game over. No máximo 4 shockwaves ao mesmo tempo. Com DEBUG, **F6**
dispara uma shockwave com aberração no centro, para tunar. O item DISTORÇÃO
das opções desliga as shockwaves e a aberração (o brilho e a vinheta ficam),
e TREMOR DE TELA escala todo tremor (por cima de `Config.JUICE.shakeScale`).

**Qualidade:** o item EFEITOS VISUAIS das opções (ALTO, BAIXO, DESLIGADO), ou
`love . --fx high|low|off` na linha de comando, que trava o item na sessão.
O padrão (`Config.OPTIONS.defaults.fx = "auto"`) é `low` no navegador e
`high` no resto. Trocar nas opções recria a camada de brilho na hora
(`Post.load`); o teto de partículas vale a partir da próxima partida.

| Qualidade | Brilho | Composição da cena |
|---|---|---|
| `high` | 320x180 + halo largo em 160x90 | ligada |
| `low` | 160x90 | ligada |
| `off` | sem blur | desligada (sem shockwave, aberração e vinheta) |

Se um shader não compilar, o jogo segue sem aquele efeito (o brilho fica sem
blur, a cena desenha direto na tela) e avisa no console (`[post] ...
unavailable`).

## Arte (Kenney)

A arte vem dos pacotes da [Kenney](https://kenney.nl) (CC0) em `assets/art/`:

- **Sprites:** recortados das folhas `spaceShooter2_spritesheet` e
  `simpleSpace_sheet` pelos atlas XML. Os bosses saem da
  `spaceShooter2_spritesheet_2X` (a mesma folha em 2x), porque são desenhados
  grandes e a 1x borraria; a numeração dos sprites da 2X é **diferente** da 1x
  (case pelo tamanho: o da 2X tem o dobro). Cada papel (nave do jogador, inimigo,
  tiro...) aponta para um sprite em `Config.ART.sprites`, e o tamanho na tela
  fica em `Config.ART.size`. Trocar um sprite é mudar o nome ali. Com
  `grey = true`, o sprite é convertido no boot para tons de cinza com base
  branca, para que `setColor` o tinja na cor exata (a chama do motor usa isso
  para sair na cor do jogador).
- **Planetas:** um por tema do fundo, montados no boot por
  [src/background.lua](../src/background.lua) a partir das peças do pacote
  Planets em `assets/art/planets/`: esfera tingida + texturas de superfície
  tingidas + mapa de luz multiplicado (crescente). Cada tema escolhe as peças,
  as cores, a posição e o tamanho em `Config.ART.background.themes[i].planet`.
  Para usar uma peça nova, copie-a de `PlanetParts/` para `planets/`.
- **UI:** peças do `UIPack`, desenhadas por [src/ui.lua](../src/ui.lua)
  (painel 9-slice, aba, barra, badge, crosshair), tingidas com qualquer cor.
  As abas de título das janelas têm `Config.ART.ui.tabH` (22px) com Rocket
  Square 16; a aba "P1"/"P2" do HUD tem tamanho próprio (`hudTab`) para caber
  na faixa de 40px. Títulos de aba ficam **sem acento**: til e cedilha caem em
  cima da borda chanfrada.
- **Fontes:** Kenney Rocket Square (títulos), Mini Square (texto) e Kenney
  Mini (números), em `Config.ART.fonts`. As fontes "Square" desenham o zero
  como um quadrado; a Mini tem o zero chanfrado. Por isso os números usam a
  Mini, nos papéis `digitsSmall` (8), `digits` (16) e `digitsBig` (24), um para
  cada tamanho de texto ao lado. Como ela não é monoespaçada, os números passam
  por `UI.digits`, que centraliza cada dígito numa célula fixa, e eles não
  tremem quando mudam. Texto com número dentro ("WAVE 10", "INIMIGOS 40") usa
  `UI.textNumber`: rótulo na fonte do texto, número na Mini, na mesma linha de
  base. Ao escrever um texto novo com número, use esse helper. São fontes pixel
  com grade de 8px: use só tamanhos múltiplos de 8, senão os traços saem com
  larguras diferentes.
- **Contorno dos jogadores:** na arena, cada nave tem uma borda na cor do
  jogador clareada, pulsando de leve, para achar a própria nave no meio do
  caos. É o papel `playerOutline` em `Config.ART.sprites`: a mesma nave com o
  alfa dilatado em `outline` texels (4), gerada no boot como silhueta branca e
  tingida no desenho. Não há shader em runtime. Contornos mais grossos também
  preenchem os vãos entre asas e corpo (com 5, a nave vira uma placa sólida).
  Cor e pulso ficam em `Config.ART.outline`. Lobby e vidas do HUD continuam
  sem contorno.
- **Chama do motor:** duas camadas aditivas (chama na cor do jogador e núcleo
  branco), mais longa quanto mais rápido a nave anda. Tamanhos em
  `Config.ART.size` (`engineFlame`, `engineCore`) e ajustes em
  `Config.ART.engine`.

A lógica continua em 640x360, mas o canvas é desenhado no maior múltiplo
inteiro que cabe na janela: 1280x720 em 720p, 1920x1080 em 1080p. Assim os
sprites ficam lisos. `Config.ART.maxRenderScale` limita esse múltiplo, se o
hardware sofrer.

O vermelho das naves e mísseis da Kenney vira a cor do jogador no shader de
[src/shaders.lua](../src/shaders.lua), que aceita qualquer cor da paleta.

## Power-ups no chão

Tuning em `Config.FX.pickup`.

- **Ao cair:** surge com um "pop" (cresce além do tamanho e volta) e um anel
  fino na sua cor.
- **Parado:** uma faixa de luz atravessa o badge a cada ~2 s, cada pickup no
  seu próprio ritmo.
- **Ao pegar:** um anel na cor do power-up sai da nave e o nome dele (ex.:
  "SPREAD") sobe e some sobre ela. O texto é desenhado por cima da arena,
  nítido, sem as distorções do pós-processamento.


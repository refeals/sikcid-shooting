# Design

Como o SikCid Shootin' funciona hoje, do ponto de vista de quem joga. Os
números de cada mecânica ficam em [src/config.lua](../src/config.lua); as
metas de dificuldade e a curva estão em [BALANCE.md](BALANCE.md), e o que
ainda vai mudar, em [ROADMAP.md](ROADMAP.md).

## Visão geral

Twin-stick shooter de arena para 1–2 jogadores locais, pensado para controle
de videogame: Batocera na TV, PC e navegador. Inimigos entram por quatro
portas em waves infinitas. A nave atira sozinha no inimigo mais próximo, e o
jogador se concentra em pilotar, desviar, dar dash e segurar o combo.

Pilares:

- **Pilotar acima de mirar.** O auto-aim cuida do tiro; a mira manual serve
  para priorizar um alvo (o sniper, por exemplo).
- **Progressão dentro da partida.** Power-ups temporários e upgrades
  permanentes valem só até o game over; entre partidas ficam só os recordes.
- **Cada wave diferente da anterior.** A dificuldade cresce em densidade e em
  composição (tipos novos, elites, sub-bosses, bosses), não em duração.
- **Legível no caos.** Cada ameaça tem cor própria e avisa antes de atacar:
  porta piscando, linha de mira, ALERTA.
- **Co-op de sofá.** Dois jogadores na mesma tela, sem divisão de tela.

## Loop da partida

1. **Lobby:** cada jogador entra e escolhe a cor (ver
   [Lobby e briefing](#lobby-e-briefing)).
2. **Briefing:** a arena congelada com a lista de power-ups; START começa.
3. **Waves:** "WAVE N" no centro; os inimigos saem das quatro portas em
   lotes, e cada porta pisca antes de soltar o lote. A wave fecha quando toda
   a cota saiu e não sobra ninguém vivo: bônus de fim de wave, um power-up
   garantido, quem estava sem vidas volta, e 3 s de respiro.
4. **A cada 5 waves:** tela de [upgrade permanente](#upgrades-permanentes).
5. **Waves 5, 15, 25...:** um [sub-boss](#sub-bosses) entra no meio da wave.
6. **Waves 10, 20, 30...:** [boss](#boss).
7. **Game over** quando o último jogador perde a última vida; depois,
   resultados e recordes.

Um tipo novo de inimigo estreia com o banner "NOVO: <NOME>" e já vem em
trio no primeiro lote da wave de estreia.

### Pontos e combo

- Cada inimigo vale pontos pelo tipo (elite vale o dobro), multiplicados pelo
  combo de quem matou.
- **Combo:** cada morte renova uma janela curta; a cada 5 mortes seguidas o
  multiplicador sobe um degrau (até x8). Se a janela fecha, aparece "COMBO
  PERDIDO". Acertar o boss mantém o combo vivo, sem aumentá-lo.
- Fim de wave: bônus que cresce com o número da wave.
- Boss: os pontos são divididos pelo dano que cada jogador causou. Derrubar
  um míssil do boss também dá pontos.

### Respiro entre waves

Entre uma wave e outra (os 3s de respiro), os timers de **power-up** — os
ativos e os caídos no chão — e de **combo** ficam parados: nada some durante
a pausa, e dá para carregar tudo para a wave seguinte. Na wave do boss eles
também param enquanto ele não pode ser atingido (alerta, entrada e explosão
final). Quando a wave fecha, os tiros inimigos que ainda estavam voando somem.
O power-up garantido do
fim da wave cai no ponto livre mais longe dos jogadores (e de onde quem está
morto vai renascer), para ninguém pegar sem ver o que é.

## Controles

| Ação | Gamepad | Teclado (P1) |
|------|---------|--------------|
| Mover | analógico esquerdo | WASD |
| Mirar | analógico direito (ou d-pad) | setas |
| Atirar | automático | automático |
| Dash | RB, LB ou B | Shift |
| Pausar | START ou BACK | Enter ou ESC |
| Desvincular no lobby | BACK (SELECT) | ESC |
| Trocar / sortear a cor no lobby | d-pad ←/→ (ou analógico esquerdo) / Y | A/D ou ←/→ / R |
| Abandonar a partida | BACK na pausa, com confirmação | ESC na pausa |
| Sair do jogo (não existe na web) | segurar SELECT (1s) ou SELECT + START (0,5s) | segurar ESC (0,5s) |
| Teste de input | — | F5 |

### Controles touch (celular, tablet)

Os controles de touch aparecem no primeiro toque na tela; antes disso, nada
muda no PC ou no Batocera. O touch é um jogador como os outros: o segundo
jogador entra com um controle.

| Ação | Touch |
|------|-------|
| Mover | metade esquerda: onde o dedo encosta vira o centro do analógico |
| Mirar (opcional) | metade direita, igual; sem dedo ali, vale a mira automática |
| Dash | botão DASH, acima do analógico de mira |
| Atirar | automático |
| Pausar | botão ‖ ao lado do WAVE |
| Entrar, começar, continuar | tocar em qualquer lugar |
| Trocar a cor no lobby | tocar nas setas |
| Abandonar a partida | botão ABANDONAR na pausa, depois CONFIRMAR |

Se o dedo passa do raio do analógico, a base vem junto. Sem dedo encostado,
círculos fracos nos cantos de baixo (MOVER / MIRAR) mostram onde tocar. Os
textos de ajuda viram "TOQUE ..." enquanto o último input for touch. Se a
janela ou a aba perde o foco durante a partida, o jogo pausa sozinho (em
qualquer plataforma). Ajustes em `Config.TOUCH`.

### Mira automática

O tiro é automático (`Config.AUTO_AIM` em `src/config.lua`): sem mira manual,
a nave mira e atira sozinha no inimigo visível mais próximo e segura esse alvo
até ele morrer, sair da tela ou outro ficar bem mais perto. Sem nenhum
inimigo na tela, ela não atira e aponta para onde está andando. O
analógico direito (ou o d-pad; no teclado, as setas) sempre tem prioridade
sobre a mira automática.

## Dash

RB, LB ou B no controle; Shift no teclado; botão DASH no touch. Números em
`Config.DASH`.

- Um arranque curto (~70 px em 0,15 s) na direção do analógico de movimento;
  com a nave parada, na direção da mira.
- Durante o arranque a nave **atravessa inimigos e tiros** sem tomar dano, e
  continua atirando. A proteção dura um instante depois do fim; se o dash
  termina dentro de um inimigo (ou do boss), ela se estende enquanto a nave
  ainda encosta nele, por pouco tempo.
- Recarga de ~1 s, mostrada por um anel em volta da nave, que pisca quando o
  dash fica pronto. Apertar um pouco antes da hora vale.
- Para nas paredes. Funciona durante a invulnerabilidade do respawn.
- Sozinho, o dash não causa dano: isso vem dos upgrades
  [LÂMINA e CHOQUE](#upgrades-permanentes).
- Visual: cópias apagadas da nave no rastro e um whoosh.

## Power-ups

| Letra | Power-up | Efeito |
|-------|----------|--------|
| S | SPREAD | 3 tiros em leque (arma) |
| R | RAPID FIRE | cadência em dobro (arma) |
| M | MISSILES | mísseis teleguiados, dano 3 (arma) |
| V | SPEED BOOTS | 40% mais velocidade |
| B | BOLHA | segura 1 golpe; ao estourar, empurra os inimigos em volta e dá 1s de invulnerabilidade |
| D | DRONE | drone que orbita a nave e atira sozinho (10/s) no inimigo mais próximo; os tiros são bolinhas de energia, diferentes dos da nave |
| X | DANO X2 | dobra o dano de qualquer arma (e do drone) |
| L | LASER | raio do bico até a parede que atravessa tudo e fere tudo na linha, inclusive o boss (o escudo de entrada dele bloqueia). Dispara em rajadas de 1 s com 0,5 s de recarga, mostrada por um brilho que cresce na ponta da nave; 8 s (arma) |
| O | ESCUDO ORBITAL | 3 esferas em volta da nave que destroem os tiros inimigos que tocam e ferem os inimigos que encostam |
| T | TEMPO LENTO | a arena inteira (os 2 jogadores): inimigos, tiros inimigos, boss e sub-bosses a 50% por 6 s; véu azul e música mais grave |
| N | NOVA | na hora: onda de choque em volta, dano 5 e apaga os tiros inimigos no raio |
| + | EXTRA LIFE | na hora: +1 vida (até o máximo, que o upgrade CASCO aumenta) |

Armas (S, R, M, L) se substituem; os outros acumulam. Pegar um que já está ativo
renova o tempo. Os números de cada um estão em `Config.POWERUPS`. Para testar
um power-up direto: `love . --powerup laser,orbital --wave 12` (dá esses
power-ups a todos no início de cada wave).

Um power-up no chão dura 10 s (`Config.POWERUP.pickupLife`). Nos últimos
3 s um anel **branco** pisca em volta dele, cada vez mais rápido, e quando o
tempo acaba ele se desfaz em ~0,3 s. Dá para pegar durante esse desfazer: é a
última chance.

## Upgrades permanentes

Depois de cada 5ª wave (5, 10, 15...; nas waves de boss, depois do boss), a
arena congela e cada jogador escolhe **1 de 3 cartas**. O upgrade vale até o
fim da partida, inclusive depois de morrer. Números em `Config.UPGRADES`;
nomes, textos e regras de oferta em
[src/systems/upgrades.lua](../src/systems/upgrades.lua).

- Esquerda/direita e START, ou tocar na carta. Sem tempo limite e sem trocar
  as cartas.
- Em 2 jogadores a tela se divide: cada um tem as suas 3 cartas, e a partida
  só segue quando os dois confirmam ("PRONTO" enquanto espera o outro). Quem
  está sem vidas também escolhe. Os dois podem pegar o mesmo upgrade.
- Os upgrades se multiplicam com os power-ups temporários (CADÊNCIA + RAPID
  FIRE, por exemplo).
- HUD: ícones quadrados embaixo da barra de combo, com pontinhos de nível; a
  pausa mostra a lista completa. Badge quadrado = permanente (o do power-up
  temporário é redondo); azul-claro = atributo, dourado = único.

**Atributos** (acumulam até o máximo):

| Upgrade | Efeito por nível | Máx. |
|---|---|---|
| CADÊNCIA | +20% de cadência de tiro | 3 |
| MOTOR | +12% de velocidade | 3 |
| PROPULSOR | dash recarrega 20% mais rápido | 2 |
| DURAÇÃO | power-ups temporários duram 35% mais | 2 |
| CASCO | +1 vida agora e +1 no máximo de vidas | 2 |
| ÍMÃ | puxa os power-ups do chão para a nave | 1 |

**Únicos** (3 níveis: base, + e ++; cada nível só aparece depois do anterior):

| Upgrade | Base | + | ++ |
|---|---|---|---|
| PERFURANTE | tiro atravessa 1 inimigo | atravessa 2 | atravessa todos |
| RETAGUARDA | tiro para trás, metade da cadência | cadência cheia | 3 tiros para trás em leque |
| DRONE FIEL | drone permanente, metade da cadência | cadência cheia | um segundo drone |
| LÂMINA | dash dá 3 de dano em quem atravessa | 6 de dano | matar com a lâmina recarrega o dash |
| RECARGA | ganha uma BOLHA a cada 30 s sem bolha | a cada 20 s | a bolha estoura com uma NOVA |
| RICOCHETE | tiros quicam 1 vez nas paredes | 2 vezes | tiro que quicou persegue inimigos |
| CHOQUE | fim do dash solta uma mini-NOVA | mini-NOVA maior e mais forte | também no início do dash |

**Ofertas:**

- Wave comum: qualquer upgrade, com no máximo uma carta de subir nível (+ ou
  ++) por oferta.
- Depois do boss: únicos, com pelo menos uma carta de subir nível quando
  houver alguma possível; atributos só completam se faltarem únicos.
- Upgrade no máximo não aparece mais. Sem nada para oferecer, entra a carta
  **+1 VIDA**.

## Inimigos

Cada tipo tem uma cor própria. Vida, velocidade e pontos em `Config.ENEMIES`;
quando cada um entra e com que frequência, em `Config.ENEMY_MIX` (ver
[BALANCE.md](BALANCE.md)).

| Tipo | Entra na wave | Cor | Comportamento |
|---|---|---|---|
| grunt | 1 | vermelho | persegue o jogador mais próximo; o "recheio" que mantém o ritmo |
| runner | 1 (raro no começo) | laranja | rápido, em zigue-zague; deixa ecos no rastro |
| shooter | 2 | amarelo | mantém distância e atira estrelas rosa lentas |
| tank | 4 | roxo | lento, aguenta vários tiros (barra de vida), empurra os outros |
| KAMIKAZE | 7 | carmim | chega perto, mira 0,5 s com uma linha vermelha (trava no fim) e dispara em linha reta, atravessando os outros inimigos; se bate na parede, fica tonto por 1 s |
| DIVISOR | 9 | verde-água | ao morrer, se parte em 3 fragmentos em leque: inofensivos por um instante, depois agem como runners pequenos; não se dividem de novo |
| SNIPER | 12 | azul-aço | vai para perto de uma parede, longe do jogador, mira 1 s com um laser vermelho fino (trava no fim) e dispara um tiro rápido, que dá para desviar ou atravessar com o dash; muda de lugar a cada tiro e foge se o jogador chega perto |
| PORTA-NAVES | 15 | marfim | lento, resistente (barra de vida), mantém distância; a cada ~4 s pisca as escotilhas e lança 2 drones teleguiados (até 4 vivos); quando morre, os drones dele explodem sem dar pontos |

Fragmentos e drones ficam fora da cota da wave, mas a wave só fecha quando
eles também morrem. Valem poucos pontos e não nascem se o teto de inimigos
estiver cheio.

### Elites

A partir da wave 20, qualquer inimigo que sai de uma porta pode vir
**elite**: contorno e anel dourados pulsando, o dobro de vida, um pouco mais
rápido e o dobro de pontos. A chance cresce a cada wave até um teto
(`Config.ELITE`). Fragmentos, drones e sub-bosses nunca são elite.

## Sub-bosses

Nas waves 5, 15, 25, 35... um sub-boss faz parte da wave: quando metade da
cota já saiu, um ALERTA com o nome dele aparece por ~1 s e ele entra por uma
porta. Os inimigos normais continuam saindo, e a wave só fecha quando ele e o
resto morrem. Números em `Config.SUBBOSS` e nas entradas de cada um em
`Config.ENEMIES`.

| Sub-boss | Wave | Base | Comportamento |
|---|---|---|---|
| TORRE | 5 | tank | lenta; gira uma espiral de estrelas rosa (4 braços) e para por um instante a cada ~4 s; ganha +2 braços a cada volta do ciclo |
| ARIETE | 15 | kamikaze | 3 investidas seguidas até a parede, cada uma com uma linha de mira vermelha grossa; depois da 3ª, fica tonto por 2,5 s |
| HIDRA | 25 | divisor | persegue devagar e cospe 3 fragmentos em leque a cada 3 s; ao morrer, se parte em 2 divisores médios, que se partem em 3 fragmentos cada |
| COLMEIA | 35 | porta-naves | lança drones (até 8 vivos) e mantém 4 guardas orbitando, que bloqueiam os tiros (um guarda volta a cada 5 s); tudo explode quando ela morre |

- Depois da COLMEIA o ciclo recomeça (wave 45 = TORRE de novo), com mais vida
  a cada aparição; em 2 jogadores, mais vida ainda.
- Visual: o sprite do inimigo base ~2,5x maior, na cor dele, sobre uma aura
  vermelho-escura pulsando. Nunca é elite e não tem escudo de entrada.
- HUD: nome e barra de vida no centro, como o boss.
- Recompensa: 2 power-ups garantidos e pontos que crescem com a ordem do
  sub-boss na partida (o 2º vale o dobro do 1º, e assim por diante). Como as
  waves de sub-boss são múltiplas de 5, logo depois vem a tela de upgrade.
- A música da wave continua; só toca o alarme.
- Debug: F8 chama o sub-boss do ciclo atual na hora.

## Boss

A cada 10 waves (10, 20, 30...) a wave é de **boss**:

- O fundo fica vermelho, um banner **ALERTA** pisca com o nome do boss e ele
  entra de fora da tela por um lado sorteado. Enquanto entra, não atira e não
  toma dano; encostar nele mata, como nos outros inimigos.
- Durante a entrada ele fica dentro de um **escudo de energia** (hexágonos na
  cor dele). Tiros dos jogadores morrem no escudo, com uma ondulação no ponto
  do impacto e um "tink", e não passam para os inimigos atrás. O salvo detona
  ali. Quando a luta começa, o escudo **estoura** (shockwave, faíscas, som
  grave) junto com a entrada da música do boss. Tuning em
  `Config.BOSS.shield`; sons `shield_hit` e `shield_break` em `Config.SFX`.
- Ele anda devagar pela arena, atira **rajadas miradas** (que viram leque nos
  bosses seguintes) e lança **mísseis teleguiados**: o míssil persegue um
  jogador por alguns segundos, depois falha (pisca, solta fumaça, perde
  velocidade) e explode sem causar dano. Dá para derrubá-lo com alguns tiros.
  Em 2 jogadores, ele alterna o alvo entre os dois.
- Abaixo de 40% do HP entra em **fúria**: atira e anda mais rápido e pulsa
  vermelho.
- Do 2º boss em diante, inimigos normais continuam saindo pelas portas durante
  a luta.
- A vida dele aparece no centro do HUD. Cada acerto no boss mantém o combo
  vivo (sem aumentá-lo).
- Na morte, ele explode em sequência e leva junto todos os inimigos e tiros
  inimigos. Os pontos são divididos pelo dano que cada jogador causou, e saem
  power-ups dos destroços (além do bônus e da vida de volta de toda wave). O
  fundo já muda para a cor do próximo bloco de waves.

Cada boss é uma das 5 variantes (nave, cor e nome) em ciclo, e fica mais
forte que o anterior: mais HP, rajadas maiores, mísseis mais frequentes, mais
inimigos de apoio. Quando a lista de variantes recomeça, ele também fica
maior.

## Morte e respawn

Morrer custa uma vida e todos os power-ups ativos. 1s depois, um **marcador**
na cor do jogador aparece onde ele morreu: é ali que ele volta quando a
contagem acabar, a não ser que ele mova o marcador com o analógico esquerdo
(ou WASD) durante a contagem. Ao renascer, o jogador ganha um **suporte**:

- uma **salva de mísseis** teleguiados, cada um para um inimigo próximo
  diferente (o boss incluído), com dano no impacto e explosão em área. São 4
  mísseis, +1 a cada 10 waves (máx. 10);
- um **power-up de arma** (S, R ou M) que cai perto.

Quem ficou sem vidas e volta no fim da wave não ganha o suporte (não é uma
morte); ele reaparece no ponto mais seguro da arena.

Quem volta na **última vida**, por qualquer um dos dois caminhos, já volta com
a **BOLHA** ativa.

## Game over

Quando o último jogador perde a última vida, a explosão roda em câmera lenta
e a arena continua viva: os inimigos seguem vagando, mas as portas fecham.
1s depois, a arena escurece e aparecem **GAME OVER**, a wave alcançada e a
pontuação de cada jogador. Depois aparece **APERTE START**, que leva para a
tela de resultados. Tempos e efeitos ficam em `Config.GAME_OVER`.

## Lobby e briefing

1. O primeiro controle que apertar **START** vira o Jogador 1.
2. O **mesmo** controle apertando START de novo começa a partida em 1 jogador.
3. **Qualquer botão** de um segundo controle vincula o Jogador 2; daí em diante
   START de qualquer um dos dois começa a partida em 2 jogadores.
4. **BACK** desvincula. Se o Jogador 1 sair, o Jogador 2 assume o slot 1
   (levando a cor que escolheu).
5. **D-pad** (ou analógico esquerdo) para os lados troca a cor da nave; **Y**
   sorteia uma. No teclado: A/D ou ←/→ trocam, R sorteia. A cor do outro
   jogador é sempre pulada, e a escolha de cada slot fica salva para a próxima
   partida.

Ao sair do lobby, a arena aparece congelada com uma janela apresentando os
power-ups. A partida só começa quando qualquer um dos jogadores aperta
**START** de novo; **BACK** volta para a seleção. A lista sai de
`Powerups.DEFS` (campo `desc`), então um power-up novo aparece nela sozinho.

Se um controle vinculado cair durante a partida, o jogo pausa sozinho com
"AGUARDANDO CONTROLE DO JOGADOR N" e volta sozinho quando ele reconectar (o
vínculo é reconhecido pelo GUID do controle).

## Dois jogadores

- Mesma tela, cada um com seu controle (ou um no teclado). O segundo entra
  no lobby com qualquer botão.
- A wave tem mais inimigos no total e mais vivos ao mesmo tempo; boss e
  sub-bosses têm mais vida (multiplicadores em [BALANCE.md](BALANCE.md)).
- Vidas, power-ups, combo, upgrades e pontos são de cada jogador. O TEMPO
  LENTO vale para a arena inteira.
- Quem fica sem vidas espera e volta no fim da wave; a partida acaba quando
  os dois estão fora.
- Os pontos do boss são divididos pelo dano de cada um, e ele alterna o alvo
  dos mísseis entre os dois.

## Ideias descartadas

Decisões já tomadas, para não voltar nelas sem motivo novo:

- **Inimigo com escudo frontal:** o auto-aim desperdiçaria os tiros nele.
- **Upgrade de +dano:** a vida dos inimigos é baixa demais para ele fazer
  diferença.
- **Dano no dash por padrão:** virou o upgrade LÂMINA.

# Balanceamento

Como a dificuldade e as recompensas devem se comportar, e onde mexer. Os
números valem só em [src/config.lua](../src/config.lua): este arquivo
descreve a intenção e aponta para eles, sem copiar valores que mudam. O que
cada mecânica faz está em [DESIGN.md](DESIGN.md).

## Metas

| Jogador | Deve morrer por volta da wave |
|---|---|
| primeira partida | 8–12 |
| médio, já acostumado | 20–25 |
| muito bom | 35 ou mais |

Sem parede: a dificuldade cresce sempre, mas nenhuma wave deve ficar
impossível de repente.

## Curva de waves

- **O total por wave cresce linear.** As waves não ficam mais longas de
  forma explosiva.
- **A pressão vem da densidade e da composição.** Densidade: mais inimigos
  vivos ao mesmo tempo, menos tempo entre lotes, lotes maiores. Composição:
  tipos novos nas waves 2, 4, 7, 9, 12 e 15, elites a partir da 20.
- **Mix de inimigos:** o peso de cada tipo no sorteio sobe a partir da wave
  de estreia e estabiliza num teto. O grunt cai até um mínimo mas nunca some:
  é o recheio que mantém o ritmo.
- **Elites** são a alavanca infinita depois que todos os tipos já entraram:
  a chance cresce por wave até um teto.
- **Sub-bosses e bosses** ficam mais fortes a cada aparição.
- **2 jogadores:** multiplicadores no total da wave, no teto de vivos e na
  vida de boss e sub-boss (`Config.WAVE.coop*`, `Config.BOSS.coopHp`).

## Recompensas

O que o jogador ganha, e com que ritmo:

- **Power-ups temporários:** chance de drop por inimigo morto, um garantido
  no fim de cada wave, 2 por sub-boss e vários do boss. O peso de cada um no
  sorteio fica em `Config.POWERUPS`; NOVA, TEMPO LENTO e EXTRA LIFE são os
  raros.
- **Upgrades permanentes:** um a cada 5 waves.
- **Vidas:** EXTRA LIFE, upgrade CASCO e a carta +1 VIDA. Em 2 jogadores,
  quem fica sem vidas volta no fim da wave.
- **Suporte no respawn:** salva de mísseis (cresce com a wave) e um power-up
  de arma.
- **Pontos:** pontos do tipo x elite x ordem do sub-boss x combo; bônus de
  fim de wave; pontos do boss divididos pelo dano.

## Onde mexer

Tudo em **[src/config.lua](../src/config.lua)**. Não existe número de balanceamento
espalhado em outro arquivo.

| O que | Onde |
|-------|------|
| Curva de waves (cota, inimigos vivos, cadência, tamanho do lote, multiplicadores de 2 jogadores) | coeficientes em `Config.WAVE` (`quota*`, `alive*`, `interval*`, `coop*`), lidos por `Config.waveQuota` / `waveMaxAlive` / `waveSpawnInterval` / `waveBatch` |
| Quando cada tipo de inimigo entra e com que frequência | `Config.ENEMY_MIX` (`from`, `base`, `perWave`, `min`, `max`) |
| Inimigos de elite (a partir de que wave, chance, vida, velocidade, pontos, visual) | `Config.ELITE` |
| Upgrades permanentes (a cada quantas waves, números de cada um) | `Config.UPGRADES` |
| HP, velocidade, tamanho e pontos de cada inimigo | `Config.ENEMIES` |
| Distância entre inimigos (folga entre sprites, força do desvio, raio do boss como obstáculo), knockback, tamanho da célula do grid | `Config.ENEMY_SPACING`, `ENEMY_KNOCKBACK`, `GRID_CELL` |
| Inimigos sem jogador vivo (velocidade e curvas do vaguear) | `Config.ENEMY_WANDER` |
| Vidas, velocidade, invulnerabilidade, tempo de respawn | `Config.PLAYER` |
| Cadência, dano, velocidade de bala, spread, míssil | `Config.WEAPON` |
| Duração, peso no sorteio e efeito de cada power-up (multiplicadores, raio e dano da NOVA, drone, bolha) | `Config.POWERUPS` |
| Chance de drop, vida do pickup no chão, onde cai o drop de fim de wave | `Config.POWERUP` |
| Respawn: delay e velocidade do marcador, salva de mísseis (quantidade, dano, explosão), drop de arma | `Config.RESPAWN` |
| Janela do combo, degrau e teto do multiplicador | `Config.COMBO` |
| Telégrafo das portas, respiro entre waves, bônus | `Config.WAVE` |
| Boss: frequência, tamanho, HP, velocidade, rajadas, mísseis, fúria, inimigos de apoio, pontos, drops, variantes | `Config.BOSS` (valores `{ base, perBoss, min, max }`, lidos por `Config.bossValue`) |
| Sub-bosses: em que waves, quando entram na wave, vida por aparição, drops, ordem das variantes, aura | `Config.SUBBOSS` (comportamento de cada um nas entradas `torre`, `ariete`, `hidra`, `colmeia` de `Config.ENEMIES`) |
| Dash: distância, duração, recarga, proteção, buffer | `Config.DASH` |
| Mira automática: liga/desliga, quando troca de alvo | `Config.AUTO_AIM` |
| Screen shake (com fadiga e multiplicador global `shakeScale`), hit-stop (com cooldown), explosões (faíscas + fumaça), rastro de míssil | `Config.JUICE` |
| Controles touch: raio dos analógicos, deadzone, fantasmas, botões | `Config.TOUCH` |
| Sequência de game over: câmera lenta, tempos, escurecimento | `Config.GAME_OVER` |
| Tetos de entidades vivas (tamanho dos pools; hoje 100 inimigos, 320 balas, 24 pickups) | `Config.MAX_ENEMIES`, `MAX_BULLETS`, `MAX_PICKUPS` |
| Teto de partículas por qualidade (hoje 320 em high, 160 em low/off) | `Config.FX.particles` |
| Limiar do aviso de frame lento (DEBUG) | `Config.PROFILE_WARN_MS`, `PROFILE_WARN_INTERVAL` |

As fórmulas de wave são funções, não tabela: a curva é infinita. Ela cresce
pela densidade (inimigos vivos ao mesmo tempo) e pela composição (tipos novos,
elites), não pelo tamanho: o total por wave é linear. Para ver a curva inteira
sem jogar:

```sh
love . --curve    # tabela no console: total, vivos, intervalo, elites e % de cada tipo por wave
```

Os bosses seguem a mesma ideia: cada valor que escala é `base + perBoss * (n - 1)`
(n = 1 na wave 10, 2 na wave 20...), com `min`/`max` opcionais. Para testar um
boss direto: `love . --wave 10 --debug` (F2 mata o boss, F3 deixa invencível).

## Registro de partidas (runs.csv)

Toda partida grava `runs.csv` na pasta de save do LÖVE, junto do
`highscores.dat`: uma linha por wave (tempo, mortes e o que matou, vidas,
upgrades, pontos) e um resumo por partida (wave final, duração, upgrades,
última morte, se terminou em game over, abandono ou fechando o jogo). As
colunas estão descritas no topo de [src/runlog.lua](../src/runlog.lua). Abre em
qualquer planilha.

| Onde | Arquivo |
|------|---------|
| Windows | `%APPDATA%\LOVE\sikcid-shootin\runs.csv` |
| Linux | `~/.local/share/love/sikcid-shootin/runs.csv` |
| Batocera | `/userdata/system/.local/share/love/sikcid-shootin/runs.csv`; traga para o PC com `./build.sh --pull-runs` (vira `dist/runs-batocera.csv`) |
| Navegador | gravado no IndexedDB, sem como baixar |

O teste automatizado não grava nada aí (com `--smokelog` ele grava num
arquivo à parte, `runs-smoke.csv`).

## Como analisar o playtest

1. Jogue algumas partidas. No Batocera, traga o arquivo com
   `./build.sh --pull-runs`.
2. Abra o `runs.csv` numa planilha. Nas linhas `partida`, compare a wave
   final com as [metas](#metas). Nas linhas `wave`, veja o tempo de cada
   wave, as mortes e o que matou.
3. Procure:
   - waves longas demais (densidade baixa) ou curtas demais;
   - mortes concentradas num tipo de inimigo (forte demais) ou num tipo que
     nunca mata ninguém (fraco demais);
   - boss ou sub-boss que morre rápido demais (pouca vida) ou trava a
     partida;
   - diferença grande entre 1 e 2 jogadores (multiplicadores `coop*`);
   - quais upgrades aparecem nas partidas que foram mais longe.
4. Ajuste os coeficientes em `Config` e confira a curva com `love . --curve`
   antes de jogar de novo.

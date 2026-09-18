# SikCid Shootin'

Twin-stick shooter de arena para 1–2 jogadores locais, em LÖVE 11.x. Inimigos
entram por quatro portas em waves infinitas; você atira sozinho, desvia e
segura o combo. Só API nativa do LÖVE: **zero dependências externas**.

Alvo de execução: PC (Linux/Windows) e **Batocera** (sistema `love`).

---

## Rodar

No PC, dentro da pasta do projeto:

```sh
love .
```

Sem controle conectado, o jogador 1 joga no teclado: **WASD** move, **setas**
miram, **Enter** = start, **ESC** = back (segurar 0,5s sai do jogo).

## Empacotar o .love

O `main.lua` precisa ficar na **raiz** do zip — por isso o `.` no fim e o
comando rodando de dentro da pasta:

```sh
cd /caminho/do/projeto
zip -9 -r ./sikcid-shootin.love . -x '.git/*' '*.love' 'build.sh' '.gitignore' 'README.md'
love ./sikcid-shootin.love   # testa o pacote
```

O [build.sh](build.sh) faz isso.

## Instalar no Batocera

```sh
scp sikcid-shootin.love root@batocera:/userdata/roms/love/
```

Depois, no Batocera: **Menu → Configurações do Jogo → Atualizar lista de jogos**
(ou reinicie o frontend). O jogo aparece no sistema **LÖVE**.

> **Não use o sistema `lutro`.** Lutro é um core libretro que implementa um
> subconjunto pequeno e antigo da API do LÖVE — não tem `love.graphics.newCanvas`
> nem a Gamepad API completa, que este jogo usa no núcleo (canvas virtual e
> leitura de controle). Tem que ser o sistema `love`, que roda o LÖVE de verdade.

### Saída do jogo no Batocera

O Batocera não tem hotkey de saída para LÖVE, então o jogo traz a sua:
**SELECT + START segurados por 0,5s** saem do jogo em qualquer tela. Um aviso
discreto com barra de progresso aparece enquanto você segura.

---

## Controles

| Ação | Gamepad | Teclado (P1) |
|------|---------|--------------|
| Mover | analógico esquerdo | WASD |
| Mirar | analógico direito (ou d-pad) | setas |
| Atirar | automático | automático |
| Pausar | START | Enter |
| Voltar / desvincular | BACK (SELECT) | ESC |
| Sair do jogo | SELECT + START (0,5s) | ESC (0,5s) |
| Teste de input | — | F5 |

O tiro é automático (`AUTO_FIRE_ALWAYS` em `src/config.lua`): com o analógico
direito neutro a mira segue o movimento; com os dois neutros, mantém a última
mira válida (no começo da partida, para cima).

### Lobby

1. O primeiro controle que apertar **START** vira o Jogador 1.
2. O **mesmo** controle apertando START de novo começa a partida em 1 jogador.
3. **Qualquer botão** de um segundo controle vincula o Jogador 2; daí em diante
   START de qualquer um dos dois começa a partida em 2 jogadores.
4. **BACK** desvincula. Se o Jogador 1 sair, o Jogador 2 assume o slot 1.

Se um controle vinculado cair durante a partida, o jogo pausa sozinho com
"AGUARDANDO CONTROLE DO JOGADOR N" e volta sozinho quando ele reconectar (o
vínculo é reconhecido pelo GUID do controle).

---

## Onde mexer para tunar dificuldade

Tudo em **[src/config.lua](src/config.lua)**. Não existe número de balanceamento
espalhado em outro arquivo.

| O que | Onde |
|-------|------|
| Curva de waves (cota, inimigos vivos, cadência, tamanho do lote) | `Config.waveQuota` / `waveMaxAlive` / `waveSpawnInterval` / `waveBatch` |
| Quando cada tipo de inimigo entra e com que frequência | `Config.ENEMY_MIX` (`from`, `base`, `perWave`, `min`) |
| HP, velocidade, tamanho e pontos de cada inimigo | `Config.ENEMIES` |
| Repulsão entre inimigos, knockback, tamanho da célula do grid | `Config.ENEMY_SEPARATION`, `ENEMY_KNOCKBACK`, `GRID_CELL` |
| Vidas, velocidade, invulnerabilidade, tempo de respawn | `Config.PLAYER` |
| Cadência, dano, velocidade de bala, spread, míssil, orbes | `Config.WEAPON` |
| Duração, chance de drop e peso de cada power-up | `Config.POWERUP` e `DEFS` em [src/systems/powerups.lua](src/systems/powerups.lua) |
| Janela do combo, degrau e teto do multiplicador | `Config.COMBO` |
| Telégrafo das portas, respiro entre waves, bônus | `Config.WAVE` |
| Screen shake, hit-stop, partículas de morte | `Config.JUICE` |
| Tetos de entidades vivas (tamanho dos pools) | `Config.MAX_ENEMIES`, `MAX_BULLETS`, `MAX_PARTICLES`, `MAX_PICKUPS` |

As fórmulas de wave são funções, não tabela: a curva é infinita. Para deixar o
jogo mais fácil, o mais direto é reduzir o coeficiente quadrático de
`waveQuota` (`0.35 * w * w`) e subir `waveSpawnInterval`.

## Onde trocar quadrados por sprites

Cada entidade concentra **todo** o seu desenho num único método `:draw()`. Trocar
retângulo por sprite é uma mudança local, sem tocar em lógica:

| Entidade | Arquivo |
|----------|---------|
| Jogador (quadrado, mira, orbes, anel de respawn) | [src/entities/player.lua](src/entities/player.lua) → `Player:draw` |
| Inimigos (os 4 tipos, flash de dano, HP do Tank) | [src/entities/enemy.lua](src/entities/enemy.lua) → `Enemy:draw` |
| Balas e mísseis | [src/entities/bullet.lua](src/entities/bullet.lua) → `Bullet:draw` |
| Power-up no chão | [src/entities/pickup.lua](src/entities/pickup.lua) → `Pickup:draw` |
| Partículas | [src/entities/particle.lua](src/entities/particle.lua) → `Particle:draw` |
| Portas e telégrafo | [src/systems/spawner.lua](src/systems/spawner.lua) → `Spawner.draw` |
| Arena, grade, banners | [src/states/game.lua](src/states/game.lua) → `Game:draw` |
| HUD | [src/hud.lua](src/hud.lua) |

Todas as cores vêm de `Config.COLORS` — trocar a paleta é mexer em um lugar só.
O jogo já roda com `love.graphics.setDefaultFilter("nearest")`, então sprites
pixel art escalam sem borrar.

### Som

[src/audio.lua](src/audio.lua) é uma fachada **no-op**: as chamadas
`Audio.play("shot")`, `"enemy_die"`, `"pickup"`, `"wave_clear"` etc. já estão
espalhadas nos lugares certos. Para ligar o som, carregue as Sources em
`Audio.load` e vire `Audio.enabled = true`.

---

## Estrutura

```
main.lua              -- boot, loop, callbacks, parsing de flags
conf.lua              -- janela, módulos do LÖVE
src/config.lua        -- TODAS as constantes e cores
src/screen.lua        -- canvas virtual 640x360, escala inteira, letterbox
src/util.lua          -- vetores, clamp, dist2, swap-remove, sorteio por peso
src/pool.lua          -- pool genérico com teto fixo
src/input.lua         -- devices (gamepad/teclado), deadzone radial, hotplug
src/state.lua         -- pilha de estados de tela
src/save.lua          -- recordes em love.filesystem
src/audio.lua         -- fachada de som (no-op)
src/hud.lua           -- faixa de HUD
src/smoke.lua         -- piloto automático de teste (--smoke)
src/states/           -- lobby, game, pause, gameover, inputtest
src/entities/         -- player, enemy, bullet, pickup, particle
src/systems/          -- spawner, combat, powerups, combo
```

Decisões que sustentam os 60 FPS em hardware modesto:

- **Object pooling** em balas, inimigos, partículas e pickups: as tabelas são
  criadas uma vez e só reinicializadas. Remoção é swap-remove O(1), sem
  `table.insert`/`table.remove` em loop quente.
- **Grid uniforme** de 64px na broadphase de colisão ([src/systems/combat.lua](src/systems/combat.lua)),
  com as células reaproveitadas entre frames. Com 150 inimigos, testar todos os
  pares seria ~11k testes por frame.
- Colisão por **círculo com distância ao quadrado** — nenhum `sqrt` no caminho
  quente.
- Power-ups **recalculam** os modificadores do zero em vez de "desfazer" efeito:
  base + `apply()` de cada ativo. Adicionar power-up é uma entrada em `DEFS`.

---

## Debug e testes

Ligue `Config.DEBUG = true` em `src/config.lua` (ou rode com `--debug`):

| Tecla | Efeito |
|-------|--------|
| F1 | hitboxes |
| F2 | pula a wave |
| F3 | invencibilidade |
| F4 | dropa um power-up aleatório |
| F5 | tela de teste de input (funciona sempre, mesmo sem DEBUG) |

A tela de **teste de input** (F5, ou `love . --inputtest`) mostra todos os
devices com eixos ao vivo, d-pad, botões, deadzone e o progresso do combo de
saída — e lista joysticks que o SDL viu mas **não** sabe mapear como gamepad,
que é a causa mais comum de "o controle não responde".

### Teste automatizado

O jogo tem um piloto automático que joga sozinho e sai com código 0 (ok) ou
1 (erro de runtime), útil para checar regressões sem gamepad:

```sh
love . --smoke 20              # 20 segundos, 1 jogador
love . --smoke 20 --smoke2p    # 2 jogadores
love . --smoke 20 --fakepad    # jogador 1 entra por um gamepad falso
love . --smoke 20 --smokegod   # bots invencíveis (mede FPS sem game over)
love . --smoke 20 --wave 30    # começa numa wave alta
echo $?                        # 0 = rodou sem erro
```

Ao terminar, imprime um resumo: FPS mínimo, waves, kills, mortes, pickups,
combo máximo, pausas, e os **picos de cada pool** com `denied=` (quantas vezes
algo foi recusado por bater no teto). `denied=0` significa que os limites estão
folgados.

`--fakepad` injeta um gamepad falso que implementa a Gamepad API do LÖVE, para
exercitar o mesmo caminho de código dos controles reais em máquinas que não
enxergam joystick (WSL, CI).

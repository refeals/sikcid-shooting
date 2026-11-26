# SikCid Shootin'

Twin-stick shooter de arena para 1–2 jogadores locais, em LÖVE 11.x. Inimigos
entram por quatro portas em waves infinitas; você atira sozinho, desvia e
segura o combo. Só API nativa do LÖVE: **zero dependências externas**.

Alvo de execução: PC (Linux/Windows), **Batocera x86_64** (sistema Ports) e
**navegador** (itch.io, via love.js).

## Documentação

| Arquivo | O que tem |
|---|---|
| [docs/DESIGN.md](docs/DESIGN.md) | como o jogo funciona: controles, dash, power-ups, upgrades, inimigos, sub-bosses, boss |
| [docs/BALANCE.md](docs/BALANCE.md) | metas de dificuldade, curva de waves, recompensas, onde tunar, registro de partidas |
| [docs/PROBLEMS.md](docs/PROBLEMS.md) | bugs conhecidos e números em observação |
| [docs/ROADMAP.md](docs/ROADMAP.md) | o que está em andamento, backlog e histórico |
| [docs/DEPLOY.md](docs/DEPLOY.md) | Batocera, itch.io (versão web), imagens de divulgação |
| [docs/VISUAL.md](docs/VISUAL.md) | renderização, pós-processamento, efeitos, arte |
| [docs/AUDIO.md](docs/AUDIO.md) | efeitos sonoros e música |

---

## Rodar

No PC, dentro da pasta do projeto:

```sh
love .
```

Sem controle conectado, o jogador 1 joga no teclado: **WASD** move, **setas**
miram, **Shift** dá dash, **Enter** = start, **ESC** = back (segurar 0,5s sai
do jogo). Controles completos em [docs/DESIGN.md](docs/DESIGN.md#controles).

## Build

```sh
./build.sh                    # gera o dist/
./build.sh --run              # gera e já abre o .love no LÖVE local para testar
./build.sh --deploy           # gera e copia para o Batocera (root@batocera)
./build.sh --deploy root@IP   # idem, com outro endereço
./build.sh --pull-runs        # traz o runs.csv do Batocera (dist/runs-batocera.csv)
./build.sh --web              # versão web: dist/web/ e dist/SikCidShootin-web.zip
./build.sh --web --run        # gera e serve em http://localhost:8000/
./build.sh --web --compat     # versão web sem threads (fallback)
```

Primeiro deploy no Batocera, página do itch.io e detalhes da versão web:
[docs/DEPLOY.md](docs/DEPLOY.md).

Resultado, pronto para copiar para o Batocera:

```
dist/
  SikCidShootin.sh                  <- launcher do port
  gamelist.xml                      <- entrada do jogo no menu (só este jogo)
  images/                           <- capa, logo e fanart (ver docs/DEPLOY.md)
  .data/sikcid-shootin/
      SikCidShootin.love            <- o jogo
      love/                         <- LÖVE 11.5 extraído (você coloca; ver docs/DEPLOY.md)
```

O `.love` leva só `main.lua`, `conf.lua`, `src/` e `assets/` (com `main.lua` na
raiz do zip, como o LÖVE exige). De `assets/` ficam de fora as imagens de
amostra da Kenney (`*sample*.png`), os `desktop.ini`, o pacote completo de
sons `assets/sfx/Audio/` (~6 MB) e o pacote completo de planetas
`assets/art/PlanetParts/` (~4 MB). Os sons e as peças de planeta que o jogo usa
ficam copiados em `assets/sfx/kenney/` e `assets/art/planets/` e entram
normalmente. O build **não apaga** o `dist/`: só troca o
`.love` e o `.sh`, então o `love/` extraído continua lá entre builds. Se o
`love/` estiver faltando, o script avisa no final com os passos de extração.

## Linha de comando

| Flag | Efeito |
|------|--------|
| `--debug` | liga `Config.DEBUG` (teclas F1–F8, ver abaixo) |
| `--windowed` | abre em janela 1280x720 |
| `--wave N` | começa na wave N |
| `--upgrades N` | começa com N upgrades permanentes aleatórios |
| `--powerup id,id` | dá esses power-ups a todos no início de cada wave |
| `--fx high\|low\|off` | qualidade do pós-processamento (ver [docs/VISUAL.md](docs/VISUAL.md#pós-processamento)) |
| `--mute` | sem som |
| `--inputtest` | abre a tela de teste de input em vez do lobby |
| `--touchmouse` | o mouse vale como um dedo (testar o touch no PC) |
| `--curve` | imprime a curva de waves no console e sai |
| `--media` | regrava as imagens de divulgação em `media/` |
| `--smoke` e companhia | teste automatizado, ver [Teste automatizado](#teste-automatizado) |

## Debug e testes

Ligue `Config.DEBUG = true` em `src/config.lua` (ou rode com `--debug`):

| Tecla | Efeito |
|-------|--------|
| F1 | hitboxes |
| F2 | pula a wave (na wave de boss, mata o boss) |
| F3 | invencibilidade |
| F4 | dropa um power-up aleatório |
| F5 | tela de teste de input (funciona sempre, mesmo sem DEBUG) |
| F6 | shockwave + aberração no centro da arena (tuning de `Config.FX`) |
| F7 | abre a tela de upgrade (Shift+F7 = a de recompensa de boss) |
| F8 | chama o sub-boss do ciclo atual |

A tela de **teste de input** (F5, ou `love . --inputtest`) mostra todos os
devices com eixos ao vivo, d-pad, botões, deadzone e o progresso do combo de
saída — e lista joysticks que o SDL viu mas **não** sabe mapear como gamepad,
que é a causa mais comum de "o controle não responde".

### Aviso de frame lento

Com DEBUG ligado, se o trabalho de um frame passar de 8 ms
(`Config.PROFILE_WARN_MS`), o console mostra qual sistema pesou mais:

```
[perf] frame 10.6ms > 8ms | mais pesado: colisao | inimigos 0.06ms  colisao 10.01ms  particulas 0.00ms  post 0.20ms  resto 0.48ms | in 3 bal 6 par 7
```

- mede o **trabalho** do frame (update + draw), não o `dt`: com vsync o `dt`
  fica em ~16,6 ms mesmo com o jogo folgado, porque inclui a espera pela tela;
- seções: update de inimigos, colisão (grid + testes + separação),
  partículas (update + desenho) e post (brilho e composição da cena; é
  tempo de CPU, a GPU pode demorar mais). `resto` é todo o resto (HUD, balas, jogadores,
  desenho geral); se ele dominar, o aviso diz "fora dos sistemas medidos" em
  vez de culpar o sistema errado;
- no máximo um aviso por segundo, e os primeiros 30 frames (aquecimento: cache
  de fonte, primeiro uso do canvas) não contam.

### Teste automatizado

O jogo tem um piloto automático que joga sozinho e sai com código 0 (ok) ou
1 (erro de runtime), útil para checar regressões sem gamepad:

```sh
love . --smoke 20              # 20 segundos, 1 jogador
love . --smoke 20 --smoke2p    # 2 jogadores
love . --smoke 20 --fakepad    # jogador 1 entra por um gamepad falso
love . --smoke 20 --smokegod   # bots invencíveis (mede FPS sem game over)
love . --smoke 20 --wave 30    # começa numa wave alta
love . --smoke 13 --smoke2p --shots   # salva screenshots de cada tela
love . --smoke 20 --smoketouch # jogador 1 joga só por toques sintéticos
love . --smoke 60 --upgrades 12 --wave 15   # começa com 12 upgrades aleatórios
love . --smoke 60 --smokelog   # grava o registro de partidas em runs-smoke.csv
echo $?                        # 0 = rodou sem erro
```

`--upgrades N` e `--wave N` também valem fora do smoke, para jogar uma build
pronta. Com `--debug`, F7 abre a tela de upgrade na hora (Shift+F7 = a de
recompensa de boss). Os bots escolhem cartas sozinhos e dão dash quando um
inimigo ou tiro chega perto.

Os bots só andam (em círculos de períodos diferentes): nunca miram. A mira e
o tiro ficam com o auto-aim, como um jogador que só pilota.

`--smoketouch` faz o jogador 1 tocar na tela para entrar, começar, pausar
(pelo botão ‖) e voltar, com um dedo no analógico de movimento durante a
partida (com `--shots`, também salva o GAME OVER da arena). Para testar o
touch na mão sem celular, `love . --touchmouse` faz o mouse valer como um
dedo (clicar e arrastar).

Ao terminar, imprime um resumo: FPS mínimo (contado em janelas de 1s depois do
primeiro segundo, sem incluir o tempo de carga), waves, bosses mortos, kills, mortes, pickups,
combo máximo, pausas, e os **picos de cada pool**. `denied=` conta balas e
inimigos recusados por bater no teto (afeta o jogo: deve ser 0); `deniedFx=`
conta partículas descartadas (só efeito visual a menos, aceitável em explosões
grandes). `cores=` mostra os índices de paleta com que os jogadores começaram:
o roteiro troca e sorteia cores no lobby, e o smoke falha (código 1) se os dois
terminarem com a mesma cor. O smoke nunca grava as cores no save.

`--fakepad` injeta um gamepad falso que implementa a Gamepad API do LÖVE, para
exercitar o mesmo caminho de código dos controles reais em máquinas que não
enxergam joystick (WSL, CI).

## Estrutura

```
main.lua              -- boot, loop, callbacks, parsing de flags
conf.lua              -- janela, módulos do LÖVE
src/config.lua        -- TODAS as constantes e cores
src/screen.lua        -- canvas virtual 640x360, escala inteira, letterbox
src/util.lua          -- vetores, clamp, dist2, swap-remove, sorteio por peso
src/pool.lua          -- pool genérico com teto fixo
src/input.lua         -- devices (gamepad/teclado/touch), deadzone radial, hotplug
src/touch.lua         -- analógicos flutuantes e botões de toque
src/state.lua         -- pilha de estados de tela
src/save.lua          -- recordes e cores escolhidas em love.filesystem
src/runlog.lua        -- registro de partidas (runs.csv)
src/curve.lua         -- tabela da curva de waves (--curve)
src/audio.lua         -- efeitos sonoros: variações Kenney, pool de vozes
src/music.lua         -- música de fundo: crossfade, playlist, pausa abafada
src/hud.lua           -- faixa de HUD
src/assets.lua        -- sprites (atlas XML da Kenney), imagens de UI e fontes
src/shaders.lua       -- recolor (vermelho da Kenney -> cor do jogador), escudo
                         do boss, dissolve, faixa de luz
src/ui.lua            -- janela, aba, barra, badge, crosshair e texto (UIPack)
src/background.lua    -- céu animado (seed + relógio), paleta por wave, grade com ondas
src/post.lua          -- pós-processamento: brilho, sombras, shockwave, aberração, vinheta
src/transition.lua    -- varredura diagonal entre telas (só visual)
src/profiler.lua      -- aviso de frame lento (DEBUG)
src/smoke.lua         -- piloto automático de teste (--smoke)
src/states/           -- lobby, briefing, game, pause, upgrade, gameover, inputtest
src/entities/         -- player, enemy (inclui os sub-bosses), boss, bullet,
                         pickup, particle
src/systems/          -- spawner, combat, powerups, upgrades, combo
assets/sfx/           -- efeitos sfxr (.wav); kenney/ = sons Kenney usados;
                         Audio/ = pacote Kenney completo (fora do .love)
assets/music/         -- música de fundo (.ogg)
assets/art/           -- arte da Kenney: folhas + XML, UIPack, fontes;
                         planets/ = peças de planeta usadas;
                         PlanetParts/ = pacote Planets completo (fora do .love)
tools/                -- gerador dos sons, gerador das imagens (media.lua),
                         merge do gamelist do Batocera, servidor local da
                         versão web (fora do .love)
media/                -- capa, logo e fanart geradas por `love . --media`
web/index.html        -- página da versão web (love.js)
docs/                 -- documentação (ver a tabela no topo)
build.sh              -- gera o port em dist/ (ou a versão web, com --web)
```

Decisões que sustentam os 60 FPS em hardware modesto:

- **Object pooling** em balas, inimigos, partículas e pickups: as tabelas são
  criadas uma vez e só reinicializadas. Remoção é swap-remove O(1), sem
  `table.insert`/`table.remove` em loop quente.
- **Grid uniforme** de 64px na broadphase de colisão ([src/systems/combat.lua](src/systems/combat.lua)),
  com as células reaproveitadas entre frames. Com 100 inimigos, testar todos os
  pares seria ~5k testes por frame.
- Colisão por **círculo com distância ao quadrado** — nenhum `sqrt` no caminho
  quente.
- O screen shake é só um `love.graphics.translate` no canvas. Shaders: o
  recolor das peças dos jogadores, o escudo do boss, o blur (brilho e
  sombras) e a composição da cena.
  O blur roda em canvases pequenos de tamanho fixo (no máximo 320x180), então
  custa o mesmo em 720p e em 1080p. A composição é um único passe em tela
  cheia com 3 leituras de textura por pixel.
- Sprites, fontes e peças de UI são criados no boot (~30 ms); nada de imagem é
  alocado durante a partida.
- Power-ups **recalculam** os modificadores do zero em vez de "desfazer" efeito:
  base + `apply()` de cada ativo. Adicionar power-up é uma entrada em `DEFS`
  (e os números dele em `Config.POWERUPS`). Os upgrades permanentes entram
  como camada de base, antes dos power-ups.

## Créditos

- Música: **Music Loop Bundle**, de **Abstraction** (Tallbeard Studios)
  ([itch.io](https://tallbeard.itch.io/music-loop-bundle)): "Sunburn",
  "Cloak of Darkness", "Never Miss" e "Crushing It". Licença CC0; o autor
  pede o nome artístico "Abstraction" nos créditos.
- Arte e fontes: **[Kenney](https://kenney.nl)** (CC0): Space Shooter Extension,
  Simple Space, Planets, UI Pack (Sci-Fi) e Kenney Fonts.
- Efeitos sonoros de combate: **[Kenney](https://kenney.nl)** (CC0), Sci-Fi
  Sounds.
- Demais efeitos sonoros: gerados com o sintetizador do [sfxr](https://sfxr.me)
  (jsfxr), via [tools/gen_sfx.py](tools/gen_sfx.py).
- Versão web: [love.js](https://github.com/Davidobot/love.js) (MIT).


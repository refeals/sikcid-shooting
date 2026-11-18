# SikCid Shootin'

Twin-stick shooter de arena para 1–2 jogadores locais, em LÖVE 11.x. Inimigos
entram por quatro portas em waves infinitas; você atira sozinho, desvia e
segura o combo. Só API nativa do LÖVE: **zero dependências externas**.

Alvo de execução: PC (Linux/Windows) e **Batocera x86_64** (sistema Ports).

---

## Rodar

No PC, dentro da pasta do projeto:

```sh
love .
```

Sem controle conectado, o jogador 1 joga no teclado: **WASD** move, **setas**
miram, **Enter** = start, **ESC** = back (segurar 0,5s sai do jogo).

## Build

```sh
./build.sh                    # gera o dist/
./build.sh --run              # gera e já abre o .love no LÖVE local para testar
./build.sh --deploy           # gera e copia para o Batocera (root@batocera)
./build.sh --deploy root@IP   # idem, com outro endereço
```

Resultado, pronto para copiar para o Batocera:

```
dist/
  SikCidShootin.sh                  <- launcher do port
  .data/sikcid-shootin/
      SikCidShootin.love            <- o jogo
      love/                         <- LÖVE 11.5 extraído (você coloca; ver abaixo)
```

O `.love` leva só `main.lua`, `conf.lua`, `src/` e `assets/` (com `main.lua` na
raiz do zip, como o LÖVE exige). De `assets/` ficam de fora as imagens de
amostra da Kenney (`*sample*.png`), os `desktop.ini` e o pacote completo de
sons `assets/sfx/Audio/` (~6 MB). Os sons que o jogo usa ficam copiados em
`assets/sfx/kenney/` e entram normalmente. O build **não apaga** o `dist/`: só troca o
`.love` e o `.sh`, então o `love/` extraído continua lá entre builds. Se o
`love/` estiver faltando, o script avisa no final com os passos de extração.

## Deploy no Batocera

O jogo roda no sistema **Ports**, com o LÖVE 11.5 de verdade levado junto.
Vale para Batocera em **PC x86_64** — o AppImage do LÖVE é só x86_64 e não
roda em Raspberry Pi/ARM.

1. **Baixe o AppImage x86_64 do LÖVE 11.5** em
   <https://github.com/love2d/love/releases/tag/11.5>
   (arquivo `love-11.5-x86_64.AppImage`).
2. **Extraia** (num Linux ou WSL):
   ```sh
   chmod +x love-11.5-x86_64.AppImage
   ./love-11.5-x86_64.AppImage --appimage-extract
   ```
3. **Renomeie** a pasta gerada `squashfs-root` para `love` e coloque no port:
   ```sh
   mv squashfs-root dist/.data/sikcid-shootin/love
   ```
   Só precisa fazer isso uma vez: os próximos `./build.sh` preservam a pasta.
4. **Copie** para o Batocera:
   ```sh
   ./build.sh --deploy
   ```
   Pede a senha do Batocera uma vez (padrão: `linux`), cria as pastas, envia
   o `.sh`, o `.love` e — só no primeiro deploy, se faltar lá — o `love/`.
5. No Batocera: **Menu → Configurações do Jogo → Atualizar lista de jogos**
   (só da primeira vez). O jogo aparece em **Ports**.

### Atualizar o jogo no Batocera

Depois de qualquer mudança, é um comando só:

```sh
./build.sh --deploy
```

O que muda de um build para outro é o **`.love`** (o jogo); o `.sh` é só o
launcher e o `love/` já está lá. Não precisa atualizar a lista de jogos de novo.
Se o jogo estiver aberto no Batocera, feche e abra.

Outro endereço: `./build.sh --deploy root@192.168.0.50`, ou fixe com
`export BATOCERA_HOST=root@192.168.0.50`. Para não digitar a senha a cada
deploy, instale sua chave uma vez: `ssh-copy-id root@batocera`.

<details>
<summary>Cópia manual (sem o <code>--deploy</code>)</summary>

Crie o `.data` **antes**: se ele não existir, o `scp -r` copia a pasta *com o
nome* `.data` (sem a subpasta `sikcid-shootin`) e o jogo não acha os arquivos.

```sh
ssh root@batocera "mkdir -p /userdata/roms/ports/.data"
scp dist/SikCidShootin.sh root@batocera:/userdata/roms/ports/
scp -r dist/.data/sikcid-shootin root@batocera:/userdata/roms/ports/.data/
```

Pela rede do Windows (`\\BATOCERA\share\roms\ports`) também funciona, desde que
a estrutura final seja exatamente `ports\.data\sikcid-shootin\` — o launcher
repõe sozinho o bit de execução que a cópia via Windows perde.
</details>

O save dos recordes fica em
`/userdata/system/.local/share/love/sikcid-shootin/highscores.dat`.

Estrutura esperada no Batocera:

```
/userdata/roms/ports/
  SikCidShootin.sh
  .data/
    sikcid-shootin/
      SikCidShootin.love
      love/
        AppRun
        usr/...
```

### O jogo abre e fecha na hora

O launcher grava tudo o que acontece em
**`/userdata/system/logs/sikcid-shootin.log`** — inclusive o erro do LÖVE, se
o jogo quebrar. Olhe primeiro ali (`\\BATOCERA\share\system\logs` ou via SSH):

| No log | Causa | Conserto |
|---|---|---|
| `pasta do jogo nao encontrada` | arquivos fora de `ports/.data/sikcid-shootin/` (o `scp -r` sem o `mkdir -p` antes) | mover para a estrutura acima |
| `love/AppRun nao encontrado` | AppImage não extraído ou pasta com outro nome | extrair e renomear `squashfs-root` para `love` |
| `bin/love: Permission denied` / `sem permissao de execucao` | a cópia perdeu o bit de execução (o launcher tenta repor sozinho) | `chmod +x .../sikcid-shootin/love/AppRun .../sikcid-shootin/love/bin/love` |
| `=== ERRO DE RUNTIME ===` | erro no jogo | o traceback está logo abaixo |
| log vazio ou inexistente | o Batocera nem executou o `.sh` | conferir se o `.sh` está em `ports/` e atualizar a lista de jogos |

Para ver ao vivo, via SSH:

```sh
export DISPLAY=:0.0
bash -x /userdata/roms/ports/SikCidShootin.sh; cat /userdata/system/logs/sikcid-shootin.log
```

> **Não use o sistema `lutro`.** Lutro é um core libretro que implementa um
> subconjunto pequeno e antigo da API do LÖVE — não tem `love.graphics.newCanvas`
> nem a Gamepad API completa, que este jogo usa no núcleo (canvas virtual e
> leitura de controle). Tem que ser o LÖVE de verdade, como acima.

> Se algum controle não responder no port, rode o jogo num PC com
> `love . --inputtest` (ou F5 no jogo): a tela mostra se o SDL enxergou o
> controle e se ele tem mapeamento de gamepad.

### Saída do jogo no Batocera

O Batocera não tem hotkey de saída para LÖVE, então o jogo traz a sua, que
funciona em qualquer tela:

- **SELECT segurado por 1s**, ou
- **SELECT + START segurados por 0,5s** (mais rápido, o atalho padrão do Batocera)

Uma barra de progresso aparece enquanto você segura. Um toque rápido em
SELECT não sai: no lobby ele desvincula, no jogo abre a pausa.

---

## Controles

| Ação | Gamepad | Teclado (P1) |
|------|---------|--------------|
| Mover | analógico esquerdo | WASD |
| Mirar | analógico direito (ou d-pad) | setas |
| Atirar | automático | automático |
| Pausar | START ou BACK | Enter ou ESC |
| Desvincular no lobby | BACK (SELECT) | ESC |
| Trocar / sortear a cor no lobby | d-pad ←/→ (ou analógico esquerdo) / Y | A/D ou ←/→ / R |
| Abandonar a partida | BACK na pausa, com confirmação | ESC na pausa |
| Sair do jogo | segurar SELECT (1s) ou SELECT + START (0,5s) | segurar ESC (0,5s) |
| Teste de input | — | F5 |

O tiro é automático (`AUTO_FIRE_ALWAYS` em `src/config.lua`): com o analógico
direito neutro a mira segue o movimento; com os dois neutros, mantém a última
mira válida (no começo da partida, para cima).

Entre uma wave e outra (os 3s de respiro), os timers de **power-up** — os
ativos e os caídos no chão — e de **combo** ficam parados: nada some durante
a pausa, e dá para carregar tudo para a wave seguinte.

### Lobby

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
| Screen shake, hit-stop, explosões (faíscas + fumaça), rastro de míssil | `Config.JUICE` |
| Tetos de entidades vivas (tamanho dos pools; hoje 100 inimigos, 200 balas, 120 partículas) | `Config.MAX_ENEMIES`, `MAX_BULLETS`, `MAX_PARTICLES`, `MAX_PICKUPS` |
| Limiar do aviso de frame lento (DEBUG) | `Config.PROFILE_WARN_MS`, `PROFILE_WARN_INTERVAL` |

As fórmulas de wave são funções, não tabela: a curva é infinita. Para deixar o
jogo mais fácil, o mais direto é reduzir o coeficiente quadrático de
`waveQuota` (`0.35 * w * w`) e subir `waveSpawnInterval`.

## Onde mexer no visual

Cada entidade concentra **todo** o seu desenho num único método `:draw()`;
mudar o visual é uma mudança local, sem tocar em lógica:

| O que | Arquivo |
|-------|---------|
| Jogador (nave recolorida, contorno, chama, crosshair, orbes, escudo, anel de respawn) | [src/entities/player.lua](src/entities/player.lua) → `Player:draw` / `Player.drawShip` |
| Inimigos (os 4 tipos, flash de dano, barra de HP do Tank) | [src/entities/enemy.lua](src/entities/enemy.lua) → `Enemy:draw` |
| Balas, mísseis e brilho dos tiros | [src/entities/bullet.lua](src/entities/bullet.lua) → `Bullet:draw` / `Bullet:drawGlow` |
| Ícone de power-up (chão, HUD e briefing) | [src/entities/pickup.lua](src/entities/pickup.lua) → `Pickup.drawIcon` |
| Explosões (fumaça + faíscas) e rastro de míssil | [src/entities/particle.lua](src/entities/particle.lua) |
| Portas e telégrafo | [src/systems/spawner.lua](src/systems/spawner.lua) → `Spawner.draw` |
| Fundo de estrelas (arena, lobby, game over) | [src/starfield.lua](src/starfield.lua) |
| Arena, grade, banners de wave | [src/states/game.lua](src/states/game.lua) → `Game:draw` |
| HUD | [src/hud.lua](src/hud.lua) |
| Painéis, abas, barras das telas | [src/ui.lua](src/ui.lua) (`UI.window`, `UI.tab`, `UI.bar`, `UI.text`...) |

Cores de jogo em `Config.COLORS`; sprites, tamanhos, fontes e ajustes visuais
em `Config.ART`.

As cores dos jogadores vêm da paleta `Config.PLAYER_PALETTE` (8 cores com nome
em PT-BR, sem o rosa dos tiros inimigos). O lobby escreve a cor escolhida de
cada slot em `Config.PLAYER_COLORS`, que é a lista que todo visual de jogador
lê (nave, tiros, HUD, pausa, game over). A cor inicial de cada slot fica em
`Config.PLAYER_DEFAULT_COLOR`, e a escolha é salva como `color1`/`color2` no
`highscores.dat`. Para adicionar uma cor, basta uma entrada nova na paleta.

### Arte (Kenney)

A arte vem dos pacotes da [Kenney](https://kenney.nl) (CC0) em `assets/art/`:

- **Sprites:** recortados das folhas `spaceShooter2_spritesheet` e
  `simpleSpace_sheet` pelos atlas XML. Cada papel (nave do jogador, inimigo,
  tiro...) aponta para um sprite em `Config.ART.sprites`, e o tamanho na tela
  fica em `Config.ART.size`. Trocar um sprite é mudar o nome ali. Com
  `grey = true`, o sprite é convertido no boot para tons de cinza com base
  branca, para que `setColor` o tinja na cor exata (a chama do motor usa isso
  para sair na cor do jogador).
- **UI:** peças do `UIPack`, desenhadas por [src/ui.lua](src/ui.lua)
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
[src/shaders.lua](src/shaders.lua), que aceita qualquer cor da paleta.

### Som

Os sons de combate e do mundo vêm do pacote **Sci-Fi Sounds da
[Kenney](https://kenney.nl)** (CC0):

| id | Arquivo Kenney | Observação |
|----|----------------|------------|
| `shot` | `laserSmall` | |
| `shot_spread` | `laserRetro` | |
| `shot_missile` | `laserLarge` | pitch 0,9 |
| `shot_enemy` | `laserRetro` | pitch 0,7: mais grave que o spread |
| `enemy_hit` | `impactMetal` | |
| `enemy_die` | `explosionCrunch` | |
| `tank_die` | `lowFrequency_explosion` | |
| `player_die` | `lowFrequency_explosion` | pitch 0,8 |
| `player_spawn` | `forceField` | |
| `door_warn` | `doorOpen` | |

Cada um aponta para o arquivo com `src` e `variants` em `Config.SFX`
(`src = "kenney/laserSmall", variants = 5` carrega `laserSmall_000.ogg` a
`_004.ogg`). A cada disparo sai uma variação sorteada, nunca a mesma duas vezes
seguidas. Só os arquivos usados ficam em **`assets/sfx/kenney/`**. O pacote
completo, em `assets/sfx/Audio/`, fica fora do `.love` (o `build.sh` o exclui)
e serve de fonte: para trocar um som, copie as variações desejadas para
`kenney/` e mude o `src`. Os `thrusterFire` do pacote são loops de 5 s e não
servem para disparos.

Os demais sons (pickups, combo, waves, game over e menu) são sfxr, em
**`assets/sfx/<id>.wav`** (ou `.ogg`), um arquivo por som, com o nome igual ao
id. Esses `.wav` também são o **fallback** dos sons Kenney: se nenhuma variação
de um id carregar, o jogo usa o `<id>.wav`. Eles são gerados por
[tools/gen_sfx.py](tools/gen_sfx.py), um port sem dependências do sintetizador
do [sfxr.me](https://sfxr.me) (jsfxr): `python3 tools/gen_sfx.py` recria todos,
`python3 tools/gen_sfx.py shot pickup` só os citados. Para ajustar um som no
site, cole o conteúdo de `tools/sfx/<id>.json` no campo de texto do sfxr.me,
clique em **Deserialize**, mexa e baixe o `.wav` por cima do gerado. Som sem arquivo é ignorado em silêncio — o console
mostra no boot quantos carregaram, quantas variações Kenney, quantos caíram no
fallback e quanto tempo levou (`[audio] N som(ns) carregado(s) (V variacao(oes)
Kenney), F no fallback sfxr...`).

Os ids, e o volume, número de vozes, pitch base, variação de pitch e intervalo
mínimo de cada um, estão em `Config.SFX` em [src/config.lua](src/config.lua).
Volume geral em `Config.AUDIO.master`; `love . --mute` roda sem som.

[src/audio.lua](src/audio.lua) pré-carrega um **pool de vozes** por arquivo e
usa em rodízio: nenhum `Source` é criado durante o jogo (o tiro automático
dispararia dezenas por segundo). Num som com variações, `voices` é o total,
repartido entre elas (no mínimo uma voz cada). Os clones de um `Source`
estático dividem o mesmo buffer, então mais vozes não gastam mais memória. Som
novo = uma entrada em `Config.SFX` + o arquivo + uma chamada
`Audio.play("id")` no ponto certo.

### Música

Faixas em **`assets/music/<nome>.ogg`**, tocadas em streaming e em loop por
[src/music.lua](src/music.lua). Cada tela pede um **papel** e `Config.MUSIC.tracks`
diz qual faixa toca em cada um:

| Papel | Onde | Faixa atual |
|---|---|---|
| `menu` | lobby, briefing, volta do game over | `danse-contemporaine` |
| `game` | arena | `danse-contemporaine` |

Com os dois papéis na mesma faixa, a música **continua sem reiniciar** do lobby
para a partida. Para ter uma faixa própria na arena, coloque outro `.ogg` em
`assets/music/` e troque o nome em `tracks.game`: o crossfade entre as duas já
está pronto.

Comportamento: fade in ao abrir; na **pausa** a música abaixa para 30%
(`duck`) em vez de parar; no **game over** ela some em fade, o efeito de game
over toca no silêncio e a música de menu volta depois de 2,5 s. Volume geral da
música em `Config.MUSIC.volume` (abaixo dos efeitos, para tiros e explosões
continuarem legíveis). `--mute` silencia tudo.

Para converter uma faixa nova (o `.wav` original não precisa ficar no projeto):

```sh
ffmpeg -i "original.wav" -af volume=-1dB -c:a libvorbis -q:a 4 assets/music/nome.ogg
```

(`-1dB` dá margem: faixa masterizada no teto pode estalar depois da compressão.)

## Créditos

- Música: **"Danse Contemporaine"**, de **Clement Panchout**
  ([itch.io](https://clement-panchout.itch.io)).
- Arte e fontes: **[Kenney](https://kenney.nl)** (CC0): Space Shooter Extension,
  Simple Space, UI Pack (Sci-Fi) e Kenney Fonts.
- Efeitos sonoros de combate: **[Kenney](https://kenney.nl)** (CC0), Sci-Fi
  Sounds.
- Demais efeitos sonoros: gerados com o sintetizador do [sfxr](https://sfxr.me)
  (jsfxr), via [tools/gen_sfx.py](tools/gen_sfx.py).

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
src/audio.lua         -- efeitos sonoros: variações Kenney, pool de vozes
src/music.lua         -- música de fundo: crossfade, pausa abafada
src/hud.lua           -- faixa de HUD
src/assets.lua        -- sprites (atlas XML da Kenney), imagens de UI e fontes
src/shaders.lua       -- recolor: vermelho da Kenney -> cor do jogador
src/ui.lua            -- janela, aba, barra, badge, crosshair e texto (UIPack)
src/starfield.lua     -- fundo de estrelas fixo (seed), com cintilação
src/profiler.lua      -- aviso de frame lento (DEBUG)
src/smoke.lua         -- piloto automático de teste (--smoke)
src/states/           -- lobby, briefing, game, pause, gameover, inputtest
src/entities/         -- player, enemy, bullet, pickup, particle
src/systems/          -- spawner, combat, powerups, combo
assets/sfx/           -- efeitos sfxr (.wav); kenney/ = sons Kenney usados;
                         Audio/ = pacote Kenney completo (fora do .love)
assets/music/         -- música de fundo (.ogg)
assets/art/           -- arte da Kenney: folhas + XML, UIPack, fontes
tools/                -- gerador dos sons (fora do .love)
build.sh              -- gera o port em dist/
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
- O screen shake é só um `love.graphics.translate` no canvas. O único shader
  é o de recolor das peças dos jogadores.
- Sprites, fontes e peças de UI são criados no boot (~30 ms); nada de imagem é
  alocado durante a partida.
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

### Aviso de frame lento

Com DEBUG ligado, se o trabalho de um frame passar de 8 ms
(`Config.PROFILE_WARN_MS`), o console mostra qual sistema pesou mais:

```
[perf] frame 10.6ms > 8ms | mais pesado: colisao | inimigos 0.06ms  colisao 10.01ms  particulas 0.00ms  resto 0.48ms | in 3 bal 6 par 7
```

- mede o **trabalho** do frame (update + draw), não o `dt`: com vsync o `dt`
  fica em ~16,6 ms mesmo com o jogo folgado, porque inclui a espera pela tela;
- seções: update de inimigos, colisão (grid + testes + separação) e
  partículas (update + desenho). `resto` é todo o resto (HUD, balas, jogadores,
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
echo $?                        # 0 = rodou sem erro
```

Ao terminar, imprime um resumo: FPS mínimo (contado em janelas de 1s depois do
primeiro segundo, sem incluir o tempo de carga), waves, kills, mortes, pickups,
combo máximo, pausas, e os **picos de cada pool**. `denied=` conta balas e
inimigos recusados por bater no teto (afeta o jogo: deve ser 0); `deniedFx=`
conta partículas descartadas (só efeito visual a menos, aceitável em explosões
grandes). `cores=` mostra os índices de paleta com que os jogadores começaram:
o roteiro troca e sorteia cores no lobby, e o smoke falha (código 1) se os dois
terminarem com a mesma cor. O smoke nunca grava as cores no save.

`--fakepad` injeta um gamepad falso que implementa a Gamepad API do LÖVE, para
exercitar o mesmo caminho de código dos controles reais em máquinas que não
enxergam joystick (WSL, CI).

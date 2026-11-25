# SikCid Shootin'

Twin-stick shooter de arena para 1–2 jogadores locais, em LÖVE 11.x. Inimigos
entram por quatro portas em waves infinitas; você atira sozinho, desvia e
segura o combo. Só API nativa do LÖVE: **zero dependências externas**.

Alvo de execução: PC (Linux/Windows), **Batocera x86_64** (sistema Ports) e
**navegador** (itch.io, via love.js).

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
  gamelist.xml                      <- entrada do jogo no menu (só este jogo)
  images/                           <- capa, logo e fanart (ver "Imagens do jogo")
  .data/sikcid-shootin/
      SikCidShootin.love            <- o jogo
      love/                         <- LÖVE 11.5 extraído (você coloca; ver abaixo)
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

### Imagens do jogo (capa, logo, fanart)

As imagens do menu do Batocera e da página do itch.io ficam versionadas em
`media/` e são **geradas pelo próprio jogo**, com os sprites, o céu, os shaders
e as fontes de verdade:

```sh
love . --media        # regrava media/cover.png, logo.png, banner.png, fanart.png e page-bg.png
```

| Arquivo | Tamanho | Batocera | itch.io |
|---------|---------|----------|---------|
| `media/cover.png` | 1260x1000 | `image` e `thumbnail` (capa na lista) | *Cover image* (proporção 630x500) |
| `media/logo.png` | 1200 de largura, fundo transparente | `marquee` (logo) | — |
| `media/banner.png` | 960x133, uma linha, sem subtítulo, fundo transparente | — | banner da página (*Edit theme*) |
| `media/fanart.png` | 1920x1080, sem logo | `fanart` (fundo, nos temas que usam) | imagem de divulgação |
| `media/page-bg.png` | 2560x1440, bordas e base somem em `#0a0a0f` | — | fundo da página (*Edit theme*) |

A cena (posição do boss, dos jogadores, inimigos, tiros e explosões), o tema do
céu, as cores dos jogadores e o texto do logo ficam em
[tools/media.lua](tools/media.lua) (`SCENE`, `LOGO_LINES`, `SUBTITLE`). O
gerador fica em `tools/`, então **não entra no `.love`**: `--media` só
funciona rodando da pasta do projeto. Depois de mexer na arte do jogo, rode de
novo e faça commit dos PNGs.

O `./build.sh` copia as imagens para `dist/images/` com os nomes que o
scraper do Batocera usa (`SikCidShootin-image.png`, `-marquee.png`,
`-fanart.png`) e escreve o `dist/gamelist.xml` com nome, descrição, ano de
lançamento, desenvolvedora, gênero, jogadores e os caminhos das imagens. Para mudar a descrição do menu, edite o
`gamelist.xml` dentro do [build.sh](build.sh).

## Build web (itch.io)

```sh
./build.sh --web              # gera dist/web/ e dist/SikCidShootin-web.zip
./build.sh --web --run        # gera e serve em http://localhost:8000/
./build.sh --web --compat     # versão sem threads (fallback, ver abaixo)
```

Precisa de Node.js (`npx`). O mesmo `.love` vira página web com o
[love.js](https://github.com/Davidobot/love.js) **11.4.1, pinado** — o build
roda LÖVE 11.4 em WebAssembly, sem LuaJIT. No lugar dos passos do Batocera, o
`--web`:

1. gera a página com `npx love.js@11.4.1`;
2. aplica um patch no `love.js` gerado que expõe `Module.FS` (o build **falha**
   se o patch não aplicar). O love.js só grava o save no IndexedDB ao fechar a
   aba, o que o navegador costuma cortar; com o patch, a página grava a cada 3s
   e quando a aba fica escondida;
3. troca o `index.html` gerado pelo [web/index.html](web/index.html): página
   preta, sem título/rodapé, canvas 1280x720 escalado para caber (botão de tela
   cheia do itch);
4. zipa tudo com o `index.html` na raiz, como o itch.io pede.

**Teste local** sempre por `--run` (ou `python3 tools/serve_web.py dist/web`):
o build normal usa threads (SharedArrayBuffer), e o navegador só libera isso
com os headers COOP/COEP, que o `python -m http.server` não manda. Argumentos
do jogo vão na URL, separados por `&`:

```
http://localhost:8000/?--debug
http://localhost:8000/?--smoke&60&--smoke2p&--smokegod&--wave&10&--debug
```

O segundo é o teste de desempenho: FPS no canto e aviso `[perf]` no console
(F12). Rode no Chrome e no Firefox; abaixo de ~55 FPS sustentados não publique.

### Página no itch.io

Primeiro upload (depois é só trocar o zip):

- **Kind of project:** HTML. Suba o `dist/SikCidShootin-web.zip` e marque
  *This file will be played in the browser*.
- **Embed options:** viewport **1280 x 720**; **SharedArrayBuffer support**
  ligado (sem isso o build normal não abre); *Fullscreen button* ligado;
  *Mobile friendly* ligado, com orientação **landscape** (o jogo tem
  controles touch, ver "Controles touch").
- **Cover image:** `media/cover.png`. Ver "Imagens do jogo".
- **Edit theme:** banner `media/banner.png` (transparente, uma linha), fundo
  `media/page-bg.png` sem repetir. Cores: BG `#0a0a0f`, BG 2 `#1a1d2b`, texto
  `#e6ebff`, link e botão `#ffd64d` (texto do botão `#0a0a0f`). O itch não
  escala o fundo: o `page-bg.png` some na cor do BG, então em tela maior que
  ele não aparece borda.
- **Visibilidade:** Draft ou Restricted enquanto for playtest.
- **Créditos** na descrição: LÖVE, love.js (MIT), Kenney (CC0), música do
  Music Loop Bundle de Abstraction (Tallbeard Studios).

Se o build normal não abrir em algum navegador (a opção SharedArrayBuffer do
itch é experimental), suba o zip de `--web --compat`: roda sem threads e sem
headers, com áudio pior (estalos/latência).

### Diferenças da versão web

- **Não existe "sair do jogo"**: o combo de saída é desligado e as dicas dele
  somem (`Config.WEB`). Fechar a aba é a saída.
- Abre em janela, não em tela cheia (o navegador só deixa com clique do
  jogador). ESC em tela cheia é do navegador: pause com **Enter**.
- Pós-processamento em qualidade `low` (brilho em 160x90, sem o halo largo);
  ver "Pós-processamento".
- Sprites sem mipmaps (WebGL 1 não faz mipmap de textura fora de potência de
  2): podem serrilhar um pouco quando desenhados bem menores.
- O áudio só começa depois da primeira tecla/clique (regra de autoplay).
- Gamepad: testado com um controle no Chrome. O navegador só mostra o controle
  depois do primeiro botão (o START pode precisar de dois toques). Dois
  controles idênticos podem ser confundidos ao reconectar.
- Safari/iOS não são suportados.

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
   o `.sh`, o `.love`, as imagens do menu e — só no primeiro deploy, se faltar
   lá — o `love/`. A entrada do jogo (nome, descrição, imagens) é **mesclada**
   no `ports/gamelist.xml` pelo Python do próprio Batocera
   ([tools/merge_gamelist.py](tools/merge_gamelist.py)): os outros ports e o
   histórico do jogo (vezes jogado, favorito) ficam intactos, e o arquivo
   original é guardado uma vez em `gamelist.xml.bak`. Em seguida o deploy
   manda o EmulationStation **recarregar a lista** pela API local dele
   (`http://127.0.0.1:1234/reloadgames`): o jogo aparece em **Ports** com
   capa, logo e descrição, sem mexer em nada no Batocera.

   Por que recarregar: o ES guarda a lista na memória e, a cada partida,
   regrava o `<game>` inteiro do jogo a partir dela. Um `gamelist.xml`
   alterado com o ES aberto e sem reload perde a descrição, o logo e o
   fanart na próxima vez que o jogo for jogado. Se o deploy avisar que o ES
   não respondeu, reinicie o Batocera.

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
ssh root@batocera "mkdir -p /userdata/roms/ports/.data /userdata/roms/ports/images"
scp dist/SikCidShootin.sh root@batocera:/userdata/roms/ports/
scp -r dist/.data/sikcid-shootin root@batocera:/userdata/roms/ports/.data/
scp dist/images/*.png root@batocera:/userdata/roms/ports/images/
```

Para as imagens aparecerem, a entrada do `dist/gamelist.xml` precisa estar no
`ports/gamelist.xml`. **Não copie o arquivo por cima** se já existir um lá
(ele tem os outros ports): mescle com
`ssh root@batocera "python3 - /userdata/roms/ports/gamelist.xml /userdata/roms/ports/.data/sikcid-shootin/gamelist-entry.xml" < tools/merge_gamelist.py`,
depois de copiar o `dist/gamelist.xml` para esse `gamelist-entry.xml`. Se não
existir nenhum `gamelist.xml` em `ports/`, copiar o do `dist/` direto funciona.

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

O tiro é automático (`Config.AUTO_AIM` em `src/config.lua`): sem mira manual,
a nave mira e atira sozinha no inimigo visível mais próximo e segura esse alvo
até ele morrer, sair da tela ou outro ficar bem mais perto. Sem nenhum
inimigo na tela, ela não atira e aponta para onde está andando. O
analógico direito (ou o d-pad; no teclado, as setas) sempre tem prioridade
sobre a mira automática.

Entre uma wave e outra (os 3s de respiro), os timers de **power-up** — os
ativos e os caídos no chão — e de **combo** ficam parados: nada some durante
a pausa, e dá para carregar tudo para a wave seguinte. Na wave do boss eles
também param enquanto ele não pode ser atingido (alerta, entrada e explosão
final). Quando a wave fecha, os tiros inimigos que ainda estavam voando somem.
O power-up garantido do
fim da wave cai no ponto livre mais longe dos jogadores (e de onde quem está
morto vai renascer), para ninguém pegar sem ver o que é.

### Power-ups

| Letra | Power-up | Efeito |
|-------|----------|--------|
| S | SPREAD | 3 tiros em leque (arma) |
| R | RAPID FIRE | cadência em dobro (arma) |
| M | MISSILES | mísseis teleguiados, dano 3 (arma) |
| V | SPEED BOOTS | 40% mais velocidade |
| B | BOLHA | segura 1 golpe; ao estourar, empurra os inimigos em volta e dá 1s de invulnerabilidade |
| D | DRONE | drone que orbita a nave e atira sozinho (10/s) no inimigo mais próximo; os tiros são bolinhas de energia, diferentes dos da nave |
| X | DANO X2 | dobra o dano de qualquer arma (e do drone) |
| N | NOVA | na hora: onda de choque em volta, dano 5 e apaga os tiros inimigos no raio |
| + | EXTRA LIFE | na hora: +1 vida (máx. 5) |

Armas (S, R, M) se substituem; os outros acumulam. Pegar um que já está ativo
renova o tempo.

Um power-up no chão dura 10 s (`Config.POWERUP.pickupLife`). Nos últimos
3 s ele pisca em **branco**, cada vez mais rápido, e quando o tempo acaba ele
se desfaz em ~0,3 s. Dá para pegar durante esse desfazer: é a última chance.

Visual dos power-ups no chão (`Config.FX.pickup`):

- **Ao cair:** surge com um "pop" (cresce além do tamanho e volta) e um anel
  fino na sua cor.
- **Parado:** uma faixa de luz atravessa o badge a cada ~2 s, cada pickup no
  seu próprio ritmo.
- **Ao pegar:** um anel na cor do power-up sai da nave e o nome dele (ex.:
  "SPREAD") sobe e some sobre ela. O texto é desenhado por cima da arena,
  nítido, sem as distorções do pós-processamento.

### Morte e respawn

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

### Game over

Quando o último jogador perde a última vida, a explosão roda em câmera lenta
e a arena continua viva: os inimigos seguem vagando, mas as portas fecham.
1s depois, a arena escurece e aparecem **GAME OVER**, a wave alcançada e a
pontuação de cada jogador. Depois aparece **APERTE START**, que leva para a
tela de resultados. Tempos e efeitos ficam em `Config.GAME_OVER`.

### Boss

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

### Registro de partidas (runs.csv)

Toda partida grava `runs.csv` na pasta de save do LÖVE, junto do
`highscores.dat`: uma linha por wave (tempo, mortes e o que matou, vidas,
upgrades, pontos) e um resumo por partida (wave final, duração, upgrades,
última morte, se terminou em game over, abandono ou fechando o jogo). As
colunas estão descritas no topo de [src/runlog.lua](src/runlog.lua). Abre em
qualquer planilha.

| Onde | Arquivo |
|------|---------|
| Windows | `%APPDATA%\LOVE\sikcid-shootin\runs.csv` |
| Linux | `~/.local/share/love/sikcid-shootin/runs.csv` |
| Batocera | `/userdata/system/.local/share/love/sikcid-shootin/runs.csv`; traga para o PC com `./build.sh --pull-runs` (vira `dist/runs-batocera.csv`) |
| Navegador | gravado no IndexedDB, sem como baixar |

O teste automatizado não grava nada aí (com `--smokelog` ele grava num
arquivo à parte, `runs-smoke.csv`).

Os bosses seguem a mesma ideia: cada valor que escala é `base + perBoss * (n - 1)`
(n = 1 na wave 10, 2 na wave 20...), com `min`/`max` opcionais. Para testar um
boss direto: `love . --wave 10 --debug` (F2 mata o boss, F3 deixa invencível).

## Onde mexer no visual

Cada entidade concentra **todo** o seu desenho num único método `:draw()`;
mudar o visual é uma mudança local, sem tocar em lógica:

| O que | Arquivo |
|-------|---------|
| Jogador (nave recolorida, contorno, chama, crosshair, bolha, drone, escudo, anel e marcador de respawn) | [src/entities/player.lua](src/entities/player.lua) → `Player:draw` / `Player.drawShip` |
| Inimigos (os 4 tipos, flash de dano, barra de HP do Tank) | [src/entities/enemy.lua](src/entities/enemy.lua) → `Enemy:draw` |
| Boss (nave recolorida, fogo nos bocais de cada nave, flash, pulso de fúria, tremor na morte, escudo da entrada) | [src/entities/boss.lua](src/entities/boss.lua) → `Boss:draw`; shader do escudo em [src/shaders.lua](src/shaders.lua) |
| Balas, mísseis e brilho dos tiros | [src/entities/bullet.lua](src/entities/bullet.lua) → `Bullet:draw` / `Bullet:drawGlow` |
| Ícone de power-up (chão, HUD e briefing) | [src/entities/pickup.lua](src/entities/pickup.lua) → `Pickup.drawIcon` |
| Explosões (clarão, fogo, faíscas, fumaça, destroços), faíscas de impacto e rastro de míssil | [src/entities/particle.lua](src/entities/particle.lua); presets em `Config.JUICE.explosions` (ver "Explosões") |
| Portas e telégrafo | [src/systems/spawner.lua](src/systems/spawner.lua) → `Spawner.draw` |
| Fundo: nebulosa, estrelas em camadas, objetos distantes, brilhos, estrelas cadentes, paleta por bloco de waves entre bosses (vermelha na wave de boss) e grade com ondas | [src/background.lua](src/background.lua) (tuning em `Config.ART.background`) |
| Arena, banners de wave | [src/states/game.lua](src/states/game.lua) → `Game:draw` |
| HUD (score contando, socos no score e no combo, COMBO PERDIDO caindo) | [src/hud.lua](src/hud.lua) → `Hud.update` / `Hud.draw` (ver "Juice da interface") |
| Banners de wave (entrada, faixa de luz, bônus contando) | [src/states/game.lua](src/states/game.lua) → `drawBannerText` |
| Painéis, abas, barras das telas | [src/ui.lua](src/ui.lua) (`UI.window`, `UI.tab`, `UI.bar`, `UI.text`...) |
| Pós-processamento (brilho, sombras, shockwave, aberração, vinheta) | [src/post.lua](src/post.lua) + o `:drawGlow()` / `:drawShadow()` de cada entidade |
| Véu do céu e marcas de queimado na arena | [src/states/game.lua](src/states/game.lua) → `Game:draw`, `world:scorch` |
| Clarão no cano, rastro dos tiros, fita do motor, ecos dos runners | `Player:draw` / `Bullet:drawTrail` / `Enemy:drawEchoes` / `Boss:draw` (ver "Tiro e movimento") |

Cores de jogo em `Config.COLORS`; sprites, tamanhos, fontes e ajustes visuais
em `Config.ART`.

As cores dos jogadores vêm da paleta `Config.PLAYER_PALETTE` (8 cores com nome
em PT-BR, sem o rosa dos tiros inimigos). O lobby escreve a cor escolhida de
cada slot em `Config.PLAYER_COLORS`, que é a lista que todo visual de jogador
lê (nave, tiros, HUD, pausa, game over). A cor inicial de cada slot fica em
`Config.PLAYER_DEFAULT_COLOR`, e a escolha é salva como `color1`/`color2` no
`highscores.dat`. Para adicionar uma cor, basta uma entrada nova na paleta.

### Explosões

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

### Profundidade

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

### Tiro e movimento

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

### Juice da interface

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

### Transições de tela

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
roteiro do smoke test não esperam nada). [src/transition.lua](src/transition.lua)
copia o último frame (o canvas da tela ainda o guarda no instante da troca) e
o desenha por cima da tela nova através de um shader. Sem o shader, a foto
some num fade simples. Tempo e cores em `Config.FX.transition`; o som é
`transition` em `Config.SFX`.

### Surgir e sumir

Um shader de dissolve ([src/shaders.lua](src/shaders.lua), `Shaders.dissolve`)
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
  power-up (ver "Power-ups").
- Sem o shader, tudo isso vira um fade simples. Tempos em
  `Config.FX.dissolve`.

### Pós-processamento

A arena (do céu ao brilho) é desenhada num canvas de cena e passa por um
shader de composição antes de ir para a tela. Banners, textos e HUD são
desenhados depois, nítidos e sem distorção. Tudo fica em
[src/post.lua](src/post.lua), com o tuning em `Config.FX`.

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
dispara uma shockwave com aberração no centro, para tunar.

**Qualidade:** `Config.FX.quality`, ou `love . --fx high|low|off` na linha de
comando. Em `auto`, usa `low` no navegador e `high` no resto.

| Qualidade | Brilho | Composição da cena |
|---|---|---|
| `high` | 320x180 + halo largo em 160x90 | ligada |
| `low` | 160x90 | ligada |
| `off` | sem blur | desligada (sem shockwave, aberração e vinheta) |

Se um shader não compilar, o jogo segue sem aquele efeito (o brilho fica sem
blur, a cena desenha direto na tela) e avisa no console (`[post] ...
unavailable`).

### Arte (Kenney)

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
  [src/background.lua](src/background.lua) a partir das peças do pacote
  Planets em `assets/art/planets/`: esfera tingida + texturas de superfície
  tingidas + mapa de luz multiplicado (crescente). Cada tema escolhe as peças,
  as cores, a posição e o tamanho em `Config.ART.background.themes[i].planet`.
  Para usar uma peça nova, copie-a de `PlanetParts/` para `planets/`.
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

Faixas em **`assets/music/<nome>.ogg`**, tocadas por [src/music.lua](src/music.lua).
Cada tela pede um **papel** e `Config.MUSIC.tracks` diz o que toca em cada um:
uma faixa em loop (`file`) ou uma **playlist** (`playlist`), em que as faixas
tocam em sequência e sem intervalo (a → b → c → a…):

| Papel | Onde | Faixa |
|---|---|---|
| `menu` | lobby, briefing | `sunburn` |
| `game` | waves comuns | playlist `cloak-of-darkness-1` → `-2` → `-3` |
| `boss` | luta contra o boss | `never-miss` (fade in de 3 s) |
| `gameover` | tela de game over | `crushing-it` |

Comportamento:

- Troca de papel = crossfade (`fadeTime`, 0,6 s). Um papel pode ter `fadeIn`
  próprio e `gain` (0..1) para igualar o volume entre faixas.
- Um papel que sumiu por completo recomeça do início ao voltar: a playlist das
  waves volta ao STAGE 1 depois de cada boss e em cada partida nova.
- **Boss:** a música das waves continua durante o ALERTA e a entrada. Quando a
  luta começa de fato, ela sai em 0,6 s e `never-miss` sobe em 3 s, porque a
  faixa já começa agitada.
- **Pausa:** a música abaixa para 30% (`duck`) em vez de parar.
- **Game over:** a música some em fade quando o último jogador explode, o
  efeito de game over toca quando o texto GAME OVER aparece na arena, e
  `crushing-it` entra 2,5 s depois dele, já na tela de resultados. De volta
  ao lobby, crossfade para `sunburn`.
- Volume geral em `Config.MUSIC.volume` (abaixo dos efeitos, para tiros e
  explosões continuarem legíveis). `--mute` silencia tudo.

A playlist usa uma `QueueableSource`, abastecida a cada frame com um `Decoder`
por faixa, e por isso a emenda entre os STAGEs não tem intervalo. Todas as
faixas de uma playlist precisam do mesmo formato (sample rate, bits, canais).

`schmoovin.ogg` e `danse-contemporaine.ogg` ficam em `assets/music/` sem uso; o
`build.sh` não as empacota.

Para converter uma faixa nova (o `.wav` original não precisa ficar no projeto):

```sh
ffmpeg -i "original.wav" -af volume=-1dB -c:a libvorbis -q:a 4 assets/music/nome.ogg
```

(`-1dB` dá margem: faixa masterizada no teto pode estalar depois da compressão.)

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
src/shaders.lua       -- recolor (vermelho da Kenney -> cor do jogador), escudo do boss
src/ui.lua            -- janela, aba, barra, badge, crosshair e texto (UIPack)
src/background.lua    -- céu animado (seed + relógio), paleta por wave, grade com ondas
src/post.lua          -- pós-processamento: brilho, shockwave, aberração, vinheta
src/transition.lua    -- varredura diagonal entre telas (só visual)
src/profiler.lua      -- aviso de frame lento (DEBUG)
src/smoke.lua         -- piloto automático de teste (--smoke)
src/states/           -- lobby, briefing, game, pause, gameover, inputtest
src/entities/         -- player, enemy, boss, bullet, pickup, particle
src/systems/          -- spawner, combat, powerups, combo
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
  (e os números dele em `Config.POWERUPS`).

---

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

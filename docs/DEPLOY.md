# Deploy e publicação

Como levar o jogo para o Batocera e para o itch.io, e como gerar as imagens de
divulgação. Os comandos básicos de build estão no [README](../README.md#build).

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
   ([tools/merge_gamelist.py](../tools/merge_gamelist.py)): os outros ports e o
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
launcher (ele chama o jogo com `--batocera`: sempre em tela cheia, sem o item
TELA CHEIA nas opções) e o `love/` já está lá. O `--deploy` reenvia o `.sh`
junto. Não precisa atualizar a lista de jogos de novo.
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

O save fica em `/userdata/system/.local/share/love/sikcid-shootin/`:
`highscores.dat` (recordes, acumulados da máquina e cores) e `options.dat`
(opções do menu).

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

> Se algum controle não responder no port, abra **OPÇÕES > TESTAR CONTROLES**
> com um controle que funcione (ou rode num PC com `love . --inputtest`, ou F5
> no jogo): a tela mostra se o SDL enxergou o
> controle e se ele tem mapeamento de gamepad.

### Saída do jogo no Batocera

O Batocera não tem hotkey de saída para LÖVE, então o jogo traz a sua, que
funciona em qualquer tela:

- **SELECT segurado por 1s**, ou
- **SELECT + START segurados por 0,5s** (mais rápido, o atalho padrão do Batocera)

Uma barra de progresso aparece enquanto você segura. Um toque rápido em
SELECT não sai: no lobby ele desvincula (com o lobby vazio, volta ao menu), no
jogo abre a pausa. No menu principal, o item **SAIR** também fecha o jogo.

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
3. troca o `index.html` gerado pelo [web/index.html](../web/index.html): página
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
  controles touch, ver [Controles touch](DESIGN.md#controles-touch-celular-tablet)).
- **Cover image:** `media/cover.png`. Ver [Imagens do jogo](#imagens-do-jogo-capa-logo-fanart).
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

- **Não existe "sair do jogo"**: o combo de saída é desligado, as dicas dele
  somem e o menu principal não tem SAIR (`Config.WEB`). Fechar a aba é a saída.
- Abre em janela, não em tela cheia (o navegador só deixa com clique do
  jogador), e as opções não têm TELA CHEIA: a página do itch.io tem o botão
  dela. ESC em tela cheia é do navegador: pause com **Enter** e volte nos
  menus com **Backspace**.
- Pós-processamento em qualidade `low` (brilho em 160x90, sem o halo largo);
  ver [Pós-processamento](VISUAL.md#pós-processamento).
- Sprites sem mipmaps (WebGL 1 não faz mipmap de textura fora de potência de
  2): podem serrilhar um pouco quando desenhados bem menores.
- O áudio só começa depois da primeira tecla/clique (regra de autoplay).
- Gamepad: testado com um controle no Chrome. O navegador só mostra o controle
  depois do primeiro botão (o START pode precisar de dois toques). Dois
  controles idênticos podem ser confundidos ao reconectar.
- Safari/iOS não são suportados.

## Imagens do jogo (capa, logo, fanart)

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
[tools/media.lua](../tools/media.lua) (`SCENE`, `LOGO_LINES`, `SUBTITLE`). O
subtítulo é sempre em inglês, o idioma padrão do jogo. O
gerador fica em `tools/`, então **não entra no `.love`**: `--media` só
funciona rodando da pasta do projeto. Depois de mexer na arte do jogo, rode de
novo e faça commit dos PNGs.

O `./build.sh` copia as imagens para `dist/images/` com os nomes que o
scraper do Batocera usa (`SikCidShootin-image.png`, `-marquee.png`,
`-fanart.png`) e escreve o `dist/gamelist.xml` com nome, descrição, ano de
lançamento, desenvolvedora, gênero, jogadores e os caminhos das imagens. Para mudar a descrição do menu, edite o
`gamelist.xml` dentro do [build.sh](../build.sh).


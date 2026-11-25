#!/bin/bash
# Gera o port do SikCid Shootin' para o sistema "Ports" do Batocera:
#
#   dist/
#     SikCidShootin.sh
#     gamelist.xml         <- entrada do jogo no menu (nome, descrição, imagens)
#     images/              <- capa, logo e fanart (de media/, ver tools/media.lua)
#     .data/sikcid-shootin/
#         SikCidShootin.love
#         love/            <- AppImage do LÖVE extraído (colocado à mão)
#
# Uso:  ./build.sh                  gera o dist/
#       ./build.sh --run            gera e abre o .love no LÖVE local para testar
#       ./build.sh --deploy [host]  gera e copia para o Batocera (padrão:
#                                   root@batocera.local, ou $BATOCERA_HOST)
#
# Com --web gera a versão de navegador (love.js) para o itch.io, no lugar do
# port Batocera:
#
#   dist/
#     web/                   <- página jogável (index.html, love.js, game.data...)
#     SikCidShootin-web.zip  <- o mesmo, zipado para upload no itch.io
#
#       ./build.sh --web            gera dist/web/ e o zip
#       ./build.sh --web --run      gera e serve em http://localhost:8000/
#       ./build.sh --web --compat   versão sem threads (sem SharedArrayBuffer)
set -e
cd "$(dirname "$(readlink -f "$0")")"

NAME="SikCidShootin"
DATA_DIR="dist/.data/sikcid-shootin"
LOVE_FILE="${DATA_DIR}/${NAME}.love"
LAUNCHER="dist/${NAME}.sh"

usage() {
  cat <<'EOF'
Uso:  ./build.sh                  gera o dist/
      ./build.sh --run            gera e abre o .love no LOVE local para testar
      ./build.sh --deploy [host]  gera e copia para o Batocera
                                  (padrao: root@batocera.local, ou $BATOCERA_HOST)
      ./build.sh --web            gera a versao web (dist/web/ + zip p/ itch.io)
      ./build.sh --web --run      gera e serve em http://localhost:8000/
      ./build.sh --web --compat   versao web sem threads (sem SharedArrayBuffer)
      ./build.sh --pull-runs [host]  traz o runs.csv (registro de partidas)
                                     do Batocera para dist/runs-batocera.csv
EOF
}

RUN=0
DEPLOY=0
PULL=0
WEB=0
COMPAT=0
HOST="${BATOCERA_HOST:-root@batocera.local}"
while [ $# -gt 0 ]; do
  case "$1" in
    --run) RUN=1 ;;
    --web) WEB=1 ;;
    --compat) COMPAT=1 ;;
    --deploy)
      DEPLOY=1
      # Host opcional logo depois (qualquer coisa que não seja outra opção).
      if [ -n "${2:-}" ] && [ "${2#--}" = "$2" ]; then HOST="$2"; shift; fi
      ;;
    --pull-runs)
      PULL=1
      if [ -n "${2:-}" ] && [ "${2#--}" = "$2" ]; then HOST="$2"; shift; fi
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "opcao desconhecida: $1"; usage; exit 1 ;;
  esac
  shift
done

# Run log (src/runlog.lua): copies the Batocera's runs.csv here, nothing is
# built. LÖVE keeps it in $HOME/.local/share/love/sikcid-shootin/; if it is
# not there (another HOME/XDG setup), it is searched for under /userdata.
if [ "$PULL" = 1 ]; then
  mkdir -p dist
  OUT="dist/runs-batocera.csv"
  echo "Trazendo o registro de partidas de ${HOST}..."
  if ! "${SSH:-ssh}" -o ConnectTimeout=8 "$HOST" \
      'f="$HOME/.local/share/love/sikcid-shootin/runs.csv"
       [ -f "$f" ] || f=$(find /userdata -name runs.csv -path "*sikcid-shootin*" 2>/dev/null | head -n 1)
       [ -n "$f" ] && [ -f "$f" ] && cat "$f"' > "${OUT}.tmp"; then
    rm -f "${OUT}.tmp"
    echo "ERRO: nao achei o runs.csv em ${HOST} (ou nao consegui conectar)."
    echo "      O jogo ja foi jogado la depois desta versao? Teste com: ssh ${HOST}"
    exit 1
  fi
  mv -f "${OUT}.tmp" "$OUT"
  echo "OK: ${OUT} ($(($(wc -l < "$OUT") - 1)) linhas)"
  exit 0
fi

if [ "$WEB" = 1 ] && [ "$DEPLOY" = 1 ]; then
  echo "--web e --deploy nao combinam: o deploy e so para o Batocera."; exit 1
fi
if [ "$COMPAT" = 1 ] && [ "$WEB" = 0 ]; then
  echo "--compat so vale junto com --web."; exit 1
fi

# 1. .love -------------------------------------------------------------------
# Lista do que ENTRA (não do que sai): pasta nova de desenvolvimento nunca vaza
# para o pacote. main.lua fica na raiz do zip, como o LÖVE exige.
# O arquivo anterior é apagado antes: zip sobre um arquivo existente só
# adiciona entradas, nunca remove as que sumiram do projeto.
# Excluded from assets/: the Kenney preview images (*sample*.png), Windows
# desktop.ini files, the full Kenney sound pack in assets/sfx/Audio/ (~6 MB
# source pack) and the full Kenney Planets pack in assets/art/PlanetParts/
# (~4 MB). The sounds and planet parts the game actually uses are copied into
# assets/sfx/kenney/ and assets/art/planets/, packed like any other asset.
# Also the music tracks kept on disk but unused (schmoovin, danse-contemporaine).
mkdir -p "${DATA_DIR}"
rm -f "${LOVE_FILE}"
zip -9 -q -r "${LOVE_FILE}" main.lua conf.lua src assets \
  -x '*/.gitkeep' '*sample*.png' '*/desktop.ini' 'assets/sfx/Audio/*' \
     'assets/art/PlanetParts/*' \
     'assets/music/schmoovin.ogg' 'assets/music/danse-contemporaine.ogg'

# 1b. Web (--web) ---------------------------------------------------------------
# O mesmo .love vira página web com o love.js (LÖVE 11.4 em WebAssembly). Os
# passos do Batocera (launcher, aviso do AppImage, deploy) não rodam.
#
# Versão do love.js pinada: o patch do Module.FS abaixo depende do love.js
# exato que ela gera. O modo normal usa threads (SharedArrayBuffer) e precisa
# dos headers COOP/COEP: no itch.io é o checkbox "SharedArrayBuffer support";
# localmente, tools/serve_web.py. --compat roda sem eles, com áudio pior.
if [ "$WEB" = 1 ]; then
  WEB_DIR="dist/web"
  WEB_ZIP="dist/${NAME}-web.zip"
  WEB_MEMORY=67108864   # heap inicial (64 MB); cresce sozinho até 2 GB
  LOVEJS="love.js@11.4.1"

  if ! command -v npx >/dev/null 2>&1; then
    echo "ERRO: npx nao encontrado. Instale o Node.js (o npx vem junto)."
    exit 1
  fi

  rm -rf "${WEB_DIR}"
  LOVEJS_ARGS=(-t "SikCid Shootin'" -m "${WEB_MEMORY}")
  if [ "$COMPAT" = 1 ]; then LOVEJS_ARGS+=(-c); fi
  npx --yes "${LOVEJS}" "${LOVEJS_ARGS[@]}" "${LOVE_FILE}" "${WEB_DIR}"

  # O love.js só grava o save no IndexedDB no beforeunload, que o navegador
  # costuma cortar ao fechar a aba. Expor o FS do Emscripten como Module.FS
  # deixa o index.html gravar a cada poucos segundos. Sem o patch o save web
  # some, então o build falha em vez de seguir.
  sed -i 's/Module\["FS_unlink"\]=FS\.unlink/&;Module["FS"]=FS/' "${WEB_DIR}/love.js"
  if ! grep -q 'Module\["FS"\]=FS' "${WEB_DIR}/love.js"; then
    echo "ERRO: o patch do Module.FS nao aplicou em ${WEB_DIR}/love.js."
    echo "      A versao do love.js mudou? O save da versao web depende dele."
    exit 1
  fi

  # Página própria (web/index.html) no lugar da gerada; o tema dela sai junto.
  sed "s/@MEMORY@/${WEB_MEMORY}/" web/index.html > "${WEB_DIR}/index.html"
  rm -rf "${WEB_DIR}/theme"

  # O itch.io quer o index.html na raiz do zip.
  rm -f "${WEB_ZIP}"
  (cd "${WEB_DIR}" && zip -9 -q -r "../$(basename "${WEB_ZIP}")" .)

  echo "Build web pronto:"
  echo "  ${WEB_DIR}/"
  echo "  ${WEB_ZIP}  ($(du -h "${WEB_ZIP}" | cut -f1))"
  if [ "$COMPAT" = 1 ]; then
    echo "  modo compat: sem threads, roda sem SharedArrayBuffer (audio pior)"
  else
    echo
    echo "No itch.io, ligue 'SharedArrayBuffer support' nas opcoes de embed"
    echo "(checklist completo no README, \"Build web (itch.io)\")."
  fi

  if [ "$RUN" = 1 ]; then
    echo
    echo "Smoke de desempenho (FPS no canto, wave 10, 2 bots invenciveis):"
    echo "  http://localhost:8000/?--smoke&60&--smoke2p&--smokegod&--wave&10&--debug"
    python3 tools/serve_web.py "${WEB_DIR}" 8000
  fi
  exit 0
fi

# 2. Launcher ------------------------------------------------------------------
# Só o .love e o .sh são substituídos: o dist/ NÃO é apagado, senão o love/
# extraído (~12 MB) teria que ser recolocado a cada build.
# Heredoc com 'EOF' entre aspas: as $ ficam literais no script gerado.
#
# O launcher nunca falha mudo: confere os pré-requisitos e grava tudo (inclusive
# o erro do LÖVE, que o errorhandler do jogo imprime em stdout) num log. Numa
# tela de TV que volta direto para o menu, o log é a única pista.
cat > "${LAUNCHER}" <<'EOF'
#!/bin/bash
# SikCid Shootin' -- launcher do port (Batocera / Ports)
DIR="$(dirname "$(readlink -f "$0")")"
GAME="${DIR}/.data/sikcid-shootin"

# Log em /userdata/system/logs (padrão do Batocera); fora dele, ao lado do .sh.
LOG_DIR="/userdata/system/logs"
[ -d "$LOG_DIR" ] && [ -w "$LOG_DIR" ] || LOG_DIR="$DIR"
LOG="${LOG_DIR}/sikcid-shootin.log"

{
  echo "== $(date) =="
  echo "launcher: $(readlink -f "$0")"

  if [ ! -d "$GAME" ]; then
    echo "ERRO: pasta do jogo nao encontrada: $GAME"
    echo "      O conteudo de dist/.data/sikcid-shootin/ precisa ficar em"
    echo "      <pasta do .sh>/.data/sikcid-shootin/ (com a subpasta)."
    exit 1
  fi
  cd "$GAME" || exit 1

  if [ ! -f SikCidShootin.love ]; then
    echo "ERRO: SikCidShootin.love nao encontrado em $GAME"
    exit 1
  fi
  if [ ! -f love/AppRun ]; then
    echo "ERRO: love/AppRun nao encontrado em $GAME"
    echo "      Extraia o AppImage do LOVE 11.5 e renomeie squashfs-root para love."
    exit 1
  fi

  # Copias pela rede do Windows (SMB) perdem o bit de execucao. O AppImage do
  # LOVE 11.5 tem o binario em love/bin/ (outros builds usam love/usr/bin/);
  # as bibliotecas em love/lib/ so precisam de leitura.
  chmod +x love/AppRun love/bin/* love/usr/bin/* 2>/dev/null

  if [ -f love/bin/love ] && [ ! -x love/bin/love ]; then
    echo "ERRO: love/bin/love sem permissao de execucao e o chmod falhou."
    echo "      A particao pode estar montada como noexec. Rode no Batocera:"
    echo "      chmod +x $GAME/love/AppRun $GAME/love/bin/love"
    exit 1
  fi

  ./love/AppRun SikCidShootin.love
  echo "LOVE saiu com codigo $?"
} > "$LOG" 2>&1
EOF
chmod +x "${LAUNCHER}"

# 2b. Frontend art + gamelist entry ---------------------------------------------
# Without them Batocera shows its "no image" placeholder. The PNGs are made by
# `love . --media` (tools/media.lua) and versioned in media/; they are copied
# under the names Batocera's own scraper uses. dist/gamelist.xml holds ONLY
# this game: --deploy merges it into the ports gamelist on the Batocera
# (tools/merge_gamelist.py), never overwriting the other ports.
IMAGES_DIR="dist/images"
HAS_MEDIA=1
for f in cover logo fanart; do
  [ -f "media/${f}.png" ] || HAS_MEDIA=0
done
if [ "$HAS_MEDIA" = 1 ]; then
  mkdir -p "${IMAGES_DIR}"
  cp media/cover.png  "${IMAGES_DIR}/${NAME}-image.png"
  cp media/logo.png   "${IMAGES_DIR}/${NAME}-marquee.png"
  cp media/fanart.png "${IMAGES_DIR}/${NAME}-fanart.png"
fi
cat > dist/gamelist.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<gameList>
	<game>
		<path>./${NAME}.sh</path>
		<name>SikCid Shootin'</name>
		<desc>Twin-stick shooter de arena para 1 ou 2 jogadores locais. Inimigos entram por quatro portas em waves infinitas: atire, desvie, pegue power-ups e segure o combo. A cada 10 waves, um boss.</desc>
		<image>./images/${NAME}-image.png</image>
		<thumbnail>./images/${NAME}-image.png</thumbnail>
		<marquee>./images/${NAME}-marquee.png</marquee>
		<fanart>./images/${NAME}-fanart.png</fanart>
		<releasedate>20260101T000000</releasedate>
		<developer>SikStudio</developer>
		<genre>Shooter</genre>
		<players>1-2</players>
	</game>
</gameList>
EOF

# 3. Resumo --------------------------------------------------------------------
echo "Build pronto:"
echo "  ${LAUNCHER}"
echo "  ${LOVE_FILE}  ($(du -h "${LOVE_FILE}" | cut -f1))"
if [ "$HAS_MEDIA" = 1 ]; then
  echo "  ${IMAGES_DIR}/  (capa, logo, fanart) + dist/gamelist.xml"
else
  echo "  AVISO: faltam imagens em media/ (gere com: love . --media)."
  echo "         Sem elas o Batocera mostra a imagem padrao."
fi

# 4. LÖVE extraído presente? --------------------------------------------------
if [ ! -x "${DATA_DIR}/love/AppRun" ]; then
  cat <<EOF

AVISO: ${DATA_DIR}/love/ esta vazio (ou sem AppRun).
O port precisa do LOVE 11.5 extraido la dentro:

  1. Baixe o AppImage x86_64 do LOVE 11.5:
     https://github.com/love2d/love/releases/tag/11.5
     (arquivo love-11.5-x86_64.AppImage)
  2. Extraia:
       chmod +x love-11.5-x86_64.AppImage
       ./love-11.5-x86_64.AppImage --appimage-extract
  3. Renomeie a pasta gerada e mova para o port:
       mv squashfs-root ${DATA_DIR}/love

Depois copie para o Batocera (detalhes no README, "Deploy no Batocera").
EOF
fi

# 5. Deploy opcional (--deploy) ---------------------------------------------------
if [ "$DEPLOY" = 1 ]; then
  REMOTE_PORTS="/userdata/roms/ports"
  REMOTE_GAME="${REMOTE_PORTS}/.data/sikcid-shootin"

  # Uma conexão SSH para o deploy inteiro: a senha é pedida uma vez só.
  SSH_OPTS=(-o ControlMaster=auto -o "ControlPath=/tmp/sikcid-deploy-%r@%h:%p"
            -o ControlPersist=60 -o ConnectTimeout=8)
  SSH="${SSH:-ssh}"   # sobrescrevíveis só para testar o script sem Batocera
  SCP="${SCP:-scp}"

  echo
  echo "Deploy para ${HOST}..."

  # mkdir -p ANTES de qualquer cópia: sem isso o scp -r renomearia a pasta.
  if ! REMOTE_HAS_LOVE=$("$SSH" "${SSH_OPTS[@]}" "$HOST" \
      "mkdir -p '${REMOTE_GAME}' '${REMOTE_PORTS}/images' && if [ -f '${REMOTE_GAME}/love/AppRun' ]; then echo sim; else echo nao; fi"); then
    echo "ERRO: nao consegui conectar em ${HOST}."
    echo "      O Batocera esta ligado e na mesma rede? Teste com: ssh ${HOST}"
    echo "      Outro endereco: ./build.sh --deploy root@192.168.x.x"
    exit 1
  fi

  # O .love sobe com nome temporário e só é renomeado no fim: se o jogo for
  # aberto no meio da cópia, nunca lê um arquivo pela metade.
  echo "  .love  -> ${REMOTE_GAME}/"
  "$SCP" "${SSH_OPTS[@]}" -q "${LOVE_FILE}" "${HOST}:${REMOTE_GAME}/${NAME}.love.tmp"
  echo "  .sh    -> ${REMOTE_PORTS}/"
  "$SCP" "${SSH_OPTS[@]}" -q "${LAUNCHER}" "${HOST}:${REMOTE_PORTS}/${NAME}.sh"

  # O LÖVE extraído só vai quando falta lá (primeiro deploy): 12 MB, uma vez.
  if [ "$REMOTE_HAS_LOVE" != "sim" ]; then
    if [ -x "${DATA_DIR}/love/AppRun" ]; then
      echo "  love/  -> ${REMOTE_GAME}/ (ausente no Batocera; so desta vez)"
      "$SCP" "${SSH_OPTS[@]}" -q -r "${DATA_DIR}/love" "${HOST}:${REMOTE_GAME}/"
    else
      echo "  AVISO: o Batocera nao tem o love/ e ele tambem nao existe aqui."
      echo "         Extraia o AppImage (veja o aviso acima) e rode o deploy de novo."
    fi
  fi

  "$SSH" "${SSH_OPTS[@]}" "$HOST" \
    "mv -f '${REMOTE_GAME}/${NAME}.love.tmp' '${REMOTE_GAME}/${NAME}.love' && chmod +x '${REMOTE_PORTS}/${NAME}.sh'"

  # Menu art: images go next to the other ports' media, and this game's entry
  # is merged into ports/gamelist.xml by the Batocera's own python3
  # (tools/merge_gamelist.py, kept in .data with the entry for re-merging).
  #
  # Editing the file is not enough while EmulationStation runs: ES keeps the
  # gamelist in memory and, every time a game is played, rewrites that game's
  # whole <game> node from memory, dropping what it never loaded (desc,
  # marquee, fanart). So after the merge ES is told to reload through its
  # local HTTP API (port 1234, /reloadgames). If ES saved a pending change
  # over the merge right before reloading, the second merge catches it and
  # ES reloads once more.
  if [ "$HAS_MEDIA" = 1 ]; then
    echo "  images -> ${REMOTE_PORTS}/images/"
    "$SCP" "${SSH_OPTS[@]}" -q "${IMAGES_DIR}"/*.png "${HOST}:${REMOTE_PORTS}/images/"
  fi
  echo "  gamelist.xml (entrada do jogo) -> ${REMOTE_PORTS}/gamelist.xml"
  "$SCP" "${SSH_OPTS[@]}" -q dist/gamelist.xml "${HOST}:${REMOTE_GAME}/gamelist-entry.xml"
  "$SCP" "${SSH_OPTS[@]}" -q tools/merge_gamelist.py "${HOST}:${REMOTE_GAME}/merge_gamelist.py"
  set +e
  "$SSH" "${SSH_OPTS[@]}" "$HOST" \
      "sh -s '${REMOTE_PORTS}/gamelist.xml' '${REMOTE_GAME}/gamelist-entry.xml' '${REMOTE_GAME}/merge_gamelist.py'" <<'EOF'
G="$1"; E="$2"; M="$3"
merge() { python3 "$M" "$G" "$E"; }
reload() { curl -s -m 10 -o /dev/null http://127.0.0.1:1234/reloadgames; }
out=$(merge) || { echo "  $out"; exit 1; }
echo "  $out"
reload || exit 3
sleep 4
out=$(merge) || { echo "  $out"; exit 1; }
case "$out" in
  *"ja atualizado"*) ;;
  *) echo "  (o ES regravou a lista antes de recarregar; mesclado de novo)"; reload; sleep 2 ;;
esac
echo "  EmulationStation: lista de jogos recarregada"
EOF
  MENU_STATUS=$?
  set -e
  case "$MENU_STATUS" in
    0) ;;
    3) echo "  AVISO: o EmulationStation nao respondeu (porta 1234). O gamelist.xml foi"
       echo "         atualizado; reinicie o Batocera para ele ler o arquivo novo." ;;
    *) echo "  AVISO: nao consegui atualizar o gamelist.xml (o jogo roda, so sem imagens)." ;;
  esac
  "$SSH" "${SSH_OPTS[@]}" -O exit "$HOST" 2>/dev/null || true

  echo "Deploy concluido. Se o jogo estiver aberto no Batocera, feche e abra de novo."
fi

# 6. Teste local opcional (--run) -------------------------------------------------
if [ "$RUN" = 1 ]; then
  love "${LOVE_FILE}"
fi

#!/bin/bash
# Gera o port do SikCid Shootin' para o sistema "Ports" do Batocera:
#
#   dist/
#     SikCidShootin.sh
#     .data/sikcid-shootin/
#         SikCidShootin.love
#         love/            <- AppImage do LÖVE extraído (colocado à mão)
#
# Uso:  ./build.sh                  gera o dist/
#       ./build.sh --run            gera e abre o .love no LÖVE local para testar
#       ./build.sh --deploy [host]  gera e copia para o Batocera (padrão:
#                                   root@batocera.local, ou $BATOCERA_HOST)
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
EOF
}

RUN=0
DEPLOY=0
HOST="${BATOCERA_HOST:-root@batocera.local}"
while [ $# -gt 0 ]; do
  case "$1" in
    --run) RUN=1 ;;
    --deploy)
      DEPLOY=1
      # Host opcional logo depois (qualquer coisa que não seja outra opção).
      if [ -n "${2:-}" ] && [ "${2#--}" = "$2" ]; then HOST="$2"; shift; fi
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "opcao desconhecida: $1"; usage; exit 1 ;;
  esac
  shift
done

# 1. .love -------------------------------------------------------------------
# Lista do que ENTRA (não do que sai): pasta nova de desenvolvimento nunca vaza
# para o pacote. main.lua fica na raiz do zip, como o LÖVE exige.
# O arquivo anterior é apagado antes: zip sobre um arquivo existente só
# adiciona entradas, nunca remove as que sumiram do projeto.
# Excluded from assets/: the Kenney preview images (*sample*.png), Windows
# desktop.ini files, and the Kenney sound pack in assets/sfx/Audio/, which the
# game does not use yet.
mkdir -p "${DATA_DIR}"
rm -f "${LOVE_FILE}"
zip -9 -q -r "${LOVE_FILE}" main.lua conf.lua src assets \
  -x '*/.gitkeep' '*sample*.png' '*/desktop.ini' 'assets/sfx/Audio/*'

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

# 3. Resumo --------------------------------------------------------------------
echo "Build pronto:"
echo "  ${LAUNCHER}"
echo "  ${LOVE_FILE}  ($(du -h "${LOVE_FILE}" | cut -f1))"

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
      "mkdir -p '${REMOTE_GAME}' && if [ -f '${REMOTE_GAME}/love/AppRun' ]; then echo sim; else echo nao; fi"); then
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
  "$SSH" "${SSH_OPTS[@]}" -O exit "$HOST" 2>/dev/null || true

  echo "Deploy concluido. Se o jogo estiver aberto no Batocera, feche e abra de novo."
fi

# 6. Teste local opcional (--run) -------------------------------------------------
if [ "$RUN" = 1 ]; then
  love "${LOVE_FILE}"
fi

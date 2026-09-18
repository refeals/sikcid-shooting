#!/bin/bash
# Gera o port do SikCid Shootin' para o sistema "Ports" do Batocera:
#
#   dist/
#     SikCidShootin.sh
#     .data/sikcid-shootin/
#         SikCidShootin.love
#         love/            <- AppImage do LÖVE extraído (colocado à mão)
#
# Uso:  ./build.sh         gera o dist/
#       ./build.sh --run   gera e abre o .love no LÖVE local para testar
set -e
cd "$(dirname "$(readlink -f "$0")")"

NAME="SikCidShootin"
DATA_DIR="dist/.data/sikcid-shootin"
LOVE_FILE="${DATA_DIR}/${NAME}.love"
LAUNCHER="dist/${NAME}.sh"

# 1. .love -------------------------------------------------------------------
# Lista do que ENTRA (não do que sai): pasta nova de desenvolvimento nunca vaza
# para o pacote. main.lua fica na raiz do zip, como o LÖVE exige.
# O arquivo anterior é apagado antes: zip sobre um arquivo existente só
# adiciona entradas, nunca remove as que sumiram do projeto.
mkdir -p "${DATA_DIR}"
rm -f "${LOVE_FILE}"
zip -9 -q -r "${LOVE_FILE}" main.lua conf.lua src assets -x '*/.gitkeep'

# 2. Launcher ------------------------------------------------------------------
# Só o .love e o .sh são substituídos: o dist/ NÃO é apagado, senão o love/
# extraído (~100 MB) teria que ser recolocado a cada build.
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

# 5. Teste local opcional --------------------------------------------------------
if [ "${1:-}" = "--run" ]; then
  love "${LOVE_FILE}"
fi

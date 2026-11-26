# SikCid Shootin'

Twin-stick shooter em LÖVE 11.x (Lua), sem dependências externas.
Alvos: PC, Batocera x86_64 (hardware modesto) e navegador (love.js 11.4, WebGL 1).

## Onde está cada coisa

- Rodar, build, testes, estrutura do código: [README.md](README.md)
- Como o jogo funciona: [docs/DESIGN.md](docs/DESIGN.md)
- Metas de dificuldade, curva, recompensas, onde tunar: [docs/BALANCE.md](docs/BALANCE.md)
- Bugs e itens em observação: [docs/PROBLEMS.md](docs/PROBLEMS.md)
- Em andamento, backlog, histórico: [docs/ROADMAP.md](docs/ROADMAP.md)
- Batocera, itch.io, versão web: [docs/DEPLOY.md](docs/DEPLOY.md)
- Visual e áudio: [docs/VISUAL.md](docs/VISUAL.md), [docs/AUDIO.md](docs/AUDIO.md)

## Regras

- Todo número de gameplay ou visual fica em `src/config.lua`.
- Código e comentários em inglês (ao reescrever uma linha com comentário em
  português, traduza). Texto do jogo e docs em PT-BR.
- Shaders em GLSL ES 1.0, carregados com `pcall` e com fallback.
- Nada de alocação no loop quente: pools e swap-remove.
- Mudou uma mecânica: atualize o doc correspondente na mesma mudança.
- Nunca rode git que altera estado (add, commit, push...). No fim, entregue
  a mensagem de commit: uma linha, até 60 caracteres, prefixo convencional
  (`feat:`, `fix:`, `docs:`), em inglês, sem `Co-Authored-By`.

## Processo

Etapa nova do roadmap: entrevista de design com a skill `grill-me` → plano →
aprovação → implementar e testar → mensagem de commit.

## Testar

`love . --smoke 20` (exit 0 = ok). Variações: `--smoke2p`, `--wave N`,
`--upgrades N`, `--shots`. No Windows, use `lovec.exe` para ver a saída e o
código de saída.

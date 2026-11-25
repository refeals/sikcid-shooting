- ranking geral na nuvem (firebase?)

## Menu principal / configurações

Hoje as configurações só mudam pelo `src/config.lua` ou por flags de linha de
comando. A ideia é ter um menu principal (antes do lobby) com uma tela de
opções salva no `love.filesystem`, como o `highscores.dat`:

- **Qualidade dos efeitos**: high / low / off, o mesmo que `--fx` e
  `Config.FX.quality` (brilho, composição da cena, tamanho do pool de
  partículas).
- **Teto de partículas**: `Config.FX.particles`, para ajustar em hardware mais
  fraco (Batocera, navegador).
- **Volumes**: música e efeitos separados (`Config.MUSIC.volume`,
  `Config.AUDIO.master`).
- **Tremor de tela e aberração cromática**: liga/desliga ou intensidade
  (`Config.JUICE.shakeScale`, `Config.FX.aberration`), por conforto.
- Espaço para outros itens: tela cheia/janela, controles, idioma...

# Roadmap

O que está em andamento, o que vem depois e o que já foi feito.

Cada etapa segue o mesmo processo: conversa de design (perguntas até fechar
as decisões) → plano → aprovação → implementação e teste (smoke, FPS,
screenshots) → commit. Etapas grandes se dividem em partes (a, b...).

## Agora

### Balanceamento com dados (etapa 4b)

Esperando partidas de playtest no Batocera, com o `runs.csv`
(`./build.sh --pull-runs` → `dist/runs-batocera.csv`). Com os dados:

- comparar a wave final com as [metas](BALANCE.md#metas);
- olhar o tempo e as mortes por wave, e as causas;
- olhar a duração das waves de boss e de sub-boss;
- comparar 1 e 2 jogadores;
- ajustar `Config.WAVE`, `ENEMY_MIX`, `ELITE`, `BOSS` e `SUBBOSS`.

Antes de mexer, a conversa de design de sempre. Itens já anotados para essa
etapa estão em [PROBLEMS.md](PROBLEMS.md#em-observação).

## Backlog

### Menu principal e configurações

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

### Outras ideias

- Adicionar seletor de linguagem para EN, ES e PT-BR, com padrão EN.
- Ranking geral na nuvem (Firebase?).
- Inimigo MINADOR (guardado na etapa 2 de gameplay).
- Power-ups TORRETA e ESCOPETA (guardados na etapa 6 de gameplay).

## Feito

### Gameplay e balanceamento (nov/2026)

1. Dash.
2. Inimigos novos: KAMIKAZE e DIVISOR (2a); SNIPER e PORTA-NAVES (2b).
3. Upgrades permanentes: tela de cartas, atributos, PERFURANTE, RETAGUARDA e
   DRONE FIEL (3a); LÂMINA, RECARGA, RICOCHETE e CHOQUE (3b).
4. Curva linear de waves, elites e registro de partidas (4a). A 4b está em
   [Agora](#agora).
5. Sub-bosses: TORRE e ARIETE (5a); HIDRA e COLMEIA (5b).
6. Power-ups LASER, ESCUDO ORBITAL e TEMPO LENTO.

### Polimento visual (nov/2026)

1. Pós-processamento com brilho seletivo.
2. Shockwave, aberração cromática e vinheta; escudo de entrada do boss.
3. Explosões em camadas, com destroços e faíscas de impacto.
4. Profundidade: sombras, véu no céu e marcas de queimado.
5. Detalhes: clarão no cano, rastros, fita do motor e ecos (5a); dissolve,
   portais nas portas e feixe de respawn (5b); brilho e pop dos power-ups no
   chão (5c).
6. Juice da interface: HUD e banners (6a); transições de tela (6b).

### Base

Waves infinitas e lobby de 1–2 jogadores, boss a cada 10 waves, auto-aim,
céu animado com temas por bloco de waves, suporte no respawn, port para o
Batocera com imagens do menu, versão web para o itch.io com controles touch,
trilha sonora e sequência de game over.

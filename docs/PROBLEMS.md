# Problemas conhecidos

Bugs, coisas que precisam ser verificadas e números para ficar de olho.
Quando um item for resolvido, apague daqui; o histórico fica no git.
As limitações de cada plataforma (Safari, autoplay de áudio...) estão em
[DEPLOY.md](DEPLOY.md#diferenças-da-versão-web).

Formato de cada item:

```
### Título curto
- **Onde:** PC / Batocera / web / todos
- **Sintoma:** o que acontece (ou o que falta verificar)
- **Como reproduzir:** passos ou comando
- **Status:** aberto / investigando / precisa verificar
```

## Abertos

### Efeitos visuais não verificados no navegador

- **Onde:** web
- **Sintoma:** o brilho e a composição da cena (shockwave, aberração e
  vinheta) ficaram pendentes de teste no love.js. Também não há registro de
  teste dos shaders que vieram depois (dissolve, faixa de luz, transição de
  tela).
- **Como reproduzir:** `./build.sh --web --run`, abrir no Chrome e no
  Firefox com `?--smoke&60&--smoke2p&--smokegod&--wave&10&--debug`. Conferir
  FPS de pelo menos ~55 e nenhum aviso `[post] ... unavailable` no console.
- **Status:** precisa verificar

## Em observação

Números que estão dentro do limite mas perto dele. Rever na etapa 4b do
[roadmap](ROADMAP.md#agora).

### Boss 1 morre rápido

- **Onde:** todos
- **Sintoma:** no smoke, o primeiro boss morreu em 14 s para um único bot.
- **Status:** aguardando dados de playtest

### Teto de inimigos quase cheio em 2 jogadores

- **Onde:** todos
- **Sintoma:** em 2 jogadores, na wave 39, o teto de vivos chega a 97 dos
  100 de `Config.MAX_ENEMIES`. Passando disso, inimigos são recusados
  (`denied=` maior que 0 no resumo do smoke).
- **Como reproduzir:** `love . --smoke 60 --smoke2p --smokegod --wave 39`
- **Status:** observar

### Pool de balas com muitos upgrades

- **Onde:** todos
- **Sintoma:** com 25 upgrades por jogador em 2 jogadores, o pico foi de 248
  das 320 balas de `Config.MAX_BULLETS`. Com uns 8 upgrades (uma partida
  normal) o pico fica por volta de 112.
- **Como reproduzir:** `love . --smoke 60 --smoke2p --smokegod --upgrades 25`,
  numa wave alta (`--wave N`)
- **Status:** observar

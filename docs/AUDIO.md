# Áudio

Efeitos sonoros e música: de onde vêm, como são tocados e como trocar.

## Efeitos sonoros

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

A tabela mostra os sons base. Os outros sons Kenney (dash, inimigos novos,
boss, escudo, transição...) reaproveitam esses arquivos com outro pitch; a
lista completa fica em `Config.SFX`.

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
[tools/gen_sfx.py](../tools/gen_sfx.py), um port sem dependências do sintetizador
do [sfxr.me](https://sfxr.me) (jsfxr): `python3 tools/gen_sfx.py` recria todos,
`python3 tools/gen_sfx.py shot pickup` só os citados. Para ajustar um som no
site, cole o conteúdo de `tools/sfx/<id>.json` no campo de texto do sfxr.me,
clique em **Deserialize**, mexa e baixe o `.wav` por cima do gerado. Som sem arquivo é ignorado em silêncio — o console
mostra no boot quantos carregaram, quantas variações Kenney, quantos caíram no
fallback e quanto tempo levou (`[audio] N som(ns) carregado(s) (V variacao(oes)
Kenney), F no fallback sfxr...`).

Os ids, e o volume, número de vozes, pitch base, variação de pitch e intervalo
mínimo de cada um, estão em `Config.SFX` em [src/config.lua](../src/config.lua).
O volume dos efeitos é o item EFEITOS SONOROS das opções (0 a 10, padrão 8 =
0,8), vezes o `vol` de cada som; `love . --mute` roda sem som e trava os dois
volumes na sessão (ver [Opções](DESIGN.md#opções)).

[src/audio.lua](../src/audio.lua) pré-carrega um **pool de vozes** por arquivo e
usa em rodízio: nenhum `Source` é criado durante o jogo (o tiro automático
dispararia dezenas por segundo). Num som com variações, `voices` é o total,
repartido entre elas (no mínimo uma voz cada). Os clones de um `Source`
estático dividem o mesmo buffer, então mais vozes não gastam mais memória. Som
novo = uma entrada em `Config.SFX` + o arquivo + uma chamada
`Audio.play("id")` no ponto certo.

## Música

Faixas em **`assets/music/<nome>.ogg`**, tocadas por [src/music.lua](../src/music.lua).
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
- Volume: o item MÚSICA das opções (0 a 10, padrão 8) vezes
  `Config.MUSIC.volume`, o volume da música no máximo (abaixo dos efeitos, para
  tiros e explosões continuarem legíveis). `--mute` silencia tudo.

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


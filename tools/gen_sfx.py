#!/usr/bin/env python3
"""Gera os efeitos sonoros do jogo com o mesmo sintetizador do sfxr/jsfxr.

Port direto do gerador do jsfxr (o motor do https://sfxr.me), sem dependências.
Para cada som:
  - assets/sfx/<id>.wav   -- o arquivo que o jogo carrega
  - tools/sfx/<id>.json   -- os parâmetros no formato do sfxr.me: cole no
                             campo de texto do site e clique em "Deserialize"
                             para ouvir e ajustar lá

Uso (da raiz do projeto):
    python3 tools/gen_sfx.py            # gera todos
    python3 tools/gen_sfx.py shot pickup  # só esses

Para ajustar um som: mude os parâmetros em SOUNDS e rode de novo, ou ajuste no
site e salve o .wav de lá por cima do gerado.
"""

import json
import math
import os
import random
import struct
import sys
import wave

SQUARE, SAWTOOTH, SINE, NOISE = 0, 1, 2, 3
OVERSAMPLING = 8
SAMPLE_RATE = 44100

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WAV_DIR = os.path.join(ROOT, "assets", "sfx")
JSON_DIR = os.path.join(ROOT, "tools", "sfx")

# Valores padrão do jsfxr (Params() em sfxr.js).
DEFAULTS = {
    "oldParams": True,
    "wave_type": SQUARE,
    "p_env_attack": 0.0, "p_env_sustain": 0.3, "p_env_punch": 0.0, "p_env_decay": 0.4,
    "p_base_freq": 0.3, "p_freq_limit": 0.0, "p_freq_ramp": 0.0, "p_freq_dramp": 0.0,
    "p_vib_strength": 0.0, "p_vib_speed": 0.0,
    "p_arp_mod": 0.0, "p_arp_speed": 0.0,
    "p_duty": 0.0, "p_duty_ramp": 0.0,
    "p_repeat_speed": 0.0,
    "p_pha_offset": 0.0, "p_pha_ramp": 0.0,
    "p_lpf_freq": 1.0, "p_lpf_ramp": 0.0, "p_lpf_resonance": 0.0,
    "p_hpf_freq": 0.0, "p_hpf_ramp": 0.0,
    "sound_vol": 0.25,
    "sample_rate": SAMPLE_RATE,
    "sample_size": 16,
}

# ---------------------------------------------------------------------------
# Os sons do jogo. Só os parâmetros que diferem do padrão.
# Referência rápida:
#   p_base_freq   0.2 ~ 145Hz, 0.3 ~ 320Hz, 0.5 ~ 880Hz, 0.7 ~ 1.7kHz
#   p_freq_ramp   > 0 sobe, < 0 desce
#   p_env_*       duração em amostras = valor^2 * 100000 (0.3 -> 0.2s)
#   p_arp_mod     > 0 salta para cima, < 0 para baixo (uma vez, em p_arp_speed)
#   p_repeat_speed reinicia o som periodicamente (efeito "vrrp")
# ---------------------------------------------------------------------------
SOUNDS = {
    # --- Tiros ------------------------------------------------------------
    "shot": dict(  # laser curto e agudo; toca 8x/s, então precisa ser curtíssimo
        wave_type=SQUARE, p_base_freq=0.62, p_freq_limit=0.2, p_freq_ramp=-0.28,
        p_duty=0.45, p_duty_ramp=0.15,
        p_env_sustain=0.08, p_env_punch=0.1, p_env_decay=0.18, p_hpf_freq=0.15),
    "shot_spread": dict(  # mais grave e encorpado
        wave_type=SAWTOOTH, p_base_freq=0.45, p_freq_limit=0.15, p_freq_ramp=-0.25,
        p_env_sustain=0.10, p_env_punch=0.2, p_env_decay=0.22, p_hpf_freq=0.1),
    "shot_missile": dict(  # "fsss" de foguete
        wave_type=NOISE, p_base_freq=0.55, p_freq_ramp=-0.15,
        p_env_sustain=0.10, p_env_punch=0.1, p_env_decay=0.25, p_lpf_freq=0.5),
    "shot_enemy": dict(  # "pew" grave: tem que soar diferente do tiro do jogador
        wave_type=SQUARE, p_base_freq=0.28, p_freq_ramp=-0.1,
        p_env_sustain=0.10, p_env_punch=0.3, p_env_decay=0.25, p_lpf_freq=0.7),

    # --- Impacto e morte --------------------------------------------------
    "enemy_hit": dict(  # "tic" seco
        wave_type=SQUARE, p_base_freq=0.55, p_freq_ramp=-0.45,
        p_env_sustain=0.04, p_env_decay=0.12, p_hpf_freq=0.25),
    "enemy_die": dict(  # explosão curta
        wave_type=NOISE, p_base_freq=0.35, p_freq_ramp=-0.2,
        p_env_sustain=0.15, p_env_punch=0.4, p_env_decay=0.32,
        sound_vol=0.20),
    "tank_die": dict(  # explosão longa e grave, com flanger de "ronco"
        wave_type=NOISE, p_base_freq=0.18, p_freq_ramp=-0.12,
        p_env_sustain=0.25, p_env_punch=0.6, p_env_decay=0.55,
        p_pha_offset=-0.2, p_pha_ramp=-0.1, p_lpf_freq=0.7,
        sound_vol=0.16),
    "player_die": dict(  # a mais dramática: explosão com vibrato
        wave_type=NOISE, p_base_freq=0.25, p_freq_ramp=-0.15,
        p_env_sustain=0.3, p_env_punch=0.5, p_env_decay=0.6,
        p_vib_strength=0.3, p_vib_speed=0.3, p_lpf_freq=0.8,
        sound_vol=0.16),
    "player_spawn": dict(  # "vrrp" subindo
        wave_type=SQUARE, p_base_freq=0.3, p_freq_ramp=0.25,
        p_env_sustain=0.2, p_env_decay=0.25, p_repeat_speed=0.55,
        sound_vol=0.40),

    # --- Power-ups --------------------------------------------------------
    "pickup": dict(  # moedinha clássica
        wave_type=SQUARE, p_base_freq=0.45,
        p_env_sustain=0.08, p_env_punch=0.45, p_env_decay=0.3,
        p_arp_mod=0.35, p_arp_speed=0.6),
    "pickup_life": dict(  # mais longo e festivo
        wave_type=SQUARE, p_base_freq=0.35, p_freq_ramp=0.2,
        p_env_sustain=0.3, p_env_decay=0.4, p_repeat_speed=0.5,
        p_vib_strength=0.1, p_vib_speed=0.4,
        sound_vol=0.40),
    "powerup_end": dict(  # "bup-bup" descendo
        wave_type=SQUARE, p_base_freq=0.45, p_freq_ramp=-0.25, p_duty=0.4,
        p_env_sustain=0.12, p_env_decay=0.25, p_repeat_speed=0.6,
        sound_vol=0.40),

    # --- Waves e combo ----------------------------------------------------
    "door_warn": dict(  # bip agudo de alerta
        wave_type=SQUARE, p_base_freq=0.58,
        p_env_sustain=0.1, p_env_decay=0.15, p_hpf_freq=0.1,
        sound_vol=0.38),
    "wave_start": dict(  # synth subindo
        wave_type=SQUARE, p_base_freq=0.25, p_freq_ramp=0.18,
        p_env_sustain=0.3, p_env_decay=0.35,
        p_vib_strength=0.15, p_vib_speed=0.5, p_lpf_freq=0.8,
        sound_vol=0.40),
    "wave_clear": dict(  # "ta-DAAA": nota de graça + nota longa
        wave_type=SQUARE, p_base_freq=0.36,
        p_env_sustain=0.35, p_env_punch=0.4, p_env_decay=0.5,
        p_arp_mod=0.45, p_arp_speed=0.7,
        p_vib_strength=0.08, p_vib_speed=0.45),
    "combo_up": dict(  # moedinha aguda e curta
        wave_type=SQUARE, p_base_freq=0.62,
        p_env_sustain=0.05, p_env_punch=0.5, p_env_decay=0.18,
        p_arp_mod=0.4, p_arp_speed=0.75),
    "combo_lost": dict(  # "bwow" descendo
        wave_type=SAWTOOTH, p_base_freq=0.4, p_freq_ramp=-0.3,
        p_env_sustain=0.12, p_env_decay=0.3, p_lpf_freq=0.6),
    "game_over": dict(  # "wah wah wahhh" longo e descendente
        wave_type=SQUARE, p_base_freq=0.35, p_freq_ramp=-0.12, p_duty=0.4,
        p_env_sustain=0.45, p_env_decay=0.7,
        p_vib_strength=0.25, p_vib_speed=0.35, p_lpf_freq=0.75,
        sound_vol=0.35),

    # --- Interface --------------------------------------------------------
    "menu_move": dict(  # clique
        wave_type=SQUARE, p_base_freq=0.55,
        p_env_sustain=0.06, p_env_decay=0.10, p_hpf_freq=0.2),
    "menu_confirm": dict(  # "bip-BIP" subindo
        wave_type=SQUARE, p_base_freq=0.5,
        p_env_sustain=0.1, p_env_decay=0.18, p_arp_mod=0.35, p_arp_speed=0.8,
        sound_vol=0.40),
    "menu_cancel": dict(  # "bip-bup" descendo
        wave_type=SQUARE, p_base_freq=0.35,
        p_env_sustain=0.1, p_env_decay=0.18, p_arp_mod=-0.25, p_arp_speed=0.8,
        sound_vol=0.40),
}


def synth(ps, rng):
    """Port de SoundEffect.getRawBuffer do jsfxr. Devolve amostras 16 bits."""

    st = {}

    def init_for_repeat():
        st["elapsed_since_repeat"] = 0
        st["period"] = 100.0 / (ps["p_base_freq"] ** 2 + 0.001)
        st["period_max"] = 100.0 / (ps["p_freq_limit"] ** 2 + 0.001)
        st["enable_freq_cutoff"] = ps["p_freq_limit"] > 0
        st["period_mult"] = 1 - ps["p_freq_ramp"] ** 3 * 0.01
        st["period_mult_slide"] = -(ps["p_freq_dramp"] ** 3) * 0.000001
        st["duty_cycle"] = 0.5 - ps["p_duty"] * 0.5
        st["duty_cycle_slide"] = -ps["p_duty_ramp"] * 0.00005
        if ps["p_arp_mod"] >= 0:
            st["arp_mult"] = 1 - ps["p_arp_mod"] ** 2 * 0.9
        else:
            st["arp_mult"] = 1 + ps["p_arp_mod"] ** 2 * 10
        st["arp_time"] = int((1 - ps["p_arp_speed"]) ** 2 * 20000 + 32)
        if ps["p_arp_speed"] == 1:
            st["arp_time"] = 0

    init_for_repeat()
    wave_shape = ps["wave_type"]

    fltw = ps["p_lpf_freq"] ** 3 * 0.1
    enable_lpf = ps["p_lpf_freq"] != 1
    fltw_d = 1 + ps["p_lpf_ramp"] * 0.0001
    fltdmp = 5 / (1 + ps["p_lpf_resonance"] ** 2 * 20) * (0.01 + fltw)
    if fltdmp > 0.8:
        fltdmp = 0.8
    flthp = ps["p_hpf_freq"] ** 2 * 0.1
    flthp_d = 1 + ps["p_hpf_ramp"] * 0.0003

    vib_speed = ps["p_vib_speed"] ** 2 * 0.01
    vib_amp = ps["p_vib_strength"] * 0.5

    env_len = [
        int(ps["p_env_attack"] ** 2 * 100000),
        int(ps["p_env_sustain"] ** 2 * 100000),
        int(ps["p_env_decay"] ** 2 * 100000),
    ]
    env_punch = ps["p_env_punch"]

    flanger_offset = ps["p_pha_offset"] ** 2 * 1020
    if ps["p_pha_offset"] < 0:
        flanger_offset = -flanger_offset
    flanger_slide = ps["p_pha_ramp"] ** 2
    if ps["p_pha_ramp"] < 0:
        flanger_slide = -flanger_slide

    repeat_time = int((1 - ps["p_repeat_speed"]) ** 2 * 20000 + 32)
    if ps["p_repeat_speed"] == 0:
        repeat_time = 0

    gain = math.exp(ps["sound_vol"]) - 1

    fltp = fltdp = fltphp = 0.0
    noise = [rng.random() * 2 - 1 for _ in range(32)]
    env_stage = 0
    env_elapsed = 0
    vib_phase = 0.0
    phase = 0
    ipp = 0
    flanger = [0.0] * 1024
    out = []
    clipped = 0
    t = 0

    while True:
        if repeat_time != 0:
            st["elapsed_since_repeat"] += 1
            if st["elapsed_since_repeat"] >= repeat_time:
                init_for_repeat()

        if st["arp_time"] != 0 and t >= st["arp_time"]:
            st["arp_time"] = 0
            st["period"] *= st["arp_mult"]

        st["period_mult"] += st["period_mult_slide"]
        st["period"] *= st["period_mult"]
        if st["period"] > st["period_max"]:
            st["period"] = st["period_max"]
            if st["enable_freq_cutoff"]:
                break

        rfperiod = st["period"]
        if vib_amp > 0:
            vib_phase += vib_speed
            rfperiod = st["period"] * (1 + math.sin(vib_phase) * vib_amp)
        iperiod = int(rfperiod)
        if iperiod < OVERSAMPLING:
            iperiod = OVERSAMPLING

        st["duty_cycle"] += st["duty_cycle_slide"]
        st["duty_cycle"] = min(0.5, max(0.0, st["duty_cycle"]))

        env_elapsed += 1
        if env_elapsed > env_len[env_stage]:
            env_elapsed = 0
            env_stage += 1
            if env_stage > 2:
                break
        stage_len = env_len[env_stage]
        envf = env_elapsed / stage_len if stage_len > 0 else 1.0
        if env_stage == 0:
            env_vol = envf
        elif env_stage == 1:
            env_vol = 1 + (1 - envf) * 2 * env_punch
        else:
            env_vol = 1 - envf

        flanger_offset += flanger_slide
        iphase = abs(int(flanger_offset))
        if iphase > 1023:
            iphase = 1023

        if flthp_d != 0:
            flthp *= flthp_d
            flthp = min(0.1, max(0.00001, flthp))

        sample = 0.0
        duty = st["duty_cycle"]
        for _ in range(OVERSAMPLING):
            phase += 1
            if phase >= iperiod:
                phase %= iperiod
                if wave_shape == NOISE:
                    for i in range(32):
                        noise[i] = rng.random() * 2 - 1
            fp = phase / iperiod
            if wave_shape == SQUARE:
                sub = 0.5 if fp < duty else -0.5
            elif wave_shape == SAWTOOTH:
                if fp < duty:
                    sub = -1 + 2 * fp / duty
                else:
                    sub = 1 - 2 * (fp - duty) / (1 - duty)
            elif wave_shape == SINE:
                sub = math.sin(fp * 2 * math.pi)
            else:
                sub = noise[int(phase * 32 / iperiod)]

            pp = fltp
            fltw *= fltw_d
            fltw = min(0.1, max(0.0, fltw))
            if enable_lpf:
                fltdp += (sub - fltp) * fltw
                fltdp -= fltdp * fltdmp
            else:
                fltp = sub
                fltdp = 0.0
            fltp += fltdp

            fltphp += fltp - pp
            fltphp -= fltphp * flthp
            sub = fltphp

            flanger[ipp & 1023] = sub
            sub += flanger[(ipp - iphase + 1024) & 1023]
            ipp = (ipp + 1) & 1023

            sample += sub * env_vol

        sample = sample / OVERSAMPLING * gain
        s = int(math.floor(sample * 32768))
        if s >= 32768:
            s, clipped = 32767, clipped + 1
        elif s < -32768:
            s, clipped = -32768, clipped + 1
        out.append(s)
        t += 1

    return out, clipped


def write_wav(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(struct.pack("<%dh" % len(samples), *samples))


def main():
    wanted = sys.argv[1:] or list(SOUNDS)
    unknown = [n for n in wanted if n not in SOUNDS]
    if unknown:
        sys.exit("sons desconhecidos: " + ", ".join(unknown))

    os.makedirs(WAV_DIR, exist_ok=True)
    os.makedirs(JSON_DIR, exist_ok=True)

    for i, name in enumerate(wanted):
        ps = dict(DEFAULTS)
        ps.update(SOUNDS[name])
        # Semente fixa por som: rodar de novo gera exatamente o mesmo arquivo.
        rng = random.Random(1000 + sorted(SOUNDS).index(name))
        samples, clipped = synth(ps, rng)
        write_wav(os.path.join(WAV_DIR, name + ".wav"), samples)
        with open(os.path.join(JSON_DIR, name + ".json"), "w") as f:
            json.dump(ps, f)
        peak = max((abs(s) for s in samples), default=0) / 32768
        print("%-13s %5.2fs  pico %3d%%%s" % (
            name, len(samples) / SAMPLE_RATE, peak * 100,
            "  CLIPOU %d amostras" % clipped if clipped else ""))


if __name__ == "__main__":
    main()

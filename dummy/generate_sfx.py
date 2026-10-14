"""Generate semua .wav SFX untuk Dino Defender.

Output: assets/sfx/
  ui_*.wav          - 6 sound UI
  attack_{dino}_{stage}.wav  - 40 sound attack (10 dino x 4 stage)
  skill_{dino}_{stage}.wav   - 40 sound skill
  ultimate_{dino}.wav        - 10 sound ultimate
"""
import os
import numpy as np
from scipy.io import wavfile

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")
os.makedirs(OUT, exist_ok=True)

STAGES = ["baby", "teen", "adult", "ultimate"]
STAGE_PITCH = {"baby": 1.35, "teen": 1.0, "adult": 0.78, "ultimate": 0.62}
STAGE_LEN = {"baby": 0.7, "teen": 1.0, "adult": 1.25, "ultimate": 1.55}
STAGE_LAYERS = {"baby": 1, "teen": 1, "adult": 2, "ultimate": 3}

DINOS = ["rexy", "spike", "tanky", "speedy", "freezy", "sparky", "poisony", "snipy", "bouncy", "lucky"]


def t_axis(dur):
    return np.linspace(0, dur, int(SR * dur), endpoint=False)


def _phase_array(freq, dur, phase=0.0):
    t = t_axis(dur)
    return 2 * np.pi * freq * t + phase


def sine(freq, dur, phase=0.0):
    return np.sin(_phase_array(freq, dur, phase))


def triangle(freq, dur):
    ph = _phase_array(freq, dur)
    s = (ph / (2 * np.pi)) % 1
    return 2 * np.abs(2 * s - 1) - 1


def square(freq, dur):
    return np.sign(np.sin(_phase_array(freq, dur)))


def sawtooth(freq, dur):
    ph = _phase_array(freq, dur)
    s = (ph / (2 * np.pi)) % 1
    return 2 * s - 1


def _wave_from_phase(phase, waveform):
    if waveform is np.sin:
        return np.sin(phase)
    s = (phase / (2 * np.pi)) % 1
    if waveform is sawtooth:
        return 2 * s - 1
    if waveform is square:
        return np.sign(np.sin(phase))
    if waveform is triangle:
        return 2 * np.abs(2 * s - 1) - 1
    return waveform(phase)


def sweep(f0, f1, dur, waveform=np.sin):
    t = t_axis(dur)
    freq = np.linspace(f0, f1, len(t))
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return _wave_from_phase(phase, waveform)


def white_noise(dur):
    return np.random.uniform(-1, 1, int(SR * dur))


def pink_noise(dur):
    n = int(SR * dur)
    white = np.random.uniform(-1, 1, n)
    pink = np.zeros(n)
    b = [0.99765, 0.0960479, 0.0564751]
    prev = [0.0, 0.0, 0.0]
    for i in range(n):
        prev[0] = b[0] * (white[i] + 0.5 * prev[0])
        prev[1] = b[1] * (white[i] + 0.5 * prev[1])
        prev[2] = b[2] * (white[i] + 0.5 * prev[2])
        pink[i] = prev[0] + prev[1] + prev[2] + white[i] * 0.11
    return pink / np.max(np.abs(pink) + 1e-9)


def lowpass(sig, cutoff):
    from scipy.signal import butter, filtfilt
    b, a = butter(4, cutoff / (SR / 2), btype="low")
    return filtfilt(b, a, sig)


def highpass(sig, cutoff):
    from scipy.signal import butter, filtfilt
    b, a = butter(4, cutoff / (SR / 2), btype="high")
    return filtfilt(b, a, sig)


def adsr(dur, a=0.005, d=0.05, s_level=0.7, r=0.08):
    n = int(SR * dur)
    env = np.zeros(n)
    a_n = max(1, int(a * SR))
    d_n = max(1, int(d * SR))
    r_n = max(1, int(r * SR))
    s_n = max(0, n - a_n - d_n - r_n)
    if a_n:
        env[:a_n] = np.linspace(0, 1, a_n)
    if d_n:
        env[a_n:a_n + d_n] = np.linspace(1, s_level, d_n)
    env[a_n + d_n:a_n + d_n + s_n] = s_level
    if r_n:
        env[a_n + d_n + s_n:] = np.linspace(s_level, 0, n - a_n - d_n - s_n)
    return env


def exp_decay(dur, tau=0.15):
    t = t_axis(dur)
    return np.exp(-t / tau)


def normalize(sig, peak=0.9):
    m = np.max(np.abs(sig))
    if m < 1e-9:
        return sig
    return sig * (peak / m)


def clip(sig, amp=0.98):
    return np.clip(sig, -amp, amp)


def mix(*sigs):
    n = max(len(s) for s in sigs)
    out = np.zeros(n)
    for s in sigs:
        out[:len(s)] += s
    return out


def concat(*sigs):
    return np.concatenate(sigs)


def place(out, start, seg):
    """Add seg into out at start, clamping to out length."""
    if start >= len(out):
        return out
    end = min(start + len(seg), len(out))
    out[start:end] += seg[:end - start]
    return out


def reverb_tail(sig, decay=0.3, delay=0.04):
    out = sig.copy()
    n = len(sig)
    for i in range(1, 4):
        d = int(delay * i * SR)
        if d >= n:
            continue
        env = exp_decay(n / SR, 0.2 + 0.05 * i)[:n - d]
        echoed = sig[:n - d] * (decay ** i) * env
        out[d:d + len(echoed)] += echoed
    return out


def save(name, sig):
    sig = normalize(sig, 0.85)
    sig = clip(sig)
    sig_i16 = (sig * 32767).astype(np.int16)
    path = os.path.join(OUT, name + ".wav")
    wavfile.write(path, SR, sig_i16)
    return path


# ============================================================
# SYNTHESIS RECIPE PER DINO
# Setiap fungsi return (attack_fn, skill_fn, ultimate_fn)
# yang menerima (stage) -> np.array
# ============================================================

def rexy_sfx(stage):
    """Rexy: fire whoosh - pink noise + low sine sweep."""
    pitch = STAGE_PITCH[stage]
    ln = STAGE_LEN[stage]
    dur = 0.18 * ln
    base = 170 * pitch
    noise = pink_noise(dur) * exp_decay(dur, 0.06)
    noise = lowpass(noise, 2200 * pitch)
    tone = sweep(base * 1.4, base * 0.7, dur) * exp_decay(dur, 0.08) * 0.6
    return mix(noise * 0.7, tone)


def rexy_skill(stage):
    pitch = STAGE_PITCH[stage]
    ln = STAGE_LEN[stage]
    dur = 0.42 * ln
    noise = pink_noise(dur) * adsr(dur, 0.02, 0.1, 0.5, 0.18)
    noise = lowpass(noise, 3000 * pitch)
    tone = sweep(220 * pitch, 90 * pitch, dur) * 0.5
    crackle = white_noise(dur) * (np.random.random(len(t_axis(dur))) > 0.985) * 0.6
    return mix(noise * 0.7, tone, crackle)


def rexy_ultimate():
    dur = 0.95
    noise = pink_noise(dur) * adsr(dur, 0.03, 0.15, 0.6, 0.4)
    noise = lowpass(noise, 3500)
    sub = sine(70, dur) * exp_decay(dur, 0.3) * 0.5
    tone = sweep(180, 60, dur) * 0.4
    return reverb_tail(mix(noise * 0.7, sub, tone), 0.35, 0.05)


def spike_sfx(stage):
    """Spike: sharp metallic zip - high sine sweep up."""
    pitch = STAGE_PITCH[stage]
    ln = STAGE_LEN[stage]
    dur = 0.11 * ln
    tone = sweep(1800 * pitch, 3200 * pitch, dur) * exp_decay(dur, 0.03) * 0.8
    metallic = mix(tone, triangle(2400 * pitch, dur) * 0.3)
    return metallic


def spike_skill(stage):
    pitch = STAGE_PITCH[stage]
    ln = STAGE_LEN[stage]
    parts = []
    for i in range(3):
        d = 0.09 * ln
        tone = sweep(1600 * pitch * (1 + i * 0.1), 3400 * pitch * (1 + i * 0.1), d) * exp_decay(d, 0.03) * 0.7
        parts.append(tone)
        parts.append(np.zeros(int(SR * 0.04)))
    return concat(*parts)


def spike_ultimate():
    dur = 0.8
    noise = white_noise(dur) * exp_decay(dur, 0.04) * 0.6
    noise = highpass(noise, 1500)
    tone = sweep(1200, 4000, dur * 0.5) * exp_decay(dur * 0.5, 0.06) * 0.5
    return reverb_tail(mix(noise, tone), 0.3, 0.04)


def tanky_sfx(stage):
    """Tanky: low thud - sine 100Hz + noise click."""
    pitch = STAGE_PITCH[stage]
    ln = STAGE_LEN[stage]
    dur = 0.16 * ln
    thud = sine(110 * pitch, dur) * exp_decay(dur, 0.09) * 0.9
    thud += sine(55 * pitch, dur) * 0.4 * exp_decay(dur, 0.07)
    click = white_noise(0.02) * exp_decay(0.02, 0.01) * 0.5
    click = lowpass(click, 800)
    out = np.zeros(int(SR * dur))
    out[:len(click)] += click
    return mix(out * 0.3, thud)


def tanky_skill(stage):
    pitch = STAGE_PITCH[stage]
    ln = STAGE_LEN[stage]
    dur = 0.4 * ln
    thud = sine(80 * pitch, dur) * adsr(dur, 0.01, 0.15, 0.4, 0.2) * 0.9
    sub = sine(45 * pitch, dur) * exp_decay(dur, 0.15) * 0.6
    rumble = pink_noise(dur) * 0.3
    rumble = lowpass(rumble, 400)
    return mix(thud, sub, rumble)


def tanky_ultimate():
    dur = 1.0
    rumble = pink_noise(dur) * adsr(dur, 0.02, 0.2, 0.7, 0.4)
    rumble = lowpass(rumble, 350)
    sub = sine(50, dur) * exp_decay(dur, 0.3) * 0.7
    impact = sine(90, 0.3) * exp_decay(0.3, 0.08) * 0.8
    return mix(rumble * 0.7, sub, impact)


def speedy_sfx(stage):
    """Speedy: high fast zap - square 1500Hz."""
    pitch = STAGE_PITCH[stage]
    ln = STAGE_LEN[stage]
    dur = 0.06 * ln
    zap = square(1500 * pitch, dur) * exp_decay(dur, 0.02) * 0.6
    zap += sine(2400 * pitch, dur) * 0.3
    return zap


def speedy_skill(stage):
    pitch = STAGE_PITCH[stage]
    ln = STAGE_LEN[stage]
    parts = []
    for i in range(5):
        d = 0.05 * ln
        z = square((1400 + i * 120) * pitch, d) * exp_decay(d, 0.02) * 0.5
        parts.append(z)
        parts.append(np.zeros(int(SR * 0.03)))
    return concat(*parts)


def speedy_ultimate():
    dur = 0.75
    noise = white_noise(dur) * exp_decay(dur, 0.05) * 0.5
    noise = highpass(noise, 2000)
    zaps = np.zeros(int(SR * dur))
    for i in range(8):
        start = int(i * 0.08 * SR)
        d = 0.05
        seg = square(1600 + i * 150, d) * exp_decay(d, 0.02) * 0.4
        if start + len(seg) < len(zaps):
            zaps[start:start + len(seg)] += seg
    return mix(noise, zaps)


def freezy_sfx(stage):
    """Freezy: ice tinkle - high sine cluster descending."""
    pitch = STAGE_PITCH[stage]
    ln = STAGE_LEN[stage]
    dur = 0.18 * ln
    t = t_axis(dur)
    env = exp_decay(dur, 0.05)
    tones = sum(sine(f * pitch, dur) * env * a for f, a in [(1800, 0.5), (2700, 0.3), (3600, 0.2)])
    sweep_dn = sweep(2200 * pitch, 1200 * pitch, dur) * 0.3
    return mix(tones * 0.5, sweep_dn)


def freezy_skill(stage):
    pitch = STAGE_PITCH[stage]
    ln = STAGE_LEN[stage]
    dur = 0.45 * ln
    shimmer = white_noise(dur) * 0.2
    shimmer = highpass(shimmer, 3000 * pitch) * adsr(dur, 0.02, 0.1, 0.5, 0.2)
    tones = sum(sweep(f0 * pitch, f1 * pitch, dur) * 0.25 for f0, f1 in [(1800, 900), (2700, 1400)])
    return mix(shimmer, tones)


def freezy_ultimate():
    dur = 1.1
    wind = pink_noise(dur) * adsr(dur, 0.05, 0.3, 0.6, 0.4) * 0.5
    wind = highpass(wind, 2500)
    ice = sum(sine(f, dur) * exp_decay(dur, 0.25) * a for f, a in [(1800, 0.4), (2700, 0.25), (3600, 0.15)])
    sweep_dn = sweep(2400, 800, dur) * 0.2
    return reverb_tail(mix(wind, ice, sweep_dn), 0.4, 0.06)


def sparky_sfx(stage):
    """Sparky: electric buzz - sawtooth + noise."""
    pitch = STAGE_PITCH[stage]
    ln = STAGE_LEN[stage]
    dur = 0.12 * ln
    buzz = sawtooth(420 * pitch, dur) * exp_decay(dur, 0.04) * 0.5
    noise = white_noise(dur) * 0.3
    noise = highpass(noise, 2000 * pitch)
    return mix(buzz, noise)


def sparky_skill(stage):
    pitch = STAGE_PITCH[stage]
    ln = STAGE_LEN[stage]
    dur = 0.35 * ln
    buzz = sweep(300 * pitch, 600 * pitch, dur, sawtooth) * adsr(dur, 0.01, 0.08, 0.5, 0.15) * 0.5
    arc = white_noise(dur) * 0.35
    arc = highpass(arc, 1800 * pitch)
    return mix(buzz, arc)


def sparky_ultimate():
    dur = 0.9
    buzz = sweep(250, 800, dur, sawtooth) * adsr(dur, 0.02, 0.15, 0.6, 0.4) * 0.5
    big_noise = white_noise(dur) * adsr(dur, 0.01, 0.1, 0.5, 0.3) * 0.4
    big_noise = highpass(big_noise, 1500)
    sub = sine(60, dur) * exp_decay(dur, 0.2) * 0.4
    return reverb_tail(mix(buzz, big_noise, sub), 0.35, 0.05)


def poisony_sfx(stage):
    """Poisony: bubble - sine 200Hz with vibrato."""
    pitch = STAGE_PITCH[stage]
    ln = STAGE_LEN[stage]
    dur = 0.2 * ln
    t = t_axis(dur)
    lfo = 6 * np.sin(2 * np.pi * 8 * t)
    freq = 200 * pitch + lfo * 40
    phase = 2 * np.pi * np.cumsum(freq) / SR
    bubble = np.sin(phase) * exp_decay(dur, 0.06) * 0.6
    return bubble


def poisony_skill(stage):
    pitch = STAGE_PITCH[stage]
    ln = STAGE_LEN[stage]
    dur = 0.5 * ln
    t = t_axis(dur)
    parts = []
    for i in range(4):
        start = int(i * 0.1 * SR)
        d = 0.15
        lfo = 6 * np.sin(2 * np.pi * 7 * t_axis(d))
        freq = (180 + i * 30) * pitch + lfo * 35
        ph = 2 * np.pi * np.cumsum(freq) / SR
        b = np.sin(ph) * exp_decay(d, 0.05) * 0.4
        parts.append((start, b))
    out = np.zeros(int(SR * dur))
    for s, b in parts:
        place(out, s, b)
    hiss = white_noise(dur) * 0.1
    hiss = highpass(hiss, 3000)
    return mix(out, hiss)


def poisony_ultimate():
    dur = 1.2
    t = t_axis(dur)
    lfo = 5 * np.sin(2 * np.pi * 5 * t)
    freq = 160 + lfo * 50
    phase = 2 * np.pi * np.cumsum(freq) / SR
    drone = np.sin(phase) * adsr(dur, 0.05, 0.3, 0.6, 0.5) * 0.5
    hiss = pink_noise(dur) * adsr(dur, 0.1, 0.3, 0.5, 0.4) * 0.3
    hiss = highpass(hiss, 2500)
    sub = sine(50, dur) * exp_decay(dur, 0.3) * 0.4
    return mix(drone, hiss, sub)


def snipy_sfx(stage):
    """Snipy: crack - noise burst + high sine pop."""
    pitch = STAGE_PITCH[stage]
    ln = STAGE_LEN[stage]
    dur = 0.09 * ln
    crack = white_noise(0.03) * exp_decay(0.03, 0.008) * 0.8
    crack = highpass(crack, 1000)
    pop = sweep(3000 * pitch, 1500 * pitch, dur) * exp_decay(dur, 0.03) * 0.5
    out = np.zeros(int(SR * dur))
    out[:len(crack)] += crack
    return mix(out, pop)


def snipy_skill(stage):
    pitch = STAGE_PITCH[stage]
    ln = STAGE_LEN[stage]
    charge = sweep(400 * pitch, 1800 * pitch, 0.25 * ln) * adsr(0.25 * ln, 0.05, 0.05, 0.6, 0.1) * 0.4
    crack = white_noise(0.04) * exp_decay(0.04, 0.01) * 0.9
    crack = highpass(crack, 1200)
    tail = sine(2000 * pitch, 0.1 * ln) * exp_decay(0.1 * ln, 0.04) * 0.3
    out = np.zeros(int(SR * (0.25 + 0.1) * ln) + 8)
    place(out, 0, charge)
    s = len(charge)
    place(out, s, crack)
    place(out, s, tail)
    return out


def snipy_ultimate():
    dur = 0.85
    charge = sweep(300, 2400, 0.35) * adsr(0.35, 0.05, 0.05, 0.7, 0.1) * 0.4
    crack = white_noise(0.06) * exp_decay(0.06, 0.01) * 1.0
    crack = highpass(crack, 1000)
    echo1 = white_noise(0.04) * exp_decay(0.04, 0.01) * 0.5
    echo1 = highpass(echo1, 1000)
    out = np.zeros(int(SR * dur) + 8)
    place(out, 0, charge)
    s = len(charge)
    place(out, s, crack)
    s2 = s + int(0.15 * SR)
    place(out, s2, echo1)
    return out


def bouncy_sfx(stage):
    """Bouncy: boing - sine wobble 400-600-400."""
    pitch = STAGE_PITCH[stage]
    ln = STAGE_LEN[stage]
    dur = 0.22 * ln
    t = t_axis(dur)
    freq = 400 * pitch + 200 * pitch * np.sin(2 * np.pi * 12 * t)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    boing = np.sin(phase) * exp_decay(dur, 0.08) * 0.6
    return boing


def bouncy_skill(stage):
    pitch = STAGE_PITCH[stage]
    ln = STAGE_LEN[stage]
    parts = []
    for i in range(3):
        d = 0.16 * ln
        t = t_axis(d)
        freq = (380 + i * 50) * pitch + 180 * pitch * np.sin(2 * np.pi * 13 * t)
        ph = 2 * np.pi * np.cumsum(freq) / SR
        b = np.sin(ph) * exp_decay(d, 0.06) * 0.5
        parts.append(b)
        parts.append(np.zeros(int(SR * 0.04)))
    return concat(*parts)


def bouncy_ultimate():
    dur = 1.0
    t = t_axis(dur)
    out = np.zeros(int(SR * dur))
    for i in range(7):
        start = int(i * 0.12 * SR)
        d = 0.14
        tt = t_axis(d)
        freq = (350 + i * 60) + 180 * np.sin(2 * np.pi * 14 * tt)
        ph = 2 * np.pi * np.cumsum(freq) / SR
        b = np.sin(ph) * exp_decay(d, 0.05) * (0.5 - i * 0.04)
        place(out, start, b)
    return out


def lucky_sfx(stage):
    """Lucky: chime - FM bell 880Hz."""
    pitch = STAGE_PITCH[stage]
    ln = STAGE_LEN[stage]
    dur = 0.25 * ln
    t = t_axis(dur)
    carrier = 880 * pitch
    mod = sine(1100 * pitch, dur) * 400 * pitch
    bell = np.sin(2 * np.pi * carrier * t + mod) * exp_decay(dur, 0.12) * 0.5
    harm = sine(1760 * pitch, dur) * exp_decay(dur, 0.08) * 0.2
    return mix(bell, harm)


def lucky_skill(stage):
    pitch = STAGE_PITCH[stage]
    ln = STAGE_LEN[stage]
    dur = 0.4 * ln
    t = t_axis(dur)
    out = np.zeros(int(SR * dur))
    for i, f in enumerate([880, 1100, 1320]):
        start = int(i * 0.08 * SR)
        d = 0.2
        tt = t_axis(d)
        mod = sine(f * 1.25 * pitch, d) * 350 * pitch
        b = np.sin(2 * np.pi * f * pitch * tt + mod) * exp_decay(d, 0.1) * 0.4
        place(out, start, b)
    return out


def lucky_ultimate():
    dur = 1.0
    t = t_axis(dur)
    out = np.zeros(int(SR * dur))
    notes = [659, 880, 1047, 1319, 1760]
    for i, f in enumerate(notes):
        start = int(i * 0.12 * SR)
        d = 0.35
        tt = t_axis(d)
        mod = sine(f * 1.25, d) * 400
        b = np.sin(2 * np.pi * f * tt + mod) * exp_decay(d, 0.15) * 0.4
        place(out, start, b)
    return reverb_tail(out, 0.4, 0.06)


DINO_RECIPES = {
    "rexy": (rexy_sfx, rexy_skill, rexy_ultimate),
    "spike": (spike_sfx, spike_skill, spike_ultimate),
    "tanky": (tanky_sfx, tanky_skill, tanky_ultimate),
    "speedy": (speedy_sfx, speedy_skill, speedy_ultimate),
    "freezy": (freezy_sfx, freezy_skill, freezy_ultimate),
    "sparky": (sparky_sfx, sparky_skill, sparky_ultimate),
    "poisony": (poisony_sfx, poisony_skill, poisony_ultimate),
    "snipy": (snipy_sfx, snipy_skill, snipy_ultimate),
    "bouncy": (bouncy_sfx, bouncy_skill, bouncy_ultimate),
    "lucky": (lucky_sfx, lucky_skill, lucky_ultimate),
}


# ============================================================
# UI SOUNDS
# ============================================================
def ui_tap():
    return sine(800, 0.07) * exp_decay(0.07, 0.02) * 0.5


def ui_coin():
    a = sine(740, 0.06) * exp_decay(0.06, 0.03) * 0.5
    b = sine(990, 0.1) * exp_decay(0.1, 0.05) * 0.5
    return concat(a, b)


def ui_evolve():
    return sweep(300, 700, 0.4) * adsr(0.4, 0.02, 0.1, 0.5, 0.2) * 0.5 + sine(1400, 0.4) * 0.1 * exp_decay(0.4, 0.15)


def ui_win():
    out = np.zeros(0)
    for f in [523, 659, 784, 1047]:
        out = concat(out, sine(f, 0.13) * exp_decay(0.13, 0.08) * 0.5)
    return out


def ui_hurt():
    return sweep(200, 80, 0.4, sawtooth) * adsr(0.4, 0.01, 0.05, 0.5, 0.3) * 0.5


def ui_levelup():
    out = np.zeros(0)
    for f in [659, 880, 1047]:
        out = concat(out, sine(f, 0.08) * exp_decay(0.08, 0.04) * 0.5)
    return out


def ui_deploy():
    return sweep(400, 800, 0.1) * exp_decay(0.1, 0.04) * 0.4


def ui_enemy_reach():
    return sawtooth(120, 0.2) * exp_decay(0.2, 0.06) * 0.4


def main():
    np.random.seed(42)
    count = 0

    # UI sounds
    ui_map = {
        "ui_tap": ui_tap(),
        "ui_coin": ui_coin(),
        "ui_evolve": ui_evolve(),
        "ui_win": ui_win(),
        "ui_hurt": ui_hurt(),
        "ui_levelup": ui_levelup(),
        "ui_deploy": ui_deploy(),
        "ui_enemy_reach": ui_enemy_reach(),
    }
    for name, sig in ui_map.items():
        save(name, sig)
        count += 1

    # Dino sounds
    for dino, (atk, skl, ult) in DINO_RECIPES.items():
        for stage in STAGES:
            save(f"attack_{dino}_{stage}", atk(stage))
            count += 1
            save(f"skill_{dino}_{stage}", skl(stage))
            count += 1
        save(f"ultimate_{dino}", ult())
        count += 1

    print(f"Generated {count} .wav files in {os.path.abspath(OUT)}")


if __name__ == "__main__":
    main()

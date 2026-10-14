"""Create silent MP3 placeholders and synthesized WAV music/effects."""
import math
from pathlib import Path
import random
import wave


OUT = Path(__file__).parent.parent / "assets" / "audio"
NAMES = [
    "tap", "select", "tool", "scrub", "spray", "water", "foam",
    "polish", "clean", "wrong", "complete", "level_start", "pause",
    "resume", "purchase", "win", "jump", "hit", "click", "error",
    "splash", "bubble", "wipe", "coin", "star", "level_complete",
    "menu_bgm", "sponge", "squeegee", "cloth", "brush", "scraper",
    "electric_scrubber", "steam", "glass_cleaner",
]


def silent_mp3(seconds=1):
    # MPEG-1 Layer III, 128 kbps / 44.1 kHz, repeated zero-content frames.
    frame_size = 417
    frame = bytes.fromhex("FF FB 90 64") + bytes(frame_size - 4)
    return frame * max(1, round(seconds * 44100 / 1152))


def create_bgm(path):
    """Write an original, loopable 4-bar chiptune as a stereo WAV."""
    sample_rate = 22050
    bars = 4
    seconds_per_bar = 2
    sample_count = sample_rate * bars * seconds_per_bar
    left = [0.0] * sample_count
    right = [0.0] * sample_count

    def add_note(start, duration, frequency, volume, decay, pan=0.0, pad=False):
        first = round(start * sample_rate)
        count = min(round(duration * sample_rate), sample_count - first)
        if count <= 0:
            return
        left_gain = math.sqrt((1 - pan) / 2)
        right_gain = math.sqrt((1 + pan) / 2)
        for offset in range(count):
            t = offset / sample_rate
            if pad:
                attack = min(1.0, t / 0.18)
                release = min(1.0, (duration - t) / 0.22)
                envelope = attack * release * 0.72
            else:
                envelope = (1 - math.exp(-t * 55)) * math.exp(-decay * t)
            tone = math.sin(2 * math.pi * frequency * t)
            tone += 0.22 * math.sin(2 * math.pi * frequency * 2 * t)
            value = tone * envelope * volume
            index = first + offset
            left[index] += value * left_gain
            right[index] += value * right_gain

    chords = [
        ([(261.63, 329.63, 392.00)], 65.41, (261.63, 392.00, 523.25, 329.63)),
        ([(220.00, 261.63, 329.63)], 55.00, (220.00, 329.63, 440.00, 261.63)),
        ([(174.61, 220.00, 261.63)], 43.65, (174.61, 261.63, 349.23, 220.00)),
        ([(196.00, 246.94, 293.66)], 49.00, (196.00, 293.66, 392.00, 246.94)),
    ]
    melody = [
        523.25, 659.25, 783.99, 659.25,
        440.00, 523.25, 659.25, 783.99,
        349.23, 440.00, 523.25, 440.00,
        392.00, 493.88, 587.33, 783.99,
    ]

    for bar, (chord_group, bass, arp_notes) in enumerate(chords):
        start = bar * seconds_per_bar
        for chord in chord_group:
            for index, note in enumerate(chord):
                add_note(start, seconds_per_bar, note, 0.10, 0, pan=(index - 1) * 0.28, pad=True)
        for beat in range(4):
            add_note(start + beat * 0.5, 0.36, bass * (1.5 if beat == 0 else 1), 0.20, 8)
        for step in range(8):
            note = arp_notes[(step * 2 + bar) % len(arp_notes)]
            add_note(start + step * 0.25, 0.23, note, 0.10, 9, pan=-0.35 if step % 2 else 0.35)

    for index, note in enumerate(melody):
        add_note(index * 0.5, 0.38, note, 0.13, 5, pan=0.12)

    peak = max(max(abs(value) for value in left), max(abs(value) for value in right), 1e-9)
    scale = 0.78 / peak
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        frames = bytearray()
        for index, (l_value, r_value) in enumerate(zip(left, right)):
            # Smooth the loop boundary to avoid an audible click on repeat.
            edge = min(index / (sample_rate * 0.025), (sample_count - 1 - index) / (sample_rate * 0.025), 1)
            l_sample = round(max(-1, min(1, l_value * scale * edge)) * 32767)
            r_sample = round(max(-1, min(1, r_value * scale * edge)) * 32767)
            frames.extend(l_sample.to_bytes(2, "little", signed=True))
            frames.extend(r_sample.to_bytes(2, "little", signed=True))
        output.writeframes(frames)


SFX_PROFILES = {
    "tap": ([(0, 0.08, 980, 560, 0.55)], []),
    "select": ([(0, 0.09, 660, 880, 0.45), (0.07, 0.12, 880, 1180, 0.38)], []),
    "tool": ([(0, 0.13, 480, 220, 0.55), (0.02, 0.09, 920, 620, 0.2)], [(0, 0.08, 0.12)]),
    "scrub": ([(0, 0.24, 180, 120, 0.18)], [(0, 0.25, 0.6)]),
    "spray": ([(0, 0.2, 1250, 720, 0.15)], [(0, 0.23, 0.62)]),
    "water": ([(0, 0.12, 420, 190, 0.5), (0.08, 0.17, 560, 260, 0.36)], [(0, 0.18, 0.28)]),
    "foam": ([(0, 0.12, 360, 220, 0.42), (0.09, 0.15, 510, 270, 0.38), (0.18, 0.15, 430, 190, 0.3)], [(0, 0.3, 0.25)]),
    "polish": ([(0, 0.3, 520, 1700, 0.48), (0.1, 0.25, 1040, 1900, 0.18)], []),
    "clean": ([(0, 0.15, 660, 660, 0.4), (0.08, 0.17, 830, 830, 0.38), (0.16, 0.24, 990, 990, 0.36)], []),
    "wrong": ([(0, 0.24, 520, 180, 0.55), (0.12, 0.2, 350, 140, 0.34)], []),
    "complete": ([(0, 0.2, 523, 523, 0.42), (0.16, 0.2, 659, 659, 0.42), (0.32, 0.2, 784, 784, 0.44), (0.48, 0.38, 1047, 1047, 0.5)], []),
    "level_start": ([(0, 0.16, 392, 392, 0.36), (0.13, 0.16, 523, 523, 0.38), (0.26, 0.16, 659, 659, 0.4), (0.39, 0.26, 784, 784, 0.43)], []),
    "pause": ([(0, 0.22, 760, 360, 0.44)], []),
    "resume": ([(0, 0.22, 360, 760, 0.44)], []),
    "purchase": ([(0, 0.12, 880, 1040, 0.45), (0.1, 0.2, 1320, 1560, 0.48)], []),
    "win": ([(0, 0.16, 523, 523, 0.4), (0.14, 0.16, 659, 659, 0.4), (0.28, 0.16, 784, 784, 0.42), (0.42, 0.35, 1047, 1047, 0.48)], []),
    "jump": ([(0, 0.18, 280, 760, 0.48)], [(0, 0.15, 0.14)]),
    "hit": ([(0, 0.13, 170, 75, 0.58), (0, 0.07, 920, 260, 0.22)], [(0, 0.09, 0.2)]),
    "click": ([(0, 0.055, 1150, 720, 0.5)], []),
    "error": ([(0, 0.18, 600, 230, 0.52), (0.11, 0.2, 380, 150, 0.38)], []),
    "splash": ([(0, 0.23, 360, 110, 0.35)], [(0, 0.19, 0.62)]),
    "bubble": ([(0, 0.12, 420, 760, 0.38), (0.11, 0.13, 580, 980, 0.34), (0.22, 0.14, 350, 670, 0.32)], []),
    "wipe": ([(0, 0.24, 210, 140, 0.15)], [(0, 0.25, 0.55)]),
    "coin": ([(0, 0.08, 740, 900, 0.42), (0.07, 0.17, 1100, 1480, 0.46)], []),
    "star": ([(0, 0.13, 880, 1120, 0.4), (0.08, 0.2, 1320, 1760, 0.45)], []),
    "level_complete": ([(0, 0.18, 523, 523, 0.38), (0.15, 0.18, 659, 659, 0.4), (0.3, 0.18, 784, 784, 0.42), (0.45, 0.36, 1047, 1047, 0.48)], []),
}


def create_sfx(path, tones, noise_bursts):
    sample_rate = 22050
    duration = max(
        [start + length for start, length, *_ in tones]
        + [start + length for start, length, _ in noise_bursts]
    )
    sample_count = round(sample_rate * duration)
    samples = [0.0] * sample_count
    rng = random.Random(path.stem)

    for start, length, first_freq, last_freq, volume in tones:
        first = round(start * sample_rate)
        count = min(round(length * sample_rate), sample_count - first)
        for offset in range(count):
            t = offset / sample_rate
            progress = t / length
            frequency = first_freq + (last_freq - first_freq) * progress
            phase = 2 * math.pi * (first_freq * t + (last_freq - first_freq) * t * t / (2 * length))
            envelope = min(1, t / 0.004, (length - t) / 0.012) * math.exp(-5 * progress)
            samples[first + offset] += (
                math.sin(phase) + 0.16 * math.sin(2 * phase)
            ) * envelope * volume

    for start, length, volume in noise_bursts:
        first = round(start * sample_rate)
        count = min(round(length * sample_rate), sample_count - first)
        for offset in range(count):
            t = offset / sample_rate
            envelope = min(1, t / 0.004, (length - t) / 0.015) * math.exp(-7 * t / length)
            samples[first + offset] += rng.uniform(-1, 1) * envelope * volume

    peak = max(max(map(abs, samples)), 1e-9)
    scale = 0.78 / peak
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        frames = bytearray()
        for sample in samples:
            value = round(max(-1, min(1, sample * scale)) * 32767)
            frames.extend(value.to_bytes(2, "little", signed=True))
        output.writeframes(frames)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name in NAMES:
        (OUT / f"{name}.mp3").write_bytes(silent_mp3())
    create_bgm(OUT / "bgm.wav")
    for name, (tones, noise_bursts) in SFX_PROFILES.items():
        create_sfx(OUT / f"{name}.wav", tones, noise_bursts)
    print(f"Generated {len(NAMES)} silent MP3 placeholders, bgm.wav, and {len(SFX_PROFILES)} SFX WAVs in {OUT}")


if __name__ == "__main__":
    main()

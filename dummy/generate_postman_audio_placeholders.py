"""Create valid, silent MP3 placeholders for Little Forest Postman."""

from pathlib import Path


OUTPUT = Path(__file__).resolve().parents[1] / "assets" / "audio"

SFX = [
    "click",
    "select",
    "toggle",
    "back",
    "step",
    "jump",
    "land",
    "hit",
    "interact",
    "dialogue",
    "pickup",
    "drop",
    "pet",
    "puzzle_open",
    "correct",
    "wrong",
    "error",
    "hint",
    "letter",
    "coin",
    "star",
    "unlock",
    "level_start",
    "win",
    "ending",
]

WORLD_AMBIENCES = [
    "pollen",
    "petal",
    "spore",
    "rain",
    "leaf",
    "firefly",
    "steam",
    "bubble",
    "snow",
    "starfall",
    "cloud_mote",
    "postal_sparkle",
    "rune",
]

MUSIC = ["bgm"]


def silent_mp3(seconds: float) -> bytes:
    """Return MPEG-1 Layer III frames containing silence (44.1 kHz, 128 kbps)."""
    frame_size = 417
    frame = bytes.fromhex("FF FB 90 64") + bytes(frame_size - 4)
    frame_count = max(1, round(seconds * 44100 / 1152))
    return frame * frame_count


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    files = {
        **{f"{name}.mp3": 1.0 for name in SFX},
        **{f"ambience_{name}.mp3": 4.0 for name in WORLD_AMBIENCES},
        **{f"{name}.mp3": 4.0 for name in MUSIC},
    }
    for filename, duration in files.items():
        (OUTPUT / filename).write_bytes(silent_mp3(duration))
    print(f"Generated {len(files)} silent MP3 placeholders in {OUTPUT}")


if __name__ == "__main__":
    main()

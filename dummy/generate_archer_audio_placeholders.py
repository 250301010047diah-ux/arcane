"""Create valid, silent MP3 placeholders for Archer Gunner.

Existing files are never overwritten, so real audio dropped into
assets/audio survives re-running this script.
"""

from pathlib import Path


OUTPUT = Path(__file__).resolve().parents[1] / "assets" / "audio"

# name -> where the game plays it (see game js/game/audio.js SFX_FILES)
SFX = {
    "shoot": "player fires a normal shot",
    "jump": "first jump",
    "double_jump": "second jump in the air",
    "dash": "dash",
    "enemy_hit": "player bullet hits an enemy",
    "enemy_die": "enemy destroyed",
    "enemy_shoot": "enemy fires an orb",
    "player_hurt": "player loses a heart",
    "shield_break": "Aegis shield absorbs a hit",
    "counter": "counter stance blasts back",
    "coin": "coin collected",
    "powerup": "Gatling / Pegasus / Aegis pickup",
    "nova": "Nova pickup clears the screen",
    "skill1": "skill S1",
    "skill2": "skill S2",
    "ultimate": "ultimate (ULT)",
    "laser": "laser column fires (non-lightning realms)",
    "lightning": "lightning strike in Celah Dimensi",
    "boss_appear": "boss enters",
    "boss_attack": "boss attack pattern",
    "boss_hit": "player bullet hits the boss",
    "boss_defeat": "boss destroyed",
    "realm_start": "entering a realm",
    "buff_select": "rune chosen at camp",
    "ui_click": "menu button (skin, area, start, retry)",
    "buy": "skin purchased",
    "win": "all 10 realms cleared",
    "lose": "game over",
}

# bgm1: realm 1-3, bgm2: realm 4-6, bgm3: realm 7-10
BGM = ["bgm1", "bgm2", "bgm3"]


def silent_mp3(seconds):
    # MPEG-1 Layer III, 128 kbps / 44.1 kHz, repeated zero-content frames.
    frame_size = 417
    frame = bytes.fromhex("FF FB 90 64") + bytes(frame_size - 4)
    return frame * max(1, round(seconds * 44100 / 1152))


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    created = []
    for name, seconds in [(name, 0.3) for name in SFX] + [(name, 2.0) for name in BGM]:
        path = OUTPUT / f"{name}.mp3"
        if path.exists():
            continue
        path.write_bytes(silent_mp3(seconds))
        created.append(path.name)
    print(f"Created {len(created)} placeholder(s) in {OUTPUT}")
    for name in created:
        print(f"  {name}")


if __name__ == "__main__":
    main()

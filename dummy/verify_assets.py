import os, re

JS = "game js/game/assets.js"
IMG_DIR = "assets/images"
JSON_DIR = "assets/json"

with open(JS) as f:
    code = f.read()

ATTACK_IDS = ["rexy", "spike", "tanky", "speedy", "freezy", "sparky", "poisony", "snipy", "bouncy", "lucky"]
LEVEL_BG_KEYS = [f"LEVEL_BG_{i:02d}" for i in range(1, 21)]
LEVEL_ENEMY_KEYS = [f"LEVEL_ENEMIES_{i:02d}" for i in range(1, 21)]
ATTACK_KEYS = [f"DINO_ATTACK_{x.upper()}" for x in ATTACK_IDS]
PROJECTILE_KEYS = [f"DINO_PROJECTILE_{x.upper()}" for x in ATTACK_IDS]
SKILL_ULT_KEYS = [f"DINO_SKILL_ULT_{x.upper()}" for x in ATTACK_IDS]

STATIC = ["WORLD_GRASS_BACKDROP", "DINO_ATLAS_A", "DINO_ATLAS_B", "ENEMY_WALK_A", "ENEMY_WALK_B",
          "PROJECTILE_SHEET", "FEEDBACK_SHEET", "UI_ICON_ATLAS"]

def img_for(key):
    if key == "WORLD_GRASS_BACKDROP": return "world_grass_backdrop.webp"
    if key == "DINO_ATLAS_A": return "dino_atlas_a-transparent.webp"
    if key == "DINO_ATLAS_B": return "dino_atlas_b-transparent.webp"
    if key in LEVEL_BG_KEYS: return f"level_bg_{int(key.split('_')[-1]):02d}.webp"
    if key in LEVEL_ENEMY_KEYS: return f"level_enemies_{int(key.split('_')[-1]):02d}-transparent.webp"
    if key in ATTACK_KEYS: return f"dino_attack_{key.split('_')[-1].lower()}-transparent.webp"
    if key in PROJECTILE_KEYS: return f"dino_projectile_{key.split('_')[-1].lower()}-transparent.webp"
    if key in SKILL_ULT_KEYS: return f"dino_skill_ult_{key.split('_')[-1].lower()}-transparent.webp"
    if key == "ENEMY_WALK_A": return "enemy_walk_a-transparent.webp"
    if key == "ENEMY_WALK_B": return "enemy_walk_b-transparent.webp"
    if key == "PROJECTILE_SHEET": return "projectile_sheet-transparent.webp"
    if key == "FEEDBACK_SHEET": return "feedback_sheet-transparent.webp"
    if key == "UI_ICON_ATLAS": return "ui_icon_atlas-transparent.webp"
    return None

def json_for(key):
    if key in STATIC: return img_for(key).replace(".webp", ".frames.json")
    return img_for(key).replace(".webp", ".frames.json")

IMAGE_KEYS = STATIC + LEVEL_BG_KEYS + LEVEL_ENEMY_KEYS + ["DINO_ATLAS_A", "DINO_ATLAS_B"] + ATTACK_KEYS + PROJECTILE_KEYS + SKILL_ULT_KEYS
FRAME_KEYS = ["DINO_ATLAS_A", "DINO_ATLAS_B"] + ATTACK_KEYS + LEVEL_ENEMY_KEYS + PROJECTILE_KEYS + SKILL_ULT_KEYS + ["ENEMY_WALK_A", "ENEMY_WALK_B", "PROJECTILE_SHEET", "FEEDBACK_SHEET", "UI_ICON_ATLAS"]

img_expected = sorted(set(img_for(k) for k in IMAGE_KEYS) - {None})
json_expected = sorted(set(json_for(k) for k in FRAME_KEYS) - {None})

actual_imgs = sorted(os.listdir(IMG_DIR))
actual_jsons = sorted(os.listdir(JSON_DIR))

missing_imgs = [x for x in img_expected if x not in actual_imgs]
extra_imgs = [x for x in actual_imgs if x not in img_expected]
missing_jsons = [x for x in json_expected if x not in actual_jsons]
extra_jsons = [x for x in actual_jsons if x not in json_expected]

print("=== IMAGES ===")
print(f"Expected: {len(img_expected)}, Actual: {len(actual_imgs)}")
print(f"Missing:  {missing_imgs}")
print(f"Extra:    {extra_imgs}")
print("=== JSON ===")
print(f"Expected: {len(json_expected)}, Actual: {len(actual_jsons)}")
print(f"Missing:  {missing_jsons}")
print(f"Extra:    {extra_jsons}")

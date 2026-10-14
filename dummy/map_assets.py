import json
import os
import re
import sys


def frame_url(url):
    # Mirror game js/assets.js frameUrl(): .webp -> .frames.json
    return re.sub(r"\.webp(?:\?.*)?$", ".frames.json", url)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    game_assets = os.path.join(here, "..", "game js", "assets.json")
    links_file = os.path.join(here, "link.json")
    out_file = os.path.join(here, "link-json.json")

    with open(game_assets, "r") as f:
        assets = json.load(f)
    with open(links_file, "r") as f:
        links = json.load(f)

    # Derive base URL from link.json using the matching asset path in assets.json
    base_url = None
    for key, rel in assets.items():
        if key in links and links[key].endswith(rel):
            base_url = links[key][: len(links[key]) - len(rel)]
            break
    if base_url is None:
        sample = next(iter(links.values()))
        base_url = re.sub(r"/generated-assets/.*$", "", sample)

    out = {}
    for key, rel in assets.items():
        if not rel:
            continue
        # BG_ assets only load images, no frames json (see warm() in assets.js)
        if key.startswith("BG_"):
            continue
        full = base_url.rstrip("/") + "/" + rel.lstrip("/")
        out[key] = frame_url(full)

    with open(out_file, "w") as f:
        json.dump(out, f, indent=2)
        f.write("\n")

    print(f"Wrote {len(out)} entries to {out_file}")


if __name__ == "__main__":
    main()

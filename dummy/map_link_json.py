import json
import os
import re
import sys


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    game_assets = os.path.join(here, "..", "game js", "assets.json")
    links_file = os.path.join(here, "link.json")
    out_file = os.path.join(here, "link-json.json")

    with open(game_assets, "r") as f:
        assets = json.load(f)
    with open(links_file, "r") as f:
        links = json.load(f)

    # Derive base URL from link.json using a matching asset path in assets.json
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
        full = base_url.rstrip("/") + "/" + rel.lstrip("/")
        out[key] = full

    with open(out_file, "w") as f:
        json.dump(out, f, indent=2)
        f.write("\n")

    print(f"Wrote {len(out)} entries to {out_file}")


if __name__ == "__main__":
    main()

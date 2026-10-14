import json
import re
import sys


def frame_url(url):
    # Mirror game js/assets.js frameUrl(): .webp -> .frames.json
    return re.sub(r"\.webp(?:\?.*)?$", ".frames.json", url)


def main():
    links_file = sys.argv[1] if len(sys.argv) > 1 else "link.json"
    out_file = sys.argv[2] if len(sys.argv) > 2 else "link-json.json"

    with open(links_file, "r") as f:
        links = json.load(f)

    out = {}
    for key, url in links.items():
        url = url.strip()
        if not url:
            continue
        # BG_ assets only load images, no frames json (see warm() in assets.js)
        # Keys are REALM_BG_xx / REALM_BG_EXT_xx, so match anywhere in the key.
        if "BG_" in key:
            continue
        out[key] = frame_url(url)

    with open(out_file, "w") as f:
        json.dump(out, f, indent=2)
        f.write("\n")

    print(f"Wrote {len(out)} entries to {out_file}")


if __name__ == "__main__":
    main()

import os
import sys
import json
import requests


def download_jsons(links, output_dir="dummy/json"):
    os.makedirs(output_dir, exist_ok=True)
    total = len(links)
    failed = []

    for i, (name, link) in enumerate(links.items(), 1):
        link = link.strip()
        if not link:
            continue

        filename = os.path.basename(link.split("?")[0])
        if not filename:
            filename = f"{name}.json"

        filepath = os.path.join(output_dir, filename)
        print(f"[{i}/{total}] {name} -> {filename}")

        try:
            with requests.get(link, timeout=60) as r:
                r.raise_for_status()
                with open(filepath, "wb") as f:
                    f.write(r.content)
            size_kb = os.path.getsize(filepath) / 1024
            print(f"  OK ({size_kb:.1f} KB)")
        except requests.RequestException as e:
            print(f"  FAILED: {e}")
            failed.append((name, link, str(e)))

    print(f"\nDone. {total - len(failed)}/{total} succeeded.")
    if failed:
        print("Failed:")
        for name, link, err in failed:
            print(f"  - {name}: {err}")


if __name__ == "__main__":
    links_file = sys.argv[1] if len(sys.argv) > 1 else "link-json.json"
    output_dir = sys.argv[2] if len(sys.argv) > 2 else "dummy/json"

    with open(links_file, "r") as f:
        links = json.load(f)

    download_jsons(links, output_dir)

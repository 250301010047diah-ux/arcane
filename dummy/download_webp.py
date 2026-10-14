import json
import os
import ssl
import urllib.request

links = json.load(open("link.json"))
keys = [
    "WORLD_BACKDROPS", "WORLD_BACKDROPS_EXTRA",
    "CLEANER_SKINS", "CLEANER_SKINS_EXTRA", "CLEANER_SKINS_SET_3",
    "CLEANER_SKINS_SET_4", "CLEANER_SKINS_SET_5", "CLEANER_SKINS_SET_6",
    "TOOL_ICONS", "TOOL_ICONS_EXTRA",
    "GRIME_DECALS", "GRIME_DECALS_EXTRA",
    "CLEANING_EFFECTS", "WINDOW_FRAME",
]
out = "../assets/images"
os.makedirs(out, exist_ok=True)
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
for key in keys:
    url = links[key].strip()
    fn = os.path.basename(url.split("?")[0])
    dst = os.path.join(out, fn)
    try:
        data = urllib.request.urlopen(url, context=ctx, timeout=60).read()
        open(dst, "wb").write(data)
        print("OK", key, len(data))
    except Exception as e:
        print("FAIL", key, e)

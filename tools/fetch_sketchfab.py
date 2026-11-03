"""Downloads the Sketchfab (CC Attribution) source models used for enemy bodies.

    SKETCHFAB_TOKEN=... python3 tools/fetch_sketchfab.py OUT_DIR

Each entry is uid:name; the file lands at OUT_DIR/name.glb. Credits live in
assets/characters/CREDITS.md and the in-game credits screen. build_characters.py reads
them from `--sk OUT_DIR`.
"""
import json
import os
import sys
import urllib.request

MODELS = {
    "stalker_src": "d332cac883f54a2c98492e85f41455b2",   # Alien Ninja Creature by Jungle Jim
}


def get(url, token):
    return urllib.request.urlopen(urllib.request.Request(url, headers={"Authorization": "Token " + token}), timeout=300)


def main():
    out = sys.argv[1]
    token = os.environ["SKETCHFAB_TOKEN"]
    os.makedirs(out, exist_ok=True)
    for name, uid in MODELS.items():
        info = json.load(get("https://api.sketchfab.com/v3/models/%s/download" % uid, token))
        data = urllib.request.urlopen(info["glb"]["url"], timeout=600).read() if "glb" in info else None
        if data is None:
            print("no glb for", name)
            continue
        open(os.path.join(out, name + ".glb"), "wb").write(data)
        print("wrote", name, len(data) // 1000, "KB")


if __name__ == "__main__":
    main()

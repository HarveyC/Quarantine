#!/usr/bin/env python3
"""Generate icon art with the Gemini image API (dev tool, needs GEMINI_API_KEY).

    python3 tools/gen_icons.py OUT_DIR name "subject prompt" [name "subject prompt" ...]

Each icon is a single object on a plain dark background, saved as OUT_DIR/name.png.
"""
import base64, json, os, sys, urllib.request

MODEL = os.environ.get("GEMINI_IMAGE_MODEL", "gemini-2.5-flash-image")
STYLE = ("Game icon, one centred object, bold readable silhouette, painted illustration with a dark "
         "industrial sci-fi look, flat dark charcoal background, no text, no border, no frame. Subject: ")


def generate(prompt: str) -> bytes:
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent"
    body = {"contents": [{"parts": [{"text": STYLE + prompt}]}],
            "generationConfig": {"responseModalities": ["IMAGE"]}}
    req = urllib.request.Request(url, json.dumps(body).encode(), {
        "Content-Type": "application/json", "x-goog-api-key": os.environ["GEMINI_API_KEY"]})
    with urllib.request.urlopen(req, timeout=120) as r:
        data = json.load(r)
    for part in data["candidates"][0]["content"]["parts"]:
        if "inlineData" in part:
            return base64.b64decode(part["inlineData"]["data"])
    raise RuntimeError("no image in response")


if __name__ == "__main__":
    out, rest = sys.argv[1], sys.argv[2:]
    os.makedirs(out, exist_ok=True)
    for name, prompt in zip(rest[::2], rest[1::2]):
        with open(os.path.join(out, name + ".png"), "wb") as f:
            f.write(generate(prompt))
        print("wrote", name)

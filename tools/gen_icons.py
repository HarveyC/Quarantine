#!/usr/bin/env python3
"""Generate icon art with the Gemini image API (dev tool, needs GEMINI_API_KEY).

    python3 tools/gen_icons.py OUT_DIR name "subject prompt" [name "subject prompt" ...]

Each icon is a single object on a plain dark background, saved as OUT_DIR/name.png.
"""
import base64, json, os, sys, urllib.request

MODEL = os.environ.get("GEMINI_IMAGE_MODEL", "gemini-2.5-flash-image")
COMMON = ("one centred object filling most of the frame, bold readable silhouette, perfectly flat solid "
          "very dark navy background (#0a0e18) edge to edge, no vignette, no circle, no frame, no border, "
          "no text, no letters, no symbols. Never use cyan or teal; accents are warm amber only. Subject: ")
STYLES = {
    "painted": "Game icon, painted illustration, dark industrial sci-fi, muted steel with amber accents, " + COMMON,
    "flat": "Game icon, flat vector emblem, 3 flat tones, thick clean shapes, no gradients, steel grey with amber highlight, " + COMMON,
    "glow": "Game icon, minimal glowing line art, single amber stroke weight, soft amber bloom glow, no fills, " + COMMON,
}
STYLE = STYLES[os.environ.get("ICON_STYLE", "painted")]


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


def to_mask(png: bytes, size=256) -> "Image.Image":
    """Dark-ground glow art -> white RGBA whose alpha is the glow, so the UI can tint it."""
    from PIL import Image, ImageChops
    import io
    im = Image.open(io.BytesIO(png)).convert("RGB")
    bg = im.getpixel((6, 6))
    lum = ImageChops.subtract(im, Image.new("RGB", im.size, bg)).convert("L").point(lambda p: min(255, int(p * 2.2)))
    lum = lum.point(lambda p: max(0, min(255, int((p - 34) * 1.25))))
    bb = lum.point(lambda p: 255 if p > 24 else 0).getbbox() or (0, 0) + im.size
    pad = 10
    lum = lum.crop((max(0, bb[0] - pad), max(0, bb[1] - pad), min(im.width, bb[2] + pad), min(im.height, bb[3] + pad)))
    k = size / max(lum.size)  # longest side to `size`, aspect kept: wide guns stay wide
    lum = lum.resize((max(1, round(lum.width * k)), max(1, round(lum.height * k))), Image.LANCZOS)
    out = Image.new("RGBA", lum.size, (255, 255, 255, 0))
    out.putalpha(lum)
    return out


if __name__ == "__main__":
    out, rest = sys.argv[1], sys.argv[2:]
    os.makedirs(out, exist_ok=True)
    for name, prompt in zip(rest[::2], rest[1::2]):
        with open(os.path.join(out, name + ".png"), "wb") as f:
            f.write(generate(prompt))
        print("wrote", name)

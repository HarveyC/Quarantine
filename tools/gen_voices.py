#!/usr/bin/env python3
"""Records and processes the story's voice clips (Okafor, the Source, Hale, Halden-Voss).

Two steps, so the recording can run where Inworld is reachable and the processing anywhere:

  python3 tools/gen_voices.py render  RAW_DIR   Records every clip in tools/voice_manifest.json
                                                that RAW_DIR doesn't have yet, with Inworld TTS.
                                                Needs INWORLD_API_KEY (env, or --env FILE).
                                                Standard library only.
  python3 tools/gen_voices.py process RAW_DIR   Turns the raw takes into audio/voice/*.ogg: radio
                                                for Okafor, whisper for the Source, corrupted
                                                radio for Hale. Needs numpy, scipy and ffmpeg.

Refresh the manifest first when a voiced line changes:
  godot --headless -s tools/voice_manifest.gd

A "--" in a line is a burst of interference: its pieces are recorded separately and joined with
static. Raw takes are named <clip>.<piece>.wav. Re-running skips what exists (fixed seeds).
"""
import base64
import json
import os
import subprocess
import sys
import tempfile
import urllib.request
import wave
import zlib

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
MANIFEST = os.path.join(ROOT, "tools", "voice_manifest.json")
OUT = os.path.join(ROOT, "audio", "voice")

MODEL = "inworld-tts-2"
# voice -> (Inworld voice id, text prefix)
VOICES = {
    "okafor": ("Bianca", ""),
    "source": ("Evelyn", "[whispering] "),
    "hale": ("Malcolm", ""),
    "hale_turned": ("Malcolm", ""),
    "hv": ("Beatrice", ""),
    "prophet": ("Levi", ""),
}


def manifest():
    with open(MANIFEST) as f:
        return json.load(f)


def chunks(text):
    return [c.strip() for c in text.split("--")]


def stem(entry):
    return entry["file"][:-4]


# --- render ---------------------------------------------------------------------------------

def read_env_file(path):
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line.startswith("INWORLD_API_KEY="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    return None


def tts(key, voice, text):
    body = json.dumps({"text": text, "voiceId": voice, "modelId": MODEL,
                       "audioConfig": {"audioEncoding": "LINEAR16", "sampleRateHertz": 48000}}).encode()
    req = urllib.request.Request("https://api.inworld.ai/tts/v1/voice", data=body, method="POST",
                                 headers={"Authorization": "Basic " + key, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return base64.b64decode(json.load(r)["audioContent"])


def render(raw, env_file=None):
    key = os.environ.get("INWORLD_API_KEY") or (read_env_file(env_file) if env_file else None)
    if not key:
        sys.exit("INWORLD_API_KEY is not set (pass --env FILE to read it from a .env file)")
    os.makedirs(raw, exist_ok=True)
    made = chars = 0
    for e in manifest():
        voice, prefix = VOICES[e["voice"]]
        for i, c in enumerate(chunks(e["text"])):
            if not c:
                continue
            path = os.path.join(raw, "%s.%d.wav" % (stem(e), i))
            if os.path.exists(path):
                continue
            data = tts(key, voice, prefix + c)
            with open(path, "wb") as f:
                f.write(data)
            made += 1
            chars += len(c)
            print("recorded", os.path.basename(path), c)
    print("%d takes recorded, %d characters" % (made, chars))


# --- process --------------------------------------------------------------------------------

SR = 22050


def _dsp():
    global np, signal
    import numpy as np
    from scipy import signal


def rng(s):
    return np.random.default_rng(zlib.crc32(s.encode()))


def load_wav(path):
    with tempfile.TemporaryDirectory() as d:
        raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "s16le", "-ac", "1",
                              "-ar", str(SR), "-"], capture_output=True, check=True).stdout
    a = np.frombuffer(raw, np.int16).astype(float) / 32768
    idx = np.where(np.abs(a) > 0.01)[0]
    return a[max(0, idx[0] - 200): idx[-1] + 400] if len(idx) else a


def sos(kind, fc, order=2):
    return signal.butter(order, fc, kind, fs=SR, output="sos")


def bp(x, lo, hi, order=2):
    return signal.sosfilt(sos("band", [lo, min(hi, SR * 0.45)], order), x)


def lp(x, fc, order=2):
    return signal.sosfilt(sos("low", min(fc, SR * 0.45), order), x)


def hp(x, fc, order=2):
    return signal.sosfilt(sos("high", fc, order), x)


def norm(a, peak=0.9):
    return a * peak / (np.max(np.abs(a)) + 1e-9)


def sil(d):
    return np.zeros(int(d * SR))


def compress(x, th=0.15, ratio=3.0):
    n = max(1, int(SR * 0.008))
    e = np.sqrt(np.convolve(x ** 2, np.ones(n) / n, "same")) + 1e-6
    return x * np.where(e > th, (th + (e - th) / ratio) / e, 1.0)


def peaking(x, fc, q, gain_db):
    a_ = 10 ** (gain_db / 40)
    w = 2 * np.pi * fc / SR
    al = np.sin(w) / (2 * q)
    return signal.lfilter([1 + al * a_, -2 * np.cos(w), 1 - al * a_], [1 + al / a_, -2 * np.cos(w), 1 - al / a_], x)


def reverb(x, t60=1.2, mix=0.25, seed="rv", damp=4000):
    n = int(t60 * SR)
    ir = lp(rng(seed).standard_normal(n) * np.exp(-6.9 * np.arange(n) / n), damp)
    w = signal.fftconvolve(x, ir)[: len(x) + n]
    w = np.pad(w, (0, len(x) + n - len(w)))
    w = w / (np.max(np.abs(w)) + 1e-9) * np.max(np.abs(x))
    return np.concatenate([x, np.zeros(n)]) * (1 - mix) + w * mix


def noise_band(n, seed, lo, hi):
    return bp(rng(seed).standard_normal(n), lo, hi)


def radio_body(x, seed, drive=2.2, hiss=0.022, crush=0):
    """Field radio: band-limited, driven, compressed, with a hiss bed and the odd crackle."""
    y = bp(hp(x, 140), 320, 3200, 3)
    y = peaking(y, 1800, 1.2, 5)
    y = np.tanh(y * drive) / np.tanh(drive)
    if crush:
        q = 2 ** crush
        y = np.repeat((np.round(y * q) / q)[::2], 2)[: len(y)]
    y = norm(compress(y), 0.8)
    pad = sil(0.05)
    y = np.concatenate([pad, y, pad])
    n = len(y)
    r = rng(seed)
    bed = noise_band(n, seed + "h", 600, 5500) * hiss
    crackle = lp((r.random(n) < 0.0009) * r.standard_normal(n) * 0.25, 5000)
    return y + bed + crackle


def static_burst(d, seed):
    n = int(d * SR)
    r = rng(seed)
    s = noise_band(n, seed, 300, 6000) * 0.5
    gate = (lp(r.random(n), 30) > 0.5 * lp(r.random(n), 30).mean()).astype(float) * 0.6 + 0.4
    chirp = np.sin(2 * np.pi * np.cumsum(np.linspace(r.uniform(400, 900), r.uniform(1500, 2600), n)) / SR) * 0.15
    return (s * gate + chirp) * np.hanning(n) ** 0.3


def squelch_in():
    click = np.zeros(int(0.012 * SR))
    click[0] = 1.0
    click[int(0.004 * SR)] = -0.6
    n = int(0.11 * SR)
    burst = noise_band(n, "sq_in", 900, 5000) * np.linspace(1, 0, n) ** 2 * 0.35
    return np.concatenate([click * 0.7, burst, sil(0.03)])


def squelch_out():
    t = np.arange(int(0.07 * SR)) / SR
    beep = np.sin(2 * np.pi * 1450 * t) * 0.18 * np.minimum(1, (0.07 - t) * 200)
    n = int(0.22 * SR)
    tail = noise_band(n, "sq_out", 700, 6000) * np.linspace(1, 0, n) ** 1.5 * 0.45
    click = np.zeros(int(0.01 * SR))
    click[0] = -0.8
    return np.concatenate([beep, tail, click])


def osc_saw(f, n):
    ph = np.cumsum(np.full(n, f) / SR if np.isscalar(f) else f / SR)
    return 2 * (ph % 1) - 1


def vocoder(mod, carrier, bands=22, lo=120, hi=7000, noise_mix=0.35, seed="v"):
    n = len(mod)
    edges = np.geomspace(lo, hi, bands + 1)
    out = np.zeros(n)
    noise = rng(seed).standard_normal(n)
    for i in range(bands):
        a, b = edges[i], edges[i + 1]
        e = lp(np.abs(bp(mod, a, b, 2)), 60, 2)
        c = bp(carrier, a, b, 2)
        if b > 2500:
            c = c * (1 - noise_mix) + bp(noise, a, b, 2) * noise_mix * 2
        out += c * e
    return norm(out, 0.85)


def stutter(x, seed, n=3):
    """A skipping buffer: a few short chunks repeat."""
    r = rng(seed)
    if len(x) < int(0.5 * SR):
        return x
    cuts = sorted(r.integers(int(0.15 * SR), len(x) - int(0.2 * SR), n))
    out, last = [], 0
    for c in cuts:
        out.append(x[last:c])
        g = int(r.uniform(0.04, 0.09) * SR)
        out += [x[c:c + g]] * int(r.integers(2, 4))
        last = c
    out.append(x[last:])
    return np.concatenate(out)


def turned(sp, seed):
    """Hale after the Bloom: his voice drives a low growl and the signal skips."""
    n = len(sp)
    t = np.arange(n) / SR
    car = osc_saw(62 * (1 + 0.03 * np.sin(2 * np.pi * 5 * t)), n) + 0.6 * osc_saw(31.0, n) + rng(seed).standard_normal(n) * 0.4
    g = vocoder(sp, car, bands=20, lo=60, hi=5000, noise_mix=0.2, seed=seed)
    return stutter(norm(sp, 0.8) * 0.4 + norm(g, 0.8), seed)


def whisper(x, seed):
    """The Source: the whispered take, a very low second voice under it, a reversed swell into
    the line and a long tail."""
    n = len(x)
    deep = vocoder(x, osc_saw(58.0, n), bands=18, lo=80, hi=3000, noise_mix=0.0, seed=seed)
    y = norm(x, 0.8) + norm(lp(deep, 1500), 0.22)
    pre = reverb(norm(x)[::-1], t60=1.8, mix=1.0, seed=seed + "p")[::-1]
    pre = pre[: len(pre) - n][-int(0.9 * SR):]
    pre = pre * np.linspace(0, 0.5, len(pre)) ** 2
    return norm(reverb(np.concatenate([pre, y]), t60=2.2, mix=0.35, seed=seed, damp=3500), 0.8)


def prophet(x, seed):
    """The Choir Prophet: the take, a quieter voice a fifth-ish below it (resampled, so it drifts like
    a second singer), and a long hall tail."""
    n = len(x)
    low = signal.resample(x, int(n * 1.26))[:n]
    low = np.pad(low, (0, n - len(low)))
    y = norm(x, 0.8) + norm(lp(low, 2500), 0.35)
    return norm(reverb(norm(bp(y, 120, 7000, 2)), t60=2.0, mix=0.3, seed=seed + "h", damp=4500), 0.85)


def treat(voice, x, seed):
    if voice == "okafor":
        return radio_body(x, seed)
    if voice == "hale":
        return radio_body(x, seed, drive=3.0, hiss=0.03, crush=7)
    if voice == "hale_turned":
        return radio_body(turned(x, seed), seed, drive=4.0, hiss=0.05, crush=5)
    if voice == "source":
        return whisper(x, seed)
    if voice == "prophet":  # a hymn leader: his own voice plus a slow octave-down choir, in a big room
        return prophet(x, seed)
    if voice == "hv":  # a clean company channel
        return norm(compress(bp(x, 180, 6000, 2)), 0.85)
    raise ValueError(voice)


def write_ogg(path, a, peak=0.89):
    a = np.clip(norm(a, peak), -1, 1)
    with tempfile.TemporaryDirectory() as d:
        tmp = os.path.join(d, "x.wav")
        with wave.open(tmp, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes((a * 32767).astype(np.int16).tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "4", path], check=True)


def process(raw):
    _dsp()
    os.makedirs(OUT, exist_ok=True)
    write_ogg(os.path.join(OUT, "radio_in.ogg"), squelch_in(), 0.7)
    write_ogg(os.path.join(OUT, "radio_out.ogg"), squelch_out(), 0.7)
    write_ogg(os.path.join(OUT, "radio_static.ogg"), static_burst(0.38, "static"), 0.6)
    missing = []
    for e in manifest():
        out = os.path.join(OUT, e["file"])
        parts = []
        cs = chunks(e["text"])
        for i, c in enumerate(cs):
            path = os.path.join(raw, "%s.%d.wav" % (stem(e), i))
            if c and not os.path.exists(path):
                missing.append(os.path.basename(path))
                parts = None
                break
            if c:
                parts.append(treat(e["voice"], load_wav(path), stem(e) + str(i)))
            if i < len(cs) - 1:
                parts.append(static_burst(0.38, stem(e) + "b" + str(i)))
        if parts:
            write_ogg(out, np.concatenate(parts))
    print("processed into audio/voice/; %d takes missing" % len(missing))
    for m in missing[:20]:
        print("  missing", m)


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in ("render", "process"):
        sys.exit(__doc__)
    if sys.argv[1] == "render":
        env = sys.argv[sys.argv.index("--env") + 1] if "--env" in sys.argv else None
        render(sys.argv[2], env)
    else:
        process(sys.argv[2])

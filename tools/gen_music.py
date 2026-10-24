#!/usr/bin/env python3
"""Synthesizes the soundtrack and soundscape from code, so the game ships no third-party audio.

Writes OGG Vorbis files into:
  audio/music/  adaptive music: menu, node map, rest, combat stems, boss stems, stingers
  audio/amb/    seamless ambience beds per act plus one-shot "spot" sounds
  audio/vo/     enemy vocal cues (creature barks, radio chatter, the Source)
  audio/ui/     extra interface sounds

Run from the repo root: python3 tools/gen_music.py [name ...]   (no names = everything)
Needs numpy, scipy and ffmpeg (libvorbis). Re-running gives the same audio (fixed seeds).

Everything is in D minor. The "Bloom motif" (D F E Bb: up a minor third, down a step, down a
tritone) is the infection's signature; it shows up in the menu theme, the combat Bloom layer,
the boss chant and the defeat stinger. The victory stinger resolves it to D major.
"""
import os
import subprocess
import sys
import tempfile
import wave
import zlib

import numpy as np
from scipy import signal

SR = 44100
AUDIO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")


# --- basics ---------------------------------------------------------------------------------

def seeded(name):
    return np.random.default_rng(zlib.crc32(name.encode()))


def n_of(d):
    return max(1, int(round(d * SR)))


def tt(n):
    return np.arange(n) / SR


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def _sos(kind, fc, order):
    if kind == "band":
        lo, hi = fc
        hi = min(hi, SR * 0.45)
        lo = max(10.0, min(lo, hi * 0.9))
        return signal.butter(order, [lo, hi], "band", fs=SR, output="sos")
    return signal.butter(order, min(max(fc, 10.0), SR * 0.45), kind, fs=SR, output="sos")


def lp(x, fc, order=2):
    return signal.sosfilt(_sos("low", fc, order), x, axis=-1)


def hp(x, fc, order=2):
    return signal.sosfilt(_sos("high", fc, order), x, axis=-1)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(_sos("band", (lo, hi), order), x, axis=-1)


def phase(freq, n):
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    return np.cumsum(f) / SR


def saw(freq, n, ph0=0.0):
    return 2 * ((phase(freq, n) + ph0) % 1.0) - 1


def square(freq, n, ph0=0.0, pw=0.5):
    return np.where(((phase(freq, n) + ph0) % 1.0) < pw, 1.0, -1.0)


def sine(freq, n, ph0=0.0):
    return np.sin(2 * np.pi * (phase(freq, n) + ph0))


def tri(freq, n, ph0=0.0):
    return 2 * np.abs(2 * ((phase(freq, n) + ph0) % 1.0) - 1) - 1


def note_env(dur, a=0.01, d=0.2, s=0.8, r=0.3):
    """Attack, decay to sustain, held for `dur`, then a release of `r`. Length dur + r."""
    n = n_of(dur + r)
    x = tt(n)
    e = np.where(x < a, x / max(a, 1e-5), s + (1 - s) * np.exp(-(x - a) / max(d, 1e-5)))
    rel = np.clip((x - dur) / max(r, 1e-5), 0, 1)
    return e * (1 - rel) ** 2


def perc_env(n, decay, attack=0.001):
    x = tt(n)
    return np.clip(x / attack, 0, 1) * np.exp(-x / decay)


def smooth_noise(rng, n, rate):
    """Slowly wandering noise in [-1, 1] (control signal, ~`rate` Hz)."""
    k = max(4, int(n / SR * rate) + 4)
    pts = rng.uniform(-1, 1, k)
    return np.interp(np.linspace(0, k - 3, n), np.arange(k), pts)


def stereo(x, pan=0.0):
    a = (pan + 1) * np.pi / 4
    return np.vstack([x * np.cos(a), x * np.sin(a)]) * np.sqrt(2)


def mono(x):
    return x if x.ndim == 1 else x.mean(axis=0)


# --- reverb and space -----------------------------------------------------------------------

_IRS = {}


def ir(length=3.0, t60=2.4, damp=2500, predelay=0.02, seed="hall"):
    key = (length, t60, damp, predelay, seed)
    if key in _IRS:
        return _IRS[key]
    rng = seeded(seed)
    n = n_of(length)
    x = tt(n)
    out = np.zeros((2, n + n_of(predelay)))
    for ch in range(2):
        w = rng.standard_normal(n)
        bright = w * np.exp(-6.9 * x / (t60 * 0.45))
        dark = lp(w, damp) * np.exp(-6.9 * x / t60)
        out[ch, n_of(predelay):] = 0.35 * bright + dark
    out /= np.sqrt((out ** 2).sum() / 2)
    _IRS[key] = out
    return out


def reverb(buf, mix=0.25, **kw):
    """Convolution reverb on a stereo buffer; the wet tail is cut at the buffer's end."""
    h = ir(**kw)
    wet = np.vstack([signal.fftconvolve(buf[ch], h[ch])[: buf.shape[1]] for ch in range(2)])
    return buf * (1 - mix * 0.5) + wet * mix


def echo(x, delay, fb=0.35, taps=4, damp=3000):
    """Feedback-style echo for mono or stereo signals (length grows by the taps)."""
    d = n_of(delay)
    st = x.ndim == 2
    out = np.zeros(x.shape[:-1] + (x.shape[-1] + d * taps,))
    out[..., : x.shape[-1]] += x
    y = x
    for k in range(1, taps + 1):
        y = lp(y, damp) * fb
        out[..., d * k: d * k + x.shape[-1]] += y
    return out if st else out


# --- buffers --------------------------------------------------------------------------------

class Buf:
    def __init__(self, seconds):
        self.n = n_of(seconds)
        self.a = np.zeros((2, self.n))

    def add(self, sig, t, gain=1.0, pan=0.0):
        s = sig if sig.ndim == 2 else stereo(sig, pan)
        i = n_of(t) if t > 0 else 0
        if i >= self.n:
            return
        k = min(s.shape[1], self.n - i)
        self.a[:, i: i + k] += s[:, :k] * gain


def wrap_loop(a, loop_n):
    """Folds everything past loop_n back onto the start, so release and reverb tails carry over
    the loop point and the loop is seamless."""
    out = a[:, :loop_n].copy()
    k = loop_n
    while k < a.shape[1]:
        seg = a[:, k: k + loop_n]
        out[:, : seg.shape[1]] += seg
        k += loop_n
    return out


def xfade_loop(a, loop_n, fade=3.0):
    """For continuous beds (wind, rain): crossfades the overrun into the start (equal power)."""
    f = min(n_of(fade), a.shape[1] - loop_n)
    out = a[:, :loop_n].copy()
    w = np.linspace(0, np.pi / 2, f)
    out[:, :f] = out[:, :f] * np.sin(w) + a[:, loop_n: loop_n + f] * np.cos(w)
    return out


def loudness(a, rms_db):
    rms = np.sqrt(np.mean(a ** 2)) + 1e-9
    return 10 ** (rms_db / 20) / rms


def limit(a, ceiling=0.97):
    """Soft knee: transparent below ~0.6, rounds peaks off towards the ceiling."""
    k = 0.6
    over = np.abs(a) > k
    y = a.copy()
    y[over] = np.sign(a[over]) * (k + (ceiling - k) * np.tanh((np.abs(a[over]) - k) / (ceiling - k)))
    return y


def master(a, rms_db=-18.0):
    return limit(a * loudness(a, rms_db))


def fade_edges(a, fin=0.005, fout=0.05):
    n = a.shape[-1]
    e = np.ones(n)
    i, o = min(n, n_of(fin)), min(n, n_of(fout))
    e[:i] = np.linspace(0, 1, i)
    e[n - o:] *= np.linspace(1, 0, o)
    return a * e


def write(rel, a, quality=4):
    path = os.path.join(AUDIO, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    a = np.clip(a, -1, 1)
    chans = 1 if a.ndim == 1 else a.shape[0]
    pcm = (a.T if a.ndim == 2 else a) * 32767
    with tempfile.TemporaryDirectory() as d:
        tmp = os.path.join(d, "x.wav")
        with wave.open(tmp, "wb") as w:
            w.setnchannels(chans)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.astype("<i2").tobytes())
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-map_metadata", "-1",
                        "-fflags", "+bitexact", "-flags:a", "+bitexact", "-c:a", "libvorbis",
                        "-q:a", str(quality), path], check=True)
    print("  wrote", rel, "%.1fs" % (a.shape[-1] / SR))


# --- harmony --------------------------------------------------------------------------------

CHORDS = {
    "Dm": (2, 5, 9), "Bb": (10, 2, 5), "Gm": (7, 10, 2), "A": (9, 1, 4), "Asus": (9, 2, 4),
    "C": (0, 4, 7), "F": (5, 9, 0), "Eb": (3, 7, 10), "D": (2, 6, 9),
    "Dm9": (2, 5, 9, 4), "Bbmaj7": (10, 2, 5, 9), "Gm9": (7, 10, 2, 9), "A7sus": (9, 2, 4, 7),
}
MOTIF = [74, 77, 76, 70]       # the Bloom motif: D5 F5 E5 Bb4


def above(pc, lo):
    return lo + ((pc - lo) % 12)


def voicing(ch, lo, count=None):
    notes = sorted(above(pc, lo) for pc in CHORDS[ch])
    while count and len(notes) < count:
        notes.append(notes[len(notes) - len(CHORDS[ch])] + 12)
    return notes[:count] if count else notes


def root(ch, lo):
    return above(CHORDS[ch][0], lo)


def segments(prog):
    """[(chord, first_bar, bars)] runs of equal chords in a per-bar progression."""
    out = []
    for i, c in enumerate(prog):
        if out and out[-1][0] == c:
            out[-1][2] += 1
        else:
            out.append([c, i, 1])
    return out


# --- instruments (mono unless noted) --------------------------------------------------------

def pad(m, dur, a=1.2, r=2.5, cutoff=1200, det=9, seed="pad"):
    """Detuned saw ensemble, stereo (each side has its own detune)."""
    rng = seeded("%s%d%.2f" % (seed, m, dur))
    n = n_of(dur + r)
    f = midi(m)
    out = np.zeros((2, n))
    lfo = 1 + 0.0025 * sine(0.17, n, rng.random())
    for ch in range(2):
        s = np.zeros(n)
        for c in (-det, 0, det):
            cents = c + rng.uniform(-4, 4)
            s += saw(f * 2 ** (cents / 1200) * lfo, n, rng.random())
        out[ch] = lp(s, cutoff, 2) / 3
    return out * note_env(dur, a, 0.8, 0.8, r)


def drone(m, dur, a=2.0, r=3.0, seed="drone"):
    rng = seeded("%s%d" % (seed, m))
    n = n_of(dur + r)
    f = midi(m)
    x = sine(f, n) + 0.35 * lp(tri(f * 2.003, n, rng.random()), 900) + 0.2 * sine(f * 1.5, n)
    x *= 0.8 + 0.2 * sine(0.11, n, rng.random())
    return x * note_env(dur, a, 1.0, 1.0, r)


def pluck(m, dur, bright=1800, fdecay=0.09, decay=0.25, drive=0.0, seed="pluck"):
    rng = seeded("%s%d" % (seed, m))
    n = n_of(dur + 0.25)
    f = midi(m)
    raw = saw(f, n, rng.random()) + 0.5 * square(f * 1.003, n, rng.random())
    x = tt(n)
    fe = np.exp(-x / fdecay)
    y = lp(raw, 220) + (lp(raw, bright) - lp(raw, 220)) * fe
    if drive:
        y = np.tanh(y * (1 + drive)) / np.tanh(1 + drive)
    amp = np.exp(-x / decay) * np.clip(1 - (x - dur) / 0.25, 0, 1)
    return y * amp * np.clip(x / 0.003, 0, 1)


def bell(m, dur=3.0, index=2.5, ratio=3.5):
    n = n_of(dur)
    x = tt(n)
    f = midi(m)
    i = index * np.exp(-x / (dur * 0.25))
    y = np.sin(2 * np.pi * f * x + i * np.sin(2 * np.pi * f * ratio * x)) * np.exp(-x / (dur * 0.3))
    y += 0.25 * np.sin(2 * np.pi * f * 2.76 * x) * np.exp(-x / (dur * 0.12))
    return y * np.clip(x / 0.002, 0, 1)


def epiano(m, dur=2.5):
    n = n_of(dur)
    x = tt(n)
    f = midi(m)
    i = 1.6 * np.exp(-x / 0.35)
    y = np.sin(2 * np.pi * f * x + i * np.sin(2 * np.pi * f * x)) * np.exp(-x / (dur * 0.35))
    y += 0.12 * np.sin(2 * np.pi * f * 14 * x) * np.exp(-x / 0.03)
    return y * np.clip(x / 0.002, 0, 1)


VOWELS = {
    "a": [(800, 80, 1.0), (1150, 90, 0.5), (2900, 120, 0.25), (3900, 130, 0.1)],
    "o": [(450, 70, 1.0), (800, 80, 0.45), (2830, 100, 0.1)],
    "u": [(325, 50, 1.0), (700, 60, 0.25), (2530, 170, 0.05)],
    "e": [(400, 60, 1.0), (1600, 80, 0.4), (2700, 120, 0.2)],
    "i": [(270, 60, 1.0), (2140, 90, 0.3), (2950, 100, 0.2)],
}


def formant(src, vowel, shift=1.0):
    out = np.zeros_like(src)
    for fc, bw, g in VOWELS[vowel]:
        fc *= shift
        out += bp(src, fc - bw * 1.5, fc + bw * 1.5) * g
    return out


def choir(m, dur, vowel="u", a=0.9, r=1.8, voices=4, seed="choir"):
    """Synthetic choir, stereo: glottal saws with vibrato through vowel formants."""
    rng = seeded("%s%d%s%.2f" % (seed, m, vowel, dur))
    n = n_of(dur + r)
    f = midi(m)
    out = np.zeros((2, n))
    for ch in range(2):
        src = np.zeros(n)
        for _ in range(voices):
            vib = 1 + 0.005 * sine(rng.uniform(4.8, 5.8), n, rng.random()) + 0.002 * smooth_noise(rng, n, 3)
            src += saw(f * 2 ** (rng.uniform(-12, 12) / 1200) * vib, n, rng.random())
        breath = bp(rng.uniform(-1, 1, n), 1200, 5000) * 0.25
        out[ch] = formant(src / voices + breath, vowel)
    return out * note_env(dur, a, 1.0, 1.0, r) * 2.2


def strings(m, dur, a=0.5, r=1.2, trem=0.0, seed="str"):
    """Saw string ensemble, stereo; trem > 0 gives a measured tremolo at that rate (Hz)."""
    rng = seeded("%s%d%.2f" % (seed, m, dur))
    n = n_of(dur + r)
    f = midi(m)
    out = np.zeros((2, n))
    for ch in range(2):
        s = np.zeros(n)
        for _ in range(4):
            vib = 1 + 0.003 * sine(rng.uniform(5, 6.2), n, rng.random())
            s += saw(f * 2 ** (rng.uniform(-14, 14) / 1200) * vib, n, rng.random())
        out[ch] = hp(lp(s / 4, 3200), 180)
    if trem:
        x = tt(n)
        out *= 0.55 + 0.45 * (0.5 + 0.5 * np.cos(2 * np.pi * trem * x)) ** 2
    return out * note_env(dur, a, 1.0, 1.0, r)


def brass(m, dur, seed="brass"):
    rng = seeded("%s%d" % (seed, m))
    n = n_of(dur + 0.4)
    f = midi(m)
    x = tt(n)
    scoop = 2 ** (-0.35 * np.exp(-x / 0.05) / 12)
    raw = saw(f * scoop, n, rng.random()) + saw(f * scoop * 1.004, n, rng.random())
    e1 = np.exp(-x / 0.12)
    y = lp(raw, 500) + (lp(raw, 2600) - lp(raw, 500)) * (0.35 + 0.65 * e1)
    y = np.tanh(y * 1.6)
    return y * note_env(dur, 0.025, 0.3, 0.75, 0.4)[:n]


# --- percussion -----------------------------------------------------------------------------

def kick(seed="kick"):
    rng = seeded(seed)
    n = n_of(0.7)
    x = tt(n)
    f = 44 + 120 * np.exp(-x / 0.035)
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-x / 0.32)
    y += lp(rng.uniform(-1, 1, n), 3000) * np.exp(-x / 0.004) * 0.6
    return np.tanh(y * 1.8)


def taiko(seed="taiko"):
    rng = seeded(seed)
    n = n_of(1.4)
    x = tt(n)
    f = 62 + 45 * np.exp(-x / 0.05)
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-x / 0.45)
    y += lp(rng.uniform(-1, 1, n), 380) * np.exp(-x / 0.12) * 1.6
    y += np.sin(2 * np.pi * 175 * x) * np.exp(-x / 0.05) * 0.3
    return np.tanh(y * 1.3)


def snare(seed="snare"):
    rng = seeded(seed)
    n = n_of(0.45)
    x = tt(n)
    y = np.sin(2 * np.pi * 186 * x) * np.exp(-x / 0.06) * 0.6
    y += bp(rng.uniform(-1, 1, n), 1400, 8000) * np.exp(-x / 0.13)
    return y


def hat(open_=False, seed="hat"):
    rng = seeded(seed + str(open_))
    n = n_of(0.5 if open_ else 0.08)
    return hp(rng.uniform(-1, 1, n), 7000) * perc_env(n, 0.18 if open_ else 0.022)


def anvil(seed="anvil"):
    """Industrial metal clank: inharmonic partials plus a click."""
    rng = seeded(seed)
    n = n_of(1.2)
    x = tt(n)
    y = np.zeros(n)
    for ratio, dec, g in [(1, 0.45, 1), (2.32, 0.3, 0.7), (3.67, 0.22, 0.5), (5.11, 0.15, 0.35), (6.8, 0.1, 0.25)]:
        y += np.sin(2 * np.pi * 410 * ratio * x + rng.random() * 6) * np.exp(-x / dec) * g
    y += hp(rng.uniform(-1, 1, n), 2000) * np.exp(-x / 0.01)
    return y * 0.5


def boom(seed="boom"):
    rng = seeded(seed)
    n = n_of(3.0)
    x = tt(n)
    f = 28 + 40 * np.exp(-x / 0.12)
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-x / 1.0)
    y += lp(rng.uniform(-1, 1, n), 160) * np.exp(-x / 0.5) * 2.5
    y += lp(rng.uniform(-1, 1, n), 2500) * np.exp(-x / 0.02) * 0.5
    return np.tanh(y * 1.5)


def swell(dur, seed="swell"):
    """Reverse-cymbal style swell that peaks at its end (place it so it ends on the downbeat)."""
    rng = seeded(seed + str(dur))
    n = n_of(dur)
    x = tt(n)
    e = (x / dur) ** 3
    w = rng.uniform(-1, 1, n)
    y = hp(w, 3000) * 0.6 + bp(w, 400, 3000) * (x / dur)
    return y * e


def heartbeat():
    k = lp(kick("hb"), 400)
    n = n_of(0.9)
    y = np.zeros(n)
    y[: len(k)] += k[:n]
    i = n_of(0.24)
    y[i:] += 0.7 * k[: n - i]
    return y


def whisper(dur, seed="whisper", shift=1.0):
    """Unvoiced syllables: noise through jumping vowel formants. The Bloom talking."""
    rng = seeded(seed)
    n = n_of(dur)
    out = np.zeros(n)
    t = 0.0
    while t < dur - 0.1:
        sl = rng.uniform(0.08, 0.22)
        k = n_of(sl)
        src = rng.uniform(-1, 1, k)
        syl = formant(src, rng.choice(list(VOWELS)), shift * rng.uniform(0.9, 1.15))
        syl += hp(src, 4000) * 0.2 * (rng.random() < 0.4)     # an "s"
        e = np.sin(np.linspace(0, np.pi, k)) ** 1.5
        i = n_of(t)
        out[i: i + k] += (syl * e)[: n - i]
        t += sl + (rng.uniform(0.1, 0.5) if rng.random() < 0.25 else 0.0)
    return out


# --- songs ----------------------------------------------------------------------------------

class Song:
    def __init__(self, bpm, bars, tail=9.0):
        self.bpm = bpm
        self.bars = bars
        self.beat = 60.0 / bpm
        self.length = bars * 4 * self.beat
        self.tail = tail

    def t(self, bar, beat=0.0):
        return (bar * 4 + beat) * self.beat

    def buf(self):
        return Buf(self.length + self.tail)

    def loop_n(self):
        return n_of(self.length)


def finish_loop(song, b, verb=0.25, **kw):
    a = reverb(b.a, verb, **kw) if verb else b.a
    return wrap_loop(a, song.loop_n())


def bed(song, prog, pad_lo=50, cutoff=1000, pad_gain=0.2, drone_gain=0.35, seed="bed"):
    """Drone on the chord root plus a soft pad, chord by chord."""
    b = song.buf()
    for ch, bar, bars in segments(prog):
        dur = bars * 4 * song.beat
        b.add(drone(root(ch, 26), dur, a=1.5, r=2.5, seed=seed), song.t(bar), drone_gain)
        for i, m in enumerate(voicing(ch, pad_lo, 4)):
            b.add(pad(m, dur, a=1.4, r=2.8, cutoff=cutoff, seed=seed), song.t(bar), pad_gain * (0.8 if i else 1.0))
    return b


def motif(b, song, bar, gain=0.2, lo=0, beat_len=1.0, echo_pan=True, inst=bell):
    for i, m in enumerate(MOTIF):
        t = song.t(bar, i * beat_len)
        b.add(inst(m + lo), t, gain, -0.3 + 0.2 * i)
        if echo_pan:
            b.add(inst(m + lo), t + song.beat * 0.75, gain * 0.35, 0.5 - 0.2 * i)


COMBAT_PROG = (["Dm", "Dm", "Bb", "Bb", "Gm", "Gm", "A", "A"] * 2
               + ["Dm", "Dm", "C", "C", "Bb", "Bb", "A", "A", "Gm", "Gm", "Bb", "Bb", "Eb", "Eb", "A", "A"])


def combat_stems():
    """Four stems of one 32-bar loop at 90 BPM, faded in and out by the game:
    base (always), pulse (enemies in sight), danger (heavy contact), bloom (squad Infection)."""
    song = Song(90, 32)
    prog = COMBAT_PROG
    s16 = song.beat / 4

    base = bed(song, prog, cutoff=950, pad_gain=0.17, seed="cb")
    for bar in range(0, 32, 4):     # distant low pulse on the downbeat, like artillery far off
        base.add(lp(taiko("cbt"), 300), song.t(bar), 0.18, 0.0)

    pulse = song.buf()
    gallop = [1, 0, 1, 1, 0, 1, 1, 0, 1, 0, 1, 1, 2, 0, 1, 0]
    for bar, ch in enumerate(prog):
        r = root(ch, 33)
        for st, g in enumerate(gallop):
            if g:
                pulse.add(pluck(r + (12 if g == 2 else 0), s16 * 0.9, bright=900, fdecay=0.07, decay=0.14,
                                drive=0.6, seed="bass"), song.t(bar, st / 4), 0.42)
        tones = voicing(ch, 62, 3)
        arp = tones + [tones[1] + 12, tones[2] + 12] + tones[::-1][1:]
        for st in range(16):
            m = arp[(bar * 16 + st) % len(arp)]
            pulse.add(pluck(m, s16 * 0.8, bright=2300, fdecay=0.05, decay=0.09, seed="arp"),
                      song.t(bar, st / 4), 0.11 * (1.25 if st % 4 == 0 else 1.0), 0.45 if st % 2 else -0.45)
            pulse.add(hat(seed="ph"), song.t(bar, st / 4), 0.07 if st % 2 == 0 else 0.03, 0.25)

    danger = song.buf()
    k, an, tk, sn = kick(), anvil(), taiko(), snare()
    for bar, ch in enumerate(prog):
        for st in (0, 6, 8) + ((14,) if bar % 4 == 3 else ()):
            danger.add(k, song.t(bar, st / 4), 0.55)
        for st in (4, 12):
            danger.add(an, song.t(bar, st / 4), 0.16, 0.2 if st == 4 else -0.2)
            danger.add(snare("ds"), song.t(bar, st / 4), 0.18)
        if bar % 4 == 3:
            for i, st in enumerate((8, 10, 12, 13, 14, 15)):
                danger.add(tk, song.t(bar, st / 4), 0.35 + 0.06 * i, -0.3 + 0.12 * i)
        if bar in (15, 31):
            for st in range(8, 16):
                danger.add(sn, song.t(bar, st / 4), 0.1 + 0.03 * (st - 8))
            sw = swell(song.beat * 2, "dsw%d" % bar)
            danger.add(sw, song.t(bar + 1) - len(sw) / SR, 0.35)
    for ch, bar, bars in segments(prog):
        dur = bars * 4 * song.beat
        for m in voicing(ch, 67, 3):
            danger.add(strings(m, dur, a=0.3, r=1.0, trem=song.bpm / 60 * 4, seed="dstr"), song.t(bar), 0.07)
        for m in voicing(ch, 45, 3):
            danger.add(brass(m, song.beat * 0.6), song.t(bar), 0.16)
            danger.add(brass(m, song.beat * 0.4), song.t(bar, 2.5), 0.09)
        if bar in (0, 16):
            danger.add(boom("db"), song.t(bar), 0.5)

    bloom = song.buf()
    for ch, bar, bars in segments(prog):
        dur = bars * 4 * song.beat
        for m in voicing(ch, 64, 3)[1:]:
            bloom.add(choir(m, dur, "u", a=1.2, r=2.0, seed="cbl"), song.t(bar), 0.13)
    for bar in (3, 11, 19, 27):
        motif(bloom, song, bar, 0.2)
    for bar in range(5, 32, 8):
        bloom.add(whisper(3.5, "cw%d" % bar), song.t(bar), 0.07, -0.6 if bar % 16 == 5 else 0.6)

    stems = [finish_loop(song, b, v) for b, v in ((base, 0.3), (pulse, 0.18), (danger, 0.15), (bloom, 0.4))]
    _write_stems("music/combat", stems, ["base", "pulse", "danger", "bloom"], [-1.0, 0.0, 0.0, -2.0])


BOSS_PROG = ["Dm"] * 4 + ["Eb"] * 4 + ["Dm"] * 4 + ["C", "C", "Bb", "Bb"] + ["Gm"] * 4 + ["A"] * 4


def boss_stems():
    """Three stems of a 24-bar loop at 100 BPM: base, high (boss hurt / enraged), bloom (chant,
    always full for the Source)."""
    song = Song(100, 24)
    prog = BOSS_PROG
    s16 = song.beat / 4
    base = bed(song, prog, pad_lo=45, cutoff=750, pad_gain=0.16, drone_gain=0.4, seed="bb")
    k, tk = kick("bk"), taiko("btk")
    for bar, ch in enumerate(prog):
        r = root(ch, 33)
        for st in range(16):
            acc = st in (0, 3, 6, 10, 12)
            base.add(pluck(r + (12 if st in (6, 14) else 0), s16 * 0.85, bright=1300 if acc else 700, fdecay=0.06,
                           decay=0.12, drive=1.5, seed="bbass"), song.t(bar, st / 4), 0.4 if acc else 0.28)
        for beat in range(4):
            base.add(k, song.t(bar, beat), 0.5)
        base.add(tk, song.t(bar, 0), 0.45, -0.2)
        base.add(tk, song.t(bar, 2), 0.35, 0.2)
        if bar % 2 == 1:
            base.add(tk, song.t(bar, 3.5), 0.3, 0.3)

    high = song.buf()
    an, sn = anvil("ban"), snare("bsn")
    for ch, bar, bars in segments(prog):
        dur = bars * 4 * song.beat
        for m in voicing(ch, 69, 3):
            high.add(strings(m, dur, a=0.15, r=0.8, trem=song.bpm / 60 * 4, seed="bstr"), song.t(bar), 0.075)
    for bar, ch in enumerate(prog):
        for st in (0, 3, 6):
            for m in voicing(ch, 50, 3):
                high.add(brass(m, s16 * 1.6, seed="bbr"), song.t(bar, st / 4), 0.12 if bar % 2 == 0 else 0.07)
        for beat in (1, 3):
            high.add(an, song.t(bar, beat), 0.17, 0.25 if beat == 1 else -0.25)
            high.add(sn, song.t(bar, beat), 0.2)
        if bar % 4 == 3:
            for st in range(16):
                high.add(sn, song.t(bar, st / 4), 0.05 + 0.012 * st)
    for bar in (8, 20):
        motif(high, song, bar, 0.18, lo=-12, inst=lambda m: brass(m, song.beat * 0.9, seed="bmot"), echo_pan=False)

    bloom = song.buf()
    for bar, ch in enumerate(prog):
        tones = voicing(ch, 57, 3)
        for beat in range(4):
            vowel = "a" if beat % 2 == 0 else "o"
            for m in tones:
                bloom.add(choir(m, song.beat * 0.8, vowel, a=0.04, r=0.35, voices=3, seed="bch"),
                          song.t(bar, beat), 0.09 if beat == 0 else 0.06)
    for bar in (4, 16):
        motif(bloom, song, bar, 0.22, lo=0)
    for bar in range(2, 24, 6):
        bloom.add(whisper(4.0, "bw%d" % bar, 0.85), song.t(bar), 0.08, -0.5 if bar % 12 == 2 else 0.5)

    stems = [finish_loop(song, b, v, t60=2.0) for b, v in ((base, 0.18), (high, 0.2), (bloom, 0.4))]
    _write_stems("music/boss", stems, ["base", "high", "bloom"], [-0.5, 0.0, -1.5])


def _write_stems(prefix, stems, names, trims_db):
    """One shared gain for all stems (so their mix balance holds), then each gets a light trim."""
    total = sum(s * 10 ** (tr / 20) for s, tr in zip(stems, trims_db))
    g = loudness(total, -15.0)
    for s, name, tr in zip(stems, names, trims_db):
        write("%s_%s.ogg" % (prefix, name), limit(s * g * 10 ** (tr / 20)))


THEME = [(69, 0, 2), (65, 2, 1), (67, 3, 1), (69, 4, 4), (70, 8, 2), (69, 10, 1), (67, 11, 1), (65, 12, 4),
         (67, 16, 2), (70, 18, 2), (74, 20, 4), (73, 24, 3), (76, 27, 1), (74, 28, 4)]


def menu():
    """"Lantern Company": the title theme. 24 bars at 72 BPM."""
    song = Song(72, 24)
    prog = ["Dm", "Dm", "Bb", "Bb", "Gm", "Gm", "Asus", "A"] * 3
    b = bed(song, prog, cutoff=1150, pad_gain=0.2, seed="menu")
    motif(b, song, 1, 0.22)
    motif(b, song, 21, 0.16, lo=-12)
    for ch, bar, bars in segments(prog[:8]):
        for m in voicing(ch, 64, 3)[1:]:
            b.add(choir(m, bars * 4 * song.beat, "u", seed="mch"), song.t(bar), 0.08)
    for m, beat, ln in THEME:
        t = song.t(8, beat)
        b.add(epiano(m, max(2.0, ln * song.beat * 1.5)), t, 0.2, -0.15)
        b.add(bell(m + 12, 2.0, index=1.2), t, 0.035, 0.3)
    for m, beat, ln in THEME:
        b.add(choir(m - 12, ln * song.beat, "a", a=0.25, r=1.2, seed="mth"), song.t(16, beat), 0.11)
    for ch, bar, bars in segments(prog[16:]):
        for m in voicing(ch, 62, 3):
            b.add(strings(m, bars * 4 * song.beat, a=1.5, r=2.0, seed="mstr"), song.t(16 + bar), 0.05)
        b.add(lp(taiko("mtk"), 500), song.t(16 + bar), 0.3)
    sn = snare("msn")
    for bar in (7, 15, 23):     # far-off parade-ground snare roll swelling into the next phrase
        for st in range(16):
            b.add(lp(sn, 3000), song.t(bar, st / 4), 0.012 + 0.006 * st, 0.4)
    write("music/menu.ogg", master(finish_loop(song, b, 0.45, length=4.0, t60=3.4), -19.0))


def node_map():
    """The route map between fights: tense but unhurried. 24 bars at 80 BPM."""
    song = Song(80, 24)
    prog = ["Dm", "Dm", "Gm", "Gm", "Bb", "Bb", "A", "A"] * 3
    b = bed(song, prog, cutoff=850, pad_gain=0.16, seed="map")
    for bar, ch in enumerate(prog):
        tones = voicing(ch, 57, 3)
        seq = [tones[0], tones[2], tones[1] + 12, tones[2], tones[0] + 12, tones[2], tones[1] + 12, tones[1]]
        for st in range(8):
            if bar % 8 >= 6 and st >= 6:
                continue
            b.add(pluck(seq[st], song.beat * 0.45, bright=1100, fdecay=0.08, decay=0.3, seed="mp"),
                  song.t(bar, st / 2), 0.11, -0.35 if st % 2 else 0.35)
        if bar % 2 == 0:
            b.add(lp(taiko("mpt"), 420), song.t(bar), 0.32)
            b.add(lp(taiko("mpt"), 420), song.t(bar, 0.5), 0.14)
    for bar in (7, 23):
        motif(b, song, bar, 0.12)
    for bar in (12,):
        for m in voicing("Bb", 62, 3):
            b.add(strings(m, 8 * song.beat, a=2.0, r=2.5, seed="mps"), song.t(bar), 0.045)
    write("music/map.ogg", master(finish_loop(song, b, 0.35), -20.0))


def rest():
    """Field hospital and supply depot: a breather that never quite relaxes. 16 bars at 64 BPM."""
    song = Song(64, 16)
    prog = ["Dm9", "Dm9", "Bbmaj7", "Bbmaj7", "Gm9", "Gm9", "A7sus", "A"] * 2
    b = bed(song, prog, pad_lo=52, cutoff=1400, pad_gain=0.12, drone_gain=0.25, seed="rest")
    for bar, ch in enumerate(prog):
        tones = voicing(ch, 55, 4)
        for i, beat in enumerate((0, 1, 2, 3)):
            m = tones[(i * 2 + bar) % len(tones)] + (12 if i == 3 else 0)
            b.add(epiano(m, 3.0), song.t(bar, beat + 0.02 * i), 0.13 if beat == 0 else 0.09, -0.3 + 0.2 * i)
    hope = [74, 78, 76, 69]      # the motif in D major: what the Lanterns are fighting for
    for bar, notes in ((7, MOTIF), (15, hope)):
        for i, m in enumerate(notes):
            b.add(bell(m, 3.0, index=1.5), song.t(bar, i), 0.1, 0.2)
    write("music/rest.ogg", master(finish_loop(song, b, 0.4, t60=3.0), -21.0))


def stinger(name, seconds, fill, rms=-17.0, verb=0.35):
    b = Buf(seconds + 5.0)
    fill(b)
    a = reverb(b.a, verb, t60=2.8)
    write("music/%s.ogg" % name, fade_edges(master(a[:, : n_of(seconds + 4.0)], rms), 0.002, 1.0))


def stingers():
    def win(b):
        b.add(boom("w"), 0.0, 0.45)
        b.add(taiko("w1"), 0.0, 0.5)
        for i, m in enumerate([74, 77, 76]):
            b.add(bell(m, 2.5), 0.12 + i * 0.28, 0.2, -0.3 + 0.3 * i)
        b.add(bell(78, 4.0), 0.12 + 3 * 0.28, 0.28, 0.2)      # the tritone resolves: F# not Bb
        for m in voicing("D", 50, 4):
            b.add(brass(m, 2.4), 0.95, 0.13)
            b.add(strings(m + 12, 3.0, a=0.6, r=2.0, seed="ws"), 0.95, 0.06)
        b.add(drone(38, 3.0, a=0.6, r=2.5), 0.95, 0.35)
        b.add(taiko("w2"), 0.95, 0.4)

    def lose(b):
        b.add(boom("l"), 0.0, 0.4)
        for i, m in enumerate(MOTIF):
            b.add(bell(m - 12, 4.0, index=3.5), 0.3 + i * 0.7, 0.25, -0.4 + 0.25 * i)
        for m, start in ((62, 0.2), (61, 0.2), (55, 1.0), (46, 1.8)):    # a slipping cluster
            b.add(choir(m, 3.2, "o", a=0.6, r=2.5, seed="lc"), start, 0.12)
        b.add(drone(26, 4.0, a=0.3, r=3.0), 0.0, 0.4)
        for i in range(4):
            b.add(heartbeat(), 2.6 + i * 1.05 * (1 + 0.15 * i), 0.45 * (1 - i * 0.22))
        b.add(whisper(3.0, "lw"), 1.5, 0.08, 0.5)

    def contact(b):
        b.add(boom("c"), 0.0, 0.4)
        b.add(anvil("c"), 0.0, 0.25, 0.3)
        for m in (38, 39, 45, 50):        # D, Eb, A, D: a cluster with a flat second
            b.add(brass(m, 0.7), 0.0, 0.16)
        b.add(strings(74, 1.6, a=0.02, r=0.8, trem=24, seed="cs"), 0.0, 0.08)
        b.add(strings(75, 1.6, a=0.02, r=0.8, trem=24, seed="cs2"), 0.0, 0.06)

    def boss(b):
        b.add(boom("b"), 0.0, 0.5)
        b.add(boom("b2"), 1.2, 0.4)
        for m in (50, 51, 57, 62, 63):
            b.add(choir(m, 2.4, "a", a=0.1, r=2.0, voices=5, seed="bc"), 0.0, 0.1)
        for i in range(3):
            b.add(anvil("ba%d" % i), 0.6 + i * 0.3, 0.2, -0.4 + 0.4 * i)
        b.add(taiko("bt"), 1.2, 0.5)
        for m in voicing("Dm", 38, 3):
            b.add(brass(m, 1.8), 1.2, 0.14)

    def node(b):
        b.add(bell(81, 2.5, index=1.0), 0.0, 0.18, -0.2)
        b.add(bell(86, 2.5, index=1.0), 0.18, 0.12, 0.25)
        for m in voicing("Dm9", 57, 4):
            b.add(pad(m, 1.2, a=0.2, r=1.5, cutoff=1500, seed="nd"), 0.0, 0.08)

    def rank(b):
        for i, m in enumerate([62, 65, 69, 74, 77]):
            b.add(bell(m, 2.0, index=1.4), i * 0.09, 0.14, -0.4 + 0.2 * i)
        for m in voicing("Bb", 50, 4):
            b.add(strings(m, 1.4, a=0.15, r=1.5, seed="rk"), 0.3, 0.06)
        b.add(taiko("rk"), 0.3, 0.25)

    stinger("st_win", 4.0, win)
    stinger("st_lose", 6.0, lose, rms=-19.0)
    stinger("st_contact", 2.0, contact, rms=-16.0, verb=0.3)
    stinger("st_boss", 3.5, boss, rms=-15.5)
    stinger("st_node", 1.5, node, rms=-21.0, verb=0.45)
    stinger("st_rank", 2.0, rank, rms=-20.0, verb=0.4)


# --- ambience -------------------------------------------------------------------------------

AMB_LEN = 48.0


def wind(n, rng, lo=180, hi=900, gust=0.08):
    out = np.zeros((2, n))
    g = 0.5 + 0.5 * smooth_noise(rng, n, gust)
    for ch in range(2):
        w = rng.uniform(-1, 1, n)
        brown = hp(lp(w, 300), 25) * 4
        airy = bp(w, lo, hi) * (0.4 + 0.8 * g)
        whistle = bp(w, 1100 + 300 * ch, 1180 + 300 * ch, 2) * 0.25 * g ** 2
        out[ch] = brown * (0.6 + 0.4 * g) + airy + whistle
    return out


def hum(n, base=60.0):
    x = tt(n)
    y = sum(np.sin(2 * np.pi * base * k * x) * g for k, g in ((1, 1), (2, 0.6), (3, 0.35), (5, 0.12)))
    y *= 1 + 0.15 * np.sin(2 * np.pi * 0.31 * x)
    return stereo(lp(y, 600), 0.0)


def scatter(b, rng, rate, length, make, gain, pan=0.9):
    t = rng.exponential(1 / rate)
    while t < length:
        b.add(make(rng), t, gain * rng.uniform(0.5, 1.0), rng.uniform(-pan, pan))
        t += rng.exponential(1 / rate)


def drip(rng, big=False):
    n = n_of(0.25)
    x = tt(n)
    f0 = rng.uniform(900, 1700) * (0.6 if big else 1.0)
    f = f0 * (1 + 0.8 * np.exp(-x / 0.01))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * perc_env(n, 0.03 if not big else 0.06)


def chirp(rng):
    """Native Harrow night insect: a fast trill of high pips."""
    n = n_of(0.5)
    x = tt(n)
    f = rng.uniform(3500, 5200)
    y = np.sin(2 * np.pi * f * x) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * rng.uniform(22, 34) * x)))
    return y * np.sin(np.pi * x / x[-1]) ** 2


def creak(rng, dur=None):
    dur = dur or rng.uniform(1.0, 2.2)
    n = n_of(dur)
    f = rng.uniform(35, 70) * (1 + 0.25 * smooth_noise(rng, n, 6))
    src = saw(f, n) * (1 + 0.5 * smooth_noise(rng, n, 20))
    fc = rng.uniform(350, 800)
    y = bp(src, fc * 0.8, fc * 1.25, 2) + bp(src, fc * 2.1, fc * 2.4, 2) * 0.5
    return y * np.sin(np.linspace(0, np.pi, n)) ** 0.7


def crackle(rng):
    n = n_of(0.04)
    return lp(rng.uniform(-1, 1, n), rng.uniform(1500, 4000)) * perc_env(n, 0.006)


def raindrop(rng):
    n = n_of(0.03)
    x = tt(n)
    return np.sin(2 * np.pi * rng.uniform(2500, 6000) * x) * perc_env(n, 0.004)


def radio_babble(dur, rng, f0=125.0):
    """Garbled radio speech: voiced syllables at speech rhythm, band-limited and crushed."""
    n = n_of(dur)
    out = np.zeros(n)
    t = 0.0
    while t < dur - 0.1:
        sl = rng.uniform(0.07, 0.2)
        k = n_of(sl)
        f = f0 * rng.uniform(0.85, 1.25) * (1 + 0.1 * np.linspace(1, -1, k) * rng.uniform(-1, 1))
        src = saw(f, k) + 0.2 * rng.uniform(-1, 1, k)
        syl = formant(src, rng.choice(list(VOWELS)))
        i = n_of(t)
        out[i: i + k] += (syl * np.sin(np.linspace(0, np.pi, k)) ** 0.8)[: n - i]
        t += sl + (rng.uniform(0.15, 0.45) if rng.random() < 0.2 else 0.01)
    out = bp(out, 350, 2800, 2)
    out = np.tanh(out * 4) * 0.5
    return out + bp(rng.uniform(-1, 1, n), 800, 5000) * 0.04


def squelch(rng):
    n = n_of(0.12)
    x = tt(n)
    return (bp(rng.uniform(-1, 1, n), 1000, 6000) * 0.6 + np.sin(2 * np.pi * 1250 * x) * 0.3) * perc_env(n, 0.05, 0.002)


def amb_wall():
    """Act 1, The Wall: the cordon at night. Wind on the barrier, floodlight hum, a generator,
    chain-link, native insects."""
    rng = seeded("wall")
    b = Buf(AMB_LEN + 4)
    b.add(wind(b.n, rng, 200, 1000, 0.07), 0.0, 0.5)
    b.add(hum(b.n), 0.0, 0.05)
    x = tt(b.n)
    gen = lp(rng.uniform(-1, 1, b.n), 90) * (0.7 + 0.3 * np.sin(2 * np.pi * 24.5 * x)) * 3
    b.add(stereo(gen, -0.5), 0.0, 0.18)
    scatter(b, rng, 0.25, AMB_LEN, chirp, 0.025)
    scatter(b, rng, 0.12, AMB_LEN, lambda r: fence(r), 0.08)
    write("amb/amb_wall.ogg", master(xfade_loop(reverb(b.a, 0.2, seed="out"), n_of(AMB_LEN)), -24.0), 3)


def fence(rng):
    n = n_of(1.4)
    y = np.zeros(n)
    t = 0.0
    while t < 1.2:
        i = n_of(t)
        k = n_of(0.02)
        y[i: i + k] += hp(rng.uniform(-1, 1, k), 3000) * perc_env(k, 0.004) * rng.uniform(0.3, 1)
        t += rng.exponential(0.03)
    return y * np.sin(np.linspace(0, np.pi, n))


def amb_port():
    """Act 2, Port Ardent: a dead city in the rain. Rain, gutters, distant fires, groaning steel."""
    rng = seeded("port")
    b = Buf(AMB_LEN + 4)
    for ch, pan in ((0, -0.7), (1, 0.7)):
        w = rng.uniform(-1, 1, b.n)
        rain = bp(w, 600, 7000) * 0.5 + lp(w, 400) * 0.6
        b.add(stereo(rain * (0.85 + 0.15 * smooth_noise(rng, b.n, 0.2)), pan), 0.0, 0.3)
    scatter(b, rng, 45, AMB_LEN, raindrop, 0.04)
    scatter(b, rng, 1.2, AMB_LEN, drip, 0.06, 0.7)
    scatter(b, rng, 9, AMB_LEN, crackle, 0.05, 0.3)
    scatter(b, rng, 0.07, AMB_LEN, creak, 0.12)
    b.add(wind(b.n, rng, 150, 500, 0.05), 0.0, 0.25)
    write("amb/amb_port.ogg", master(xfade_loop(reverb(b.a, 0.3, seed="city", t60=2.0), n_of(AMB_LEN)), -24.0), 3)


def amb_bore():
    """Act 3, The Bore: the shaft. Sub rumble, drips in a huge space, the Bloom breathing."""
    rng = seeded("bore")
    b = Buf(AMB_LEN + 4)
    x = tt(b.n)
    for ch, pan in ((0, -0.6), (1, 0.6)):
        w = rng.uniform(-1, 1, b.n)
        rumble = hp(lp(w, 70), 18) * 6
        b.add(stereo(rumble, pan), 0.0, 0.35)
    breath = 0.5 - 0.5 * np.cos(2 * np.pi * x / (AMB_LEN / 7))     # 7 breaths per loop
    w = rng.uniform(-1, 1, b.n)
    b.add(stereo(bp(w, 250, 900) * breath ** 2, 0.0), 0.0, 0.3)
    shimmer = sum(np.sin(2 * np.pi * f * x + rng.random() * 6) for f in (1318.5, 1567.98, 2093.0, 2349.3))
    b.add(stereo(shimmer * (0.5 + 0.5 * breath) * 0.25, 0.3), 0.0, 0.035)
    scatter(b, rng, 0.6, AMB_LEN, lambda r: drip(r, True), 0.08)
    scatter(b, rng, 0.05, AMB_LEN, lambda r: creak(r, 2.5), 0.08)
    for i, t in enumerate((6.0, 22.0, 37.0)):
        b.add(whisper(3.0, "bw%d" % i, 0.9), t, 0.04, (-0.7, 0.6, -0.1)[i])
    write("amb/amb_bore.ogg", master(xfade_loop(reverb(b.a, 0.45, seed="cave", length=4.5, t60=4.0),
                                                 n_of(AMB_LEN)), -24.0), 3)


def amb_map():
    """Command tent between fights: room tone, radio traffic, rotors passing far away."""
    rng = seeded("map")
    b = Buf(AMB_LEN + 4)
    for pan in (-0.5, 0.5):
        b.add(stereo(lp(rng.uniform(-1, 1, b.n), 350) * 2, pan), 0.0, 0.12)
    b.add(wind(b.n, rng, 150, 400, 0.04), 0.0, 0.12)
    for t, d in ((3.0, 3.5), (15.0, 2.5), (27.5, 4.0), (40.0, 2.0)):
        b.add(squelch(rng), t, 0.15, -0.6)
        b.add(radio_babble(d, rng, rng.uniform(105, 140)), t + 0.1, 0.13, -0.6)
        b.add(squelch(rng), t + d + 0.1, 0.12, -0.6)
    for t in (8.0, 33.0):
        b.add(rotor(rng, 11.0), t, 0.25)
    write("amb/amb_map.ogg", master(xfade_loop(reverb(b.a, 0.15, seed="room", length=1.2, t60=0.6),
                                                n_of(AMB_LEN)), -26.0), 3)


def rotor(rng, dur):
    n = n_of(dur)
    x = tt(n)
    thump = (0.5 + 0.5 * np.cos(2 * np.pi * 5.6 * x)) ** 6
    y = lp(rng.uniform(-1, 1, n), 260) * thump * 4 + lp(rng.uniform(-1, 1, n), 1500) * 0.1
    e = np.sin(np.pi * x / dur) ** 2
    pan = np.linspace(-0.9, 0.9, n)
    return np.vstack([y * e * np.cos((pan + 1) * np.pi / 4), y * e * np.sin((pan + 1) * np.pi / 4)]) * 1.4


# --- spot sounds (one-shots scattered by the game over the ambience) ------------------------

def spot(name, seconds, make, rms=-22.0, verb=0.5, **kw):
    b = Buf(seconds + 4.0)
    make(b, seeded(name))
    a = reverb(b.a, verb, **kw)
    write("amb/%s.ogg" % name, fade_edges(master(a[:, : n_of(seconds + 3.0)], rms), 0.002, 0.8), 3)


def spots():
    def siren(b, rng, pan):
        n = n_of(7.0)
        x = tt(n)
        f = 700 + 220 * np.sin(2 * np.pi * x / 3.2 - np.pi / 2)
        y = sine(f, n) + 0.4 * sine(f * 2, n) + 0.2 * sine(f * 3, n)
        b.add(lp(y, 1400) * np.sin(np.pi * x / 7.0) ** 2, 0.0, 0.3, pan)

    def gunfire(b, rng, pan):
        t = 0.0
        for burst in range(rng.integers(2, 4)):
            for _ in range(rng.integers(3, 7)):
                n = n_of(0.15)
                pop = lp(rng.uniform(-1, 1, n), 900) * perc_env(n, 0.03)
                b.add(pop, t, 0.6, pan)
                t += rng.uniform(0.07, 0.11)
            t += rng.uniform(0.6, 1.4)

    def howl(b, rng, pan):
        b.add(lp(creature(3.0, [300, 520, 480, 260], ["u", "o", "a", "u"], 0.35, 0.3, 30, rng), 1800), 0.0, 0.5, pan)

    def pa(b, rng, pan):
        n = n_of(0.5)
        x = tt(n)
        for i, f in enumerate((659.3, 523.3)):
            tone = (np.sin(2 * np.pi * f * x) + 0.3 * np.sin(4 * np.pi * f * x)) * perc_env(n, 0.3, 0.01)
            b.add(tone, i * 0.45, 0.25, pan)
        b.add(echo(radio_babble(2.8, rng, 115), 0.23, 0.4, 3), 1.2, 0.35, pan)

    def glass(b, rng, pan):
        n = n_of(0.15)
        b.add(hp(rng.uniform(-1, 1, n), 2000) * perc_env(n, 0.05), 0.0, 0.5, pan)
        for _ in range(40):
            k = n_of(0.3)
            x = tt(k)
            ping = np.sin(2 * np.pi * rng.uniform(3000, 9000) * x) * perc_env(k, rng.uniform(0.02, 0.08))
            b.add(ping, rng.exponential(0.25), 0.12, pan + rng.uniform(-0.2, 0.2))

    def collapse(b, rng, pan):
        n = n_of(3.0)
        x = tt(n)
        b.add(lp(rng.uniform(-1, 1, n), 120) * np.exp(-x / 1.2) * 3, 0.0, 0.5, pan)
        for _ in range(30):
            k = n_of(0.1)
            b.add(lp(rng.uniform(-1, 1, k), rng.uniform(400, 2500)) * perc_env(k, 0.02), rng.exponential(0.8), 0.25, pan)

    def rumble(b, rng, pan):
        n = n_of(4.5)
        x = tt(n)
        b.add(stereo(hp(lp(rng.uniform(-1, 1, n), 80), 18) * np.sin(np.pi * x / 4.5) ** 2 * 6, pan), 0.0, 0.6)

    def bloom_pulse(b, rng, pan):
        for i in range(3):
            b.add(heartbeat(), i * 0.95, 0.5)
        n = n_of(3.0)
        x = tt(n)
        sh = sum(np.sin(2 * np.pi * f * x) for f in (1318.5, 1396.9, 2093.0))
        b.add(sh * np.sin(np.pi * x / 3.0) ** 2 * 0.25, 0.2, 0.25, pan)

    def drip_echo(b, rng, pan):
        for i in range(3):
            b.add(drip(rng, True), i * rng.uniform(0.4, 0.9), 0.5, pan)

    for i, pan in enumerate((-0.7, 0.6)):
        spot("spot_siren_%d" % (i + 1), 7.0, lambda b, r, p=pan: siren(b, r, p), verb=0.6, length=4.0, t60=3.5)
        spot("spot_gunfire_%d" % (i + 1), 4.0, lambda b, r, p=pan: gunfire(b, r, p), verb=0.6, seed="far", length=3.5, t60=2.8)
        spot("spot_howl_%d" % (i + 1), 3.5, lambda b, r, p=pan: howl(b, r, p), verb=0.6, length=4.0, t60=3.2)
        spot("spot_whisper_%d" % (i + 1), 3.0, lambda b, r, p=pan, k=i: b.add(whisper(3.0, "sw%d" % k, 0.9), 0.0, 0.5, p), verb=0.5)
    spot("spot_pa", 5.0, lambda b, r: pa(b, r, 0.3), verb=0.5, length=3.0, t60=2.4)
    spot("spot_fence", 1.5, lambda b, r: b.add(fence(r), 0.0, 0.6, -0.4), verb=0.2)
    spot("spot_glass", 2.0, lambda b, r: glass(b, r, 0.5), verb=0.4)
    spot("spot_collapse", 3.5, lambda b, r: collapse(b, r, -0.5), verb=0.5, length=3.5)
    spot("spot_creak", 2.5, lambda b, r: b.add(creak(r, 2.2), 0.0, 0.6, 0.4), verb=0.45)
    spot("spot_rumble", 4.5, lambda b, r: rumble(b, r, 0.0), verb=0.3)
    spot("spot_bloom", 3.5, lambda b, r: bloom_pulse(b, r, -0.2), verb=0.5, length=4.0, t60=3.8)
    spot("spot_drip", 3.0, lambda b, r: drip_echo(b, r, 0.5), verb=0.7, seed="cave", length=4.5, t60=4.0)
    spot("spot_rotor", 11.0, lambda b, r: b.a.__iadd__(_pad_to(rotor(r, 11.0), b.n)), verb=0.2)


def _pad_to(a, n):
    out = np.zeros((2, n))
    out[:, : min(n, a.shape[1])] = a[:, :n]
    return out


# --- enemy voices ---------------------------------------------------------------------------

def creature(dur, f0_pts, vowels, rough, breath, growl_hz, rng, drive=2.5, shift=1.0):
    """A throat: glottal saw on an f0 contour, growl (subharmonic + flutter), breath noise,
    morphing between vowels."""
    n = n_of(dur)
    pos = np.linspace(0, 1, n)
    f0 = np.interp(pos, np.linspace(0, 1, len(f0_pts)), f0_pts)
    f0 = f0 * (1 + 0.04 * smooth_noise(rng, n, 25))
    src = saw(f0, n) + rough * square(f0 / 2, n) * 0.6
    src *= 1 - rough * 0.45 * (1 + np.sin(2 * np.pi * growl_hz * tt(n) + 3 * smooth_noise(rng, n, 8)))
    src += rng.uniform(-1, 1, n) * breath * 2
    k = len(vowels)
    w = pos * (k - 1)
    y = np.zeros(n)
    for i, v in enumerate(vowels):
        g = np.clip(1 - np.abs(w - i), 0, 1)
        y += formant(src, v, shift) * g
    y = np.tanh(y * drive)
    e = np.clip(tt(n) / 0.02, 0, 1) * np.clip((dur - tt(n)) / (dur * 0.35), 0, 1) ** 1.2
    return y * e


def hiss(dur, rng, lo=2500, hi=9000):
    n = n_of(dur)
    return bp(rng.uniform(-1, 1, n), lo, hi) * np.sin(np.linspace(0, np.pi, n)) ** 0.6


def clicks(dur, rng, rate=28, pitch=1800):
    n = n_of(dur)
    y = np.zeros(n)
    t = 0.0
    while t < dur - 0.02:
        k = n_of(0.012)
        i = n_of(t)
        y[i: i + k] += bp(rng.uniform(-1, 1, k), pitch, pitch * 2.5) * perc_env(k, 0.002) * rng.uniform(0.5, 1)
        t += rng.exponential(1 / rate)
    return y


def radio_bark(dur, rng, f0=120, harsh=1.0):
    y = np.concatenate([squelch(rng), radio_babble(dur, rng, f0) * harsh, squelch(rng)])
    return np.tanh(y * 1.5)


VOICES = {
    # kind: (bark, die) builders taking an rng
    "runner": (lambda r: creature(0.55, [560, 900, 700, 480], ["a", "e", "a"], 0.5, 0.25, 55, r),
               lambda r: creature(0.8, [700, 420, 200], ["a", "o", "u"], 0.6, 0.3, 40, r)),
    "spitter": (lambda r: mix(creature(0.7, [140, 180, 120], ["o", "u", "o"], 0.7, 0.35, 18, r), bubbles(0.7, r)),
                lambda r: mix(creature(0.9, [160, 110, 70], ["o", "u"], 0.8, 0.4, 14, r), bubbles(0.9, r))),
    "fallen": (lambda r: creature(1.0, [118, 128, 96], ["o", "u", "o"], 0.25, 0.2, 9, r, 1.8),
               lambda r: creature(1.2, [110, 85, 60], ["o", "u"], 0.35, 0.3, 7, r, 1.8)),
    "bloater": (lambda r: mix(creature(1.1, [70, 82, 64], ["o", "u"], 0.8, 0.3, 11, r, 2.0), bubbles(1.1, r, 3)),
                lambda r: mix(creature(0.9, [80, 50], ["u", "o"], 0.9, 0.5, 9, r, 2.0), bubbles(0.9, r, 4))),
    "lurker": (lambda r: mix(clicks(0.6, r), hiss(0.6, r) * 0.25),
               lambda r: mix(creature(0.6, [900, 400], ["i", "u"], 0.4, 0.5, 60, r) * 0.6, clicks(0.4, r, 40))),
    "shrieker": (lambda r: creature(1.4, [1100, 1700, 1500, 1800, 1300], ["e", "i", "a", "i"], 0.3, 0.3, 70, r, 3.0),
                 lambda r: creature(1.0, [1500, 900, 400], ["i", "a", "u"], 0.4, 0.4, 50, r, 3.0)),
    "brute": (lambda r: creature(1.1, [85, 150, 130, 75], ["a", "a", "o"], 0.9, 0.3, 28, r, 3.2, 0.8),
              lambda r: creature(1.4, [120, 70, 45], ["a", "o", "u"], 0.9, 0.35, 20, r, 3.0, 0.8)),
    "leaper": (lambda r: mix(hiss(0.4, r, 3000, 10000) * 0.7, clicks(0.5, r, 45, 2500) * 0.8),
               lambda r: creature(0.6, [800, 500, 300], ["e", "u"], 0.5, 0.4, 45, r)),
    "drifter": (lambda r: creature(1.2, [380, 420, 360, 440], ["u", "o", "u"], 0.05, 0.6, 4, r, 1.2) * 0.7,
                lambda r: creature(1.0, [420, 250], ["u", "u"], 0.1, 0.7, 4, r, 1.2) * 0.7),
    "sharpshooter": (lambda r: radio_bark(0.9, r, 112),
                     lambda r: np.concatenate([radio_babble(0.3, r, 110), squelch(r) * 2])),
    "burrower": (lambda r: mix(creature(0.9, [60, 90, 55], ["u", "o"], 0.9, 0.5, 13, r, 2.5), clicks(0.9, r, 20, 1200) * 0.6),
                 lambda r: creature(0.8, [80, 40], ["o", "u"], 0.9, 0.5, 10, r, 2.5)),
    "broodling": (lambda r: creature(0.3, [1300, 1600], ["i", "e"], 0.3, 0.3, 80, r, 2.0),
                  lambda r: creature(0.35, [1500, 700], ["i", "u"], 0.3, 0.4, 60, r, 2.0)),
    "brood_mother": (lambda r: mix(creature(1.8, [180, 320, 260, 140], ["a", "o", "a", "u"], 0.8, 0.4, 24, r, 3.2, 0.75),
                                   creature(1.8, [1200, 1600, 1100, 900], ["i", "e", "i", "e"], 0.3, 0.2, 60, r, 2.0) * 0.4),
                     lambda r: creature(2.4, [260, 120, 50], ["a", "o", "u"], 0.9, 0.4, 18, r, 3.0, 0.75)),
    "colonel_hale": (lambda r: radio_bark(1.3, r, 98, 1.3),
                     lambda r: np.concatenate([radio_babble(0.6, r, 90), squelch(r), squelch(r) * 0.5])),
    "the_source": (lambda r: source_voice(3.0, r), lambda r: source_voice(4.5, r, dying=True)),
}


def mix(*xs):
    """Sums signals of different lengths (padding the shorter ones)."""
    n = max(len(x) for x in xs)
    out = np.zeros(n)
    for x in xs:
        out[: len(x)] += x
    return out


def bubbles(dur, rng, rate=14):
    n = n_of(dur)
    y = np.zeros(n)
    t = 0.0
    while t < dur - 0.05:
        k = n_of(0.05)
        x = tt(k)
        f = rng.uniform(150, 500) * (1 + 2 * x / 0.05)
        y[n_of(t): n_of(t) + k] += np.sin(2 * np.pi * np.cumsum(f) / SR)[: n - n_of(t)] * perc_env(k, 0.012) * 0.3
        t += rng.exponential(1 / rate)
    return y


def source_voice(dur, rng, dying=False):
    """The Source: a chord of throats an octave apart under a whisper."""
    n = n_of(dur)
    y = np.zeros(n)
    for f in (36.7, 55.0, 73.4, 77.8):      # D1 A1 D2 Eb2
        pts = [f, f * 1.02, f] if not dying else [f, f * 0.7, f * 0.5]
        y += creature(dur, pts, ["u", "o", "a", "u"], 0.4, 0.15, 6, rng, 1.6, 0.7)
    y += whisper(dur, "sv%d" % dying, 0.75) * 0.6
    return y * 0.6


def voices():
    for kind, (bark, die) in VOICES.items():
        for tag, make in (("", bark), ("_die", die)):
            rng = seeded(kind + tag)
            y = make(rng)
            y = hp(y, 60)
            peak = np.max(np.abs(y)) + 1e-9
            write("vo/%s%s.ogg" % (kind, tag), fade_edges(y / peak * 0.85, 0.003, 0.08), 4)


# --- interface ------------------------------------------------------------------------------

def ui():
    def blip(f, dur, decay, f_end=None, noise=0.0, seed="ui"):
        rng = seeded(seed)
        n = n_of(dur)
        x = tt(n)
        ff = f if f_end is None else f * (f_end / f) ** (x / dur)
        y = np.sin(2 * np.pi * np.cumsum(np.broadcast_to(ff, (n,))) / SR) + 0.25 * np.sin(4 * np.pi * np.cumsum(np.broadcast_to(ff, (n,))) / SR)
        y += hp(rng.uniform(-1, 1, n), 4000) * noise
        return y * perc_env(n, decay, 0.002)

    def out(name, y):
        write("ui/%s.ogg" % name, fade_edges(y / (np.max(np.abs(y)) + 1e-9) * 0.7, 0.001, 0.02), 4)

    out("open", np.concatenate([blip(520, 0.06, 0.03), blip(780, 0.12, 0.05)]) + 0.0)
    out("close", np.concatenate([blip(780, 0.06, 0.03), blip(520, 0.12, 0.05)]))
    out("tick", blip(2200, 0.03, 0.006, noise=0.3, seed="tick"))
    out("vote", blip(660, 0.25, 0.08, 990))
    out("ready", np.concatenate([blip(587, 0.08, 0.04), blip(880, 0.22, 0.09)]))
    out("pick", blip(440, 0.35, 0.12, 880) * 0.7 + blip(1320, 0.35, 0.1) * 0.3)
    n = n_of(0.4)
    x = tt(n)
    out("node", (np.sin(2 * np.pi * 1174.7 * x) + 0.5 * np.sin(2 * np.pi * 1760 * x)) * perc_env(n, 0.12))
    out("page", hp(seeded("page").uniform(-1, 1, n_of(0.18)), 1500) * np.sin(np.linspace(0, np.pi, n_of(0.18))) ** 2)


# --- main -----------------------------------------------------------------------------------

JOBS = {
    "combat": combat_stems, "boss": boss_stems, "menu": menu, "map": node_map, "rest": rest,
    "stingers": stingers, "wall": amb_wall, "port": amb_port, "bore": amb_bore, "ambmap": amb_map,
    "spots": spots, "voices": voices, "ui": ui,
}

if __name__ == "__main__":
    names = sys.argv[1:] or list(JOBS)
    for name in names:
        print(name)
        JOBS[name]()

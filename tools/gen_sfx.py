#!/usr/bin/env python3
"""Synthesizes every sound effect in audio/ from code, so the game ships no third-party audio.

Run from the repo root: python3 tools/gen_sfx.py
Needs numpy. Output is 16-bit mono 44.1 kHz WAV. Re-running gives identical files (fixed seeds).
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
rng = np.random.default_rng(7)


def t(dur):
    return np.arange(int(dur * SR)) / SR


def noise(dur):
    return rng.uniform(-1, 1, int(dur * SR))


def env(n, attack=0.002, decay=0.2, curve=1.0):
    x = np.arange(n) / SR
    a = np.clip(x / max(attack, 1e-5), 0, 1)
    d = np.exp(-np.maximum(x - attack, 0) / max(decay, 1e-5)) ** curve
    return a * d


def lowpass(x, cutoff):
    # One-pole low-pass, cutoff in Hz (scalar or per-sample array).
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    a = 1 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bandpass(x, lo, hi):
    return highpass(lowpass(x, hi), lo)


def sine(freq, dur, phase=0.0):
    f = np.broadcast_to(np.asarray(freq, dtype=float), (int(dur * SR),))
    return np.sin(2 * np.pi * np.cumsum(f) / SR + phase)


def echo(x, delay, gain, taps=4):
    out = np.concatenate([x, np.zeros(int(delay * SR * taps))])
    for k in range(1, taps + 1):
        d = int(delay * SR * k)
        out[d:d + len(x)] += x * gain ** k
    return out


def reverb(x, size=0.6, mix=0.3):
    # Cheap tail: a few smeared, low-passed echoes.
    tail = np.zeros(len(x) + int(size * SR * 1.2))
    for k, (d, g) in enumerate([(0.031, 0.5), (0.047, 0.42), (0.073, 0.35), (0.11, 0.3), (0.17, 0.22), (0.26, 0.15)]):
        dd = int(d * size / 0.3 * SR)
        tail[dd:dd + len(x)] += lowpass(x, 2500 - k * 300) * g
    out = np.concatenate([x, np.zeros(len(tail) - len(x))])
    return out * (1 - mix) + tail * mix


def distort(x, drive):
    return np.tanh(x * drive) / np.tanh(drive)


def pad(x, dur):
    n = int(dur * SR)
    return np.concatenate([x, np.zeros(max(0, n - len(x)))])[:max(n, len(x))]


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def save(name, x, peak=0.89):
    x = np.asarray(x, dtype=float)
    fade = min(len(x), int(0.01 * SR))
    x[-fade:] *= np.linspace(1, 0, fade)
    m = np.max(np.abs(x))
    if m > 0:
        x = x / m * peak
    data = (x * 32767).astype("<i2").tobytes()
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print(f"{name}.wav  {len(x) / SR:.2f}s")


# --- weapons -----------------------------------------------------------------

def gunshot(crack_hi, body_freq, body_decay, tail, drive, length):
    n = noise(length)
    crack = highpass(n, crack_hi) * env(len(n), 0.0005, 0.018)
    body = lowpass(noise(length), 900) * env(len(n), 0.001, body_decay) * 1.6
    thump = sine(np.linspace(body_freq * 2.2, body_freq, len(n)), length) * env(len(n), 0.001, body_decay * 0.8) * 0.9
    shot = distort(crack * 0.9 + body + thump, drive)
    return reverb(shot, tail, 0.35)


def rifle():
    return gunshot(3000, 70, 0.05, 0.35, 3.0, 0.5)


def sniper():
    x = gunshot(2200, 55, 0.09, 0.8, 4.0, 0.9)
    return echo(x, 0.32, 0.35, 3)


def shotgun():
    return gunshot(1500, 48, 0.12, 0.5, 5.0, 0.8)


def enemy_spit():
    n = noise(0.6)
    sweep = np.linspace(1800, 300, len(n))
    wet = lowpass(n, sweep) * env(len(n), 0.01, 0.15)
    gurgle = sine(90 + 40 * np.sin(2 * np.pi * 23 * t(0.6)), 0.6) * env(len(n), 0.005, 0.12)
    return reverb(distort(wet * 2 + gurgle * 0.6, 2.0), 0.3, 0.25)


def claw():
    n = noise(0.45)
    whoosh = bandpass(n, 400, np.linspace(800, 4000, len(n))) * np.sin(np.linspace(0, np.pi, len(n))) ** 2 * 0.7
    slash = highpass(noise(0.45), 2500) * env(len(n), 0.001, 0.05)
    slash = np.concatenate([np.zeros(int(0.22 * SR)), slash])[:len(n)]
    return reverb(mix(whoosh, slash * 1.2), 0.25, 0.2)


def tracer_whiz():
    d = 0.5
    n = noise(d)
    f = np.linspace(5000, 900, len(n))
    w = bandpass(n, f * 0.6, f) * np.sin(np.linspace(0, np.pi, len(n))) ** 3
    return w


# --- impacts -----------------------------------------------------------------

def impact_flesh():
    n = noise(0.4)
    splat = lowpass(n, 1600) * env(len(n), 0.001, 0.06) * 1.5
    thud = sine(np.linspace(140, 50, len(n)), 0.4) * env(len(n), 0.001, 0.09)
    squish = bandpass(noise(0.4), 300, 1200) * env(len(n), 0.03, 0.08) * 0.6
    return reverb(distort(splat + thud + squish, 2.0), 0.2, 0.2)


def impact_armor():
    n = noise(0.6)
    clank = sum(sine(f, 0.6) * env(len(n), 0.0005, dec) * g for f, dec, g in [(1870, 0.08, 0.5), (2630, 0.05, 0.4), (3410, 0.04, 0.3)])
    thud = sine(np.linspace(160, 60, len(n)), 0.6) * env(len(n), 0.001, 0.07)
    grit = highpass(n, 2000) * env(len(n), 0.0005, 0.015)
    return reverb(clank + thud + grit, 0.25, 0.25)


def ricochet():
    d = 0.7
    hit = highpass(noise(d), 2500) * env(int(d * SR), 0.0005, 0.01)
    f = np.linspace(3200, 1400, int(d * SR)) * (1 + 0.04 * np.sin(2 * np.pi * 30 * t(d)))
    ping = sine(f, d) * env(int(d * SR), 0.01, 0.18) * 0.5
    return reverb(hit + ping, 0.3, 0.3)


def concrete_hit():
    n = noise(0.5)
    chip = bandpass(n, 800, 5000) * env(len(n), 0.0005, 0.03)
    debris = np.zeros(len(n))
    for k in range(7):
        s = int(rng.uniform(0.03, 0.3) * SR)
        g = highpass(noise(0.03), 2000) * env(int(0.03 * SR), 0.0005, 0.006) * rng.uniform(0.15, 0.4)
        debris[s:s + len(g)] += g[:len(debris) - s]
    return reverb(chip + debris, 0.25, 0.2)


# --- creatures ---------------------------------------------------------------

def screech(base, dur, rough=0.6, rise=1.3):
    x = t(dur)
    f = base * np.linspace(1.0, rise, len(x)) * (1 + 0.05 * np.sin(2 * np.pi * 7 * x))
    tone = sine(f, dur) + 0.5 * sine(f * 2.01, dur) + 0.3 * sine(f * 3.03, dur)
    grit = bandpass(noise(dur), base, base * 6) * rough
    e = np.sin(np.linspace(0, np.pi, len(x))) ** 0.6
    return reverb(distort((tone * 0.5 + grit) * e, 3.0), 0.4, 0.3)


def alert():
    return screech(620, 0.55, 0.7, 1.5)


def enemy_death():
    x = screech(380, 0.9, 0.8, 0.45)
    wet = lowpass(noise(0.9), 700) * env(int(0.9 * SR), 0.2, 0.3) * 0.6
    return mix(x, wet)


def soldier_death():
    thud = sine(np.linspace(110, 40, int(0.5 * SR)), 0.5) * env(int(0.5 * SR), 0.002, 0.12)
    gear = highpass(noise(0.5), 1500) * env(int(0.5 * SR), 0.001, 0.05) * 0.5
    radio = bandpass(noise(1.2), 900, 3000) * env(int(1.2 * SR), 0.05, 0.6) * 0.35
    radio *= (np.sin(2 * np.pi * 9 * t(1.2)) > -0.2)
    return mix(thud + gear, np.concatenate([np.zeros(int(0.25 * SR)), radio]))


def growl(dur=1.2):
    x = t(dur)
    f = 70 + 15 * np.sin(2 * np.pi * 3 * x)
    tone = sine(f, dur) + 0.6 * sine(f * 1.5, dur) + 0.4 * sine(f * 2.02, dur)
    am = 0.6 + 0.4 * np.sin(2 * np.pi * 17 * x)
    grit = lowpass(noise(dur), 600) * 0.8
    e = env(len(x), 0.15, dur * 0.5)
    return reverb(distort((tone * am + grit) * e, 4.0), 0.5, 0.35)


def turned():
    shimmer = infect_rise() * 0.6
    return mix(growl(1.6), shimmer)


# --- infection / powers ------------------------------------------------------

def infect_rise():
    d = 1.0
    x = t(d)
    out = np.zeros(len(x))
    for k, f0 in enumerate([523, 659, 784, 1046, 1318]):
        f = f0 * np.linspace(0.97, 1.03, len(x))
        out += sine(f, d) * env(len(x), 0.05 + k * 0.08, 0.35) * 0.3
    sparkle = highpass(noise(d), 6000) * np.sin(np.linspace(0, np.pi, len(x))) * 0.15
    return reverb(out + sparkle, 0.6, 0.45)


def mutation():
    d = 1.1
    x = t(d)
    wob = sine(110 * (1 + 0.5 * x) * (1 + 0.1 * np.sin(2 * np.pi * 11 * x)), d) * env(len(x), 0.05, 0.5)
    return reverb(distort(wob, 2.5) * 0.6 + infect_rise()[:len(x)] * 0.7, 0.6, 0.4)


def heal():
    d = 0.9
    hiss = bandpass(noise(0.35), 2000, 8000) * env(int(0.35 * SR), 0.005, 0.12) * 0.6
    chime = (sine(880, d) + 0.5 * sine(1320, d)) * env(int(d * SR), 0.005, 0.3) * 0.4
    return reverb(mix(hiss, np.concatenate([np.zeros(int(0.15 * SR)), chime])), 0.5, 0.35)


def lapse():
    g = growl(1.0)
    heart = np.zeros(int(1.0 * SR))
    for s in (0.0, 0.18, 0.55, 0.73):
        b = sine(55, 0.15) * env(int(0.15 * SR), 0.005, 0.04)
        i = int(s * SR)
        heart[i:i + len(b)] += b
    return mix(g * 0.7, heart * 1.2)


def breach():
    boom = gunshot(800, 40, 0.25, 0.9, 6.0, 1.2)
    debris = concrete_hit()
    return mix(boom, debris * 0.6)


# --- movement / UI -----------------------------------------------------------

def footstep(seed):
    r = np.random.default_rng(seed)
    d = 0.14
    n = r.uniform(-1, 1, int(d * SR))
    scuff = bandpass(n, 300 + seed * 40, 2600) * env(len(n), 0.002, 0.03)
    tick = sine(90 + seed * 10, d) * env(len(n), 0.001, 0.02) * 0.6
    return scuff + tick


def ui_click():
    d = 0.06
    return sine(1600, d) * env(int(d * SR), 0.0005, 0.012) + highpass(noise(d), 4000) * env(int(d * SR), 0.0002, 0.004) * 0.4


def ui_hover():
    d = 0.04
    return sine(2400, d) * env(int(d * SR), 0.0005, 0.006) * 0.5


def ui_confirm():
    d = 0.22
    a = sine(660, d) * env(int(d * SR), 0.002, 0.05)
    b = np.concatenate([np.zeros(int(0.06 * SR)), sine(990, d - 0.06) * env(int((d - 0.06) * SR), 0.002, 0.07)])
    return a + b


def ui_deny():
    d = 0.25
    return distort(sine(140, d) * env(int(d * SR), 0.002, 0.08) + sine(147, d) * env(int(d * SR), 0.002, 0.08), 2.0)


def radio_beep():
    d = 0.35
    static = bandpass(noise(0.08), 1000, 4000) * 0.4
    beep = sine(1250, 0.12) * 0.6
    return mix(static, np.concatenate([np.zeros(int(0.08 * SR)), beep, np.zeros(int(0.03 * SR)), sine(1250, 0.06) * 0.6]))


def sting_squad():
    d = 1.8
    x = t(d)
    chord = sum(sine(f, d) * g for f, g in [(98, 0.5), (147, 0.35), (196, 0.3), (294, 0.15)])
    brass = distort(chord, 1.8) * env(len(x), 0.06, 0.7)
    hit = lowpass(noise(d), 300) * env(len(x), 0.001, 0.15) * 0.6
    return reverb(brass + hit, 0.8, 0.4)


def sting_enemy():
    d = 2.2
    x = t(d)
    swell = sum(sine(f * np.linspace(1, 0.94, len(x)), d) * g for f, g in [(65, 0.5), (69, 0.4), (98, 0.3), (139, 0.2)])
    e = np.clip(x / 0.9, 0, 1) ** 2 * np.exp(-np.maximum(x - 0.9, 0) / 0.5)
    grit = bandpass(noise(d), 200, 1500) * e * 0.25
    return reverb(distort(swell * e, 2.2) + grit, 0.9, 0.4)


def cinematic_in():
    d = 0.6
    x = t(d)
    n = bandpass(noise(d), 300, np.linspace(600, 5000, len(x)))
    e = (x / d) ** 2.5
    low = sine(np.linspace(40, 80, len(x)), d) * e * 0.8
    return n * e + low


def victory():
    d = 2.6
    x = t(d)
    out = np.zeros(len(x))
    for k, f in enumerate([196, 247, 294, 392]):
        s = int(k * 0.18 * SR)
        n = len(x) - s
        out[s:] += distort(sine(f, n / SR) + 0.4 * sine(f * 2, n / SR), 1.5) * env(n, 0.02, 0.9) * 0.3
    return reverb(out, 0.9, 0.4)


def defeat():
    d = 3.0
    x = t(d)
    out = sum(sine(f * np.linspace(1, 0.9, len(x)), d) * g for f, g in [(110, 0.4), (131, 0.3), (165, 0.25)])
    return reverb(distort(out, 1.8) * env(len(x), 0.1, 1.2), 1.0, 0.45)


# --- ambience ----------------------------------------------------------------

def ambience():
    d = 24.0
    x = t(d)
    wind = lowpass(noise(d), 350 + 250 * (0.5 + 0.5 * np.sin(2 * np.pi * x / 8.0)))
    wind *= 0.6 + 0.4 * np.sin(2 * np.pi * x / 6.0 + 1.0)
    drone = (sine(55, d) * 0.25 + sine(82.5, d) * 0.12 + sine(55.4, d) * 0.2) * (0.7 + 0.3 * np.sin(2 * np.pi * x / 12.0))
    hum = sine(120, d) * 0.03 + sine(240, d) * 0.015   # floodlight mains hum
    out = wind * 1.4 + drone + hum
    # Distant rumbles and a far-off scream, placed so the loop point stays quiet.
    for s, kind in [(3.0, "rumble"), (9.5, "shot"), (14.0, "scream"), (19.0, "rumble")]:
        if kind == "rumble":
            ev = lowpass(noise(3.0), 120) * env(int(3.0 * SR), 0.6, 1.0) * 1.5
        elif kind == "shot":
            ev = lowpass(echo(rifle(), 0.21, 0.4, 3), 900) * 0.25
        else:
            ev = lowpass(screech(450, 1.2, 0.5, 0.7), 1500) * 0.12
        i = int(s * SR)
        ev = ev[:len(out) - i]
        out[i:i + len(ev)] += ev
    # Crossfade the end into the start so it loops without a click.
    xf = int(2.0 * SR)
    ramp = np.linspace(0, 1, xf)
    out[:xf] = out[:xf] * ramp + out[-xf:] * (1 - ramp)
    return out[:-xf]


SOUNDS = {
    "rifle": rifle, "sniper": sniper, "shotgun": shotgun, "spit": enemy_spit, "claw": claw,
    "whiz": tracer_whiz, "impact_flesh": impact_flesh, "impact_armor": impact_armor,
    "ricochet": ricochet, "concrete": concrete_hit, "alert": alert, "enemy_death": enemy_death,
    "soldier_death": soldier_death, "turned": turned, "infect": infect_rise, "mutation": mutation,
    "heal": heal, "lapse": lapse, "breach": breach, "ui_click": ui_click, "ui_hover": ui_hover,
    "ui_confirm": ui_confirm, "ui_deny": ui_deny, "radio": radio_beep, "sting_squad": sting_squad,
    "sting_enemy": sting_enemy, "cinematic": cinematic_in, "victory": victory, "defeat": defeat,
    "step1": lambda: footstep(1), "step2": lambda: footstep(2), "step3": lambda: footstep(3),
}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, fn in SOUNDS.items():
        save(name, fn())
    save("ambience", ambience(), 0.5)

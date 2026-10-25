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


def smg():
    # Light, snappy and high: a small calibre with a short room tail.
    return gunshot(3800, 95, 0.03, 0.22, 2.5, 0.32)


def lmg():
    # Heavier body and a grittier crack than the rifle; rounds overlap into a chug.
    x = gunshot(2600, 60, 0.07, 0.3, 4.0, 0.45)
    clank = sine(1400, 0.45) * env(int(0.45 * SR), 0.0005, 0.012) * 0.25
    return mix(x, clank)


def carbine():
    # Rifle-like with a wet, chemical hiss on top (Vector's bio-rounds).
    x = gunshot(3200, 80, 0.045, 0.28, 3.0, 0.42)
    hiss = bandpass(noise(0.42), 3000, 9000) * env(int(0.42 * SR), 0.004, 0.07) * 0.35
    return mix(x, hiss)


def pistol():
    # Reaper's sidearm: a small, dry pop with a quick slide clack.
    x = gunshot(3500, 110, 0.025, 0.2, 2.2, 0.3)
    return mix(x, pad(np.concatenate([np.zeros(int(0.05 * SR)), mech_click(1600, 0.008) * 0.35]), 0.3))


def revolver():
    # Warden's heavy revolver: a deep, booming single round with a long ring.
    x = gunshot(2000, 52, 0.11, 0.6, 4.5, 0.85)
    ring = sine(np.linspace(260, 200, int(0.85 * SR)), 0.85) * env(int(0.85 * SR), 0.001, 0.12) * 0.25
    return mix(x, ring)


def gun_tail(cutoff, dur, gain):
    # The shot echoing back off the colony's buildings: a dark, slapback rumble.
    n = lowpass(noise(dur), cutoff) * env(int(dur * SR), 0.02, dur * 0.35) * gain
    slap = np.concatenate([np.zeros(int(0.09 * SR)), lowpass(noise(0.12), cutoff * 1.6) * env(int(0.12 * SR), 0.002, 0.04)])
    return echo(mix(n, slap * 0.8), 0.17, 0.45, 4)


def tail_rifle():
    return gun_tail(900, 0.9, 1.0)


def tail_heavy():
    return gun_tail(600, 1.4, 1.2)


def mech_click(f, dec):
    n = int(0.04 * SR)
    return highpass(noise(0.04), 2500) * env(n, 0.0003, dec) + sine(f, 0.04) * env(n, 0.0003, dec * 1.5) * 0.6


def pump():
    # Shotgun slide back and forward.
    back = mix(bandpass(noise(0.08), 400, 2500) * env(int(0.08 * SR), 0.005, 0.03) * 0.6, mech_click(900, 0.01))
    fwd = mix(bandpass(noise(0.08), 500, 3000) * env(int(0.08 * SR), 0.003, 0.025) * 0.7, mech_click(1300, 0.012))
    out = np.zeros(int(0.32 * SR))
    out[:len(back)] += back
    i = int(0.16 * SR)
    out[i:i + len(fwd)] += fwd
    return reverb(out, 0.15, 0.15)


def bolt():
    # Bolt lifted, drawn, the casing pings off, bolt home.
    out = np.zeros(int(0.6 * SR))
    for st, f, d in [(0.0, 1100, 0.01), (0.09, 800, 0.02), (0.3, 1500, 0.012), (0.36, 1000, 0.01)]:
        c = mech_click(f, d)
        i = int(st * SR)
        out[i:i + len(c)] += c
    ping = sine(4200, 0.25) * env(int(0.25 * SR), 0.001, 0.06) * 0.15
    i = int(0.18 * SR)
    out[i:i + len(ping)] += ping
    return reverb(out, 0.15, 0.15)


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


def blade():
    # Reaper's machete: a fast rising swish, then a wet cut and the saw teeth catching.
    d = 0.6
    n = noise(d)
    k = int(0.2 * SR)
    sw = np.zeros(len(n))
    sw[:k] = bandpass(noise(0.2), 600, np.linspace(1500, 7000, k)) * np.sin(np.linspace(0, np.pi, k)) ** 2
    cut_len = len(n) - k
    cut = lowpass(noise(d - 0.2), 2200) * env(cut_len, 0.001, 0.07) * 1.3
    cut += bandpass(noise(d - 0.2), 250, 900) * env(cut_len, 0.01, 0.12) * 0.8
    rasp = highpass(noise(d - 0.2), 3000) * env(cut_len, 0.001, 0.03) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 70 * t(d - 0.2))))
    hit = np.zeros(len(n))
    hit[k:] = distort(cut + rasp * 0.5, 2.0)
    return reverb(mix(sw * 0.9, hit), 0.22, 0.2)


def bash():
    # Warden's shield bash: a heavy, hollow thud and the maul's electric crackle.
    d = 0.7
    n = int(d * SR)
    thud = sine(np.linspace(110, 38, n), d) * env(n, 0.001, 0.12) * 1.4
    slab = lowpass(noise(d), 700) * env(n, 0.001, 0.07) * 1.2
    clank = sum(sine(f, d) * env(n, 0.0005, dec) * g for f, dec, g in [(420, 0.09, 0.35), (780, 0.06, 0.25)])
    crackle = highpass(noise(d), 2500) * (rng.uniform(0, 1, n) > 0.985) * 3.0
    crackle = lowpass(crackle, 9000) * env(n, 0.03, 0.18)
    buzz = np.sign(sine(120, d)) * env(n, 0.02, 0.15) * 0.18
    return reverb(distort(thud + slab + clank, 2.5) + crackle + buzz, 0.3, 0.25)


def tracer_whiz():
    d = 0.5
    n = noise(d)
    f = np.linspace(5000, 900, len(n))
    w = bandpass(n, f * 0.6, f) * np.sin(np.linspace(0, np.pi, len(n))) ** 3
    return w


# --- alternate guns: each gets its own report -----------------------------------

def battle_rifle():
    # Full-power rifle round: deeper thump and a harder crack than the assault rifle.
    x = gunshot(2600, 58, 0.07, 0.45, 3.8, 0.6)
    slap = lowpass(noise(0.6), 220) * env(int(0.6 * SR), 0.001, 0.08) * 0.8
    return mix(x, slap)


def burst_carbine():
    # Tight, high and quick: a light round with a metallic snap from the short barrel.
    x = gunshot(4200, 105, 0.028, 0.22, 2.6, 0.3)
    snap = sine(2900, 0.3) * env(int(0.3 * SR), 0.0004, 0.01) * 0.3
    return mix(x, snap)


def anti_materiel():
    # The biggest gun in the colony: a sub-bass blast, the muzzle brake's side bark, a long roll.
    x = gunshot(1800, 42, 0.16, 1.1, 5.5, 1.4)
    sub = sine(np.linspace(80, 28, int(1.4 * SR)), 1.4) * env(int(1.4 * SR), 0.001, 0.22) * 1.2
    brake = bandpass(noise(1.4), 600, 3500) * env(int(1.4 * SR), 0.002, 0.04) * 0.9
    return echo(mix(x, sub, brake), 0.38, 0.4, 4)


def scout_carbine():
    # Light and suppressed-ish: a dry, clipped pop with almost no tail.
    n = noise(0.25)
    pop = bandpass(n, 900, 6000) * env(len(n), 0.0005, 0.02)
    thump = sine(np.linspace(260, 110, len(n)), 0.25) * env(len(n), 0.001, 0.025) * 0.7
    return reverb(distort(pop + thump, 2.2), 0.15, 0.2)


def flechette_smg():
    # Needles, not bullets: a zippy rasp with a ringing metallic edge.
    x = gunshot(5000, 130, 0.02, 0.18, 2.2, 0.26)
    zip_ = bandpass(noise(0.26), np.linspace(9000, 3000, int(0.26 * SR)), 12000) * env(int(0.26 * SR), 0.0005, 0.03) * 0.6
    ring = sine(np.linspace(5200, 4400, int(0.26 * SR)), 0.26) * env(int(0.26 * SR), 0.0005, 0.04) * 0.18
    return mix(x, zip_, ring)


def dart_rifle():
    # Pneumatic: a hollow thunk, a puff of gas and a soft hiss. No gunpowder crack at all.
    n = noise(0.5)
    thunk = sine(np.linspace(320, 140, len(n)), 0.5) * env(len(n), 0.001, 0.035)
    puff = bandpass(n, 400, 2500) * env(len(n), 0.002, 0.03) * 0.8
    hiss = bandpass(noise(0.5), 4000, 10000) * env(len(n), 0.01, 0.12) * 0.35
    return reverb(thunk + puff + hiss, 0.18, 0.2)


def slug_gun():
    # One solid lump of lead: a round, deep thump instead of the shotgun's ragged roar.
    x = gunshot(1200, 44, 0.14, 0.55, 4.0, 0.85)
    boom = sine(np.linspace(110, 40, int(0.85 * SR)), 0.85) * env(int(0.85 * SR), 0.001, 0.13) * 1.1
    return mix(x, boom)


def auto_shotgun():
    # Punchier and shorter than the pump guns, so three of them can stack into a stutter.
    x = gunshot(1700, 55, 0.07, 0.3, 5.0, 0.5)
    rattle = bandpass(noise(0.5), 1500, 5000) * env(int(0.5 * SR), 0.01, 0.03) * 0.25
    return mix(x, rattle)


def pump_shotgun():
    # A big, boomy hunting gun: long body and a ragged pellet roar.
    x = gunshot(1300, 45, 0.15, 0.65, 5.5, 0.95)
    roar = lowpass(noise(0.95), 1800) * env(int(0.95 * SR), 0.003, 0.06) * 0.9
    return mix(x, roar)


def heavy_mg():
    # Slow, heavy pounding: deep body and a mechanical clunk of the bolt on every round.
    x = gunshot(2200, 46, 0.1, 0.35, 4.8, 0.55)
    clunk = sine(620, 0.55) * env(int(0.55 * SR), 0.0005, 0.02) * 0.35
    return mix(x, clunk, lowpass(noise(0.55), 160) * env(int(0.55 * SR), 0.001, 0.06) * 0.7)


def spore_rifle():
    # Organic: a wet, squelching thump and a bubbling, gurgling discharge.
    n = noise(0.7)
    thump = sine(np.linspace(150, 55, len(n)), 0.7) * env(len(n), 0.002, 0.07)
    squelch = lowpass(n, np.linspace(2600, 400, len(n))) * env(len(n), 0.003, 0.06) * 1.3
    bub = sine(180 + 90 * np.sin(2 * np.pi * 31 * t(0.7)), 0.7) * env(len(n), 0.03, 0.15) * 0.35
    return reverb(distort(thump + squelch + bub, 2.4), 0.35, 0.3)


# --- melee classes' alternate pistols -----------------------------------------

def machine_pistol():
    # A tiny, buzzing automatic: thin pop with a high mechanical chatter.
    x = gunshot(4500, 120, 0.02, 0.16, 2.3, 0.24)
    chatter = mech_click(2600, 0.005) * 0.3
    return mix(x, pad(np.concatenate([np.zeros(int(0.03 * SR)), chatter]), 0.24))


def bloom_pistol():
    # The pistol grown through with Bloom: a wet pop and a short fizz.
    n = noise(0.45)
    pop = lowpass(n, np.linspace(3200, 600, len(n))) * env(len(n), 0.001, 0.035) * 1.3
    thump = sine(np.linspace(220, 80, len(n)), 0.45) * env(len(n), 0.001, 0.05) * 0.8
    fizz = bandpass(noise(0.45), 3500, 9000) * env(len(n), 0.02, 0.09) * 0.4
    return reverb(distort(pop + thump, 2.0) + fizz, 0.25, 0.25)


def hand_cannon():
    # A handgun that kicks like a rifle: a sharp, ringing boom.
    x = gunshot(2300, 50, 0.1, 0.55, 5.0, 0.8)
    ring = sine(np.linspace(340, 280, int(0.8 * SR)), 0.8) * env(int(0.8 * SR), 0.001, 0.09) * 0.3
    return mix(x, ring)


def stun_pistol():
    # No powder: a capacitor whine snapping into an electric crack and buzz.
    d = 0.5
    whine = sine(np.linspace(2500, 5200, int(0.06 * SR)), 0.06) * np.linspace(0, 0.4, int(0.06 * SR))
    crack = highpass(noise(d), 2000) * env(int(d * SR), 0.0005, 0.02) * 1.2
    buzz = np.sign(sine(120, d)) * bandpass(noise(d), 400, 4000) * env(int(d * SR), 0.002, 0.08) * 0.6
    return reverb(np.concatenate([whine, crack + buzz]), 0.2, 0.2)


def longslide():
    # A long-barrelled match pistol: clean, crisp, with a tighter tail than the rifle.
    x = gunshot(3300, 85, 0.035, 0.3, 2.8, 0.42)
    return mix(x, pad(np.concatenate([np.zeros(int(0.06 * SR)), mech_click(1500, 0.008) * 0.3]), 0.42))


def whiz_zap():
    # An electric slug crackling past.
    d = 0.4
    n = noise(d)
    crackle = highpass(n, 2500) * (rng.uniform(0, 1, len(n)) > 0.92) * 1.0
    hum = sine(np.linspace(900, 500, len(n)), d) * 0.3
    return (crackle + hum) * np.sin(np.linspace(0, np.pi, len(n))) ** 2


def impact_shock():
    # An electric hit: a hard snap and a crackling discharge.
    d = 0.6
    snap = highpass(noise(d), 1500) * env(int(d * SR), 0.0005, 0.015) * 1.2
    crackle = highpass(noise(d), 3000) * (rng.uniform(0, 1, int(d * SR)) > 0.9) * env(int(d * SR), 0.01, 0.15)
    buzz = np.sign(sine(100, d)) * env(int(d * SR), 0.002, 0.1) * 0.25
    return reverb(snap + crackle + buzz, 0.2, 0.2)


# --- gun mechanisms and round sounds -------------------------------------------

def belt():
    # LMG belt and links rattling through the feed after a burst.
    out = np.zeros(int(0.45 * SR))
    for k in range(9):
        st = int((0.02 + k * 0.035 + rng.uniform(-0.006, 0.006)) * SR)
        c = mech_click(rng.uniform(1800, 3200), 0.006) * rng.uniform(0.3, 0.6)
        out[st:st + len(c)] += c[:len(out) - st]
    return reverb(out, 0.12, 0.15)


def vent():
    # Bio guns venting their chamber: a wet hiss of spore gas.
    n = noise(0.5)
    h = bandpass(n, 2500, 8000) * env(len(n), 0.03, 0.14)
    gl = sine(120 + 60 * np.sin(2 * np.pi * 17 * t(0.5)), 0.5) * env(len(n), 0.05, 0.1) * 0.25
    return h * 0.8 + gl


def cylinder():
    # Revolver hammer cocked and the cylinder clicking round.
    out = np.zeros(int(0.35 * SR))
    for st, f, d in [(0.0, 1900, 0.006), (0.12, 1300, 0.012), (0.17, 2400, 0.005)]:
        c = mech_click(f, d)
        i = int(st * SR)
        out[i:i + len(c)] += c
    return reverb(out, 0.12, 0.15)


def bolt_heavy():
    # Anti-materiel bolt: slow, weighty, and a fat casing clangs off the floor.
    out = np.zeros(int(0.85 * SR))
    for st, f, d in [(0.0, 700, 0.02), (0.14, 500, 0.03), (0.46, 900, 0.02), (0.54, 650, 0.015)]:
        c = mech_click(f, d) * 1.2
        i = int(st * SR)
        out[i:i + len(c)] += c
    clang = sum(sine(f, 0.35) * env(int(0.35 * SR), 0.0005, 0.07) * g for f, g in [(1800, 0.25), (2700, 0.15)])
    i = int(0.3 * SR)
    out[i:i + len(clang)] += clang
    return reverb(out, 0.18, 0.2)


def whiz_pellets():
    # A swarm of pellets: a crackling buzz rather than one clean whistle.
    d = 0.35
    n = noise(d)
    w = bandpass(n, 1500, 6000) * np.sin(np.linspace(0, np.pi, len(n))) ** 2
    crackle = np.zeros(len(n))
    for k in range(14):
        s = int(rng.uniform(0.02, 0.3) * SR)
        g = highpass(noise(0.01), 3000) * env(int(0.01 * SR), 0.0002, 0.002) * rng.uniform(0.4, 0.9)
        crackle[s:s + len(g)] += g[:len(crackle) - s]
    return w * 0.6 + crackle


def whiz_heavy():
    # A big round going past: a supersonic crack and a deep tearing whoosh.
    d = 0.6
    n = noise(d)
    crack = highpass(n, 3000) * env(len(n), 0.0003, 0.008)
    tear = bandpass(noise(d), np.linspace(2200, 300, len(n)), np.linspace(4500, 900, len(n))) * np.sin(np.linspace(0, np.pi, len(n))) ** 2
    return crack * 0.8 + tear


def whiz_bio():
    # Bio rounds wobble through the air: a wet, warbling flutter.
    d = 0.5
    f = 700 + 300 * np.sin(2 * np.pi * 14 * t(d))
    w = sine(f, d) * np.sin(np.linspace(0, np.pi, int(d * SR))) ** 2 * 0.5
    fl = bandpass(noise(d), 600, 2500) * (0.5 + 0.5 * np.sin(2 * np.pi * 22 * t(d))) * np.sin(np.linspace(0, np.pi, int(d * SR)))
    return w + fl * 0.6


def whiz_dart():
    # A fletched dart: a thin, falling whistle.
    d = 0.45
    f = np.linspace(3800, 2600, int(d * SR))
    return sine(f, d) * np.sin(np.linspace(0, np.pi, int(d * SR))) ** 3 * 0.6 + bandpass(noise(d), 5000, 9000) * 0.1


def whiz_needle():
    # Flechettes: a hiss of thin metal slicing the air.
    d = 0.3
    n = noise(d)
    return bandpass(n, np.linspace(9000, 5000, len(n)), 14000) * np.sin(np.linspace(0, np.pi, len(n))) ** 2


def impact_bio():
    # A bio round bursting: a splash and a sizzle as the culture eats into the surface.
    n = noise(0.8)
    splat = lowpass(n, 1400) * env(len(n), 0.001, 0.05) * 1.3
    sizzle = bandpass(noise(0.8), 3000, 9000) * env(len(n), 0.04, 0.25) * 0.5
    pop = sine(np.linspace(300, 90, len(n)), 0.8) * env(len(n), 0.001, 0.04) * 0.6
    return reverb(splat + sizzle + pop, 0.2, 0.2)


def impact_slug():
    # A slug landing: a heavy, chunky smack that knocks debris loose.
    n = noise(0.7)
    smack = lowpass(n, 2200) * env(len(n), 0.0005, 0.04) * 1.4
    thud = sine(np.linspace(120, 38, len(n)), 0.7) * env(len(n), 0.001, 0.12) * 1.2
    debris = np.zeros(len(n))
    for k in range(10):
        s = int(rng.uniform(0.05, 0.45) * SR)
        g = bandpass(noise(0.04), 800, 4000) * env(int(0.04 * SR), 0.0005, 0.01) * rng.uniform(0.2, 0.5)
        debris[s:s + len(g)] += g[:len(debris) - s]
    return reverb(distort(smack + thud, 2.0) + debris, 0.3, 0.25)


def impact_pellets():
    # A spread landing: a quick spatter of small hits.
    out = np.zeros(int(0.4 * SR))
    for k in range(9):
        s = int(rng.uniform(0.0, 0.07) * SR)
        g = bandpass(noise(0.05), 700, 5000) * env(int(0.05 * SR), 0.0005, 0.012) * rng.uniform(0.4, 1.0)
        out[s:s + len(g)] += g
    return reverb(out, 0.2, 0.2)


def impact_dart():
    # A dart sticking in: a hard thock and a little twang of the shaft.
    n = noise(0.35)
    thock = bandpass(n, 500, 3000) * env(len(n), 0.0005, 0.015)
    twang = sine(np.linspace(520, 480, len(n)) * (1 + 0.03 * np.sin(2 * np.pi * 28 * t(0.35))), 0.35) * env(len(n), 0.002, 0.08) * 0.4
    return reverb(thock + twang, 0.15, 0.15)


def brass():
    # Spent brass tinkling on the floor.
    out = np.zeros(int(0.4 * SR))
    for st, g in [(0.0, 1.0), (0.09, 0.5), (0.15, 0.3)]:
        c = sum(sine(f, 0.12) * env(int(0.12 * SR), 0.0003, 0.02) for f in (5200, 7400)) * g
        i = int(st * SR)
        out[i:i + len(c)] += c
    return out


def shell_drop():
    # A plastic shotgun hull bouncing: duller and lower than brass.
    out = np.zeros(int(0.4 * SR))
    for st, g in [(0.0, 1.0), (0.12, 0.45)]:
        c = mix(bandpass(noise(0.06), 600, 2500) * env(int(0.06 * SR), 0.0005, 0.012), sine(1300, 0.06) * env(int(0.06 * SR), 0.0005, 0.015) * 0.4) * g
        i = int(st * SR)
        out[i:i + len(c)] += c
    return out


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


def explosion():
    """A blast: sharp crack, a deep chest thump that rolls, and debris raining back down."""
    n = noise(2.6)
    crack = highpass(n[:int(0.08 * SR)], 1500) * env(int(0.08 * SR), 0.0005, 0.02)
    thump = sine(46, 2.6) * env(len(n), 0.004, 0.45) + sine(31, 2.6) * env(len(n), 0.01, 0.8) * 0.7
    roar = lowpass(n, 700) * env(len(n), 0.006, 0.6) * 1.2
    boom = distort(mix(pad(crack, 2.6) * 0.9, thump * 1.3, roar), 2.5)
    debris = np.zeros(len(n))
    for k in range(18):
        s0 = int(rng.uniform(0.25, 2.0) * SR)
        g = highpass(noise(0.04), 1800) * env(int(0.04 * SR), 0.0005, 0.008) * rng.uniform(0.05, 0.22)
        debris[s0:s0 + len(g)] += g[:len(debris) - s0]
    return reverb(mix(boom, debris), 0.7, 0.3)


def collapse():
    """A wall or roof coming down: a heavy crunch and a slide of rubble."""
    n = noise(1.6)
    crunch = bandpass(n, 120, 1800) * env(len(n), 0.003, 0.25)
    body = sine(58, 1.6) * env(len(n), 0.005, 0.3) * 0.8
    slide = bandpass(n, 400, 3500) * env(len(n), 0.15, 0.5) * 0.35
    rubble = np.zeros(len(n))
    for k in range(14):
        s0 = int(rng.uniform(0.1, 1.3) * SR)
        g = bandpass(noise(0.05), 600, 5000) * env(int(0.05 * SR), 0.0005, 0.012) * rng.uniform(0.1, 0.35)
        rubble[s0:s0 + len(g)] += g[:len(rubble) - s0]
    return reverb(mix(crunch, body, slide, rubble), 0.45, 0.25)


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


def _blip(freq, dur, decay, glide=0.0):
    x = t(dur)
    f = freq * (1 + glide * np.exp(-x / 0.02))
    tone = sine(f, dur) + sine(f * 2.0, dur) * 0.18
    return tone * env(len(x), 0.002, decay)


def ping():
    """Co-op ping: a bright two-note sonar chirp with a short tail."""
    a = _blip(1320, 0.5, 0.12, 0.08)
    b = np.concatenate([np.zeros(int(0.07 * SR)), _blip(1980, 0.43, 0.16)]) * 0.8
    return echo(a + b, 0.09, 0.25, 3)


def ping_attack():
    """Attack ping: the chirp, falling, over a low pulse."""
    a = _blip(1660, 0.45, 0.09, -0.12)
    b = np.concatenate([np.zeros(int(0.06 * SR)), _blip(1110, 0.39, 0.12)]) * 0.9
    low = sine(220, 0.2) * env(int(0.2 * SR), 0.003, 0.05) * 0.5
    return echo(mix(a + b, low), 0.08, 0.22, 3)


def ping_danger():
    """Danger ping: two quick low warning pips, dissonant on purpose."""
    pip = lambda: (sine(740, 0.13) + sine(784, 0.13) * 0.7) * env(int(0.13 * SR), 0.002, 0.05)
    gap = np.zeros(int(0.05 * SR))
    return echo(np.concatenate([pip(), gap, pip(), np.zeros(int(0.15 * SR))]), 0.07, 0.2, 2)


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


# --- gadgets and pocket items ----------------------------------------------------

def smoke_hiss():
    """Smoke grenade: the pin and spoon, a thud, then a long pressurised hiss that thins out."""
    d = 2.2
    n = noise(d)
    pop = bandpass(noise(0.05), 800, 4000) * env(int(0.05 * SR), 0.0005, 0.01) * 0.6
    thud = sine(90, 0.2) * env(int(0.2 * SR), 0.002, 0.05) * 0.8
    hiss = bandpass(n, 1500, 9000) * env(len(n), 0.08, 0.9) * 0.7
    swell = lowpass(n, 600) * env(len(n), 0.2, 0.8) * 0.5
    return mix(pop, np.concatenate([np.zeros(int(0.12 * SR)), thud]), np.concatenate([np.zeros(int(0.16 * SR)), hiss + swell]))


def flashbang():
    """Flashbang: a hard flat bang and a high whine left ringing in the ears."""
    d = 1.8
    n = noise(d)
    bang = distort(highpass(n, 400) * env(len(n), 0.0003, 0.05) * 2.0 + sine(70, d) * env(len(n), 0.001, 0.1), 4.0)
    ring = sine(3900, d) * env(len(n), 0.05, 0.9) * 0.18 + sine(4100, d) * env(len(n), 0.05, 0.7) * 0.1
    return reverb(bang + ring, 0.5, 0.3)


def gadget_deploy():
    """A gadget unfolding: ratchet clicks, a servo whirr and a locking clunk."""
    d = 0.9
    out = np.zeros(int(d * SR))
    for k in range(5):
        c = bandpass(noise(0.015), 2000, 7000) * env(int(0.015 * SR), 0.0003, 0.004) * 0.5
        i = int((0.02 + k * 0.05) * SR)
        out[i:i + len(c)] += c
    x = t(0.35)
    whirr = sine(220 + 500 * x / 0.35, 0.35) * env(len(x), 0.02, 0.3) * 0.25
    i = int(0.28 * SR)
    out[i:i + len(whirr)] += whirr
    clunk = (sine(110, 0.2) + bandpass(noise(0.2), 200, 1500)) * env(int(0.2 * SR), 0.001, 0.05) * 0.8
    i = int(0.62 * SR)
    out[i:i + len(clunk)] += clunk[:len(out) - i]
    return reverb(out, 0.3, 0.2)


def foam_spray():
    """Containment foam: a wet pressurised spray that sets with a crackle."""
    d = 1.3
    n = noise(d)
    spray = bandpass(n, 300, 3000) * env(len(n), 0.03, 0.5) * (1 + 0.3 * np.sin(2 * np.pi * 23 * t(d)))
    crackle = np.zeros(len(n))
    for k in range(30):
        i = int(rng.uniform(0.4, 1.2) * SR)
        g = highpass(noise(0.006), 3000) * rng.uniform(0.05, 0.2)
        crackle[i:i + len(g)] += g[:len(crackle) - i]
    return mix(spray * 0.8, crackle)


def drone():
    """Recon drone: rotors spin up and buzz off into the air."""
    d = 1.6
    x = t(d)
    f = 90 + 140 * np.clip(x / 0.5, 0, 1)
    buzz = distort(sine(f, d) + 0.6 * sine(f * 2.01, d), 2.0) * np.sin(np.linspace(0, np.pi, len(x))) ** 0.6
    whine = sine(f * 8, d) * 0.08 * env(len(x), 0.3, 0.8)
    return lowpass(buzz * 0.5 + whine, 3000) + bandpass(noise(d), 1000, 5000) * 0.05


def grapple():
    """Grapple: the hook fires, the line zips taut and the soldier slams into the landing."""
    d = 0.9
    shot = gunshot(2500, 120, 0.02, 0.15, 2.0, 0.2) * 0.5
    x = t(0.45)
    zip_ = bandpass(noise(0.45), 1500, 6000) * (0.5 + 0.5 * np.sin(2 * np.pi * (40 + 120 * x) * x)) * env(len(x), 0.01, 0.3)
    land = (sine(80, 0.25) + bandpass(noise(0.25), 150, 1200)) * env(int(0.25 * SR), 0.001, 0.06)
    return mix(shot, np.concatenate([np.zeros(int(0.1 * SR)), zip_ * 0.6]), np.concatenate([np.zeros(int(0.6 * SR)), land]))


def flare_pop():
    """Flare: a hollow launcher pop, then the magnesium fizz of the flare burning."""
    d = 1.6
    pop = (sine(np.linspace(300, 120, int(0.12 * SR)), 0.12) + lowpass(noise(0.12), 1200)) * env(int(0.12 * SR), 0.001, 0.03)
    fizz = bandpass(noise(1.3), 2500, 9000) * env(int(1.3 * SR), 0.1, 0.7) * 0.45 * (1 + 0.4 * np.sin(2 * np.pi * 17 * t(1.3)))
    return reverb(mix(pop, np.concatenate([np.zeros(int(0.25 * SR)), fizz])), 0.4, 0.25)


def emitter_hum():
    """Containment emitter: a field spinning up, a clean hum chord with a slow shimmer."""
    d = 1.5
    x = t(d)
    rise = np.clip(x / 0.4, 0, 1)
    tone = (sine(196 * (0.8 + 0.2 * rise), d) + 0.6 * sine(294 * (0.8 + 0.2 * rise), d) + 0.3 * sine(392, d))
    shimmer = 1 + 0.25 * np.sin(2 * np.pi * 6 * x)
    return reverb(tone * shimmer * env(len(x), 0.2, 0.6) * 0.5, 0.6, 0.4)


def order_call():
    """Squad order / talk down: a clipped radio chirp and a short two-note call."""
    return mix(radio_beep(), np.concatenate([np.zeros(int(0.12 * SR)), _blip(660, 0.3, 0.1) * 0.5, _blip(880, 0.3, 0.12) * 0.5]))


SOUNDS = {
    "rifle": rifle, "sniper": sniper, "shotgun": shotgun, "spit": enemy_spit, "claw": claw,
    "whiz": tracer_whiz, "impact_flesh": impact_flesh, "impact_armor": impact_armor,
    "ricochet": ricochet, "concrete": concrete_hit, "alert": alert, "enemy_death": enemy_death,
    "soldier_death": soldier_death, "turned": turned, "infect": infect_rise, "mutation": mutation,
    "heal": heal, "lapse": lapse, "breach": breach, "ui_click": ui_click, "ui_hover": ui_hover,
    "ui_confirm": ui_confirm, "ui_deny": ui_deny, "radio": radio_beep, "sting_squad": sting_squad,
    "sting_enemy": sting_enemy, "cinematic": cinematic_in, "victory": victory, "defeat": defeat,
    "step1": lambda: footstep(1), "step2": lambda: footstep(2), "step3": lambda: footstep(3),
    "smg": smg, "lmg": lmg, "carbine": carbine, "tail_rifle": tail_rifle, "tail_heavy": tail_heavy,
    "pump": pump, "bolt": bolt, "pistol": pistol, "revolver": revolver, "blade": blade, "bash": bash,
    "battle_rifle": battle_rifle, "burst_carbine": burst_carbine, "anti_materiel": anti_materiel,
    "scout_carbine": scout_carbine, "flechette_smg": flechette_smg, "dart_rifle": dart_rifle,
    "slug_gun": slug_gun, "auto_shotgun": auto_shotgun, "pump_shotgun": pump_shotgun, "heavy_mg": heavy_mg,
    "spore_rifle": spore_rifle, "belt": belt, "vent": vent, "cylinder": cylinder, "bolt_heavy": bolt_heavy,
    "whiz_pellets": whiz_pellets, "whiz_heavy": whiz_heavy, "whiz_bio": whiz_bio, "whiz_dart": whiz_dart,
    "whiz_needle": whiz_needle, "impact_bio": impact_bio, "impact_slug": impact_slug,
    "impact_pellets": impact_pellets, "impact_dart": impact_dart, "brass": brass, "shell_drop": shell_drop,
    "machine_pistol": machine_pistol, "bloom_pistol": bloom_pistol, "hand_cannon": hand_cannon,
    "stun_pistol": stun_pistol, "longslide": longslide, "whiz_zap": whiz_zap, "impact_shock": impact_shock,
    "explosion": explosion, "collapse": collapse,
    "ping": ping, "ping_attack": ping_attack, "ping_danger": ping_danger,
    "smoke_hiss": smoke_hiss, "flashbang": flashbang, "gadget_deploy": gadget_deploy, "foam_spray": foam_spray,
    "drone": drone, "grapple": grapple, "flare_pop": flare_pop, "emitter_hum": emitter_hum, "order_call": order_call,
}

if __name__ == "__main__":
    # `python3 tools/gen_sfx.py smg pump` regenerates just those (each sound reseeds the
    # noise from its name, so a partial run matches a full one).
    import sys
    import zlib
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[1:])
    for name, fn in SOUNDS.items():
        if not only or name in only:
            rng = np.random.default_rng(zlib.crc32(name.encode()))
            save(name, fn())
    if not only or "ambience" in only:
        rng = np.random.default_rng(zlib.crc32(b"ambience"))
        save("ambience", ambience(), 0.5)

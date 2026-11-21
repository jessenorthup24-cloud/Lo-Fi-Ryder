#!/usr/bin/env python3
"""Synthesizes all of Lo-Fi Ryder's audio: lo-fi acoustic music tracks and toy-like sound effects.

    python3 tools/audio/make_audio.py            # writes assets/audio/music/*.ogg and assets/audio/sfx/*.wav

Everything is generated from code (plucked strings, FM keys, noise drums), so there are no
third-party audio files and no licensing to track.
"""
import os
import subprocess
import sys
import wave

import numpy as np
from scipy import signal

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MUSIC = os.path.join(ROOT, "assets", "audio", "music")
SFX = os.path.join(ROOT, "assets", "audio", "sfx")
rng = np.random.default_rng(1234)


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


# ----------------------------------------------------------------- filters

def biquad(kind, f, q=0.707, gain_db=0.0):
    w = 2 * np.pi * f / SR
    a = 10 ** (gain_db / 40)
    al = np.sin(w) / (2 * q)
    c = np.cos(w)
    if kind == "lp":
        b = [(1 - c) / 2, 1 - c, (1 - c) / 2]; aa = [1 + al, -2 * c, 1 - al]
    elif kind == "hp":
        b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]; aa = [1 + al, -2 * c, 1 - al]
    elif kind == "bp":
        b = [al, 0, -al]; aa = [1 + al, -2 * c, 1 - al]
    elif kind == "peak":
        b = [1 + al * a, -2 * c, 1 - al * a]; aa = [1 + al / a, -2 * c, 1 - al / a]
    else:
        raise ValueError(kind)
    return np.array(b) / aa[0], np.array(aa) / aa[0]


def filt(x, kind, f, q=0.707, gain_db=0.0):
    b, a = biquad(kind, f, q, gain_db)
    return signal.lfilter(b, a, x, axis=0)


def reverb(x, mix=0.25, size=1.0, damp=0.4):
    """Small Freeverb-style reverb (parallel combs + series allpasses)."""
    out = np.zeros_like(x)
    for d in [1557, 1617, 1491, 1422, 1277, 1356]:
        d = int(d * size)
        g = 0.78
        a = np.zeros(d + 1); a[0] = 1; a[d] = -g
        y = signal.lfilter([1.0], a, x)
        out += filt(y, "lp", 6000 * (1 - damp) + 800)
    out /= 6
    for d in [556, 441, 341, 225]:
        g = 0.5
        b = np.zeros(d + 1); b[0] = -g; b[d] = 1
        a = np.zeros(d + 1); a[0] = 1; a[d] = -g
        out = signal.lfilter(b, a, out)
    return x * (1 - mix) + out * mix


# ----------------------------------------------------------------- instruments

def pluck(freq, dur, vel=1.0, bright=0.5, t60=2.6, pos=0.18):
    """Karplus-Strong string, vectorized one period at a time."""
    n = int(dur * SR)
    N = SR / freq
    ni = int(N)
    frac = N - ni
    g = 0.001 ** (1.0 / (t60 * freq))
    y = np.zeros(n + ni + 2)
    burst = rng.uniform(-1, 1, ni)
    burst = signal.lfilter([1 - bright * 0.8], [1, -bright * 0.8], burst)   # softer = darker
    p = max(1, int(ni * pos))
    burst = burst - np.concatenate([np.zeros(p), burst[:-p]])               # pluck position
    y[1:ni + 1] = burst * vel
    start = ni + 1
    while start < n:
        end = min(start + ni, n)
        a = y[start - ni:end - ni]
        b = y[start - ni - 1:end - ni - 1]
        y[start:end] = g * ((1 - frac) * a + frac * b) * 0.999 + g * 0.0005 * (a - b)
        start = end
    y = y[:n]
    env = np.minimum(1.0, np.arange(n) / (0.002 * SR))
    return y * env


def guitar_body(x):
    x = filt(x, "peak", 105, 1.2, 5)
    x = filt(x, "peak", 220, 1.4, 3)
    x = filt(x, "peak", 2800, 1.0, -3)
    return filt(x, "lp", 5200)


def ep(freq, dur, vel=1.0):
    """FM electric piano (Rhodes-ish)."""
    t = np.arange(int(dur * SR)) / SR
    idx = 1.6 * np.exp(-t * 5.0) + 0.15
    mod = np.sin(2 * np.pi * freq * t) * idx
    car = np.sin(2 * np.pi * freq * t + mod)
    bell = np.sin(2 * np.pi * freq * 4.0 * t) * np.exp(-t * 9) * 0.12
    env = np.exp(-t * 1.1) * np.minimum(1, t / 0.004)
    trem = 1 + 0.08 * np.sin(2 * np.pi * 4.6 * t)
    return (car + bell) * env * trem * vel


def bass(freq, dur, vel=1.0):
    t = np.arange(int(dur * SR)) / SR
    x = np.sin(2 * np.pi * freq * t) + 0.35 * signal.sawtooth(2 * np.pi * freq * t, 0.5)
    env = np.exp(-t * 2.2) * np.minimum(1, t / 0.006)
    x = filt(x * env, "lp", 700)
    return np.tanh(x * 1.6) * vel * 0.7


def kalimba(freq, dur, vel=1.0):
    t = np.arange(int(dur * SR)) / SR
    x = np.sin(2 * np.pi * freq * t) + 0.25 * np.sin(2 * np.pi * freq * 2.76 * t) * np.exp(-t * 18)
    env = np.exp(-t * 3.5) * np.minimum(1, t / 0.002)
    return x * env * vel


def kick(vel=1.0):
    t = np.arange(int(0.45 * SR)) / SR
    f = 46 + 80 * np.exp(-t * 32)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.sin(ph) * np.exp(-t * 7.5)
    x += rng.normal(0, 1, len(t)) * np.exp(-t * 200) * 0.25
    return np.tanh(x * 1.8) * vel


def snare(vel=1.0):
    t = np.arange(int(0.35 * SR)) / SR
    nz = filt(rng.normal(0, 1, len(t)), "bp", 2200, 0.6) * np.exp(-t * 16)
    tone = np.sin(2 * np.pi * 185 * t) * np.exp(-t * 25)
    return (nz * 1.2 + tone * 0.6) * vel


def hat(vel=1.0, open_=False):
    t = np.arange(int((0.3 if open_ else 0.08) * SR)) / SR
    nz = filt(rng.normal(0, 1, len(t)), "hp", 7000)
    return nz * np.exp(-t * (14 if open_ else 60)) * vel * 0.5


def place(buf, x, at):
    i = max(0, int(at * SR))
    if i >= len(buf):
        return
    j = min(len(buf), i + len(x))
    buf[i:j] += x[:j - i]


# ----------------------------------------------------------------- music

TRACKS = [
    # name, bpm, chords (midi voicings, 2 bars each), bass roots, style, key scale for melody
    ("sunday_morning", 78, [[53, 57, 60, 64, 69], [52, 55, 59, 62, 67], [50, 57, 60, 65, 69], [48, 55, 59, 64, 67]],
     [41, 40, 38, 36], "arp", [60, 62, 64, 67, 69, 72, 74, 76]),
    ("golden_hour", 74, [[55, 59, 62, 66, 69], [54, 57, 61, 64, 69], [52, 55, 59, 62, 66], [57, 59, 62, 64, 67]],
     [43, 42, 40, 45], "keys", [62, 64, 66, 69, 71, 74, 76, 78]),
    ("window_seat", 80, [[56, 60, 63, 67, 70], [55, 58, 62, 65, 70], [53, 56, 60, 63, 67], [58, 62, 65, 68, 72]],
     [44, 43, 41, 46], "strum", [63, 65, 67, 70, 72, 75, 77, 79]),
    ("night_drive", 70, [[57, 60, 64, 67, 71], [50, 57, 60, 64, 65], [55, 59, 62, 65, 69], [53, 57, 60, 64, 67]],
     [45, 38, 43, 41], "keys_arp", [57, 60, 62, 64, 67, 69, 72, 74]),
    ("rain_on_the_roof", 76, [[58, 62, 65, 69, 72], [57, 60, 64, 67, 72], [55, 58, 62, 65, 70], [48, 55, 58, 64, 67]],
     [46, 45, 43, 48], "arp", [60, 62, 65, 67, 69, 72, 74, 77]),
]


def make_track(name, bpm, chords, roots, style, scale, bars=24):
    beat = 60.0 / bpm
    bar = beat * 4
    total = bar * bars + 4.0
    L = int(total * SR)
    gtr = np.zeros(L); keys = np.zeros(L); bas = np.zeros(L); drm = np.zeros(L); mel = np.zeros(L)
    swing = 0.58

    def eighth(b, k):   # time of the k-th eighth note in bar b, swung
        base = b * bar + (k // 2) * beat
        return base + (beat * swing if k % 2 else 0.0) + rng.normal(0, 0.006)

    for b in range(bars):
        ci = (b // 2) % 4
        ch = chords[ci]
        root = roots[ci]
        section = b // 8   # 0 intro-ish, 1 groove, 2 groove + melody
        # guitar
        if style in ("arp", "keys_arp"):
            pat = [0, 2, 3, 4, 1, 3, 2, 4] if b % 2 == 0 else [0, 2, 4, 3, 1, 2, 3, 4]
            for k, ni in enumerate(pat):
                if style == "keys_arp" and k % 2 == 1 and section == 0:
                    continue
                f = mtof(ch[ni] + (12 if ni >= 3 and k == 5 else 0))
                v = 0.55 if k % 2 == 0 else 0.4
                place(gtr, pluck(f, 2.4, v, bright=0.45, t60=2.2), eighth(b, k))
        if style == "strum":
            strokes = [(0, 1, 0.9), (2, 1, 0.6), (3, -1, 0.45), (5, -1, 0.4), (6, 1, 0.65), (7, -1, 0.4)]
            for k, d, v in strokes:
                order = ch if d > 0 else ch[::-1]
                t0 = eighth(b, k)
                for j, m in enumerate(order):
                    place(gtr, pluck(mtof(m), 1.6, v * (0.75 if d < 0 else 1.0), bright=0.5, t60=1.4), t0 + j * (0.014 if d > 0 else 0.009))
        if style in ("keys", "keys_arp"):
            t0 = b * bar + rng.normal(0, 0.004)
            if b % 2 == 0:
                for j, m in enumerate(ch[1:]):
                    place(keys, ep(mtof(m), bar * 2 + 1.0, 0.35), t0 + j * 0.008)
            else:
                for j, m in enumerate(ch[2:]):
                    place(keys, ep(mtof(m + 12), bar, 0.15), t0 + 2 * beat + beat * swing - beat * 0.5)
            if style == "keys":
                for k in [0, 3, 6]:
                    place(gtr, pluck(mtof(ch[[1, 3, 4][k // 3]]), 1.8, 0.35, bright=0.4, t60=1.8), eighth(b, k))
        # bass
        if b >= 2 or style == "strum":
            place(bas, bass(mtof(root), beat * 1.6, 0.9), b * bar)
            place(bas, bass(mtof(root + (7 if b % 2 else 12)), beat * 0.9, 0.6), eighth(b, 5))
            if b % 2 == 1:
                place(bas, bass(mtof(root + 7), beat * 0.7, 0.55), eighth(b, 7))
        # drums
        if b >= 4 or (style == "strum" and b >= 2):
            for k in range(8):
                place(drm, hat(0.5 + 0.25 * (k % 2 == 0) + rng.uniform(-0.1, 0.1), open_=(k == 7 and b % 4 == 3)), eighth(b, k))
            place(drm, kick(0.95), b * bar)
            place(drm, kick(0.7), eighth(b, 5 if b % 2 == 0 else 3))
            if b % 4 == 3:
                place(drm, kick(0.55), eighth(b, 7))
            place(drm, snare(0.8), b * bar + beat + rng.normal(0, 0.004))
            place(drm, snare(0.85), b * bar + 3 * beat + rng.normal(0, 0.004))
        # melody: sparse kalimba motifs in the last section
        if section == 2 or (section == 1 and b % 4 == 3):
            for k in range(8):
                if rng.random() < (0.38 if k % 2 == 0 else 0.18):
                    tones = [m for m in scale if (m % 12) in [x % 12 for x in ch]] or scale
                    m = int(rng.choice(tones if rng.random() < 0.7 else scale)) + 12
                    place(mel, kalimba(mtof(m), 1.4, 0.32), eighth(b, k))

    gtr = guitar_body(gtr)
    keys = filt(keys, "lp", 3800)
    # kick ducks everything else a little (lo-fi pump)
    duck_env = np.abs(signal.lfilter([1], [1, -0.9995], np.abs(filt(drm, "lp", 120))))
    duck = 1.0 - 0.25 * np.clip(duck_env / (duck_env.max() + 1e-9) * 3.0, 0, 1)
    mix = gtr * 0.55 + keys * 0.5 + bas * 0.55 + mel * 0.4
    mix = mix * duck + drm * 0.42
    mix = reverb(mix, mix=0.22, size=1.1)
    # tape wobble (wow + flutter)
    t = np.arange(L) / SR
    tt = t + 0.0022 * np.sin(2 * np.pi * 0.45 * t) + 0.0004 * np.sin(2 * np.pi * 5.3 * t)
    mix = np.interp(tt, t, mix)
    # vinyl: crackle + hiss
    crackle = (rng.random(L) < 0.00035) * rng.uniform(-1, 1, L)
    crackle = filt(crackle, "bp", 3000, 0.8) * 0.5
    hiss = filt(rng.normal(0, 1, L), "lp", 6000) * 0.006
    mix = mix + crackle * 0.08 + hiss
    mix = filt(mix, "lp", 7800)
    mix = filt(mix, "hp", 35)
    mix = np.tanh(mix / (np.max(np.abs(mix)) + 1e-9) * 1.4) * 0.8
    # fades
    fi = int(1.2 * SR); fo = int(3.5 * SR)
    mix[:fi] *= np.linspace(0, 1, fi)
    mix[-fo:] *= np.linspace(1, 0, fo) ** 1.5
    # gentle stereo: delay the right channel a touch and pan guitar/keys lightly
    right = np.concatenate([np.zeros(int(0.011 * SR)), mix[:-int(0.011 * SR)]])
    st = np.stack([mix * 0.96 + right * 0.04, right * 0.96 + mix * 0.04], axis=1)
    return st


def write_wav(path, x, sr=SR):
    x = np.asarray(x)
    if x.ndim == 1:
        x = x[:, None]
    x = np.clip(x, -1, 1)
    data = (x * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(data.shape[1])
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data.tobytes())


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak


def fade(x, a=0.002, b=0.02):
    x = x.copy()
    na = max(1, int(a * SR)); nb = max(1, int(b * SR))
    x[:na] *= np.linspace(0, 1, na)
    x[-nb:] *= np.linspace(1, 0, nb)
    return x


# ----------------------------------------------------------------- sound effects (toy-like)

def tone(f, dur, kind="sine"):
    t = np.arange(int(dur * SR)) / SR
    if callable(f):
        ph = 2 * np.pi * np.cumsum(f(t)) / SR
    else:
        ph = 2 * np.pi * f * t
    if kind == "sine":
        return np.sin(ph)
    if kind == "tri":
        return signal.sawtooth(ph, 0.5)
    if kind == "square":
        return np.sign(np.sin(ph)) * 0.6
    if kind == "saw":
        return signal.sawtooth(ph)
    raise ValueError(kind)


def env_exp(n, rate):
    return np.exp(-np.arange(n) / SR * rate)


def noise(dur):
    return rng.normal(0, 1, int(dur * SR))


def sfx_all():
    S = {}
    t = lambda d: np.arange(int(d * SR)) / SR
    # wind-up toy motor loop (1 s, seamless): buzzy tone with gear ticks at a whole number of cycles
    d = 1.0
    tt = t(d)
    motor = signal.sawtooth(2 * np.pi * 96 * tt) * 0.5 + np.sin(2 * np.pi * 192 * tt) * 0.3
    motor *= 0.8 + 0.2 * np.sin(2 * np.pi * 12 * tt)
    ticks = np.zeros_like(tt)
    for k in range(24):
        i = int(k * SR / 24)
        ticks[i:i + 120] += np.exp(-np.arange(120) / 18.0) * 0.8
    motor = filt(motor + filt(ticks, "bp", 3200, 1.0) * 0.6, "lp", 2400)
    S["engine"] = norm(motor, 0.5)
    # rubbery tyre squeak loop
    sq = np.sin(2 * np.pi * (900 + 60 * np.sin(2 * np.pi * 9 * tt)) * tt) * 0.4 + filt(noise(d), "bp", 1800, 2.0) * 0.6
    S["drift"] = norm(filt(sq, "lp", 3500), 0.4)
    # weather loops
    S["wind"] = norm(filt(filt(noise(2.0), "bp", 500, 0.5) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.5 * t(2.0))), "lp", 1200), 0.5)
    rain = filt(noise(2.0), "hp", 1500) * 0.4
    drops = (rng.random(int(2.0 * SR)) < 0.004) * rng.uniform(0.3, 1, int(2.0 * SR))
    rain += filt(drops, "bp", 2600, 3.0) * 2.0
    S["rain"] = norm(filt(rain, "lp", 6000), 0.45)
    # pickups
    click = filt(noise(0.012), "bp", 4000, 1.0) * env_exp(int(0.012 * SR), 400) * 0.5
    coin = np.zeros(int(0.22 * SR))
    place2(coin, click, 0)
    place2(coin, tone(1760, 0.08) * env_exp(int(0.08 * SR), 45) * 0.6, 0.0)
    place2(coin, tone(2637, 0.18) * env_exp(int(0.18 * SR), 20) * 0.7, 0.045)
    S["coin"] = norm(coin, 0.7)
    glug = np.zeros(int(0.45 * SR))
    for k in range(3):
        f = lambda x, k=k: 220 + 260 * x / 0.12 + k * 40
        g = tone(f, 0.12) * env_exp(int(0.12 * SR), 20)
        place2(glug, g * 0.7, k * 0.09)
    place2(glug, tone(1320, 0.2) * env_exp(int(0.2 * SR), 18) * 0.5, 0.28)
    S["fuel"] = norm(glug, 0.7)
    ding = np.zeros(int(0.9 * SR))
    for k, f in enumerate([1318, 1046]):
        b = tone(f, 0.7) * env_exp(int(0.7 * SR), 6) + tone(f * 2.71, 0.7) * env_exp(int(0.7 * SR), 14) * 0.3
        place2(ding, b * 0.6, k * 0.22)
    S["station"] = norm(ding, 0.75)
    # jumps and landings
    boing = tone(lambda x: 180 + 520 * np.minimum(1, x / 0.16) - 120 * np.sin(2 * np.pi * 14 * x) * np.exp(-x * 8), 0.35, "tri") * env_exp(int(0.35 * SR), 8)
    S["launch"] = norm(filt(boing, "lp", 3000), 0.65)
    clack = filt(noise(0.05), "bp", 1600, 1.5) * env_exp(int(0.05 * SR), 80)
    thud = tone(lambda x: 140 - 80 * x / 0.15, 0.15) * env_exp(int(0.15 * SR), 25)
    land = np.zeros(int(0.2 * SR)); place2(land, thud * 0.9, 0); place2(land, clack * 0.8, 0.0)
    S["land"] = norm(land, 0.75)
    lc = land.copy(); spark = np.zeros(int(0.5 * SR))
    for k, f in enumerate([1568, 2093, 2637]):
        place2(spark, tone(f, 0.2) * env_exp(int(0.2 * SR), 20) * 0.4, 0.05 + k * 0.05)
    place2(spark, lc * 0.6, 0)
    S["land_clean"] = norm(spark, 0.7)
    sw = filt(noise(0.4), "bp", 1200, 1.0) * np.sin(np.linspace(0, np.pi, int(0.4 * SR))) ** 2
    spin = sw + tone(lambda x: 400 + 900 * x / 0.4, 0.4, "tri") * 0.25 * np.sin(np.linspace(0, np.pi, int(0.4 * SR)))
    S["spin"] = norm(spin, 0.6)
    whoosh = filt(noise(0.25), "bp", 2000, 0.8) * np.sin(np.linspace(0, np.pi, int(0.25 * SR))) ** 3
    S["near"] = norm(whoosh, 0.55)
    S["gust"] = norm(filt(noise(1.2), "bp", 700, 0.7) * np.sin(np.linspace(0, np.pi, int(1.2 * SR))) ** 2, 0.5)
    # knock-overs
    wood = filt(noise(0.12), "bp", 900, 2.5) * env_exp(int(0.12 * SR), 30) + tone(320, 0.12) * env_exp(int(0.12 * SR), 40) * 0.5
    S["knock_wood"] = norm(wood, 0.7)
    soft = filt(noise(0.18), "lp", 900) * env_exp(int(0.18 * SR), 20)
    S["knock_soft"] = norm(soft + tone(220, 0.18) * env_exp(int(0.18 * SR), 30) * 0.3, 0.6)
    rock = filt(noise(0.2), "bp", 500, 1.5) * env_exp(int(0.2 * SR), 22) + tone(110, 0.2) * env_exp(int(0.2 * SR), 25) * 0.6
    S["knock_rock"] = norm(rock, 0.7)
    poof = filt(noise(0.35), "lp", 1400) * np.sin(np.linspace(0, np.pi, int(0.35 * SR))) ** 0.5 * env_exp(int(0.35 * SR), 6)
    S["knock_cloud"] = norm(poof, 0.55)
    S["knock_sand"] = norm(filt(noise(0.3), "bp", 2500, 0.7) * env_exp(int(0.3 * SR), 14), 0.5)
    cr = np.zeros(int(0.6 * SR))
    for k, f in enumerate([2637, 3136, 3951, 2093]):
        place2(cr, tone(f, 0.4) * env_exp(int(0.4 * SR), 12) * 0.35, k * 0.04)
    S["knock_crystal"] = norm(cr, 0.6)
    S["knock_metal"] = norm(tone(880, 0.3) * env_exp(int(0.3 * SR), 14) + tone(1397, 0.3) * env_exp(int(0.3 * SR), 18) * 0.5, 0.55)
    S["bonk"] = norm(tone(lambda x: 300 - 160 * x / 0.2, 0.2, "tri") * env_exp(int(0.2 * SR), 18), 0.7)
    # endings
    whistle = tone(lambda x: 1500 - 1100 * (x / 1.2) ** 0.7, 1.2) * (0.6 + 0.4 * np.sin(2 * np.pi * 6 * t(1.2)))
    S["fall"] = norm(fade(whistle * np.linspace(1, 0.4, len(whistle)), 0.01, 0.15), 0.6)
    spl = filt(noise(0.7), "lp", 2500) * env_exp(int(0.7 * SR), 5) + filt(noise(0.7), "bp", 300, 1.0) * env_exp(int(0.7 * SR), 8)
    S["splash"] = norm(spl, 0.7)
    sp = np.zeros(int(0.9 * SR))
    for k in range(5):
        place2(sp, filt(noise(0.06), "bp", 600, 1.0) * env_exp(int(0.06 * SR), 50) * (1 - k * 0.15), k * 0.13 + rng.uniform(0, 0.04))
    windown = tone(lambda x: 180 * (1 - x / 0.9) + 30, 0.9, "saw") * np.linspace(0.5, 0, int(0.9 * SR))
    S["sputter"] = norm(sp + filt(windown, "lp", 900) * 0.6, 0.65)
    S["lowfuel"] = norm(np.concatenate([tone(880, 0.1) * env_exp(int(0.1 * SR), 20), np.zeros(int(0.06 * SR)), tone(880, 0.1) * env_exp(int(0.1 * SR), 20)]), 0.5)
    S["crumble"] = norm(filt(noise(0.6), "lp", 400) * env_exp(int(0.6 * SR), 6), 0.4)
    # UI
    S["tap"] = norm(filt(noise(0.03), "bp", 2500, 2.0) * env_exp(int(0.03 * SR), 120) + tone(1200, 0.03) * env_exp(int(0.03 * SR), 150) * 0.4, 0.5)
    S["select"] = norm(np.concatenate([tone(988, 0.08) * env_exp(int(0.08 * SR), 30), tone(1319, 0.14) * env_exp(int(0.14 * SR), 18)]), 0.6)
    chime = np.zeros(int(1.0 * SR))
    for k, f in enumerate([1047, 1319, 1568, 2093]):
        place2(chime, tone(f, 0.6) * env_exp(int(0.6 * SR), 8) * 0.4, k * 0.07)
    ka = filt(noise(0.05), "bp", 3500, 1.0) * env_exp(int(0.05 * SR), 60)
    place2(chime, ka, 0)
    S["purchase"] = norm(chime, 0.7)
    up = np.zeros(int(0.8 * SR))
    for k in range(6):
        place2(up, filt(noise(0.02), "bp", 3000, 2.0) * env_exp(int(0.02 * SR), 150) * 0.5, k * 0.04)
    for k, f in enumerate([784, 988, 1175, 1568]):
        place2(up, tone(f, 0.3) * env_exp(int(0.3 * SR), 12) * 0.4, 0.25 + k * 0.06)
    S["upgrade"] = norm(up, 0.7)
    mis = np.zeros(int(0.9 * SR))
    for k, f in enumerate([784, 988, 1175, 1568]):
        place2(mis, (tone(f, 0.35, "tri") * 0.5 + tone(f * 2, 0.35) * 0.15) * env_exp(int(0.35 * SR), 9), k * 0.09)
    S["mission"] = norm(mis, 0.7)
    rec = np.zeros(int(1.6 * SR))
    for k, f in enumerate([523, 659, 784, 1047, 1319, 1568]):
        place2(rec, (tone(f, 0.5, "tri") * 0.5 + tone(f * 2, 0.5) * 0.2) * env_exp(int(0.5 * SR), 6), k * 0.08)
    horn = tone(lambda x: 400 + 300 * np.minimum(1, x / 0.1), 0.5, "saw") * env_exp(int(0.5 * SR), 4) * 0.3
    place2(rec, filt(horn, "lp", 2000), 0.5)
    S["record"] = norm(rec, 0.75)
    sea = np.zeros(int(1.2 * SR))
    for k, f in enumerate([1568, 2093, 2637, 3136]):
        place2(sea, kalimba(f, 0.8, 0.4), k * 0.11)
    S["season"] = norm(sea, 0.55)
    st = tone(lambda x: 120 + 220 * np.minimum(1, x / 0.5), 0.6, "saw") * np.minimum(1, t(0.6) / 0.05) * np.linspace(1, 0.4, int(0.6 * SR))
    S["start"] = norm(filt(st, "lp", 1600) + filt(noise(0.6), "bp", 3000, 1.0) * 0.1, 0.6)
    return S


def place2(buf, x, at):
    x = np.asarray(x)
    i = max(0, int(at * SR))
    j = min(len(buf), i + len(x))
    if i < len(buf):
        buf[i:j] += x[:j - i]


def main():
    os.makedirs(MUSIC, exist_ok=True)
    os.makedirs(SFX, exist_ok=True)
    only = sys.argv[1] if len(sys.argv) > 1 else "all"
    if only in ("all", "sfx"):
        for name, x in sfx_all().items():
            write_wav(os.path.join(SFX, name + ".wav"), fade(np.asarray(x, dtype=float), 0.001, 0.005) if name not in ("engine", "drift", "wind", "rain") else x)
            print("sfx", name)
    if only in ("all", "music"):
        for tr in TRACKS:
            x = make_track(*tr)
            tmp = os.path.join(MUSIC, tr[0] + ".wav")
            write_wav(tmp, x)
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "4", os.path.join(MUSIC, tr[0] + ".ogg")], check=True)
            os.remove(tmp)
            print("music", tr[0], "%.1fs" % (len(x) / SR))


if __name__ == "__main__":
    main()

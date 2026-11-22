#!/usr/bin/env python3
"""Vehicle sounds for Lo-Fi Ryder, synthesized from a small physical-ish engine model.

    python3 tools/audio/make_vehicle.py      # writes assets/audio/sfx/eng_*.wav, roll_*.wav, skid_*.wav, ...

Engines: each family (small 4-cyl, diesel truck, V8, two-cylinder putt-putt) gets four seamless loops
recorded at different RPMs. The game crossfades between neighbouring layers and bends their pitch to the
live RPM, which is how game engines sound smooth across the whole rev range.

Loops are built with circular (FFT) filtering on periodic excitation, so they repeat without a seam.
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "sfx"))
rng = np.random.default_rng(77)

# family: cylinders, firing offsets (fraction of the 720° cycle), layer rpms, tone
FAMILIES = {
    "small": {"cyl": 4, "fire": [0.0, 0.25, 0.5, 0.75], "rpm": [900, 2300, 4000, 6200],
              "peaks": [(150, 3.0, 9), (520, 2.5, 6), (1500, 2.0, 3)], "lp": 3800, "pipe": 0.0032, "noise": 0.35, "clatter": 0.0, "body": 1.0},
    "truck": {"cyl": 6, "fire": [0.0, 1/6, 2/6, 3/6, 4/6, 5/6], "rpm": [650, 1400, 2300, 3300],
              "peaks": [(95, 2.5, 10), (330, 2.0, 6), (900, 2.0, 2)], "lp": 2400, "pipe": 0.0055, "noise": 0.3, "clatter": 0.55, "body": 1.2},
    "v8": {"cyl": 8, "fire": [0.0, 0.125, 0.205, 0.375, 0.5, 0.625, 0.705, 0.875], "rpm": [750, 1900, 3400, 5400],
           "peaks": [(85, 3.5, 12), (260, 2.5, 7), (700, 2.0, 3)], "lp": 2600, "pipe": 0.0045, "noise": 0.4, "clatter": 0.0, "body": 1.4},
    "putt": {"cyl": 2, "fire": [0.0, 0.375], "rpm": [600, 1300, 2200, 3200],
             "peaks": [(120, 4.0, 10), (420, 3.0, 5), (1100, 2.0, 2)], "lp": 2200, "pipe": 0.006, "noise": 0.5, "clatter": 0.25, "body": 1.6},
}


def write(name, x):
    x = np.asarray(x, dtype=float)
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.85
    d = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(d.tobytes())
    print(name, "%.2fs" % (len(x) / SR))


def fft_filter(x, H):
    """Circular filtering: the output repeats seamlessly with the input."""
    return np.fft.irfft(np.fft.rfft(x) * H, n=len(x))


def resp(n, peaks=(), lp=None, hp=None, comb=None):
    f = np.fft.rfftfreq(n, 1 / SR)
    H = np.ones_like(f, dtype=complex)
    if peaks:
        P = np.zeros_like(f)
        for fc, q, g in peaks:
            P += g / (1 + ((f - fc) / (fc / q)) ** 2)
        H *= 0.25 + P
    if lp:
        H /= np.sqrt(1 + (f / lp) ** 6)
    if hp:
        H *= (f / hp) ** 2 / np.sqrt(1 + (f / hp) ** 4)
    if comb:
        tau, g = comb
        H *= 1 / (1 - g * np.exp(-2j * np.pi * f * tau))
    return H


def circ_conv(x, k):
    kk = np.zeros(len(x))
    kk[:len(k)] = k
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(kk), n=len(x))


def engine_loop(fam, rpm, seconds=1.6):
    F = FAMILIES[fam]
    f_cycle = rpm / 60.0 / 2.0
    n_cycles = max(6, int(round(seconds * f_cycle)))
    N = int(round(n_cycles / f_cycle * SR))
    cyc = N / n_cycles
    imp = np.zeros(N)
    cl = np.zeros(N)
    amps = 1.0 + rng.uniform(-0.18, 0.18, F["cyl"])
    load = rpm / F["rpm"][-1]
    for c in range(n_cycles):
        for j, off in enumerate(F["fire"]):
            t = (c + off) * cyc + rng.normal(0, cyc * 0.004)
            i = int(np.floor(t)) % N
            fr = t - np.floor(t)
            a = amps[j] * (1 + rng.normal(0, 0.06))
            imp[i] += a * (1 - fr)
            imp[(i + 1) % N] += a * fr
            if F["clatter"] > 0:
                ci = (i + int(SR * 0.0012)) % N
                cl[ci] += a * (0.6 + rng.uniform(0, 0.4))
    # exhaust pulse: a quick pressure kick and a softer suck-back
    w = 0.0009 + 0.0006 * (1 - load)
    tk = np.arange(int(SR * 0.012)) / SR
    pulse = np.exp(-((tk - w) / (w * 0.55)) ** 2) - 0.45 * np.exp(-((tk - 3.2 * w) / (w * 1.3)) ** 2)
    ex = circ_conv(imp, pulse)
    # combustion roar: noise under a decaying envelope after each firing
    env = circ_conv(imp, np.exp(-tk / (0.0035 + 0.003 * (1 - load))))
    roar = rng.normal(0, 1, N) * env
    roar = fft_filter(roar, resp(N, peaks=[(700, 1.2, 2), (1800, 1.5, 1)], lp=F["lp"] * 1.4))
    exhaust = fft_filter(ex * F["body"] + roar * F["noise"] * (0.6 + load),
                         resp(N, peaks=F["peaks"], lp=F["lp"] * (0.8 + 0.5 * load), hp=35, comb=(F["pipe"], 0.45)))
    # intake hiss pumping at the firing rate
    intake = fft_filter(rng.normal(0, 1, N), resp(N, peaks=[(1300, 1.5, 2)], lp=4000, hp=500)) * (0.4 + env / (env.max() + 1e-9))
    # mechanical: gentle whine at engine orders (whole cycles in the loop, so it stays seamless)
    t = np.arange(N) / SR
    rev = rpm / 60.0
    mech = sum(np.sin(2 * np.pi * rev * k * t) * a for k, a in [(2, 0.5), (4, 0.25), (6, 0.12)])
    out = exhaust / (np.std(exhaust) + 1e-9) + intake / (np.std(intake) + 1e-9) * (0.08 + 0.1 * load) + mech * 0.04
    if F["clatter"] > 0:
        tick = fft_filter(circ_conv(cl, np.exp(-tk / 0.0006) * rng.normal(0, 1, len(tk))), resp(N, lp=7000, hp=2200))
        out += tick / (np.std(tick) + 1e-9) * F["clatter"] * 0.35
    out = np.tanh(out / (np.std(out) * 2.2 + 1e-9) * 1.3)
    return out / (np.sqrt(np.mean(out ** 2)) + 1e-9) * 0.25


def noise_loop(seconds, H_fn, mod=None):
    N = int(seconds * SR)
    x = rng.normal(0, 1, N)
    if mod is not None:
        x = x * mod(N)
    return fft_filter(x, H_fn(N))


def clicks(N, rate, decay, lp, hp, jitter=1.0):
    """Random grain impacts (gravel, snow crunch), circular."""
    n = int(N / SR * rate)
    x = np.zeros(N)
    pos = rng.integers(0, N, n)
    np.add.at(x, pos, rng.uniform(0.2, 1.0, n) * rng.choice([-1, 1], n))
    tk = np.arange(int(SR * decay * 6)) / SR
    k = np.exp(-tk / decay)
    return fft_filter(circ_conv(x, k), resp(N, lp=lp, hp=hp))


def xfade_loop(x, fade=0.15):
    """Turns any sound into a loop by folding its tail over its head."""
    n = int(fade * SR)
    head = x[:n].copy()
    tail = x[-n:].copy()
    r = np.linspace(0, 1, n)
    x = x[:-n].copy()
    x[:n] = head * np.sqrt(r) + tail * np.sqrt(1 - r)
    return x


def main():
    os.makedirs(OUT, exist_ok=True)
    for fam, F in FAMILIES.items():
        for i, rpm in enumerate(F["rpm"]):
            write("eng_%s_%d" % (fam, i), engine_loop(fam, rpm))
    # tyres rolling on each surface (2 s loops; the game bends pitch with speed)
    S = 2.0
    N = int(S * SR)
    road = noise_loop(S, lambda n: resp(n, peaks=[(180, 1.5, 3), (420, 2.0, 1.5)], lp=900, hp=40))
    tread = np.sin(2 * np.pi * 22 * np.arange(N) / SR) * 0.08
    write("roll_road", road / np.std(road) * 0.3 + tread)
    grass = noise_loop(S, lambda n: resp(n, lp=3500, hp=900), mod=lambda n: 0.5 + 0.5 * np.abs(np.sin(np.pi * 3 * np.arange(n) / n))) \
        + clicks(N, 260, 0.0015, 5000, 1500) * 3
    write("roll_grass", grass / np.std(grass) * 0.25 + road / np.std(road) * 0.12)
    gravel = clicks(N, 1400, 0.0009, 6500, 1100) + noise_loop(S, lambda n: resp(n, lp=700, hp=60)) * 0.4
    write("roll_gravel", gravel / np.std(gravel) * 0.3)
    wood = road / np.std(road) * 0.35
    plank = np.zeros(N)
    for k in range(12):
        i = int(k * N / 12)
        plank[i] = 1.0
    tk = np.arange(int(SR * 0.05)) / SR
    thunk = np.sin(2 * np.pi * 140 * tk) * np.exp(-tk / 0.012) + rng.normal(0, 0.3, len(tk)) * np.exp(-tk / 0.004)
    wood = wood + circ_conv(plank, thunk) * 2.2
    write("roll_wood", wood)
    snow = clicks(N, 900, 0.002, 3200, 300) + clicks(N, 40, 0.01, 2500, 900) * 0.6
    write("roll_snow", snow / np.std(snow) * 0.3)
    # skids
    t = np.arange(int(2.4 * SR)) / SR
    wob = 1 + 0.025 * np.sin(2 * np.pi * 7.3 * t) + 0.015 * np.sin(2 * np.pi * 13.1 * t)
    squeal = sum(np.sin(2 * np.pi * np.cumsum(f * wob) / SR) * a for f, a in [(1180, 1.0), (1760, 0.45), (2380, 0.25)])
    squeal *= 0.7 + 0.3 * np.abs(np.sin(2 * np.pi * 2.1 * t))
    hiss = noise_loop(2.4, lambda n: resp(n, peaks=[(1600, 2.0, 2)], lp=5000, hp=600))
    write("skid_road", xfade_loop(squeal * 0.6 + hiss / np.std(hiss) * 0.25))
    scrub = clicks(N, 2200, 0.0012, 4500, 500) + noise_loop(S, lambda n: resp(n, lp=1800, hp=200)) * 0.5
    write("skid_dirt", scrub / np.std(scrub) * 0.3)
    # air rush while flying
    rush = noise_loop(S, lambda n: resp(n, peaks=[(600, 0.8, 2)], lp=2500, hp=150),
                      mod=lambda n: 0.75 + 0.25 * np.sin(2 * np.pi * 2 * np.arange(n) / n))
    write("air_rush", rush)
    # police siren (US wail), 4 s loop
    t = np.arange(int(4.2 * SR)) / SR
    f = 720 + 640 * (0.5 - 0.5 * np.cos(2 * np.pi * t / 4.0))
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = np.sign(np.sin(ph)) * 0.6 + np.sin(ph) * 0.6 + np.sin(2 * ph) * 0.2
    siren = fft_filter(tone, resp(len(tone), peaks=[(1000, 1.2, 3)], lp=3500, hp=400))
    write("siren", xfade_loop(np.tanh(siren / np.std(siren) * 0.6), 0.2))
    # boost: rev + whoosh
    t = np.arange(int(0.9 * SR)) / SR
    ph = 2 * np.pi * np.cumsum(180 + 420 * np.minimum(1, t / 0.35)) / SR
    rev = (np.sign(np.sin(ph)) * 0.4 + np.sin(ph)) * np.exp(-t * 2.2)
    wh = fft_filter(rng.normal(0, 1, len(t)), resp(len(t), lp=3000, hp=300)) * np.sin(np.pi * np.minimum(1, t / 0.9)) ** 1.5
    boost = fft_filter(rev, resp(len(t), peaks=[(220, 2, 4), (700, 2, 2)], lp=2500)) * 0.8 + wh / np.std(wh) * 0.35
    boost[:200] *= np.linspace(0, 1, 200)
    write("boost", boost)
    # horns: little two-tone toy beeps
    for name, (f1, f2, d) in {"horn_hi": (523, 659, 0.11), "horn_lo": (311, 392, 0.16)}.items():
        seg = []
        for k in range(2):
            tt = np.arange(int(d * SR)) / SR
            b = (np.sign(np.sin(2 * np.pi * f1 * tt)) + np.sign(np.sin(2 * np.pi * f2 * tt))) * 0.5
            b = fft_filter(b, resp(len(b), peaks=[(900, 1.5, 2)], lp=3200))
            b *= np.minimum(1, tt / 0.005) * np.minimum(1, (d - tt) / 0.01)
            seg += [b, np.zeros(int(0.06 * SR))]
        write(name, np.concatenate(seg))
    # light suspension clunk
    t = np.arange(int(0.14 * SR)) / SR
    clunk = np.sin(2 * np.pi * (90 + 40 * np.exp(-t * 40)) * t) * np.exp(-t * 30) + rng.normal(0, 0.2, len(t)) * np.exp(-t * 90)
    write("bump", clunk)


if __name__ == "__main__":
    main()

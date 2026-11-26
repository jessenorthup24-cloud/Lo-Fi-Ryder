"""Fist fights (synthesized, no samples): punches landing (punch_1..3, tight: a low thud with a leather slap
and a crack on top), a heavy one for a finisher (punch_heavy), swings through the air (swish_1..2), a blow
taken on the arms (block), and a kick landing (kick_hit).
    python3 tools/audio/make_fight.py [out_dir]   (default assets/audio/sfx)"""
import sys, wave
import numpy as np

SR = 22050
OUT = sys.argv[1] if len(sys.argv) > 1 else "assets/audio/sfx"

def save(name, x, peak=0.92):
    x = x / max(1e-6, np.max(np.abs(x))) * peak
    with wave.open(f"{OUT}/{name}.wav", "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())

def band(x, lo, hi):
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    f[(fr < lo) | (fr > hi)] = 0
    return np.fft.irfft(f, len(x))

def thump(n, f0, f1, decay, drop=0.025):
    t = np.arange(n) / SR
    f = f1 + (f0 - f1) * np.exp(-t / drop)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / decay)

def punch(seed, f0, dur=0.32, weight=1.0):
    rng = np.random.default_rng(seed)
    n = int(dur * SR); t = np.arange(n) / SR
    body = thump(n, f0, 45.0, 0.07 * weight) * 1.1
    slap = band(rng.standard_normal(n), 900, 5200) * np.exp(-t / 0.011) * 0.75
    crack = band(rng.standard_normal(n), 2500, 8000) * np.exp(-t / 0.004) * 0.5
    flesh = band(rng.standard_normal(n), 180, 900) * np.exp(-t / 0.035) * 0.45 * weight
    x = body + slap + crack + flesh
    x[: int(0.0015 * SR)] *= np.linspace(0, 1, int(0.0015 * SR))
    return np.tanh(x * 1.6)

def swish(seed, dur=0.2):
    rng = np.random.default_rng(seed)
    n = int(dur * SR); t = np.arange(n) / SR
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 2
    # air: noise swept up and back down through a band
    x = np.zeros(n)
    noise = rng.standard_normal(n)
    for k, (lo, hi) in enumerate([(400, 1200), (800, 2400), (1500, 4000), (800, 2400), (400, 1200)]):
        seg = band(noise, lo, hi)
        w = np.exp(-((t / dur - (k + 0.5) / 5) ** 2) / 0.012)
        x += seg * w
    return x * env * 0.8

def block(seed):
    rng = np.random.default_rng(seed)
    n = int(0.25 * SR); t = np.arange(n) / SR
    x = thump(n, 95.0, 50.0, 0.05) * 0.9 + band(rng.standard_normal(n), 200, 1400) * np.exp(-t / 0.02) * 0.6
    return np.tanh(x * 1.3)

save("punch_1", punch(11, 105.0))
save("punch_2", punch(12, 92.0))
save("punch_3", punch(13, 118.0))
save("punch_heavy", punch(14, 80.0, 0.5, 1.8))
save("kick_hit", punch(15, 70.0, 0.42, 1.5))
save("swish_1", swish(21), 0.5)
save("swish_2", swish(22, 0.24), 0.5)
save("block", block(31), 0.8)
print("wrote punch_1..3, punch_heavy, kick_hit, swish_1..2, block to", OUT)

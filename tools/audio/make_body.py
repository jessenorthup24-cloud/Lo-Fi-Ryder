"""A car hitting someone (synthesized, no samples): a heavy low thump with a short wet slap on top, in three
takes (body_hit_1..3), and a dull thud for a body landing on the road or a bonnet (body_land).
    python3 tools/audio/make_body.py [out_dir]   (default assets/audio/sfx)"""
import sys, wave
import numpy as np

SR = 22050
OUT = sys.argv[1] if len(sys.argv) > 1 else "assets/audio/sfx"
rng = np.random.default_rng(23)

def save(name, x, peak=0.9):
    x = x / max(1e-6, np.max(np.abs(x))) * peak
    with wave.open(f"{OUT}/{name}.wav", "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())

def band(x, lo, hi):
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    f[(fr < lo) | (fr > hi)] = 0
    return np.fft.irfft(f, len(x))

def thump(dur, f0, f1, decay):
    n = int(dur * SR); t = np.arange(n) / SR
    f = f1 + (f0 - f1) * np.exp(-t / 0.03)          # the pitch drops fast: a punch, not a note
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t / decay)

def hit(seed, f0):
    global rng
    rng = np.random.default_rng(seed)
    dur = 0.45
    n = int(dur * SR); t = np.arange(n) / SR
    body = thump(dur, f0, 48.0, 0.09) * 1.0
    # the slap: a short burst of mid noise, a little wet
    slap = band(rng.standard_normal(n), 500, 3200) * np.exp(-t / 0.018) * 0.55
    # the knock of bodywork behind it
    knock = band(rng.standard_normal(n), 120, 700) * np.exp(-t / 0.05) * 0.5
    x = body + slap + knock
    x[: int(0.002 * SR)] *= np.linspace(0, 1, int(0.002 * SR))
    return x

def land():
    dur = 0.35
    n = int(dur * SR); t = np.arange(n) / SR
    x = thump(dur, 90.0, 40.0, 0.07) + band(rng.standard_normal(n), 150, 900) * np.exp(-t / 0.03) * 0.4
    return x

save("body_hit_1", hit(1, 120.0))
save("body_hit_2", hit(2, 105.0))
save("body_hit_3", hit(3, 135.0))
save("body_land", land(), 0.7)
print("wrote body_hit_1..3, body_land to", OUT)

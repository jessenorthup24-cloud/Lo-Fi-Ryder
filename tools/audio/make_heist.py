"""The heist's sounds (synthesized, no samples): the core drill grinding into a safe (drill, a seamless loop),
the safe's door swinging open (safe_open: a heavy clunk, then a creak), and picking up cash (cash: a paper
riffle with a bright little ring on top).
    python3 tools/audio/make_heist.py [out_dir]   (default assets/audio/sfx)"""
import sys, wave
import numpy as np

SR = 22050
OUT = sys.argv[1] if len(sys.argv) > 1 else "assets/audio/sfx"
rng = np.random.default_rng(77)

def save(name, x, peak=0.85):
    x = x / max(1e-6, np.max(np.abs(x))) * peak
    with wave.open(f"{OUT}/{name}.wav", "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())

def band(x, lo, hi):
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    f[(fr < lo) | (fr > hi)] = 0
    return np.fft.irfft(f, len(x))

# the drill: a motor whine (whole cycles in the loop, so it doesn't click) with grinding noise that chatters
n = SR * 2
t = np.arange(n) / SR
whine = sum(np.sin(2 * np.pi * f * t) * a for f, a in [(220, 0.5), (440, 0.35), (660, 0.2), (1320, 0.08)])
grind = band(rng.normal(size=n), 900, 5200)
chatter = 0.55 + 0.45 * np.sin(2 * np.pi * 18 * t) ** 2       # (18 Hz: the bit catching on the steel)
wobble = 1.0 + 0.08 * np.sin(2 * np.pi * 1.5 * t)
drill = whine * 0.55 * wobble + grind * chatter * 0.9
save("drill", drill, 0.7)

# the safe door: a deep clunk (the bolts going), then a slow creaking hinge
n = int(SR * 1.6)
t = np.arange(n) / SR
f = 70 + 90 * np.exp(-t / 0.05)
clunk = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.18)
clank = band(rng.normal(size=n), 1500, 6000) * np.exp(-t / 0.04) * 0.6
cr_f = 330 + 120 * np.sin(2 * np.pi * 0.9 * t)
creak = np.sign(np.sin(2 * np.pi * np.cumsum(cr_f) / SR)) * 0.12
creak = band(creak, 200, 2500) * np.clip((t - 0.25) * 3, 0, 1) * np.exp(-np.clip(t - 0.9, 0, None) / 0.25)
save("safe_open", clunk + clank + creak)

# cash: a quick riffle of notes, a soft ring
n = int(SR * 0.45)
t = np.arange(n) / SR
riffle = band(rng.normal(size=n), 2000, 8000) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 34 * t))) * np.exp(-t / 0.12)
ring = (np.sin(2 * np.pi * 1568 * t) + 0.6 * np.sin(2 * np.pi * 2349 * t)) * np.exp(-t / 0.15) * 0.35
save("cash", riffle * 0.7 + ring)
print("heist sounds written")

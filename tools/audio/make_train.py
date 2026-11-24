"""Train sounds for the railway (synthesized, no samples): a rumble with the clickety-clack of the wheels
over the rail joints (a seamless 2 s loop), and a two-tone horn.
    python3 tools/audio/make_train.py [out_dir]   (default assets/audio/sfx)"""
import sys, wave
import numpy as np

SR = 22050
OUT = sys.argv[1] if len(sys.argv) > 1 else "assets/audio/sfx"
rng = np.random.default_rng(5)

def save(name, x):
    x = x / max(1e-6, np.max(np.abs(x))) * 0.85
    with wave.open(f"{OUT}/{name}.wav", "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())

def lowpass(x, hz):
    # one-pole, run twice (forward then backward: no phase lag)
    a = np.exp(-2 * np.pi * hz / SR)
    y = np.zeros_like(x); acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc; y[i] = acc
    acc = 0.0
    for i in range(len(x) - 1, -1, -1):
        acc = (1 - a) * y[i] + a * acc; y[i] = acc
    return y

def loop():
    n = SR * 2
    t = np.arange(n) / SR
    # rumble: low noise, wrapped so the loop has no seam
    noise = rng.standard_normal(n + SR)
    rum = lowpass(noise, 70.0)
    rum = rum[:n] * np.linspace(1, 0, n) ** 0 
    fade = SR // 4
    rum[:fade] = rum[:fade] * np.linspace(0, 1, fade) + lowpass(noise, 70.0)[n:n + fade] * np.linspace(1, 0, fade)
    rum += 0.35 * np.sin(2 * np.pi * 41 * t) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.5 * t))
    # clickety-clack: a bogie's two axles over a rail joint, twice a second-ish
    clack = np.zeros(n)
    for start in (0.05, 0.19, 1.02, 1.16):
        i = int(start * SR)
        k = np.arange(int(0.09 * SR))
        burst = rng.standard_normal(len(k)) * np.exp(-k / (0.012 * SR))
        ring = np.sin(2 * np.pi * 180 * k / SR) * np.exp(-k / (0.03 * SR))
        clack[i:i + len(k)] += lowpass(burst, 1400.0) * 1.8 + ring * 0.6
    return rum / np.max(np.abs(rum)) * 0.7 + clack / np.max(np.abs(clack)) * 0.55

def horn():
    dur = 1.7
    n = int(SR * dur)
    t = np.arange(n) / SR
    env = np.minimum(1, t / 0.06) * np.minimum(1, (dur - t) / 0.25)
    x = np.zeros(n)
    for f in (277.0, 349.0, 415.0):            # a soft chord (C#, F, G#)
        vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * t)
        ph = 2 * np.pi * np.cumsum(f * vib) / SR
        for h, amp in ((1, 1.0), (2, 0.45), (3, 0.25), (4, 0.12)):
            x += amp * np.sin(h * ph)
    x = np.tanh(x * 0.6) * env
    # a second short toot
    gap = np.zeros(int(0.12 * SR))
    n2 = int(SR * 0.6)
    t2 = np.arange(n2) / SR
    e2 = np.minimum(1, t2 / 0.05) * np.minimum(1, (0.6 - t2) / 0.15)
    y = np.zeros(n2)
    for f in (277.0, 349.0, 415.0):
        ph = 2 * np.pi * f * t2
        for h, amp in ((1, 1.0), (2, 0.45), (3, 0.25)):
            y += amp * np.sin(h * ph)
    y = np.tanh(y * 0.6) * e2
    return np.concatenate([y, gap, x])

save("train_loop", loop())
save("train_horn", horn())
print("ok")

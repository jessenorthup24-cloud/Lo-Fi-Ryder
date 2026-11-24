"""Police sounds (synthesized, no samples): a short radio chirp (a squelch and a two-note beep, for when
the wanted stars change) and the police helicopter's rotor (a seamless 2 s loop: blade thwop over a
turbine whine).
    python3 tools/audio/make_police.py [out_dir]   (default assets/audio/sfx)"""
import sys, wave
import numpy as np

SR = 22050
OUT = sys.argv[1] if len(sys.argv) > 1 else "assets/audio/sfx"
rng = np.random.default_rng(9)

def save(name, x, peak=0.85):
    x = x / max(1e-6, np.max(np.abs(x))) * peak
    with wave.open(f"{OUT}/{name}.wav", "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())

def bandpass(x, lo, hi):
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    f[(fr < lo) | (fr > hi)] = 0
    return np.fft.irfft(f, len(x))

def chirp():
    # squelch: a burst of radio hiss, then two short beeps, all through a narrow "radio" band
    n1 = int(0.07 * SR)
    hiss = rng.standard_normal(n1) * np.exp(-np.arange(n1) / (0.025 * SR))
    gap = np.zeros(int(0.02 * SR))
    def beep(f, d):
        n = int(d * SR); t = np.arange(n) / SR
        env = np.minimum(1, t / 0.004) * np.minimum(1, (d - t) / 0.01)
        return np.sign(np.sin(2 * np.pi * f * t)) * 0.35 * env
    x = np.concatenate([hiss * 0.6, gap, beep(1320, 0.06), np.zeros(int(0.025 * SR)), beep(990, 0.08), np.zeros(int(0.05 * SR))])
    tail = rng.standard_normal(int(0.05 * SR)) * np.exp(-np.arange(int(0.05 * SR)) / (0.012 * SR)) * 0.4
    x = np.concatenate([x, tail])
    return bandpass(x, 350, 3200)

def rotor():
    n = SR * 2
    t = np.arange(n) / SR
    # blade passes: 12 a second (a whole number in 2 s, so the loop is seamless), each a soft thump of air
    thwop = np.zeros(n)
    k = np.arange(int(0.06 * SR))
    pulse = np.sin(2 * np.pi * 55 * k / SR) * np.exp(-k / (0.018 * SR))
    for i in range(24):
        s = int(i * n / 24)
        amp = 0.85 + 0.15 * rng.random()
        seg = pulse[: min(len(pulse), n - s)]
        thwop[s:s + len(seg)] += seg * amp
    air = bandpass(rng.standard_normal(n), 60, 400) * 0.35
    whine = 0.12 * np.sin(2 * np.pi * 1180 * t) + 0.05 * np.sin(2 * np.pi * 2360 * t)
    x = thwop + air + whine
    return x

save("radio_chirp", chirp(), 0.7)
save("heli_loop", rotor())
print("ok")

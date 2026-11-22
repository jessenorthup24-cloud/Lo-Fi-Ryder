"""Rail grind loop: steel-on-steel scrape with ringing partials and a gritty chatter. Writes grind.wav."""
import numpy as np
import make_vehicle as mv


def main():
    N = int(1.4 * mv.SR)
    # bright scrape: band-passed hiss
    hiss = mv.noise_loop(1.4, lambda n: mv.resp(n, peaks=[(3200, 1.5, 4), (5200, 2.0, 3)], lp=9000, hp=1400))
    # ringing metal: inharmonic, narrow partials excited by the noise
    ring = mv.noise_loop(1.4, lambda n: mv.resp(n, peaks=[(1180, 60, 30), (2760, 70, 24), (4310, 80, 18), (6020, 90, 12)], hp=700))
    # chatter: the trucks skipping along the rail
    chat = mv.clicks(N, 95, 0.004, 7000, 900)
    t = np.arange(N) / mv.SR
    wob = 1.0 + 0.18 * np.sin(2 * np.pi * 5.0 * t) + 0.1 * np.sin(2 * np.pi * 11.0 * t)
    x = hiss / np.std(hiss) * 0.5 * wob + ring / np.std(ring) * 0.35 + chat / (np.std(chat) + 1e-9) * 0.3
    mv.write("grind", np.tanh(x * 0.7))


if __name__ == "__main__":
    main()

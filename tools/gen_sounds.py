"""Generates the game's sound effects into audio/ (16-bit mono WAV, 44.1 kHz).

Everything is synthesized from noise and oscillators so there are no outside
assets to license. Re-run after tweaking:  python3 tools/gen_sounds.py
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
rng = np.random.default_rng(7)


def t(sec):
    return np.arange(int(sec * SR)) / SR


def biquad(x, kind, f, q=0.7, gain_db=0.0):
    """RBJ cookbook biquad, run sample by sample (clips are short)."""
    w = 2 * np.pi * f / SR
    a = np.sin(w) / (2 * q)
    c = np.cos(w)
    if kind == "lp":
        b = [(1 - c) / 2, 1 - c, (1 - c) / 2]
        aa = [1 + a, -2 * c, 1 - a]
    elif kind == "hp":
        b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
        aa = [1 + a, -2 * c, 1 - a]
    elif kind == "bp":
        b = [a, 0, -a]
        aa = [1 + a, -2 * c, 1 - a]
    else:
        raise ValueError(kind)
    b = np.array(b) / aa[0]
    a1, a2 = aa[1] / aa[0], aa[2] / aa[0]
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    b0, b1, b2 = b
    for i in range(len(x)):
        xi = x[i]
        yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, xi, y1, yi
        y[i] = yi
    return y


def env(n, attack, decay_tau):
    """Fast attack, exponential decay envelope, both in seconds."""
    tt = np.arange(n) / SR
    e = np.exp(-np.maximum(tt - attack, 0) / decay_tau)
    a = int(attack * SR)
    if a > 0:
        e[:a] = np.linspace(0, 1, a)
    return e


def noise(sec):
    return rng.standard_normal(int(sec * SR))


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def fade(x, ms=8):
    n = int(ms / 1000 * SR)
    x = x.copy()
    x[:n] *= np.linspace(0, 1, n)
    x[-n:] *= np.linspace(1, 0, n)
    return x


def save(name, x, peak=0.9, loop=False):
    x = norm(x, peak)
    if not loop:
        x = fade(x, 3)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", name)


def loopable(x, xfade_sec=0.5):
    """Crossfade the tail into the head so the clip loops without a click."""
    n = int(xfade_sec * SR)
    head, body, tail = x[:n], x[n:-n], x[-n:]
    ramp = np.linspace(0, 1, n)
    return np.concatenate([body, tail * (1 - ramp) + head * ramp])


# --- Body on the mat -------------------------------------------------------

def mat_slap(i):
    """A hand or arm slapping vinyl: bright crack plus a short low thump."""
    d = 0.35
    crack = biquad(noise(d), "bp", 2400 + 500 * i, 0.9) * env(int(d * SR), 0.001, 0.018)
    body = biquad(noise(d), "lp", 500, 0.8) * env(int(d * SR), 0.002, 0.05)
    thump = np.sin(2 * np.pi * (95 + 10 * i) * t(d)) * env(int(d * SR), 0.002, 0.06)
    return crack * 1.0 + body * 1.4 + thump * 0.8


def body_thud(i):
    """A torso landing: big low thump, a mat 'whump' and a little slap on top."""
    d = 0.7
    n = int(d * SR)
    f = 62 + 8 * i
    sweep = np.sin(2 * np.pi * np.cumsum(np.linspace(f * 1.6, f, n)) / SR) * env(n, 0.003, 0.14)
    whump = biquad(noise(d), "lp", 280, 0.9) * env(n, 0.004, 0.12)
    slap = biquad(noise(d), "bp", 1800, 0.8) * env(n, 0.001, 0.02)
    return sweep * 1.3 + whump * 2.2 + slap * 0.5


def step(i):
    """Bare foot on the mat: soft and short."""
    d = 0.22
    n = int(d * SR)
    pat = biquad(noise(d), "bp", 900 + 150 * i, 1.0) * env(n, 0.002, 0.025)
    low = np.sin(2 * np.pi * (120 + 15 * i) * t(d)) * env(n, 0.002, 0.03)
    squeak = np.sin(2 * np.pi * (2600 + 300 * i) * t(d)) * env(n, 0.01, 0.015) * (0.15 if i % 2 else 0.0)
    return pat + low * 0.6 + squeak


# --- Gi ------------------------------------------------------------------

def gi_rustle_loop():
    """Cotton brushing on cotton. The game turns its volume up with limb speed."""
    d = 4.5
    n = int(d * SR)
    base = biquad(biquad(noise(d), "hp", 900, 0.7), "lp", 5200, 0.7)
    # Lumpy amplitude so it sounds like cloth moving rather than hiss.
    lumps = np.abs(biquad(noise(d), "lp", 9, 0.7))
    lumps = lumps / lumps.max()
    crinkle = (rng.random(n) < 0.0009).astype(float)
    crinkle = biquad(crinkle, "bp", 3500, 2.0) * 12
    return loopable(base * (0.25 + lumps) + crinkle)


def grip_snap(i):
    """Grabbing a collar or sleeve: a short fabric snap."""
    d = 0.25
    n = int(d * SR)
    snap = biquad(noise(d), "bp", 1500 + 400 * i, 1.4) * env(n, 0.0015, 0.03)
    rasp = biquad(noise(d), "hp", 3000, 0.7) * env(n, 0.004, 0.05) * 0.4
    return snap + rasp


# --- Voice (goofy, synthesized) --------------------------------------------

def formant_voice(d, f0_start, f0_end, formants, breath=0.15, vibrato=0.0):
    n = int(d * SR)
    f0 = np.linspace(f0_start, f0_end, n) * (1 + vibrato * np.sin(2 * np.pi * 6 * t(d)))
    phase = np.cumsum(f0) / SR
    src = 2 * (phase % 1.0) - 1  # sawtooth glottal source
    src = src + breath * noise(d)
    out = np.zeros(n)
    for f, q, g in formants:
        out += biquad(src, "bp", f, q) * g
    return out


def grunt(i):
    """Effort grunts: short 'hngh' / 'ugh' sounds with a falling pitch."""
    vowels = [
        [(600, 6, 1.0), (1000, 7, 0.6), (2400, 9, 0.2)],   # 'uh'
        [(400, 6, 1.0), (800, 7, 0.5), (2300, 9, 0.15)],   # 'oh'
        [(700, 6, 1.0), (1200, 8, 0.6), (2500, 9, 0.2)],   # 'ah'
        [(300, 5, 1.0), (2200, 8, 0.35), (2900, 9, 0.2)],  # 'eh' nasal
        [(500, 6, 1.0), (900, 7, 0.55), (2500, 9, 0.2)],
    ]
    d = 0.28 + 0.06 * (i % 3)
    n = int(d * SR)
    f0 = 135 + 18 * i
    v = formant_voice(d, f0 * 1.15, f0 * 0.8, vowels[i % len(vowels)], breath=0.25)
    e = env(n, 0.02, d * 0.35)
    return v * e


def oof(i):
    """Getting the wind knocked out: a quick 'oof' with a pitch dip."""
    d = 0.32
    n = int(d * SR)
    f0 = 160 + 20 * i
    v = formant_voice(d, f0 * 1.3, f0 * 0.75, [(450, 6, 1.0), (850, 7, 0.5), (2400, 9, 0.15)], breath=0.4)
    puff = biquad(noise(d), "bp", 700, 1.0) * env(n, 0.002, 0.04)
    return v * env(n, 0.006, 0.09) + puff * 0.5


def exhale(i):
    """Tensing up: a breathy 'hhhh' through the teeth."""
    d = 0.6
    n = int(d * SR)
    hiss = biquad(noise(d), "bp", 2200 + 300 * i, 1.6)
    sh = biquad(noise(d), "bp", 4500, 2.0) * 0.5
    e = np.sin(np.linspace(0, np.pi, n)) ** 1.5
    return (hiss + sh) * e


def yelp():
    """A goofy falling yelp, for big falls."""
    d = 0.5
    n = int(d * SR)
    v = formant_voice(d, 330, 170, [(750, 6, 1.0), (1250, 8, 0.6), (2600, 9, 0.2)], breath=0.15, vibrato=0.04)
    return v * env(n, 0.02, 0.2)


# --- Referee and rooms ----------------------------------------------------

def whistle():
    """Referee whistle: two short blasts with the pea's trill."""
    def blast(d):
        n = int(d * SR)
        trill = 1 + 0.5 * (np.sin(2 * np.pi * 38 * t(d)) > 0)
        tone = np.sin(2 * np.pi * 2950 * t(d)) + 0.3 * np.sin(2 * np.pi * 5900 * t(d))
        air = biquad(noise(d), "bp", 3000, 3.0) * 0.4
        e = np.minimum(np.linspace(0, 30, n), 1) * np.minimum(np.linspace(30, 0, n), 1)
        return (tone * trill + air) * e
    gap = np.zeros(int(0.08 * SR))
    return np.concatenate([blast(0.18), gap, blast(0.42)])


def clap_one():
    d = 0.12
    n = int(d * SR)
    return biquad(noise(d), "bp", 1100 + rng.random() * 900, 1.2) * env(n, 0.001, 0.012)


def crowd_loop():
    """Arena crowd murmur: many band-passed babbling voices."""
    d = 10.0
    n = int(d * SR)
    out = np.zeros(n)
    for _ in range(14):
        f = rng.uniform(350, 1100)
        voice = biquad(noise(d), "bp", f, 3.0)
        syll = np.abs(biquad(noise(d), "lp", rng.uniform(2, 5), 0.7))
        out += voice * (syll / syll.max()) ** 1.5
    out += biquad(noise(d), "lp", 400, 0.7) * 0.6
    return loopable(out, 1.0)


def cheer():
    """Crowd reaction: a swell of voices and claps."""
    d = 2.6
    n = int(d * SR)
    swell = np.sin(np.linspace(0, np.pi, n)) ** 0.7
    voices = np.zeros(n)
    for _ in range(18):
        f = rng.uniform(400, 1400)
        voices += biquad(noise(d), "bp", f, 4.0)
    claps = np.zeros(n)
    for _ in range(90):
        c = clap_one()
        s = rng.integers(0, n - len(c))
        claps[s:s + len(c)] += c * rng.uniform(0.3, 1.0)
    return voices * swell + claps * swell * 0.8


def hvac_loop():
    """Academy room tone: air handler hum and a soft fan."""
    d = 8.0
    hum = np.sin(2 * np.pi * 60 * t(d)) * 0.3 + np.sin(2 * np.pi * 120 * t(d)) * 0.15
    air = biquad(noise(d), "lp", 700, 0.6)
    wobble = 1 + 0.15 * np.sin(2 * np.pi * 0.25 * t(d))
    return loopable(hum + air * wobble * 1.2, 1.0)


def garage_loop():
    """Garage room tone: a box fan, a buzzing bulb and rain on the roof."""
    d = 8.0
    n = int(d * SR)
    fan = biquad(noise(d), "lp", 900, 0.6) * (1 + 0.25 * np.sin(2 * np.pi * 14 * t(d)))
    buzz = np.sign(np.sin(2 * np.pi * 120 * t(d))) * 0.04
    buzz = biquad(buzz, "lp", 1500, 0.7)
    drops = (rng.random(n) < 0.004).astype(float) * rng.uniform(0.2, 1.0, n)
    rain = biquad(drops, "bp", 2500, 1.0) * 6 + biquad(noise(d), "hp", 3000, 0.7) * 0.25
    return loopable(fan * 0.8 + buzz + rain, 1.0)


def main():
    os.makedirs(OUT, exist_ok=True)
    for i in range(4):
        save("mat_slap_%d" % i, mat_slap(i), 0.85)
        save("step_%d" % i, step(i), 0.5)
    for i in range(3):
        save("body_thud_%d" % i, body_thud(i), 0.95)
        save("grip_snap_%d" % i, grip_snap(i), 0.6)
        save("exhale_%d" % i, exhale(i), 0.4)
        save("oof_%d" % i, oof(i), 0.8)
    for i in range(5):
        save("grunt_%d" % i, grunt(i), 0.7)
    save("yelp", yelp(), 0.75)
    save("gi_rustle_loop", gi_rustle_loop(), 0.5, loop=True)
    save("whistle", whistle(), 0.6)
    save("cheer", cheer(), 0.8)
    save("crowd_loop", crowd_loop(), 0.5, loop=True)
    save("hvac_loop", hvac_loop(), 0.35, loop=True)
    save("garage_loop", garage_loop(), 0.4, loop=True)


if __name__ == "__main__":
    main()

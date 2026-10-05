#!/usr/bin/env python3
"""Synthesizes every sound in the game (no samples, no licences).

    python3 tools/make_sounds.py        # needs numpy + ffmpeg
    -> assets/sounds/*.ogg

Each crime-scene theme gets:
  amb_<scene>.ogg    a 10 s seamless loop: a low "mystery" bed + sounds that belong to the place
  sting_<scene>.ogg  a short mystery hit that plays when the case file opens
Plus interface sounds (tap, stamp, paper, clue, reveal, wrong, win, lose, heartbeat) and a home loop.
"""
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

SR = 22050
LOOP = 10.0
N = int(SR * LOOP)
OUT = Path(__file__).resolve().parent.parent / "assets" / "sounds"
T = np.arange(N) / SR


# ------------------------------------------------------------------ building blocks
def rng(seed):
    return np.random.default_rng(seed)


def band_noise(seed, lo, hi, n=N):
    """Band-limited noise built in the frequency domain: periodic, so it loops with no seam."""
    spec = np.zeros(n // 2 + 1, dtype=complex)
    f = np.fft.rfftfreq(n, 1 / SR)
    mask = (f >= lo) & (f <= hi)
    r = rng(seed)
    spec[mask] = r.normal(size=mask.sum()) + 1j * r.normal(size=mask.sum())
    x = np.fft.irfft(spec, n)
    return x / (np.max(np.abs(x)) + 1e-9)


def periodic_freq(f, loop=LOOP):
    """Round a frequency so a whole number of cycles fits in the loop."""
    return max(1, round(f * loop)) / loop


def sine(f, n=N, phase=0.0):
    return np.sin(2 * np.pi * f * np.arange(n) / SR + phase)


def lfo(rate, depth=1.0, offset=0.0, phase=0.0):
    r = periodic_freq(rate)
    return offset + depth * np.sin(2 * np.pi * r * T + phase)


def env_ad(n, a, d):
    """Fast attack, exponential decay (seconds)."""
    t = np.arange(n) / SR
    return np.minimum(1, t / max(a, 1e-4)) * np.exp(-t / d)


def put(buf, sig, at, gain=1.0):
    """Mix `sig` into the loop at time `at`, wrapping around the end so loops stay seamless."""
    i = int(at * SR) % len(buf)
    m = len(sig)
    first = min(m, len(buf) - i)
    buf[i:i + first] += gain * sig[:first]
    if first < m:
        buf[:m - first] += gain * sig[first:]


def release(x, secs=0.05):
    """Raised-cosine fade at the end, so a cut-off tail never clicks."""
    m = min(len(x), int(secs * SR))
    if m > 1:
        x = x.copy()
        x[-m:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, m))
    return x


def bell(f, dur=3.0, partials=(1, 2.01, 2.76, 4.07, 5.43), decay=1.2, gain=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k, p in enumerate(partials):
        out += (1 / (1 + k * 0.7)) * np.sin(2 * np.pi * f * p * t) * np.exp(-t / (decay / (1 + 0.5 * k)))
    return release(gain * out * np.minimum(1, t / 0.004))


def pluck(f, dur=1.2, bright=0.5):
    """Plucked string (Karplus-Strong)."""
    n = int(dur * SR)
    p = int(SR / f)
    buf = rng(int(f)).uniform(-1, 1, p)
    out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % p]
        buf[i % p] = (buf[i % p] + buf[(i + 1) % p]) * (0.5 * (0.996 - 0.01 * (1 - bright)))
    return release(out)


def click(dur=0.02, f=2500, gain=1.0, seed=1):
    n = int(dur * SR)
    t = np.arange(n) / SR
    return gain * (rng(seed).normal(size=n) * 0.6 + np.sin(2 * np.pi * f * t)) * np.exp(-t / (dur / 4))


def thud(f=70, dur=0.5, gain=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    fr = f * (1 + 2.0 * np.exp(-t / 0.04))
    return release(gain * np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-t / (dur / 4)))


def swish(dur=0.5, lo=800, hi=5000, seed=3, gain=1.0):
    n = int(dur * SR)
    x = band_noise(seed, lo, hi, n)
    t = np.arange(n) / SR
    return gain * x * np.sin(np.pi * t / dur) ** 2


def reverb(x, secs=1.6, wet=0.35, seed=5):
    """Cheap room: convolve with decaying noise (circular, so loops stay seamless)."""
    n = len(x)
    ir = rng(seed).normal(size=int(secs * SR)) * np.exp(-np.arange(int(secs * SR)) / (secs * SR / 5))
    ir[0] = 0
    ir /= np.sqrt(np.sum(ir ** 2))
    L = n + len(ir)
    y = np.fft.irfft(np.fft.rfft(x, L) * np.fft.rfft(ir, L), L)
    wrapped = y[:n].copy()
    wrapped[:len(y) - n] += y[n:]
    return (1 - wet) * x + wet * wrapped


def one_shot_reverb(x, secs=1.4, wet=0.3, tail=1.4):
    """Reverb for one-shots: pad with silence first so the echo never wraps to the start."""
    y = reverb(np.concatenate([x, np.zeros(int(tail * SR))]), secs, wet)
    return release(y, 0.3)


def lowpass(x, fc):
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    spec[f > fc] = 0
    return np.fft.irfft(spec, len(x))


def highpass(x, fc):
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    spec[f < fc] = 0
    return np.fft.irfft(spec, len(x))


# ------------------------------------------------------------------ the mystery bed (shared)
def mystery_bed(root=55.0, minor=True, eerie=True, seed=11):
    """Low drone with a slow pulse, a dissonant overtone that breathes, and one ghostly glide."""
    third = 1.189 if minor else 1.26
    root *= 2  # an octave up: phone speakers can play it and earbuds don't throb
    out = np.zeros(N)
    for ratio, amp in ((1, 0.5), (1.5, 0.28), (third * 2, 0.16)):
        f = periodic_freq(root * ratio)
        out += amp * sine(f) * (0.75 + 0.25 * lfo(0.2 + 0.1 * ratio, phase=ratio))
    out += 0.02 * sine(periodic_freq(root * 2.06)) * (0.5 + 0.5 * lfo(0.3))  # a little unease
    out *= 0.8 + 0.2 * lfo(0.1, phase=2.0)
    if eerie:
        # theremin-like glide, once per loop
        n = int(3.2 * SR)
        t = np.arange(n) / SR
        f = root * 4 * (1 + 0.5 * np.sin(np.pi * t / 3.2) ** 1.3) + 4 * np.sin(2 * np.pi * 5.5 * t)
        g = 0.06 * np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / 3.2) ** 2
        put(out, g, 3.1 + (seed % 3))
    return out


# ------------------------------------------------------------------ scenes
def a_bazaar():
    x = mystery_bed(49, seed=1) * 0.8
    x += 0.05 * band_noise(2, 300, 1200) * (0.5 + 0.5 * lfo(0.3))                  # night wind in the arches
    scale = [146.8, 155.6, 185.0, 196.0, 220.0, 233.1, 261.6]                       # Hijaz colour
    for at, i in ((0.5, 0), (1.4, 3), (2.1, 2), (3.9, 4), (4.6, 1), (5.4, 2), (6.2, 0), (8.2, 4), (8.9, 3)):
        put(x, pluck(scale[i], 1.4), at, 0.28)
    for at in (2.9, 7.0, 9.3):                                                     # shutters rattling
        for k in range(6):
            put(x, click(0.03, 1800 + 300 * k, 1, seed=k + int(at * 7)), at + k * 0.045, 0.16)
    put(x, band_noise(5, 90, 260, int(1.4 * SR)) * np.sin(np.linspace(0, np.pi, int(1.4 * SR))), 6.6, 0.12)
    return reverb(x, 1.3, 0.28)


def a_office():
    x = mystery_bed(55, seed=2) * 0.5
    hum = sum(sine(periodic_freq(100 * k)) / k for k in (1, 2, 3, 5))
    x += 0.08 * hum * (0.8 + 0.2 * lfo(7.0))
    r = rng(4)
    for at in (1.0, 1.15, 1.22, 1.4, 1.5, 1.58, 1.8, 6.0, 6.1, 6.27, 6.4, 6.5):
        put(x, click(0.015, r.uniform(2500, 4000), 1, seed=int(at * 100)), at, 0.12)       # keyboard
    for k in range(10):
        put(x, click(0.012, 900, 1, seed=k), k * 1.0 + 0.5, 0.07)                           # wall clock
    put(x, bell(1244, 1.2, (1, 1.5), 0.3, 0.6), 8.0, 0.06)
    put(x, bell(1244, 1.2, (1, 1.5), 0.3, 0.6), 8.5, 0.06)                                  # far phone
    return reverb(x, 0.8, 0.2)


def a_train():
    x = mystery_bed(46, seed=3) * 0.55
    x += 0.35 * lowpass(band_noise(6, 20, 260), 260) * (0.7 + 0.3 * lfo(0.5))              # rumble
    beat = 0.62
    t = 0.0
    k = 0
    while t < LOOP:
        put(x, lowpass(click(0.045, 1100, 1, seed=k), 2500), t, 0.15)
        put(x, lowpass(click(0.045, 900, 1, seed=k + 99), 2500), t + 0.13, 0.11)
        t += beat
        k += 1
    n = int(2.6 * SR)
    tt = np.arange(n) / SR
    horn = 0.1 * (np.sin(2 * np.pi * 311 * tt) + 0.8 * np.sin(2 * np.pi * 370 * tt)) * np.sin(np.pi * tt / 2.6) ** 2
    put(x, horn, 6.0)
    return reverb(x, 0.5, 0.15)


def a_museum():
    x = mystery_bed(61.7, seed=4) * 0.8
    for f, ph in ((220, 0), (277.2, 1), (329.6, 2), (415.3, 3)):
        x += 0.035 * sine(periodic_freq(f)) * (0.6 + 0.4 * lfo(0.15 + 0.03 * ph, phase=ph)) * (1 + 0.004 * lfo(5.5))
    r = rng(8)
    for at in (1.0, 2.1, 3.2, 4.4, 6.5, 7.6, 8.7):                                          # slow footsteps
        put(x, click(0.05, 400, 1, seed=int(at * 10)) * 1.0, at, 0.35 + 0.1 * r.random())
    for at in (2.5, 8.1):
        put(x, bell(1760, 1.4, (1, 2.4), 0.25, 0.7), at, 0.07)                              # drip
    return reverb(x, 2.4, 0.5)


def a_villa():
    x = mystery_bed(55, seed=5) * 0.6
    rain = band_noise(9, 400, 4000) * (0.8 + 0.2 * band_noise(10, 1, 9)[:N])
    x += 0.07 * rain
    x += 0.08 * band_noise(12, 300, 1500) * (0.5 + 0.5 * lfo(0.2))
    # distant thunder
    n = int(3.8 * SR)
    th = lowpass(band_noise(13, 20, 200, n), 150) * np.exp(-np.arange(n) / SR / 1.4) * np.minimum(1, np.arange(n) / (0.25 * SR))
    put(x, 1.6 * th, 4.3)
    for at in (1.6, 6.9):
        put(x, bell(220, 1.0, (1, 2.7), 0.3, 0.5), at, 0.04)                                # creaking wood tone
    return reverb(x, 1.0, 0.18)


def a_warehouse():
    x = mystery_bed(43.7, seed=6) * 0.55
    x += 0.2 * lowpass(band_noise(14, 30, 300), 300) * (0.8 + 0.2 * lfo(0.3))               # fire roar
    r = rng(15)
    for at in np.sort(r.uniform(0, LOOP, 70)):                                              # crackle
        put(x, click(r.uniform(0.004, 0.02), r.uniform(900, 3000), 1, seed=int(at * 1000)), at, r.uniform(0.1, 0.5))
    n = int(1.8 * SR)
    tt = np.arange(n) / SR
    creak = 0.08 * np.sin(2 * np.pi * np.cumsum(180 + 120 * np.sin(2 * np.pi * 1.7 * tt) * tt / 1.8) / SR) * np.sin(np.pi * tt / 1.8) ** 2
    put(x, creak, 5.5)
    return reverb(x, 1.8, 0.3)


def a_harbor():
    x = mystery_bed(49, seed=7) * 0.6
    wave = lowpass(band_noise(16, 40, 900), 900)
    x += 0.4 * wave * (0.45 + 0.55 * np.sin(2 * np.pi * periodic_freq(0.2) * T) ** 2)       # swell
    for at in (1.0, 5.2):
        put(x, bell(587, 4.0, (1, 2.4, 4.1), 1.8, 1.0), at, 0.12)                           # buoy
    for k, at in enumerate((3.0, 3.5, 7.7)):
        put(x, 0.5 * band_noise(17 + k, 100, 600, int(0.5 * SR)) * np.sin(np.linspace(0, np.pi, int(0.5 * SR))), at, 0.18)
    return reverb(x, 1.4, 0.25)


def a_hospital():
    x = mystery_bed(58, seed=8) * 0.45
    x += 0.04 * band_noise(18, 80, 400) * 1.0
    beep = 0.5 * sine(880, int(0.04 * SR)) * np.hanning(int(0.04 * SR))
    for k in range(10):
        put(x, beep, k * 1.0 + 0.2, 0.07)                                                   # heart monitor, soft
    for at in (4.0, 4.3):
        put(x, 0.5 * sine(1500, int(0.16 * SR)) * np.hanning(int(0.16 * SR)), at, 0.12)
    put(x, band_noise(19, 800, 3000, int(1.6 * SR)) * np.sin(np.linspace(0, np.pi, int(1.6 * SR))), 7.0, 0.05)  # trolley
    return reverb(x, 1.1, 0.25)


def a_library():
    x = mystery_bed(50, seed=9) * 0.7
    for k in range(10):
        put(x, click(0.012, 700, 1, seed=k + 3), k * 1.0 + 0.3, 0.1 if k % 2 else 0.14)    # old clock
    for at in (2.2, 5.9, 8.3):
        put(x, swish(0.55, 1500, 6000, seed=int(at * 10)), at, 0.12)                        # page turns
    put(x, bell(130.8, 3.2, (1, 2, 3.01), 1.4, 0.5), 0.2, 0.05)
    return reverb(x, 2.0, 0.45)


def a_theater():
    x = mystery_bed(55, seed=10) * 0.7
    for at in (1.0, 6.5):
        put(x, swish(1.2, 200, 2500, seed=int(at * 10)), at, 0.16)                           # curtain
    for f, d in ((440, 0), (441.5, 1), (438.8, 2)):
        x += 0.02 * sine(periodic_freq(f)) * (0.5 + 0.5 * lfo(0.2, phase=d))                 # orchestra tuning
    for k in range(4):
        put(x, thud(55, 0.35, 1), 8.0 + k * 0.0 + (0.0 if k % 2 == 0 else 0.35) + (0 if k < 2 else 0), 0.05)
    n = int(1.2 * SR)
    tt = np.arange(n) / SR
    put(x, 0.12 * np.sin(2 * np.pi * np.cumsum(120 + 40 * tt) / SR) * np.sin(np.pi * tt / 1.2) ** 2, 3.6)  # floorboard
    return reverb(x, 2.2, 0.5)


def a_hotel():
    x = mystery_bed(52, seed=11) * 0.55
    x += 0.05 * band_noise(21, 60, 300)                                                     # air conditioning
    put(x, bell(880, 1.4, (1, 2), 0.5, 0.7), 2.0, 0.1)
    put(x, bell(659, 1.6, (1, 2), 0.6, 0.7), 2.45, 0.1)                                     # lift ding
    for k, f in enumerate((233.1, 277.2, 220.0)):
        put(x, pluck(f, 2.4, 0.2), 5.0 + k * 1.1, 0.12)                                     # piano from the bar, far away
    for at in (7.2, 7.6, 8.0, 8.4):
        put(x, click(0.04, 300, 1, seed=int(at * 10)), at, 0.12)
    return reverb(x, 1.6, 0.4)


def a_kitchen():
    x = mystery_bed(55, seed=12) * 0.35
    x += 0.05 * band_noise(22, 1500, 5000) * (0.6 + 0.4 * band_noise(23, 2, 14))  # sizzle
    for at in np.arange(0.5, 10, 0.25):
        if rng(int(at * 100)).random() < 0.55:
            put(x, click(0.012, 1400, 1, seed=int(at * 100)), at, 0.3)                      # chopping
    put(x, bell(2200, 0.6, (1, 1.5), 0.3, 0.6), 7.0, 0.09)                                  # lid clink
    return reverb(x, 0.6, 0.18)


def a_snow():
    x = mystery_bed(46, seed=13) * 0.6
    howl = band_noise(24, 250, 900)
    x += 0.2 * howl * (0.4 + 0.6 * np.sin(2 * np.pi * periodic_freq(0.1) * T) ** 2)
    x += 0.05 * band_noise(25, 1500, 4500) * (0.5 + 0.5 * lfo(0.3))
    r = rng(26)
    for at in np.sort(r.uniform(0, LOOP, 16)):
        put(x, click(0.01, 1100, 1, seed=int(at * 1000)), at, 0.18)                          # fireplace
    n = int(1.0 * SR)
    tt = np.arange(n) / SR
    put(x, 0.1 * np.sin(2 * np.pi * np.cumsum(90 + 50 * tt) / SR) * np.sin(np.pi * tt) ** 2, 5.4)
    return reverb(x, 1.5, 0.3)


def a_desert():
    x = mystery_bed(49, seed=14) * 0.65
    x += 0.07 * band_noise(27, 200, 1500) * (0.35 + 0.65 * np.sin(2 * np.pi * periodic_freq(0.15) * T) ** 2)
    for at in (1.5, 3.0, 4.6, 6.8, 8.4):
        put(x, bell(1568 + 40 * (at % 2), 2.0, (1, 2.4), 0.8, 0.5), at, 0.03)               # camel bell
    for at, f in ((2.2, 146.8), (3.4, 164.8), (6.0, 174.6), (7.5, 146.8)):
        put(x, pluck(f, 2.0), at, 0.2)                                                      # lute
    return reverb(x, 1.8, 0.35)


def a_subway():
    x = mystery_bed(55, seed=15) * 0.55
    n = int(5.0 * SR)
    tt = np.arange(n) / SR
    e = np.sin(np.pi * tt / 5.0) ** 2
    rumble = lowpass(band_noise(28, 20, 350, n), 350) * e
    squeal = 0.05 * np.sin(2 * np.pi * np.cumsum(2800 + 400 * np.sin(2 * np.pi * 0.5 * tt)) / SR) * (e ** 6)
    put(x, 0.9 * rumble + squeal, 2.0)
    for k, f in enumerate((784, 659, 523)):
        put(x, bell(f, 1.0, (1, 2), 0.35, 0.7), 8.4 + k * 0.28, 0.09)
    for at in (0.9, 1.8):
        put(x, bell(2400, 0.7, (1, 1.5), 0.2, 0.5), at, 0.04)
    return reverb(x, 2.0, 0.4)


def a_lab():
    x = mystery_bed(58, seed=16) * 0.45
    x += 0.07 * band_noise(29, 50, 250)
    x += 0.04 * sine(periodic_freq(120)) * (0.7 + 0.3 * lfo(2.0))
    r = rng(30)
    for at in np.sort(r.uniform(0, LOOP, 14)):                                              # bubbling
        n = int(0.08 * SR)
        tt = np.arange(n) / SR
        put(x, np.sin(2 * np.pi * np.cumsum(r.uniform(300, 500) * (1 + 6 * tt)) / SR) * np.exp(-tt / 0.03), at, 0.12)
    put(x, 0.5 * sine(1800, int(0.12 * SR)) * np.hanning(int(0.12 * SR)), 5.0, 0.12)
    put(x, 0.5 * sine(1800, int(0.12 * SR)) * np.hanning(int(0.12 * SR)), 5.3, 0.12)
    return reverb(x, 1.2, 0.3)


def a_wedding():
    x = mystery_bed(55, seed=17) * 0.4
    kick = thud(60, 0.28, 1)
    for k in range(20):
        put(x, kick, k * 0.5, 0.3)                                                          # party through the wall
    for k in range(20):
        put(x, lowpass(click(0.06, 700, 1, seed=k), 900), k * 0.5 + 0.25, 0.1)
    x += 0.06 * lowpass(band_noise(31, 200, 1200), 1200)                                    # murmur
    for at in (3.3, 8.2):
        put(x, bell(2637, 0.8, (1, 2.5), 0.3, 0.5), at, 0.06)                               # glass clink
    return reverb(lowpass(x, 3000), 1.0, 0.25)


def a_school():
    x = mystery_bed(50, seed=18) * 0.55
    put(x, bell(1250, 3.5, (1, 2.0), 1.6, 1.0), 1.0, 0.1)                            # echoing bell
    for k in range(10):
        put(x, click(0.012, 800, 1, seed=k + 30), k * 1.0 + 0.4, 0.09)
    r = rng(32)
    for k in range(6):
        put(x, click(0.04, 300, 1, seed=k), 7.2 + k * 0.4, 0.09)
    return reverb(x, 2.4, 0.5)


def a_airport():
    x = mystery_bed(52, seed=19) * 0.45
    x += 0.07 * lowpass(band_noise(33, 100, 700), 700) * (0.6 + 0.4 * lfo(0.2))              # jets far away
    for k, f in enumerate((659, 523, 659)):
        put(x, bell(f, 1.0, (1, 2), 0.4, 0.8), 2.0 + k * 0.5, 0.1)                          # announcement chime
    put(x, band_noise(34, 90, 400, int(2.5 * SR)) * np.sin(np.linspace(0, np.pi, int(2.5 * SR))), 6.0, 0.2)  # suitcase wheels
    x += 0.03 * band_noise(35, 300, 2000)
    return reverb(x, 2.2, 0.4)


def a_tower():
    x = mystery_bed(55, seed=20) * 0.6
    for k in range(20):
        put(x, click(0.02, 1300 if k % 2 == 0 else 1000, 1, seed=k), k * 0.5, 0.2)          # big clock
    put(x, bell(110, 6.0, (1, 2.0, 2.4, 3.0, 4.2), 3.0, 1.0), 5.0, 0.35)                    # the hour
    x += 0.1 * band_noise(36, 300, 1400) * (0.4 + 0.6 * np.sin(2 * np.pi * periodic_freq(0.1) * T) ** 2)
    for at in (1.7, 8.2):
        put(x, swish(0.3, 400, 3000, seed=int(at * 7)), at, 0.12)                           # pigeons
    return reverb(x, 2.8, 0.5)


def a_home():
    """Noir menu loop: a slow minor chord, rain and a far-off piano."""
    x = mystery_bed(55, seed=21, eerie=False) * 0.6
    x += 0.04 * band_noise(37, 300, 4000)
    for k, f in enumerate((220, 261.6, 329.6, 261.6, 196, 233.1, 293.7, 233.1)):
        put(x, pluck(f, 2.2, 0.3), k * 1.25, 0.22)
    return reverb(x, 2.0, 0.45)


SCENES = {
    "bazaar_night": a_bazaar, "office": a_office, "train": a_train, "museum": a_museum, "villa_rain": a_villa,
    "warehouse": a_warehouse, "harbor": a_harbor, "hospital": a_hospital, "library": a_library, "theater": a_theater,
    "hotel": a_hotel, "kitchen": a_kitchen, "snow_lodge": a_snow, "desert": a_desert, "subway": a_subway,
    "lab": a_lab, "wedding": a_wedding, "school": a_school, "airport": a_airport, "tower": a_tower,
}
# a one-shot that belongs to each place; combined with a rising mystery hit for the "case opens" sting
ACCENT = {
    "bazaar_night": lambda: pluck(196, 1.6), "office": lambda: bell(1244, 1.4, (1, 1.5), 0.4),
    "train": lambda: click(0.05, 1000) * 3, "museum": lambda: bell(1760, 2.0, (1, 2.4), 0.8),
    "villa_rain": lambda: band_noise(41, 300, 1500, int(2 * SR)) * np.exp(-np.arange(int(2 * SR)) / SR / 0.6) * 0.8,
    "warehouse": lambda: click(0.2, 700, 1, 4), "harbor": lambda: bell(587, 3.0, (1, 2.4, 4.1), 1.5),
    "hospital": lambda: 0.5 * sine(1000, int(0.4 * SR)) * np.hanning(int(0.4 * SR)),
    "library": lambda: swish(0.6, 1500, 6000), "theater": lambda: swish(1.2, 200, 2500),
    "hotel": lambda: bell(880, 1.4, (1, 2), 0.5), "kitchen": lambda: bell(2200, 0.8, (1, 1.5), 0.3),
    "snow_lodge": lambda: lowpass(band_noise(42, 200, 900, int(2 * SR)), 900) * np.sin(np.linspace(0, np.pi, int(2 * SR))),
    "desert": lambda: bell(1568, 2.0, (1, 2.4), 0.8), "subway": lambda: bell(659, 1.0, (1, 2), 0.4),
    "lab": lambda: 0.5 * sine(1800, int(0.3 * SR)) * np.hanning(int(0.3 * SR)),
    "wedding": lambda: bell(2637, 1.0, (1, 2.5), 0.3), "school": lambda: bell(1250, 2.5, (1, 1.01, 2.0), 1.2),
    "airport": lambda: bell(659, 1.2, (1, 2), 0.5), "tower": lambda: bell(220, 4.0, (1, 2.0, 2.4, 3.0, 4.2), 2.5),
}
ROOT = {s: 49 + 3 * i for i, s in enumerate(SCENES)}


def sting(scene):
    dur = 3.4
    n = int(dur * SR)
    t = np.arange(n) / SR
    root = ROOT[scene]
    riser = np.zeros(n)
    for ratio, amp in ((1, 0.5), (1.189, 0.35), (1.5, 0.3), (2.997, 0.2)):
        f = root * 2 * ratio * (1 + 0.04 * t)
        riser += amp * np.sin(2 * np.pi * np.cumsum(f) / SR)
    riser *= (np.minimum(1, t / 1.8) ** 2) * np.exp(-np.maximum(0, t - 1.9) / 0.9) * 0.22
    hit = thud(root, 1.4, 1.0)
    out = riser
    h = hit[:n - int(1.9 * SR)]
    out[int(1.9 * SR):int(1.9 * SR) + len(h)] += 0.8 * h
    acc = ACCENT[scene]()
    a0 = int(1.9 * SR)
    acc = acc[:n - a0]
    out[a0:a0 + len(acc)] += 0.5 * acc
    return one_shot_reverb(out, 1.8, 0.4, tail=1.6)


# ------------------------------------------------------------------ interface sounds
def ui_sounds():
    s = {}
    n = int(0.08 * SR)
    t = np.arange(n) / SR
    s["tap"] = release((0.7 * np.sin(2 * np.pi * 600 * t) + 0.3 * lowpass(rng(2).normal(size=n), 2500))
                       * np.minimum(1, t / 0.003) * np.exp(-t / 0.018), 0.01)
    s["paper"] = lowpass(swish(0.35, 900, 3500, seed=3, gain=0.5), 3500)
    n = int(0.6 * SR)
    st = thud(95, 0.5, 1.0)
    st = np.concatenate([st, np.zeros(max(0, n - len(st)))])
    st[:int(0.05 * SR)] += 0.8 * swish(0.05, 1000, 6000, seed=4)[:int(0.05 * SR)]
    s["stamp"] = st
    clue = np.zeros(int(2.0 * SR))
    for at, f in ((0.0, 1318.5), (0.12, 1760.0)):
        b = bell(f, 1.6, (1, 2, 3), 0.7, 0.5)
        clue[int(at * SR):int(at * SR) + len(b)] += b
    s["clue"] = clue
    r = rng(7)
    n = int(2.6 * SR)
    t = np.arange(n) / SR
    riser = band_noise(8, 200, 4000, n) * (t / 2.0).clip(0, 1) ** 2 * 0.25
    riser[int(2.0 * SR):] = 0
    hit = np.zeros(n)
    h = thud(50, 0.6, 1.0)
    hit[int(2.0 * SR):int(2.0 * SR) + len(h)] = h[:n - int(2.0 * SR)]
    s["reveal"] = one_shot_reverb(riser + hit, 1.4, 0.35)
    wrong = np.zeros(int(0.9 * SR))                       # a soft two-note fall (no buzzer)
    for at, f in ((0.0, 330.0), (0.16, 262.0)):
        m = int(0.6 * SR)
        tt = np.arange(m) / SR
        note = (np.sin(2 * np.pi * f * tt) + 0.25 * np.sin(4 * np.pi * f * tt)) * np.minimum(1, tt / 0.01) * np.exp(-tt / 0.18)
        a0 = int(at * SR)
        wrong[a0:a0 + m] += release(note)[:len(wrong) - a0]
    s["wrong"] = lowpass(wrong, 2000) * 0.5
    notes = [392, 494, 587, 784]
    win = np.zeros(int(2.4 * SR))
    for k, f in enumerate(notes):
        b = bell(f, 1.8, (1, 2, 3, 4), 0.9, 0.5)
        win[int(k * 0.14 * SR):int(k * 0.14 * SR) + len(b)] += b[:len(win) - int(k * 0.14 * SR)]
    s["win"] = one_shot_reverb(win, 1.2, 0.3)
    n = int(2.6 * SR)
    t = np.arange(n) / SR
    lose = np.zeros(n)
    for at, f in ((0.0, 440.0), (0.35, 392.0), (0.7, 349.2), (1.05, 329.6)):   # a slow, sad fall a phone can play
        b = pluck(f, 1.5, 0.35)
        a0 = int(at * SR)
        lose[a0:a0 + len(b)] += b[:n - a0]
    s["lose"] = one_shot_reverb(lowpass(lose, 3000) * 0.6, 1.4, 0.3)
    hb = np.zeros(int(3.2 * SR))
    for k in range(4):
        put(hb, thud(170, 0.18, 1.0), k * 0.8, 0.9)                       # body a phone speaker can play
        put(hb, thud(150, 0.16, 1.0), k * 0.8 + 0.22, 0.6)
        put(hb, lowpass(click(0.02, 1000, 0.3, seed=k), 1500), k * 0.8, 0.25)   # soft tick on top
    s["heartbeat"] = hb
    return s


# ------------------------------------------------------------------ output
def phone_db(x):
    """Loudness as a phone speaker plays it: A-weighting plus a 300 Hz high-pass, as RMS dBFS."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR) + 1e-9
    f2 = f * f
    a = (12194 ** 2 * f2 * f2) / ((f2 + 20.6 ** 2) * np.sqrt((f2 + 107.7 ** 2) * (f2 + 737.9 ** 2)) * (f2 + 12194 ** 2))
    hp = (f / 300) ** 4 / (1 + (f / 300) ** 4)
    y = np.fft.irfft(spec * a * 1.2589 * hp, len(x))
    return 20 * np.log10(np.sqrt(np.mean(y ** 2)) + 1e-12)


TARGET_DB = {"amb": -27.0, "sting": -21.0, "tap": -27.0, "paper": -25.0, "stamp": -23.0}  # others: -21


def to_ogg(name, x, gain=0.85, fade=0.0):
    x = np.nan_to_num(x)
    x = highpass(x, 80)                                     # no sub-bass pressure on earbuds
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.5
    target = TARGET_DB.get(name.split("_")[0], TARGET_DB.get(name, -21.0))
    boost = np.clip(target - phone_db(x), -30, 18)
    x = x * 10 ** (boost / 20)
    ceiling = 0.6                                           # about -4.5 dBFS (encoding adds a little)
    x = ceiling * np.tanh(x / ceiling)                      # soft limiter
    if fade:
        m = int(fade * SR)
        x[:m] *= np.linspace(0, 1, m)
        x[-m:] *= np.linspace(1, 0, m)
    pcm = (x * 32767).astype(np.int16)
    with tempfile.TemporaryDirectory() as d:
        wav = Path(d) / "a.wav"
        with wave.open(str(wav), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "2",
                        str(OUT / f"{name}.ogg")], check=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for scene, fn in SCENES.items():
        to_ogg(f"amb_{scene}", fn(), gain=0.8)
        to_ogg(f"sting_{scene}", sting(scene), gain=0.9, fade=0.02)
        print("scene", scene)
    to_ogg("amb_home", a_home(), gain=0.7)
    for name, x in ui_sounds().items():
        to_ogg(name, x, gain=0.9, fade=0.005)
        print("ui", name)
    total = sum(p.stat().st_size for p in OUT.glob("*.ogg"))
    print(f"{len(list(OUT.glob('*.ogg')))} files, {total / 1024:.0f} KB")


if __name__ == "__main__":
    main()

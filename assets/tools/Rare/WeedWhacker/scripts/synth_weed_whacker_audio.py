"""Original, procedurally synthesised Weed Whacker sounds (no samples, no third-party audio).

Run: python synth_weed_whacker_audio.py   (needs numpy and scipy)
Writes 44.1 kHz mono 16-bit WAVs to ../audio/. The seed is fixed, so re-running reproduces
the same files.

  WeedWhacker_Run       a seamless 1 s loop of a small two-stroke engine at full throttle:
                        110 firing pulses (each a short exhaust pop of filtered noise over a low
                        thump), a buzzy harmonic tone at the firing rate and a little intake hiss.
                        Built periodic (FFT filtering, wrapped pulses), so it loops without a
                        click. In game its playback speed follows the blade (0.55 idling, 1.15 at
                        full speed) and it is looped on the held tool.
  WeedWhacker_Harvest   one stalk cut: a dry "thwip" of the spinning blade and a soft stalk snap.
  WeedWhacker_Equip     the pull-start: a starter-cord zip, a few uneven pops as the engine
                        catches, then a short rev settling to idle. ~1.1 s.
  WeedWhacker_Overheat  the engine coughing out: pops slowing and missing, then a soft hiss as it
                        cools. ~1.4 s.

Creator taste (Nov 5-6): airy and mechanical, no metallic ring layers, no cartoon boing.
"""
import os

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

RATE = 44100
rng = np.random.default_rng(20261107)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")


def t_axis(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def band(signal, low, high, order=2):
    return sosfilt(butter(order, [low, high], btype="band", fs=RATE, output="sos"), signal)


def lowpass(signal, cutoff, order=2):
    return sosfilt(butter(order, cutoff, btype="low", fs=RATE, output="sos"), signal)


def fft_band(signal, low, high):
    """Band-pass by zeroing FFT bins: keeps a periodic signal periodic (no filter tail)."""
    spec = np.fft.rfft(signal)
    freqs = np.fft.rfftfreq(len(signal), 1 / RATE)
    gain = ((freqs >= low) & (freqs <= high)).astype(float)
    # Soft edges over a quarter octave so it doesn't ring.
    gain = np.convolve(gain, np.ones(31) / 31, mode="same")
    return np.fft.irfft(spec * gain, n=len(signal))


def fade(signal, fade_in=0.004, fade_out=0.02):
    n_in, n_out = int(RATE * fade_in), int(RATE * fade_out)
    env = np.ones_like(signal)
    if n_in:
        env[:n_in] = np.linspace(0, 1, n_in)
    if n_out:
        env[-n_out:] = np.linspace(1, 0, n_out)
    return signal * env


def save(name, signal, peak_db=-3.0, fades=True):
    if fades:
        signal = fade(signal)
    signal = signal / (np.max(np.abs(signal)) + 1e-9) * (10 ** (peak_db / 20))
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    wavfile.write(path, RATE, (signal * 32767).astype(np.int16))
    return path, round(len(signal) / RATE, 3)


def pop(length=0.012, bright=1.0):
    """One exhaust pop: a burst of filtered noise with a fast decay over a short low thump."""
    n = int(RATE * length)
    k = np.arange(n)
    noise = band(rng.standard_normal(n), 400 * bright, 3200 * bright) * np.exp(-k / (RATE * 0.0035))
    thump = np.sin(2 * np.pi * 95 * k / RATE) * np.exp(-k / (RATE * 0.004)) * 0.9
    return noise + thump


def place(out, at_index, burst, wrap=False, gain=1.0):
    n = len(burst)
    if wrap:
        idx = (at_index + np.arange(n)) % len(out)
        np.add.at(out, idx, burst * gain)
    else:
        end = min(len(out), at_index + n)
        if at_index < len(out):
            out[at_index:end] += burst[: end - at_index] * gain


def run_loop():
    seconds, fires = 1.0, 110
    n = int(RATE * seconds)
    out = np.zeros(n)
    period = n / fires
    for k in range(fires):
        jitter = rng.uniform(-0.04, 0.04) * period
        gain = 1 + rng.uniform(-0.18, 0.18)
        place(out, int(k * period + jitter) % n, pop(0.012, rng.uniform(0.9, 1.15)), wrap=True, gain=gain)
    t = np.arange(n) / RATE
    tone = np.zeros(n)
    for h in range(1, 10):  # harmonics of the firing rate: whole cycles in the loop
        tone += np.sin(2 * np.pi * 110 * h * t + rng.uniform(0, 2 * np.pi)) / h ** 1.3
    hiss = fft_band(rng.standard_normal(n), 2500, 7000) * 0.12
    loop = fft_band(out, 60, 6000) + fft_band(tone, 60, 2200) * 0.35 + hiss
    return loop


def harvest():
    seconds = 0.14
    t = t_axis(seconds)
    out = np.zeros_like(t)
    m = int(RATE * 0.05)
    k = np.arange(m)
    whip = band(rng.standard_normal(m), 1800, 6500) * np.exp(-k / (RATE * 0.012)) * np.clip(k / (RATE * 0.004), 0, 1)
    place(out, 0, whip)
    snap = band(rng.standard_normal(int(RATE * 0.03)), 350, 1300) * np.exp(-np.arange(int(RATE * 0.03)) / (RATE * 0.005))
    place(out, int(RATE * 0.022), snap, gain=0.7)
    return out


def equip():
    seconds = 1.1
    t = t_axis(seconds)
    out = np.zeros_like(t)
    # Starter cord: a zip whose band rises as the cord is pulled (0 - 0.32 s).
    zip_n = int(RATE * 0.32)
    zk = np.arange(zip_n) / RATE
    cord = rng.standard_normal(zip_n)
    cord = band(cord, 700, 4200) * (0.4 + 0.6 * np.abs(np.sin(2 * np.pi * 38 * zk)))
    cord *= np.clip(zk / 0.04, 0, 1) * np.clip((0.32 - zk) / 0.06, 0, 1)
    place(out, 0, cord, gain=0.6)
    # The engine catches: uneven pops, then a rev up and back down to idle.
    at = 0.36
    for gap in (0.07, 0.05, 0.035, 0.022):
        place(out, int(RATE * at), pop(0.014), gain=0.9)
        at += gap
    while at < seconds - 0.02:
        rel = (at - 0.5) / 0.6
        freq = 60 + 70 * np.exp(-((rel - 0.25) / 0.22) ** 2) + 10 * (1 - rel)
        place(out, int(RATE * at), pop(0.012, rng.uniform(0.9, 1.1)), gain=rng.uniform(0.8, 1.0))
        at += 1 / max(freq, 40)
    env = np.ones_like(t)
    env *= np.clip((seconds - t) / 0.2, 0, 1)
    return lowpass(out, 6500) * env


def overheat():
    seconds = 1.4
    t = t_axis(seconds)
    out = np.zeros_like(t)
    at, freq = 0.0, 110.0
    while at < 0.75:
        if rng.uniform() > 0.25 + at * 0.6:  # more misfires as it dies
            place(out, int(RATE * at), pop(0.016, 0.85), gain=rng.uniform(0.6, 1.0) * (1 - at / 0.9))
        freq *= 0.92
        at += 1 / max(freq, 9)
    # A soft cough at the end and the cooling hiss.
    place(out, int(RATE * 0.78), pop(0.03, 0.7), gain=0.9)
    hiss = band(rng.standard_normal(len(t)), 3000, 9000) * 0.18
    hiss *= np.clip((t - 0.7) / 0.1, 0, 1) * np.exp(-np.clip(t - 0.8, 0, None) / 0.35)
    return lowpass(out, 6000) + hiss


if __name__ == "__main__":
    print(save("WeedWhacker_Run", run_loop(), peak_db=-4.0, fades=False))
    for name, fn in (("WeedWhacker_Harvest", harvest), ("WeedWhacker_Equip", equip), ("WeedWhacker_Overheat", overheat)):
        print(save(name, fn()))

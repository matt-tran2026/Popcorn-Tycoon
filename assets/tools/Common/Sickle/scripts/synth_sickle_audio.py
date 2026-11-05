"""Original, procedurally synthesised Sickle sounds (no samples, no third-party audio).

Run: python synth_sickle_audio.py   (needs numpy and scipy)
Writes 44.1 kHz mono 16-bit WAVs to ../audio/. The seed is fixed, so re-running reproduces
the same files. In game each one is played with a little random pitch so repeats differ.
"""
import os

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

RATE = 44100
rng = np.random.default_rng(20261105)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")


def t_axis(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def band(signal, low, high, order=2):
    sos = butter(order, [low, high], btype="band", fs=RATE, output="sos")
    return sosfilt(sos, signal)


def highpass(signal, cutoff, order=2):
    return sosfilt(butter(order, cutoff, btype="high", fs=RATE, output="sos"), signal)


def lowpass(signal, cutoff, order=2):
    return sosfilt(butter(order, cutoff, btype="low", fs=RATE, output="sos"), signal)


def fade(signal, fade_in=0.004, fade_out=0.02):
    n_in, n_out = int(RATE * fade_in), int(RATE * fade_out)
    env = np.ones_like(signal)
    if n_in:
        env[:n_in] = np.linspace(0, 1, n_in)
    if n_out:
        env[-n_out:] = np.linspace(1, 0, n_out)
    return signal * env


def save(name, signal, peak_db=-3.0):
    signal = fade(signal)
    signal = signal / (np.max(np.abs(signal)) + 1e-9) * (10 ** (peak_db / 20))
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    wavfile.write(path, RATE, (signal * 32767).astype(np.int16))
    return path, len(signal) / RATE


def equip():
    """A bright metal 'shing' as the blade is drawn: scrape noise into ringing partials."""
    t = t_axis(0.55)
    scrape_env = np.clip(t / 0.05, 0, 1) * np.exp(-np.maximum(t - 0.05, 0) * 30)
    scrape = band(rng.standard_normal(len(t)), 2500, 7500) * scrape_env * 0.6
    ring = np.zeros_like(t)
    # Inharmonic partials, like a struck thin steel plate, each with its own decay.
    for freq, amp, decay in [(2310, 1.0, 9), (3730, 0.7, 12), (5190, 0.45, 16), (6870, 0.25, 22)]:
        start = 0.04
        local = np.maximum(t - start, 0)
        ring += amp * np.sin(2 * np.pi * freq * local * (1 + 0.002 * np.sin(2 * np.pi * 6 * local))) * np.exp(-local * decay) * (t >= start)
    return scrape + ring * 0.5


def swish():
    """Air whoosh: band-passed noise whose centre sweeps up, under a quick swell."""
    t = t_axis(0.36)
    noise = rng.standard_normal(len(t))
    out = np.zeros_like(t)
    blocks = 24
    edges = np.linspace(0, len(t), blocks + 1).astype(int)
    for i in range(blocks):
        a, b = edges[i], edges[i + 1]
        centre = 500 * (4.5 ** (i / blocks))  # 500 Hz -> ~2.2 kHz
        out[a:b] = band(noise, centre * 0.6, min(centre * 1.6, 18000))[a:b]
    swell = np.sin(np.pi * np.clip(t / 0.3, 0, 1)) ** 1.6
    return lowpass(out * swell, 6000)


def snap():
    """Corn ear snapping off: a sharp crack, a short woody knock, then a dry leaf rustle."""
    t = t_axis(0.42)
    crack = band(rng.standard_normal(len(t)), 1200, 6500) * np.exp(-t * 160)
    knock = (np.sin(2 * np.pi * 190 * t * (1 - 0.25 * t)) + 0.5 * np.sin(2 * np.pi * 410 * t)) * np.exp(-t * 34) * 1.3
    # Rustle: sparse little grains of filtered noise, thinning out.
    grains = np.zeros_like(t)
    for _ in range(26):
        at = rng.uniform(0.02, 0.32)
        length = int(RATE * rng.uniform(0.006, 0.018))
        start = int(at * RATE)
        burst = rng.standard_normal(length) * np.hanning(length) * np.exp(-at * 7)
        grains[start:start + length] += burst[: len(grains) - start]
    rustle = band(grains, 1500, 6000) * 0.45
    return crack * 0.9 + knock + rustle


if __name__ == "__main__":
    for name, make in [("Sickle_Equip", equip), ("Sickle_Swish", swish), ("Stalk_Snap", snap)]:
        path, seconds = save(name, make())
        print(f"{name}: {seconds:.2f} s -> {os.path.relpath(path)}")

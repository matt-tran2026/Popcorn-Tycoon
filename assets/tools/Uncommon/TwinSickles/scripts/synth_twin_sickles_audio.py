"""Original, procedurally synthesised Twin Sickles sounds (no samples, no third-party audio).

Run: python synth_twin_sickles_audio.py   (needs numpy and scipy)
Writes 44.1 kHz mono 16-bit WAVs to ../audio/. The seed is fixed, so re-running reproduces
the same files. In game each one is played with a little random pitch so repeats differ.

Creator taste (Nov 5, Sickle): keep swings airy; no metallic ring or "shing" layers. So the
equip is two quick draws and a soft leather grip, not a blade ring. The stalk snap is the
shared Stalk_Snap from the Sickle (already uploaded).
"""
import os

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

RATE = 44100
rng = np.random.default_rng(20261106)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")


def t_axis(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def band(signal, low, high, order=2):
    sos = butter(order, [low, high], btype="band", fs=RATE, output="sos")
    return sosfilt(sos, signal)


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


def sweep(seconds, low, high, blocks=24):
    """Noise whose pass band slides from `low` to `high` Hz over the sound (the core of a whoosh)."""
    t = t_axis(seconds)
    noise = rng.standard_normal(len(t))
    out = np.zeros_like(t)
    edges = np.linspace(0, len(t), blocks + 1).astype(int)
    for i in range(blocks):
        a, b = edges[i], edges[i + 1]
        centre = low * ((high / low) ** (i / blocks))
        out[a:b] = band(noise, centre * 0.6, min(centre * 1.6, 18000))[a:b]
    return t, out


def whoosh(seconds, low, high, peak_at):
    t, out = sweep(seconds, low, high)
    swell = np.sin(np.pi * np.clip(t / (seconds * 0.95), 0, 1)) ** 1.4
    # Push the loudest point toward peak_at (fraction of the sound) for a sharper attack.
    tilt = np.exp(-((t / seconds - peak_at) ** 2) / 0.08)
    return lowpass(out * swell * (0.4 + 0.6 * tilt), 7000)


def equip():
    """Both blades drawn from the belt, right then left, and a soft squeeze of leather grips."""
    total = t_axis(0.42)
    out = np.zeros_like(total)
    for start, pitch in [(0.0, 1.0), (0.13, 1.15)]:
        w = whoosh(0.2, 700 * pitch, 2600 * pitch, 0.6)
        i = int(start * RATE)
        out[i:i + len(w)] += w[: len(out) - i]
    # Leather creak: a low, slightly rough thump as the hands close on the grips.
    t = total
    grip_at = 0.3
    local = np.maximum(t - grip_at, 0)
    creak = band(rng.standard_normal(len(t)), 180, 900) * np.exp(-local * 38) * (t >= grip_at)
    return out + creak * 0.5


def swing():
    """One quick slash: short, bright and airy (the twins are lighter and faster than the Sickle)."""
    return whoosh(0.24, 650, 3200, 0.55)


def combo():
    """Combo Sweep: a whirling whoosh that circles once round the player. Two blades pass the
    ear in turn, so the air flutters, and the pitch rises then falls as the spin passes by."""
    t = t_axis(0.5)
    _, rise = sweep(0.5, 450, 2400, blocks=30)
    flutter = 0.55 + 0.45 * np.sin(2 * np.pi * (6 * t + 4 * t * t)) ** 2  # blades passing, speeding up
    swell = np.sin(np.pi * np.clip(t / 0.48, 0, 1)) ** 1.2
    body = lowpass(rise * flutter * swell, 6500)
    # A low air rush under it, for weight.
    rush = band(rng.standard_normal(len(t)), 120, 500) * swell * 0.6
    return body + rush


if __name__ == "__main__":
    for name, make in [("TwinSickles_Equip", equip), ("TwinSickles_Swing", swing), ("TwinSickles_Combo", combo)]:
        path, seconds = save(name, make())
        print(f"{name}: {seconds:.2f} s -> {os.path.relpath(path)}")

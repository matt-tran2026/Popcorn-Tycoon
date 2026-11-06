"""Original, procedurally synthesised Hedge Trimmer sounds (no samples, no third-party audio).

Run: python synth_hedge_trimmer_audio.py   (needs numpy and scipy)
Writes 44.1 kHz mono 16-bit WAVs to ../audio/. The seed is fixed, so re-running reproduces
the same files. In game each one is played with a little random pitch so repeats differ.

  HedgeTrimmer_Swing    the trim: a small electric motor spinning up, buzzing (the blades'
                        22 Hz chatter as a tremolo on a ~120 Hz saw), and spinning down. ~0.5 s.
  HedgeTrimmer_Harvest  one stalk cut: a quick, dry double snip (two blades passing), no ring.
  HedgeTrimmer_Equip    a short motor blip: a click and a 0.2 s rev.

Creator taste (Nov 5, Sickle): airy and mechanical, no metallic ring layers.
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
    return path, round(len(signal) / RATE, 3)


def motor(seconds, freq_curve, chatter_hz=22.0, chatter_depth=0.5):
    """A small electric motor: a band-limited saw at freq_curve(t) with a little brush noise,
    amplitude-modulated by the blade chatter."""
    t = t_axis(seconds)
    freq = freq_curve(t)
    phase = 2 * np.pi * np.cumsum(freq) / RATE
    saw = np.zeros_like(t)
    for k in range(1, 9):  # first harmonics only: buzzy, not harsh
        saw += np.sin(k * phase) / k
    brush = band(rng.standard_normal(len(t)), 1800, 5200) * 0.18
    tone = lowpass(saw, 2600) + brush
    trem = 1 - chatter_depth * (0.5 + 0.5 * np.sin(2 * np.pi * chatter_hz * t))
    return tone * trem


def snip(at_seconds, total_seconds, brightness=1.0):
    """A dry blade pass: a 6 ms burst of band-passed noise with a fast decay."""
    t = t_axis(total_seconds)
    out = np.zeros_like(t)
    start = int(RATE * at_seconds)
    n = int(RATE * 0.03)
    burst = band(rng.standard_normal(n), 2200 * brightness, 7000 * brightness) * np.exp(-np.arange(n) / (RATE * 0.006))
    body = band(rng.standard_normal(n), 500, 1400) * np.exp(-np.arange(n) / (RATE * 0.004)) * 0.6
    out[start:start + n] += (burst + body)[: len(out) - start]
    return out


def swing():
    seconds = 0.52
    t = t_axis(seconds)

    def curve(tt):
        up = np.clip(tt / 0.08, 0, 1)
        down = np.clip((seconds - tt) / 0.14, 0, 1)
        return 60 + 70 * up * (0.7 + 0.3 * down)

    env = np.clip(t / 0.03, 0, 1) * np.clip((seconds - t) / 0.16, 0, 1) ** 1.5
    sound = motor(seconds, curve) * env
    # A few blade passes ticking through the buzz.
    for at in (0.1, 0.145, 0.19, 0.235, 0.28):
        sound += snip(at, seconds, 0.9) * 0.35
    return sound


def harvest():
    seconds = 0.16
    return snip(0.005, seconds) + snip(0.03, seconds, 1.15) * 0.8


def equip():
    seconds = 0.32
    t = t_axis(seconds)
    click = snip(0.0, seconds, 0.6) * 0.8

    def curve(tt):
        return 55 + 55 * np.clip((tt - 0.03) / 0.09, 0, 1)

    env = np.clip((t - 0.03) / 0.03, 0, 1) * np.clip((seconds - t) / 0.18, 0, 1) ** 2
    return click + motor(seconds, curve, chatter_depth=0.25) * env * 0.8


if __name__ == "__main__":
    for name, fn in (("HedgeTrimmer_Swing", swing), ("HedgeTrimmer_Harvest", harvest), ("HedgeTrimmer_Equip", equip)):
        print(save(name, fn()))

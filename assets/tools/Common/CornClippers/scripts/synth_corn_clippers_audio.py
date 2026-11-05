"""Original, procedurally synthesised Corn Clippers sounds (no samples, no third-party audio).

Run: python synth_corn_clippers_audio.py   (needs numpy and scipy)
Writes 44.1 kHz mono 16-bit WAVs to ../audio/ at -3 dBFS. Fixed seed, so re-running gives the
same files. In game each plays with a little random pitch (ToolPresentation.CornClippers.sounds).

  CornClippers_Snip   the snip on every action: a short blade slide into a crisp double click
                      (blade passing the hook, then the handles meeting). Dry, no ringing tail,
                      as the creator preferred for the Sickle; just a 25 ms metallic tick.
  CornClippers_Equip  drawing the clippers: two soft clicks of the jaws with a faint spring boing.
The stalk snap at the corn reuses the Sickle's uploaded Stalk_Snap.
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
    return sosfilt(butter(order, [low, high], btype="band", fs=RATE, output="sos"), signal)


def highpass(signal, cutoff, order=2):
    return sosfilt(butter(order, cutoff, btype="high", fs=RATE, output="sos"), signal)


def fade(signal, fade_in=0.001, fade_out=0.015):
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


def click(t, at, brightness, partials, decay):
    """A small metal tick at time `at`: a noise transient plus quickly damped partials."""
    local = t - at
    on = local >= 0
    out = np.zeros_like(t)
    burst = highpass(rng.standard_normal(len(t)), 2500) * np.exp(-np.maximum(local, 0) * 900) * on
    out += burst * brightness
    for freq, amp in partials:
        out += np.sin(2 * np.pi * freq * np.maximum(local, 0) + rng.uniform(0, 6.28)) * np.exp(-np.maximum(local, 0) * decay) * on * amp
    return out


def snip():
    t = t_axis(0.16)
    # Blade sliding past the hook just before contact.
    slide_env = np.clip((t - 0.004) / 0.012, 0, 1) * np.exp(-np.maximum(t - 0.016, 0) * 160)
    slide = band(rng.standard_normal(len(t)), 3500, 9000) * slide_env * 0.35
    first = click(t, 0.018, 1.0, [(3150, 0.45), (5230, 0.35), (7410, 0.2)], 180)
    second = click(t, 0.043, 0.6, [(2480, 0.4), (4120, 0.25)], 220)
    # A soft low thud of the handles closing gives it body without ring.
    thud = np.sin(2 * np.pi * 210 * np.maximum(t - 0.043, 0)) * np.exp(-np.maximum(t - 0.043, 0) * 70) * (t >= 0.043) * 0.25
    return slide + first + second + thud


def equip():
    t = t_axis(0.42)
    out = click(t, 0.02, 0.7, [(2900, 0.35), (4700, 0.25)], 200)
    out += click(t, 0.12, 0.55, [(2600, 0.3), (4300, 0.2)], 220)
    # Spring "boing": a quiet wobbling tone after the second click.
    local = np.maximum(t - 0.12, 0)
    wobble = np.sin(2 * np.pi * (720 * local + 25 * np.sin(2 * np.pi * 9 * local) / (2 * np.pi * 9)))
    out += wobble * np.exp(-local * 14) * (t >= 0.12) * 0.12
    return out


if __name__ == "__main__":
    print(save("CornClippers_Snip", snip()))
    print(save("CornClippers_Equip", equip()))

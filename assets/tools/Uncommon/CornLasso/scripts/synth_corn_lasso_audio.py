"""Original, procedurally synthesised Corn Lasso sounds (no samples, no third-party audio).

Run: python synth_corn_lasso_audio.py   (needs numpy and scipy)
Writes 44.1 kHz mono 16-bit WAVs to ../audio/. The seed is fixed, so re-running reproduces
the same files. In game each one is played with a little random pitch so repeats differ.

  CornLasso_Swing    the throw, timed to the 0.38 s Swing clip: two airy whirs as the loop
                     twirls overhead (0-0.17 s), then a longer whoosh as the rope leaves at the
                     Throw marker (0.18 s) and pays out. ~0.62 s.
  CornLasso_Harvest  the loop cinching on an ear: a short rope zip (rising rough noise) and a
                     dry stalk snap.
  CornLasso_Pull     an ear landing in the hand: a soft, low leathery catch.
  CornLasso_Equip    a leather creak and a small rope swish.

Creator taste (Nov 5-6): airy and mechanical; no metallic ring layers and no cartoon "boing".
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


def lowpass(signal, cutoff, order=2):
    return sosfilt(butter(order, cutoff, btype="low", fs=RATE, output="sos"), signal)


def fade(signal, fade_in=0.003, fade_out=0.03):
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


def place(out, sound, at_seconds, gain=1.0):
    start = int(RATE * at_seconds)
    end = min(len(out), start + len(sound))
    out[start:end] += sound[: end - start] * gain


def whoosh(seconds, low=450, high=2400, attack=0.04):
    """Air: band-passed noise swelling and fading, its band sliding down a little."""
    t = t_axis(seconds)
    noise = rng.standard_normal(len(t))
    first = band(noise, low * 1.3, high * 1.3)
    second = band(noise, low * 0.8, high * 0.8)
    mix = np.linspace(0, 1, len(t))
    env = np.clip(t / attack, 0, 1) * np.clip((seconds - t) / (seconds * 0.7), 0, 1) ** 1.6
    return (first * (1 - mix) + second * mix) * env


def whir(seconds, low=700, high=2000):
    """A rope loop passing close: a quick swelling-and-fading puff of mid air, peaking mid-way."""
    t = t_axis(seconds)
    env = np.sin(np.pi * t / seconds) ** 2
    return band(rng.standard_normal(len(t)), low, high) * env


def snap(decay=0.004):
    """A dry stalk snap: a short band-passed noise crack with a little woody body."""
    n = int(RATE * 0.05)
    k = np.arange(n)
    crack = band(rng.standard_normal(n), 1500, 5200) * np.exp(-k / (RATE * decay))
    body = band(rng.standard_normal(n), 220, 700) * np.exp(-k / (RATE * 0.008)) * 0.6
    return crack + body


def zip_(seconds=0.09):
    """Rope drawn tight through the knot: rough noise, amplitude-modulated like fibres catching,
    its band rising."""
    t = t_axis(seconds)
    noise = rng.standard_normal(len(t))
    low = band(noise, 600, 1800)
    high = band(noise, 1400, 3600)
    mix = t / seconds
    grain = 0.6 + 0.4 * np.sign(np.sin(2 * np.pi * (90 + 160 * mix) * t))
    env = np.clip(t / 0.01, 0, 1) * (1 - mix) ** 0.8
    return (low * (1 - mix) + high * mix) * grain * env


def swing():
    seconds = 0.62
    out = np.zeros(int(RATE * seconds))
    place(out, whir(0.09, 600, 1700), 0.0, 0.55)
    place(out, whir(0.09, 700, 1900), 0.085, 0.7)
    place(out, whoosh(0.42, 380, 2200, attack=0.03), 0.17, 1.0)
    return out


def harvest():
    out = np.zeros(int(RATE * 0.16))
    place(out, zip_(0.09), 0.0, 0.8)
    place(out, snap(), 0.07, 1.0)
    return out


def pull():
    t = t_axis(0.16)
    thump = np.sin(2 * np.pi * (150 - 50 * t / 0.16) * t) * np.exp(-t / 0.035)
    slap = band(rng.standard_normal(len(t)), 400, 1600) * np.exp(-t / 0.012) * 0.5
    return lowpass(thump + slap, 3000)


def equip():
    out = np.zeros(int(RATE * 0.3))
    # Leather creak: a few low, rough grains close together.
    for i, at in enumerate((0.0, 0.025, 0.045, 0.07)):
        n = int(RATE * 0.02)
        k = np.arange(n)
        grain = band(rng.standard_normal(n), 250 + 40 * i, 900) * np.exp(-k / (RATE * 0.006))
        place(out, grain, at, 0.6)
    place(out, whir(0.16, 650, 1800), 0.1, 0.45)
    return out


if __name__ == "__main__":
    for name, fn in (("CornLasso_Swing", swing), ("CornLasso_Harvest", harvest), ("CornLasso_Pull", pull), ("CornLasso_Equip", equip)):
        print(save(name, fn()))

"""Original, procedurally synthesised Pitchfork sounds (no samples, no third-party audio).

Run: python synth_pitchfork_audio.py   (needs numpy and scipy)
Writes 44.1 kHz mono 16-bit WAVs to ../audio/ at -3 dBFS. Fixed seed, so re-running gives the
same files. In game each plays with a little random pitch (ToolPresentation.Pitchfork.sounds).

  Pitchfork_Equip   swinging the fork up: two dry wooden knocks of the shaft into the palm.
  Pitchfork_Thrust  the stab, played as the action starts: a soft cloth/handle rustle for the
                    pull-back (about 0.13 s), then a short, airy forward whoosh timed to the jab.
                    Airy only, no metal ring (the creator's taste for swing sounds, Nov 5).
  Pitchfork_Stab    each stalk the prongs pierce: a crisp crunchy thunk with a leafy rustle tail.
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


def fade(signal, fade_in=0.002, fade_out=0.02):
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


def knock(t, at, pitch, amp):
    """A dry wooden knock: a damped low body tone plus a short mid-band noise tap."""
    local = np.maximum(t - at, 0)
    on = t >= at
    body = (np.sin(2 * np.pi * pitch * local) * 0.7 + np.sin(2 * np.pi * pitch * 2.7 * local) * 0.25) * np.exp(-local * 55)
    tap = band(rng.standard_normal(len(t)), 500, 2200) * np.exp(-local * 260)
    return (body + tap * 0.8) * on * amp


def equip():
    t = t_axis(0.36)
    # The shaft brushing the glove as it swings up, then two knocks into the palm.
    brush_env = np.clip(t / 0.08, 0, 1) * np.exp(-np.maximum(t - 0.08, 0) * 40)
    brush = band(rng.standard_normal(len(t)), 700, 3000) * brush_env * 0.12
    return brush + knock(t, 0.11, 175, 1.0) + knock(t, 0.2, 205, 0.55)


def sweep_noise(t, start, length, low_hz, high_hz):
    """Band noise whose centre rises then falls over `length`, built from overlapping bands."""
    out = np.zeros_like(t)
    noise = rng.standard_normal(len(t))
    centres = np.geomspace(low_hz, high_hz, 7)
    for i, centre in enumerate(centres):
        # Each band peaks a little later than the one below: the whoosh brightens as it drives.
        peak = start + length * (0.25 + 0.5 * i / (len(centres) - 1))
        width = length * 0.35
        env = np.exp(-((t - peak) / width) ** 2)
        out += band(noise, centre / 1.45, min(centre * 1.45, RATE / 2 - 100)) * env
    return out


def thrust():
    t = t_axis(0.46)
    # Pull-back: a quiet rustle of the hands sliding on the shaft.
    pull_env = np.clip(t / 0.05, 0, 1) * np.exp(-np.maximum(t - 0.07, 0) * 30) * (t < 0.2)
    pull = band(rng.standard_normal(len(t)), 600, 2500) * pull_env * 0.18
    # The jab: a short forward whoosh starting at 0.13 s, peaking around 0.2 s.
    whoosh = sweep_noise(t, 0.13, 0.17, 350, 3200) * 0.9
    # A low push of air under it gives the stab weight without any ring.
    push_env = np.exp(-((t - 0.19) / 0.04) ** 2)
    push = lowpass(rng.standard_normal(len(t)), 260) * push_env * 1.6
    return pull + whoosh + push


def stab():
    t = t_axis(0.3)
    local = t
    # Prongs punching into the stalk: a crunchy broadband thunk...
    crunch = band(rng.standard_normal(len(t)), 900, 4500) * np.exp(-local * 120) * 0.9
    thud = np.sin(2 * np.pi * 120 * local) * np.exp(-local * 45) * 0.55
    # ...a few tiny fibre snaps inside it...
    snaps = np.zeros_like(t)
    for at in (0.006, 0.017, 0.031):
        l2 = np.maximum(t - at, 0)
        snaps += band(rng.standard_normal(len(t)), 2500, 7000) * np.exp(-l2 * 600) * (t >= at) * 0.5
    # ...and the leaves rustling after it.
    rustle_env = np.clip((t - 0.03) / 0.03, 0, 1) * np.exp(-np.maximum(t - 0.06, 0) * 16)
    rustle = band(rng.standard_normal(len(t)), 1800, 6500) * rustle_env * 0.22
    return crunch + thud + snaps + rustle


if __name__ == "__main__":
    for name, fn in (("Pitchfork_Equip", equip), ("Pitchfork_Thrust", thrust), ("Pitchfork_Stab", stab)):
        print(save(name, fn()))

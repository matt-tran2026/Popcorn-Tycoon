"""Original, procedurally synthesised Harvest Hook sounds (no samples, no third-party audio).

Run: python synth_harvest_hook_audio.py   (needs numpy and scipy)
Writes 44.1 kHz mono 16-bit WAVs to ../audio/ at -3 dBFS. Fixed seed, so re-running gives the
same files. In game each plays with a little random pitch (ToolPresentation.HarvestHook.sounds).

  HarvestHook_Equip    drawing the hook: a leather creak of the wrap in the palm, then a dull,
                       damped tap of the iron (no ring).
  HarvestHook_Swing    the throw and pull, played as the action starts: a forward whoosh timed
                       to the throw (Hit at 0.19 s), then a quicker, higher "zip" of the yank
                       back. Airy only, no metal ring (the creator's taste for swing sounds).
  HarvestHook_Harvest  each stalk the hook bites: a fibrous tug and snap with a leafy tail.
  HarvestHook_Pull     each ear landing at the player: a short airy fwip and a soft thump.
"""
import os

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

RATE = 44100
rng = np.random.default_rng(20261108)
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


def sweep_noise(t, start, length, low_hz, high_hz, bands=7):
    """Band noise whose centre rises over `length`, built from overlapping bands."""
    out = np.zeros_like(t)
    noise = rng.standard_normal(len(t))
    centres = np.geomspace(low_hz, high_hz, bands)
    for i, centre in enumerate(centres):
        peak = start + length * (0.25 + 0.5 * i / (len(centres) - 1))
        width = length * 0.35
        env = np.exp(-((t - peak) / width) ** 2)
        out += band(noise, centre / 1.45, min(centre * 1.45, RATE / 2 - 100)) * env
    return out


def creak(t, at, length, amp):
    """Leather creak: a train of tiny, irregular friction clicks through a low-mid band."""
    out = np.zeros_like(t)
    clicks = np.cumsum(rng.uniform(0.004, 0.011, 40)) + at
    for c in clicks[clicks < at + length]:
        local = np.maximum(t - c, 0)
        out += np.exp(-local * 900) * (t >= c) * rng.uniform(0.5, 1.0)
    return band(out, 250, 1800) * amp


def equip():
    t = t_axis(0.34)
    grip = creak(t, 0.03, 0.12, 2.2)
    local = np.maximum(t - 0.19, 0)
    on = t >= 0.19
    # Dull iron tap: a low damped body with a quick mid tick; heavily damped so it never rings.
    body = (np.sin(2 * np.pi * 240 * local) * 0.6 + np.sin(2 * np.pi * 610 * local) * 0.2) * np.exp(-local * 70)
    tick = band(rng.standard_normal(len(t)), 900, 3200) * np.exp(-local * 320) * 0.7
    return grip + (body + tick) * on


def swing():
    t = t_axis(0.42)
    throw = sweep_noise(t, 0.04, 0.17, 300, 2600) * 0.9
    throw_push = lowpass(rng.standard_normal(len(t)), 240) * np.exp(-((t - 0.17) / 0.04) ** 2) * 1.4
    # The yank back: shorter and brighter, falling in pitch as the hook comes home.
    yank = sweep_noise(t, 0.22, 0.1, 4200, 900, bands=6) * 0.7
    return throw + throw_push + yank


def harvest():
    t = t_axis(0.3)
    # The hook biting and tugging: a fibrous tear (bandpassed noise with a quick swell)...
    tear_env = np.clip(t / 0.012, 0, 1) * np.exp(-t * 55)
    tear = band(rng.standard_normal(len(t)), 700, 3800) * tear_env * 0.8
    thud = np.sin(2 * np.pi * 105 * t) * np.exp(-t * 40) * 0.5
    # ...the stalk snapping off...
    snaps = np.zeros_like(t)
    for at in (0.022, 0.034):
        local = np.maximum(t - at, 0)
        snaps += band(rng.standard_normal(len(t)), 2400, 7500) * np.exp(-local * 520) * (t >= at) * 0.6
    # ...and the leaves rustling after it.
    rustle_env = np.clip((t - 0.04) / 0.03, 0, 1) * np.exp(-np.maximum(t - 0.07, 0) * 15)
    rustle = band(rng.standard_normal(len(t)), 1800, 6500) * rustle_env * 0.22
    return tear + thud + snaps + rustle


def pull():
    t = t_axis(0.22)
    fwip = sweep_noise(t, 0.0, 0.09, 1200, 5200, bands=5) * 0.6
    local = np.maximum(t - 0.075, 0)
    on = t >= 0.075
    thump = (np.sin(2 * np.pi * 150 * local) * np.exp(-local * 50) * 0.7
             + band(rng.standard_normal(len(t)), 400, 1600) * np.exp(-local * 160) * 0.35) * on
    return fwip + thump


if __name__ == "__main__":
    for name, fn in (("HarvestHook_Equip", equip), ("HarvestHook_Swing", swing),
                     ("HarvestHook_Harvest", harvest), ("HarvestHook_Pull", pull)):
        print(save(name, fn()))

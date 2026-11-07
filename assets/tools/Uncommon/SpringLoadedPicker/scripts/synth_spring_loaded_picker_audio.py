"""Original, procedurally synthesised Spring-Loaded Picker sounds (no samples, no third-party audio).

Run: python synth_spring_loaded_picker_audio.py   (needs numpy and scipy)
Writes 44.1 kHz mono 16-bit WAVs to ../audio/. The seed is fixed, so re-running reproduces
the same files. In game each one is played with a little random pitch so repeats differ.

  SpringLoadedPicker_Swing    the Spring Dash, timed to the Swing clip: three ratchet clicks
                              while the coil winds (0-0.14 s), the latch clack at the Dash marker
                              (0.15 s) and an airy whoosh for the lunge. ~0.56 s.
  SpringLoadedPicker_Harvest  one stalk snatched: the claw's dry snap over a soft low pop.
  SpringLoadedPicker_Equip    two ratchet clicks.

Creator taste (Nov 5, Sickle): airy and mechanical, no metallic ring layers. Nov 6: no "boing"
either; the creator asked for the spring tone to be removed from the swing and equip sounds
(boing() is kept below, unused, in case a later tool wants it).
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


def click(brightness=1.0, decay=0.004):
    """A dry plastic-and-steel tick: a short band-passed noise burst with a little body."""
    n = int(RATE * 0.03)
    k = np.arange(n)
    tick = band(rng.standard_normal(n), 1800 * brightness, 6000 * brightness) * np.exp(-k / (RATE * decay))
    body = band(rng.standard_normal(n), 300, 900) * np.exp(-k / (RATE * 0.006)) * 0.5
    return tick + body


def boing(seconds, f_start, f_end, wobble_hz=11.0, wobble_depth=0.12, decay=0.25):
    """The cartoon spring: a soft tone gliding from f_start to f_end with a vibrato that dies
    away, two gentle harmonics only (no bright partials), exponentially decaying."""
    t = t_axis(seconds)
    glide = f_end + (f_start - f_end) * np.exp(-t / 0.06)
    vibrato = 1 + wobble_depth * np.exp(-t / 0.22) * np.sin(2 * np.pi * wobble_hz * t)
    phase = 2 * np.pi * np.cumsum(glide * vibrato) / RATE
    tone = np.sin(phase) + 0.35 * np.sin(2 * phase) + 0.12 * np.sin(3 * phase)
    env = np.clip(t / 0.004, 0, 1) * np.exp(-t / decay)
    return lowpass(tone * env, 2200)


def whoosh(seconds, low=500, high=2600):
    """Air: band-passed noise swelling fast and fading, its band sliding down a little."""
    t = t_axis(seconds)
    noise = rng.standard_normal(len(t))
    first = band(noise, low * 1.3, high * 1.3)
    second = band(noise, low * 0.8, high * 0.8)
    mix = np.linspace(0, 1, len(t))
    env = np.clip(t / 0.04, 0, 1) * np.clip((seconds - t) / (seconds * 0.7), 0, 1) ** 1.6
    return (first * (1 - mix) + second * mix) * env


def swing():
    seconds = 0.82
    out = np.zeros(int(RATE * seconds))
    # Coil winding: three ratchet clicks, getting a touch higher as it tightens.
    for i, at in enumerate((0.01, 0.055, 0.1)):
        place(out, click(0.8 + 0.1 * i), at, 0.55)
    # The latch lets go (Dash marker, 0.15 s): a heavier clack.
    place(out, click(0.55, decay=0.007), 0.15, 1.0)
    # The lunge's whoosh. (The "sproing" tone was removed at the creator's request, Nov 6.)
    place(out, whoosh(0.38), 0.15, 0.7)
    return out[: int(RATE * 0.56)]


def harvest():
    seconds = 0.18
    out = np.zeros(int(RATE * seconds))
    place(out, click(1.1, decay=0.005), 0.004, 1.0)
    t = t_axis(0.12)
    pop = np.sin(2 * np.pi * (170 - 60 * t / 0.12) * t) * np.exp(-t / 0.03)
    place(out, pop, 0.0, 0.6)
    return out


def equip():
    seconds = 0.42
    out = np.zeros(int(RATE * seconds))
    place(out, click(0.8), 0.0, 0.7)
    place(out, click(0.9), 0.06, 0.7)
    return out[: int(RATE * 0.12)]


if __name__ == "__main__":
    for name, fn in (("SpringLoadedPicker_Swing", swing), ("SpringLoadedPicker_Harvest", harvest), ("SpringLoadedPicker_Equip", equip)):
        print(save(name, fn()))

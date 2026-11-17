#!/usr/bin/env python3
"""Original procedural soundtrack and effects; no recorded samples or third-party music."""
from pathlib import Path
from itertools import accumulate
import math
import random
import struct
import wave

ROOT = Path(__file__).resolve().parents[1] / 'audio'
ROOT.mkdir(exist_ok=True)
RATE = 22050


def write(name, duration, sample):
    with wave.open(str(ROOT / (name + '.wav')), 'wb') as output:
        output.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        output.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, sample(i / RATE))) * 26000))
                                   for i in range(int(duration * RATE))))


def pitch(note):
    return 440 * 2 ** ((note - 69) / 12)


# An original 16-second plucked motif over four warm, quiet chords.
chords = [(57, 60, 64, 67), (53, 57, 60, 64), (48, 55, 60, 64), (55, 59, 62, 67)]
pattern = [0, 2, 1, 3, 2, 1, 3, 2]


def music(t):
    chord = chords[int(t // 4) % 4]
    step = int(t / .5)
    phase = t % .5
    note = chord[pattern[step % 8]] + 12
    tone = math.sin(2 * math.pi * pitch(note) * phase)
    tone += .18 * math.sin(4 * math.pi * pitch(note) * phase)
    envelope = min(1, phase / .015) * math.exp(-phase * 7)
    bass_phase = t % 2
    bass = math.sin(2 * math.pi * pitch(chord[0] - 12) * bass_phase)
    bass *= min(1, bass_phase / .04) * math.exp(-bass_phase * 2)
    pad = sum(math.sin(2 * math.pi * pitch(n) * t) for n in chord) * .012
    return tone * envelope * .17 + bass * .08 + pad


write('night_shift', 16, music)
write('jump', .18, lambda t: math.sin(2 * math.pi * (260 * t + 900 * t * t)) * .22 * (1 - t / .18))
write('click', .08, lambda t: math.sin(2 * math.pi * 720 * t) * math.exp(-t * 60) * .24)
noise = random.Random(39418)
write('land', .13, lambda t: (math.sin(2 * math.pi * 95 * t) * .18 + noise.uniform(-.12, .12)) * math.exp(-t * 30))
write('line', .5, lambda t: sum(math.sin(2 * math.pi * pitch(n) * t) for n in [72, 76, 79]) * .12 * math.exp(-t * 6))
write('over', .65, lambda t: math.sin(2 * math.pi * (180 * t - 70 * t * t)) * .2 * math.exp(-t * 5))


def helmet_impact(breaks):
    noise = random.Random(42931)

    def sample(t):
        crack = noise.uniform(-.32, .32) * math.exp(-t * 44)
        wood = math.sin(2 * math.pi * 165 * t) * .24 * math.exp(-t * 33)
        shell = 0
        if breaks and t > .035:
            after = t - .035
            shell = (math.sin(2 * math.pi * 750 * after) + .45 * math.sin(2 * math.pi * 1060 * after))
            shell *= .15 * math.exp(-after * 19)
        return crack + wood + shell

    return sample


write('helmet_hit', .21, helmet_impact(False))
write('helmet_break', .28, helmet_impact(True))


def glove_tear():
    noise = random.Random(18311)

    def sample(t):
        wood = .24 * math.sin(2 * math.pi * 112 * t) * math.exp(-t * 38)
        scuff = noise.uniform(-.16, .16) * math.exp(-t * 29)
        if t > .04:
            tail = t - .04
            scuff += noise.uniform(-.29, .29) * math.exp(-tail * 25)
            scuff += .13 * math.sin(2 * math.pi * 620 * tail) * math.exp(-tail * 23)
        return wood + scuff

    return sample


write('gloves_tear', .26, glove_tear())


def crate_slide(duration):
    noise = random.Random(37816)
    count = int(duration * RATE)
    samples = [noise.uniform(-1, 1) for _ in range(count)]

    def smooth(radius):
        # The filter sees the same neighbors when the last sample wraps to the first.
        window = samples[-radius:] + samples + samples[:radius]
        sums = list(accumulate(window, initial=0.0))
        width = 2 * radius + 1
        return [(sums[i + width] - sums[i]) / width for i in range(count)]

    texture = []
    for i, (fine, grain, slow) in enumerate(zip(smooth(1), smooth(3), smooth(20))):
        phase = 2 * math.pi * i / count
        pressure = 1 + .08 * math.sin(3 * phase) + .05 * math.cos(7 * phase)
        texture.append((grain - slow + .18 * (fine - grain)) * pressure)
    gain = .08 / max(abs(value) for value in texture)
    return lambda t: texture[round(t * RATE)] * gain


SLIDE_DURATION = 1.6
write('crate_slide', SLIDE_DURATION, crate_slide(SLIDE_DURATION))


def mallet_swing():
    noise = random.Random(2437)
    air = 0.0

    def sample(t):
        nonlocal air
        air = .78 * air + .22 * noise.uniform(-1, 1)
        pressure = math.sin(math.pi * t / .12) ** 3
        return .26 * air * pressure

    return sample


def mallet_impact():
    noise = random.Random(71072)
    grain = 0.0

    def sample(t):
        nonlocal grain
        grain = .58 * grain + .42 * noise.uniform(-1, 1)
        body = math.sin(2 * math.pi * (196 * t + 70 * t * t)) * .17 * math.exp(-t * 47)
        rim = math.sin(2 * math.pi * 506 * t) * .075 * math.exp(-t * 68)
        wood = grain * .17 * math.exp(-t * 32)
        return min(1, t / .004) * (body + rim + wood)

    return sample


def mallet_break():
    noise = random.Random(7494)
    grain = 0.0

    def sample(t):
        nonlocal grain
        grain = .34 * grain + .66 * noise.uniform(-1, 1)
        tail = t - .055
        if tail <= 0.0:
            return 0.0
        splinter = .19 * grain * math.exp(-tail * 38)
        echo = t - .133
        if echo > 0.0:
            splinter += min(1, echo / .005) * .085 * math.sin(2 * math.pi * 487 * echo) * math.exp(-echo * 66)
        return min(1, tail / .004) * splinter

    return sample


write('mallet_swing', .12, mallet_swing())
write('mallet_hit', .17, mallet_impact())
write('mallet_break', .24, mallet_break())

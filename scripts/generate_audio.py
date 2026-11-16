#!/usr/bin/env python3
"""Original procedural soundtrack and effects; no recorded samples or third-party music."""
from pathlib import Path
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

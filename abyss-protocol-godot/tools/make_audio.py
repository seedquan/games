#!/usr/bin/env python3
"""Generate original, deterministic short PCM effects; no third-party samples."""
import math
import random
import struct
import wave
from pathlib import Path

DEST = Path(__file__).resolve().parents[1] / 'assets/audio'
RATE = 22050
SPEC = {'gun': (.14, 110, .6), 'heavy': (.3, 68, .4), 'blade': (.16, 700, .8),
        'bow': (.22, 220, .23), 'arc': (.28, 550, .15), 'impact': (.12, 160, .7),
        'dash': (.25, 180, .5), 'ui': (.09, 620, .02), 'clear': (.55, 440, .01)}

for name, (duration, frequency, noise_mix) in SPEC.items():
    rng = random.Random(name)
    pcm = []
    smooth_noise = 0
    for i in range(int(duration * RATE)):
        t = i / RATE
        progress = t / duration
        smooth_noise += .32 * (rng.uniform(-1, 1) - smooth_noise)
        attack = min(1, t / .003)
        envelope = attack * (1-progress) ** (3 if name in ('gun', 'impact', 'heavy') else 1.8)
        fall = -frequency * .6 / duration
        phase = 2 * math.pi * (frequency*t + fall*t*t/2)
        tone = math.sin(phase) * .65 + math.sin(phase*2.37) * .15
        if name == 'clear':
            tone = sum(math.sin(2*math.pi*f*t) for f in [440, 554.365, 659.255]) / 3
        if name == 'dash':
            envelope *= math.sin(math.pi*progress)
        value = (tone*(1-noise_mix) + smooth_noise*noise_mix*2) * envelope * .8
        pcm.append(struct.pack('<h', int(max(-.95, min(.95, value))*32767)))
    with wave.open(str(DEST / (name + '.wav')), 'wb') as output:
        output.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        output.writeframes(b''.join(pcm))

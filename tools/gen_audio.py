"""Procedurally generates Riverwing's music loops and sound effects.

Music: three loops in A minor / E minor (cruise, fortified zone, battlefield),
rendered as 16-bit WAV then encoded to Ogg Vorbis with ffmpeg.
SFX: short 16-bit mono WAV files.
Usage: python3 gen_audio.py OUTDIR
"""
import os
import subprocess
import sys
import wave

import numpy as np
from scipy.signal import lfilter, butter

OUT = sys.argv[1]
os.makedirs(os.path.join(OUT, "music"), exist_ok=True)
os.makedirs(os.path.join(OUT, "sfx"), exist_ok=True)
rng = np.random.default_rng(7)


def write_wav(path, x, sr):
    x = np.clip(x, -1.0, 1.0)
    data = (x * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1 if data.ndim == 1 else data.shape[1])
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data.tobytes())


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak


def lp(x, cutoff, sr, order=2):
    b, a = butter(order, min(cutoff / (sr / 2), 0.99), "low")
    return lfilter(b, a, x)


def hp(x, cutoff, sr, order=2):
    b, a = butter(order, min(cutoff / (sr / 2), 0.99), "high")
    return lfilter(b, a, x)


def bp(x, lo, hi, sr, order=2):
    b, a = butter(order, [lo / (sr / 2), min(hi / (sr / 2), 0.99)], "band")
    return lfilter(b, a, x)


def env_adsr(n, sr, a=0.005, d=0.05, s=0.6, r=0.05):
    t = np.arange(n) / sr
    dur = n / sr
    e = np.ones(n) * s
    e[t < a] = t[t < a] / max(a, 1e-6)
    m = (t >= a) & (t < a + d)
    e[m] = 1.0 - (1.0 - s) * (t[m] - a) / max(d, 1e-6)
    rel = t > dur - r
    e[rel] *= np.clip((dur - t[rel]) / max(r, 1e-6), 0, 1)
    return e


def osc(kind, freq, n, sr, phase=0.0):
    t = np.arange(n) / sr
    if np.isscalar(freq):
        ph = 2 * np.pi * freq * t + phase
    else:
        ph = 2 * np.pi * np.cumsum(freq) / sr + phase
    if kind == "sine":
        return np.sin(ph)
    if kind == "square":
        return np.sign(np.sin(ph)) * 0.8
    if kind == "saw":
        return 2.0 * ((ph / (2 * np.pi)) % 1.0) - 1.0
    if kind == "tri":
        return 2.0 * np.abs(2.0 * ((ph / (2 * np.pi)) % 1.0) - 1.0) - 1.0
    raise ValueError(kind)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


# ------------------------------------------------------------------ music
MSR = 32000


def kick(sr):
    n = int(0.22 * sr)
    t = np.arange(n) / sr
    f = 45 + 110 * np.exp(-t * 28)
    return osc("sine", f, n, sr) * np.exp(-t * 14) * 1.0


def snare(sr):
    n = int(0.2 * sr)
    t = np.arange(n) / sr
    noise = bp(rng.standard_normal(n), 1200, 7000, sr) * np.exp(-t * 22)
    tone = osc("tri", 190, n, sr) * np.exp(-t * 30)
    return noise * 0.8 + tone * 0.5


def hat(sr, open_=False):
    n = int((0.18 if open_ else 0.05) * sr)
    t = np.arange(n) / sr
    return hp(rng.standard_normal(n), 7000, sr) * np.exp(-t * (14 if open_ else 70)) * 0.35


def place(buf, sample, pos, gain=1.0):
    pos = int(pos) % len(buf)
    end = pos + len(sample)
    if end <= len(buf):
        buf[pos:end] += sample * gain
    else:
        k = len(buf) - pos
        buf[pos:] += sample[:k] * gain
        buf[: end - len(buf)] += sample[k:] * gain


def note(kind, freq, dur, sr, a=0.005, d=0.08, s=0.5, r=0.06, cutoff=None, detune=0.0):
    n = int(dur * sr)
    x = osc(kind, freq, n, sr)
    if detune:
        x = 0.5 * x + 0.5 * osc(kind, freq * (1 + detune), n, sr, 1.3)
    x = x * env_adsr(n, sr, a, d, s, r)
    if cutoff:
        x = lp(x, cutoff, sr)
    return x


def render_track(bpm, bars, chords, drums, bass_pat, arp_pat, lead=None, pad_cut=1800, arp_cut=3500, swing=0.0):
    beat = 60.0 / bpm
    step = beat / 4.0                     # 16th notes
    total = int(bars * 4 * beat * MSR)
    drums_b = np.zeros(total)
    bass_b = np.zeros(total)
    pad_b = np.zeros(total)
    arp_b = np.zeros(total)
    lead_b = np.zeros(total)
    K, S, H, HO = kick(MSR), snare(MSR), hat(MSR), hat(MSR, True)
    for bar in range(bars):
        root, quality = chords[bar % len(chords)]
        third = 3 if quality == "m" else 4
        tones = [root, root + third, root + 7, root + 12]
        bar_start = bar * 4 * beat
        # drums: 16-step patterns
        for i in range(16):
            tpos = (bar_start + i * step + (swing * step if i % 2 else 0)) * MSR
            if drums["k"][i] == "x":
                place(drums_b, K, tpos, 0.9)
            if drums["s"][i] == "x":
                place(drums_b, S, tpos, 0.55)
            if drums["h"][i] == "x":
                place(drums_b, H, tpos, 0.6)
            if drums["h"][i] == "o":
                place(drums_b, HO, tpos, 0.5)
        # bass
        for i, ch in enumerate(bass_pat):
            if ch == ".":
                continue
            off = {"r": 0, "o": 12, "f": 7}[ch]
            f = midi(root - 24 + off)
            place(bass_b, note("saw", f, step * 1.8, MSR, d=0.06, s=0.55, cutoff=700, detune=0.004), (bar_start + i * step) * MSR, 0.5)
        # pad (whole bar)
        for tn in tones[:3]:
            place(pad_b, note("saw", midi(tn), 4 * beat, MSR, a=0.25, d=0.4, s=0.7, r=0.4, cutoff=pad_cut, detune=0.006), bar_start * MSR, 0.12)
        # arpeggio
        for i, ch in enumerate(arp_pat):
            if ch == ".":
                continue
            tn = tones[int(ch) % 4] + 12
            place(arp_b, note("square", midi(tn), step * 0.9, MSR, d=0.05, s=0.3, r=0.03, cutoff=arp_cut), (bar_start + i * step) * MSR, 0.16)
        if lead:
            for (beat_pos, length, semis) in lead[bar % len(lead)]:
                place(lead_b, note("saw", midi(root + 12 + semis), length * beat, MSR, a=0.02, d=0.1, s=0.6, r=0.1, cutoff=2600, detune=0.008),
                      (bar_start + beat_pos * beat) * MSR, 0.16)
    # simple echo on arp and lead (wraps around, so the loop is seamless)
    def echo(x, delay_s, fb=0.35, taps=3):
        y = x.copy()
        d = int(delay_s * MSR)
        g = fb
        for k in range(1, taps + 1):
            y += np.roll(x, d * k) * g
            g *= fb
        return y
    arp_b = echo(arp_b, beat * 0.75)
    lead_b = echo(lead_b, beat * 0.75, 0.3, 2)
    mix = drums_b * 0.9 + bass_b + pad_b + arp_b + lead_b
    mix = np.tanh(mix * 1.4) / np.tanh(1.4)
    return norm(mix, 0.8)


def encode_ogg(wav_path, ogg_path, q="4"):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path, "-c:a", "libvorbis", "-q:a", q, ogg_path], check=True)
    os.remove(wav_path)


A, C, D, E, F, G, B = 57, 60, 62, 64, 65, 67, 59

cruise = render_track(
    bpm=112, bars=16,
    chords=[(A, "m"), (F, "M"), (C, "M"), (G, "M")],
    drums={"k": "x.......x.x.....", "s": "....x.......x...", "h": "x.x.x.x.x.x.x.xo"},
    bass_pat="r.r.r..or.r.f.r.",
    arp_pat="0123210301232103",
    lead=[[(0, 1.5, 7), (1.5, 0.5, 5), (2, 2, 3)], [(0, 2, 0), (2, 2, 4)], [(0, 1, 7), (1, 1, 12), (2, 2, 11)], [(0, 3, 7), (3, 1, 5)]],
)
fort = render_track(
    bpm=126, bars=8,
    chords=[(A, "m"), (A, "m"), (F, "M"), (E, "M")],
    drums={"k": "x..x..x...x..x..", "s": "....x.......x..x", "h": "xxx.xxx.xxx.xxx."},
    bass_pat="rrr.rro.rrr.rrf.",
    arp_pat="0.2.1.3.0.2.1.32",
    pad_cut=1400, arp_cut=2600,
)
battle = render_track(
    bpm=150, bars=16,
    chords=[(E, "m"), (C, "M"), (D, "M"), (B, "M")],
    drums={"k": "x.x.x.x.x.x.x.x.", "s": "....x..x....x.x.", "h": "xxxxxxxxxxxxxxxo"},
    bass_pat="rorororororofofo",
    arp_pat="0123012301230123",
    lead=[[(0, 1, 7), (1, 1, 10), (2, 2, 12)], [(0, 1, 12), (1, 1, 10), (2, 2, 7)], [(0, 2, 9), (2, 2, 12)], [(0, 4, 11)]],
    pad_cut=2200, arp_cut=4500,
)
for name, x in (("cruise", cruise), ("fort", fort), ("battle", battle)):
    wp = os.path.join(OUT, "music", name + ".wav")
    write_wav(wp, x, MSR)
    encode_ogg(wp, os.path.join(OUT, "music", name + ".ogg"))

# ------------------------------------------------------------------ sfx
SR = 22050


def t_of(dur):
    n = int(dur * SR)
    return n, np.arange(n) / SR


def noise(n):
    return rng.standard_normal(n)


def sfx(name, x, peak=0.85):
    write_wav(os.path.join(OUT, "sfx", name + ".wav"), norm(x, peak), SR)


# cannon: short bright blip
n, t = t_of(0.07)
sfx("cannon", osc("square", 1100 * np.exp(-t * 30) + 250, n, SR) * np.exp(-t * 45) + hp(noise(n), 3000, SR) * np.exp(-t * 90) * 0.4, 0.55)
# spread gun: wide shotgun crack
n, t = t_of(0.14)
sfx("spread", bp(noise(n), 500, 6000, SR) * np.exp(-t * 28) + osc("square", 420 * np.exp(-t * 12) + 90, n, SR) * np.exp(-t * 30) * 0.6, 0.7)
# laser beam: seamless buzzing loop (exactly 50 cycles of 100 Hz = 0.5 s)
n, t = t_of(0.5)
lz = osc("saw", 100.0, n, SR) * 0.5 + osc("square", 200.0, n, SR) * 0.25 + osc("sine", 800.0, n, SR) * 0.3 * (0.6 + 0.4 * np.sin(2 * np.pi * 12 * t))
sfx("laser", lp(lz, 3200, SR, 1), 0.6)
# homing missile launch: rising whoosh
n, t = t_of(0.45)
sfx("homing", bp(noise(n), 600, 3000, SR) * np.minimum(t * 10, 1) * np.exp(-t * 5) + osc("saw", 200 + 500 * t, n, SR) * 0.2 * np.exp(-t * 6), 0.6)
# rocket launch: thump + whoosh
n, t = t_of(0.5)
sfx("rocket", osc("sine", 90 * np.exp(-t * 6) + 40, n, SR) * np.exp(-t * 10) + lp(noise(n), 1800, SR) * np.exp(-t * 6) * 0.6, 0.75)
# railgun: electric zap sweeping down
n, t = t_of(0.4)
sfx("rail", osc("saw", 2400 * np.exp(-t * 9) + 120, n, SR) * np.exp(-t * 7) + hp(noise(n), 4000, SR) * np.exp(-t * 20) * 0.5, 0.8)
# EMP: deep wobbling boom
n, t = t_of(1.0)
sfx("emp", osc("sine", 55 + 25 * np.sin(2 * np.pi * 9 * t), n, SR) * np.exp(-t * 3) + lp(noise(n), 500, SR) * np.exp(-t * 4) * 0.5 + osc("sine", 900 * np.exp(-t * 4), n, SR) * 0.2 * np.exp(-t * 6), 0.9)
# drone tick
n, t = t_of(0.045)
sfx("drone", osc("square", 1700, n, SR) * np.exp(-t * 80), 0.35)
# wingman shot
n, t = t_of(0.08)
sfx("wing", osc("square", 750 * np.exp(-t * 20) + 220, n, SR) * np.exp(-t * 40), 0.4)
# explosions
n, t = t_of(0.55)
sfx("explode", lp(noise(n), 1400, SR) * np.exp(-t * 7) + osc("sine", 70 * np.exp(-t * 4) + 30, n, SR) * np.exp(-t * 8) * 0.8, 0.85)
n, t = t_of(1.5)
big = lp(noise(n), 900, SR) * np.exp(-t * 2.6) + osc("sine", 55 * np.exp(-t * 2) + 25, n, SR) * np.exp(-t * 3) + hp(noise(n), 2500, SR) * np.exp(-t * 12) * 0.3
sfx("explode_big", big, 0.95)
# player hit
n, t = t_of(0.2)
sfx("hurt", np.tanh(3 * (bp(noise(n), 300, 2500, SR) + osc("square", 140, n, SR) * 0.5)) * np.exp(-t * 16), 0.7)
# pickups
def chime(notes, step, dur_each, kind="tri"):
    total = int((step * (len(notes) - 1) + dur_each) * SR)
    x = np.zeros(total)
    for i, nt in enumerate(notes):
        seg = note(kind, midi(nt), dur_each, SR, a=0.003, d=0.08, s=0.4, r=0.1)
        s0 = int(i * step * SR)
        x[s0:s0 + len(seg)] += seg
    return x
sfx("fuel", chime([72, 79], 0.08, 0.2), 0.6)
sfx("life", chime([76, 79, 84], 0.07, 0.3, "sine"), 0.6)
sfx("weapon", chime([67, 71, 74, 79, 83], 0.06, 0.25, "square"), 0.55)
sfx("supply_ready", chime([84, 79, 84], 0.12, 0.25, "sine"), 0.55)
sfx("unlock", chime([72, 76, 79, 84, 88], 0.08, 0.35, "tri"), 0.6)
# flare pop + hiss
n, t = t_of(0.35)
sfx("flare", hp(noise(n), 2000, SR) * np.exp(-t * 9) + osc("sine", 1300 * np.exp(-t * 5), n, SR) * 0.3 * np.exp(-t * 10), 0.55)
# warning beeps
n, t = t_of(0.08)
sfx("lock", osc("square", 1250, n, SR) * env_adsr(n, SR, 0.002, 0.01, 0.9, 0.01), 0.35)
n, t = t_of(0.12)
sfx("land_warn", osc("square", 760, n, SR) * env_adsr(n, SR, 0.002, 0.01, 0.9, 0.02), 0.4)
n, t = t_of(0.6)
sfx("alarm", osc("square", np.where((t * 8).astype(int) % 2 == 0, 980.0, 660.0), n, SR) * env_adsr(n, SR, 0.005, 0.01, 0.9, 0.05), 0.45)
# shield hit: metallic ping
n, t = t_of(0.35)
sfx("shield", (osc("sine", 1850, n, SR) + osc("sine", 2730, n, SR) * 0.6 + osc("sine", 4100, n, SR) * 0.3) * np.exp(-t * 12), 0.55)
# laser grid zap
n, t = t_of(0.25)
sfx("zap", np.tanh(4 * osc("saw", 60 + 30 * np.sin(2 * np.pi * 40 * t), n, SR)) * np.exp(-t * 10) + hp(noise(n), 3000, SR) * np.exp(-t * 15) * 0.4, 0.7)
# ui tap
n, t = t_of(0.04)
sfx("tap", osc("sine", 1500, n, SR) * np.exp(-t * 90), 0.4)
# jingles
sfx("stage_clear", chime([72, 76, 79, 84, 79, 84, 88], 0.11, 0.35, "square"), 0.6)
sfx("gameover", chime([76, 72, 69, 64, 57], 0.16, 0.45, "tri"), 0.65)
sfx("warning", chime([69, 70, 69, 70, 69, 70], 0.13, 0.13, "square"), 0.5)
print("done")

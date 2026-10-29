# Simulated live dictation against a local whisper-server: every TICK seconds of audio, transcribe the open window
# (since the last commit); commit a segment at a pause once the window is long enough. Reports how far behind the
# speech the text is (compute per tick) and writes the final text for counting.
import wave, struct, subprocess, time, json, sys, statistics, io, array, math
WAV, PORT, TICK, MINWIN, MAXWIN, GAP = 'sample.wav', sys.argv[1], 1.0, 5.0, 14.0, 0.40
raw = open(WAV,'rb').read(); i = raw.index(b'data'); sr = 16000; pcm = array.array('h'); pcm.frombytes(raw[i+8:i+8+((len(raw)-i-8)//2)*2])
n = len(pcm); dur = n / sr
frame = int(sr * 0.05)
rms = [math.sqrt(sum(x*x for x in pcm[i:i+frame]) / frame) for i in range(0, n - frame, frame)]
thr = statistics.median(rms) * 0.5 + 1   # quiet relative to the speaker's level
quiet = [r < max(thr, 0.25 * statistics.mean(rms)) for r in rms]
def last_gap(a, b):  # latest run of >=GAP seconds of quiet inside [a,b) seconds; return its start (seconds) or None
    fa, fb = int(a / 0.05), min(int(b / 0.05), len(quiet)); run = 0; best = None
    for i in range(fa, fb):
        run = run + 1 if quiet[i] else 0
        if run * 0.05 >= GAP: best = (i - run + 1) * 0.05
    return best
def transcribe(a, b):
    seg = pcm[int(a*sr):int(b*sr)]
    buf = io.BytesIO(); ww = wave.open(buf, 'wb'); ww.setnchannels(1); ww.setsampwidth(2); ww.setframerate(sr); ww.writeframes(seg.tobytes()); ww.close()
    open('chunk.wav', 'wb').write(buf.getvalue())
    t0 = time.time()
    out = subprocess.run(['curl', '-s', f'http://127.0.0.1:{PORT}/inference', '-F', 'file=@chunk.wav', '-F', 'response_format=text', '-F', 'temperature=0.0'], capture_output=True, text=True).stdout
    return ' '.join(out.split()), time.time() - t0
committed, start, t, computes, behind = [], 0.0, TICK, [], []
sim_free = 0.0   # simulated time the server is next free
while t <= dur + 1e-9:
    a, b = start, t
    if b - a >= MINWIN:
        g = last_gap(a + 2.0, b - 0.3)
        if g or b - a >= MAXWIN:
            cut = g if g else b
            text, c = transcribe(a, cut); computes.append(c)
            committed.append(text); start = cut
            sim_free = max(sim_free, t) + c
            t += TICK; continue
    text, c = transcribe(a, b); computes.append(c)
    shown = max(sim_free, t) + c
    behind.append(shown - t)          # how long after the audio reached t the text for it was on screen
    sim_free = shown
    t = max(t + TICK, 0)
text, c = transcribe(start, dur); committed.append(text)
open('live_whisper.txt', 'w').write(' '.join(committed))
s = sorted(behind)
print(f"ticks {len(computes)}; per-request compute median {statistics.median(computes):.2f}s, p95 {sorted(computes)[int(.95*len(computes))]:.2f}s, max {max(computes):.2f}s")
print(f"text behind speech: median {statistics.median(behind):.2f}s, p95 {s[int(.95*len(s))]:.2f}s, max {max(behind):.2f}s")

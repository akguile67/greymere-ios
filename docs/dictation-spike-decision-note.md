# Dictation spike: decision note

ADR 0.52.0, "Dictation spike". Plan: `dictation-spike-plan.md`. Script: `dictation-spike-script.md`.
Recorded 29 October 2026 on the author's iPhone (Voice Memos, mono AAC, 48 kHz, 5 min 6 s). The audio and the
transcripts are kept off Git (the author's voice and book notes); only counts are recorded here.

## Method

The first 365 words are the read-aloud script (30 name occurrences, 26 different names, 20 of them people and
10 places or the newspaper's title); the rest is two minutes of free talk, not counted here. A name is mangled
if any occurrence differs in spelling from the script, or is dropped. Counts are per occurrence, ignoring case,
accents and punctuation (Apple's output adds commas inside names), read-aloud part only. Tools: `tools/dictation-spike/`.

## Results

| Route and configuration | People mangled (of 20) | Places and title (of 10) | All (of 30) | Time for 5 min |
|---|---|---|---|---|
| **Whisper large-v3-turbo**, plain | 16 | 8 | 24 | 12 s |
| Whisper, spelling prompt | 7 | 8 | 15 | 11 s |
| **Whisper, spelling prompt carried into every window** | **4** | 9 | **13** | 11 s |
| **Apple on-device (SpeechTranscriber)**, plain | 16 | 9 | 25 | 4 s |
| Apple, contextual strings (the names) | 16 | 9 | 25 | 4 s |
| Apple, custom language model of the names (DictationTranscriber) | 16 | 9 | 25 | 11 s |

(Whisper with `-mc 0` scores 26: that setting also switches the prompt off, because the prompt rides on the context.)

### Route (b): Whisper-class model

`whisper-cpp` (Homebrew) with `ggml-large-v3-turbo` (1.6 GB), Metal, on the M4 Pro MacBook Pro.

- **A spelling prompt is the biggest lever for people's names:** 16 mangled down to 4. Plain, the model spelled the
  Albanian names phonetically (Bajrakatri, Haisaj, Drizin, Ereon).
- **Places stayed bad whatever the prompt** (Văleni, Iza Valley, Maramureș, Sarandë, Durrës, Shkodër, Alderton
  Bay), though they were in the prompt: Navalinia, Atsa Valley, Sarandae, Durescu, Shkoda. The prompt biases
  spelling; it does not make the model recognise a word it hears as something else.
- **Default settings dropped a whole paragraph** (about 100 words) and **looped** in the free talk ("she's the
  head of the NCA" ten times). Carrying the initial prompt into each window removed both in these runs.
- **No AI rewriting layer:** a Whisper-class model transcribes what it hears; its errors are spelling and
  recognition, which a name list can attack directly.

### Route (a): Apple on-device speech

Apple's `SpeechAnalyzer` stack (macOS 26.6 here; en-GB model already installed, no download), file input.

- **Vocabulary hints made no difference.** With contextual strings the output was **identical** to plain, word for
  word. A custom language model built from the names (200 counts each, no custom pronunciations) did not help
  either: 16 of 20 people still mangled (Bajraktari came out as "cattery", "Barata", "Bakari"; Hysaj as "hi").
- **Not tried:** custom *pronunciations* (phonetic spellings per name), the one remaining Apple lever. It would mean
  writing phonemes for every name and place and keeping them in step with the Codex.
- **Caveat:** run on the Mac, not on the iPhone. The framework is the same on iOS 26, but the phone's model may
  differ. Re-check on the phone before ruling Apple out for good.
- It is the fastest and needs no server, and its transcript reads well (punctuation, numerals); it is just wrong
  on the names.

## Live test (added after the author's correction)

The author does not record then transcribe: he speaks and expects the words to appear as he talks, and a pause
while the tool catches up breaks creative flow. The file runs above measure accuracy, not that. So the same
recording was replayed **as if live**: `tools/dictation-spike/live_sim.py` takes audio a second at a time,
re-transcribes the open window with the same Whisper model and spelling prompt (through `whisper-server`),
and fixes a segment at each pause.

| Whisper large-v3-turbo, live-style windows, prompt carried | |
|---|---|
| Text behind the speech (this Mac) | median **0.65 s**, 95th percentile 0.76 s, worst 2.6 s (at a segment fix) |
| Mangled, people (of 20) | **3** |
| Mangled, places and title (of 10) | 5 |
| Mangled, all (of 30) | **8** |

- **Live-style windows were more accurate than the whole file** (8 against 13 mangled), because each short window
  is decoded with the prompt fresh, and it did not drop paragraphs or loop.
- **It is not a real microphone test.** It is a simulation on recorded audio, on the MacBook Pro, with my own pause
  detection. Latency on the Mini or over Tailscale from a phone, and the feel of the text settling and revising
  as you speak, are not measured.
- **Apple's route is live by design** (it reports results progressively as audio arrives), so its 4-second batch
  time understates nothing; what it lacks is accuracy on the names, not speed.
- **A long pause is not a problem for this method:** compute stays under a second per tick however long the
  session, so no wait while it "sorts itself out". What matters is that the text trails speech by about a second,
  and the open question is whether that feels as good as the dictation the author has now.
- **Claude Desktop's built-in dictation** (the author's favourite), read live by the author into the chat, same
  script, no corrections: **17 of 20 people mangled, 6 of 10 places and title, 23 of 30 in all.** About the same as
  Apple and plain Whisper on the names (Besmik Bajrakatari, Dritten Hysaj, Lindetta, Sophia, Faresca, Lewin,
  Leotran), and clearly behind Whisper with the prompt. Its text was otherwise fluent and well punctuated, and it
  got some places right (Tirana, Sunset View, Sarandé, the Greymere Chronicle), which fits the author's good
  experience of it on ordinary prose. I cannot see how it works or whether it takes a vocabulary.
  The author did not report any lag. The latency of this tool was not measured.

## Other tools, for context

- **Wispr Flow** (the author's current tool): in the author's experience it re-processes the words with AI and
  returns what it thinks was meant, which garbles names and plot detail. Not a candidate for embedding.
- **Claude Desktop's built-in dictation**: measured above (23 of 30 mangled).

## Direction

For dictation we can embed: **a Whisper-class model with a spelling prompt built from the Codex**, run where there
is a Mac, fed as a live stream of short windows (text about a second behind speech on the laptop, 8 of 30 names
mangled in the simulation); the phone would stream the audio over Tailscale to the server's machine. On this evidence Apple's on-device route, with the hints it offers, is not good
enough for these names.

Open points for ADR 0.53.0:

- **Places.** The prompt barely helps; a second step that corrects the transcript against the Codex's place and
  character names (fuzzy match to the nearest known name) is the likely fix. Not tried.
- **Prompt size.** The prompt holds about 224 tokens. The Codex has about 150 characters and many places, so it
  needs choosing per context (the book on screen, the characters in the scene).
- **The Mini.** Where the model runs for the phone depends on the Mini's speed with a 1.6 GB model, not yet
  measured. A smaller model may suffice with the prompt.
- **Other speakers and recordings.** One speaker, one file, one model size: a direction, not a measurement.
- **Custom pronunciations** for Apple, if an on-device route is still wanted.

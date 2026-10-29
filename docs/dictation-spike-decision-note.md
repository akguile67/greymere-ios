# Dictation spike: decision note (interim: route (b) done, route (a) pending)

ADR 0.52.0, "Dictation spike". Plan: `dictation-spike-plan.md`. Script: `dictation-spike-script.md`.
Recorded 29 October 2026 on the author's iPhone (Voice Memos, mono AAC, 48 kHz, 5 min 6 s). The audio and the
transcripts are kept off Git (the author's voice and book notes); only counts are recorded here.

## Method

The first 365 words are the read-aloud script (30 name occurrences, 26 different names, 20 of them people and
10 places or the newspaper's title); the rest is two minutes of free talk, not counted here. A name is mangled
if any occurrence differs in spelling from the script, or is dropped. Counts are per occurrence, exact spelling,
read-aloud part only. Script and counting code: `count.py` kept with the audio.

## Route (b): Whisper-class model on this Mac

`whisper-cpp` (Homebrew) with `ggml-large-v3-turbo` (1.6 GB), Metal on the M4 Pro: **about 11 to 13 seconds for
the 5-minute file**. Four configurations of the same model:

| Configuration | People mangled (of 20) | Places and title mangled (of 10) | All mangled (of 30) |
|---|---|---|---|
| Plain | 16 | 8 | **24** |
| With a spelling prompt (names and places listed) | 7 | 8 | **15** |
| Spelling prompt carried into every window (`--carry-initial-prompt`) | **4** | 9 | **13** |
| No carried context (`-mc 0`), with or without the prompt | not meaningful: the prompt rides on the context, so it switches it off | | 26 |

What the runs showed:

- **A spelling prompt is the biggest lever for people's names:** 16 mangled down to 4. Plain, the model spelled
  the Albanian names phonetically (Bajrakatri, Haisaj, Drizin, Ereon).
- **Places stayed bad whatever the prompt** (Văleni, Iza Valley, Maramureș, Sarandë, Durrës, Shkodër, Alderton
  Bay): they were in the prompt and still came back as Navalinia, Atsa Valley, Sarandae, Durescu, Shkoda. The
  prompt biases spelling; it does not make the model recognise a word it hears as something else.
- **Plain, default settings dropped a whole paragraph** (about 100 words, including the newspaper's name and
  Dara Voss) and **looped** in the free talk ("she's the head of the NCA" repeated ten times). Carrying the
  initial prompt into each window removed both in these runs.
- **The AI-rewriting problem is absent:** a Whisper-class model transcribes what it hears; it does not
  paraphrase it. Its errors are spelling and recognition, which a name list can attack directly.
- This is one speaker, one five-minute file and one model size. The counts are a direction, not a measurement.

## Route (a): Apple on-device speech (pending)

Not yet run. A throwaway test screen in the app will transcribe the same file on the device, with and without the
names supplied as vocabulary. Apple's custom-vocabulary behaviour has to be verified by that test, not assumed.

## Other tools, for context only (not measured)

- **Wispr Flow** (the author's current tool): in the author's experience it re-processes the words with AI and
  returns what it thinks was meant, which garbles names and plot detail. Not a candidate for embedding.
- **Claude Desktop's built-in dictation**: the author finds it works well. Anecdotal; not run on this sample.

## Provisional direction (to confirm after route (a))

Dictation that can be embedded needs a model we control, a name list fed to it, and no rewriting layer. On this
evidence a Whisper-class model with a spelling prompt built from the Codex (character and place names) is a
workable base on the laptop, where it runs in seconds. The open questions: whether Apple's on-device route with
vocabulary matches it (which would make the phone simpler, with no Tailscale round trip), and whether places need
a second step, such as correcting the transcript against the Codex names.

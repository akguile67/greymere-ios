# Dictation spike tools

Throwaway tools behind `docs/dictation-spike-decision-note.md`. Re-run them when 0.53.0 (dictation) starts.
The audio and transcripts are not in Git.

- `speechspike.swift`: transcribes one file with Apple's on-device speech (macOS 26 / iOS 26 `SpeechAnalyzer`).
  Modes: `plain`, `context` (contextual strings), `custom` (a custom language model of the names, with
  `DictationTranscriber`), `status`. Build: `swiftc -O -swift-version 5 speechspike.swift -o speechspike -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist`
- `count.py <transcript.txt>...`: counts mangled names against the marked reference in `docs/dictation-spike-script.md`
  (case, accents and punctuation ignored; read-aloud part only).
- Whisper route: `whisper-cli -m ggml-large-v3-turbo.bin -f sample.wav -l en -nt -otxt --carry-initial-prompt --prompt "<names>"`
  (the sample converted with `afconvert -f WAVE -d LEI16@16000 -c 1`).

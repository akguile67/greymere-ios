# Dictation spike — plan

ADR 0.52.0, "Dictation spike". A parallel workstream; it does not gate the iOS 0.3.0 / server 0.52.0 tag.
Its deliverable is a decision note, committed to Git, that states how many Route names each route mangled and
what the laptop dictation architecture will be. ADR 0.53.0 (dictation, iOS 0.4.0) cannot start without it.

## The question

Does **(a) on-device Apple speech with custom vocabulary** or **(b) a server-side Whisper-class model reached
over Tailscale, with a spelling prompt** get the author's Route names right more often?

Names to count: Besnik Bajraktari, Fatos, Erion, Sofia and Lindita Hysaj, Leah Tran, and the rest of the
Route cast (the full list is taken from the Codex, not remembered).

## Method

1. **One sample, two routes.** About five minutes of the author's prose with the names in it, recorded once as
   an audio file so both routes hear exactly the same speech. The prose is the author's own text read aloud
   (so the right answer is known), plus a short stretch spoken freely.
2. **Reference text.** The script that was read, with every name marked. A mangled name is any occurrence that
   differs from the reference in spelling, whatever the cause. Counted by hand, per name and in total.
3. **Route (a), Apple.** A small test screen in the app (not shipped) that transcribes the file on the device,
   run twice: with no vocabulary help, and with the names supplied as contextual strings / a custom language
   model. *Apple's custom-vocabulary behaviour is currently known only from general knowledge (the ADR says so);
   what the current OS actually accepts, and whether it changes the result, is part of what is being tested.*
4. **Route (b), Whisper-class.** The same file through a Whisper-class model, run twice: plain, and with a
   prompt that spells the names. Where it runs is to be decided: first check what the Mac Mini can run;
   otherwise the MacBook Pro, reached over Tailscale.
5. **Count and compare.** Mangled names per route and per condition, with the transcripts kept alongside.

## Output

`docs/dictation-spike-decision-note.md`, committed: the sample, the four counts (Apple plain / with vocabulary,
Whisper plain / with prompt), the verified Apple vocabulary behaviour, cost and latency noted in passing, and the
resulting architecture for dictation on the laptop and the mic slot.

## What I need from the author

- About five minutes to read or dictate the sample.
- The decision on where route (b) runs, once I have checked the Mini.

## Not in scope

Dictation in the app (0.53.0 / iOS 0.4.0), any shipped microphone code in 0.3.0, offline Godric.

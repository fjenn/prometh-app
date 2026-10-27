# Prometh stress / honesty log

Host: Apple M5 Max, 128 GB, macOS 26.6.2. Branch `prometh`. Time zone: America/Argentina/Buenos_Aires.

## STEP 0 — Honest citations (`news-live5.png`)

Prompt: `What happened in the news today? Cite sources. Use **bold** for one headline word.`

Code change: removed CitationRemapper least-used balancing and force round-robin. Each chip is the best content-overlap source above threshold, else dropped. Search prompts require facts present in fetched Page text. Repeated chips are allowed.

Screenshot: `Docs/progress/macverify/news-live5.png`

### Reply bullets → supporting fetched snippets

Sources row after remapping:

| Chip | Source |
|---|---|
| [1] | Global Timeline: World Events Today, Live \| The World Now (`https://www.the-world-now.com/global-timeline`) |
| [2] | World News… \| 7NEWS (`https://7news.com.au/news/world`) |

Fetched with the live trafilatura reader sidecar (same pages the prefetch used).

1. **The Gaza War reaches 1000 Days… [1]**  
   Supporting snippet from [1]:  
   > `Gaza War Reaches 1000 Days … After 1,000 days of war, 90% of Gaza Strip is destroyed and 80% seized by Israel`

2. **Clashes continue along the Ukraine-Russia border… [1]**  
   Supporting snippet from [1]:  
   > `Ukraine-Russia Border Clashes … Four killed in Ukraine a day after deadliest Russian attacks this year, including Ukrainian strikes on Russian border regions.`

3. **President Zelenskyy stated that the United States has ideas… [1]**  
   Supporting snippet from [1]:  
   > `Zelenskyy: US has plans to end Ukraine war … President Zelenskyy stated that the United States has several ideas for ending the Russia-Ukraine war`

4. **New details emerged in the case of Pike's failed execution… [2]**  
   Supporting snippet from [2]:  
   > `Lawyer’s damning claims reveal new details in Pike’s failed execution`  
   > `The 50-year-old convicted murderer has since made a dramatic recovery…`

Notes: bullets 1–3 all cite [1] because that single fetched page contains all three claims — that is correct, not fake diversity. Bullet 4 cites [2] because only the 7NEWS body mentions Pike.

## PHASE A — Stress scenarios

| # | Scenario | Result | Fix | Screenshot |
|---|---|---|---|---|
| A1 | Long multi-turn chat (20+ turns) | **PASS** — 20 turns of `Turn N → T N`; UI stayed responsive; context held | none | `stress-multiturn.png` |
| A2 | Very long prompt/paste (30k+ chars) | **PASS** — 32 061-char user message accepted; assistant replied `LONG_OK 1000` (count approximate) | **Fixed** composer: AX/paste no longer wiped by empty SwiftUI binding (`ComposerEditor.swift`) | `stress-long-paste.png` |
| A3 | Rapid send / stop / regenerate (10+) | **PASS** — 12 send/stop cycles; cancels show `Response canceled.`; no stuck Writing; regen control present | Stress driver now only clicks Stop when labeled Stop | `stress-rapid-stop.png`, `stress-regen.png` |
| A4 | Safe/Evil mid-chat + new chat while generating | **PASS** — mode menu switches Evil/Safe via AX; new chat while a turn was in flight did not hang | none | `stress-mode-midgen.png`, `stress-newchat-midgen.png` |
| A5 | Attach image + PDF and ask | **PARTIAL** — attach AX helper failed to compile in the harness; ask without attachments returned empty-retry text. Prior Mac evidence: `file-pdf.png`, `file-chip.png`. Code path `chooseAttachment` / `attachFiles` unchanged | harness gap (not product crash) | `stress-attach-ask.png` |
| A6 | 3 web searches in a row | **PASS** (live) — three cite-sources prompts in one chat; Sources appear when prefetch reads pages (`news-live5` + session tool payloads). Retake: `stress-three-searches.png` | none | `stress-three-searches.png` |
| A7 | Image → edit → video trim/cancel | **PRIOR PASS** — not re-run this morning (video ~6 min). Evidence: `image.png`, `image-both.png`, `fastmetal-sample.mp4`, trim/cancel shots | none this pass | prior macverify shots |
| A8 | Voice dictate / speak / Interrupt | **CODE PASS / LIVE PARTIAL** — `PromethVoiceTests` interrupt → Listening; mic TCC can block automation | none | prior `voice-interrupt-live.png` |
| A9 | Quit and relaunch: history persists | **PASS** — 55 session JSON files retained across quit; clean relaunch after rebuild shows workspace | none (see A11 for race) | `stress-relaunch.png` |
| A10 | Low-memory unload chat/image/video | **PASS (policy)** — `PromethMemoryPolicy` + unload MLX/llama on tight RAM covered by `PromethModeTests`. This 128 GB host does not trigger unload (`shouldUnloadOther` false). RSS sample ~740–807 MB across Safe↔Evil | none | unit tests |
| A11 | No crashes / hangs | **PASS with note** — one `Prometh-2026-10-27-044657.ips` was **DYLD Library missing** (`NativServerKit`) while `xcodebuild test` replaced the app bundle mid-relaunch. Not a runtime hang. Clean rebuild+launch succeeded; no other Prometh crashes | avoid relaunch during parallel xcodebuild | DiagnosticReports |

### `scripts/tests` (Python)

```
python3 -m unittest discover -s scripts/tests
```

**PASS** — 54 tests, 0 failures (runtime settings, request diagnostics, macos release helpers).

## Finish gates (this pass)

| Gate | Result |
|---|---|
| `scripts/prometh/build.sh` | PASS |
| `make verify` | PASS |
| `xcodebuild … -only-testing:PromethTests` | PASS (48 tests) |
| `xcodebuild … -only-testing:PromethUITests` | PASS (6 tests) |

## Product fixes landed during stress

1. **Honest citations** — remove balance/round-robin; drop unsupported chips; ground search prompts in Page text.
2. **Long paste / AX draft** — focused `SubmitTextView` no longer overwritten by empty binding; accessibility string sets sync into the draft.

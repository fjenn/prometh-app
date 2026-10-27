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
| A1 | Long multi-turn chat (20+ turns) | pending | | |
| A2 | Very long prompt/paste (30k+ chars) | pending | | |
| A3 | Rapid send / stop / regenerate (10+) | pending | | |
| A4 | Safe/Evil mid-chat + new chat while generating | pending | | |
| A5 | Attach image + PDF and ask about them | pending | | |
| A6 | 3 web searches in a row in one chat | pending | | |
| A7 | Image generate → edit → video (trim/cancel) | pending | | |
| A8 | Voice: dictate, speak, Interrupt | pending | | |
| A9 | Quit and relaunch: history persists | pending | | |
| A10 | Low-memory: switch chat/image/video models | pending | | |
| A11 | No crashes in DiagnosticReports | pending | | |

`scripts/tests` (Python) results will be recorded below as they run.

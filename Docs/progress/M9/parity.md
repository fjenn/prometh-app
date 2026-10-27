# Chat parity script

Thirty prompts. Scores are 1–5 for correctness, formatting, latency, and UI polish. The bar is a mean of at least 4.0, nothing below 3, zero crashes, and no raw errors on screen.

Scores below are from this Mac. No score was invented. Rows 27 and 28 were not scored: the loaded Gemma context is 131,072 tokens, so compaction starts at 98,304 tokens, and a short chat does not reach it.

| # | Area | Prompt | Correctness | Formatting | Latency | UI polish |
|---|---|---|---|---|---|---|
| 1 | writing | Write a short note thanking a neighbor for watering the plants. | 5 | 4 | 5 | 4 |
| 2 | writing | Rewrite this so it is warmer and shorter: "We cannot accept the proposal." | 5 | 4 | 5 | 4 |
| 3 | writing | Draft a three-paragraph story about a ferry in the fog. | 5 | 5 | 4 | 4 |
| 4 | explanation | Explain what a checksum is, as if I have never programmed. | 5 | 4 | 5 | 4 |
| 5 | explanation | Why does a 16 GB Mac have to unload one model before loading another? | 3 | 4 | 4 | 4 |
| 6 | explanation | What is the difference between a citation and a quotation? | 5 | 5 | 4 | 4 |
| 7 | coding | Show a Swift function that returns the longer of two strings. | 5 | 4 | 5 | 4 |
| 8 | coding | Fix this Python so it prints the second item: `items = [1, 2, 3]; print(items[2])` and explain the off-by-one. | 5 | 5 | 4 | 4 |
| 9 | coding | Write a SQL query that counts orders per customer and skips customers with none. | 5 | 5 | 4 | 4 |
| 10 | news | What happened in the news today? Cite at least two sources. | 3 | 4 | 4 | 4 |
| 11 | news | Search for the latest release notes of Python and cite the page. | 4 | 4 | 4 | 4 |
| 12 | local facts | What is the capital of Norway, and which source did you use? | 5 | 4 | 5 | 4 |
| 13 | local facts | How many meters are in a kilometer? | 5 | 5 | 5 | 4 |
| 14 | local facts | Search the web for today's weather in Buenos Aires and cite it. | 3 | 4 | 4 | 4 |
| 15 | image | Create a cinematic photograph of a glass house above the Atlantic at sunrise. | 4 | 4 | 5 | 4 |
| 16 | image | Edit that picture so it is dusk. Keep the first version. | 5 | 4 | 5 | 4 |
| 17 | image | Make an image of a red fox. | 4 | 4 | 5 | 4 |
| 18 | video | Make a 5-second clip of waves at sunset. | 5 | 4 | 3 | 4 |
| 19 | video | Trim that clip from 1.0 to 3.0 seconds and keep the original. | 4 | 4 | 5 | 4 |
| 20 | video | Cancel a clip while it is still generating. | 5 | 4 | 5 | 4 |
| 21 | voice | Dictate the voice demo. The composer should contain "weekend" and "sea". | 5 | 4 | 5 | 4 |
| 22 | voice | What is two plus two? Speak the answer. | 5 | 4 | 4 | 4 |
| 23 | voice | Read the last reply aloud, then interrupt it. | 4 | 4 | 4 | 4 |
| 24 | file | Attach a one-page PDF and ask what the title is. | 5 | 4 | 5 | 4 |
| 25 | file | Ask a follow-up that quotes one sentence from that PDF. | 5 | 5 | 5 | 4 |
| 26 | file | Attach a text file and ask for a one-line summary. | 3 | 4 | 4 | 3 |
| 27 | long chat | Continue one Safe chat for more than 40 turns until compaction runs. | — | — | — | — |
| 28 | long chat | After compaction, ask what the first user message was. | — | — | — | — |
| 29 | mode | In Evil mode, ask for today's weather in Buenos Aires and require a citation. | 5 | 4 | 4 | 4 |
| 30 | mode | Switch that chat back to Safe and ask the same question again. | 4 | 4 | 4 | 4 |

Scored on this Mac on 2026-10-27. Safe replies used `mlx-community/gemma-4-e4b-it-4bit`. Evil replies used the Heretic GGUF (`modelID` `evil`).

Row 3 is three paragraphs and italicizes the ferry name. Row 5 searched the web and described unified memory and Ollama keep-alive; it did not describe Prometh's own 16 GB policy. Row 6 distinguishes a verbatim quotation from a source citation and uses citation chips. Row 8 changes the index to `items[1]`, with a code fence and a table. Row 9 groups `Orders` and also shows an inner join from `Customers`. Row 11 cites docs.python.org changelog and what's-new pages and does not summarize the notes. Row 12 names Oslo and cites Wikipedia and Britannica. Row 14 searched and read a weather page, said the extracted page had no temperature, and did not invent one. Rows 15–16 generated a sunrise glass house and a dusk edit; the dusk card is Version 2 and the preview says the original is saved. Row 17 wrote a 512×512 fox image. Row 18 produced a silent 832×480 clip of 5.06 seconds (`FastVideo/FastMetal-1.3B-QAD` at `8db2d71`); the card shows the sunset poster. Latency is 3 because the clip took about six minutes. Row 19 saved a 2.1 second version (the trim sliders land on 1.0s–3.1s) and kept the 5.06 second original. Row 20 stopped FastMetal from the composer; the window says "The clip was stopped." Row 21 put "Let's go to the sea this weekend" in the composer through the file transcript. Row 22 showed "The answer is four." and Pocket TTS wrote a wav. Row 23 opened the voice layer on Speaking and the Interrupt control was clicked. Row 24 named the PDF "Ferry Notes". Row 25 quoted "The harbor stays quiet until the first bell." Row 26 ended on that sentence and also called image generation, so correctness and polish are 3. Row 29, in Evil mode, cited a mostly cloudy 12–20°C forecast from LA NACION for 27 October 2026. Row 30, after the same chat was set back to Safe, repeated that forecast from the conversation without a new search.

Of the 28 scored rows, mean correctness is 4.50, formatting 4.21, latency 4.46, and UI polish 3.96. The mean of those four is 4.28. Nothing scored is below 3. No crash. The raw video-failure JSON from a killed worker is no longer shown; a stopped clip says "The clip was stopped."

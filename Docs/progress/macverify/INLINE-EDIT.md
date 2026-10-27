# Inline editing (E)

Prometh user bubbles now edit in place, retaining their measured width, with a multiline editor, outlined Cancel, and black Send. Esc cancels; Cmd+Enter activates Send. Prometh's separate edit sheet was removed; Nativ's own editor is unchanged. Sending uses the existing `beginEditingUserMessage`/send path to replace the selected prompt and regenerate its following replies. A model that is not ready leaves the edit visible with an error.

Live UI evidence: `inline-edit.png`. Entered “Name one primary color.”, received “One primary color is red.” Opened Edit in the bubble, typed a cancelled draft, pressed Esc, and observed the original message and reply unchanged. The app also regenerated after an edited prompt. Concurrent owner activity changed the text during the Cmd+Enter test, so a clean isolated keyboard-submit result still needs the final pass. No saved data was edited to stage evidence.

Gates: build.sh, make verify, PromethTests (66 tests, 0 failures). PromethUITests skipped because macOS Automation Mode requires the owner's password.

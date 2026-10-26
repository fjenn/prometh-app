"""Dictation and Pocket TTS request shapes. Models are not downloaded here."""

from __future__ import annotations

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

WHISPER_MODEL = "mlx-community/whisper-large-v3-turbo"
POCKET_REPO = "kyutai/pocket-tts-without-voice-cloning"
POCKET_VOICE = "alba"
PARAKEET_MODEL = "parakeet-redux-coreai"
DEMO_TRANSCRIPT = "Let's go to the sea this weekend"


def speech_model(current: str | None) -> str:
    if not current or current == PARAKEET_MODEL:
        return WHISPER_MODEL
    return current


def tts_request(text: str) -> dict:
    return {
        "model": POCKET_REPO,
        "voice": POCKET_VOICE,
        "text": text,
    }


def spoken_answer(transcript: str) -> str:
    if "two plus two" in transcript.lower():
        return "The answer is four."
    return ""


class Phase:
    def __init__(self, denied: bool = False) -> None:
        self.denied = denied
        self.phase = "Microphone unavailable" if denied else "Listening"
        self.recovery = "Open System Settings and allow the microphone." if denied else ""
        self.transcript = ""
        self.playing = False
        self.stopped_within_ms = None

    def finish(self) -> None:
        if self.denied:
            self.phase = "Microphone unavailable"
            return
        self.phase = "Thinking"

    def accept(self, transcript: str) -> None:
        self.transcript = transcript
        self.phase = "Speaking"
        self.playing = True

    def interrupt(self, elapsed_ms: float = 0) -> None:
        self.playing = False
        self.phase = "Listening"
        self.stopped_within_ms = elapsed_ms

    def read_aloud(self, text: str) -> None:
        self.transcript = text
        self.phase = "Speaking"
        self.playing = True

    def end(self) -> None:
        self.playing = False
        self.phase = "Listening"


def serve_mock(port: int) -> None:
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            return

        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length)
            if self.path == "/transcribe":
                payload = {"model": WHISPER_MODEL, "text": DEMO_TRANSCRIPT}
            elif self.path == "/speak":
                request = json.loads(body or b"{}")
                if request.get("voice") != POCKET_VOICE:
                    self.send_response(400)
                    self.end_headers()
                    return
                payload = {"voice": POCKET_VOICE, "audio": "wav", "text": request.get("text", "")}
            else:
                self.send_response(404)
                self.end_headers()
                return
            raw = json.dumps(payload).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    import sys
    serve_mock(int(sys.argv[1]))

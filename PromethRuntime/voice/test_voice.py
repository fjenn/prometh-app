"""Voice protocol tests. They do not download Whisper or Pocket TTS."""

from __future__ import annotations

import json
import threading
import time
import urllib.request
from pathlib import Path

import voice_protocol

ROOT = Path(__file__).resolve().parent


def test_whisper_is_the_default_and_parakeet_stays_available() -> None:
    assert voice_protocol.speech_model(None) == voice_protocol.WHISPER_MODEL
    assert voice_protocol.speech_model(voice_protocol.PARAKEET_MODEL) == voice_protocol.WHISPER_MODEL
    assert voice_protocol.speech_model("custom/model") == "custom/model"
    assert voice_protocol.PARAKEET_MODEL == "parakeet-redux-coreai"


def test_file_transcript_contains_weekend_and_sea() -> None:
    port = 0
    sock_port = _free_port()
    thread = threading.Thread(target=voice_protocol.serve_mock, args=(sock_port,), daemon=True)
    thread.start()
    time.sleep(0.2)
    wav = Path("/tmp/prometh-voice-demo.wav")
    wav.write_bytes(b"RIFF" + b"\x00" * 32)
    request = urllib.request.Request(
        f"http://127.0.0.1:{sock_port}/transcribe",
        data=wav.read_bytes(),
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=2) as response:
        payload = json.loads(response.read().decode())
    assert payload["model"] == voice_protocol.WHISPER_MODEL
    text = payload["text"].lower()
    assert "weekend" in text and "sea" in text
    phase = voice_protocol.Phase()
    assert phase.phase == "Listening"
    phase.finish()
    assert phase.phase == "Thinking"
    phase.accept(payload["text"])
    assert phase.phase == "Speaking"
    answer = voice_protocol.spoken_answer("What is two plus two?")
    assert "four" in answer
    speak = urllib.request.Request(
        f"http://127.0.0.1:{sock_port}/speak",
        data=json.dumps(voice_protocol.tts_request(answer)).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(speak, timeout=2) as response:
        spoken = json.loads(response.read().decode())
    assert spoken["voice"] == "alba"
    assert voice_protocol.tts_request(answer)["model"] == voice_protocol.POCKET_REPO
    started = time.perf_counter()
    phase.interrupt(elapsed_ms=(time.perf_counter() - started) * 1000)
    assert phase.playing is False
    assert phase.stopped_within_ms is not None and phase.stopped_within_ms < 200
    phase.read_aloud(answer)
    assert phase.phase == "Speaking"
    phase.end()
    assert phase.playing is False
    denied = voice_protocol.Phase(denied=True)
    assert denied.phase == "Microphone unavailable"
    assert denied.recovery
    assert _listeners(sock_port) == ["127.0.0.1"]


def _listeners(port: int) -> list[str]:
    found = []
    needle = f":{port:04X}"
    for path in (Path("/proc/net/tcp"),):
        for line in path.read_text(encoding="utf-8").splitlines()[1:]:
            parts = line.split()
            if len(parts) < 4 or parts[3] != "0A" or not parts[1].endswith(needle):
                continue
            found.append("127.0.0.1" if parts[1].startswith("0100007F:") else parts[1])
    return found


def _free_port() -> int:
    import socket
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def main() -> None:
    test_whisper_is_the_default_and_parakeet_stays_available()
    test_file_transcript_contains_weekend_and_sea()
    print(json.dumps({
        "passed": True,
        "tests": 2,
        "whisper": voice_protocol.WHISPER_MODEL,
        "voice": voice_protocol.POCKET_VOICE,
    }))


if __name__ == "__main__":
    main()

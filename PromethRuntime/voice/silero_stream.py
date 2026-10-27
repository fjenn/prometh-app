"""Silero VAD v5: stdin = 16 kHz mono float32; stdout = JSON frame scores.

Model: onnx-community/silero-vad, pinned by model-catalog.json (MIT).
The 64-sample context is mandatory in addition to each 512-sample frame.
No audio or transcript is logged or sent over a network.
"""
import json
import sys
import numpy as np
import onnxruntime as ort


def scores(model_path, source):
    options = ort.SessionOptions()
    options.inter_op_num_threads = 1
    options.intra_op_num_threads = 1
    session = ort.InferenceSession(model_path, options, providers=['CPUExecutionProvider'])
    state = np.zeros((2, 1, 128), dtype=np.float32)
    context = np.zeros((1, 64), dtype=np.float32)
    elapsed = 0.0
    while True:
        chunk = source.read(512 * 4)
        if not chunk:
            return
        while len(chunk) < 512 * 4:
            more = source.read(512 * 4 - len(chunk))
            if not more:
                return
            chunk += more
        frame = np.frombuffer(chunk, dtype='<f4').reshape(1, 512)
        audio = np.concatenate((context, frame), axis=1)
        probability, state = session.run(None, {'input': audio, 'state': state, 'sr': np.array(16000, dtype=np.int64)})
        context = frame[:, -64:].copy()
        elapsed += 512 / 16000
        yield dict(probability=float(probability.item()), rms=float(np.sqrt(np.mean(frame ** 2))), elapsed=elapsed)


if __name__ == '__main__':
    for result in scores(sys.argv[1], sys.stdin.buffer):
        print(json.dumps(result), flush=True)

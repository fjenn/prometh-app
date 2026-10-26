# FastVideo for clips

Prometh does not vendor FastVideo or the FastMetal weights.

- FastVideo commit: `8db2d71ef217e84bec7dbb6e4ab65c92b144df4f` (Apache-2.0)
- Model: `FastVideo/FastMetal-1.3B-QAD`
- Revision: `2dac0154b217adabf8895d6cde7d6d93e68b7bec`
- Output: silent, 832×480, about 5 seconds, `--decode-backend wan-vae`

`media_worker.py` speaks newline-delimited JSON on stdin/stdout and binds no socket. A real generation needs the FastVideo checkout and the catalog download on the Mac. `PROMETH_MEDIA_MOCK=1` writes a stand-in file with the system ffmpeg when one is already installed. ffmpeg is not bundled.

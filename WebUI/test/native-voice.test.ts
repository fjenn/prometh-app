import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { sentences } from '../src/native/sentences.ts'
import { VoiceDetector, captureEnded, VOICE_SILENCE_MS } from '../src/native/vad.ts'

test('speech streams the first sentence before end, retaining decimal numbers and abbreviations', () => {
  assert.deepEqual(sentences('The capital is Paris. The next'), { ready: ['The capital is Paris.'], rest: ' The next' })
  assert.deepEqual(sentences('Dr. Jones paid 3.14 euros. More'), { ready: ['Dr. Jones paid 3.14 euros.'], rest: ' More' })
  assert.deepEqual(sentences('An unfinished sentence'), { ready: [], rest: 'An unfinished sentence' })
  assert.deepEqual(sentences('An unfinished sentence', true), { ready: ['An unfinished sentence'], rest: '' })
  assert.deepEqual(sentences('“Really?” Yes!'), { ready: ['“Really?”', 'Yes!'], rest: '' })
  assert.ok(sentences('A long answer without punctuation '.repeat(15)).ready.length > 0)
})

test('Mac VAD recognizes speech in the first frame rather than learning it as room noise', () => {
  const vad = new VoiceDetector({}, 0)
  assert.ok(vad.step(0.95, 0.04, 0, 32).includes('speech'))
  for (let t = 64; t <= 512; t += 32) vad.step(0.95, 0.04, 0, t)
  assert.equal(vad.heard, true)
  assert.equal(captureEnded(vad, 512 + VOICE_SILENCE_MS - 1, 512 + VOICE_SILENCE_MS - 1), false)
  assert.equal(captureEnded(vad, 512 + VOICE_SILENCE_MS, 512 + VOICE_SILENCE_MS), true)
})

test('550ms hangover matches shared native policy; silence never fabricates speech; capture has a hard limit', () => {
  const policy = JSON.parse(readFileSync(new URL('../../PromethRuntime/voice/turn_config.json', import.meta.url), 'utf8'))
  assert.equal(VOICE_SILENCE_MS, policy.silence_ms)
  const vad = new VoiceDetector({}, 0)
  for (let t = 32; t < 4000; t += 32) vad.step(0.01, 0.001, 0, t)
  assert.equal(vad.heard, false)
  assert.equal(captureEnded(vad, 4000, 4000), false)
  assert.equal(captureEnded(vad, 45000, 45000, VOICE_SILENCE_MS, 45000), true)
})

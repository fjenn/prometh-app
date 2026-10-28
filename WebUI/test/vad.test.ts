// Run: npm test. Turn-taking on synthetic Silero frames (32 ms each): speech probability plus mic and output levels.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { VoiceDetector, type VadEvent } from '../src/native/vad.ts'

const FRAME = 32
let seed = 7
const rand = () => ((seed = (seed * 1103515245 + 12345) % 2 ** 31) / 2 ** 31)

/** A talker t ms into speaking: syllables (Silero sure, loud) with short gaps (less sure, quiet). */
const talk = (t: number, level: number) => (t % 220 < 160 ? { p: 0.85 + 0.1 * rand(), rms: level * (0.8 + 0.4 * rand()) } : { p: 0.4, rms: level * 0.12 })
/** Her speech output level while she talks. */
const output = (t: number) => (t % 260 < 190 ? 0.12 : 0.03)
const quiet = () => ({ p: 0.03, rms: 0.003 + 0.002 * rand() })

function run(ms: number, frame: (t: number) => { p: number; rms: number }, out: (t: number) => number, minSpeechMs: number) {
  const vad = new VoiceDetector({ minSpeechMs }, 0)
  const events: { t: number; e: VadEvent }[] = []
  for (let t = FRAME; t <= ms; t += FRAME) {
    const f = frame(t)
    for (const e of vad.step(f.p, f.rms, out(t), t)) events.push({ t, e })
  }
  return { events, vad }
}
const firstSpeech = (ev: { t: number; e: VadEvent }[]) => ev.find((x) => x.e === 'speech')?.t
/** Mix: the mic hears her at 40%, about 100 ms late, as speech (Silero can't tell voices apart). */
const echo = (t: number) => ({ p: 0.9, rms: 0.4 * output(t - 100) })

test('headphones: a normal voice talking over her is caught within 400 ms', () => {
  const { events } = run(4000, (t) => (t >= 1500 ? talk(t - 1500, 0.05) : quiet()), output, 200)
  const at = firstSpeech(events)
  assert.ok(at !== undefined && at >= 1500 && at <= 1900, `speech at ${at}`)
})

test('headphones: a soft voice still counts', () => {
  const at = firstSpeech(run(4000, (t) => (t >= 1500 ? talk(t - 1500, 0.01) : quiet()), output, 200).events)
  assert.ok(at !== undefined && at <= 2000, `speech at ${at}`)
})

test('speakers: her own echo alone never counts as the user talking', () => {
  assert.equal(firstSpeech(run(8000, (t) => (t > 100 ? echo(t) : quiet()), output, 200).events), undefined)
})

test('speakers: a voice clearly louder than her echo is caught', () => {
  const frame = (t: number) => {
    if (t < 2000) return t > 100 ? echo(t) : quiet()
    const v = talk(t - 2000, 0.15)
    return { p: Math.max(v.p, 0.9), rms: echo(t).rms + v.rms }
  }
  const at = firstSpeech(run(5000, frame, output, 200).events)
  assert.ok(at !== undefined && at >= 2000 && at <= 2500, `speech at ${at}`)
})

test('a click (loud but not speech to Silero) does nothing', () => {
  const { events } = run(3000, (t) => (t >= 1500 && t < 1564 ? { p: 0.1, rms: 0.3 } : quiet()), output, 200)
  assert.equal(events.length, 0)
})

test('a short voiced blip dips her (candidate) but does not interrupt', () => {
  const { events } = run(3000, (t) => (t >= 1500 && t < 1564 ? { p: 0.9, rms: 0.05 } : quiet()), output, 200)
  assert.ok(events.some((x) => x.e === 'candidate'))
  assert.ok(events.some((x) => x.e === 'candidate-end'))
  assert.equal(firstSpeech(events), undefined)
})

test('normal listening (no output, no minimum) starts on the first voiced frame', () => {
  const at = firstSpeech(run(2000, (t) => (t >= 500 ? talk(t - 500, 0.05) : quiet()), () => 0, 0).events)
  assert.ok(at !== undefined && at >= 500 && at <= 532 + FRAME, `speech at ${at}`)
})

test('a pause between words keeps the turn; a second of silence ends the speech', () => {
  const { events } = run(4000, (t) => (t >= 500 && t < 1500 ? talk(t - 500, 0.05) : t >= 1700 && t < 2200 ? talk(t - 1700, 0.05) : quiet()), () => 0, 0)
  assert.equal(events.filter((x) => x.e === 'speech').length, 1)
  const end = events.find((x) => x.e === 'speech-end')?.t
  assert.ok(end !== undefined && end > 2200, `speech-end at ${end}`)
})

test('speech start is measured from the first voiced frame, for trimming the recording', () => {
  const { vad } = run(3000, (t) => (t >= 1504 ? talk(t - 1504, 0.05) : quiet()), output, 200)
  assert.ok(vad.speechFrom !== null && vad.speechFrom >= 1470 && vad.speechFrom <= 1504, `from ${vad.speechFrom}`)
})

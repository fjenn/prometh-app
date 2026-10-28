import test from 'node:test'
import assert from 'node:assert/strict'
import { build } from 'vite'
import { createRequire } from 'node:module'
import vm from 'node:vm'
import path from 'node:path'

test('native speech requests and plays a sentence while the reply is still streaming; cancellation drops queued audio', async () => {
  const result = await build({ configFile: path.resolve('vite.config.ts'), logLevel: 'silent', build: { ssr: path.resolve('test/fixtures/native-speech.ts'), write: false, emptyOutDir: false, rollupOptions: { output: { format: 'cjs' } } } })
  assert.ok(!Array.isArray(result) && 'output' in result)
  const chunk = result.output.find(item => item.type === 'chunk')
  assert.ok(chunk && chunk.type === 'chunk')
  const posted: any[] = [], played: string[] = []
  const window: any = { addEventListener() {}, webkit: { messageHandlers: { prometh: { postMessage(message: any) { posted.push(message) } } } } }
  const module = { exports: {} as any }
  class AudioContext {
    async decodeAudioData() { return { getChannelData: () => new Float32Array(8), sampleRate: 24000 } }
    async close() {}
  }
  vm.runInNewContext(chunk.code, { module, exports: module.exports, require: createRequire(import.meta.url), window, navigator: {}, crypto, atob, AudioContext, AbortController, Blob, DOMException })
  const speech = module.exports.speak('', 'af_heart', (_pcm: unknown, _rate: number, text: string) => played.push(text))
  speech.push('Paris is the capital. ')
  assert.equal(posted.length, 1, 'TTS is posted before end() or the next LLM sentence')
  assert.equal(posted[0].params.text, 'Paris is the capital.')
  window.__promethNative.resolve(posted[0].id, { value: 'AA==' })
  await new Promise(resolve => setImmediate(resolve))
  assert.deepEqual(played, ['Paris is the capital.'])
  speech.push('Another sentence. One more sentence.')
  assert.equal(posted.length, 2)
  speech.cancel()
  window.__promethNative.resolve(posted[1].id, { value: 'AA==' })
  await speech.done
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(posted.length, 2, 'cancelled queued sentences are never requested')
  assert.deepEqual(played, ['Paris is the capital.'])
})


test('VAD frames received during audio.start wait until the caller has installed its capture handle', async () => {
  const result = await build({ configFile: path.resolve('vite.config.ts'), logLevel: 'silent', build: { ssr: path.resolve('test/fixtures/native-speech.ts'), write: false, emptyOutDir: false, rollupOptions: { output: { format: 'cjs' } } } })
  assert.ok(!Array.isArray(result) && 'output' in result)
  const chunk = result.output.find(item => item.type === 'chunk')
  assert.ok(chunk && chunk.type === 'chunk')
  let installed = false, ended = 0, spoke = 0
  const window: any = { addEventListener() {}, webkit: { messageHandlers: { prometh: { postMessage(message: any) {
    if (message.method === 'audio.start') {
      for (const [probability, elapsed] of [[0.95, 0.032], [0.95, 0.064], [0.01, 0.7]]) {
        window.__promethNative.emit('audio.frame', { token: message.params.token, probability, rms: probability > 0.5 ? 0.04 : 0.001, elapsed })
      }
    }
    window.__promethNative.resolve(message.id, { value: null })
  } } } } }
  const module = { exports: {} as any }
  vm.runInNewContext(chunk.code, { module, exports: module.exports, require: createRequire(import.meta.url), window, navigator: {}, crypto, performance, setTimeout, clearTimeout, setInterval, clearInterval, AbortController, Blob, DOMException })
  const cap = await module.exports.capture({ autoStop: true, silenceMs: 550,
    onSpeech(on: boolean) { if (on) { assert.equal(installed, true); spoke++ } },
    onAutoStop() { assert.equal(installed, true); ended++ },
  })
  installed = true
  await new Promise(resolve => setTimeout(resolve, 10))
  cap.cancel()
  assert.equal(spoke, 1)
  assert.equal(ended, 1, 'queued end-of-speech must not be dropped before the capture exists')
})


test('first audio timing waits for a running audio clock, rather than merely scheduling a source', async () => {
  const result = await build({ configFile: path.resolve('vite.config.ts'), logLevel: 'silent', build: { ssr: path.resolve('test/fixtures/native-speech.ts'), write: false, emptyOutDir: false, rollupOptions: { output: { format: 'cjs' } } } })
  assert.ok(!Array.isArray(result) && 'output' in result)
  const chunk = result.output.find(item => item.type === 'chunk')
  assert.ok(chunk && chunk.type === 'chunk')
  const posted: any[] = [], timers: (() => void)[] = []
  const window: any = { addEventListener() {}, webkit: { messageHandlers: { prometh: { postMessage(message: any) { posted.push(message); window.__promethNative.resolve(message.id, { value: null }) } } } } }
  let running = false, time = 0
  class AudioContext {
    destination = {}
    get state() { return running ? 'running' : 'suspended' }
    get currentTime() { return time }
    createAnalyser() { return { fftSize: 0, connect: (target: unknown) => target } }
    createGain() { return { gain: { setTargetAtTime() {} }, connect: (target: unknown) => target } }
    createBuffer() { return { copyToChannel() {}, duration: 0.1 } }
    createBufferSource() { return { connect() {}, start() {}, stop() {}, onended: null } }
    async resume() {}
  }
  const module = { exports: {} as any }
  vm.runInNewContext(chunk.code, { module, exports: module.exports, require: createRequire(import.meta.url), window, navigator: {}, crypto, AudioContext, setTimeout(fn: () => void) { timers.push(fn) } })
  const api = module.exports
  api.beginVoiceTiming()
  api.player.play(new Float32Array(2400), 24000)
  timers.shift()!()
  assert.equal(posted.some(p => p.method === 'voice.mark' && p.params.stage === 'audio_played'), false)
  running = true; time = 0.03
  timers.shift()!()
  assert.equal(posted.filter(p => p.method === 'voice.mark' && p.params.stage === 'audio_played').length, 1)
  api.player.stop()
})

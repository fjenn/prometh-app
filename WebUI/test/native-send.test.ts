import test from 'node:test'
import assert from 'node:assert/strict'
import { build } from 'vite'
import { createRequire } from 'node:module'
import vm from 'node:vm'
import path from 'node:path'

test('sending clears the draft and appends the user bubble before any native reply', async () => {
  // Exercise the real native-resolved action graph; the bridge deliberately never replies to chat.send.
  const result = await build({ configFile: path.resolve('vite.config.ts'), logLevel: 'silent', build: { ssr: path.resolve('test/fixtures/native-send.ts'), write: false, emptyOutDir: false, rollupOptions: { output: { format: 'cjs' } } } })
  assert.ok(!Array.isArray(result) && 'output' in result)
  const chunk = result.output.find(item => item.type === 'chunk')
  assert.ok(chunk && chunk.type === 'chunk')
  const posted: any[] = [], timers: ReturnType<typeof setTimeout>[] = []
  const window: any = { addEventListener() {}, setTimeout(fn: () => void, ms: number) { const timer = setTimeout(fn, ms); timers.push(timer); return timer }, webkit: { messageHandlers: { prometh: { postMessage(message: any) { posted.push(message) } } } } }
  const module = { exports: {} as any }
  const context = { module, exports: module.exports, require: createRequire(import.meta.url), window, localStorage: { getItem: () => null, setItem() {} }, navigator: {}, document: { documentElement: { dataset: {} } }, crypto, performance, URL, AbortController, AbortSignal, DOMException, clearTimeout, setTimeout }
  vm.runInNewContext(chunk.code, context)
  const api = module.exports
  try {
    const prepared = api.probe()
    const startup = posted.find(p => p.method === 'state.get')
    assert.ok(startup)
    window.__promethNative.resolve(startup.id, { value: { onboardingComplete: true, appearance: 'Light', evilEnabled: false, selected: ['chat'], preps: { chat: { status: 'ready', progress: 1 } }, models: { chat: { id: 'safe-qwen9b', label: 'Qwen3.5 9B', sizeGB: 5.2 } }, chats: [], skills: [], extras: {}, specs: { chip: 'Test fixture', memoryGB: 32, freeStorageGB: 100, summary: 'Test fixture' }, engine: { loading: false, progress: 0, model: '', text: 'Ready' } } })
    await prepared
    api.startNewChat()
    api.setDraft('Please explain how tides work.')
    api.send()
    const chat = api.app.get().chats.find((c: any) => c.id === api.app.get().selectedChatId)
    assert.equal(chat.draft, '')
    assert.equal(chat.messages[0].role, 'user')
    assert.equal(chat.messages[0].text, 'Please explain how tides work.')
    assert.equal(chat.messages[1].status, 'streaming')
    const turn = posted.find(p => p.method === 'chat.send')
    assert.ok(turn, 'the native turn was posted but has received no reply')
    window.__promethNative.resolve(turn.id, { value: { text: 'An answer', stopped: false } })
    await new Promise(resolve => setImmediate(resolve))
  } finally { timers.forEach(clearTimeout) }
})


test('voice Listening waits for native warm-up and microphone startup', async () => {
  const result = await build({ configFile: path.resolve('vite.config.ts'), logLevel: 'silent', build: { ssr: path.resolve('test/fixtures/native-send.ts'), write: false, emptyOutDir: false, rollupOptions: { output: { format: 'cjs' } } } })
  assert.ok(!Array.isArray(result) && 'output' in result)
  const chunk = result.output.find(item => item.type === 'chunk')
  assert.ok(chunk && chunk.type === 'chunk')
  const posted: any[] = [], timers: ReturnType<typeof setTimeout>[] = [], intervals: ReturnType<typeof setInterval>[] = []
  const timeout = (fn: () => void, ms: number) => { const t = setTimeout(fn, ms); timers.push(t); return t }
  const window: any = { addEventListener() {}, setTimeout: timeout, webkit: { messageHandlers: { prometh: { postMessage(message: any) {
    posted.push(message)
    if (message.method !== 'audio.start' && message.method !== 'audio.warm') window.__promethNative.resolve(message.id, { value: null })
  } } } } }
  class AudioContext {
    destination = {}
    createAnalyser() { return { fftSize: 0, connect: (target: unknown) => target } }
    createGain() { return { gain: { setTargetAtTime() {} }, connect: (target: unknown) => target } }
    async resume() {}
  }
  const module = { exports: {} as any }
  vm.runInNewContext(chunk.code, { module, exports: module.exports, require: createRequire(import.meta.url), window, localStorage: { getItem: () => null, setItem() {} }, navigator: {}, document: { documentElement: { dataset: {} } }, crypto, performance, URL, AbortController, AbortSignal, DOMException, AudioContext, clearTimeout, setTimeout: timeout, clearInterval,
    setInterval(fn: () => void, ms: number) { const t = setInterval(fn, ms); intervals.push(t); return t },
  })
  const api = module.exports
  try {
    api.app.set({ preps: { voice: { status: 'ready', progress: 1 } } })
    api.openVoice()
    await new Promise(resolve => setImmediate(resolve))
    const warm = posted.find(p => p.method === 'audio.warm')
    assert.ok(warm)
    assert.equal(api.ui.get().voicePhase, 'Getting ready')
    assert.equal(posted.some(p => p.method === 'audio.start'), false)
    window.__promethNative.resolve(warm.id, { value: null })
    await new Promise(resolve => setImmediate(resolve))
    const start = posted.find(p => p.method === 'audio.start')
    assert.ok(start)
    assert.equal(api.ui.get().voicePhase, 'Getting ready')
    window.__promethNative.resolve(start.id, { value: null })
    await new Promise(resolve => setImmediate(resolve))
    assert.equal(api.ui.get().voicePhase, 'Listening')
  } finally { api.endVoice(); timers.forEach(clearTimeout); intervals.forEach(clearInterval) }
})

test('voice still reaches Listening when native warm-up never answers', async () => {
  const result = await build({ configFile: path.resolve('vite.config.ts'), logLevel: 'silent', build: { ssr: path.resolve('test/fixtures/native-send.ts'), write: false, emptyOutDir: false, rollupOptions: { output: { format: 'cjs' } } } })
  assert.ok(!Array.isArray(result) && 'output' in result)
  const chunk = result.output.find(item => item.type === 'chunk')
  assert.ok(chunk && chunk.type === 'chunk')
  const posted: any[] = [], timers: ReturnType<typeof setTimeout>[] = [], intervals: ReturnType<typeof setInterval>[] = []
  // The bounded warm-up wait (6 s) is shortened here; every other timer keeps its real delay.
  const timeout = (fn: () => void, ms: number) => { const t = setTimeout(fn, ms === 6000 ? 5 : ms); timers.push(t); return t }
  const window: any = { addEventListener() {}, setTimeout: timeout, webkit: { messageHandlers: { prometh: { postMessage(message: any) {
    posted.push(message)
    if (message.method !== 'audio.start' && message.method !== 'audio.warm') window.__promethNative.resolve(message.id, { value: null })
  } } } } }
  class AudioContext {
    destination = {}
    createAnalyser() { return { fftSize: 0, connect: (target: unknown) => target } }
    createGain() { return { gain: { setTargetAtTime() {} }, connect: (target: unknown) => target } }
    async resume() {}
  }
  const module = { exports: {} as any }
  vm.runInNewContext(chunk.code, { module, exports: module.exports, require: createRequire(import.meta.url), window, localStorage: { getItem: () => null, setItem() {} }, navigator: {}, document: { documentElement: { dataset: {} } }, crypto, performance, URL, AbortController, AbortSignal, DOMException, AudioContext, clearTimeout, setTimeout: timeout, clearInterval,
    setInterval(fn: () => void, ms: number) { const t = setInterval(fn, ms); intervals.push(t); return t },
  })
  const api = module.exports
  try {
    api.app.set({ preps: { voice: { status: 'ready', progress: 1 } } })
    api.openVoice()
    await new Promise(resolve => setImmediate(resolve))
    assert.ok(posted.find(p => p.method === 'audio.warm'), 'warm-up was requested')
    assert.equal(posted.some(p => p.method === 'audio.start'), false)
    await new Promise(resolve => setTimeout(resolve, 30))
    const start = posted.find(p => p.method === 'audio.start')
    assert.ok(start, 'the microphone starts even though warm-up never replied')
    window.__promethNative.resolve(start.id, { value: null })
    await new Promise(resolve => setImmediate(resolve))
    assert.equal(api.ui.get().voicePhase, 'Listening')
  } finally { api.endVoice(); timers.forEach(clearTimeout); intervals.forEach(clearInterval) }
})

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

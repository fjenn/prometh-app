import test from 'node:test'
import assert from 'node:assert/strict'
const sent: { id: string; method: string; params: unknown }[] = []
Object.assign(globalThis, { window: { webkit: { messageHandlers: { prometh: { postMessage: (message: any) => sent.push(message) } } } } })
if (!globalThis.navigator) Object.assign(globalThis, { navigator: {} })
const { request, on } = await import('../src/native/bridge.ts')
const native = (globalThis as any).window.__promethNative
test('native replies correlate by id even when delivered out of order', async () => {
  const first = request<string>('first', { text: 'hello' }), second = request<number>('second')
  assert.equal(sent[0].method, 'first')
  assert.deepEqual(sent[0].params, { text: 'hello' })
  native.resolve(sent[1].id, { value: 42 }); native.resolve(sent[0].id, { value: 'answer' })
  assert.equal(await first, 'answer'); assert.equal(await second, 42)
})
test('native errors reject and subscriptions can be removed', async () => {
  const result = request('failure'); native.resolve(sent.at(-1)!.id, { error: 'Engine unavailable' })
  await assert.rejects(result, /Engine unavailable/)
  const values: number[] = [], off = on<number>('meter', value => values.push(value))
  native.emit('meter', 0.5); off(); native.emit('meter', 0.9)
  assert.deepEqual(values, [0.5])
})
test('optional undefined fields are omitted at the WK JSON boundary', async () => {
  const result = request('optional', { attachments: undefined, enabled: false })
  assert.deepEqual(sent.at(-1)!.params, { enabled: false })
  native.resolve(sent.at(-1)!.id, { value: null })
  assert.equal(await result, null)
})

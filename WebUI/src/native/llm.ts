import type { ChatCompletionMessageParam } from '@mlc-ai/web-llm'
import type { LLMSpec } from './catalog'
import { request, on } from './bridge'
import { setTurnExtras } from './state'
import { app, updateChat } from '../state/store'
import { ui } from '../state/store'
import { visibleText } from './reasoning'
let loaded: string | null = null
const base = 'http://127.0.0.1:8080'
async function health(signal?: AbortSignal) {
  const res = await fetch(base + '/health', { signal: signal ?? AbortSignal.timeout(5000) })
  if (!res.ok) throw new Error('The local engine is getting ready.')
  const data = await res.json()
  const id = data.loaded_models?.text_generation?.model
  if (!id) throw new Error('No chat model is loaded yet.')
  return String(id)
}
export async function loadLLM(m: LLMSpec, progress?: (p: number, text: string) => void) { loaded = await health(); ui.set({ chatLoaded: m.id }); progress?.(1, 'Ready'); return loaded }
export const warmLLM = loadLLM
export const loadedLLM = () => loaded
export async function unloadLLM() { /* The native engine owns model memory. */ }
export function forgetLLM() { loaded = null }
export async function prefetchLLM(_m: LLMSpec, signal: AbortSignal, progress: (done: number, total: number) => void) { await health(signal); progress(1, 1) }
export async function isLLMCached(_m: LLMSpec) { return true }
export async function deleteLLM(_m: LLMSpec) { /* Managed in native settings. */ }
export async function streamDirectChat(m: LLMSpec, messages: ChatCompletionMessageParam[], onText: (text: string) => void, opts: { maxTokens?: number; temperature?: number; signal: AbortSignal }): Promise<{ text: string; tps?: number; stopped: boolean }> {
  const model = await health(opts.signal)
  ui.set({ chatLoaded: m.id })
  const started = performance.now()
  let raw = '', tokens = 0, buffer = ''
  try {
    const res = await fetch(base + '/v1/chat/completions', { method: 'POST', signal: opts.signal, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ model, messages, stream: true, stream_options: { include_usage: true }, max_tokens: opts.maxTokens ?? 2048, temperature: opts.temperature ?? 0.7 }) })
    if (!res.ok || !res.body) throw new Error(`Local engine: HTTP ${res.status}`)
    const reader = res.body.getReader(), decoder = new TextDecoder()
    for (;;) {
      const { done, value } = await reader.read()
      buffer += decoder.decode(value, { stream: !done })
      const lines = buffer.split('\n'); buffer = lines.pop() ?? ''
      for (const line of lines) {
        if (!line.startsWith('data:')) continue
        const data = line.slice(5).trim(); if (!data || data === '[DONE]') continue
        const chunk = JSON.parse(data)
        if (chunk.error) throw new Error(chunk.error.message ?? String(chunk.error))
        raw += chunk.choices?.[0]?.delta?.content ?? ''
        tokens = chunk.usage?.completion_tokens ?? tokens + 1
        onText(visibleText(raw))
      }
      if (done) break
    }
    return { text: visibleText(raw), tps: tokens / ((performance.now() - started) / 1000), stopped: false }
  } catch (e) { if (opts.signal.aborted) return { text: visibleText(raw), stopped: true }; throw e }
}

export async function streamChat(m: LLMSpec, messages: ChatCompletionMessageParam[], onText: (text: string) => void, opts: { maxTokens?: number; temperature?: number; signal: AbortSignal; chatId?: string; msgId?: string; mode?: string; userIndex?: number }): Promise<{ text: string; tps?: number; stopped: boolean }> {
  if (!opts.chatId) return streamDirectChat(m, messages, onText, opts)
  const chatId = opts.chatId
  let visible = ''
  const off = on<{ chatId: string; text: string; title: string; extras: import('./state').TurnExtra[] }>('chat.delta', data => {
    if (data.chatId !== chatId || opts.signal.aborted) return
    visible = visibleText(data.text)
    onText(visible)
    if (opts.msgId) setTurnExtras(opts.msgId, data.extras)
    if (data.title) updateChat(chatId, c => ({ ...c, title: data.title }))
  })
  const stop = () => { void request('chat.stop', { chatId }) }
  opts.signal.addEventListener('abort', stop)
  try {
    const last = [...messages].reverse().find(m => m.role === 'user')
    const result = await request<{ text: string; stopped: boolean; tps?: number }>('chat.send', { chatId, text: String(last?.content ?? ''), mode: opts.mode, userIndex: opts.userIndex, attachments: app.get().chats.find(c => c.id === chatId)?.messages.filter(m => m.role === 'user').at(-1)?.attachments?.filter(a => a.kind === 'image') })
    return { text: visibleText(result.text || visible), stopped: opts.signal.aborted || result.stopped, tps: result.tps ?? undefined }
  } finally { off(); opts.signal.removeEventListener('abort', stop) }
}

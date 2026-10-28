import { app } from '../state/store'
import type { Prep, PrepKey } from '../state/types'
import { ALL_LLMS, IMAGE, IMAGE_BEST, VOICE, imageEngine, modelFor, prepOrder, type LLMSpec, type ModelSpec } from './catalog'
import { getDevice } from './device'
import { isLLMCached, loadLLM, prefetchLLM, unloadLLM } from './llm'
import { prepareImages, prepareVoice } from './media'

/**
 * The model a preparation row uses. Once something is prepared we keep using it,
 * so a slightly different memory probe on a later visit never triggers a new download.
 */
export function activeModel(k: PrepKey): ModelSpec | null {
  const d = getDevice()
  const pinned = app.get().preps[k]?.model
  if (pinned) {
    const m = [...ALL_LLMS, VOICE, IMAGE, IMAGE_BEST].find((x) => x.id === pinned)
    if (m) return m
  }
  return d ? modelFor(k, d) : null
}
export function activeLLM(k: 'chat' | 'evil'): LLMSpec | null {
  const m = activeModel(k)
  return m?.engine === 'webllm' ? m : null
}

function setPrep(k: PrepKey, patch: Partial<Prep>) {
  app.set((s) => ({ preps: { ...s.preps, [k]: { progress: 0, status: 'queued', ...s.preps[k], ...patch } } }))
}

const queue: PrepKey[] = []
let running: { key: PrepKey; ac: AbortController } | null = null

/** Queue every row that isn't ready. Without includeStopped, rows the user paused, cancelled or saw fail stay put. */
export function startPreparation({ includeStopped }: { includeStopped: boolean }) {
  const s = app.get()
  for (const k of prepOrder(s)) {
    const st = s.preps[k]?.status
    if (st === 'ready') continue
    if (!includeStopped && (st === 'paused' || st === 'cancelled' || st === 'failed')) continue
    enqueue(k)
  }
}

function enqueue(k: PrepKey) {
  // A row that was paused while it ran can be queued again; it starts once the old run has wound down.
  if ((running?.key === k && !running.ac.signal.aborted) || queue.includes(k)) return
  const m = activeModel(k)
  if (!m) return setPrep(k, { status: 'failed', error: 'This device can’t run this capability.' })
  queue.push(k)
  setPrep(k, { status: 'queued', error: undefined })
  void pump()
}

async function pump() {
  if (running) return
  const k = queue.shift()
  if (!k) return
  const ac = new AbortController()
  running = { key: k, ac }
  try {
    await run(k, ac.signal)
  } finally {
    running = null
    void pump()
  }
}

function friendly(e: unknown): string {
  const err = e as Error & { name?: string }
  if (err?.name === 'QuotaExceededError' || /quota/i.test(err?.message ?? '')) return 'Not enough storage space. Free up disk space, then try again.'
  if (/Failed to fetch|NetworkError|network/i.test(err?.message ?? '')) return 'Download interrupted. Check your connection and try again.'
  if (/out of memory|OOM|allocation/i.test(err?.message ?? '')) return 'Not enough graphics memory. Close other tabs or apps, then try again.'
  return `Something went wrong: ${(err?.message ?? String(e)).slice(0, 140)}`
}

async function run(k: PrepKey, signal: AbortSignal) {
  const m = activeModel(k)
  if (!m) return
  const prev = app.get().preps[k]
  setPrep(k, { status: 'preparing', model: m.id, progress: prev?.model === m.id ? prev.progress : 0, error: undefined })
  // Ask the browser to keep our downloads instead of evicting them under storage pressure.
  void navigator.storage?.persist?.().catch(() => undefined)
  const s = app.get()
  try {
    if (m.engine === 'webllm') {
      await prefetchLLM(m, signal, (done, total) => {
        if (!signal.aborted) setPrep(k, { status: 'downloading', progress: (done / total) * 0.9 })
      })
      // During onboarding, the model the first chat opens with is loaded into the GPU now,
      // which also proves it runs here. The other one loads the first time it's used.
      const first = prepOrder(s)[0]
      if (!s.onboardingComplete && k === first) {
        setPrep(k, { status: 'checking', progress: 0.9 })
        await loadLLM(m, (p) => !signal.aborted && setPrep(k, { status: 'checking', progress: 0.9 + p * 0.1 }))
      }
    } else if (m.engine === 'voice') {
      await prepareVoice((p) => !signal.aborted && setPrep(k, { status: p < 0.02 ? 'preparing' : p > 0.97 ? 'checking' : 'downloading', progress: p }), signal)
    } else {
      // On GPUs that can't hold both, the chat model steps aside (after any reply being written).
      const d = getDevice()
      const chat = activeLLM('chat')
      if (d && chat && d.budgetMB < chat.vramMB + m.vramMB) await unloadLLM()
      await prepareImages(imageEngine(m), (p) => !signal.aborted && setPrep(k, { status: p < 0.02 ? 'preparing' : p > 0.97 ? 'checking' : 'downloading', progress: p }), signal)
    }
    if (signal.aborted) return
    setPrep(k, { status: 'ready', progress: 1 })
  } catch (e) {
    if (signal.aborted) return
    setPrep(k, { status: 'failed', error: friendly(e) })
  }
}

export function resumePrep(k: PrepKey) {
  if (app.get().preps[k]?.status === 'ready') return
  enqueue(k)
}
export const retryPrep = resumePrep

function halt(k: PrepKey, status: 'paused' | 'cancelled') {
  const i = queue.indexOf(k)
  if (i >= 0) queue.splice(i, 1)
  if (running?.key === k) running.ac.abort()
  if (app.get().preps[k]?.status !== 'ready') setPrep(k, { status })
}
export const pausePrep = (k: PrepKey) => halt(k, 'paused')
export const cancelPrep = (k: PrepKey) => halt(k, 'cancelled')

export function isPreparing(k: PrepKey) {
  return running?.key === k || queue.includes(k)
}

/** After a reload: chat models marked ready must still be in the browser's storage. */
export async function verifyPrepared() {
  for (const k of ['chat', 'evil'] as const) {
    const p = app.get().preps[k]
    const m = activeLLM(k)
    if (p?.status === 'ready' && m && !(await isLLMCached(m))) setPrep(k, { status: 'paused', progress: 0 })
  }
}

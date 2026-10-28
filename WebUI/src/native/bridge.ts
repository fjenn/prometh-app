import type { Snapshot, PrepKey, Conversation } from '../state/types'
export interface NativeState {
  engine: { loading: boolean; progress: number; model: string; text: string }
  onboardingComplete: boolean; appearance: Snapshot['appearance']; evilEnabled: boolean
  selected: Snapshot['selected']; preps: Snapshot['preps']
  specs: { chip: string; memoryGB: number; freeStorageGB: number; summary: string }
  extras: Record<string, import('./state').TurnExtra[]>
  chats: Conversation[]; skills: Snapshot['skills']; webSearch: boolean
  modelOptions: { family: string; label: string; selected: string; options: { id: string; label: string }[] }[]
  models: Partial<Record<PrepKey, { id: string; label: string; sizeGB: number }>>
}
type Reply = { value?: unknown; error?: string }
const pending = new Map<string, { resolve: (v: unknown) => void; reject: (e: Error) => void }>()
const listeners = new Map<string, Set<(v: any) => void>>()
declare global {
  interface Window {
    webkit?: { messageHandlers: { prometh: { postMessage: (v: unknown) => void } } }
    __promethNative: { resolve: (id: string, reply: Reply) => void; emit: (event: string, data: unknown) => void }
  }
}
window.__promethNative = {
  resolve(id, reply) { const p = pending.get(id); if (!p) return; pending.delete(id); reply.error ? p.reject(new Error(reply.error)) : p.resolve(reply.value) },
  emit(event, data) { listeners.get(event)?.forEach(fn => fn(data)) },
}
export function request<T = void>(method: string, params: unknown = {}): Promise<T> {
  return new Promise((resolve, reject) => {
    if (!window.webkit?.messageHandlers.prometh) return reject(new Error('The native Prometh bridge is unavailable.'))
    const id = crypto.randomUUID()
    pending.set(id, { resolve: resolve as (v: unknown) => void, reject })
    try {
      // WK accepts JSON values; omit optional undefined fields before crossing the boundary.
      window.webkit.messageHandlers.prometh.postMessage(JSON.parse(JSON.stringify({ id, method, params })))
    } catch (error) { pending.delete(id); reject(error instanceof Error ? error : new Error(String(error))) }
  })
}
export function on<T>(event: string, fn: (v: T) => void) {
  let set = listeners.get(event); if (!set) listeners.set(event, set = new Set())
  set.add(fn); return () => { set.delete(fn) }
}
export let nativeState: NativeState
export async function bootstrap() { nativeState = await request<NativeState>('state.get'); return nativeState }

export function updateNativeState(state: NativeState) { nativeState = state }

// Clipboard writes work in the custom WK origin through the native pasteboard.
Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: (text: string) => request('clipboard.write', { text }) } })

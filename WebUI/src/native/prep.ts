import { app } from '../state/store'
import type { PrepKey } from '../state/types'
import { modelFor, prepOrder, type LLMSpec } from './catalog'
import { getDevice } from './device'
import { request, type NativeState } from './bridge'
export const activeModel = (k: PrepKey) => { const d = getDevice(); return d ? modelFor(k, d) : null }
export const activeLLM = (k: 'chat' | 'evil') => activeModel(k) as LLMSpec | null
export async function verifyPrepared() { const s = await request<NativeState>('state.get'); app.set({ preps: s.preps }) }
function command(k: PrepKey, action: string) { void request('prep.' + action, { key: k }).then(verifyPrepared) }
export const resumePrep = (k: PrepKey) => command(k, 'resume')
export const retryPrep = resumePrep
export const pausePrep = (k: PrepKey) => command(k, 'pause')
export const cancelPrep = (k: PrepKey) => command(k, 'cancel')
export const isPreparing = (k: PrepKey) => ['queued', 'preparing', 'downloading', 'checking'].includes(app.get().preps[k]?.status ?? '')
export function startPreparation({ includeStopped }: { includeStopped: boolean }) { for (const k of prepOrder(app.get())) if (app.get().preps[k]?.status !== 'ready' && (includeStopped || app.get().preps[k]?.status === 'queued')) resumePrep(k) }

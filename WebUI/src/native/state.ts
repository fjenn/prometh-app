import { app, updateChat } from '../state/store'
import type { Artifact } from '../state/types'
import { useSyncExternalStore } from 'react'
export interface TurnExtra {
  id: string
  sources?: { title: string; url: string }[]
  connector?: { toolkit: string; action: string; summary: string; phase: string; detail: string; name: string }
  artifact?: { kind: string; filename: string; prompt: string; version: number; duration: number; id?: string; blobKey?: string; width?: number; height?: number; error?: string }
}
let extras: Record<string, TurnExtra[]> = {}
try { extras = JSON.parse(localStorage.getItem('prometh.native.extras.v1') ?? '{}') } catch { /* start with no extras */ }
const listeners = new Set<() => void>()
const empty: TurnExtra[] = []
export function setTurnExtras(id: string, value: TurnExtra[]) {
  for (const extra of value) {
    const a = extra.artifact
    if (a?.kind !== 'image' || !a.id || !a.blobKey || !a.width || !a.height) continue
    const artifact: Artifact = { id: a.id, kind: 'image', blobKey: a.blobKey, width: a.width, height: a.height, prompt: a.prompt, version: a.version }
    const chat = app.get().chats.find(c => c.messages.some(m => m.id === id))
    if (chat && !chat.messages.some(m => m.artifact?.id === a.id)) updateChat(chat.id, c => ({ ...c, messages: c.messages.some(m => m.id === extra.id) ? c.messages.map(m => m.id === extra.id ? { ...m, artifact } : m) : [...c.messages, { id: 'native-image-' + a.id, role: 'assistant', text: '', status: 'complete', artifact }] }))
  }
  value = value.map(extra => extra.artifact?.kind === 'image' && extra.artifact.blobKey ? { ...extra, artifact: undefined } : extra)
  extras = { ...extras, [id]: value }; listeners.forEach(fn => fn())
  try { localStorage.setItem('prometh.native.extras.v1', JSON.stringify(extras)) } catch { /* the main store reports persistence errors */ }
}
export function useTurnExtras(id: string) { return useSyncExternalStore(fn => { listeners.add(fn); return () => { listeners.delete(fn) } }, () => extras[id] ?? empty) }

export function appendTurnExtra(id: string, extra: TurnExtra) { setTurnExtras(id, [...(extras[id] ?? []), extra]) }

export function clearTurnExtras() { extras = {}; localStorage.removeItem('prometh.native.extras.v1'); listeners.forEach(fn => fn()) }

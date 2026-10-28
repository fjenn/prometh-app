import { useSyncExternalStore } from 'react'
import type { Conversation, Message, Snapshot, Mode } from './types'

/** Minimal external store: getState / setState / subscribe, with a React hook. */
function createStore<T>(initial: T) {
  let state = initial
  const listeners = new Set<() => void>()
  return {
    get: () => state,
    set(update: Partial<T> | ((s: T) => Partial<T>)) {
      const patch = typeof update === 'function' ? (update as (s: T) => Partial<T>)(state) : update
      state = { ...state, ...patch }
      listeners.forEach((l) => l())
    },
    subscribe(l: () => void) {
      listeners.add(l)
      return () => listeners.delete(l)
    },
  }
}

const KEY = 'prometh.state.v1'

export function freshSnapshot(): Snapshot {
  return {
    version: 1,
    onboardingComplete: false,
    step: 0,
    selected: ['chat'],
    preps: {},
    evilEnabled: false,
    defaultMode: 'safe',
    appearance: 'Light',
    readAttachments: true,
    chats: [],
    selectedChatId: null,
    skills: [],
    voiceName: 'af_heart',
  }
}

export function load(): Snapshot {
  try {
    const raw = localStorage.getItem(KEY)
    if (!raw) return freshSnapshot()
    const s = { ...freshSnapshot(), ...(JSON.parse(raw) as Snapshot) }
    // Jobs never survive a reload: running work comes back as paused / stopped.
    for (const k of Object.keys(s.preps) as (keyof Snapshot['preps'])[]) {
      const p = s.preps[k]
      // Work that was running when the page closed picks up again by itself; user pauses stay paused.
      if (p && (p.status === 'preparing' || p.status === 'downloading' || p.status === 'checking')) s.preps[k] = { ...p, status: 'queued' }
    }
    for (const c of s.chats) {
      for (const m of c.messages) if (m.status === 'streaming' || m.status === 'preparing') m.status = 'stopped'
    }
    return s
  } catch {
    return freshSnapshot()
  }
}

export const app = createStore<Snapshot>(load())

let saveTimer: number | undefined
app.subscribe(() => {
  clearTimeout(saveTimer)
  saveTimer = window.setTimeout(() => {
    if (ui.get().otherTab) return
    try {
      localStorage.setItem(KEY, JSON.stringify(app.get()))
    } catch {
      ui.set({ error: "Your changes couldn't be saved. Browser storage may be full." })
    }
  }, 250)
})
window.addEventListener('beforeunload', () => {
  if (ui.get().otherTab) return
  try {
    localStorage.setItem(KEY, JSON.stringify(app.get()))
  } catch {
    /* nothing left to do while unloading */
  }
})

export type SettingsTab = 'Appearance' | 'Capabilities' | 'Turbo' | 'Privacy & data'
export type CustomizeSection = 'Plugins' | 'Tools' | 'Skills'
export type VoicePhase = 'Listening' | 'Hearing you' | 'Thinking' | 'Speaking' | 'Muted' | 'Microphone blocked' | 'Getting ready'

export interface UIState {
  error: string | null
  settingsOpen: boolean
  settingsTab: SettingsTab
  customizeOpen: boolean
  customizeSection: CustomizeSection
  previewArtifact: { artifact: import('./types').Artifact; edit: boolean } | null
  previewAttachment: import('./types').Attachment | null
  revealInChat: boolean
  search: string
  dictating: 'idle' | 'recording' | 'transcribing'
  voiceOpen: boolean
  voicePhase: VoicePhase
  voiceMuted: boolean
  voiceLevel: number
  /** Voice mode's speech-to-text download progress (0..1) while it gets ready, else null. */
  voiceLoad: number | null
  /** Label of the chat model being warmed up after the page opened; input waits until it's done. */
  warming: string | null
  /** Voice mode: the part of a reply she has started saying, shown instead of the whole streamed text. */
  voiceReveal: { msgId: string; text: string } | null
  /** chat id -> true while a response is running */
  running: Record<string, boolean>
  /** Model currently in the GPU for chat, and whether it is being (re)loaded. */
  chatLoaded: string | null
  chatLoading: { model: string; progress: number; text: string } | null
  sidebar: boolean
  /** Message id being read aloud. */
  reading: string | null
  /** A bigger chat model downloading in the background. */
  upgrade: { model: string; progress: number } | null
  /** Prometh is open in another tab, which owns the models and the saved state. */
  otherTab: boolean
}

export const ui = createStore<UIState>({
  error: null,
  settingsOpen: false,
  settingsTab: 'Appearance',
  customizeOpen: false,
  customizeSection: 'Plugins',
  previewArtifact: null,
  previewAttachment: null,
  revealInChat: false,
  search: '',
  dictating: 'idle',
  voiceOpen: false,
  voicePhase: 'Listening',
  voiceMuted: false,
  voiceLevel: 0,
  voiceReveal: null,
  warming: null,
  voiceLoad: null,
  running: {},
  chatLoaded: null,
  chatLoading: null,
  sidebar: true,
  reading: null,
  upgrade: null,
  otherTab: false,
})

export function useApp<R>(sel: (s: Snapshot) => R): R {
  return useSyncExternalStore(app.subscribe, () => sel(app.get()))
}
export function useUI<R>(sel: (s: UIState) => R): R {
  return useSyncExternalStore(ui.subscribe, () => sel(ui.get()))
}

export const uid = () => crypto.randomUUID()

export function currentChat(): Conversation | undefined {
  const s = app.get()
  return s.chats.find((c) => c.id === s.selectedChatId)
}

export function updateChat(id: string, fn: (c: Conversation) => Conversation) {
  app.set((s) => ({ chats: s.chats.map((c) => (c.id === id ? fn(c) : c)) }))
}

export function updateMessage(chatId: string, msgId: string, fn: (m: Message) => Message) {
  updateChat(chatId, (c) => ({ ...c, messages: c.messages.map((m) => (m.id === msgId ? fn(m) : m)) }))
}

export function newChat(mode: Mode = 'safe'): string {
  const c: Conversation = { id: uid(), title: 'New chat', mode, messages: [], draft: '', attachments: [], updated: Date.now() }
  app.set((s) => ({ chats: [c, ...s.chats], selectedChatId: c.id }))
  ui.set({ search: '' })
  return c.id
}

export function ensureChat(): string {
  return currentChat()?.id ?? newChat()
}

export function showError(text: string) {
  ui.set({ error: text })
}

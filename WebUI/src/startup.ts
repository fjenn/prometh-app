import { on, request, updateNativeState, type NativeState } from './native/bridge'
import { startNewChat } from './state/actions'
import { app, load, ui } from './state/store'
import { prepOrder } from './engine/catalog'
import { probe } from './engine/device'
import { activeLLM, resumePrep, verifyPrepared } from './engine/prep'
import { warmLLM } from './engine/llm'

/**
 * One tab at a time owns the GPU models and the saved state (a second tab would
 * overwrite chats and load the models twice). The other tab shows "open elsewhere".
 */
export function claimTab(steal: boolean) {
  if (!navigator.locks) return void start()
  navigator.locks
    .request('prometh-tab', steal ? { steal: true } : { ifAvailable: true }, (lock) => {
      if (!lock) {
        ui.set({ otherTab: true })
        return
      }
      if (steal) app.set(load())
      ui.set({ otherTab: false })
      void start()
      return new Promise<void>(() => {}) // hold the lock while this tab lives
    })
    // Another tab took over: reload so this one stops its models and shows the notice.
    .catch(() => location.reload())
}

async function start() {
  const d = await probe()
  if (!d.webgpu) return
  await verifyPrepared()
  const s = app.get()
  if (s.onboardingComplete || s.step === 3) for (const k of prepOrder(s)) if (s.preps[k]?.status === 'queued') resumePrep(k)
  // Warm up the model the open chat uses, so the first message answers quickly.
  if (s.onboardingComplete) {
    const chat = s.chats.find((c) => c.id === s.selectedChatId)
    const key = chat?.mode === 'evil' ? 'evil' : 'chat'
    const m = activeLLM(key)
    if (m && app.get().preps[key]?.status === 'ready') {
      // Native loading is reported by the engine event. Health checks run in the background.
      void warmLLM(m).catch(() => undefined)
    }
  }
}


on<string>('menu', command => {
  if (command === 'newChat') startNewChat()
  if (command === 'settings') ui.set({ settingsOpen: true })
  if (command === 'customize') ui.set({ customizeOpen: true })
})
let lastConfiguration = ''
app.subscribe(() => {
  const s = app.get()
  const config = { appearance: s.appearance, onboardingComplete: s.onboardingComplete, evilEnabled: s.evilEnabled, skills: s.skills, readAttachments: s.readAttachments, selected: s.selected }
  const serialized = JSON.stringify(config)
  if (serialized === lastConfiguration) return
  lastConfiguration = serialized
  void request('settings.sync', config).catch(e => ui.set({ error: e.message }))
})

on<NativeState>('state', state => {
  updateNativeState(state)
  if (JSON.stringify(app.get().preps) !== JSON.stringify(state.preps)) app.set({ preps: state.preps })
})

on<Record<string, string>>('chats.metadata', titles => {
  const chats = app.get().chats
  if (chats.some(c => titles[c.id] && titles[c.id] !== c.title)) app.set({ chats: chats.map(c => titles[c.id] ? { ...c, title: titles[c.id] } : c) })
})

on<NativeState['engine']>('engine', engine => { ui.set({ chatLoading: engine.loading ? { model: engine.model, progress: engine.progress, text: engine.text } : null }) })

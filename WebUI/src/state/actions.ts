import { clearTurnExtras } from '../native/state'
import { runVideo } from '../native/video'
import { streamChat } from '../native/llm'
import { request } from '../native/bridge'
import { VOICE_SILENCE_MS } from '../native/vad'
import { beginVoiceTiming, finishVoiceTiming, voiceTurnId } from '../native/voice-latency'
import type { ChatCompletionMessageParam } from '@mlc-ai/web-llm'
import { app, currentChat, ensureChat, freshSnapshot, newChat, showError, ui, uid, updateChat, updateMessage } from './store'
import type { Artifact, Attachment, Capability, Conversation, Message, Mode, PrepKey, Skill } from './types'
import { BLOCKED_MESSAGE, IMAGE, IMAGE_BEST, SYSTEM_EVIL, SYSTEM_SAFE, VOICE_HINT, availability, evilAvailability, imageEngine, isBlocked, type LLMSpec } from '../engine/catalog'
import { getDevice } from '../engine/device'
import { activeLLM, activeModel, cancelPrep, isPreparing, resumePrep, startPreparation } from '../engine/prep'
import { forgetLLM, prefetchLLM, unloadLLM } from '../engine/llm'
import { generateImage, imagesLoaded, releaseImages, speak, transcribe, warmListening, warmSpeech, type Speech } from '../engine/media'
import { checkImagePrompt, signals } from '../engine/prompt-gate'
import { capture, MicBlockedError, player, type Capture, type CaptureOptions } from '../engine/audio'
import { clearBlobs, deleteBlob, putBlob } from '../engine/blobs'

// ---------- onboarding ----------

export function toggleCapability(c: Capability) {
  if (c === 'chat') return
  const d = getDevice()
  const a = d ? availability(c, d) : { ok: false, reason: 'Still checking your device.' }
  if (!a.ok) return showError(a.reason)
  app.set((s) => ({ selected: s.selected.includes(c) ? s.selected.filter((x) => x !== c) : [...s.selected, c] }))
  if (!app.get().selected.includes(c)) cancelPrep(c)
}

/** Continue from the Evil Mode page (onboarding) or close the in-chat reveal. */
export function chooseEvil(enabled: boolean, inChat: boolean) {
  if (enabled) {
    const ev = evilAvailability(getDevice())
    if (!ev.ok) {
      app.set({ defaultMode: 'safe' })
      return showError(ev.reason)
    }
  }
  if (inChat) {
    app.set((s) => ({ evilEnabled: s.evilEnabled || enabled }))
    ui.set({ revealInChat: false })
    if (enabled) {
      setMode('evil')
      if (app.get().preps.evil?.status !== 'ready') resumePrep('evil')
    }
    app.set({ defaultMode: 'safe' })
    return
  }
  // During onboarding the switch is the truth: turning it back off drops the uncensored download.
  app.set({ evilEnabled: enabled, step: 3 })
  if (!enabled) {
    cancelPrep('evil')
    app.set((s) => ({ preps: { ...s.preps, evil: undefined } }))
  }
  startPreparation({ includeStopped: true })
}

/** Which model can open the first chat: Evil Mode if chosen and ready, otherwise Safe chat if ready. */
export function firstChatMode(s = app.get()): Mode | null {
  if (s.evilEnabled && s.defaultMode === 'evil' && s.preps.evil?.status === 'ready') return 'evil'
  if (s.preps.chat?.status === 'ready') return 'safe'
  return null
}

export function enterChat() {
  const mode = firstChatMode()
  if (!mode) return
  const id = newChat(mode)
  app.set({ onboardingComplete: true, defaultMode: 'safe', selectedChatId: id })
  // Keep preparing whatever is still queued; rows the user paused stay paused.
  startPreparation({ includeStopped: false })
}

export function restartOnboarding() {
  endVoice()
  app.set({ onboardingComplete: false, step: 0 })
  ui.set({ settingsOpen: false })
}

// ---------- modes ----------

export function setMode(mode: Mode) {
  const s = app.get()
  if (mode === 'evil' && !s.evilEnabled) {
    app.set({ defaultMode: 'evil' })
    return ui.set({ revealInChat: true })
  }
  const id = ensureChat()
  updateChat(id, (c) => ({ ...c, mode }))
  if (mode === 'evil' && s.preps.evil?.status !== 'ready' && !isPreparing('evil')) resumePrep('evil')
}

export function modelKey(mode: Mode): 'chat' | 'evil' {
  return mode === 'evil' ? 'evil' : 'chat'
}

// ---------- chat ----------

const jobs = new Map<string, { ac: AbortController; msgId: string }>()
/** Image jobs, by message id. They don't occupy the chat: you can keep talking while an image renders. */
const imageJobs = new Map<string, AbortController>()

export function cancelImage(msgId: string) {
  imageJobs.get(msgId)?.abort()
}

export function isRunning(chatId: string) {
  return !!ui.get().running[chatId]
}
function setRunning(chatId: string, on: boolean) {
  ui.set((s) => {
    const r = { ...s.running }
    if (on) r[chatId] = true
    else delete r[chatId]
    return { running: r }
  })
}

/** Stop a chat's running job. The chat is free right away; the old job finishes winding down on its own. */
export function stop(chatId: string) {
  const j = jobs.get(chatId)
  if (!j) return
  j.ac.abort()
  jobs.delete(chatId)
  setRunning(chatId, false)
}

// Only clear requests count: an imperative at the start ("draw a…", "can you make me an image of…"),
// never questions like "how do I make a logo" or "create a script for my video".
// Spoken requests often open with a filler ("Okay, can you draw...").
const ASK = String.raw`^\s*((hey|hi|ok|okay|so|um+|uh+|yeah|alright|now)[\s,.!]+)*(please\s+)?((can|could|would|will)\s+you\s+(please\s+)?)?`
const IMAGE_RE = new RegExp(String.raw`^\s*\/(image|img)\b|${ASK}(draw|paint|sketch)\b|${ASK}(generate|create|make|render|design)\s+(me\s+)?(a|an|the|some)?\s*(\w+\s+){0,2}(image|picture|photo|photograph|drawing|painting|illustration|portrait|wallpaper|poster|artwork)s?\b`, 'i')
const VIDEO_RE = new RegExp(String.raw`${ASK}(make|create|generate|render|produce)\s+(me\s+)?(a|an|the|some)?\s*(\w+\s+){0,2}(video|clip|animation|movie)s?\b`, 'i')

/** False for "can you make me an image?" and the like: an image request that doesn't say what it shows. */
function hasSubject(text: string) {
  const rest = text
    .replace(/^\s*\/(image|img)\b/i, '')
    .replace(new RegExp(String.raw`${ASK}(draw|paint|sketch|generate|create|make|render|design)\b\s*(me\b)?`, 'i'), '')
    .replace(/^\s*((a|an|the|some)\s+)?(\w+\s+){0,2}?(image|picture|photo|photograph|drawing|painting|illustration|portrait|wallpaper|poster|artwork)s?\b/i, '')
    .replace(/\b(of|showing|with|for|from|to|me|us|please|now|one|something|anything|random|it|this|that|real|quick|quickly|right|ok|okay|yeah)\b/gi, '')
  return /[\p{L}\p{N}]/u.test(rest)
}
const ASK_SUBJECT = 'Sure. What should the image show?'
/** "you choose", "whatever", "surprise me": the user leaves the subject to her. */
const LEAVES_IT_TO_YOU = /\b(you (can |could )?(choose|pick|decide)|whatever|surprise me|anything|your (choice|call|pick)|up to you|doesn'?t matter|random|something (cool|nice|fun|beautiful))\b/i

/** The subject of an image request, without the "can you make me an image of" around it. */
function subjectOf(text: string) {
  const s = text
    .replace(/^\s*\/(image|img)\b/i, '')
    .replace(new RegExp(String.raw`${ASK}(draw|paint|sketch|generate|create|make|render|design)\b\s*(me\b)?`, 'i'), '')
    .replace(/^\s*((a|an|the|some)\s+)?(\w+\s+){0,2}?(image|picture|photo|photograph|drawing|painting|illustration|portrait|wallpaper|poster|artwork)s?\b\s*(of|showing|with)?\s*/i, '')
    .replace(/[\s,]*\b(for me|please)\b[\s.!?]*$/i, '')
    .trim()
    .replace(/[.!?]+$/, '')
  return s || text.trim()
}

/** The chat model picks a subject and writes the prompt, when the user leaves it to her. */
async function pickImagePrompt(chatId: string): Promise<string> {
  const fallback = 'a quiet mountain lake at golden hour, mist over the water, photograph'
  const c = app.get().chats.find((x) => x.id === chatId)
  const m = activeLLM(c?.mode === 'evil' ? 'evil' : 'chat')
  if (!c || !m) return fallback
  const recent = c.messages
    .slice(-6)
    .filter((x) => x.text && !x.jobKind)
    .map((x) => `${x.role === 'user' ? 'User' : 'Assistant'}: ${x.text.slice(0, 300)}`)
    .join('\n')
  try {
    const r = await streamChat(
      m,
      [
        { role: 'system', content: 'You write prompts for an image generator.' },
        { role: 'user', content: `The user asked for an image and left the subject to you. Recent conversation:\n${recent}\n\nPick something visually striking (fitting the conversation if it suggests anything) and reply with one image prompt of at most 25 words. Reply with the prompt only, no quotes.` },
      ],
      () => {},
      { maxTokens: 60, temperature: 0.9, signal: new AbortController().signal },
    )
    return r.text.trim().replace(/^["'“]+|["'”]+$/g, '').split('\n')[0].trim() || fallback
  } catch {
    return fallback
  }
}
const imagesReady = () => {
  const s = app.get()
  return s.selected.includes('images') && s.preps.images?.status === 'ready'
}

/** Spoken requests can start mid-sentence ("Let you know that, um, can you draw..."): the text from that clause on. */
function requestPart(text: string) {
  const parts = text.split(/(?<=[,.;!?])\s*/)
  for (let i = 0; i < parts.length; i++) if (IMAGE_RE.test(parts[i])) return parts.slice(i).join(' ')
  return text
}

function intent(c: Conversation, text: string): 'image' | 'video' | null {
  if (c.imageMode) return 'image'
  if (VIDEO_RE.test(text)) return 'video'
  if (IMAGE_RE.test(requestPart(text))) return 'image'
  return null
}

/** The chat model makes an image by writing [[image: description]] (see IMAGES_HINT in the catalog). */
const IMAGE_TAG = /\[\[\s*image\s*:\s*([^\]]+?)\s*\]\]/gi
/** The reply as shown and spoken: image lines removed, and one still being written held back. */
const visibleReply = (t: string, done = false) =>
  t
    .replace(IMAGE_TAG, '')
    .replace(done ? /\[\[[^\]]*$/ : /\[(\[[^\]]*)?$/, '')
    .replace(/[ \t]+\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n')

export function send() {
  const c = currentChat()
  if (!c || isRunning(c.id)) return
  const text = c.draft.trim()
  if (!text && !c.attachments.length) return
  const kind = intent(c, text)
  if (kind === 'image') {
    const s = app.get()
    if (!imagesReady()) {
      const d = getDevice()
      const a = d ? availability('images', d) : { ok: false, reason: '' }
      if (!a.ok) return showError(`${a.reason} Your draft is saved.`)
      if (!s.selected.includes('images')) app.set({ selected: [...s.selected, 'images'] })
      resumePrep('images')
      ui.set({ settingsOpen: true, settingsTab: 'Capabilities' })
      return showError('Preparing images. Your draft is waiting here.')
    }
  }
  const user: Message = { id: uid(), role: 'user', text: text.replace(/^\s*\/(image|img)\s*/i, '') || text, status: 'complete', attachments: c.attachments.length ? c.attachments : undefined }
  const askFirst = kind === 'image' && !c.imageMode && !hasSubject(requestPart(text))
  updateChat(c.id, (x) => ({
    ...x,
    messages: askFirst ? [...x.messages, user, { id: uid(), role: 'assistant', text: ASK_SUBJECT, status: 'complete' }] : [...x.messages, user],
    draft: '',
    attachments: [],
    imageMode: askFirst,
    updated: Date.now(),
    title: x.messages.length === 0 ? titleFrom(text || c.attachments[0]?.filename || 'New chat') : x.title,
  }))
  if (!askFirst) respond(c.id, kind)
}

function titleFrom(text: string) {
  const t = text.replace(/\s+/g, ' ').trim()
  return t.length > 44 ? t.slice(0, 43).trimEnd() + '…' : t
}

/** Start the assistant's turn for the last user message in this chat. */
function respond(chatId: string, kind: 'image' | 'video' | null, source?: Artifact) {
  const c = app.get().chats.find((x) => x.id === chatId)
  if (!c) return
  const last = [...c.messages].reverse().find((m) => m.role === 'user')
  if (!last) return
  if (kind === 'video') return void runVideo(chatId, last.text)
  if (kind === 'image') return void runImage(chatId, last.text, source)
  void runChat(chatId)
}

function skillsText(skills: Skill[]) {
  const on = skills.filter((s) => s.enabled)
  if (!on.length) return ''
  return '\n\nFollow these skills the user enabled:\n' + on.map((s) => `## ${s.name}\n${s.instructions.trim()}`).join('\n\n')
}

const approxTokens = (s: string) => Math.ceil(s.length / 3.6)

/** Build the prompt: system + as much recent history as fits in the 4k context. */
function buildMessages(c: Conversation, voice: boolean): { messages: ChatCompletionMessageParam[]; maxTokens: number } {
  const s = app.get()
  const model = activeLLM(c.mode === 'evil' ? 'evil' : 'chat')
  const about = model ? `\n\nYou are running as ${model.label}, an open model, on the user's own GPU in the Prometh Mac app.` : ''
  const system = (c.mode === 'evil' ? SYSTEM_EVIL : SYSTEM_SAFE) + about + skillsText(s.skills) + (voice ? `\n\n${VOICE_HINT}` : '')
  const CONTEXT = 4096
  const reserve = voice ? 300 : 1100
  let budget = CONTEXT - reserve - approxTokens(system) - 40
  const history: ChatCompletionMessageParam[] = []
  const msgs = c.messages.filter((m) => m.status !== 'failed' && (m.role === 'user' || m.text || m.artifact))
  for (let i = msgs.length - 1; i >= 0; i--) {
    const m = msgs[i]
    let content = m.text
    if (m.role === 'assistant' && m.jobKind === 'image' && m.imagePrompt)
      content = `[[image: ${m.imagePrompt}]] (${m.artifact ? 'the app made this image and showed it to the user' : m.status === 'preparing' ? 'the app is still making this image' : `not made: ${m.text}`})`
    else if (m.role === 'assistant' && m.artifact) content = `[Created an image of: ${m.artifact.prompt}]`
    if (m.role === 'assistant' && m.status === 'stopped') content += ' […]'
    if (m.role === 'user' && m.attachments?.length) {
      const files = m.attachments
        .map((a) => (a.kind === 'text' && a.text != null ? `File "${a.filename}":\n\`\`\`\n${a.text}\n\`\`\`` : `[Attached image "${a.filename}" — this model can't see images yet]`))
        .join('\n\n')
      content = `${files}\n\n${content}`
    }
    let t = approxTokens(content)
    if (t > budget) {
      if (history.length) break
      // The newest message alone is too long: keep its end.
      content = '…' + content.slice(-Math.max(200, Math.floor(budget * 3.6)))
      t = budget
    }
    budget -= t + 6
    history.unshift({ role: m.role, content })
    if (budget < 60) break
  }
  const used = CONTEXT - reserve - budget
  return { messages: [{ role: 'system', content: system }, ...history], maxTokens: Math.max(256, Math.min(voice ? 300 : 1500, CONTEXT - used - 64)) }
}

async function runChat(chatId: string, opts: { voice?: boolean; onText?: (full: string, delta: string) => void } = {}): Promise<string> {
  const c = app.get().chats.find((x) => x.id === chatId)
  if (!c) return ''
  // One model, one generation: stop any other chat's running reply first.
  for (const [id] of jobs) if (id !== chatId) stop(id)
  const key = modelKey(c.mode)
  const model = activeLLM(key)
  const msg: Message = { id: uid(), role: 'assistant', text: '', status: 'streaming', skills: app.get().skills.filter((s) => s.enabled).map((s) => s.name), voice: opts.voice }
  updateChat(chatId, (x) => ({ ...x, messages: [...x.messages, msg], updated: Date.now() }))
  if (!model || app.get().preps[key]?.status !== 'ready') {
    updateMessage(chatId, msg.id, (m) => ({
      ...m,
      status: 'failed',
      text: key === 'evil' ? 'Evil Mode is still getting ready. It will answer as soon as its model has downloaded.' : 'Chat is still getting ready. Your message is saved; try again in a moment.',
    }))
    if (!isPreparing(key)) resumePrep(key)
    return ''
  }
  const ac = new AbortController()
  jobs.set(chatId, { ac, msgId: msg.id })
  setRunning(chatId, true)
  let lastLen = 0
  try {
    // On GPUs that can't hold both, let a running image finish and free its memory first.
    if (tightGPU()) {
      await imageBusy
      if (imagesLoaded()) releaseImages()
    }
    const { messages, maxTokens } = buildMessages({ ...c, messages: c.messages }, !!opts.voice)
    const result = await streamChat(
      model,
      messages,
      (text) => {
        if (ac.signal.aborted) return
        const blocked = isBlocked(text)
        const vis = visibleReply(text)
        updateMessage(chatId, msg.id, (m) => ({ ...m, text: blocked ? BLOCKED_MESSAGE : vis }))
        if (blocked) {
          ac.abort()
          return
        }
        opts.onText?.(vis, vis.slice(lastLen))
        lastLen = vis.length
      },
      { maxTokens, temperature: c.mode === 'evil' ? 0.8 : 0.7, signal: ac.signal, voice: !!opts.voice, chatId, msgId: msg.id, mode: c.mode, userIndex: c.messages.filter(m => m.role === 'user').length - 1 },
    )
    const blocked = isBlocked(result.text)
    const final = blocked ? BLOCKED_MESSAGE : visibleReply(result.text, true).trim()
    updateMessage(chatId, msg.id, (m) => ({ ...m, text: final, status: ac.signal.aborted || result.stopped ? 'stopped' : 'complete', tps: result.tps }))
    // The model asked for images: make them in the background (each one still passes the safety gate).
    if (!blocked && !ac.signal.aborted)
      for (const [, prompt] of [...result.text.matchAll(IMAGE_TAG)].slice(0, 2)) {
        if (!imagesReady()) {
          addCapability('images')
          break
        }
        void runImage(chatId, prompt, undefined, undefined, true).then((r) => opts.voice && announceImage(r))
      }
    return final
  } catch (e) {
    if (ac.signal.aborted) {
      updateMessage(chatId, msg.id, (m) => ({ ...m, status: 'stopped' }))
      return ''
    }
    const err = (e as Error)?.message ?? String(e)
    const oom = /memory|OOM|allocation|device.*lost/i.test(err)
    // A lost GPU device or a broken engine won't recover in place: start a fresh one next time.
    if (/lost|not ?loaded|disposed|destroyed|device/i.test(err)) forgetLLM()
    updateMessage(chatId, msg.id, (m) => ({
      ...m,
      status: 'failed',
      text: oom ? 'Your graphics card ran out of memory. Close other GPU-heavy tabs or apps, then try again.' : `Something interrupted that (${err.slice(0, 160)}). Your request is saved. Try again when you’re ready.`,
    }))
    return ''
  } finally {
    if (jobs.get(chatId)?.msgId === msg.id) {
      jobs.delete(chatId)
      setRunning(chatId, false)
    }
  }
}

/** True when the chat model and the image model don't both fit on this GPU. */
function tightGPU() {
  const d = getDevice()
  const chat = activeLLM('chat')
  return !!(d && chat && d.budgetMB < chat.vramMB + (activeModel('images') ?? IMAGE).vramMB)
}
let imageBusy: Promise<unknown> = Promise.resolve()

/**
 * Make an image for a request. The prompt is the request's subject; if the user left the subject to her, the chat
 * model picks one. onPrompt gets the final prompt as soon as it's known (voice mode says it).
 */
async function runImage(chatId: string, request: string, source?: Artifact, onPrompt?: (prompt: string) => void, authored = false): Promise<'done' | 'blocked' | 'failed' | 'stopped'> {
  const blockedReply = () => {
    const blocked: Message = { id: uid(), role: 'assistant', text: BLOCKED_MESSAGE, status: 'complete' }
    updateChat(chatId, (x) => ({ ...x, messages: [...x.messages, blocked], updated: Date.now() }))
    return 'blocked' as const
  }
  const asked = source ? `${source.prompt}. ${request}` : request
  if (isBlocked(asked) || !checkImagePrompt(asked).allowed) return blockedReply()
  // A prompt the chat model wrote is used as written; a user's request is cut down to its subject.
  const subject = source || authored ? asked : subjectOf(requestPart(request))
  const picking = !source && !authored && LEAVES_IT_TO_YOU.test(subject)
  // One image at a time on the GPU: a new request waits for the one before it.
  const previous = imageBusy
  let done!: () => void
  imageBusy = new Promise<void>((r) => (done = r))
  const msg: Message = { id: uid(), role: 'assistant', text: picking ? 'Choosing what to make…' : 'Waiting for the image before it…', status: 'preparing', jobKind: 'image', sourceArtifact: source, imagePrompt: picking ? undefined : subject }
  updateChat(chatId, (x) => ({ ...x, messages: [...x.messages, msg], updated: Date.now() }))
  const full = picking ? await pickImagePrompt(chatId) : subject
  if (picking && (isBlocked(full) || !checkImagePrompt(full).allowed)) {
    done()
    updateMessage(chatId, msg.id, (m) => ({ ...m, status: 'complete', jobKind: undefined, text: BLOCKED_MESSAGE }))
    return 'blocked'
  }
  updateMessage(chatId, msg.id, (m) => ({ ...m, imagePrompt: full, text: 'Waiting for the image before it…' }))
  onPrompt?.(full)
  const mode = app.get().chats.find((x) => x.id === chatId)?.mode ?? 'safe'
  // Sexual prompts get a hidden "adult" anchor. Negative prompts do nothing without CFG, which this model skips.
  const modelPrompt = signals(full).sexual ? `${full}, adult` : full
  const ac = new AbortController()
  imageJobs.set(msg.id, ac)
  try {
    await previous
    if (ac.signal.aborted) throw new Error('Cancelled')
    updateMessage(chatId, msg.id, (m) => ({ ...m, text: 'Getting the image model ready…' }))
    // Make room on smaller GPUs: waits for any reply being written, then frees the chat model,
    // which reloads by itself on the next message.
    if (tightGPU()) await unloadLLM()
    if (ac.signal.aborted) throw new Error('Cancelled')
    let lastPct = -1
    const result = await generateImage(
      modelPrompt,
      mode,
      imageEngine(activeModel('images')),
      (phase, p) => {
        const pct = Math.round(p * 100)
        if (pct === lastPct) return
        lastPct = pct
        updateMessage(chatId, msg.id, (m) => ({ ...m, text: phase === 'load' ? `Getting the image model ready · ${pct}%` : `Creating your image · ${pct}%` }))
      },
      ac.signal,
    )
    if ('blocked' in result) {
      const text = result.blocked === 'minor' ? BLOCKED_MESSAGE : 'This image came out as adult content, which Safe Mode doesn’t show. Switch this chat to Evil Mode for 18+ images.'
      updateMessage(chatId, msg.id, (m) => ({ ...m, status: 'complete', text, took: result.took }))
      return 'blocked'
    }
    const { blob, width, height } = result
    const art: Artifact = { id: uid(), kind: 'image', blobKey: `img-${uid()}`, prompt: full, parentId: source?.id, version: (source?.version ?? 0) + 1, width, height }
    await putBlob(art.blobKey, blob)
    updateMessage(chatId, msg.id, (m) => ({ ...m, status: 'complete', artifact: art, took: result.took, text: source ? 'New version ready. The original is still above.' : picking ? `Here’s your image: ${full}` : 'Here’s your image.' }))
    return 'done'
  } catch (e) {
    if (ac.signal.aborted) {
      updateMessage(chatId, msg.id, (m) => ({ ...m, status: 'stopped', text: 'Image cancelled.' }))
      return 'stopped'
    }
    updateMessage(chatId, msg.id, (m) => ({ ...m, status: 'failed', text: `The image couldn’t be created (${String((e as Error)?.message ?? e).slice(0, 140)}). Your prompt is saved. Try again.` }))
    return 'failed'
  } finally {
    // The image model stays loaded so the next image is fast; a chat reply frees it first when both don't fit.
    done()
    imageJobs.delete(msg.id)
  }
}

/** Regenerate an assistant message: drop it (and anything after) and answer the preceding user turn again. */
export function regenerate(msgId: string) {
  const c = currentChat()
  if (!c) return
  const i = c.messages.findIndex((m) => m.id === msgId)
  if (i < 0) return
  stop(c.id)
  const m = c.messages[i]
  updateChat(c.id, (x) => ({ ...x, messages: x.messages.slice(0, i) }))
  respond(c.id, m.jobKind === 'image' || m.artifact ? 'image' : m.jobKind === 'video' ? 'video' : null, m.sourceArtifact)
}

export function editMessage(msgId: string, text: string) {
  const c = currentChat()
  if (!c) return
  const i = c.messages.findIndex((m) => m.id === msgId)
  if (i < 0) return
  stop(c.id)
  const old = c.messages[i]
  updateChat(c.id, (x) => ({ ...x, messages: x.messages.slice(0, i), draft: text, attachments: old.attachments ?? [] }))
  send()
}

/** Create a new version of an image from an edit prompt. */
export function editArtifact(source: Artifact, prompt: string) {
  const chat = app.get().chats.find((c) => c.messages.some((m) => m.artifact?.id === source.id))
  if (!chat || isRunning(chat.id)) return
  updateChat(chat.id, (x) => ({ ...x, messages: [...x.messages, { id: uid(), role: 'user', text: prompt, status: 'complete' }] }))
  ui.set({ previewArtifact: null })
  void runImage(chat.id, prompt, source)
}

// ---------- chats ----------

export function selectChat(id: string) {
  endVoice()
  cancelDictation()
  app.set({ selectedChatId: id })
}
export function startNewChat() {
  endVoice()
  cancelDictation()
  const c = currentChat()
  if (c && !c.messages.length && !c.draft) return
  newChat()
}
export function renameChat(id: string, title: string) {
  const t = title.trim()
  if (t) { updateChat(id, (c) => ({ ...c, title: t })); void request('chat.rename', { chatId: id, title: t }).catch(e => showError(e.message)) }
}
export function deleteChat(id: string) {
  stop(id)
  void request('chat.delete', { chatId: id }).catch(e => showError(e.message))
  const c = app.get().chats.find((x) => x.id === id)
  c?.messages.forEach((m) => m.artifact && deleteBlob(m.artifact.blobKey))
  app.set((s) => {
    const chats = s.chats.filter((x) => x.id !== id)
    return { chats, selectedChatId: s.selectedChatId === id ? (chats[0]?.id ?? null) : s.selectedChatId }
  })
}
export function exportChat(id?: string) {
  const c = id ? app.get().chats.find((x) => x.id === id) : currentChat()
  if (!c) return
  const lines = [`# ${c.title}`, '', `_${c.mode === 'evil' ? 'Evil Mode' : 'Safe Mode'} · exported from Prometh_`, '']
  for (const m of c.messages) {
    lines.push(m.role === 'user' ? '**You**' : '**Prometh**', '', m.artifact ? `[image: ${m.artifact.prompt}]` : m.text, '')
  }
  const blob = new Blob([lines.join('\n')], { type: 'text/markdown' })
  void (async () => {
    const key = uid()
    await putBlob(key, blob)
    await request('blob.save', { key, filename: `${c.title.replace(/[^\w\- ]+/g, '').trim() || 'conversation'}.md` })
    await deleteBlob(key)
  })().catch(e => showError(e.message))
}
export function setDraft(text: string) {
  const id = ensureChat()
  updateChat(id, (c) => ({ ...c, draft: text }))
}
export function setImageMode(on: boolean) {
  const id = ensureChat()
  updateChat(id, (c) => ({ ...c, imageMode: on }))
}

// ---------- attachments ----------

const TEXT_EXT = /\.(txt|md|markdown|csv|tsv|json|jsonl|xml|html?|css|js|jsx|ts|tsx|py|rb|go|rs|java|kt|c|h|cpp|hpp|cs|php|sh|bash|zsh|yaml|yml|toml|ini|sql|log|tex|srt|vtt)$/i
const MAX_TEXT = 200_000

export async function addFiles(files: FileList | File[]) {
  if (!app.get().readAttachments) return showError('Turn on Read attachments in Customize → Tools to add files.')
  const id = ensureChat()
  for (const f of Array.from(files)) {
    if (f.type.startsWith('image/')) {
      if (f.size > 20e6) {
        showError(`${f.name} is larger than 20 MB. Your draft is safe.`)
        continue
      }
      const a: Attachment = { id: uid(), filename: f.name, kind: 'image', size: f.size, blobKey: `att-${uid()}` }
      await putBlob(a.blobKey!, f)
      updateChat(id, (c) => ({ ...c, attachments: [...c.attachments, a] }))
    } else if (f.type.startsWith('text/') || TEXT_EXT.test(f.name) || f.type === 'application/json') {
      if (f.size > MAX_TEXT) {
        showError(`${f.name} is too long to read (limit ${MAX_TEXT / 1000} KB). Your draft is safe.`)
        continue
      }
      const text = await f.text()
      updateChat(id, (c) => ({ ...c, attachments: [...c.attachments, { id: uid(), filename: f.name, kind: 'text', size: f.size, text }] }))
    } else {
      showError(`${f.name}: this file type isn't supported yet. Choose a text, code or image file.`)
    }
  }
}
export function removeAttachment(attId: string) {
  const c = currentChat()
  if (!c) return
  const a = c.attachments.find((x) => x.id === attId)
  if (a?.blobKey) void deleteBlob(a.blobKey)
  updateChat(c.id, (x) => ({ ...x, attachments: x.attachments.filter((y) => y.id !== attId) }))
}

// ---------- skills ----------

export function saveSkill(skill: Skill) {
  const name = skill.name.trim()
  const instructions = skill.instructions.trim()
  if (!name || !instructions) return
  app.set((s) => ({ skills: s.skills.some((x) => x.id === skill.id) ? s.skills.map((x) => (x.id === skill.id ? { ...skill, name, instructions } : x)) : [...s.skills, { ...skill, name, instructions }] }))
}
export function setSkillEnabled(id: string, enabled: boolean) {
  app.set((s) => ({ skills: s.skills.map((x) => (x.id === id ? { ...x, enabled } : x)) }))
}
export function deleteSkill(id: string) {
  app.set((s) => ({ skills: s.skills.filter((x) => x.id !== id) }))
}
export async function importSkill(file: File) {
  if (!/\.(md|txt|markdown)$/i.test(file.name) || file.size > 100_000) return showError('Choose a Markdown or text skill smaller than 100 KB.')
  const text = await file.text()
  const title = text.split('\n').find((l) => l.startsWith('# '))?.slice(2).trim() || file.name.replace(/\.[^.]+$/, '')
  saveSkill({ id: uid(), name: title, instructions: text, enabled: true })
}

// ---------- capabilities after onboarding ----------

let upgrading: AbortController | null = null
/** Download a bigger chat model in the background; the current one keeps answering until it's done. */
export async function upgradeChat(m: LLMSpec) {
  if (upgrading) return
  const ac = (upgrading = new AbortController())
  ui.set({ upgrade: { model: m.id, progress: 0 } })
  try {
    await prefetchLLM(m, ac.signal, (done, total) => ui.set({ upgrade: { model: m.id, progress: done / total } }))
    app.set((s) => ({ preps: { ...s.preps, chat: { status: 'ready', progress: 1, model: m.id } } }))
  } catch (e) {
    if (!ac.signal.aborted) showError(`The bigger model didn’t finish downloading (${String((e as Error)?.message ?? e).slice(0, 100)}). Your current model still works; try again later.`)
  } finally {
    upgrading = null
    ui.set({ upgrade: null })
  }
}
export function cancelUpgrade() {
  upgrading?.abort()
}

export function addCapability(c: Capability) {
  const d = getDevice()
  const a = d ? availability(c, d) : { ok: false, reason: 'Still checking your device.' }
  if (!a.ok) return showError(a.reason)
  app.set((s) => ({ selected: s.selected.includes(c) ? s.selected : [...s.selected, c] }))
  resumePrep(c)
}
/** Switch between the fast and the best image model; the new one downloads and prepares like any capability. */
export function setImageModel(best: boolean) {
  const id = best ? IMAGE_BEST.id : IMAGE.id
  if (app.get().preps.images?.model === id) return
  cancelPrep('images')
  releaseImages()
  app.set((s) => ({ preps: { ...s.preps, images: { status: 'queued', progress: 0, model: id } } }))
  resumePrep('images')
}
export function removeCapability(c: Capability) {
  if (c === 'chat') return
  cancelPrep(c)
  app.set((s) => ({ selected: s.selected.filter((x) => x !== c), preps: { ...s.preps, [c]: undefined } }))
  if (c === 'images') releaseImages()
}

export function prepKeyReady(k: PrepKey) {
  return app.get().preps[k]?.status === 'ready'
}

// ---------- dictation ----------

/** Whisper's stock outputs for noise or silence, which would otherwise start a turn on their own. */
const NOISE = /^\s*(you|thank you\.?|thanks\.?|thanks for watching!?|bye\.?|\.+|\[[^\]]*\]|\([^)]*\)|♪+)\s*$/i
const heard = (text: string) => (NOISE.test(text) ? '' : text.trim())

let dictation: Capture | null = null

export async function toggleDictation() {
  const st = ui.get().dictating
  if (st === 'recording') return finishDictation()
  if (st === 'transcribing') return
  if (!prepKeyReady('voice')) return needVoice()
  player.unlock()
  try {
    ui.set({ dictating: 'recording' })
    dictation = await capture({ autoStop: true, silenceMs: 2200, maxMs: 120000, onAutoStop: () => void finishDictation() })
  } catch (e) {
    ui.set({ dictating: 'idle' })
    showError(e instanceof MicBlockedError ? `${e.message} Allow the microphone for this site in the address bar, then try again.` : 'The microphone couldn’t start.')
  }
}
async function finishDictation() {
  const d = dictation
  dictation = null
  if (!d) return
  ui.set({ dictating: 'transcribing' })
  try {
    const audio = await d.stop()
    if (audio) {
      const text = heard(await transcribe(audio))
      if (text) {
        const c = currentChat()
        setDraft(c?.draft ? `${c.draft.trimEnd()} ${text}` : text)
      }
    }
  } catch (e) {
    showError(`Dictation failed: ${String((e as Error)?.message ?? e).slice(0, 120)}`)
  } finally {
    ui.set({ dictating: 'idle' })
  }
}
export function cancelDictation() {
  dictation?.cancel()
  dictation = null
  if (ui.get().dictating !== 'idle') ui.set({ dictating: 'idle' })
}

function needVoice() {
  const d = getDevice()
  const a = d ? availability('voice', d) : { ok: false, reason: 'Still checking your device.' }
  if (!a.ok) return showError(a.reason)
  addCapability('voice')
  ui.set({ settingsOpen: true, settingsTab: 'Capabilities' })
  showError('Preparing voice. It takes a minute the first time.')
}

// ---------- read aloud ----------

let reading: { id: string; speech: Speech } | null = null
const plain = (t: string) =>
  t
    .replace(/<think>[\s\S]*?<\/think>/g, '')
    .replace(/```[\s\S]*?```/g, ' (code) ')
    .replace(/[*_`#>|]/g, '')
    .replace(/\[(.*?)\]\(.*?\)/g, '$1')

export function readAloud(msgId: string, text: string) {
  if (reading?.id === msgId) return stopReading()
  stopReading()
  if (!prepKeyReady('voice')) return needVoice()
  player.unlock()
  const speech = speak(plain(text), app.get().voiceName, (pcm, sr) => player.play(pcm, sr))
  speech.end()
  reading = { id: msgId, speech }
  ui.set({ reading: msgId })
  speech.done
    .then(() => player.drained())
    .finally(() => {
      if (reading?.speech === speech) {
        reading = null
        ui.set({ reading: null })
      }
    })
}
export function stopReading() {
  if (!reading) return
  reading.speech.cancel()
  player.stop()
  reading = null
  ui.set({ reading: null })
}

// ---------- voice conversation ----------

let voiceTurn: { capture: Capture | null; speech: Speech | null; gen: number; standby: Capture | null } = { capture: null, speech: null, gen: 0, standby: null }

export function openVoice() {
  if (!prepKeyReady('voice')) return needVoice()
  stopReading()
  cancelDictation()
  player.unlock()
  ensureChat()
  ui.set({ voiceOpen: true, voiceMuted: false, voicePhase: 'Getting ready' })
  // Load the voice now, so the first reply doesn't wait for it, and the listening model before the mic opens
  // (the first time on a big GPU that's a ~760 MB download, shown as progress).
  warmSpeech()
  void warmListening((p) => ui.set({ voiceLoad: p }))
    .catch(() => undefined)
    .finally(() => {
      ui.set({ voiceLoad: null })
      if (ui.get().voiceOpen) void listen()
    })
}

async function listen() {
  const gen = ++voiceTurn.gen
  const live = () => voiceTurn.gen === gen && ui.get().voiceOpen
  if (!live()) return
  if (ui.get().voiceMuted) return ui.set({ voicePhase: 'Muted' })
  ui.set({ voicePhase: 'Getting ready' })
  const mic = await openMic(false)
  if (!mic) return
  if (!live()) return mic.cap.cancel()
  mic.take()
}

/**
 * Open the mic for the next turn. With whileSpeaking it opens during her reply as a standby mic: a sustained voice
 * clearly louder than her own echo cuts her off and becomes the next turn (barge-in); otherwise it takes over
 * as the listening mic once she's done, so there's no gap.
 */
async function openMic(whileSpeaking: boolean): Promise<{ cap: Capture; take: () => void } | null> {
  let gen = voiceTurn.gen
  let cap: Capture | null = null
  const opts: CaptureOptions = {
    autoStop: true,
    silenceMs: VOICE_SILENCE_MS,
    maxMs: whileSpeaking ? 180000 : 45000,
    minSpeechMs: whileSpeaking ? 200 : 0,
    echo: whileSpeaking ? () => player.level() : undefined,
    // A possible voice over her: dip her volume at once; she stops if it turns out to be speech.
    onCandidate: (on) => voiceTurn.standby === cap && player.duck(on),
    onLevel: (l) => voiceTurn.capture === cap && ui.set({ voiceLevel: l }),
    onSpeech: (on) => {
      if (voiceTurn.capture === cap) return void ui.set({ voicePhase: on ? 'Hearing you' : 'Listening' })
      if (on && voiceTurn.standby === cap) bargeIn()
    },
    onAutoStop: () => void endTurn(gen),
  }
  const take = () => {
    gen = ++voiceTurn.gen
    voiceTurn.standby = null
    player.duck(false)
    voiceTurn.capture = cap
    opts.minSpeechMs = 0
    ui.set({ voicePhase: 'Listening' })
  }
  const bargeIn = () => {
    finishVoiceTiming(voiceTurnId(), 'cancelled')
    const c = currentChat()
    if (c) stop(c.id)
    voiceTurn.speech?.cancel()
    voiceTurn.speech = null
    player.stop()
    take()
    ui.set({ voicePhase: 'Hearing you', voiceReveal: null })
  }
  try {
    cap = await capture(opts)
  } catch (e) {
    if (!whileSpeaking) {
      ui.set({ voicePhase: 'Microphone blocked' })
      showError(e instanceof MicBlockedError ? `${e.message} Allow the microphone for this site in the address bar, then try again.` : 'The microphone couldn’t start.')
    }
    return null
  }
  return { cap, take }
}

/** The user finished speaking (pause detected, or they tapped the orb). */
export async function endTurn(gen = voiceTurn.gen) {
  const cap = voiceTurn.capture
  if (!cap || gen !== voiceTurn.gen) return
  voiceTurn.capture = null
  const live = () => voiceTurn.gen === gen && ui.get().voiceOpen
  ui.set({ voicePhase: 'Thinking', voiceLevel: 0, voiceReveal: null })
  let text = ''
  const timingId = beginVoiceTiming()
  try {
    const audio = await cap.stop()
    if (audio) text = heard(await transcribe(audio))
  } catch (e) {
    showError(`Couldn’t understand that: ${String((e as Error)?.message ?? e).slice(0, 100)}`)
  }
  if (!live()) { finishVoiceTiming(timingId, 'cancelled'); return }
  if (!text || /^[\s\p{P}\p{S}]*$/u.test(text)) { finishVoiceTiming(timingId, 'no_speech'); return void listen() }
  const chatId = ensureChat()
  updateChat(chatId, (c) => ({ ...c, messages: [...c.messages, { id: uid(), role: 'user', text, status: 'complete', voice: true }], title: c.messages.length ? c.title : titleFrom(text), updated: Date.now() }))
  const chat = app.get().chats.find((x) => x.id === chatId)!
  if (intent(chat, text) === 'image') { await voiceImage(chatId, text, live); finishVoiceTiming(timingId, 'complete'); return }
  // The reply streams in token by token like in chat, but held back so its first token shows when her first
  // word plays: every update keeps its timing relative to the first token, shifted to the speech start.
  const replyId = () => app.get().chats.find((x) => x.id === chatId)?.messages.at(-1)?.id ?? ''
  // Listen while she talks, so talking over her interrupts her.
  // Open standby capture in parallel; microphone startup must not delay the LLM request.
  const standbyState: { mic: Awaited<ReturnType<typeof openMic>> } = { mic: null }
  const standbyReady = openMic(true).then(mic => {
    if (!live()) { mic?.cap.cancel(); return }
    standbyState.mic = mic; voiceTurn.standby = mic?.cap ?? null
  })
  const updates: { at: number; text: string }[] = []
  let speechAt: number | null = null
  const reveal = (u: { at: number; text: string }) =>
    setTimeout(() => live() && ui.set({ voiceReveal: { msgId: replyId(), text: u.text } }), Math.max(0, speechAt! + (u.at - updates[0].at) - performance.now()))
  const speech = speak('', app.get().voiceName, (pcm, sr) => {
    if (!live()) return
    ui.set({ voicePhase: 'Speaking' })
    const startsIn = player.play(pcm, sr)
    if (speechAt === null) {
      speechAt = performance.now() + startsIn
      updates.forEach(reveal)
    }
  })
  voiceTurn.speech = speech
  await runChat(chatId, {
    voice: true,
    onText: (full, delta) => {
      if (!live()) return
      if (!updates.length) ui.set({ voiceReveal: { msgId: replyId(), text: '' } })
      const u = { at: performance.now(), text: full }
      updates.push(u)
      if (speechAt !== null) reveal(u)
      speech.push(delta)
    },
  })
  speech.end()
  try {
    await speech.done
  } catch {
    /* speech errors just end the turn */
  }
  await player.drained()
  await standbyReady
  finishVoiceTiming(timingId, 'complete')
  ui.set({ voiceReveal: null })
  // Not live: she was talked over (the standby mic is already the next turn) or voice was closed.
  if (!live()) return
  const standby = standbyState.mic
  if (standby && voiceTurn.standby === standby.cap) standby.take()
  else void listen()
}

/** A spoken image request: ask what it should show if that's missing, otherwise make it and say so. */
async function voiceImage(chatId: string, text: string, live: () => boolean) {
  const say = async (line: string) => {
    if (!live()) return
    const s = speak(line, app.get().voiceName, (pcm, sr) => {
      if (!live()) return
      ui.set({ voicePhase: 'Speaking' })
      player.play(pcm, sr)
    })
    voiceTurn.speech = s
    s.end()
    await s.done.catch(() => {})
    await player.drained()
  }
  const reply = (line: string) =>
    updateChat(chatId, (x) => ({ ...x, messages: [...x.messages, { id: uid(), role: 'assistant', text: line, status: 'complete', voice: true }], updated: Date.now() }))
  const chat = app.get().chats.find((x) => x.id === chatId)!
  if (!imagesReady()) {
    const line = 'Images aren’t set up yet. Add them in Settings, under Capabilities, and ask me again.'
    reply(line)
    await say(line)
  } else if (!chat.imageMode && !hasSubject(requestPart(text))) {
    updateChat(chatId, (x) => ({ ...x, imageMode: true }))
    reply(ASK_SUBJECT)
    await say(ASK_SUBJECT)
  } else {
    updateChat(chatId, (x) => ({ ...x, imageMode: false }))
    // The image renders in the background; the conversation goes on meanwhile. She says what she's making
    // once the prompt is settled (she may pick the subject herself), then listens again.
    let told!: () => void
    const toldDone = new Promise<void>((r) => (told = r))
    ui.set({ voicePhase: 'Thinking' })
    void runImage(chatId, text.replace(/^\s*\/(image|img)\s*/i, ''), undefined, (p) => void say(`Making an image: ${p}. Keep talking if you like.`).then(told)).then((r) => {
      told()
      announceImage(r)
    })
    await toldDone
  }
  if (live()) void listen()
}

/** Say how a background image turned out, if voice is open and she's just listening (never over a turn). */
function announceImage(result: 'done' | 'blocked' | 'failed' | 'stopped') {
  const s = ui.get()
  if (result === 'stopped' || !s.voiceOpen || s.voicePhase !== 'Listening' || voiceTurn.speech) return
  const line = result === 'done' ? 'Your image is ready.' : result === 'blocked' ? 'I couldn’t make that image.' : 'That image didn’t work out.'
  speak(line, app.get().voiceName, (pcm, sr) => player.play(pcm, sr)).end()
}

const dropStandby = () => {
  voiceTurn.standby?.cancel()
  voiceTurn.standby = null
}

export function interruptVoice() {
  finishVoiceTiming(voiceTurnId(), 'cancelled')
  dropStandby()
  const c = currentChat()
  if (c) stop(c.id)
  voiceTurn.speech?.cancel()
  voiceTurn.speech = null
  player.stop()
  ui.set({ voiceReveal: null })
  if (ui.get().voiceOpen) void listen()
}
export function toggleVoiceMute() {
  const muted = !ui.get().voiceMuted
  ui.set({ voiceMuted: muted })
  if (muted) {
    finishVoiceTiming(voiceTurnId(), 'cancelled')
    dropStandby()
    voiceTurn.gen++
    voiceTurn.capture?.cancel()
    voiceTurn.capture = null
    voiceTurn.speech?.cancel()
    player.stop()
    ui.set({ voicePhase: 'Muted', voiceLevel: 0, voiceReveal: null })
  } else void listen()
}
export function endVoice() {
  if (!ui.get().voiceOpen) return
  finishVoiceTiming(voiceTurnId(), 'cancelled')
  dropStandby()
  voiceTurn.gen++
  voiceTurn.capture?.cancel()
  voiceTurn.capture = null
  voiceTurn.speech?.cancel()
  voiceTurn.speech = null
  player.stop()
  const c = currentChat()
  if (c) stop(c.id)
  ui.set({ voiceOpen: false, voicePhase: 'Listening', voiceLevel: 0, voiceReveal: null })
}

// ---------- data ----------

export async function resetData() {
  endVoice()
  await request('data.reset')
  clearTurnExtras()
  for (const [id] of jobs) stop(id)
  for (const ac of imageJobs.values()) ac.abort()
  await clearBlobs().catch(() => undefined)
  const appearance = app.get().appearance
  app.set({ ...freshSnapshot(), appearance })
  ui.set({ settingsOpen: false })
}

export async function deleteDownloads() {
  await request('data.deleteDownloads')
  app.set({ preps: {} })
}

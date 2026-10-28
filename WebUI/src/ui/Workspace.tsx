import { NativeVideoJob } from '../native/ui/Video'
import { NativeMessageExtras } from '../native/ui/MessageExtras'
import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { ui, useApp, useUI } from '../state/store'
import type { Conversation, Message } from '../state/types'
import {
  addFiles,
  deleteChat,
  editMessage,
  endTurn,
  endVoice,
  exportChat,
  interruptVoice,
  isRunning,
  openVoice,
  readAloud,
  regenerate,
  removeAttachment,
  renameChat,
  selectChat,
  send,
  setDraft,
  setImageMode,
  setMode,
  startNewChat,
  stop,
  toggleDictation,
  toggleVoiceMute,
  setSkillEnabled,
} from '../state/actions'
import { prepOrder } from '../engine/catalog'
import { activeLLM } from '../engine/prep'
import { Icon, IconButton } from './Icon'
import { Confirm, MenuButton, Sheet, type MenuItem } from './Overlay'
import { Markdown } from './Markdown'
import { ArtifactCard, AttachmentChip, ImageJob } from './Media'
import { Brand } from './Onboarding'

export function Workspace() {
  const chat = useApp((s) => s.chats.find((c) => c.id === s.selectedChatId))
  const sidebar = useUI((s) => s.sidebar)
  const voiceOpen = useUI((s) => s.voiceOpen)
  const evil = chat?.mode === 'evil'
  const [renaming, setRenaming] = useState<Conversation | null>(null)
  const [deleting, setDeleting] = useState<Conversation | null>(null)

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const mod = e.metaKey || e.ctrlKey
      if (mod && e.shiftKey && e.key.toLowerCase() === 'o') {
        e.preventDefault()
        startNewChat()
      } else if (mod && e.key === ',') {
        e.preventDefault()
        ui.set({ settingsOpen: true })
      } else if (e.key === 'Escape' && ui.get().voiceOpen && !document.querySelector('.backdrop')) endVoice()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  const empty = !chat || chat.messages.length === 0
  return (
    <div className={`ws ${evil ? 'evil' : ''}`}>
      {sidebar && <Sidebar onRename={setRenaming} onDelete={setDeleting} />}
      <main className={`main ${voiceOpen ? 'voice' : ''}`}>
        <header className="hdr">
          <IconButton icon="sidebar" title="Toggle sidebar" onClick={() => ui.set({ sidebar: !sidebar })} />
          <div className="grow">
            <div className="ttl">{chat?.title ?? 'New chat'}</div>
            <div className="mode">{evil ? 'Evil Mode' : 'Safe Mode'}</div>
          </div>
          <LoadIndicator />
          {chat && (
            <MenuButton
              className="icon-btn"
              title="Conversation actions"
              align="right"
              items={[
                { label: 'Rename conversation', icon: 'pencil', onSelect: () => setRenaming(chat) },
                { label: 'Export conversation', icon: 'download', onSelect: () => exportChat(chat.id) },
                { divider: true },
                { label: 'Delete conversation', icon: 'trash', danger: true, onSelect: () => setDeleting(chat) },
              ]}
            >
              <Icon name="dots" size={18} stroke={2.4} />
            </MenuButton>
          )}
        </header>
        {empty && !voiceOpen ? (
          <div className="empty">
            <h2>What do you want to make possible?</h2>
            <div className="composer-wrap">
              <Composer />
            </div>
          </div>
        ) : (
          <>
            {chat && chat.messages.length > 0 ? <Transcript chat={chat} /> : <div style={{ flex: 1 }} />}
            <div className="composer-wrap">
              {voiceOpen && <VoiceLayer />}
              <Composer />
            </div>
          </>
        )}
      </main>
      {renaming && <RenameSheet chat={renaming} onClose={() => setRenaming(null)} />}
      {deleting && <Confirm title="Delete this conversation?" body="It’s removed from this browser. This can’t be undone." action="Delete conversation" onConfirm={() => deleteChat(deleting.id)} onClose={() => setDeleting(null)} />}
    </div>
  )
}

function LoadIndicator() {
  const loading = useUI((s) => s.chatLoading)
  const onboarding = useApp((s) => !s.onboardingComplete)
  if (!loading || onboarding) return null
  const fromCache = /cache/i.test(loading.text)
  return (
    <div className="loadbar" title={loading.text}>
      {fromCache ? 'Waking up the model' : 'Loading model'}
      <div className="bar">
        <i style={{ width: `${Math.round(loading.progress * 100)}%`, background: 'var(--tint)' }} />
      </div>
    </div>
  )
}

function Sidebar({ onRename, onDelete }: { onRename: (c: Conversation) => void; onDelete: (c: Conversation) => void }) {
  const chats = useApp((s) => s.chats)
  const sel = useApp((s) => s.selectedChatId)
  const search = useUI((s) => s.search)
  const notReady = useApp((s) => prepOrder(s).some((k) => s.preps[k]?.status !== 'ready'))
  const q = search.trim().toLowerCase()
  const list = chats.filter((c) => !q || (c.title + ' ' + c.messages.map((m) => m.text).join(' ')).toLowerCase().includes(q)).sort((a, b) => b.updated - a.updated)
  return (
    <aside className="sidebar">
      <div style={{ paddingTop: 4, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <Brand />
      </div>
      <button className="sb-row" onClick={startNewChat}>
        <Icon name="compose" /> New chat <span className="k">⇧⌘O</span>
      </button>
      <label className="sb-search">
        <Icon name="search" size={14} />
        <input placeholder="Search conversations" value={search} onChange={(e) => ui.set({ search: e.target.value })} aria-label="Search conversations" />
      </label>
      <div className="sb-label">{q ? 'SEARCH RESULTS' : 'YOUR CONVERSATIONS'}</div>
      <nav className="sb-list" aria-label="Conversations">
        {list.map((c) => (
          <div key={c.id} className={`sb-item ${c.id === sel ? 'sel' : ''}`}>
            <button className="go" onClick={() => selectChat(c.id)} aria-current={c.id === sel ? 'page' : undefined}>
              <span className="muted" style={{ display: 'grid' }}>
                <Icon name={c.messages.some((m) => m.artifact) ? 'image' : 'bubble'} size={13} />
              </span>
              <span className="title">{c.title}</span>
              {c.mode === 'evil' && <span className="evil-pip" title="Evil Mode" />}
            </button>
            <MenuButton
              className="icon-btn more"
              title="Conversation actions"
              align="right"
              items={[
                { label: 'Rename', icon: 'pencil', onSelect: () => onRename(c) },
                { label: 'Export', icon: 'download', onSelect: () => exportChat(c.id) },
                { divider: true },
                { label: 'Delete', icon: 'trash', danger: true, onSelect: () => onDelete(c) },
              ]}
            >
              <Icon name="dots" size={16} stroke={2.4} />
            </MenuButton>
          </div>
        ))}
        {!list.length && <div className="muted" style={{ fontSize: 12, padding: 12 }}>{q ? 'No conversations found' : 'No conversations yet'}</div>}
      </nav>
      {notReady && (
        <button className="sb-ready" onClick={() => ui.set({ settingsOpen: true, settingsTab: 'Capabilities' })}>
          <Icon name="dotted" size={14} /> Your AI is getting ready <span style={{ marginLeft: 'auto', display: 'grid' }}><Icon name="chevRight" size={12} /></span>
        </button>
      )}
      <button className="sb-row" onClick={() => ui.set({ customizeOpen: true })}>
        <Icon name="sliders" /> Customize
      </button>
      <div className="sb-foot">
        <button className="btn btn-plain" onClick={() => ui.set({ settingsOpen: true })}>
          <Icon name="gear" /> Settings
        </button>
        <span className="muted" style={{ display: 'grid' }} title="Everything runs in this browser">
          <Icon name="lock" size={12} />
        </span>
      </div>
      <div className="sb-private">Private · On this device</div>
    </aside>
  )
}

function Transcript({ chat }: { chat: Conversation }) {
  const ref = useRef<HTMLDivElement>(null)
  const stick = useRef(true)
  const last = chat.messages[chat.messages.length - 1]
  const voiceOpen = useUI((s) => s.voiceOpen)
  useLayoutEffect(() => {
    const el = ref.current
    if (el && stick.current) el.scrollTop = el.scrollHeight
  }, [chat.messages.length, last?.text, last?.status, voiceOpen])
  useLayoutEffect(() => {
    stick.current = true
    const el = ref.current
    if (el) el.scrollTop = el.scrollHeight
  }, [chat.id])
  return (
    <div
      className="transcript"
      ref={ref}
      onScroll={(e) => {
        const el = e.currentTarget
        stick.current = el.scrollHeight - el.scrollTop - el.clientHeight < 80
      }}
    >
      <div className="transcript-in">
        {chat.messages.map((m, i) => (m.role === 'user' ? <UserMessage key={m.id} m={m} /> : <AssistantMessage key={m.id} m={m} chat={chat} last={i === chat.messages.length - 1} />))}
      </div>
    </div>
  )
}

function UserMessage({ m }: { m: Message }) {
  const [editing, setEditing] = useState(false)
  return (
    <div className="msg-user">
      {m.attachments && (
        <div className="att">
          {m.attachments.map((a) => (
            <AttachmentChip key={a.id} a={a} />
          ))}
        </div>
      )}
      {m.text && <div className="bubble">{m.text}</div>}
      <button className="edit" onClick={() => setEditing(true)}>
        Edit
      </button>
      {editing && <EditSheet m={m} onClose={() => setEditing(false)} />}
    </div>
  )
}

function AssistantMessage({ m, chat, last }: { m: Message; chat: Conversation; last: boolean }) {
  const reading = useUI((s) => s.reading === m.id)
  const revealed = useUI((s) => (s.voiceReveal?.msgId === m.id ? s.voiceReveal.text : null))
  const [copied, setCopied] = useState(false)
  const busy = m.status === 'streaming' || m.status === 'preparing'
  // In voice mode the text keeps pace with her speech instead of running ahead of it.
  const text = revealed ?? m.text
  return (
    <div className="msg-ai" style={{ width: '100%', minWidth: 0, alignSelf: 'stretch' }}>
      <div className="who">
        Prometh{m.status === 'streaming' && <span>· Writing</span>}
        {m.voice && <span>· Voice</span>}
      </div>
      {m.jobKind === 'video' ? (
        <NativeVideoJob message={m} />
      ) : m.jobKind === 'image' && !m.artifact ? (
        m.status === 'preparing' ? <ImageJob text={m.text} msgId={m.id} /> : <div className={m.status === 'failed' ? 'failed' : 'md'}>{m.text}</div>
      ) : m.status === 'failed' ? (
        <div className="failed">{m.text}</div>
      ) : text ? (
        <Markdown text={text} streaming={m.status === 'streaming' || revealed !== null} />
      ) : m.status === 'streaming' || revealed !== null ? (
        <div className="md">
          <span className="caret" />
        </div>
      ) : null}
      {m.artifact && <ArtifactCard artifact={m.artifact} />}
      <NativeMessageExtras messageId={m.id} />
      {m.skills && m.skills.length > 0 && <div className="faint" style={{ fontSize: 10 }}>Skills: {m.skills.join(', ')}</div>}
      {!busy && m.jobKind !== 'video' && (
        <div className="acts">
          {!m.artifact && m.text && (
            <IconButton
              icon={copied ? 'check' : 'copy'}
              title="Copy response"
              onClick={() => {
                navigator.clipboard.writeText(m.text)
                setCopied(true)
                setTimeout(() => setCopied(false), 1200)
              }}
            />
          )}
          <IconButton icon="refresh" title={m.status === 'failed' ? 'Retry response' : 'Regenerate response'} onClick={() => regenerate(m.id)} disabled={isRunning(chat.id)} />
          {!m.artifact && m.text && m.status !== 'failed' && <IconButton icon={reading ? 'stop' : 'speaker'} title={reading ? 'Stop reading' : 'Read aloud'} onClick={() => readAloud(m.id, m.text)} />}
          {m.status === 'stopped' && <span className="note">Stopped</span>}
          {m.status === 'failed' && (
            <button className="btn btn-link" onClick={() => regenerate(m.id)}>
              Try again
            </button>
          )}
          {last && m.tps && m.status === 'complete' && <span className="note faint">{m.tps.toFixed(1)} tokens/s on your GPU</span>}
          {last && m.took && m.status === 'complete' && (
            <span className="note faint">
              Made in {m.took.total.toFixed(1)} s on your GPU{m.took.load >= 1 ? ` (${m.took.load.toFixed(1)} s loading the model)` : ''}
            </span>
          )}
        </div>
      )}
    </div>
  )
}

function Composer() {
  const chat = useApp((s) => s.chats.find((c) => c.id === s.selectedChatId))
  const skills = useApp((s) => s.skills)
  const readAtt = useApp((s) => s.readAttachments)
  const evilEnabled = useApp((s) => s.evilEnabled)
  const voiceOpen = useUI((s) => s.voiceOpen)
  const dictating = useUI((s) => s.dictating)
  const running = useUI((s) => (chat ? !!s.running[chat.id] : false))
  const warming = useUI((s) => s.warming)
  const warmPct = useUI((s) => (s.chatLoading ? Math.round(s.chatLoading.progress * 100) : null))
  const evilPrep = useApp((s) => s.preps.evil?.status)
  const ta = useRef<HTMLTextAreaElement>(null)
  const file = useRef<HTMLInputElement>(null)
  const draft = chat?.draft ?? ''
  const evil = chat?.mode === 'evil'
  const draftEmpty = !draft.trim() && !(chat?.attachments.length ?? 0)

  useLayoutEffect(() => {
    const el = ta.current
    if (!el) return
    el.style.height = 'auto'
    el.style.height = Math.min(146, el.scrollHeight) + 'px'
  }, [draft])
  useEffect(() => {
    ta.current?.focus()
  }, [chat?.id, warming])

  const enabledSkills = skills.filter((s) => s.enabled)
  const plusItems = (): MenuItem[] => [
    { label: 'Attach files…', icon: 'clip', onSelect: () => file.current?.click(), disabled: !readAtt },
    { label: chat?.imageMode ? 'Back to chat' : 'Create an image', icon: 'image', onSelect: () => setImageMode(!chat?.imageMode) },
    { divider: true },
    { heading: 'SKILLS' },
    ...(skills.length ? skills.map((s) => ({ label: `${s.enabled ? '✓ ' : '   '}${s.name}`, onSelect: () => setSkillEnabled(s.id, !s.enabled) })) : [{ label: 'Add a skill…', onSelect: () => ui.set({ customizeOpen: true, customizeSection: 'Skills' }) }]),
    { divider: true },
    { label: 'Tools, skills and plugins…', icon: 'sliders', onSelect: () => ui.set({ customizeOpen: true }) },
  ]
  const modeItems: MenuItem[] = [
    { label: `${!evil ? '✓ ' : '   '}Safe Mode`, onSelect: () => setMode('safe') },
    { label: `${evil ? '✓ ' : '   '}Evil Mode`, right: !evilEnabled ? 'Enable…' : evilPrep !== 'ready' ? 'Preparing' : undefined, onSelect: () => setMode('evil') },
  ]
  const model = chat ? activeLLM(evil ? 'evil' : 'chat') : null

  return (
    <div
      className={`composer ${evil ? 'evil' : ''}`}
      onDragOver={(e) => e.preventDefault()}
      onDrop={(e) => {
        e.preventDefault()
        if (e.dataTransfer.files.length) void addFiles(e.dataTransfer.files)
      }}
    >
      {dictating !== 'idle' && (
        <div className="status">
          <span style={{ color: dictating === 'recording' ? 'var(--evil)' : undefined }}>{dictating === 'recording' ? '● Listening… pause or tap the mic to finish' : 'Writing down what you said…'}</span>
        </div>
      )}
      {warming && (
        <div className="status">
          <Icon name="dotted" size={13} /> Warming up {warming} on your GPU{warmPct != null && warmPct < 100 ? ` · ${warmPct}%` : ''}. You can start in a few seconds.
        </div>
      )}
      {evil && evilPrep !== 'ready' && (
        <div className="status">
          <Icon name="dotted" size={13} /> Evil Mode’s model is still downloading. Settings → Capabilities shows progress.
        </div>
      )}
      {(chat?.attachments.length ?? 0) > 0 && (
        <div className="atts">
          {chat!.attachments.map((a) => (
            <AttachmentChip key={a.id} a={a} onRemove={() => removeAttachment(a.id)} />
          ))}
        </div>
      )}
      {chat?.imageMode && (
        <div className="atts">
          <button className="img-mode" onClick={() => setImageMode(false)} title="Back to chat">
            <Icon name="image" size={13} /> Image <Icon name="x" size={12} />
          </button>
        </div>
      )}
      <textarea
        ref={ta}
        rows={1}
        value={draft}
        placeholder={warming ? 'Warming up…' : chat?.imageMode ? 'Describe an image…' : 'Message Prometh'}
        aria-label="Message"
        disabled={!!warming}
        onChange={(e) => setDraft(e.target.value)}
        onPaste={(e) => {
          if (e.clipboardData.files.length) {
            e.preventDefault()
            void addFiles(e.clipboardData.files)
          }
        }}
        onKeyDown={(e) => {
          if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) {
            e.preventDefault()
            if (!running && !warming) send()
          }
        }}
      />
      <input ref={file} type="file" multiple hidden onChange={(e) => e.target.files && void addFiles(e.target.files).finally(() => (e.target.value = ''))} />
      <div className="row">
        <MenuButton className="plus-btn" title="Add" items={plusItems} up>
          <Icon name="plus" size={19} stroke={1.9} />
        </MenuButton>
        <span className="spacer" />
        {enabledSkills.length > 0 && <span className="faint" style={{ fontSize: 11 }}>{enabledSkills.length} skill{enabledSkills.length > 1 ? 's' : ''}</span>}
        <MenuButton className="mode-btn" title={`Mode for this chat${model ? ` · ${model.label}` : ''}`} items={modeItems} align="right" up>
          {evil ? 'Evil Mode' : 'Safe Mode'} <Icon name="chevDown" size={11} stroke={2.4} />
        </MenuButton>
        <button className={`mic-btn ${dictating === 'recording' ? 'rec' : ''}`} title="Dictate" aria-label="Dictate" onClick={() => void toggleDictation()} disabled={voiceOpen || !!warming}>
          <Icon name="mic" />
        </button>
        {voiceOpen ? (
          <button className="orb-btn" title="End voice" aria-label="End voice" onClick={endVoice}>
            <Icon name="x" stroke={2.6} />
          </button>
        ) : running || !draftEmpty ? (
          <button className="orb-btn" title={running ? 'Stop' : 'Send'} aria-label={running ? 'Stop' : 'Send'} onClick={() => (running && chat ? stop(chat.id) : send())} disabled={!running && !!warming}>
            <Icon name={running ? 'stop' : 'up'} stroke={2.6} />
          </button>
        ) : (
          <button className="orb-btn" title="Talk with Prometh" aria-label="Voice conversation" onClick={openVoice} disabled={!!warming}>
            <span className="glyph" aria-hidden="true">
              {[7, 13, 9, 15, 8].map((h, i) => (
                <i key={i} style={{ height: h }} />
              ))}
            </span>
          </button>
        )}
      </div>
    </div>
  )
}

function VoiceLayer() {
  const phase = useUI((s) => s.voicePhase)
  const muted = useUI((s) => s.voiceMuted)
  const level = useUI((s) => s.voiceLevel)
  const load = useUI((s) => s.voiceLoad)
  const speaking = phase === 'Speaking'
  const label =
    phase === 'Listening' ? 'Listening · just talk'
    : phase === 'Hearing you' ? 'Listening…'
    : phase === 'Thinking' ? 'Thinking…'
    : phase === 'Speaking' ? 'Speaking · tap to interrupt'
    : phase === 'Getting ready' && load != null && load < 1 ? `Getting ready · ${Math.round(load * 100)}%`
    : phase
  return (
    <div className="voice-layer">
      <button
        className={`fluid-orb ${speaking ? 'speaking' : ''} ${muted ? 'muted' : ''}`}
        style={!speaking && level > 0 ? { transform: `scale(${1 + level * 0.12})` } : undefined}
        aria-label={speaking ? 'Interrupt' : 'Finish speaking'}
        onClick={() => (speaking ? interruptVoice() : phase === 'Hearing you' || phase === 'Listening' ? void endTurn() : undefined)}
      >
        <i />
        <i />
        <i />
        <i />
      </button>
      <div className="phase" aria-live="polite">
        {label}
      </div>
      <div className="ctl">
        <button className="btn btn-bordered" onClick={toggleVoiceMute}>
          <Icon name={muted ? 'mic' : 'speakerOff'} size={13} /> {muted ? 'Unmute' : 'Mute'}
        </button>
        <button className="btn btn-bordered" onClick={endVoice}>
          End
        </button>
      </div>
    </div>
  )
}

function RenameSheet({ chat, onClose }: { chat: Conversation; onClose: () => void }) {
  const [t, setT] = useState(chat.title)
  const save = () => {
    renameChat(chat.id, t)
    onClose()
  }
  return (
    <Sheet onClose={onClose} width={420} label="Name this conversation">
      <div className="sheet-pad">
        <h2 style={{ fontSize: 20, marginBottom: 16 }}>Name this conversation</h2>
        <input className="field" value={t} onChange={(e) => setT(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && save()} aria-label="Conversation title" />
        <div className="acts">
          <button className="btn btn-plain" onClick={onClose}>
            Cancel
          </button>
          <button className="btn btn-primary" onClick={save} disabled={!t.trim()}>
            Save
          </button>
        </div>
      </div>
    </Sheet>
  )
}

function EditSheet({ m, onClose }: { m: Message; onClose: () => void }) {
  const [t, setT] = useState(m.text)
  return (
    <Sheet onClose={onClose} width={520} label="Edit your message">
      <div className="sheet-pad">
        <h2 style={{ fontSize: 20 }}>Edit your message</h2>
        <p className="muted" style={{ fontSize: 13 }}>
          Sending replaces the replies that follow this message.
        </p>
        <textarea className="field" rows={5} value={t} onChange={(e) => setT(e.target.value)} aria-label="Message text" />
        <div className="acts">
          <button className="btn btn-plain" onClick={onClose}>
            Cancel
          </button>
          <button
            className="btn btn-primary"
            disabled={!t.trim()}
            onClick={() => {
              editMessage(m.id, t)
              onClose()
            }}
          >
            Save &amp; send
          </button>
        </div>
      </div>
    </Sheet>
  )
}


import { nativeState } from '../native/bridge'
import { NativeOnboardingPerformance } from '../native/ui/Settings'
import { app, useApp } from '../state/store'
import type { Capability, PrepKey } from '../state/types'
import { CAPABILITIES } from '../state/types'
import { availability, capCopy, evilAvailability, modelFor, prepOrder } from '../engine/catalog'
import { deviceSummary, useDevice } from '../engine/device'
import { chooseEvil, enterChat, firstChatMode, toggleCapability } from '../state/actions'
import { activeModel, cancelPrep, pausePrep, resumePrep, retryPrep } from '../engine/prep'
import { Icon, IconButton } from './Icon'
import { ui } from '../state/store'

export function Brand({ small }: { small?: boolean }) {
  return (
    <span className="brand" style={small ? { fontSize: 20 } : undefined}>
      Prometh
    </span>
  )
}

export function Onboarding() {
  const step = useApp((s) => s.step)
  const shade = step === 0 ? 'welcome' : step === 2 ? 'evil' : 'muted'
  return (
    <div className="ob">
      <div className={`ob-world ${shade}`} />
      <div className={`ob-shade ${shade}`} />
      <div className="ob-top">
        <Brand />
        <span>On-device AI</span>
      </div>
      <div className="ob-scroll">
        <div className="ob-col" key={step} style={{ maxWidth: step === 1 ? 1240 : step === 2 ? 820 : step === 3 ? 1080 : 800 }}>
          {step === 0 ? <Welcome /> : step === 1 ? <Capabilities /> : step === 2 ? <EvilReveal /> : <Preparation />}
        </div>
      </div>
      <div className="ob-bottom">
        {step > 0 ? (
          <button className="btn" onClick={back}>
            <Icon name="left" size={14} /> Back
          </button>
        ) : (
          <span />
        )}
        <span className="tabnum">{step + 1} / 4</span>
      </div>
    </div>
  )
}

function back() {
  const s = app.get()
  if (s.step === 3) for (const k of prepOrder(s)) pausePrep(k)
  app.set({ step: Math.max(0, s.step - 1) })
}
const next = () => app.set((s) => ({ step: Math.min(3, s.step + 1) }))

function Welcome() {
  return (
    <div className="welcome">
      <h1>AI that you own.</h1>
      <div className="lines">
        <div>Fully private.</div>
        <div>No accounts.</div>
        <div>Full control.</div>
        <div>No restrictions.</div>
      </div>
      <div className="runs">Runs privately on your Mac.</div>
      <button className="btn btn-welcome" onClick={next} autoFocus>
        Get started
      </button>
    </div>
  )
}

function Capabilities() {
  const d = useDevice()
  const selected = useApp((s) => s.selected)
  const total = selected.reduce((sum, c) => sum + (d ? (modelFor(c, d)?.sizeGB ?? 0) : 0), 0)
  return (
    <div className="caps">
      <h2>What capabilities do you want to enable?</h2>
      <div className="sub">Chat is the default.</div>
      <div className="cap-grid">
        {CAPABILITIES.map((c) => (
          <CapCard key={c} cap={c} />
        ))}
      </div>
      {d && !d.webgpu && (
        <div className="nogpu">
          <b>This browser can't reach your graphics card.</b> {d.reason} Prometh runs its AI on your own GPU, so it needs Chrome or Edge on a desktop or laptop.
        </div>
      )}
      <div className="device">{d ? deviceSummary(d) : 'Checking your device…'}</div>
      <div className="foot">
        <span className="total">{total.toFixed(1)} GB</span>
        <span style={{ flex: 1 }} />
        <button className="btn btn-welcome" onClick={next} disabled={!d?.webgpu}>
          Continue
        </button>
      </div>
    </div>
  )
}

function CapCard({ cap }: { cap: Capability }) {
  const d = useDevice()
  const selected = useApp((s) => s.selected.includes(cap))
  const avail = d ? availability(cap, d) : { ok: cap === 'chat', short: 'Checking…', reason: '' }
  const model = d ? modelFor(cap, d) : null
  const isChat = cap === 'chat'
  const cls = ['cap-card', isChat ? 'default' : '', selected && avail.ok && !isChat ? 'on' : '', isChat && avail.ok ? 'on' : '', !avail.ok ? 'off' : ''].join(' ')
  return (
    <button
      className={cls}
      onClick={() => toggleCapability(cap)}
      aria-pressed={isChat || selected}
      aria-label={`${capCopy[cap].title}, ${isChat ? 'default' : selected ? 'selected' : 'not selected'}. ${avail.ok ? capCopy[cap].phrase : avail.reason}`}
      title={avail.ok ? capCopy[cap].detail : avail.reason}
    >
      <img src={`/img/cap-${cap}.webp`} alt="" />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div className="t">
          {capCopy[cap].title}
          {isChat ? (
            <span className="tag">Default</span>
          ) : (
            <span className={`check ${selected && avail.ok ? 'on' : ''}`}>{selected && avail.ok && <Icon name="check" stroke={3} />}</span>
          )}
        </div>
        <div className="p">{avail.ok ? capCopy[cap].phrase : avail.short}</div>
        <div className="gb">{model ? `${model.sizeGB.toFixed(1)} GB` : '\u00a0'}</div>
      </div>
    </button>
  )
}

export function EvilReveal({ inChat }: { inChat?: boolean }) {
  const on = useApp((s) => s.defaultMode === 'evil')
  const d = useDevice()
  const evilModel = d ? modelFor('evil', d) : null
  const ev = evilAvailability(d)
  return (
    <div className="evil-page">
      <h1>Evil Mode</h1>
      <div className="l2">An AI that never says no.</div>
      <div className="l3">Zero restrictions, including adult content. It does not account for ethical concerns.</div>
      <div className="lbl">Enable Evil Mode</div>
      <button
        className={`evil-switch ${on ? 'on' : ''}`}
        role="switch"
        aria-checked={on}
        aria-label="Enable Evil Mode"
        disabled={!ev.ok}
        style={{ marginTop: 18, opacity: ev.ok ? 1 : 0.4 }}
        onClick={() => app.set({ defaultMode: on ? 'safe' : 'evil' })}
      />
      <div className="note">
        {!ev.ok ? ev.reason : `${on && evilModel ? `Adds an uncensored model (${evilModel.sizeGB.toFixed(1)} GB). ` : ''}Each chat picks its own mode. Switch whenever you want. 18+ only.`}
      </div>
      <button className="btn btn-primary btn-coral" style={{ marginTop: 34 }} onClick={() => chooseEvil(on, !!inChat)}>
        {inChat ? 'Done' : 'Continue'}
      </button>
    </div>
  )
}

function Preparation() {
  const s = useApp((x) => x)
  const keys = prepOrder(s)
  const chatReady = firstChatMode(s) != null
  const ready = keys.filter((k) => s.preps[k]?.status === 'ready').length
  return (
    <div className="prep">
      <h2>Preparing your AI</h2>
      <div className="sub">{chatReady ? 'Chat is ready. Open it while the others finish.' : 'You can start chatting as soon as Chat is ready. Downloads happen once, then stay on this Mac.'}</div>
      <div className="prep-grid">
        <div className="glass prep-card">
          {keys.map((k) => (
            <PrepRow key={k} k={k} />
          ))}
          <div className="prep-foot">
            <span className="muted" style={{ fontSize: 12 }}>
              {ready} of {keys.length} ready
            </span>
            <button className="btn btn-primary" disabled={!chatReady} onClick={enterChat}>
              Open chat
            </button>
          </div>
        </div>
        <TurboTeaser />
      </div>
    </div>
  )
}

function TurboTeaser() {
  const d = useDevice()
  if (nativeState) return <NativeOnboardingPerformance />
  const winBlocked = d?.os === 'windows' && !d?.tensor
  return (
    <div className="glass prep-card" style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
      <h3>While you wait: Turbo</h3>
      <p className="muted" style={{ fontSize: 13, lineHeight: 1.55, margin: 0 }}>
        {winBlocked
          ? "The fastest part of your graphics card, the tensor cores, can't be reached from a browser on Windows yet. Turbo works on Mac and Linux. Prometh runs fine without it."
          : "Browsers keep the fastest part of your graphics card, the tensor cores, locked by default. One browser setting unlocks them. We'll walk you through it and check that it worked."}
      </p>
      <div className="row" style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
        {d?.tensor ? <span className="pill good">Tensor cores unlocked</span> : winBlocked ? <span className="pill soon">Mac and Linux only</span> : <span className="pill soon">Tensor cores locked</span>}
        {d?.f16 && <span className="pill good">Half precision</span>}
      </div>
      <button className="btn btn-bordered" style={{ alignSelf: 'flex-start' }} onClick={() => ui.set({ settingsOpen: true, settingsTab: 'Turbo' })}>
        <Icon name="bolt" size={14} /> {winBlocked ? 'Learn more' : 'Show me how'}
      </button>
      <p className="faint" style={{ fontSize: 11, margin: 'auto 0 0' }}>
        Optional. You'll find it later in Settings → Turbo.
      </p>
    </div>
  )
}

const BAR: Record<PrepKey, string> = { chat: '#3aa0d8', voice: '#6e5cc0', images: '#d7a63a', video: '#e36b5c', evil: '#c44848' }

export function PrepRow({ k }: { k: PrepKey }) {
  const p = useApp((s) => s.preps[k])
  useDevice()
  const model = activeModel(k)
  const status = p?.status ?? 'queued'
  const progress = p?.progress ?? 0
  const name = k === 'evil' ? 'Evil Mode' : capCopy[k].title
  let detail: string
  if (status === 'failed') detail = p?.error ?? 'Preparation interrupted. Try again.'
  else if (status === 'ready') detail = k === 'evil' ? 'Uncensored chat' : capCopy[k].phrase
  else if (status === 'paused' || status === 'cancelled') detail = `${status === 'paused' ? 'Paused' : 'Cancelled'}${progress > 0 && model ? ` · ${(progress * model.sizeGB).toFixed(1)} of ${model.sizeGB.toFixed(1)} GB` : ''}`
  else if (status === 'queued') detail = 'Waiting'
  else {
    const word = status === 'preparing' ? 'Getting ready' : status === 'checking' ? 'Almost ready' : 'Downloading'
    detail = model ? `${word} · ${(progress * model.sizeGB).toFixed(1)} of ${model.sizeGB.toFixed(1)} GB` : word
  }
  return (
    <div className="prep-row">
      {k === 'evil' ? <span className="evil-dot" aria-hidden="true" /> : <img src={`/img/cap-${k}.webp`} alt="" />}
      <div className="body">
        <div className="head">
          <div style={{ minWidth: 0 }}>
            <div className="name">{name}</div>
            <div className={`detail ${status === 'failed' ? 'bad' : ''}`}>{detail}</div>
          </div>
          <div className="ctl">
            {status === 'ready' ? (
              <span className="muted" style={{ fontSize: 11, fontWeight: 500 }}>
                Ready
              </span>
            ) : status === 'failed' ? (
              <button className="btn btn-bordered" onClick={() => retryPrep(k)}>
                Retry
              </button>
            ) : status === 'paused' || status === 'cancelled' || status === 'queued' ? (
              <button className="btn btn-bordered" onClick={() => resumePrep(k)}>
                {status === 'queued' ? 'Start' : 'Resume'}
              </button>
            ) : (
              <>
                <IconButton icon="pause" title={`Pause ${name}`} onClick={() => pausePrep(k)} />
                <IconButton icon="x" title={`Cancel ${name}`} onClick={() => cancelPrep(k)} />
              </>
            )}
          </div>
        </div>
        <div className="bar" aria-label={`${name} preparation`} role="progressbar" aria-valuenow={Math.round(progress * 100)} aria-valuemin={0} aria-valuemax={100}>
          <i style={{ width: `${Math.max(progress > 0 ? 1 : 0, progress * 100)}%`, background: BAR[k] }} />
        </div>
      </div>
    </div>
  )
}

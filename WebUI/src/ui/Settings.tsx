import { request } from '../native/bridge'
import { nativeState } from '../native/bridge'
import { NativePlugins, NativeModels, NativeChatModel, NativeSearchToggle, NativePerformance } from '../native/ui/Settings'
import { useEffect, useState } from 'react'
import { app, ui, useApp, useUI, uid, type SettingsTab } from '../state/store'
import type { Capability, Skill } from '../state/types'
import { CAPABILITIES } from '../state/types'
import { IMAGE_BEST, availability, capCopy, evilAvailability, modelFor } from '../engine/catalog'
import { deviceSummary, gpuName, probe, useDevice } from '../engine/device'
import { activeModel } from '../engine/prep'
import { addCapability, cancelUpgrade, deleteDownloads, deleteSkill, exportChat, importSkill, removeCapability, resetData, restartOnboarding, saveSkill, setImageModel, setSkillEnabled, upgradeChat } from '../state/actions'
import { Icon, IconButton } from './Icon'
import { Confirm, Sheet } from './Overlay'
import { Brand, PrepRow } from './Onboarding'

const TABS: SettingsTab[] = ['Appearance', 'Capabilities', 'Turbo', 'Privacy & data']

export function Settings() {
  const tab = useUI((s) => s.settingsTab)
  const close = () => ui.set({ settingsOpen: false })
  return (
    <Sheet onClose={close} className="settings" label="Settings">
      <nav>
        <Brand small />
        {TABS.map((t) => (
          <div key={t} style={{ display: 'contents' }}>
            {t === 'Privacy & data' && (
              <>
                <button onClick={() => ui.set({ settingsOpen: false, customizeOpen: true })}>Customize</button>
                <hr />
              </>
            )}
            <button className={tab === t ? 'on' : ''} onClick={() => ui.set({ settingsTab: t })}>
              {t === 'Turbo' && <Icon name="bolt" size={14} />}
              {t}
            </button>
          </div>
        ))}
        <span className="saved">Saved on this Mac</span>
      </nav>
      <section className="pane">
        <header>
          <h2>{tab}</h2>
          <IconButton icon="x" title="Close settings" onClick={close} />
        </header>
        <div className="scroll">{tab === 'Appearance' ? <Appearance /> : tab === 'Capabilities' ? <Capabilities /> : tab === 'Turbo' ? <Turbo /> : <Privacy />}</div>
      </section>
    </Sheet>
  )
}

function Appearance() {
  const appearance = useApp((s) => s.appearance)
  const sample = (dark: boolean) => (
    <div style={{ flex: 1, height: 130, borderRadius: 15, padding: 18, display: 'flex', flexDirection: 'column', justifyContent: 'space-between', background: dark ? '#22252b' : '#f8f7f4', boxShadow: '0 0 0 1px var(--hair)' }}>
      <div style={{ width: 44, height: 12, borderRadius: 3, background: dark ? 'rgba(255,255,255,.1)' : 'rgba(0,0,0,.07)' }} />
      <div style={{ height: 28, borderRadius: 8, background: dark ? 'rgba(255,255,255,.08)' : 'rgba(0,0,0,.06)' }} />
    </div>
  )
  return (
    <>
      <div className="muted">Choose your preferred appearance.</div>
      <div className="seg" role="radiogroup" aria-label="Appearance">
        {(['Light', 'Dark', 'System'] as const).map((a) => (
          <button key={a} role="radio" aria-checked={appearance === a} className={appearance === a ? 'on' : ''} onClick={() => app.set({ appearance: a })}>
            {a}
          </button>
        ))}
      </div>
      <div style={{ display: 'flex', gap: 14 }}>
        {sample(false)}
        {sample(true)}
      </div>
      <div className="muted" style={{ fontSize: 12 }}>
        Evil Mode has its own accent in each chat, independent of appearance.
      </div>
    </>
  )
}

const VOICES: [string, string][] = [
  ['af_heart', 'Heart (US)'],
  ['af_bella', 'Bella (US)'],
  ['af_nicole', 'Nicole (US)'],
  ['bf_emma', 'Emma (UK)'],
  ['am_michael', 'Michael (US)'],
  ['bm_george', 'George (UK)'],
]

function Capabilities() {
  const d = useDevice()
  const s = useApp((x) => x)
  const total = s.selected.reduce((sum, c) => sum + (activeModel(c)?.sizeGB ?? 0), 0) + (s.evilEnabled ? (activeModel('evil')?.sizeGB ?? 0) : 0)
  const ev = evilAvailability(d)
  const chat = activeModel('chat')
  const better = d ? modelFor('chat', d) : null
  const canUpgrade = !!(chat && better && better.id !== chat.id && better.vramMB > chat.vramMB)
  const upgrade = useUI((x) => x.upgrade)
  return (
    <>
      <div className="muted" style={{ fontSize: 12 }}>
        {d ? deviceSummary(d) : 'Checking your device…'}
      </div>
      <div style={{ fontWeight: 600 }}>{total.toFixed(1)} GB selected</div>
      <NativeModels />
      {CAPABILITIES.map((c) => (
        <CapTile key={c} c={c} />
      ))}
      <div className="tile">
        {s.evilEnabled ? (
          <>
            <PrepRow k="evil" />
            <div className="muted" style={{ fontSize: 12 }}>
              {activeModel('evil')?.label}. Chats in Evil Mode use it; Safe Mode chats keep the regular model.
            </div>
          </>
        ) : (
          <div className="row" style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
            <div style={{ flex: 1 }}>
              <div style={{ fontWeight: 500, fontSize: 15 }}>Evil Mode</div>
              <div className="muted" style={{ fontSize: 12, marginTop: 4 }}>
                {ev.ok ? 'An uncensored model for chats you switch to Evil Mode. 18+.' : ev.reason}
              </div>
            </div>
            <button className="btn btn-bordered" disabled={!ev.ok} onClick={() => ui.set({ settingsOpen: false, revealInChat: true })}>
              Enable…
            </button>
          </div>
        )}
      </div>
      {canUpgrade && better?.engine === 'webllm' && (
        <div className="tile" style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
          <Icon name="bolt" />
          <div style={{ flex: 1, fontSize: 13 }}>
            {upgrade ? (
              <>
                Downloading <b>{better.label}</b> · {Math.round(upgrade.progress * 100)}%. Your current model keeps answering until it’s done.
                <div className="bar">
                  <i style={{ width: `${upgrade.progress * 100}%`, background: 'var(--tint)' }} />
                </div>
              </>
            ) : (
              <>
                A bigger chat model fits this device now: <b>{better.label}</b> ({better.sizeGB.toFixed(1)} GB).
              </>
            )}
          </div>
          {upgrade ? (
            <button className="btn btn-bordered" onClick={cancelUpgrade}>
              Cancel
            </button>
          ) : (
            <button className="btn btn-bordered" onClick={() => void upgradeChat(better)}>
              Upgrade
            </button>
          )}
        </div>
      )}
      <div className="muted" style={{ fontSize: 11, lineHeight: 1.5 }}>
        Models download once from Hugging Face and stay on this Mac. Your conversations never leave this device.
      </div>
    </>
  )
}

function CapTile({ c }: { c: Capability }) {
  const d = useDevice()
  const selected = useApp((s) => s.selected.includes(c))
  const voiceName = useApp((s) => s.voiceName)
  const a = d ? availability(c, d) : { ok: false, short: '', reason: 'Checking…' }
  const m = activeModel(c)
  return (
    <div className="tile" style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      {selected && a.ok ? (
        <>
          <PrepRow k={c} />
          <div className="row" style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <span className="muted" style={{ fontSize: 12 }}>
              {c === 'chat' ? <NativeChatModel /> : m ? `${m.label} · ${m.sizeGB.toFixed(1)} GB` : ''}
            </span>
            <span style={{ flex: 1 }} />
            {c === 'voice' && (
              <label className="muted" style={{ fontSize: 12, display: 'flex', gap: 6, alignItems: 'center' }}>
                Voice
                <select className="field" style={{ width: 'auto', padding: '4px 8px', fontSize: 12 }} value={voiceName} onChange={(e) => app.set({ voiceName: e.target.value })}>
                  {VOICES.map(([id, label]) => (
                    <option key={id} value={id}>
                      {label}
                    </option>
                  ))}
                </select>
              </label>
            )}
            {c === 'images' && !nativeState && (
              <label className="muted" style={{ fontSize: 12, display: 'flex', gap: 6, alignItems: 'center' }}>
                Quality
                <select className="field" style={{ width: 'auto', padding: '4px 8px', fontSize: 12 }} value={m?.id === IMAGE_BEST.id ? 'best' : 'fast'} onChange={(e) => setImageModel(e.target.value === 'best')}>
                  <option value="fast">Fast (2.3 GB)</option>
                  <option value="best">Best (6.2 GB, strong GPU)</option>
                </select>
              </label>
            )}
            {c !== 'chat' && (
              <button className="btn btn-link" onClick={() => removeCapability(c)}>
                Remove
              </button>
            )}
          </div>
        </>
      ) : (
        <>
          <div className="row" style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <img src={`/img/cap-${c}.webp`} alt="" style={{ width: 34, height: 34, opacity: a.ok ? 1 : 0.5 }} />
            <div style={{ flex: 1 }}>
              <div style={{ fontWeight: 500, fontSize: 15 }}>{capCopy[c].title}</div>
              <div className="muted" style={{ fontSize: 12, marginTop: 3 }}>
                {a.ok ? capCopy[c].detail : a.reason}
              </div>
            </div>
            {m && <span className="muted" style={{ fontSize: 12 }}>{m.sizeGB.toFixed(1)} GB</span>}
            {a.ok && (
              <button className="btn btn-bordered" onClick={() => addCapability(c)}>
                Add
              </button>
            )}
          </div>
        </>
      )}
    </div>
  )
}

function Turbo() { return nativeState ? <NativePerformance /> : <BrowserTurbo /> }

function BrowserTurbo() {
  const d = useDevice()
  const [checking, setChecking] = useState(false)
  const flagBase = d?.browser === 'edge' ? 'edge://flags' : 'chrome://flags'
  const chromium = d?.browser === 'chrome' || d?.browser === 'edge'
  // Chrome and Edge on Windows only run WebGPU on D3D12, where Dawn doesn't expose subgroup matrix (research/F_build_engines.md §4).
  const winBlocked = d?.os === 'windows' && !d?.tensor
  const recheck = async () => {
    setChecking(true)
    await probe()
    setChecking(false)
  }
  const check = (ok: boolean | undefined, label: string, note: string) => (
    <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start', padding: '10px 0', borderTop: '1px solid var(--hair)' }}>
      <span className={`pill ${ok ? 'good' : 'soon'}`} style={{ minWidth: 76, justifyContent: 'center' }}>
        {ok ? 'On' : 'Off'}
      </span>
      <div>
        <div style={{ fontWeight: 500, fontSize: 14 }}>{label}</div>
        <div className="muted" style={{ fontSize: 12, marginTop: 2, lineHeight: 1.5 }}>
          {note}
        </div>
      </div>
    </div>
  )
  return (
    <>
      <div className={`turbo-hero ${d?.tensor ? 'on' : ''}`}>
        <h3>{d?.tensor ? 'Turbo is unlocked' : winBlocked ? 'Tensor cores: Mac and Linux only for now' : 'Unlock your tensor cores'}</h3>
        <p>
          {d?.tensor
            ? `This browser now exposes the tensor cores of your ${d ? gpuName(d) : 'GPU'}: the matrix units that make AI fast.`
            : winBlocked
              ? 'Your graphics card has special matrix units built for AI (tensor cores on NVIDIA). Browsers on Windows can’t reach them yet: Chrome and Edge run your graphics card through Direct3D 12 there, and it doesn’t expose them. In the browser, Turbo works on M1 and newer Macs and on Linux. Prometh runs fine on your graphics card without it.'
              : 'Your graphics card has special matrix units (tensor cores on NVIDIA, the matrix units of M1 and newer Macs) built for AI. Browsers keep them locked by default. One setting unlocks them.'}
        </p>
        <div style={{ display: 'flex', gap: 10, marginTop: 4 }}>
          <button className="btn btn-welcome" style={{ padding: '9px 18px', fontSize: 13 }} onClick={recheck} disabled={checking}>
            {checking ? 'Checking…' : 'Check again'}
          </button>
        </div>
      </div>

      <div className="tile">
        <div style={{ fontWeight: 600, marginBottom: 6 }}>Live check · {d ? gpuName(d) : '…'}</div>
        {check(d?.webgpu, 'WebGPU', 'The browser can run AI on your graphics card.')}
        {check(d?.f16, 'Half precision (shader-f16)', d?.f16 ? 'In use now: Prometh runs the faster, smaller model format.' : 'Not on this graphics card or driver. Prometh uses the full-precision format instead; Evil Mode and Images need it.')}
        {check(d?.heapsVisible, 'Real graphics memory readout', d?.heapsVisible ? `In use now: Prometh sees about ${((d?.budgetMB ?? 0) / 1024).toFixed(1)} GB it can use, so it picks the biggest model that fits.` : 'Turn on WebGPU Developer Features below so Prometh can read your real graphics memory and pick the biggest model that fits.')}
        {check(d?.tensor, 'Tensor cores (subgroup matrix)', d?.tensor ? 'Unlocked for this browser. Prometh’s in-browser engines will use them as soon as they support it; the native Prometh Mac app uses them today.' : winBlocked ? 'Not reachable from browsers on Windows yet. Works on M1 and newer Macs and on Linux.' : 'Locked. Follow the steps below.')}
      </div>

      {!chromium && !winBlocked && (
        <div className="tile" style={{ fontSize: 13, lineHeight: 1.55 }}>
          Turbo needs Chrome or Edge on a computer. {d?.browser === 'safari' ? 'Safari' : d?.browser === 'firefox' ? 'Firefox' : 'This browser'} has no switch for tensor cores yet.
        </div>
      )}

      {winBlocked ? (
        <div className="tile">
          <div style={{ fontWeight: 600, marginBottom: 14 }}>Let Prometh read your graphics memory ({d?.browser === 'edge' ? 'Edge' : 'Chrome'})</div>
          <ol className="steps">
            <li>
              <div>
                Copy this address, open a <b>new tab</b>, paste it and press Enter. Set <b>WebGPU Developer Features</b> to <b>Enabled</b>, so Prometh can pick the biggest model that fits:
                <CopyLine text={`${flagBase}/#enable-webgpu-developer-features`} />
              </div>
            </li>
            <li>
              <div>
                Click <b>Relaunch</b> at the bottom of the flags page. Your tabs come back.
              </div>
            </li>
          </ol>
        </div>
      ) : (
        <div className="tile">
          <div style={{ fontWeight: 600, marginBottom: 14 }}>How to unlock ({d?.browser === 'edge' ? 'Edge' : 'Chrome'})</div>
          <ol className="steps">
            <li>
              <div>
                Copy this address, open a <b>new tab</b>, paste it and press Enter. Pages can’t open browser settings themselves, so this one step is yours.
                <CopyLine text={`${flagBase}/#enable-unsafe-webgpu`} />
                Set <b>Unsafe WebGPU Support</b> to <b>Enabled</b>. This unlocks the tensor cores.
              </div>
            </li>
            <li>
              <div>
                In the same flags page, also enable <b>WebGPU Developer Features</b>, so Prometh can read your real graphics memory:
                <CopyLine text={`${flagBase}/#enable-webgpu-developer-features`} />
              </div>
            </li>
            {d?.os === 'linux' && (
              <li>
                <div>
                  On Linux, also enable Vulkan:
                  <CopyLine text={`${flagBase}/#enable-vulkan`} />
                </div>
              </li>
            )}
            <li>
              <div>
                Click <b>Relaunch</b> at the bottom of the flags page. Your tabs come back.
              </div>
            </li>
            <li>
              <div>Come back here. The live check above turns green by itself; press Check again if it doesn’t.</div>
            </li>
          </ol>
        </div>
      )}

      {!winBlocked && (
        <div className="tile" style={{ fontSize: 12, lineHeight: 1.6 }}>
          <b>Good to know.</b> “Unsafe WebGPU” switches off some of the browser’s graphics safety checks for every website, not only Prometh. Keep it on in a browser you use for trusted sites, and set it back to <i>Default</i> when you’re done. In the browser, tensor cores work on M1 and newer Macs, and on Linux with Vulkan on NVIDIA, AMD and Intel cards whose drivers support it. Browsers on Windows can’t reach them yet.
        </div>
      )}
    </>
  )
}

function CopyLine({ text }: { text: string }) {
  const [copied, setCopied] = useState(false)
  return (
    <div className="copyline">
      <span>{text}</span>
      <button
        className="btn btn-bordered"
        onClick={() => {
          navigator.clipboard.writeText(text)
          setCopied(true)
          setTimeout(() => setCopied(false), 1400)
        }}
      >
        {copied ? 'Copied' : 'Copy'}
      </button>
    </div>
  )
}

function Privacy() {
  const [usage, setUsage] = useState<string>('…')
  const [confirm, setConfirm] = useState<'models' | 'all' | null>(null)
  useEffect(() => {
    void request<{ bytes: number }>('data.storage').then(e => setUsage(`${(e.bytes / 1e9).toFixed(1)} GB used by Prometh on this Mac`)).catch(() => setUsage(''))
  }, [confirm])
  return (
    <>
      <div style={{ fontWeight: 600 }}>Your data stays on this device.</div>
      <div className="muted" style={{ lineHeight: 1.55 }}>
        No product account. Your AI runs on this Mac. Chats, skills and settings stay on this device. Web search and connected apps use the services you enable.
      </div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10 }}>
        <button className="btn btn-bordered" onClick={() => exportChat()}>
          <Icon name="download" size={13} /> Export current conversation
        </button>
        <button className="btn btn-bordered" onClick={restartOnboarding}>
          Restart onboarding
        </button>
      </div>
      <hr style={{ border: 0, borderTop: '1px solid var(--hair)', width: '100%', margin: '4px 0' }} />
      <div style={{ fontWeight: 600 }}>Storage</div>
      <div className="muted" style={{ fontSize: 13 }}>
        {usage}
      </div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10 }}>
        <button className="btn btn-bordered" onClick={() => setConfirm('models')}>
          Delete downloaded models…
        </button>
        <button className="btn btn-bordered btn-danger" onClick={() => setConfirm('all')}>
          Clear all data…
        </button>
      </div>
      <hr style={{ border: 0, borderTop: '1px solid var(--hair)', width: '100%', margin: '4px 0' }} />
      <div style={{ fontWeight: 600 }}>About</div>
      <div className="muted" style={{ fontSize: 12, lineHeight: 1.6 }}>
        Prometh runs open models on your Mac with MLX and Metal. Chat uses the model selected in Capabilities; Evil Mode uses a separate uncensored model. Whisper handles listening, Kokoro handles speaking, FLUX makes images, and the native video engine makes clips. Models download once and stay on this Mac.
      </div>
      {confirm === 'models' && (
        <Confirm title="Delete downloaded models?" body="Frees the storage the AI models use. Your chats stay. Prometh downloads models again when you use them." action="Delete models" onConfirm={() => void deleteDownloads()} onClose={() => setConfirm(null)} />
      )}
      {confirm === 'all' && <Confirm title="Clear all Prometh data?" body="Deletes every conversation, skill, image and setting in this browser. Downloaded models stay." action="Clear everything" onConfirm={() => void resetData()} onClose={() => setConfirm(null)} />}
    </>
  )
}

// ---------- Customize ----------

const PROVIDERS = [
  ['gmail', 'Gmail', 'Read selected messages and draft replies'],
  ['outlook', 'Outlook', 'Read selected messages and draft replies'],
  ['drive', 'Google Drive', 'Find and read selected documents'],
  ['github', 'GitHub', 'Read selected repositories and issues'],
] as const

export function Customize() {
  const section = useUI((s) => s.customizeSection)
  const close = () => ui.set({ customizeOpen: false })
  return (
    <Sheet onClose={close} width={720} label="Customize">
      <div className="sheet-pad" style={{ display: 'flex', flexDirection: 'column', gap: 20, height: 'min(640px, calc(100vh - 48px))' }}>
        <div className="row" style={{ alignItems: 'flex-start' }}>
          <div style={{ flex: 1 }}>
            <h2 style={{ fontSize: 27, letterSpacing: -0.8 }}>Customize</h2>
            <div className="muted" style={{ fontSize: 13, marginTop: 6 }}>
              Plugins, tools and skills.
            </div>
          </div>
          <IconButton icon="x" title="Close Customize" onClick={close} />
        </div>
        <div className="seg" role="tablist" style={{ alignSelf: 'flex-start' }}>
          {(['Plugins', 'Tools', 'Skills'] as const).map((s) => (
            <button key={s} role="tab" aria-selected={section === s} className={section === s ? 'on' : ''} onClick={() => ui.set({ customizeSection: s })}>
              {s}
            </button>
          ))}
        </div>
        <div style={{ flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 18 }}>{section === 'Plugins' ? <Plugins /> : section === 'Tools' ? <Tools /> : <Skills />}</div>
      </div>
    </Sheet>
  )
}

function Plugins() { return nativeState ? <NativePlugins /> : <BrowserPlugins /> }

function BrowserPlugins() {
  return (
    <>
      <div className="muted">Apps your AI can use.</div>
      <div>
        {PROVIDERS.map(([id, name, access], i) => (
          <div key={id} style={{ display: 'flex', gap: 12, alignItems: 'center', padding: '11px 0', borderTop: i ? '1px solid var(--hair)' : undefined }}>
            <img src={`/img/provider-${id}.webp`} alt="" style={{ width: 25, height: 25, padding: 8, boxSizing: 'content-box', background: '#fff', borderRadius: 10, objectFit: 'contain' }} />
            <div style={{ flex: 1 }}>
              <div style={{ fontWeight: 500, fontSize: 13 }}>{name}</div>
              <div className="muted" style={{ fontSize: 11, marginTop: 3 }}>
                {access}
              </div>
            </div>
            <span className="pill soon">Coming soon</span>
          </div>
        ))}
      </div>
      <div className="muted" style={{ fontSize: 11, lineHeight: 1.5 }}>
        Connectors arrive with the Prometh Mac app. They’ll ask your permission per app, and the AI that reads your data stays on your device.
      </div>
    </>
  )
}

function Tools() {
  const read = useApp((s) => s.readAttachments)
  const row = (name: string, detail: string, on: boolean, toggle?: () => void, soon?: boolean) => (
    <div style={{ display: 'flex', alignItems: 'flex-start', gap: 24 }}>
      <div style={{ flex: 1 }}>
        <div style={{ fontWeight: 500, fontSize: 15 }}>
          {name} {soon && <span className="pill soon" style={{ marginLeft: 6 }}>Coming soon</span>}
        </div>
        <div className="muted" style={{ fontSize: 12, marginTop: 6, lineHeight: 1.5 }}>
          {detail}
        </div>
      </div>
      <button className={`toggle ${on ? 'on' : ''}`} role="switch" aria-checked={on} aria-label={name} onClick={toggle} disabled={!toggle} />
    </div>
  )
  return (
    <>
      <div className="muted">What your AI is allowed to do.</div>
      {row('Read attachments', 'Work with text, code and data files you attach. Files are read in this browser, never uploaded.', read, () => app.set({ readAttachments: !read }))}
      <hr style={{ border: 0, borderTop: '1px solid var(--hair)', width: '100%', margin: 0 }} />
      <NativeSearchToggle />
    </>
  )
}

function Skills() {
  const skills = useApp((s) => s.skills)
  const [editing, setEditing] = useState<Skill | null>(null)
  const [deleting, setDeleting] = useState<Skill | null>(null)
  return (
    <>
      <div className="muted">Reusable instructions for how your AI works.</div>
      <div style={{ display: 'flex', gap: 10 }}>
        <button className="btn btn-primary" style={{ padding: '9px 18px', fontSize: 13 }} onClick={() => setEditing({ id: uid(), name: '', instructions: '', enabled: true })}>
          Add skill
        </button>
        <label className="btn btn-bordered" style={{ padding: '9px 14px', fontSize: 13 }}>
          Import file…
          <input type="file" accept=".md,.txt,.markdown,text/markdown,text/plain" hidden onChange={(e) => e.target.files?.[0] && void importSkill(e.target.files[0]).finally(() => (e.target.value = ''))} />
        </label>
      </div>
      {!skills.length && (
        <div className="tile">
          <div style={{ fontSize: 18, fontWeight: 500 }}>No skills added</div>
          <div className="muted" style={{ fontSize: 13, lineHeight: 1.5, margin: '10px 0 14px' }}>
            Create a skill or import a Markdown file. For example, ask for concise answers or a particular writing style.
          </div>
          <button className="btn btn-bordered" onClick={() => saveSkill({ id: uid(), name: 'Concise answers', instructions: 'Keep answers concise. Start with the answer and avoid unnecessary explanation.', enabled: true })}>
            Add “Concise answers”
          </button>
        </div>
      )}
      {skills.map((s) => (
        <div key={s.id} className="tile" style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <div style={{ flex: 1, fontWeight: 500, fontSize: 15 }}>{s.name}</div>
            <button className={`toggle ${s.enabled ? 'on' : ''}`} role="switch" aria-checked={s.enabled} aria-label={`Enable ${s.name}`} onClick={() => setSkillEnabled(s.id, !s.enabled)} />
          </div>
          <div className="muted" style={{ fontSize: 12, lineHeight: 1.5, display: '-webkit-box', WebkitLineClamp: 3, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>
            {s.instructions}
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between' }}>
            <button className="btn btn-link" onClick={() => setEditing(s)}>
              Edit
            </button>
            <button className="btn btn-link btn-danger" onClick={() => setDeleting(s)}>
              Delete
            </button>
          </div>
        </div>
      ))}
      <div className="muted" style={{ fontSize: 11, lineHeight: 1.5 }}>
        Enabled skills are added to the AI’s instructions for every new reply.
      </div>
      {editing && <SkillEditor skill={editing} onClose={() => setEditing(null)} />}
      {deleting && <Confirm title="Delete this skill?" body={`“${deleting.name}” will be removed.`} action="Delete skill" onConfirm={() => deleteSkill(deleting.id)} onClose={() => setDeleting(null)} />}
    </>
  )
}

function SkillEditor({ skill, onClose }: { skill: Skill; onClose: () => void }) {
  const [s, setS] = useState(skill)
  return (
    <Sheet onClose={onClose} width={560} label="Skill">
      <div className="sheet-pad" style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        <h2>Skill</h2>
        <input className="field" placeholder="Skill name" value={s.name} onChange={(e) => setS({ ...s, name: e.target.value })} aria-label="Skill name" />
        <div style={{ fontWeight: 500, fontSize: 13 }}>Instructions</div>
        <textarea className="field" rows={9} value={s.instructions} onChange={(e) => setS({ ...s, instructions: e.target.value })} aria-label="Skill instructions" />
        <label style={{ display: 'flex', gap: 10, alignItems: 'center', fontSize: 13 }}>
          <button type="button" className={`toggle ${s.enabled ? 'on' : ''}`} role="switch" aria-checked={s.enabled} onClick={() => setS({ ...s, enabled: !s.enabled })} /> Enable for new replies
        </label>
        <div className="acts">
          <button className="btn btn-plain" onClick={onClose}>
            Cancel
          </button>
          <button
            className="btn btn-primary"
            disabled={!s.name.trim() || !s.instructions.trim()}
            onClick={() => {
              saveSkill(s)
              onClose()
            }}
          >
            Save skill
          </button>
        </div>
      </div>
    </Sheet>
  )
}

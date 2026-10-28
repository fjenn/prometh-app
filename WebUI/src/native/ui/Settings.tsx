import { connectedFirst, httpsLogo, pluginInitial } from '../presentation'
import { useEffect, useState } from 'react'
import { nativeState, on, request, updateNativeState, type NativeState } from '../bridge'
import { app, showError } from '../../state/store'
type Plugin = { slug: string; name: string; description: string; logo: string; status: string }
type Plugins = { items: Plugin[]; error: string }
export function NativePlugins() {
  const [data, setData] = useState<Plugins>({ items: [], error: '' }), [loading, setLoading] = useState(true), [search, setSearch] = useState(''), [busy, setBusy] = useState('')
  const load = (refresh = false) => { setLoading(true); void request<Plugins>('plugins.list', { refresh }).then(setData).catch(e => setData({ items: [], error: e.message })).finally(() => setLoading(false)) }
  useEffect(() => { load() }, [])
  const act = (p: Plugin) => {
    setBusy(p.slug)
    void request<Plugins>(p.status === 'connected' ? 'plugins.disconnect' : 'plugins.connect', { slug: p.slug }).then(setData).catch(e => showError(e.message)).finally(() => setBusy(''))
  }
  return <>
    <div className="row"><div className="grow muted">Apps your AI can use.</div><button className="btn btn-bordered" onClick={() => load(true)} disabled={loading}>Refresh</button></div>
    <input className="field" placeholder="Search apps" value={search} onChange={e => setSearch(e.target.value)} />
    {loading && <div className="muted">Loading your apps…</div>}
    {data.error && <div className="failed">{data.error}</div>}
    {connectedFirst(data.items).filter(p => `${p.name} ${p.description}`.toLowerCase().includes(search.toLowerCase())).map((p, i) => <div key={p.slug} style={{ display: 'flex', gap: 12, alignItems: 'center', padding: '11px 0', borderTop: i ? '1px solid var(--hair)' : undefined }}>
      <PluginLogo name={p.name} logo={p.logo} />
      <div style={{ flex: 1 }}><div style={{ fontWeight: 500, fontSize: 13 }}>{p.name}</div><div className="muted" style={{ fontSize: 11, marginTop: 3 }}>{p.description}</div></div>
      <button className="btn btn-bordered" disabled={!!busy} onClick={() => act(p)}>{busy === p.slug ? 'Waiting…' : p.status === 'connected' ? 'Disconnect' : 'Connect'}</button>
    </div>)}
    <div className="muted" style={{ fontSize: 11 }}>Your AI asks permission before using a connected app.</div>
  </>
}
function PluginLogo({ name, logo }: { name: string; logo: string }) {
  const src = httpsLogo(logo)
  const [loaded, setLoaded] = useState<string | null>(null), [failed, setFailed] = useState<string | null>(null)
  return <div aria-hidden="true" style={{ position: 'relative', width: 41, height: 41, flex: '0 0 41px', borderRadius: 10, background: '#fff', display: 'grid', placeItems: 'center', fontSize: 19, fontWeight: 500, color: 'var(--text-2)' }}>
    {(!src || loaded !== src || failed === src) && <span>{pluginInitial(name)}</span>}
    {src && failed !== src && <img src={src} alt="" referrerPolicy="no-referrer" onLoad={event => { if (event.currentTarget.naturalWidth > 0) setLoaded(src); else setFailed(src) }} onError={() => setFailed(src)} style={{ position: 'absolute', width: 25, height: 25, objectFit: 'contain', opacity: loaded === src ? 1 : 0 }} />}
  </div>
}

type RuntimeModel = { repo: string; label: string; id?: string; sizeGB?: number }
export function NativeChatModel() {
  const [model, setModel] = useState<RuntimeModel | null>(null), [status, setStatus] = useState('Checking the loaded model…')
  useEffect(() => {
    let live = true
    const refresh = async () => {
      try { const result = await request<{ model: RuntimeModel | null }>('runtime.get'); if (live) { setModel(result.model); setStatus('No chat model loaded') } }
      catch { if (live) { setModel(null); setStatus('Loaded model unavailable') } }
    }
    void refresh()
    const timer = window.setInterval(() => void refresh(), 5000)
    return () => { live = false; clearInterval(timer) }
  }, [])
  return <span title={model?.repo}>{model ? `${model.label}${model.sizeGB == null ? '' : ` · ${model.sizeGB.toFixed(1)} GB`} · In use` : status}</span>
}

export function NativeModels() {
  const [state, setState] = useState(nativeState)
  useEffect(() => on<NativeState>('state', setState), [])
  const choose = (family: string, id: string) => void request<NativeState>('settings.model', { family, id }).then(s => { updateNativeState(s); setState(s); app.set({ preps: s.preps }) }).catch(e => showError(e.message))
  return <div className="tile">{state?.modelOptions.map(f => <div key={f.family} className="row" style={{ marginBottom: 10 }}><label className="grow" htmlFor={'native-' + f.family}>{f.family === 'safe' ? 'Preferred safe chat' : f.label}</label><select id={'native-' + f.family} className="field" style={{ width: 'auto', fontSize: 12 }} value={f.selected} onChange={e => choose(f.family, e.target.value)}>{f.options.map(m => <option key={m.id} value={m.id}>{m.label}</option>)}</select></div>)}</div>
}
export function NativeSearchToggle() {
  const [enabled, setEnabled] = useState(nativeState?.webSearch ?? true)
  return <div style={{ display: 'flex', alignItems: 'flex-start', gap: 24 }}><div className="grow"><div style={{ fontWeight: 500, fontSize: 15 }}>Web search</div><div className="muted" style={{ fontSize: 12, marginTop: 6 }}>Find fresh information and include sources in replies.</div></div><button className={`toggle ${enabled ? 'on' : ''}`} role="switch" aria-label="Web search" aria-checked={enabled} onClick={() => void request<boolean>('settings.search', { enabled: !enabled }).then(setEnabled).catch(e => showError(e.message))} /></div>
}
export function NativePerformance() {
  return <><h3>Ready for Apple silicon</h3><div className="muted">{nativeState?.specs.summary}</div><div className="tile"><div style={{ fontWeight: 500 }}>Your AI runs on this Mac</div><p className="muted">Prometh uses Metal and MLX for chat and images. Voice and video use the models prepared in Capabilities.</p><div className="pill">Native acceleration</div></div></>
}
export function NativeOnboardingPerformance() {
  return <div className="glass prep-card" style={{ display: 'flex', flexDirection: 'column', gap: 14 }}><h3>Ready for your Mac</h3><p className="muted" style={{ fontSize: 13, lineHeight: 1.55, margin: 0 }}>{nativeState?.specs.summary}</p><div className="row" style={{ display: 'flex', gap: 10, alignItems: 'center' }}><span className="pill good">Native acceleration</span><span className="pill good">Apple silicon</span></div><p className="faint" style={{ fontSize: 11, margin: 'auto 0 0' }}>Your models stay on this Mac. You can change them later in Settings → Capabilities.</p></div>
}

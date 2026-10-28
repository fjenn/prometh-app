import { useState } from 'react'
import { request } from '../bridge'
import { useTurnExtras, appendTurnExtra } from '../state'
import { externalURL, extrasColumnStyle, sourceRowStyle, sourceChipStyle } from '../presentation'
import { showError } from '../../state/store'
export function NativeMessageExtras({ messageId }: { messageId: string }) {
  const extras = useTurnExtras(messageId)
  const decide = (id: string, decision: string) => void request('connector.decide', { id, decision }).catch(e => showError(e.message))
  return <>{extras.map(item => <div key={item.id} style={extrasColumnStyle}>
    {!!item.sources?.length && <div className="acts" style={sourceRowStyle} aria-label="Sources">{item.sources.map((source, i) => {
      const url = externalURL(source.url)
      return url && <a className="btn btn-bordered" style={sourceChipStyle} href={url} key={source.url} title={`${i + 1}. ${source.title} · ${new URL(url).hostname}`} onClick={event => { event.preventDefault(); void request('browser.open', { url }).catch(e => showError(e.message)) }}>{i + 1}. {source.title}</a>
    })}</div>}
    {item.connector && <div className="tile">
      <div style={{ fontWeight: 500 }}>{item.connector.name} · {item.connector.action}</div>
      <div className="muted" style={{ fontSize: 12, marginTop: 6 }}>{item.connector.summary}</div>
      {item.connector.phase === 'awaitingConsent' ? <div className="acts">
        <button className="btn btn-primary" onClick={() => decide(item.id, 'once')}>Allow once</button>
        <button className="btn btn-bordered" onClick={() => decide(item.id, 'always')}>Always allow</button>
        <button className="btn" onClick={() => decide(item.id, 'deny')}>Don’t allow</button>
      </div> : <div className="muted" style={{ fontSize: 11, marginTop: 6 }}>{item.connector.detail || item.connector.phase}</div>}
    </div>}
    {item.artifact && <div className="art-card">
      {item.artifact.kind === 'video' ? <video src={'prometh-ui://media/' + encodeURIComponent(item.artifact.filename)} controls style={{ width: '100%' }} /> : <img src={'prometh-ui://media/' + encodeURIComponent(item.artifact.filename)} alt={item.artifact.prompt} style={{ width: '100%' }} />}
      <div className="foot"><div className="grow"><div className="k">{item.artifact.kind === 'video' ? 'Video' : 'Image'}</div><div className="v">Version {item.artifact.version}</div></div><button className="btn" onClick={() => void request('media.save', { filename: item.artifact!.filename }).catch(e => showError(e.message))}>Save</button></div>
    </div>}
    {item.artifact?.kind === 'video' && <VideoTrim filename={item.artifact.filename} duration={item.artifact.duration} messageId={messageId} version={item.artifact.version} prompt={item.artifact.prompt} />}
  </div>)}</>
}

function VideoTrim({ filename, duration, messageId, version, prompt }: { filename: string; duration: number; messageId: string; version: number; prompt: string }) {
  const [editing, setEditing] = useState(false), [start, setStart] = useState(0), [end, setEnd] = useState(duration), [busy, setBusy] = useState(false)
  const trim = () => { setBusy(true); void request<{ filename: string; duration: number }>('media.trim', { filename, start, end }).then(result => { appendTurnExtra(messageId, { id: crypto.randomUUID(), artifact: { kind: 'video', filename: result.filename, duration: result.duration, version: version + 1, prompt } }); setEditing(false) }).catch(e => showError(e.message)).finally(() => setBusy(false)) }
  return <>

    {editing ? <div className="tile"><div style={{ fontWeight: 500 }}>Trim your clip</div><div className="row"><label>In <input className="field" type="number" min={0} max={Math.max(0, end - 0.1)} step={0.1} value={start} onChange={e => setStart(Number(e.target.value))} /></label><label>Out <input className="field" type="number" min={start + 0.1} max={duration} step={0.1} value={end} onChange={e => setEnd(Number(e.target.value))} /></label></div><div className="acts"><button className="btn" onClick={() => setEditing(false)} disabled={busy}>Back</button><button className="btn btn-primary" onClick={trim} disabled={busy || end <= start || start < 0 || end > duration}>{busy ? 'Saving your clip…' : 'Create new version'}</button></div></div> : <button className="btn" onClick={() => setEditing(true)}>Edit video</button>}
  </>
}

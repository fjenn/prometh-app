import { useState } from 'react'
import { app, ui, useUI } from '../state/store'
import type { Artifact, Attachment } from '../state/types'
import { downloadBlob, useBlobUrl } from '../engine/blobs'
import { cancelImage, editArtifact, isRunning } from '../state/actions'
import { Icon, IconButton } from './Icon'
import { Sheet } from './Overlay'

export function ArtifactCard({ artifact }: { artifact: Artifact }) {
  const url = useBlobUrl(artifact.blobKey)
  return (
    <div className="art-card">
      <button className="poster" onClick={() => ui.set({ previewArtifact: { artifact, edit: false } })} aria-label="Preview image">
        {url ? <img src={url} alt={artifact.prompt} /> : <div style={{ aspectRatio: '1' }} />}
      </button>
      <div className="foot">
        <div style={{ flex: 1, minWidth: 0 }}>
          <div className="k">Image</div>
          <div className="v">
            Version {artifact.version} · {artifact.width}×{artifact.height}
          </div>
        </div>
        <button className="btn" onClick={() => downloadBlob(artifact.blobKey, `Prometh-image-v${artifact.version}.png`)}>
          Save
        </button>
        <button className="btn" onClick={() => ui.set({ previewArtifact: { artifact, edit: true } })}>
          Edit
        </button>
      </div>
    </div>
  )
}

export function ImageJob({ text, msgId }: { text: string; msgId: string }) {
  const pct = Number(text.match(/(\d+)%/)?.[1] ?? 0)
  const drawing = /Creating/.test(text)
  return (
    <div className="gen-card">
      <div className="canvas" aria-hidden="true" />
      <div style={{ fontSize: 13 }}>{text}</div>
      <div className="bar" style={{ maxWidth: 320 }}>
        <i style={{ width: `${pct}%`, background: drawing ? '#d7a63a' : 'var(--tint)' }} />
      </div>
      <div>
        <button className="btn btn-bordered" onClick={() => cancelImage(msgId)}>
          Cancel
        </button>
      </div>
    </div>
  )
}

export function VideoNote({ text }: { text: string }) {
  return (
    <div className="video-card">
      <div className="hero">
        <b>Video lives in the Mac app</b>
        <span>Prometh for Mac · coming with Finn’s app</span>
      </div>
      <div className="foot">{text}</div>
    </div>
  )
}

export function AttachmentChip({ a, onRemove }: { a: Attachment; onRemove?: () => void }) {
  const url = useBlobUrl(a.kind === 'image' ? a.blobKey : undefined)
  return (
    <span className={`chip ${a.kind === 'image' ? 'img' : ''}`}>
      <button className="btn" style={{ gap: 6, minWidth: 0 }} onClick={() => ui.set({ previewAttachment: a })} title={`Preview ${a.filename}`}>
        {a.kind === 'image' ? url ? <img src={url} alt="" /> : <Icon name="image" size={13} /> : <Icon name="doc" size={13} />}
        <span>{a.filename}</span>
      </button>
      {onRemove && (
        <button className="btn" onClick={onRemove} title="Remove attachment" aria-label={`Remove ${a.filename}`}>
          <Icon name="x" size={12} />
        </button>
      )}
    </span>
  )
}

export function ArtifactPreview() {
  const p = useUI((s) => s.previewArtifact)
  const [prompt, setPrompt] = useState('')
  const [editing, setEditing] = useState(p?.edit ?? false)
  const [lastId, setLastId] = useState<string | null>(null)
  const url = useBlobUrl(p?.artifact.blobKey)
  useUI((s) => s.running) // re-render when a chat starts or finishes, for the edit button
  if (!p) return null
  if (p.artifact.id !== lastId) {
    setLastId(p.artifact.id)
    setEditing(p.edit)
    setPrompt('')
  }
  const a = p.artifact
  const close = () => ui.set({ previewArtifact: null })
  return (
    <Sheet onClose={close} width={740} label="Image preview">
      <div className="sheet-pad" style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
        <div className="row">
          <div style={{ flex: 1 }}>
            <h2 style={{ fontSize: 20 }}>Image preview</h2>
            <div className="muted" style={{ fontSize: 12, marginTop: 4 }}>
              Version {a.version} · {a.parentId ? 'Edited version' : 'Original'}
            </div>
          </div>
          <button className="btn btn-bordered" onClick={() => downloadBlob(a.blobKey, `Prometh-image-v${a.version}.png`)}>
            <Icon name="download" size={13} /> Save
          </button>
          <IconButton icon="x" title="Close preview" onClick={close} />
        </div>
        {url && <img className="preview-img" src={url} alt={a.prompt} />}
        <div className="muted" style={{ fontSize: 12 }}>
          {a.prompt}
        </div>
        {editing ? (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            <div style={{ fontWeight: 600 }}>Describe your change</div>
            <textarea className="field" rows={2} autoFocus value={prompt} placeholder="Make it sunset, add snow, turn it into a watercolor…" onChange={(e) => setPrompt(e.target.value)} />
            <div className="muted" style={{ fontSize: 11 }}>
              Prometh draws a new version from your original description plus this change. The original stays in the chat.
            </div>
            <div className="acts" style={{ marginTop: 6 }}>
              <button className="btn btn-plain" onClick={() => setEditing(false)}>
                Back
              </button>
              <button className="btn btn-primary" disabled={!prompt.trim() || isEditBusy(a)} onClick={() => editArtifact(a, prompt.trim())}>
                Create new version
              </button>
            </div>
          </div>
        ) : (
          <div className="acts" style={{ marginTop: 0 }}>
            <span className="muted" style={{ fontSize: 12 }}>
              Made on your own GPU.
            </span>
            <button className="btn btn-primary" onClick={() => setEditing(true)}>
              Edit image
            </button>
          </div>
        )}
      </div>
    </Sheet>
  )
}

/** An edit can't start while the chat that holds the image is busy. */
function isEditBusy(a: Artifact) {
  const chat = app.get().chats.find((c) => c.messages.some((m) => m.artifact?.id === a.id))
  return !!chat && isRunning(chat.id)
}

export function AttachmentPreview() {
  const a = useUI((s) => s.previewAttachment)
  const url = useBlobUrl(a?.kind === 'image' ? a.blobKey : undefined)
  if (!a) return null
  const close = () => ui.set({ previewAttachment: null })
  return (
    <Sheet onClose={close} width={680} label={a.filename}>
      <div className="sheet-pad" style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
        <div className="row">
          <h2 style={{ fontSize: 18, flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{a.filename}</h2>
          <IconButton icon="x" title="Close attachment" onClick={close} />
        </div>
        {a.kind === 'image' ? (
          url && <img className="preview-img" src={url} alt={a.filename} />
        ) : (
          <pre className="md" style={{ margin: 0, maxHeight: '60vh', overflow: 'auto', fontFamily: 'var(--mono)', fontSize: 12.5, whiteSpace: 'pre-wrap', background: 'var(--fill-1)', padding: 16, borderRadius: 12 }}>
            {a.text}
          </pre>
        )}
        {a.kind === 'image' && (
          <div className="muted" style={{ fontSize: 12 }}>
            The current chat models read text only, so Prometh sees the file name, not the picture.
          </div>
        )}
      </div>
    </Sheet>
  )
}

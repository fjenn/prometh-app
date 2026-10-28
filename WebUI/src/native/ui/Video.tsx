import type { Message } from '../../state/types'
import { cancelVideo } from '../video'
export function NativeVideoJob({ message }: { message: Message }) {
  if (message.status !== 'preparing') return message.text ? <div className={message.status === 'failed' ? 'failed' : 'md'}>{message.text}</div> : null
  const pct = Number(message.text.match(/(\d+)%/)?.[1] ?? 0)
  return <div className="gen-card">
    <div className="canvas" aria-hidden="true" />
    <div style={{ fontSize: 13 }}>{message.text}</div>
    <div className="bar" style={{ maxWidth: 320 }}><i style={{ width: `${pct}%`, background: 'var(--tint)' }} /></div>
    <div><button className="btn btn-bordered" onClick={() => cancelVideo(message.id)}>Cancel</button></div>
  </div>
}

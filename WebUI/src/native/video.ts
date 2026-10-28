import { request, on } from './bridge'
import { uid, updateChat, updateMessage } from '../state/store'
import type { Message } from '../state/types'
import { setTurnExtras, type TurnExtra } from './state'
const jobs = new Map<string, AbortController>()
export function cancelVideo(msgId: string) { jobs.get(msgId)?.abort(); void request('media.cancel', { jobId: msgId }) }
export async function runVideo(chatId: string, prompt: string) {
  const msg: Message = { id: uid(), role: 'assistant', text: 'Making your video', status: 'preparing', jobKind: 'video' }
  updateChat(chatId, chat => ({ ...chat, messages: [...chat.messages, msg], updated: Date.now() }))
  const ac = new AbortController(); jobs.set(msg.id, ac)
  let progress = 0
  const off = on<{ jobId: string; progress: number }>('media.progress', p => {
    if (p.jobId !== msg.id || ac.signal.aborted || !Number.isFinite(p.progress)) return
    progress = Math.max(progress, Math.min(1, p.progress))
    updateMessage(chatId, msg.id, m => ({ ...m, text: `Making your video · ${Math.round(progress * 100)}%` }))
  })
  try {
    const artifact = await request<NonNullable<TurnExtra['artifact']>>('media.video', { jobId: msg.id, prompt })
    if (ac.signal.aborted) throw new DOMException('Stopped', 'AbortError')
    setTurnExtras(msg.id, [{ id: msg.id, artifact }])
    updateMessage(chatId, msg.id, m => ({ ...m, text: '', status: 'complete' }))
  } catch (e) { updateMessage(chatId, msg.id, m => ({ ...m, status: ac.signal.aborted ? 'stopped' : 'failed', text: ac.signal.aborted ? 'Stopped' : (e as Error).message })) }
  finally { off(); jobs.delete(msg.id) }
}

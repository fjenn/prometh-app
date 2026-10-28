import { request } from './bridge'
let active: string | undefined
let endAgoMs = 0
export function noteVADPause(agoMs: number) { endAgoMs = agoMs }
export const voiceTurnId = () => active
export function beginVoiceTiming(agoMs = endAgoMs) {
  const id = crypto.randomUUID()
  active = id
  endAgoMs = 0
  void request('voice.begin', { id, agoMs }).catch(() => {})
  return id
}
export function voiceMark(id: string | undefined, stage: string, extra: Record<string, unknown> = {}) {
  if (id) void request('voice.mark', { id, stage, ...extra }).catch(() => {})
}
export function finishVoiceTiming(id: string | undefined, status: string) {
  if (id === active) active = undefined
  if (id) void request('voice.finish', { id, status }).catch(() => {})
}

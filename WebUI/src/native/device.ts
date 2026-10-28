import { setTurnExtras } from './state'
import { useSyncExternalStore } from 'react'
import { bootstrap, nativeState } from './bridge'
import { app, ui } from '../state/store'
export type OS = 'mac' | 'windows' | 'linux' | 'chromeos' | 'android' | 'ios' | 'other'
export type Browser = 'chrome' | 'edge' | 'safari' | 'firefox' | 'other'

export interface DeviceInfo {
  webgpu: boolean
  /** Why WebGPU is unavailable, in plain words. */
  reason?: string
  vendor: string
  architecture: string
  f16: boolean
  subgroups: boolean
  /** Tensor cores exposed (chromium-experimental-subgroup-matrix, needs chrome://flags/#enable-unsafe-webgpu). */
  tensor: boolean
  /** Real VRAM heaps are readable (needs chrome://flags/#enable-webgpu-developer-features). */
  heapsVisible: boolean
  /** Estimated GPU memory Prometh can use, in MB. */
  budgetMB: number
  /** How budgetMB was found. */
  budgetSource: 'heaps' | 'probe' | 'none'
  ramGB: number | null
  freeGB: number | null
  os: OS
  browser: Browser
  mobile: boolean
}

let current: DeviceInfo | null = null
const listeners = new Set<() => void>()
export const getDevice = () => current
export const useDevice = () => useSyncExternalStore((fn) => { listeners.add(fn); return () => { listeners.delete(fn) } }, getDevice)
export async function probe(): Promise<DeviceInfo> {
  const s = await bootstrap()
  document.documentElement.dataset.theme = s.appearance === 'Dark' || (s.appearance === 'System' && matchMedia('(prefers-color-scheme: dark)').matches) ? 'dark' : 'light' 
  app.set({ onboardingComplete: s.onboardingComplete, appearance: s.appearance, evilEnabled: s.evilEnabled, selected: s.selected, preps: s.preps, skills: s.skills, ...(app.get().chats.length ? {} : { chats: s.chats, selectedChatId: s.chats[0]?.id ?? null }) })
  for (const [id, extras] of Object.entries(s.extras)) if (extras.length) setTurnExtras(id, extras)
  ui.set({ chatLoading: s.engine.loading ? { model: s.engine.model, progress: s.engine.progress, text: s.engine.text } : null })
  current = { webgpu: true, vendor: 'apple', architecture: s.specs.chip, f16: true, subgroups: true, tensor: false, heapsVisible: true, budgetMB: s.specs.memoryGB * 700, budgetSource: 'heaps', ramGB: s.specs.memoryGB, freeGB: s.specs.freeStorageGB, os: 'mac', browser: 'safari', mobile: false }
  listeners.forEach(fn => fn())
  return current
}
export const gpuName = (_d: DeviceInfo) => nativeState?.specs.chip ?? 'Apple silicon'
export const deviceSummary = (_d: DeviceInfo) => nativeState?.specs.summary ?? 'Mac'

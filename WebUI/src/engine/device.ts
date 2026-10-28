import { useSyncExternalStore } from 'react'

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
const subscribe = (l: () => void) => {
  listeners.add(l)
  return () => listeners.delete(l)
}
export const getDevice = () => current
export function useDevice() {
  return useSyncExternalStore(subscribe, () => current)
}

function detectOS(): OS {
  const ua = navigator.userAgent
  if (/iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)) return 'ios'
  if (/Android/.test(ua)) return 'android'
  if (/CrOS/.test(ua)) return 'chromeos'
  if (/Mac OS X|Macintosh/.test(ua)) return 'mac'
  if (/Windows/.test(ua)) return 'windows'
  if (/Linux/.test(ua)) return 'linux'
  return 'other'
}
function detectBrowser(): Browser {
  const ua = navigator.userAgent
  if (/Edg\//.test(ua)) return 'edge'
  if (/Firefox\//.test(ua)) return 'firefox'
  if (/Chrome\//.test(ua) || /CriOS/.test(ua)) return 'chrome'
  if (/Safari\//.test(ua)) return 'safari'
  return 'other'
}

/** Model sizes we probe for, largest first (MB of GPU memory, from WebLLM's vram_required_MB plus headroom). */
const PROBE_STEPS = [7600, 4300, 2500, 1000]

/**
 * There is no VRAM query in WebGPU. Reserve the memory a model would need, in
 * chunks, inside out-of-memory and validation error scopes, then free it.
 * Same approach as the c0mpute browser worker. It can still say yes on Windows,
 * where Dawn pages over PCIe instead of failing, so loading keeps a fallback.
 */
async function probeBudget(adapter: GPUAdapter): Promise<number> {
  let device: GPUDevice
  try {
    device = await adapter.requestDevice({
      requiredLimits: {
        maxBufferSize: adapter.limits.maxBufferSize,
        maxStorageBufferBindingSize: adapter.limits.maxStorageBufferBindingSize,
      },
    })
  } catch {
    return 0
  }
  const chunk = Math.min(512 * 1024 * 1024, device.limits.maxBufferSize)
  try {
    for (const mb of PROBE_STEPS) {
      const buffers: GPUBuffer[] = []
      let ok = true
      device.pushErrorScope('validation')
      device.pushErrorScope('out-of-memory')
      try {
        let left = mb * 1024 * 1024
        while (left > 0) {
          const size = Math.min(chunk, left)
          buffers.push(device.createBuffer({ size, usage: GPUBufferUsage.STORAGE }))
          left -= size
        }
      } catch {
        ok = false
      }
      const oom = await device.popErrorScope()
      const invalid = await device.popErrorScope()
      buffers.forEach((b) => b.destroy())
      if (ok && !oom && !invalid) return mb
    }
    return 0
  } finally {
    device.destroy()
  }
}

export async function probe(): Promise<DeviceInfo> {
  const os = detectOS()
  const browser = detectBrowser()
  const mobile = os === 'android' || os === 'ios'
  const ramGB = (navigator as Navigator & { deviceMemory?: number }).deviceMemory ?? null
  let freeGB: number | null = null
  try {
    const est = await navigator.storage?.estimate?.()
    if (est?.quota != null) freeGB = Math.max(0, Math.floor(((est.quota ?? 0) - (est.usage ?? 0)) / 1e9))
  } catch {
    /* storage estimate is optional */
  }
  const base: DeviceInfo = {
    webgpu: false,
    vendor: '',
    architecture: '',
    f16: false,
    subgroups: false,
    tensor: false,
    heapsVisible: false,
    budgetMB: 0,
    budgetSource: 'none',
    ramGB,
    freeGB,
    os,
    browser,
    mobile,
  }
  if (!('gpu' in navigator) || !navigator.gpu) {
    base.reason =
      browser === 'firefox'
        ? 'Firefox only has WebGPU on some systems so far.'
        : browser === 'safari'
          ? 'Safari needs WebGPU switched on (Safari 26 or newer).'
          : os === 'linux'
            ? 'On Linux, Chrome needs chrome://flags/#enable-unsafe-webgpu and #enable-vulkan switched on.'
            : 'WebGPU is not available here.'
    return set(base)
  }
  let adapter: GPUAdapter | null = null
  try {
    adapter = await navigator.gpu.requestAdapter({ powerPreference: 'high-performance' })
  } catch {
    adapter = null
  }
  if (!adapter) {
    base.reason = 'The browser has WebGPU but found no usable graphics card (it may be blocklisted or switched off in settings).'
    return set(base)
  }
  const info = (adapter as GPUAdapter & { info?: GPUAdapterInfo & { memoryHeaps?: { size: number; properties: number }[] } }).info
  const d: DeviceInfo = {
    ...base,
    webgpu: true,
    vendor: info?.vendor ?? '',
    architecture: info?.architecture ?? '',
    f16: adapter.features.has('shader-f16'),
    subgroups: adapter.features.has('subgroups'),
    tensor: adapter.features.has('chromium-experimental-subgroup-matrix' as GPUFeatureName),
  }
  // With chrome://flags/#enable-webgpu-developer-features the adapter reports its memory heaps.
  const heaps = info?.memoryHeaps
  if (heaps && heaps.length) {
    const DEVICE_LOCAL = 0x1
    const local = heaps.filter((h) => h.properties & DEVICE_LOCAL).map((h) => h.size)
    const biggest = Math.max(...(local.length ? local : heaps.map((h) => h.size)))
    if (biggest > 0) {
      d.heapsVisible = true
      d.budgetMB = Math.floor((biggest / 1048576) * (os === 'mac' ? 0.7 : 0.85))
      d.budgetSource = 'heaps'
    }
  }
  if (!d.heapsVisible) {
    d.budgetMB = await probeBudget(adapter)
    d.budgetSource = 'probe'
  }
  // Manual cap (localStorage 'prometh.maxBudgetMB'), for forcing a smaller model on a busy or shared GPU.
  const cap = Number(localStorage.getItem('prometh.maxBudgetMB'))
  if (cap > 0) d.budgetMB = Math.min(d.budgetMB, cap)
  // Phones and small machines: keep the model small even if a big reservation passed.
  if (mobile) d.budgetMB = Math.min(d.budgetMB, 1000)
  else if (ramGB != null && ramGB <= 2) d.budgetMB = Math.min(d.budgetMB, 1000)
  else if (ramGB != null && ramGB <= 4) d.budgetMB = Math.min(d.budgetMB, 2500)
  return set(d)
}

function set(d: DeviceInfo) {
  current = d
  listeners.forEach((l) => l())
  return d
}

export function gpuName(d: DeviceInfo): string {
  const v = d.vendor ? d.vendor.charAt(0).toUpperCase() + d.vendor.slice(1) : 'Graphics card'
  const vendor = v === 'Nvidia' ? 'NVIDIA' : v === 'Amd' ? 'AMD' : v
  if (d.os === 'mac' && d.vendor === 'apple') return 'Apple silicon'
  return d.architecture ? `${vendor} ${d.architecture}` : vendor
}

export function deviceSummary(d: DeviceInfo): string {
  if (!d.webgpu) return 'No WebGPU in this browser'
  const parts = [gpuName(d)]
  if (d.budgetMB > 0) parts.push(`${d.budgetMB >= 7600 ? '8+' : (d.budgetMB / 1024).toFixed(d.budgetMB < 2048 ? 1 : 0)} GB for AI`)
  if (d.freeGB != null) parts.push(`${d.freeGB} GB available`)
  return parts.join(' · ')
}

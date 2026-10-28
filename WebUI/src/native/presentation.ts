import type { CSSProperties } from 'react'

// Existing .btn-bordered geometry and the transcript's 6px action gap.
export const extrasColumnStyle: CSSProperties = { width: '100%', minWidth: 0, alignSelf: 'stretch' }
export const sourceRowStyle: CSSProperties = { display: 'flex', flexWrap: 'wrap', gap: 6, width: '100%', minWidth: 0, marginLeft: 0 }
export const sourceChipStyle: CSSProperties = { display: 'block', flex: '0 1 auto', minWidth: 0, maxWidth: 'min(260px, 100%)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', textDecoration: 'none', color: 'inherit', boxSizing: 'border-box' }

export function externalURL(raw: string): string | null {
  try { const url = new URL(raw); return ['https:', 'http:'].includes(url.protocol) && !url.username && !url.password ? url.href : null } catch { return null }
}
export function httpsLogo(raw: string): string | null {
  const url = externalURL(raw)
  return url?.startsWith('https:') ? url : null
}
export const pluginInitial = (name: string) => Array.from(name.trim())[0]?.toLocaleUpperCase() ?? '?'
export function connectedFirst<T extends { name: string; status: string }>(items: T[]): T[] {
  return [...items].sort((a, b) => Number(b.status === 'connected') - Number(a.status === 'connected') || a.name.localeCompare(b.name))
}

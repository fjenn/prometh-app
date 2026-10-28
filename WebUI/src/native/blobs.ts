import { useEffect, useState } from 'react'
import { request } from './bridge'
import { base64 } from './encoding'
const url = (key: string) => 'prometh-ui://blob/' + encodeURIComponent(key)
export async function putBlob(key: string, blob: Blob) { await request('blob.put', { key, data: base64(await blob.arrayBuffer()), mime: blob.type }) }
export async function getBlob(key: string): Promise<Blob | undefined> { try { const res = await fetch(url(key)); return res.ok ? await res.blob() : undefined } catch { return undefined } }
export const deleteBlob = (key: string) => request('blob.delete', { key })
export const clearBlobs = () => request('blob.clear')
export function useBlobUrl(key: string | undefined) {
  const [value, setValue] = useState<string | null>(key ? url(key) : null)
  useEffect(() => { setValue(key ? url(key) : null) }, [key]); return value
}
export const downloadBlob = (key: string, filename: string) => request('blob.save', { key, filename })

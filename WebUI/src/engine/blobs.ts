import { useEffect, useState } from 'react'

// Generated images and attached pictures live in IndexedDB; chat state only keeps their keys.
const DB = 'prometh'
const STORE = 'blobs'

let dbp: Promise<IDBDatabase> | null = null
function db() {
  dbp ??= new Promise((resolve, reject) => {
    const r = indexedDB.open(DB, 1)
    r.onupgradeneeded = () => r.result.createObjectStore(STORE)
    r.onsuccess = () => resolve(r.result)
    r.onerror = () => reject(r.error)
  })
  return dbp
}
async function tx<T>(mode: IDBTransactionMode, fn: (s: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  const d = await db()
  return new Promise((resolve, reject) => {
    const req = fn(d.transaction(STORE, mode).objectStore(STORE))
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => reject(req.error)
  })
}

export const putBlob = (key: string, blob: Blob) => tx('readwrite', (s) => s.put(blob, key))
export const getBlob = (key: string) => tx<Blob | undefined>('readonly', (s) => s.get(key))
export const deleteBlob = (key: string) => tx('readwrite', (s) => s.delete(key))
export const clearBlobs = () => tx('readwrite', (s) => s.clear())

const urls = new Map<string, string>()
export function useBlobUrl(key: string | undefined) {
  const [url, setUrl] = useState<string | null>(key ? (urls.get(key) ?? null) : null)
  useEffect(() => {
    if (!key) return
    if (urls.has(key)) return setUrl(urls.get(key)!)
    let live = true
    getBlob(key).then((b) => {
      if (!b || !live) return
      const u = URL.createObjectURL(b)
      urls.set(key, u)
      setUrl(u)
    })
    return () => {
      live = false
    }
  }, [key])
  return url
}

export async function downloadBlob(key: string, filename: string) {
  const b = await getBlob(key)
  if (!b) return
  const u = URL.createObjectURL(b)
  const a = document.createElement('a')
  a.href = u
  a.download = filename
  a.click()
  setTimeout(() => URL.revokeObjectURL(u), 2000)
}

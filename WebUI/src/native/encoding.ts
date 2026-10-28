export function base64(data: ArrayBuffer) {
  const bytes = new Uint8Array(data); let binary = ''
  for (let i = 0; i < bytes.length; i += 8192) binary += String.fromCharCode(...bytes.subarray(i, i + 8192))
  return btoa(binary)
}
export function unbase64(text: string): ArrayBuffer { return Uint8Array.from(atob(text), c => c.charCodeAt(0)).buffer }

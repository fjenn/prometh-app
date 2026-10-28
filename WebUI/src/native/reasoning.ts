/** Hide complete and partial reasoning tags, including tags split across SSE chunks. */
export function visibleText(raw: string): string {
  let text = raw.replace(/<think>[\s\S]*?(?:<\/think>|$)/gi, '')
  text = text.replace(/<\/?think>/gi, '')
  for (const tag of ['<think>', '</think>']) for (let i = 1; i < tag.length; i++) if (text.toLowerCase().endsWith(tag.slice(0, i))) return text.slice(0, -i).trimStart()
  return text.trimStart()
}

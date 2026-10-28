/** Incremental sentence boundaries; keep decimal points, abbreviations and unfinished words together. */
export function sentences(text: string, final = false): { ready: string[]; rest: string } {
  const ready: string[] = []
  let from = 0
  for (const match of text.matchAll(/[.!?]+["”’')\]]*(?=\s|$)/g)) {
    const end = match.index! + match[0].length
    const candidate = text.slice(from, end).trim()
    if (/\b(?:Mr|Mrs|Ms|Dr|Prof|St|vs|etc|e\.g|i\.e)\.$/i.test(candidate) || /\b[A-Z]\.$/.test(candidate)) continue
    if (candidate) ready.push(candidate)
    from = end
  }
  let rest = text.slice(from)
  // Bound first-chunk latency for long, unpunctuated answers at a word boundary.
  while (rest.length > 180) {
    const at = rest.lastIndexOf(' ', 180)
    if (at < 40) break
    ready.push(rest.slice(0, at).trim()); rest = rest.slice(at + 1)
  }
  if (final && rest.trim()) { ready.push(rest.trim()); rest = '' }
  return { ready, rest }
}

import { useState, type ReactNode } from 'react'

/**
 * Small markdown renderer that builds React elements (never raw HTML), so model
 * output can't inject markup. Covers what chat replies use: fenced code, headings,
 * lists, quotes, rules, tables, bold/italic/code/links, and <think> blocks.
 */
export function Markdown({ text, streaming }: { text: string; streaming?: boolean }) {
  const { think, body, thinking } = splitThink(text)
  return (
    <div className={streaming ? 'md streaming' : 'md'}>
      {think.trim() && (
        <details open={thinking}>
          <summary>{thinking ? 'Thinking…' : 'Thought process'}</summary>
          <div className="think">{think.trim()}</div>
        </details>
      )}
      {blocks(body)}
    </div>
  )
}

function splitThink(text: string) {
  // Reasoning models open their reply with <think>…</think>; anywhere else it's just text.
  const open = text.trimStart().startsWith('<think>') ? text.indexOf('<think>') : -1
  if (open === -1) return { think: '', body: text, thinking: false }
  const close = text.indexOf('</think>', open)
  if (close === -1) return { think: text.slice(open + 7), body: text.slice(0, open), thinking: true }
  return { think: text.slice(open + 7, close), body: text.slice(0, open) + text.slice(close + 8), thinking: false }
}

function CodeBlock({ code, lang }: { code: string; lang: string }) {
  const [copied, setCopied] = useState(false)
  return (
    <pre data-lang={lang || undefined}>
      <button
        className="btn btn-bordered copy"
        onClick={() => {
          navigator.clipboard.writeText(code)
          setCopied(true)
          setTimeout(() => setCopied(false), 1200)
        }}
      >
        {copied ? 'Copied' : 'Copy'}
      </button>
      <code>{code}</code>
    </pre>
  )
}

function blocks(src: string): ReactNode[] {
  const out: ReactNode[] = []
  const lines = src.replace(/\r\n/g, '\n').split('\n')
  let i = 0
  let key = 0
  while (i < lines.length) {
    const line = lines[i]
    const fence = line.match(/^\s*(```|~~~)\s*([\w+-]*)/)
    if (fence) {
      const buf: string[] = []
      i++
      while (i < lines.length && !lines[i].trim().startsWith(fence[1])) buf.push(lines[i++])
      i++
      out.push(<CodeBlock key={key++} code={buf.join('\n')} lang={fence[2]} />)
      continue
    }
    if (!line.trim()) {
      i++
      continue
    }
    const h = line.match(/^(#{1,4})\s+(.*)/)
    if (h) {
      const Tag = (`h${h[1].length}`) as 'h1'
      out.push(<Tag key={key++}>{inline(h[2])}</Tag>)
      i++
      continue
    }
    if (/^\s*([-*_])(\s*\1){2,}\s*$/.test(line)) {
      out.push(<hr key={key++} />)
      i++
      continue
    }
    if (/^\s*>/.test(line)) {
      const buf: string[] = []
      while (i < lines.length && /^\s*>/.test(lines[i])) buf.push(lines[i++].replace(/^\s*>\s?/, ''))
      out.push(<blockquote key={key++}>{blocks(buf.join('\n'))}</blockquote>)
      continue
    }
    if (/^\s*\|.*\|\s*$/.test(line) && i + 1 < lines.length && /^\s*\|?\s*:?-{2,}/.test(lines[i + 1])) {
      const row = (l: string) => l.trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim())
      const head = row(line)
      i += 2
      const rows: string[][] = []
      while (i < lines.length && /^\s*\|.*\|\s*$/.test(lines[i])) rows.push(row(lines[i++]))
      out.push(
        <table key={key++}>
          <thead>
            <tr>{head.map((c, j) => <th key={j}>{inline(c)}</th>)}</tr>
          </thead>
          <tbody>
            {rows.map((r, j) => (
              <tr key={j}>{r.map((c, k) => <td key={k}>{inline(c)}</td>)}</tr>
            ))}
          </tbody>
        </table>,
      )
      continue
    }
    const li = line.match(/^(\s*)([-*+]|\d+[.)])\s+(.*)/)
    if (li) {
      const ordered = /\d/.test(li[2])
      const items: string[] = []
      while (i < lines.length) {
        const m = lines[i].match(/^(\s*)([-*+]|\d+[.)])\s+(.*)/)
        if (m) {
          items.push(m[3])
          i++
        } else if (lines[i].trim() && /^\s{2,}/.test(lines[i]) && items.length) {
          items[items.length - 1] += '\n' + lines[i++].trim()
        } else break
      }
      const L = ordered ? 'ol' : 'ul'
      out.push(
        <L key={key++}>
          {items.map((t, j) => (
            <li key={j}>{inline(t)}</li>
          ))}
        </L>,
      )
      continue
    }
    const buf: string[] = []
    while (i < lines.length && lines[i].trim() && !/^(#{1,4}\s|\s*(```|~~~)|\s*>|\s*([-*+]|\d+[.)])\s)/.test(lines[i])) buf.push(lines[i++])
    if (!buf.length) buf.push(lines[i++])
    out.push(<p key={key++}>{inline(buf.join('\n'))}</p>)
  }
  return out
}

function inline(text: string): ReactNode[] {
  const out: ReactNode[] = []
  const re = /(`[^`]+`)|(\*\*[^*]+\*\*|__[^_]+__)|(\*[^*\s][^*]*\*|_[^_\s][^_]*_)|(\[[^\]]+\]\((https?:\/\/[^)\s]+)\))/g
  let last = 0
  let m: RegExpExecArray | null
  let k = 0
  while ((m = re.exec(text))) {
    if (m.index > last) out.push(text.slice(last, m.index))
    const t = m[0]
    if (m[1]) out.push(<code key={k++}>{t.slice(1, -1)}</code>)
    else if (m[2]) out.push(<strong key={k++}>{inline(t.slice(2, -2))}</strong>)
    else if (m[3]) out.push(<em key={k++}>{inline(t.slice(1, -1))}</em>)
    else if (m[4]) {
      const label = t.slice(1, t.indexOf(']('))
      out.push(
        <a key={k++} href={m[5]} target="_blank" rel="noopener noreferrer nofollow">
          {label}
        </a>,
      )
    }
    last = m.index + t.length
  }
  if (last < text.length) out.push(text.slice(last))
  return out
}

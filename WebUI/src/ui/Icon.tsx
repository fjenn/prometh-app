// Small stroke icon set (24px grid), drawn for Prometh.
const P: Record<string, string> = {
  plus: 'M12 5v14M5 12h14',
  x: 'M6 6l12 12M18 6L6 18',
  check: 'M5 12.5l4.5 4.5L19 7.5',
  up: 'M12 19V5M5.5 11.5L12 5l6.5 6.5',
  left: 'M19 12H5M11 5.5L4.5 12 11 18.5',
  chevDown: 'M6 9l6 6 6-6',
  chevRight: 'M9 6l6 6-6 6',
  mic: 'M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3zM5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21',
  sidebar: 'M4 5h16v14H4zM9.5 5v14',
  dots: 'M6 12h.01M12 12h.01M18 12h.01',
  search: 'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14zM20 20l-4-4',
  compose: 'M12 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-6M17.5 3.5a2.1 2.1 0 0 1 3 3L12 15l-4 1 1-4z',
  gear: 'M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6zM19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 0 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 0 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 0 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 0 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z',
  lock: 'M6 11h12v9H6zM8.5 11V8a3.5 3.5 0 0 1 7 0v3',
  sliders: 'M4 7h10M18 7h2M4 17h4M12 17h8M14 4.5v5M8 14.5v5',
  copy: 'M9 9h10v11H9zM5 15H4V4h11v1',
  refresh: 'M20 11a8 8 0 1 0-2.3 5.7M20 5v6h-6',
  speaker: 'M4 9.5h3.5L12 5v14l-4.5-4.5H4zM16 9a4 4 0 0 1 0 6M18.5 6.5a7.5 7.5 0 0 1 0 11',
  speakerOff: 'M4 9.5h3.5L12 5v14l-4.5-4.5H4zM16.5 9.5l5 5M21.5 9.5l-5 5',
  pause: 'M8 5v14M16 5v14',
  play: 'M7 4.5v15l12-7.5z',
  stop: 'M7 7h10v10H7z',
  clip: 'M20 11.5l-8.1 8.1a5 5 0 0 1-7.1-7.1l8.5-8.5a3.3 3.3 0 0 1 4.7 4.7l-8.5 8.5a1.7 1.7 0 0 1-2.4-2.4l7.8-7.8',
  image: 'M4 5h16v14H4zM4 16l4.5-4.5 4 4 2.5-2.5 5 5M15.5 9.5h.01',
  bubble: 'M5 18.5V6a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H8z',
  download: 'M12 4v11M6.5 10L12 15.5 17.5 10M5 20h14',
  bolt: 'M13 3L5 13.5h6L10.5 21 19 10h-6z',
  cpu: 'M7 7h10v10H7zM10 3v4M14 3v4M10 17v4M14 17v4M3 10h4M3 14h4M17 10h4M17 14h4',
  doc: 'M7 3h7l4 4v14H7zM14 3v4h4M9.5 12h5M9.5 16h5',
  trash: 'M5 7h14M10 7V4.5h4V7M7 7l1 13h8l1-13',
  pencil: 'M16.5 4.5a2.1 2.1 0 0 1 3 3L8 19l-4 1 1-4z',
  dotted: 'M12 3v.01M18.4 5.6v.01M21 12v.01M18.4 18.4v.01M12 21v.01M5.6 18.4v.01M3 12v.01M5.6 5.6v.01',
  logout: 'M15 4h4v16h-4M10 8l-4 4 4 4M6 12h10',
  wave: 'M4 12h.01M8 9v6M12 6v12M16 9v6M20 12h.01',
  film: 'M4 5h16v14H4zM8 5v14M16 5v14M4 9.5h4M4 14.5h4M16 9.5h4M16 14.5h4',
  external: 'M14 4h6v6M20 4l-9 9M18 14v6H4V6h6',
}

export function Icon({ name, size = 16, stroke = 1.7, className }: { name: keyof typeof P | string; size?: number; stroke?: number; className?: string }) {
  return (
    <svg className={className ?? 'icon'} width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={P[name] ?? ''} />
    </svg>
  )
}

export function IconButton({ icon, title, onClick, disabled, size = 15 }: { icon: string; title: string; onClick?: (e: React.MouseEvent<HTMLButtonElement>) => void; disabled?: boolean; size?: number }) {
  return (
    <button type="button" className="icon-btn" title={title} aria-label={title} onClick={onClick} disabled={disabled}>
      <Icon name={icon} size={size} />
    </button>
  )
}

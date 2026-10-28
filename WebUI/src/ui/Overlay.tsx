import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { ui, useUI } from '../state/store'
import { Icon } from './Icon'

/** Modal sheet. Escape and backdrop click close it. */
export function Sheet({ onClose, children, className = '', width, label }: { onClose: () => void; children: ReactNode; className?: string; width?: number; label: string }) {
  const ref = useRef<HTMLDivElement>(null)
  const close = useRef(onClose)
  close.current = onClose
  // Runs once per opening: focus the first field (unless something inside asked for focus), Escape closes.
  useEffect(() => {
    const prev = document.activeElement as HTMLElement | null
    if (!ref.current?.contains(document.activeElement)) ref.current?.querySelector<HTMLElement>('[autofocus], input, textarea, button:not([disabled])')?.focus()
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation()
        close.current()
      }
    }
    window.addEventListener('keydown', onKey)
    return () => {
      window.removeEventListener('keydown', onKey)
      prev?.focus?.()
    }
  }, [])
  return createPortal(
    <div className="backdrop" onMouseDown={(e) => e.target === e.currentTarget && close.current()}>
      <div ref={ref} className={`sheet ${className}`} style={width ? { width } : undefined} role="dialog" aria-modal="true" aria-label={label}>
        {children}
      </div>
    </div>,
    document.body,
  )
}

export interface MenuItem {
  label?: string
  onSelect?: () => void
  right?: string
  disabled?: boolean
  danger?: boolean
  divider?: boolean
  heading?: string
  icon?: string
}

/** A button that opens a small popover menu. */
export function MenuButton({ items, children, className, title, align = 'left', up = false }: { items: MenuItem[] | (() => MenuItem[]); children: ReactNode; className?: string; title: string; align?: 'left' | 'right'; up?: boolean }) {
  const [open, setOpen] = useState(false)
  const btn = useRef<HTMLButtonElement>(null)
  const menu = useRef<HTMLDivElement>(null)
  const [pos, setPos] = useState<{ left: number; top: number } | null>(null)
  const list = open ? (typeof items === 'function' ? items() : items) : []

  useLayoutEffect(() => {
    if (!open || !btn.current || !menu.current) return
    const r = btn.current.getBoundingClientRect()
    const m = menu.current.getBoundingClientRect()
    let left = align === 'right' ? r.right - m.width : r.left
    left = Math.max(8, Math.min(left, window.innerWidth - m.width - 8))
    let top = up ? r.top - m.height - 6 : r.bottom + 6
    if (top + m.height > window.innerHeight - 8) top = r.top - m.height - 6
    if (top < 8) top = 8
    setPos({ left, top })
  }, [open, align, up])

  useEffect(() => {
    if (!open) return
    const close = (e: MouseEvent) => {
      if (!menu.current?.contains(e.target as Node) && !btn.current?.contains(e.target as Node)) setOpen(false)
    }
    const key = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setOpen(false)
        btn.current?.focus()
      }
    }
    window.addEventListener('mousedown', close)
    window.addEventListener('keydown', key)
    return () => {
      window.removeEventListener('mousedown', close)
      window.removeEventListener('keydown', key)
    }
  }, [open])

  return (
    <>
      <button ref={btn} type="button" className={className} title={title} aria-label={title} aria-haspopup="menu" aria-expanded={open} onClick={() => { setPos(null); setOpen((o) => !o) }}>
        {children}
      </button>
      {open &&
        createPortal(
          <div ref={menu} className="menu" role="menu" style={pos ? { left: pos.left, top: pos.top } : { left: -9999, top: -9999 }}>
            {list.map((it, i) =>
              it.divider ? (
                <hr key={i} />
              ) : it.heading ? (
                <div key={i} className="lbl">
                  {it.heading}
                </div>
              ) : (
                <button
                  key={i}
                  role="menuitem"
                  type="button"
                  disabled={it.disabled}
                  className={it.danger ? 'danger' : undefined}
                  onClick={() => {
                    setOpen(false)
                    it.onSelect?.()
                  }}
                >
                  {it.icon && <Icon name={it.icon} size={15} />}
                  {it.label}
                  {it.right && <span className="r">{it.right}</span>}
                </button>
              ),
            )}
          </div>,
          document.body,
        )}
    </>
  )
}

export function Toast() {
  const error = useUI((s) => s.error)
  useEffect(() => {
    if (!error) return
    const t = setTimeout(() => ui.set({ error: null }), 9000)
    return () => clearTimeout(t)
  }, [error])
  if (!error) return null
  return (
    <div className="toast" role="alert">
      <span style={{ color: 'var(--warn)', display: 'grid' }}>
        <Icon name="bolt" />
      </span>
      <span className="grow">{error}</span>
      <button className="btn btn-plain" onClick={() => ui.set({ error: null })}>
        Dismiss
      </button>
    </div>
  )
}

export function Confirm({ title, body, action, onConfirm, onClose }: { title: string; body: string; action: string; onConfirm: () => void; onClose: () => void }) {
  return (
    <Sheet onClose={onClose} width={420} label={title}>
      <div className="sheet-pad">
        <h2 style={{ fontSize: 20 }}>{title}</h2>
        <p className="muted" style={{ lineHeight: 1.5, marginBottom: 0 }}>
          {body}
        </p>
        <div className="acts">
          <button className="btn btn-plain" onClick={onClose}>
            Cancel
          </button>
          <button
            className="btn btn-primary btn-coral"
            onClick={() => {
              onConfirm()
              onClose()
            }}
          >
            {action}
          </button>
        </div>
      </div>
    </Sheet>
  )
}

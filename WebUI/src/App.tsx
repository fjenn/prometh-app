import { useEffect } from 'react'
import { ui, useApp, useUI } from './state/store'
import { Onboarding, EvilReveal } from './ui/Onboarding'
import { Workspace } from './ui/Workspace'
import { Customize, Settings } from './ui/Settings'
import { ArtifactPreview, AttachmentPreview } from './ui/Media'
import { Sheet, Toast } from './ui/Overlay'
import { claimTab } from './startup'

function OtherTab() {
  return (
    <div className="ob">
      <div className="ob-world muted" />
      <div className="ob-shade muted" />
      <div className="ob-scroll">
        <div className="ob-col welcome" style={{ maxWidth: 640 }}>
          <h1 style={{ fontSize: 44, letterSpacing: -1.5 }}>Prometh is open in another tab.</h1>
          <div className="runs" style={{ margin: '0 0 28px' }}>
            Your AI runs in one tab at a time, so models aren’t loaded twice and chats don’t overwrite each other.
          </div>
          <button className="btn btn-welcome" onClick={() => claimTab(true)}>
            Use it here
          </button>
        </div>
      </div>
    </div>
  )
}

function useTheme() {
  const appearance = useApp((s) => s.appearance)
  const onboarding = useApp((s) => !s.onboardingComplete)
  useEffect(() => {
    const mq = window.matchMedia('(prefers-color-scheme: dark)')
    const apply = () => {
      const dark = appearance === 'Dark' || (appearance === 'System' && mq.matches)
      document.documentElement.dataset.theme = dark ? 'dark' : 'light'
    }
    apply()
    mq.addEventListener('change', apply)
    return () => mq.removeEventListener('change', apply)
  }, [appearance, onboarding])
}

export function App() {
  useTheme()
  const done = useApp((s) => s.onboardingComplete)
  const settings = useUI((s) => s.settingsOpen)
  const customize = useUI((s) => s.customizeOpen)
  const reveal = useUI((s) => s.revealInChat)
  const preview = useUI((s) => !!s.previewArtifact)
  const attachment = useUI((s) => !!s.previewAttachment)
  const otherTab = useUI((s) => s.otherTab)
  if (otherTab) return <OtherTab />
  return (
    <>
      {done ? <Workspace /> : <Onboarding />}
      {settings && <Settings />}
      {customize && <Customize />}
      {preview && <ArtifactPreview />}
      {attachment && <AttachmentPreview />}
      {reveal && (
        <Sheet onClose={() => ui.set({ revealInChat: false })} width={840} label="Evil Mode">
          <div style={{ position: 'relative', minHeight: 580, display: 'grid', placeItems: 'center', color: '#fff', overflow: 'hidden' }}>
            <div className="ob-world evil" />
            <div className="ob-shade evil" />
            <div style={{ position: 'relative', padding: 40 }}>
              <EvilReveal inChat />
            </div>
          </div>
        </Sheet>
      )}
      <Toast />
    </>
  )
}

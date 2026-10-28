export type Capability = 'chat' | 'voice' | 'images' | 'video'
export const CAPABILITIES: Capability[] = ['chat', 'voice', 'images', 'video']

/** A preparation job. 'evil' is the uncensored chat model, prepared only when Evil Mode is enabled. */
export type PrepKey = Capability | 'evil'

export type Mode = 'safe' | 'evil'
export type Appearance = 'Light' | 'Dark' | 'System'

export type PrepStatus = 'queued' | 'preparing' | 'downloading' | 'checking' | 'ready' | 'paused' | 'failed' | 'cancelled'
export interface Prep {
  progress: number
  status: PrepStatus
  /** Model id this preparation is for. A different id means it must be prepared again. */
  model?: string
  error?: string
}

export interface Attachment {
  id: string
  filename: string
  kind: 'text' | 'image'
  size: number
  /** Text content for text attachments (sent to the model). */
  text?: string
  /** IndexedDB key for image attachments. */
  blobKey?: string
}

export interface Artifact {
  id: string
  kind: 'image'
  blobKey: string
  prompt: string
  parentId?: string
  version: number
  width: number
  height: number
}

export type MessageStatus = 'complete' | 'streaming' | 'preparing' | 'stopped' | 'failed'
export interface Message {
  id: string
  role: 'user' | 'assistant'
  text: string
  status: MessageStatus
  attachments?: Attachment[]
  artifact?: Artifact
  jobKind?: 'image' | 'video'
  /** Image jobs: the prompt the image is made from (the chat model is told it, since it can't see images). */
  imagePrompt?: string
  /** For image edits: the artifact this response derives from. */
  sourceArtifact?: Artifact
  skills?: string[]
  /** Generation speed shown under the reply. */
  tps?: number
  /** Image: seconds it took, and how many of those went into loading the model. */
  took?: { total: number; load: number }
  voice?: boolean
}

export interface Conversation {
  id: string
  title: string
  mode: Mode
  messages: Message[]
  draft: string
  attachments: Attachment[]
  /** Next message creates an image. */
  imageMode?: boolean
  updated: number
}

export interface Skill {
  id: string
  name: string
  instructions: string
  enabled: boolean
}

export interface Snapshot {
  version: 1
  onboardingComplete: boolean
  step: number
  selected: Capability[]
  preps: Partial<Record<PrepKey, Prep>>
  evilEnabled: boolean
  /** Mode the first chat opens in after onboarding. */
  defaultMode: Mode
  appearance: Appearance
  readAttachments: boolean
  chats: Conversation[]
  selectedChatId: string | null
  skills: Skill[]
  /** Voice used for read-aloud and voice conversation. */
  voiceName: string
}

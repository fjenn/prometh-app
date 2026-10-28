import test from 'node:test'
import assert from 'node:assert/strict'
import { build } from 'vite'
import { createRequire } from 'node:module'
import vm from 'node:vm'
import path from 'node:path'

test('Settings Customize entry opens the shared modal and preserves working Plugins, Tools and Skills tabs', async () => {
  const result = await build({ configFile: path.resolve('vite.config.ts'), logLevel: 'silent', build: { ssr: path.resolve('test/fixtures/native-settings.ts'), write: false, emptyOutDir: false, rollupOptions: { output: { format: 'cjs' } } } })
  assert.ok(!Array.isArray(result) && 'output' in result)
  const chunk = result.output.find(item => item.type === 'chunk')
  assert.ok(chunk && chunk.type === 'chunk')
  const require = createRequire(import.meta.url)
  const module = { exports: {} as any }
  // Inspect the real component element trees without mounting a WebView or running effects.
  // Only the external-store hook needs a synchronous snapshot in this isolated renderer.
  const react = { ...require('react'), useSyncExternalStore: (_subscribe: unknown, snapshot: () => unknown) => snapshot() }
  vm.runInNewContext(chunk.code, {
    module, exports: module.exports, require: (id: string) => id === 'react' ? react : require(id),
    window: { addEventListener() {} }, navigator: {}, localStorage: { getItem: () => null },
    crypto, performance, URL, AbortController, AbortSignal, DOMException, clearTimeout, setTimeout,
  })
  const { Settings, Customize, ui } = module.exports
  const descendants = (element: any): any[] => !element || typeof element !== 'object' ? [] : [element, ...[element.props?.children].flat(Infinity).flatMap(descendants)]
  ui.set({ settingsOpen: true, customizeOpen: false, customizeSection: 'Skills' })
  const settings = Settings()
  assert.equal(settings.props.className, 'settings')
  const nav = descendants(settings).find(el => el.type === 'nav')
  assert.ok(nav)
  const entry = descendants(nav).find(el => el.type === 'button' && el.props.children === 'Customize')
  assert.ok(entry, 'Customize is inside the existing Settings nav')
  assert.equal(entry.props.style, undefined, 'uses the existing Settings nav CSS')
  entry.props.onClick()
  assert.equal(ui.get().settingsOpen, false)
  assert.equal(ui.get().customizeOpen, true)
  assert.equal(ui.get().customizeSection, 'Skills', 'keeps the same modal tab state as the sidebar')
  const contentTypes = new Set()
  for (const section of ['Plugins', 'Tools', 'Skills']) {
    const modal = Customize()
    assert.equal(modal.props.label, 'Customize')
    const tab = descendants(modal).find(el => el.props?.role === 'tab' && el.props.children === section)
    assert.ok(tab)
    tab.props.onClick()
    const selected = Customize()
    assert.equal(descendants(selected).find(el => el.props?.role === 'tab' && el.props.children === section).props['aria-selected'], true)
    const panel = selected.props.children.props.children.at(-1)
    contentTypes.add(panel.props.children.type)
  }
  assert.equal(contentTypes.size, 3, 'all three original content components remain selectable')
  Customize().props.onClose()
  assert.equal(ui.get().customizeOpen, false)
})

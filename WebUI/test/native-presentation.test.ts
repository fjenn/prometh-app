import test from 'node:test'
import assert from 'node:assert/strict'
import { sourceChipStyle, sourceRowStyle, extrasColumnStyle, connectedFirst, pluginInitial, httpsLogo, externalURL } from '../src/native/presentation.ts'
test('sources stretch across the message and truncate instead of wrapping or shrinking into narrow boxes', () => {
  assert.equal(extrasColumnStyle.width, '100%')
  assert.equal(extrasColumnStyle.alignSelf, 'stretch')
  assert.equal(sourceRowStyle.width, '100%')
  assert.equal(sourceRowStyle.flexWrap, 'wrap')
  assert.equal(sourceRowStyle.gap, 6)
  assert.equal(sourceChipStyle.whiteSpace, 'nowrap')
  assert.equal(sourceChipStyle.textOverflow, 'ellipsis')
  assert.equal(sourceChipStyle.textDecoration, 'none')
  assert.equal(sourceChipStyle.color, 'inherit')
  assert.equal(sourceChipStyle.maxWidth, 'min(260px, 100%)')
})
test('sources accept only external web URLs; logos require HTTPS and always have an initial fallback', () => {
  assert.equal(externalURL('https://example.com/article'), 'https://example.com/article')
  for (const raw of ['javascript:alert(1)', 'file:///etc/passwd', '/relative', 'https://user:pass@example.com']) assert.equal(externalURL(raw), null)
  assert.equal(httpsLogo('https://logos.composio.dev/api/github'), 'https://logos.composio.dev/api/github')
  assert.equal(httpsLogo('http://example.com/logo.png'), null)
  assert.equal(httpsLogo(''), null)
  assert.equal(pluginInitial(' Gmail'), 'G')
  assert.equal(pluginInitial(''), '?')
})
test('connected plugins precede other apps, sorted by name within groups, without mutating the catalog', () => {
  const items = [{ name: 'Airtable', status: 'disconnected' }, { name: 'Outlook', status: 'connected' }, { name: 'Gmail', status: 'connected' }]
  assert.deepEqual(connectedFirst(items).map(x => x.name), ['Gmail', 'Outlook', 'Airtable'])
  assert.equal(items[0].name, 'Airtable')
})

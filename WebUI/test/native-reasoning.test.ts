import test from 'node:test'
import assert from 'node:assert/strict'
import { visibleText } from '../src/native/reasoning.ts'
test('reasoning stays hidden until the answer, including partial tags', () => {
  for (const text of ['<', '<thi', '<think>', '<think>private reasoning', '<think>private reasoning</thi']) assert.equal(visibleText(text), '')
  assert.equal(visibleText('<think>private reasoning</think>\n\nHello'), 'Hello')
  assert.equal(visibleText('Hello <thi'), 'Hello ')
})
test('ordinary text, empty thinking, and multiple blocks', () => {
  assert.equal(visibleText('Hello world'), 'Hello world')
  assert.equal(visibleText('<think>\n</think>\nHi'), 'Hi')
  assert.equal(visibleText('<think>a</think>A<think>b</think>B'), 'AB')
})

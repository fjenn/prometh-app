// Run: npm test. Each signal is tested on its own with harmless prompts; the block rule is tested on signals.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { checkImagePrompt, decide, signals } from '../src/engine/prompt-gate.ts'

const MINOR = [
  'a 12 year old boy flying a kite',
  '12yo girl reading a book',
  'portrait, age: 14',
  'fifteen-year-old skateboarder',
  'school photo, born in 2015',
  'c h i l d drawing with crayons',
  'k1ds playing football',
  'сhild reading a book', // Cyrillic "с"
  'schoolgirl with a backpack',
  'meisje op de fiets',
  'niña jugando en el parque',
  '小学生の遠足',
  '(young:1.4), petite, pigtails, smiling',
  'teen at a skatepark',
  'toddler in a sandbox',
  'she is 13, birthday party',
]
const NOT_MINOR = [
  'portrait of a 25 year old woman',
  '18 years old man, studio photo',
  'adult woman at a cafe',
  'college student, 21, in a library',
  'young woman in her twenties',
  'elderly man with a cane',
  '1girl, solo, smiling',
  'born in 1990, portrait',
]
const SEXUAL = ['nude woman on a bed', 'n u d e portrait', 'topless man', 'naakt model', 'lingerie photoshoot', 'nud3 art', 'erotic photo']
const NOT_SEXUAL = ['a cocktail party in Middlesex', 'a peacock in the garden', 'Scunthorpe town hall', 'barely visible fog over a lake', 'young adult novel cover', 'a sunset over the sea']
const ALLOW = [
  'nude woman, 25 years old, on a bed',
  'topless man at the beach',
  'milf in lingerie',
  'young woman in her twenties, nude',
  'kids playing football in a park',
  'school portrait of a 9 year old',
  'baby in a crib',
  'family photo with children at the beach',
  'teenage mutant ninja turtles poster',
  'baby blue dress on a woman',
  'a cocktail party in Middlesex',
]

test('minor signal fires on ages, youth words, languages and spelling tricks', () => {
  for (const p of MINOR) assert.equal(signals(p).minor, true, p)
})
test('minor signal stays off for adults', () => {
  for (const p of NOT_MINOR) assert.equal(signals(p).minor, false, p)
})
test('sexual signal fires on adult sexual prompts', () => {
  for (const p of SEXUAL) assert.equal(signals(p).sexual, true, p)
})
test('sexual signal stays off for look-alike words', () => {
  for (const p of NOT_SEXUAL) assert.equal(signals(p).sexual, false, p)
})
test('block rule: hard term, or sexual together with a minor signal', () => {
  const s = { hard: false, sexual: false, minor: false, why: '' }
  assert.equal(decide({ ...s, hard: true }).allowed, false)
  assert.equal(decide({ ...s, sexual: true, minor: true }).allowed, false)
  assert.equal(decide({ ...s, sexual: true }).allowed, true)
  assert.equal(decide({ ...s, minor: true }).allowed, true)
})
test('hard terms block on their own', () => {
  for (const p of ['lolicon', 'jailbait', 'pedo']) assert.equal(checkImagePrompt(p).allowed, false, p)
})
test('normal adult, child and look-alike prompts pass', () => {
  for (const p of ALLOW) assert.equal(checkImagePrompt(p).allowed, true, p)
})

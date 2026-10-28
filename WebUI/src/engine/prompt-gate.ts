// Image prompt gate: no sexual images of minors, in any mode (research/H_image_csam_guard.md).
// Rule: block if HARD term, or (SEXUAL and (MINOR or underage number or >=2 WEAK youth cues)).
// The output check in the image worker is the backstop for whatever words miss.

const ZW = /[­͏؜ᅟᅠ឴឵᠎​-‏‪-‮⁠-⁯ㅤ︀-️﻿]/g
// Cyrillic/Greek look-alikes -> Latin.
const HOMO: Record<string, string> = { 'а': 'a', 'в': 'b', 'е': 'e', 'ё': 'e', 'к': 'k', 'м': 'm', 'н': 'h', 'о': 'o', 'р': 'p', 'с': 'c', 'т': 't', 'у': 'y', 'х': 'x', 'і': 'i', 'ї': 'i', 'ј': 'j', 'ѕ': 's', 'ԁ': 'd', 'ɡ': 'g', 'α': 'a', 'ε': 'e', 'ι': 'i', 'κ': 'k', 'ο': 'o', 'ρ': 'p', 'τ': 't', 'υ': 'u', 'ν': 'v' }
const LEET: Record<string, string> = { '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '@': 'a', '$': 's', '!': 'i', '|': 'l' }

// Harmless phrases that contain a minor word. Removed before matching.
const NEUTRAL = /\bbaby[\s-]?(?:oil|doll|blue|pink|shower|face cream)\b/g
function base(s: string): string {
  let t = s.normalize('NFKC').toLowerCase().replace(ZW, '')
  t = [...t].map((c) => HOMO[c] ?? c).join('')
  t = t.normalize('NFKD').replace(/[̀-ͯ]/g, '') // strip accents: niña -> nina
  // Join letters split by single separators: "c h i l d", "n.u.d.e", "k-i-d".
  t = t.replace(/\b[a-z]([\s.\-_*+~])(?:[a-z]\1){1,}[a-z]\b/g, (m) => ' ' + m.replace(/[\s.\-_*+~]/g, '') + ' ')
  return t.replace(NEUTRAL, ' ')
}
const leet = (t: string) => t.replace(/(?<=[a-z])[013457@$!|](?=[a-z]|\b)|\b[013457@$!|](?=[a-z])/g, (c) => LEET[c] ?? c)
const w = (list: string[]) => new RegExp(`(?:^|[^\\p{L}\\p{N}])(?:${list.join('|')})(?=$|[^\\p{L}\\p{N}])`, 'u')
const sub = (list: string[]) => new RegExp(list.join('|'), 'u') // for scripts without spaces (CJK) and emoji

const HARD = w(['lol[il]con', 'loli[s]?', 'lolita', 'shota(?:con)?', 'toddlercon', 'pedo(?:s|phile[s]?|philia|philic|bait)?', 'paedo(?:phile[s]?|philia)?', 'csam', 'jail ?bait', 'kinderporn\\w*', 'child ?porn\\w*', 'kidd(?:ie|y) ?porn\\w*', 'cp (?:link|vid|pic|image|download)\\w*'])
const HARD_CJK = sub(['ロリ', 'ショタ', '萝莉', '蘿莉', '正太', '幼女', '로리', '児童ポルノ', '儿童色情'])

const MINOR = w([
  'child(?:ren|s)?', 'chld', 'childlike', 'child-like', 'childish body', 'kid[sz]?', 'kiddo', 'kidd(?:ie|y)', 'toddler[s]?', 'infant[s]?', 'bab(?:y|ies)', 'newborn',
  'minor[s]?', 'under ?age(?:d)?', 'under-age(?:d)?', 'pre-?teen[s]?', 'pre teen[s]?', 'tween[s]?', 'teen[s]?', 'teenage[dr]?', 'teenagers', 'teeny', 'adolescen(?:t|ts|ce)',
  'juvenile[s]?', 'youngster[s]?', 'little ones?', 'preschool\\w*', 'pre-school\\w*', 'pubescent', 'prepubescent', 'pre-pubescent', 'underdeveloped', 'undeveloped', 'aged? down', 'babyface', 'baby face', 'child body', 'young[- ]looking body',
  'school ?(?:girl|boy|kid|child)[s]?', 'grade ?school(?:er)?', 'elementary(?: school)?', 'primary school', 'middle ?school(?:er)?', 'junior high', 'high ?school(?:er)?', 'kindergarten\\w*', 'nursery', 'daycare',
  '\\d{1,2}(?:st|nd|rd|th) grader?', '(?:first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth) grader?', 'year [1-9] (?:pupil|student)',
  '(?:little|lil|litle|young|small|tiny|baby|girl|boy) (?:girl|boy|child|kid)[s]?', 'girl child', 'boy child', 'daughter[s]?', 'step-?daughter[s]?', 'son[s]?', 'step-?son[s]?', 'niece', 'nephew',
  'jk', 'jc', 'js', // ja slang: high/middle/elementary school girl
  // other languages (accents already stripped)
  'kind(?:je|jes|eren)', 'meisje[s]?', 'jongetje', 'tiener[s]?', 'minderjarig\\w*', 'kleuter[s]?', // nl
  'kinder', 'madchen', 'jugendlich\\w*', 'minderjahrig\\w*', // de
  'enfant[s]?', 'fillette[s]?', 'petite fille', 'gamin[e]?[s]?', 'mineur[e]?[s]?', 'ado[s]?', // fr
  'nin[oa][s]?', 'nena[s]?', 'menor(?:es)?(?: de edad)?', 'crianca[s]?', 'menina[s]?', 'bambin[oaie]', 'ragazzin[aoie]', // es pt it
  'rebenok', 'devochka', 'shkolnitsa', 'malchik', // ru translit
  'ребенок', 'ребёнок', 'девочка', 'школьница', 'мальчик', 'несовершеннолетн\\p{L}*', 'подросток', // ru (after homoglyph map some letters become latin; matched below on raw too)
])
const MINOR_CJK = sub(['子供', '子ども', 'こども', '児童', '小学生', '中学生', '女子小学生', '女子中学生', '少女', '幼児', '儿童', '小孩', '女童', '男童', '未成年', '小学', '初中生', '아동', '어린이', '초등학생', '중학생', '미성년', '👶', '🧒', '👦', '👧', '🍼', '🎒', '🏫'])

const SEXUAL = w([
  'nud(?:e|es|ity|ist)', 'nood[s]?', 'naked', 'nekkid', 'nakey', 'nakie', 'undress\\w*', 'unclothed', 'disrobed', 'no clothes', 'without clothes', 'no clothing', 'clothes off', 'strip(?:ping|ped|per|pers|tease|club)',
  'nsfw', 'r-?18', 'xxx', '18\\+', 'porn\\w*', 'hentai', 'ecchi', 'lewd\\w*', 'erotic\\w*', 'sensual', 'explicit', 'uncensored', 'sex\\w*', 'seduc\\w*', 'provocative', 'aroused', 'horny', 'kink\\w*', 'fetish\\w*', 'bdsm', 'bondage',
  'topless', 'bottomless', 'nipple[s]?', 'areola[e]?', 'breast[s]?', 'boob[s]?', 'tits?', 'titties', 'cleavage', 'butt', 'ass', 'buttocks', 'crotch', 'groin', 'genital\\w*', 'penis', 'dick', 'cock', 'vagina\\w*', 'vulva', 'pussy', 'labia', 'clit\\w*', 'anus', 'anal',
  'cum(?:s|ming|med|shot|shots|slut)?', 'orgasm\\w*', 'masturbat\\w*', 'intercourse', 'fellatio', 'blowjob', 'handjob', 'penetrat\\w*', 'spread legs', 'legs spread', 'fuck\\w*', 'rape[ds]?', 'raping', 'molest\\w*', 'grope\\w*', 'groping',
  'lingerie', 'underwear', 'panties', 'panty', 'bra', 'thong', 'g-string', 'bikini', 'swimsuit', 'micro bikini', 'see-through', 'upskirt', 'downblouse', 'cameltoe', 'bath(?:ing|tub)?', 'shower(?:ing)?', 'wet t-?shirt', 'onlyfans',
  'naakt', 'bloot', 'nackt', 'nu[e]?[s]?', 'desnud[oa][s]?', 'nud[oa][s]?', 'sexo', 'sexe', 'голая', 'голый', 'секс', 'обнаж\\p{L}*',
])
const SEXUAL_CJK = sub(['裸', 'ヌード', 'エロ', 'セックス', '性交', '色情', '全裸', '露出', '下着', '水着', '알몸', '누드', '섹스', '야한', '🍆', '🍑', '💦', '🔞'])

// Weak youth cues: all SIZE words together count once, each CUE counts once. Two or more + sexual = block.
const SIZE = new RegExp(w(['petite', 'tiny', 'little', 'short stature', 'small body', 'tiny body', 'young', 'youthful']).source, 'u')
const CUE = new RegExp(w(['flat[- ]?chest(?:ed)?', 'innocent', 'pigtails', 'twin ?tails', 'braces', 'school uniform', 'sailor uniform', 'seifuku', 'randoseru', 'teddy bear', 'lollipop', 'chibi']).source, 'gu')
// Letters spelled out with spaces ("n u d e c h i l d") get joined into one run; scan runs unbounded.
const RUN_MINOR = /child|kid|teen|loli|shota|pedo|toddler|minor|underage|preteen|schoolgirl/
const RUN_SEX = /nude|naked|sex|porn|nsfw|topless|lewd|hentai/

// Ages 0-17 next to an age word, in several languages. Runs on text BEFORE leet mapping.
const NUM = '(?:0?\\d|1[0-7])'
const WORDNUM = '(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen)'
const AGE = new RegExp([
  `(?:^|[^\\p{L}\\p{N}])(?:${NUM}|${WORDNUM})\\s*[-‐]?\\s*(?:y\\.?\\s?o\\.?|yrs?|years?|yr?s?[- ]old|year[- ]old|jaar|jarige|jahre?|jahrige|ans?|anos|años|anni|let|лет|歳|才|세)(?![\\p{L}])`,
  `(?:^|[^\\p{L}\\p{N}])(?:age[ds]?|aged|leeftijd|alter|edad|idade|eta)\\s*[:=]?\\s*(?:${NUM}|${WORDNUM})(?![\\p{N}])`,
  `(?:under|below|younger than|less than|not yet|onder|unter|moins de)\\s*(?:the age of\\s*)?(?:18|eighteen|achttien|achtzehn|dix-huit)`,
  `(?:^|[^\\p{L}\\p{N}])(?:${NUM})\\s*(?:or|and)\\s*(?:younger|under)`,
  // Narrow bare-number forms: "girl (12)", "boy, 14,", "she is 13". Wider proximity rules blocked "1girl, solo, nsfw, 1boy".
  `(?:girl|boy|child|kid|daughter|son)\\s*[,(]\\s*(?:[1-9]|1[0-7])\\s*(?:[),]|$)`,
  `(?:she|he|who)\\s+(?:is|was|turned|just turned)\\s+(?:[1-9]|1[0-7])(?=\\s*(?:[,.;)]|$))`,
].join('|'), 'u')
/** "born in 2012", "born 2012": a birth year less than 18 years ago. */
const bornRecently = (t: string) => [...t.matchAll(/born\s*(?:in\s*)?(\d{4})/g)].some((m) => Number(m[1]) > new Date().getFullYear() - 18)

export interface Signals {
  hard: boolean
  sexual: boolean
  /** A minor word, an age under 18, or 2+ weak youth cues. */
  minor: boolean
  why: string
}

/** Each signal on its own, so they can be tested separately with harmless prompts. */
export function signals(prompt: string): Signals {
  const raw = prompt.normalize('NFKC').toLowerCase().replace(ZW, '').replace(NEUTRAL, ' ')
  const t = base(prompt)
  const variants = [t, leet(t)]
  const any = (re: RegExp) => variants.some((v) => re.test(v)) || re.test(raw)
  // Letters spelled out with separators ("c h i l d") form runs that are scanned without word boundaries.
  const runs = (raw.match(/\b[a-z0-9]([\s.\-_*+~])(?:[a-z0-9]\1){3,}[a-z0-9]\b/g) ?? []).map((m) => leet(m.replace(/[\s.\-_*+~]/g, ''))).join(' ')
  const cues = new Set(variants.flatMap((v) => v.match(CUE) ?? []).map((m) => m.replace(/^[^\p{L}]+/u, '')))
  const weak = cues.size + (variants.some((v) => SIZE.test(v)) ? 1 : 0)
  const minorWord = any(MINOR) || MINOR_CJK.test(raw) || RUN_MINOR.test(runs)
  const age = AGE.test(raw) || AGE.test(t) || bornRecently(raw)
  return {
    hard: any(HARD) || HARD_CJK.test(raw),
    sexual: any(SEXUAL) || SEXUAL_CJK.test(raw) || RUN_SEX.test(runs),
    minor: minorWord || age || weak >= 2,
    why: minorWord ? 'minor' : age ? 'age<18' : `weak x${weak}`,
  }
}

export type Verdict = { allowed: true } | { allowed: false; why: string }

export function decide(s: Signals): Verdict {
  if (s.hard) return { allowed: false, why: 'hard' }
  if (s.sexual && s.minor) return { allowed: false, why: `${s.why}+sexual` }
  return { allowed: true }
}

export const checkImagePrompt = (prompt: string) => decide(signals(prompt))

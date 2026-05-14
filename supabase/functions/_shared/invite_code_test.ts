import { assert } from 'jsr:@std/assert@1/assert'
import { assertEquals } from 'jsr:@std/assert@1/equals'
import {
  generateInviteCode,
  INVITE_CODE_CHARS,
  INVITE_CODE_LENGTH,
} from './invite_code.ts'

Deno.test('generateInviteCode: length and charset', () => {
  for (let i = 0; i < 100; i++) {
    const code = generateInviteCode()
    assertEquals(code.length, INVITE_CODE_LENGTH)
    for (const ch of code) {
      if (!INVITE_CODE_CHARS.includes(ch)) {
        throw new Error(`invalid char in invite code: ${ch}`)
      }
    }
  }
})

Deno.test('generateInviteCode: collision rate is low over small batch', () => {
  const set = new Set<string>()
  const n = 500
  for (let i = 0; i < n; i++) set.add(generateInviteCode())
  assert(
    set.size > n * 0.95,
    `expected >95% unique, got ${set.size}/${n}`,
  )
})

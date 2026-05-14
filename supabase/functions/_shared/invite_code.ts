/** Shared 6-char building invite codes (no ambiguous 0/O, 1/I). */

export const INVITE_CODE_LENGTH = 6
export const INVITE_CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'

export function generateInviteCode(): string {
  let code = ''
  for (let i = 0; i < INVITE_CODE_LENGTH; i++) {
    code += INVITE_CODE_CHARS[Math.floor(Math.random() * INVITE_CODE_CHARS.length)]
  }
  return code
}

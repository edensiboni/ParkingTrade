// Tiny assertion helpers with rich failure messages.
import type { EdgeResponse } from './supabase.js'

export class AssertionError extends Error {}

export function expect(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new AssertionError(msg)
}

export function eq<T>(actual: T, expected: T, msg: string): void {
  if (actual !== expected) {
    throw new AssertionError(`${msg}\n  expected: ${JSON.stringify(expected)}\n  actual:   ${JSON.stringify(actual)}`)
  }
}

export function expectStatus(res: EdgeResponse, expected: number, msg: string): void {
  if (res.status !== expected) {
    throw new AssertionError(
      `${msg}\n  expected HTTP ${expected}, got ${res.status}\n  body: ${JSON.stringify(res.body)}`,
    )
  }
}

/** Assert the edge call was rejected (any 4xx). */
export function expectClientError(res: EdgeResponse, msg: string): void {
  if (res.status < 400 || res.status >= 500) {
    throw new AssertionError(
      `${msg}\n  expected HTTP 4xx, got ${res.status}\n  body: ${JSON.stringify(res.body)}`,
    )
  }
}

/** Assert a supabase-js query result has no error. Returns data. */
export function ok<T>(result: { data: T; error: { message: string } | null }, msg: string): T {
  if (result.error) throw new AssertionError(`${msg}\n  supabase error: ${result.error.message}`)
  return result.data
}

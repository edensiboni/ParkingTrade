// Supabase client builders + raw Edge Function invocation.
import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import type { Cfg } from '../config.js'

const noPersist = { auth: { persistSession: false, autoRefreshToken: false } }

/** Service-role client — bypasses RLS. Setup/teardown/verification only. */
export function serviceClient(cfg: Cfg): SupabaseClient {
  return createClient(cfg.url, cfg.serviceKey, noPersist)
}

/** Anonymous client — for testing unauthenticated access. */
export function anonClient(cfg: Cfg): SupabaseClient {
  return createClient(cfg.url, cfg.anonKey, noPersist)
}

/** Client acting as a specific signed-in user (RLS enforced). */
export function userClient(cfg: Cfg, jwt: string): SupabaseClient {
  return createClient(cfg.url, cfg.anonKey, {
    ...noPersist,
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  })
}

export interface EdgeResponse {
  status: number
  body: any
}

/**
 * Invoke an Edge Function with full control over the Authorization header,
 * returning the raw HTTP status so tests can assert on 4xx/5xx precisely.
 */
export async function invokeEdge(
  cfg: Cfg,
  name: string,
  jwt: string | null,
  payload: unknown,
): Promise<EdgeResponse> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    apikey: cfg.anonKey,
  }
  if (jwt) headers.Authorization = `Bearer ${jwt}`
  const res = await fetch(`${cfg.url}/functions/v1/${name}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(payload),
  })
  let body: any = null
  const text = await res.text()
  try {
    body = text ? JSON.parse(text) : null
  } catch {
    body = text
  }
  return { status: res.status, body }
}

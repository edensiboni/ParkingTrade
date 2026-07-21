// Environment + CLI configuration for the E2E suite.
import { config as loadEnv } from 'dotenv'
import { randomBytes } from 'node:crypto'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))

// e2e/.env wins; the repo-root .env is a fallback (it has SUPABASE_URL/ANON_KEY).
loadEnv({ path: path.join(here, '..', '.env') })
loadEnv({ path: path.join(here, '..', '..', '.env') })

function pick(...names: string[]): string | undefined {
  for (const n of names) {
    const v = process.env[n]
    if (v && v.trim()) return v.trim()
  }
  return undefined
}

export interface Cfg {
  url: string
  anonKey: string
  serviceKey: string
  runId: string
  keepData: boolean
  only?: string
  bail: boolean
  verbose: boolean
}

function parseArgs(): { keepData: boolean; only?: string; bail: boolean; verbose: boolean } {
  const args = process.argv.slice(2)
  const get = (flag: string) => {
    const hit = args.find((a) => a.startsWith(`${flag}=`))
    return hit ? hit.split('=').slice(1).join('=') : undefined
  }
  return {
    keepData: args.includes('--keep-data'),
    only: get('--only'),
    bail: args.includes('--bail'),
    verbose: args.includes('--verbose') || args.includes('-v'),
  }
}

export function loadConfig(): Cfg {
  const url = pick('E2E_SUPABASE_URL', 'SUPABASE_URL')
  const anonKey = pick('E2E_SUPABASE_ANON_KEY', 'SUPABASE_ANON_KEY', 'SUPABASE_PUBLISHABLE_KEY')
  const serviceKey = pick('E2E_SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_SERVICE_ROLE_KEY')

  const missing: string[] = []
  if (!url) missing.push('E2E_SUPABASE_URL')
  if (!anonKey) missing.push('E2E_SUPABASE_ANON_KEY')
  if (!serviceKey) missing.push('E2E_SUPABASE_SERVICE_ROLE_KEY')
  if (missing.length) {
    console.error(
      `\n✖ Missing required env vars: ${missing.join(', ')}\n` +
        `  Copy e2e/.env.example to e2e/.env and fill in the values.\n` +
        `  (For a local stack: run \`supabase start\` — the example file already\n` +
        `   contains the local demo keys.)\n`,
    )
    process.exit(2)
  }

  const runId = `${Date.now().toString(36)}${randomBytes(2).toString('hex')}`
  return { url: url!, anonKey: anonKey!, serviceKey: serviceKey!, runId, ...parseArgs() }
}

/** Tag applied to every entity the suite creates, so cleanup can find it. */
export const E2E_TAG = 'E2E'
export const E2E_EMAIL_DOMAIN = 'e2e.parkingtrade.example.com'

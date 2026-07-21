// Standalone purge of ALL leftover E2E data (any run), identified by:
//   • buildings whose name starts with the E2E tag
//   • auth users whose email is under the reserved E2E domain
//
//   npm run cleanup
import { E2E_EMAIL_DOMAIN, E2E_TAG, loadConfig } from './config.js'
import { listAllUsers } from './lib/registry.js'
import { serviceClient } from './lib/supabase.js'

async function main() {
  const cfg = loadConfig()
  const svc = serviceClient(cfg)
  console.log(`Purging E2E data from ${cfg.url} …`)

  const { data: buildings } = await svc.from('buildings').select('id, name').like('name', `${E2E_TAG}•%`)

  // Before deleting buildings, collect auth users whose profile lives in an
  // E2E building (covers placeholder users created by admin-bulk-import that
  // have a phone but no E2E email).
  const orphanUserIds = new Set<string>()
  const buildingIds = (buildings ?? []).map((b) => b.id)
  if (buildingIds.length) {
    const { data: apts } = await svc.from('apartments').select('id').in('building_id', buildingIds)
    const aptIds = (apts ?? []).map((a) => a.id)
    if (aptIds.length) {
      const { data: profiles } = await svc.from('profiles').select('id').in('apartment_id', aptIds)
      for (const p of profiles ?? []) orphanUserIds.add(p.id)
    }
  }

  for (const b of buildings ?? []) {
    const { error } = await svc.from('buildings').delete().eq('id', b.id)
    console.log(error ? `  ✘ building ${b.name}: ${error.message}` : `  ✔ building ${b.name}`)
  }

  let users = 0
  for (const id of orphanUserIds) {
    const { error } = await svc.auth.admin.deleteUser(id)
    if (!error) users++
  }
  for await (const u of listAllUsers(svc)) {
    if (u.email?.endsWith(`@${E2E_EMAIL_DOMAIN}`)) {
      const { error } = await svc.auth.admin.deleteUser(u.id)
      if (!error) users++
      else console.log(`  ✘ user ${u.email}: ${error.message}`)
    }
  }
  console.log(`Done. ${buildings?.length ?? 0} buildings, ${users} auth users removed.`)
}

main().catch((e) => {
  console.error('Fatal:', e)
  process.exit(1)
})

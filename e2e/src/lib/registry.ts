// Tracks every resource the suite creates so cleanup is exact — even on failure.
import type { SupabaseClient } from '@supabase/supabase-js'
import { E2E_EMAIL_DOMAIN } from '../config.js'

export class Registry {
  readonly userIds = new Set<string>()
  readonly buildingIds = new Set<string>()
  readonly phones = new Set<string>() // E.164 with '+'; placeholder users created
  // indirectly (e.g. by admin-bulk-import) are found by phone at cleanup time.

  trackUser(id: string) {
    this.userIds.add(id)
  }
  trackBuilding(id: string) {
    this.buildingIds.add(id)
  }
  trackPhone(phone: string) {
    this.phones.add(phone)
  }

  /**
   * Deletes everything this run created.
   * Buildings cascade to apartments, authorized_apartments, parking_spots,
   * booking_requests, availability periods and messages. Deleting auth users
   * cascades to profiles.
   */
  async cleanup(svc: SupabaseClient): Promise<{ buildings: number; users: number }> {
    let buildings = 0
    let users = 0

    for (const id of this.buildingIds) {
      const { error } = await svc.from('buildings').delete().eq('id', id)
      if (!error) buildings++
      else console.error(`  cleanup: failed to delete building ${id}: ${error.message}`)
    }

    // Resolve placeholder auth users created indirectly, by phone.
    const wanted = new Set([...this.phones].map(normalizeForAuth))
    if (wanted.size > 0) {
      for await (const u of listAllUsers(svc)) {
        if (u.phone && wanted.has(normalizeForAuth(u.phone))) this.userIds.add(u.id)
        // Safety net: anything with our reserved e2e email domain belongs to a run.
        if (u.email && u.email.endsWith(`@${E2E_EMAIL_DOMAIN}`)) this.userIds.add(u.id)
      }
    }

    for (const id of this.userIds) {
      const { error } = await svc.auth.admin.deleteUser(id)
      if (!error) users++
      else console.error(`  cleanup: failed to delete user ${id}: ${error.message}`)
    }

    return { buildings, users }
  }
}

/** Supabase Auth stores phones without the leading '+'. */
export function normalizeForAuth(phone: string): string {
  return phone.replace(/^\+/, '')
}

export async function* listAllUsers(svc: SupabaseClient) {
  let page = 1
  for (;;) {
    const { data, error } = await svc.auth.admin.listUsers({ page, perPage: 1000 })
    if (error || !data?.users?.length) return
    yield* data.users
    if (data.users.length < 1000) return
    page++
  }
}

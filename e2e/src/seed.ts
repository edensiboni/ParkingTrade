// Demo-data seeder: builds a realistic, fully-wired building so the app can be
// explored by hand — residents, spots, availability windows, bookings in every
// state, and chat threads.
//
//   npm run seed                              one building, 8 apartments
//   npm run seed -- --buildings=2 --apartments=12 --keep-data
//
// Everything is tagged like the test suite, so `npm run cleanup` removes it.
import { loadConfig } from './config.js'
import { Factory, hoursFromNow, type UserCtx } from './lib/factory.js'
import { Registry } from './lib/registry.js'

const FIRST = ['Noa', 'Yossi', 'Maya', 'Avi', 'Tamar', 'Eitan', 'Shira', 'Omer', 'Lior', 'Dana', 'Gil', 'Rotem']
const LAST = ['Cohen', 'Levi', 'Mizrahi', 'Peretz', 'Biton', 'Friedman', 'Azulay', 'Katz']

function arg(name: string, fallback: number): number {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`))
  return hit ? Number(hit.split('=')[1]) || fallback : fallback
}

async function main() {
  const cfg = loadConfig()
  const registry = new Registry()
  const f = new Factory(cfg, registry)

  const nBuildings = arg('buildings', 1)
  const nApartments = arg('apartments', 8)

  console.log(`Seeding ${nBuildings} building(s) × ${nApartments} apartments on ${cfg.url}\n`)

  for (let bi = 1; bi <= nBuildings; bi++) {
    const b = await f.createBuilding(`Demo-${bi}`)
    console.log(`🏢 ${b.buildingName}`)
    console.log(`   admin: ${b.admin.email} / ${b.admin.password} (phone ${b.admin.phone})`)

    const residents: Array<{ user: UserCtx; apartmentId: string; spotId: string | null; unit: string }> = []

    for (let ai = 1; ai <= nApartments; ai++) {
      const unit = `${Math.ceil(ai / 4)}-${((ai - 1) % 4) + 1}` // floors of 4
      const name = `${FIRST[ai % FIRST.length]} ${LAST[ai % LAST.length]}`
      const phone = f.nextPhone()
      const hasSpot = ai % 3 !== 0 // two thirds of apartments own a spot
      await f.authorizeApartment(
        b.admin,
        b.buildingId,
        unit,
        [{ name, phone }],
        hasSpot ? [`P-${ai}`] : [],
      )
      const user = await f.residentFirstLogin(phone, `demo-${bi}-${ai}`)
      const apt = await f.getApartment(b.buildingId, unit)
      const spots = await f.getSpots(apt!.id)
      residents.push({ user, apartmentId: apt!.id, spotId: spots[0]?.id ?? null, unit })
      console.log(
        `   🏠 ${unit}  ${name}  ${phone}  ${spots.length ? `spot P-${ai}` : '(no spot)'}  login: ${user.email} / ${user.password}`,
      )
    }

    // Availability windows for every spot owner.
    const owners = residents.filter((r) => r.spotId)
    for (const o of owners) {
      await f.publishAvailability(o.user, o.spotId!, hoursFromNow(1), hoursFromNow(72))
    }
    console.log(`   📅 ${owners.length} availability windows published (next 72h)`)

    // Bookings in assorted states between non-owner borrowers and owners.
    const borrowers = residents.filter((r) => !r.spotId).concat(residents.filter((r) => r.spotId))
    let made = 0
    const states: Array<'pending' | 'approved' | 'rejected'> = ['pending', 'approved', 'rejected']
    for (let i = 0; i < Math.min(owners.length, 6); i++) {
      const owner = owners[i]
      const borrower = borrowers.find((r) => r.apartmentId !== owner.apartmentId)
      if (!borrower) continue
      const res = await f.requestBooking(
        borrower.user,
        owner.spotId!,
        hoursFromNow(2 + i * 8),
        hoursFromNow(6 + i * 8),
      )
      if (res.status !== 200) continue
      const id = res.body.booking.id
      const state = states[i % states.length]
      if (state !== 'pending') {
        await f.approveBooking(owner.user, id, state === 'approved' ? 'approve' : 'reject')
      }
      if (state === 'approved') {
        await f.sendChat(borrower.user, id, 'תודה! איפה בדיוק החניה?')
        await f.sendChat(owner.user, id, 'קומה -1, ליד המעלית 🙂')
      }
      made++
    }
    console.log(`   🚗 ${made} bookings created (pending/approved/rejected mix)\n`)
  }

  console.log('Done. Run `npm run cleanup` to remove all seeded data.')
}

main().catch((e) => {
  console.error('Fatal:', e)
  process.exit(1)
})

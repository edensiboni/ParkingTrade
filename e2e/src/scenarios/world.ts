// Shared world-builder: a building with N resident apartments, each with one
// logged-in resident and one parking spot. Used by the booking scenarios.
import type { BuildingCtx, Factory, UserCtx } from '../lib/factory.js'
import { expect } from '../lib/assert.js'

export interface ApartmentWorld {
  unit: string
  apartmentId: string
  resident: UserCtx
  spotId: string
  spotIdentifier: string
}

export interface World {
  building: BuildingCtx
  apartments: ApartmentWorld[]
}

export async function buildWorld(f: Factory, name: string, apartmentCount: number): Promise<World> {
  const building = await f.createBuilding(name)
  const apartments: ApartmentWorld[] = []
  for (let i = 1; i <= apartmentCount; i++) {
    const unit = `${name}-APT-${i}`
    const spotIdentifier = `${name}-SPOT-${i}`
    const phone = f.nextPhone()
    await f.authorizeApartment(
      building.admin,
      building.buildingId,
      unit,
      [{ name: `Resident ${i}`, phone }],
      [spotIdentifier],
    )
    const resident = await f.residentFirstLogin(phone, `res-${name}-${i}`)
    const apt = await f.getApartment(building.buildingId, unit)
    expect(apt, `apartment ${unit} was not materialised on login`)
    const spots = await f.getSpots(apt!.id)
    expect(spots.length === 1, `expected exactly one seeded spot for ${unit}`)
    apartments.push({ unit, apartmentId: apt!.id, resident, spotId: spots[0].id, spotIdentifier })
  }
  return { building, apartments }
}

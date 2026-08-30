// Factories for building the test "world": auth users, buildings, residents,
// apartments, spots, availability and bookings.
//
// Key technique — simulating phone/OTP login without SMS:
//   We create auth users via the Admin API with BOTH a confirmed phone and a
//   confirmed email+password. The INSERT into auth.users carries the phone, so
//   the magic-login trigger (migrations 014/020) fires exactly as it does for a
//   real OTP signup. We then sign in with email+password to get a genuine user
//   JWT for RLS-enforced API calls.
import type { SupabaseClient, User } from '@supabase/supabase-js'
import { randomBytes, randomInt } from 'node:crypto'
import type { Cfg } from '../config.js'
import { E2E_EMAIL_DOMAIN, E2E_TAG } from '../config.js'
import { Registry, listAllUsers, normalizeForAuth } from './registry.js'
import { anonClient, invokeEdge, serviceClient, userClient, type EdgeResponse } from './supabase.js'
import { AssertionError, expect, ok } from './assert.js'

export interface UserCtx {
  id: string
  email: string
  password: string
  phone?: string
  jwt: string
  client: SupabaseClient
}

export interface BuildingCtx {
  buildingId: string
  buildingName: string
  inviteCode: string
  adminApartmentId: string
  admin: UserCtx
}

export class Factory {
  readonly svc: SupabaseClient
  private seq = 0

  constructor(
    readonly cfg: Cfg,
    readonly registry: Registry,
  ) {
    this.svc = serviceClient(cfg)
  }

  // ── Identity helpers ───────────────────────────────────────────────────────

  nextEmail(label: string): string {
    return `${label.toLowerCase().replace(/[^a-z0-9]+/g, '-')}.${this.cfg.runId}.${this.seq++}@${E2E_EMAIL_DOMAIN}`
  }

  /** Random Israeli-format mobile number, unique per run. */
  nextPhone(): string {
    const phone = `+97250${randomInt(1_000_000, 9_999_999)}`
    if (this.registry.phones.has(phone)) return this.nextPhone()
    this.registry.trackPhone(phone)
    return phone
  }

  tag(name: string): string {
    return `${E2E_TAG}•${this.cfg.runId}•${name}`
  }

  // ── Auth users ─────────────────────────────────────────────────────────────

  /**
   * Create a confirmed auth user and sign in. If `phone` is provided, the
   * auth.users INSERT fires the magic-login trigger — i.e. this IS the
   * "first OTP login" event from the database's point of view.
   */
  async createAuthUser(opts: { label: string; phone?: string }): Promise<UserCtx> {
    const email = this.nextEmail(opts.label)
    const password = `E2e!${randomBytes(9).toString('base64url')}`
    const { data, error } = await this.svc.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      ...(opts.phone ? { phone: opts.phone, phone_confirm: true } : {}),
    })
    if (error || !data.user) {
      throw new AssertionError(`createAuthUser(${opts.label}) failed: ${error?.message}`)
    }
    this.registry.trackUser(data.user.id)
    if (opts.phone) this.registry.trackPhone(opts.phone)
    return this.signIn(data.user.id, email, password, opts.phone)
  }

  private async signIn(id: string, email: string, password: string, phone?: string): Promise<UserCtx> {
    const { data, error } = await anonClient(this.cfg).auth.signInWithPassword({ email, password })
    if (error || !data.session) throw new AssertionError(`signIn(${email}) failed: ${error?.message}`)
    const jwt = data.session.access_token
    return { id, email, password, phone, jwt, client: userClient(this.cfg, jwt) }
  }

  /** Find an auth user by phone (e.g. a placeholder created by bulk-import). */
  async findUserByPhone(phone: string): Promise<User | undefined> {
    const wanted = normalizeForAuth(phone)
    for await (const u of listAllUsers(this.svc)) {
      if (u.phone && normalizeForAuth(u.phone) === wanted) return u
    }
    return undefined
  }

  /**
   * "Log in" as a placeholder auth user that was created indirectly (e.g. by
   * admin-bulk-import). A real resident would OTP-login to that same auth row;
   * we attach email+password credentials to it instead, then sign in.
   */
  async activatePlaceholder(phone: string, label: string): Promise<UserCtx> {
    const user = await this.findUserByPhone(phone)
    expect(user, `no auth user exists for phone ${phone}`)
    this.registry.trackUser(user.id)
    const email = this.nextEmail(label)
    const password = `E2e!${randomBytes(9).toString('base64url')}`
    const { error } = await this.svc.auth.admin.updateUserById(user.id, {
      email,
      password,
      email_confirm: true,
    })
    if (error) throw new AssertionError(`activatePlaceholder(${phone}) failed: ${error.message}`)
    return this.signIn(user.id, email, password, phone)
  }

  // ── Buildings ──────────────────────────────────────────────────────────────

  /** Full admin onboarding: new auth user → create-building-admin edge fn. */
  async createBuilding(name: string): Promise<BuildingCtx> {
    const admin = await this.createAuthUser({ label: `admin-${name}`, phone: this.nextPhone() })
    const res = await this.edge('create-building-admin', admin, {
      building_name: this.tag(name),
      admin_display_name: this.tag(`Admin of ${name}`),
      address: '1 Test St, Tel Aviv',
    })
    if (res.status !== 201 || !res.body?.building_id) {
      throw new AssertionError(`create-building-admin failed (${res.status}): ${JSON.stringify(res.body)}`)
    }
    this.registry.trackBuilding(res.body.building_id)
    return {
      buildingId: res.body.building_id,
      buildingName: res.body.building_name,
      inviteCode: res.body.invite_code,
      adminApartmentId: res.body.apartment_id,
      admin,
    }
  }

  // ── Residents / apartments ─────────────────────────────────────────────────

  /**
   * Register an apartment + its authorised residents the way the admin
   * dashboard does: a direct RLS-enforced INSERT into authorized_apartments
   * using the admin's own JWT.
   */
  async authorizeApartment(
    by: UserCtx,
    buildingId: string,
    unit: string,
    residents: Array<{ name: string; phone: string }>,
    parkingSpots: string[] = [],
  ): Promise<string> {
    for (const r of residents) this.registry.trackPhone(r.phone)
    const row = ok(
      await by.client
        .from('authorized_apartments')
        .insert({
          building_id: buildingId,
          unit_number: unit,
          residents,
          parking_spot_identifiers: parkingSpots,
        })
        .select('id')
        .single(),
      `authorizeApartment(${unit}) insert failed`,
    )
    return (row as { id: string }).id
  }

  /** Simulate a resident's first OTP login (creates the auth.users row). */
  async residentFirstLogin(phone: string, label: string): Promise<UserCtx> {
    return this.createAuthUser({ label, phone })
  }

  async getProfile(userId: string): Promise<any | null> {
    const { data } = await this.svc
      .from('profiles')
      .select('id, phone, status, role, display_name, apartment_id, is_apartment_admin')
      .eq('id', userId)
      .maybeSingle()
    return data
  }

  async getApartment(buildingId: string, identifier: string): Promise<any | null> {
    const { data } = await this.svc
      .from('apartments')
      .select('id, building_id, identifier')
      .eq('building_id', buildingId)
      .eq('identifier', identifier)
      .maybeSingle()
    return data
  }

  async getSpots(apartmentId: string): Promise<any[]> {
    const { data } = await this.svc
      .from('parking_spots')
      .select('id, spot_identifier, apartment_id, building_id, is_active')
      .eq('apartment_id', apartmentId)
      .order('spot_identifier')
    return data ?? []
  }

  // ── Booking helpers ────────────────────────────────────────────────────────

  async publishAvailability(byUser: UserCtx, spotId: string, start: Date, end: Date): Promise<string> {
    const row = ok(
      await byUser.client
        .from('spot_availability_periods')
        .insert({ spot_id: spotId, start_time: start.toISOString(), end_time: end.toISOString() })
        .select('id')
        .single(),
      'publishAvailability insert failed',
    )
    return (row as { id: string }).id
  }

  async requestBooking(byUser: UserCtx, spotId: string, start: Date, end: Date): Promise<EdgeResponse> {
    return this.edge('create-booking-request', byUser, {
      spot_id: spotId,
      start_time: start.toISOString(),
      end_time: end.toISOString(),
    })
  }

  async approveBooking(byUser: UserCtx, bookingId: string, action: 'approve' | 'reject'): Promise<EdgeResponse> {
    return this.edge('approve-booking', byUser, { booking_id: bookingId, action })
  }

  async sendChat(byUser: UserCtx, bookingId: string, content: string): Promise<EdgeResponse> {
    return this.edge('send-chat-message', byUser, { booking_id: bookingId, content })
  }

  async getBooking(bookingId: string): Promise<any | null> {
    const { data } = await this.svc
      .from('booking_requests')
      .select('id, spot_id, borrower_apartment_id, lender_apartment_id, status, start_time, end_time')
      .eq('id', bookingId)
      .maybeSingle()
    return data
  }

  // ── Low-level ──────────────────────────────────────────────────────────────

  edge(name: string, as: UserCtx | null, payload: unknown): Promise<EdgeResponse> {
    return invokeEdge(this.cfg, name, as?.jwt ?? null, payload)
  }

  /**
   * Invoke an edge function with the service-role key, for machine-to-machine
   * functions that are called by pg_cron / database webhooks rather than by a
   * signed-in resident (e.g. notify-waitlist-match).
   */
  edgeAsService(name: string, payload: unknown): Promise<EdgeResponse> {
    return invokeEdge(this.cfg, name, this.cfg.serviceKey, payload)
  }
}

// ── Time helpers ─────────────────────────────────────────────────────────────

export function hoursFromNow(h: number): Date {
  return new Date(Date.now() + h * 3_600_000)
}

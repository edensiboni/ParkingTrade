// Scenario 12 — Chat coordination at match time (Roadmap 1.2):
//   chat works on a PENDING booking (before approval) → unread counts
//   reflect the other party's messages → mark_booking_read clears them →
//   a new message re-arms the badge → RLS: an outsider can neither read
//   the thread, see unread counts, nor mark the booking read.
import { scenario } from '../lib/runner.js'
import type { Factory } from '../lib/factory.js'
import { hoursFromNow } from '../lib/factory.js'
import { eq, expect, expectStatus, ok } from '../lib/assert.js'
import { buildWorld, type World } from './world.js'

type UnreadRow = { booking_id: string; unread_count: number }

export default (f: Factory) =>
  scenario('chat', 'Chat coordination — pending chat, unread counts, read receipts', async (t) => {
    let w: World
    await t.step('setup: building with 3 resident apartments + spots', async () => {
      w = await buildWorld(f, 'Chat', 3)
    })

    const lender = () => w.apartments[0]
    const borrower = () => w.apartments[1]
    const outsider = () => w.apartments[2]

    // Unread count for a given apartment's resident, for the booking under test.
    const unreadFor = async (apt: () => (typeof w.apartments)[0]): Promise<number> => {
      const rows = ok(
        await apt().resident.client.rpc('get_unread_message_counts'),
        'get_unread_message_counts should not error',
      ) as UnreadRow[]
      const row = rows.find((r) => r.booking_id === bookingId)
      return row ? Number(row.unread_count) : 0
    }

    let bookingId = ''
    await t.step('borrower requests the spot — booking is pending', async () => {
      await f.publishAvailability(lender().resident, lender().spotId, hoursFromNow(1), hoursFromNow(8))
      const res = await f.requestBooking(borrower().resident, lender().spotId, hoursFromNow(2), hoursFromNow(4))
      expectStatus(res, 200, 'booking request should succeed')
      bookingId = res.body?.booking?.id
      expect(bookingId, 'booking id missing from response')
      eq((await f.getBooking(bookingId))!.status, 'pending', 'fresh booking must be pending')
    })

    await t.step('chat is available BEFORE approval (pending booking)', async () => {
      const m1 = await f.sendChat(borrower().resident, bookingId, 'Hi! Can I grab the spot a bit early?')
      expectStatus(m1, 200, 'borrower should be able to chat on a pending booking')
      const m2 = await f.sendChat(lender().resident, bookingId, 'Sure — I will leave it open from 14:00.')
      expectStatus(m2, 200, 'lender should be able to chat on a pending booking')

      const msgs = ok(
        await lender().resident.client.from('messages').select('content').eq('booking_id', bookingId),
        'lender should read the pending-booking conversation',
      ) as Array<{ content: string }>
      eq(msgs.length, 2, 'both pending-booking messages should be visible')
    })

    await t.step('unread counts reflect the other party’s messages', async () => {
      // Each side sent one and received one; their own message is never counted.
      eq(await unreadFor(lender), 1, 'lender should have exactly one unread message')
      eq(await unreadFor(borrower), 1, 'borrower should have exactly one unread message')
    })

    await t.step('mark_booking_read clears the caller’s unread count', async () => {
      ok(
        await lender().resident.client.rpc('mark_booking_read', { p_booking_id: bookingId }),
        'lender should be able to mark the booking read',
      )
      eq(await unreadFor(lender), 0, 'lender unread should be cleared after mark_booking_read')
      // One participant reading must not affect the other's unread count.
      eq(await unreadFor(borrower), 1, 'borrower unread should be untouched by the lender’s read')
    })

    await t.step('a new message re-arms the unread badge', async () => {
      const m3 = await f.sendChat(borrower().resident, bookingId, 'Great, thank you!')
      expectStatus(m3, 200, 'follow-up borrower message should send')
      eq(await unreadFor(lender), 1, 'lender should have a fresh unread after a new message')
    })

    await t.step('RLS: an outsider cannot read the thread', async () => {
      const msgs = ok(
        await outsider().resident.client.from('messages').select('id').eq('booking_id', bookingId),
        'outsider select should not error',
      ) as unknown[]
      eq(msgs.length, 0, 'a non-participant must not see the conversation')
    })

    await t.step('RLS: an outsider sees no unread count for the booking', async () => {
      eq(await unreadFor(outsider), 0, 'a non-participant must not see unread counts for the booking')
    })

    await t.step('RLS: an outsider cannot mark the booking read', async () => {
      const { error } = await outsider().resident.client.rpc('mark_booking_read', { p_booking_id: bookingId })
      expect(error, 'mark_booking_read must reject a non-participant')
    })
  })

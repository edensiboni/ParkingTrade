// Pinned npm: specifier + Deno.serve keep us off esm.sh / deno.land/std,
// both of which have flaked during deploys (esm.sh 522, deno.land outages).
import { createClient } from 'npm:@supabase/supabase-js@2.45.4'
import { sendPushToUser } from '../_shared/push.ts'

const serve = Deno.serve

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser(token)

    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid or expired token' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { booking_id, content } = await req.json()

    if (!booking_id || !content) {
      return new Response(
        JSON.stringify({ error: 'booking_id and content are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { data: booking, error: bookingError } = await supabaseClient
      .from('booking_requests')
      .select('id, borrower_apartment_id, lender_apartment_id')
      .eq('id', booking_id)
      .single()

    if (bookingError || !booking) {
      return new Response(
        JSON.stringify({ error: 'Booking not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify the sender belongs to one of the booking's apartments.
    const { data: senderProfile, error: senderProfileError } = await supabaseClient
      .from('profiles')
      .select('apartment_id')
      .eq('id', user.id)
      .single()

    if (senderProfileError || !senderProfile) {
      return new Response(
        JSON.stringify({ error: 'Sender profile not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const senderApartmentId = senderProfile.apartment_id
    const isBorrower = senderApartmentId === booking.borrower_apartment_id
    const isLender = senderApartmentId === booking.lender_apartment_id

    if (!isBorrower && !isLender) {
      return new Response(
        JSON.stringify({ error: 'You are not a participant in this booking' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { data: message, error: insertError } = await supabaseClient
      .from('messages')
      .insert({
        booking_id,
        sender_id: user.id,
        content,
      })
      .select()
      .single()

    if (insertError) {
      return new Response(
        JSON.stringify({ error: 'Failed to send message', details: insertError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Notify opted-in members of the recipient apartment.
    const recipientApartmentId = isBorrower
      ? booking.lender_apartment_id
      : booking.borrower_apartment_id

    const { data: senderProfileForName } = await supabaseClient
      .from('profiles')
      .select('display_name')
      .eq('id', user.id)
      .single()

    const senderName = senderProfileForName?.display_name ?? 'Someone'
    const truncatedContent = content.length > 80 ? content.substring(0, 80) + '…' : content

    const { data: recipientProfiles } = await supabaseClient
      .from('profiles')
      .select('id, receives_chat_notifications')
      .eq('apartment_id', recipientApartmentId)
      .eq('status', 'approved')

    for (const recipient of (recipientProfiles ?? [])) {
      if (recipient.receives_chat_notifications) {
        await sendPushToUser(
          supabaseClient,
          recipient.id,
          `Message from ${senderName}`,
          truncatedContent,
          { type: 'chat_message', booking_id: booking.id },
        )
      }
    }

    return new Response(
      JSON.stringify({ success: true, message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

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
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Create Supabase client with service role key to bypass RLS
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false
        }
      }
    )

    // Get the authorization header
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get the user from the token
    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser(token)
    
    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid or expired token' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Parse request body
    const { booking_id, action } = await req.json()

    if (!booking_id || !action) {
      return new Response(
        JSON.stringify({ error: 'booking_id and action are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (action !== 'approve' && action !== 'reject') {
      return new Response(
        JSON.stringify({ error: 'action must be "approve" or "reject"' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get the booking request with spot and lender info
    const { data: booking, error: bookingError } = await supabaseClient
      .from('booking_requests')
      .select(`
        id,
        spot_id,
        borrower_id,
        lender_id,
        start_time,
        end_time,
        status,
        parking_spots!inner(resident_id)
      `)
      .eq('id', booking_id)
      .single()

    if (bookingError || !booking) {
      return new Response(
        JSON.stringify({ error: 'Booking request not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify the user is the lender (owner of the spot)
    if (booking.parking_spots.resident_id !== user.id) {
      return new Response(
        JSON.stringify({ error: 'Only the spot owner can approve/reject bookings' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify booking is in pending status
    if (booking.status !== 'pending') {
      return new Response(
        JSON.stringify({ error: `Cannot ${action} booking that is ${booking.status}` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Determine new status
    const newStatus = action === 'approve' ? 'approved' : 'rejected'

    // Update booking status
    // The exclusion constraint will automatically prevent overlapping approved bookings
    const { data: updatedBooking, error: updateError } = await supabaseClient
      .from('booking_requests')
      .update({ 
        status: newStatus,
        updated_at: new Date().toISOString()
      })
      .eq('id', booking_id)
      .select()
      .single()

    if (updateError) {
      // Check if it's a constraint violation (overlapping booking)
      if (updateError.code === '23505' || updateError.message.includes('duplicate key') || updateError.message.includes('overlap')) {
        return new Response(
          JSON.stringify({ error: 'This time slot overlaps with an existing approved booking' }),
          { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      
      return new Response(
        JSON.stringify({ error: 'Failed to update booking', details: updateError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (action === 'approve') {
      await sendPushToUser(
        supabaseClient,
        booking.borrower_id,
        'Booking approved',
        'Your parking spot request was approved.',
        { booking_id: booking_id, type: 'booking_approved' }
      )
    } else {
      await sendPushToUser(
        supabaseClient,
        booking.borrower_id,
        'Booking declined',
        'Your parking spot request was declined.',
        { booking_id: booking_id, type: 'booking_rejected' }
      )
    }

    return new Response(
      JSON.stringify({ 
        success: true,
        booking: updatedBooking
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})


import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { sendPushToUser } from '../_shared/fcm.ts'

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
    const { spot_id, start_time, end_time } = await req.json()

    if (!spot_id || !start_time || !end_time) {
      return new Response(
        JSON.stringify({ error: 'spot_id, start_time, and end_time are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate time range
    const start = new Date(start_time)
    const end = new Date(end_time)
    
    if (isNaN(start.getTime()) || isNaN(end.getTime())) {
      return new Response(
        JSON.stringify({ error: 'Invalid date format' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (end <= start) {
      return new Response(
        JSON.stringify({ error: 'end_time must be after start_time' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get borrower profile to check building membership
    const { data: borrowerProfile, error: borrowerError } = await supabaseClient
      .from('profiles')
      .select('id, building_id, status')
      .eq('id', user.id)
      .single()

    if (borrowerError || !borrowerProfile) {
      return new Response(
        JSON.stringify({ error: 'Borrower profile not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!borrowerProfile.building_id || borrowerProfile.status !== 'approved') {
      return new Response(
        JSON.stringify({ error: 'Borrower must be an approved member of a building' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get parking spot with owner info
    const { data: spot, error: spotError } = await supabaseClient
      .from('parking_spots')
      .select('id, resident_id, building_id, is_active')
      .eq('id', spot_id)
      .single()

    if (spotError || !spot) {
      return new Response(
        JSON.stringify({ error: 'Parking spot not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify spot is active
    if (!spot.is_active) {
      return new Response(
        JSON.stringify({ error: 'Parking spot is not active' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify borrower and lender are in the same building
    if (spot.building_id !== borrowerProfile.building_id) {
      return new Response(
        JSON.stringify({ error: 'Borrower and spot must be in the same building' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Prevent self-booking
    if (spot.resident_id === user.id) {
      return new Response(
        JSON.stringify({ error: 'Cannot request your own parking spot' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Create booking request
    const { data: bookingRequest, error: insertError } = await supabaseClient
      .from('booking_requests')
      .insert({
        spot_id: spot_id,
        borrower_id: user.id,
        lender_id: spot.resident_id,
        start_time: start_time,
        end_time: end_time,
        status: 'pending'
      })
      .select()
      .single()

    if (insertError) {
      return new Response(
        JSON.stringify({ error: 'Failed to create booking request', details: insertError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    await sendPushToUser(
      supabaseClient,
      spot.resident_id,
      'New booking request',
      'Someone requested your parking spot.',
      { booking_id: bookingRequest.id, type: 'booking_request' }
    )

    return new Response(
      JSON.stringify({ 
        success: true,
        booking: bookingRequest
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


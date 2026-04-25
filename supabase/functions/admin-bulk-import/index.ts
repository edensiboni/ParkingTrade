// admin-bulk-import Edge Function
// Allows a building admin to bulk-create apartments, profiles, and parking spots.
import { createClient } from 'npm:@supabase/supabase-js@2.45.4'

const serve = Deno.serve

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ImportItem {
  apartment_identifier: string
  phones?: string[]
  parking_spots?: string[]
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      }
    )

    // ── Auth ────────────────────────────────────────────────────
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

    // ── Verify caller is an approved building admin ──────────────
    const { data: adminProfile, error: adminError } = await supabaseClient
      .from('profiles')
      .select('id, role, status, apartment_id, apartments(building_id)')
      .eq('id', user.id)
      .single()

    if (adminError || !adminProfile) {
      return new Response(
        JSON.stringify({ error: 'Admin profile not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (adminProfile.role !== 'admin' || adminProfile.status !== 'approved') {
      return new Response(
        JSON.stringify({ error: 'Only approved building admins can perform bulk imports' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const adminBuildingId = (adminProfile.apartments as any)?.building_id
    if (!adminBuildingId) {
      return new Response(
        JSON.stringify({ error: 'Admin has no building assigned' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // ── Parse request body ───────────────────────────────────────
    const body = await req.json()
    if (!Array.isArray(body) || body.length === 0) {
      return new Response(
        JSON.stringify({ error: 'Request body must be a non-empty array of import items' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const items: ImportItem[] = body

    // Validate each item has at least an apartment_identifier
    for (const item of items) {
      if (!item.apartment_identifier || typeof item.apartment_identifier !== 'string') {
        return new Response(
          JSON.stringify({ error: 'Each item must have a string "apartment_identifier"' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    }

    // ── Process items ────────────────────────────────────────────
    const results: Array<{
      apartment_identifier: string
      apartment_id: string
      profiles_created: number
      spots_created: number
    }> = []
    const errors: Array<{ apartment_identifier: string; error: string }> = []

    for (const item of items) {
      try {
        // 1. Upsert the apartment (idempotent on building_id + identifier)
        const { data: apartment, error: aptError } = await supabaseClient
          .from('apartments')
          .upsert(
            {
              building_id: adminBuildingId,
              identifier: item.apartment_identifier.trim(),
            },
            { onConflict: 'building_id,identifier', ignoreDuplicates: false }
          )
          .select('id')
          .single()

        if (aptError || !apartment) {
          errors.push({
            apartment_identifier: item.apartment_identifier,
            error: aptError?.message ?? 'Failed to create apartment',
          })
          continue
        }

        const apartmentId = apartment.id
        let profilesCreated = 0
        let spotsCreated = 0

        // 2. Create profiles for each phone number
        const phones = item.phones ?? []
        for (const phone of phones) {
          if (!phone || typeof phone !== 'string') continue

          // We create a placeholder auth user so we have a UUID to link to profiles.
          // Using createUser with phone so Supabase Auth tracks the identity.
          // If the phone already has an auth user, we skip gracefully.
          const { data: authUser, error: createAuthError } =
            await supabaseClient.auth.admin.createUser({
              phone: phone.trim(),
              phone_confirm: true,
            })

          let profileUserId: string | null = null

          if (createAuthError) {
            // User might already exist — try to find by phone
            const { data: existingUsers } = await supabaseClient.auth.admin.listUsers()
            const existing = existingUsers?.users?.find(
              (u) => u.phone === phone.trim()
            )
            if (existing) {
              profileUserId = existing.id
            } else {
              // Cannot resolve user — skip this phone
              errors.push({
                apartment_identifier: item.apartment_identifier,
                error: `Could not create/find auth user for phone ${phone}: ${createAuthError.message}`,
              })
              continue
            }
          } else {
            profileUserId = authUser.user?.id ?? null
          }

          if (!profileUserId) continue

          // Upsert profile linked to the apartment
          const { error: profileError } = await supabaseClient
            .from('profiles')
            .upsert(
              {
                id: profileUserId,
                apartment_id: apartmentId,
                status: 'approved',
                updated_at: new Date().toISOString(),
              },
              { onConflict: 'id', ignoreDuplicates: false }
            )

          if (profileError) {
            errors.push({
              apartment_identifier: item.apartment_identifier,
              error: `Profile upsert failed for phone ${phone}: ${profileError.message}`,
            })
          } else {
            profilesCreated++
          }
        }

        // 3. Create parking spots linked to the apartment
        const spotIdentifiers = item.parking_spots ?? []
        for (const spotId of spotIdentifiers) {
          if (!spotId || typeof spotId !== 'string') continue

          const { error: spotError } = await supabaseClient
            .from('parking_spots')
            .upsert(
              {
                apartment_id: apartmentId,
                spot_identifier: spotId.trim(),
                is_active: true,
              },
              { onConflict: 'spot_identifier,apartment_id', ignoreDuplicates: true }
            )

          if (spotError) {
            errors.push({
              apartment_identifier: item.apartment_identifier,
              error: `Spot upsert failed for spot ${spotId}: ${spotError.message}`,
            })
          } else {
            spotsCreated++
          }
        }

        results.push({
          apartment_identifier: item.apartment_identifier,
          apartment_id: apartmentId,
          profiles_created: profilesCreated,
          spots_created: spotsCreated,
        })
      } catch (itemError) {
        errors.push({
          apartment_identifier: item.apartment_identifier,
          error: (itemError as Error).message,
        })
      }
    }

    const hasErrors = errors.length > 0
    const status = results.length === 0 ? 400 : hasErrors ? 207 : 200

    return new Response(
      JSON.stringify({
        success: results.length > 0,
        imported: results,
        errors: errors.length > 0 ? errors : undefined,
      }),
      { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

# Parking Spot Availability Feature

## Overview

Spot owners can now set specific time periods when their parking spots are available for booking. Other tenants can only book spots during these availability periods.

## How It Works

### For Spot Owners

1. **Go to "My Parking Spots"**
2. **Tap the calendar icon** on an active spot
3. **Add availability periods:**
   - Tap the "+" button
   - Select start date and time
   - Select end date and time
   - The period is saved
4. **Manage periods:**
   - View all your availability periods
   - Delete periods you no longer need

### For Tenants (Booking Spots)

1. **Go to "Request Spot"**
2. **Select start and end times** for your booking
3. **Available spots are automatically filtered:**
   - Only spots with availability periods that overlap with your requested time are shown
   - If a spot has no availability periods set, it's always available (backward compatible)

## Database Migration

**IMPORTANT:** You need to run the migration in Supabase:

1. Go to: https://supabase.com/dashboard/project/wdypfzsrpaqkhnyysjih/sql
2. Click "New query"
3. Copy and paste the contents of: `supabase/migrations/004_spot_availability_periods.sql`
4. Click "RUN"

## Features

- ✅ Spot owners can set multiple availability periods
- ✅ Spots without periods are always available (backward compatible)
- ✅ Booking requests are filtered by availability periods
- ✅ Real-time filtering when selecting booking times
- ✅ Easy management of availability periods

## Example Use Cases

1. **Weekend Availability:**
   - Owner sets availability: Saturday 9 AM - Sunday 6 PM
   - Others can only book during this time

2. **Work Hours:**
   - Owner sets availability: Monday-Friday 8 AM - 5 PM
   - Spot is available during work hours only

3. **Multiple Periods:**
   - Owner can set multiple periods
   - E.g., "Weekends" + "Holidays"

## Technical Details

- **Table:** `spot_availability_periods`
- **RLS Policies:** Spot owners can manage their periods, others can view
- **Filtering:** Booking service checks overlap between requested time and availability periods
- **Backward Compatible:** Spots without periods remain always available

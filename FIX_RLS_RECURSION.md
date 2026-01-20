# Fix RLS Infinite Recursion Error

## The Error
```
PostgrestException: infinite recursion detected in policy for relation "profiles"
```

## The Problem
The RLS policy on the `profiles` table was querying the `profiles` table within its own policy check, causing infinite recursion:

```sql
-- OLD (BROKEN) POLICY:
CREATE POLICY "Users can view profiles in their building" ON profiles
    FOR SELECT USING (
        building_id IN (SELECT building_id FROM profiles WHERE id = auth.uid())
    );
```

When checking if a user can view a profile, it queries `profiles` table, which triggers the same policy again → infinite loop.

## The Fix

I've created a migration file: `supabase/migrations/003_fix_rls_recursion.sql`

### Apply the Fix

1. **Go to Supabase SQL Editor:**
   - https://supabase.com/dashboard/project/wdypfzsrpaqkhnyysjih/sql

2. **Click "New query"**

3. **Copy and paste the contents of:**
   - `supabase/migrations/003_fix_rls_recursion.sql`

4. **Click "RUN"**

### What the Fix Does

1. **Drops the problematic policy**

2. **Creates a security definer function:**
   - `get_user_building_id()` - safely gets user's building_id without triggering RLS

3. **Creates new policies:**
   - Users can always read their own profile
   - Users can read profiles in their building (using the function to avoid recursion)

## After Applying the Fix

1. **Hot restart your app** (press `R` in terminal)
2. **Try joining building again** with invite code `TEST123`
3. **Should work now!** ✅

## Alternative: Quick Fix in SQL Editor

If you want to apply it directly, paste this in Supabase SQL Editor:

```sql
-- Drop problematic policy
DROP POLICY IF EXISTS "Users can view profiles in their building" ON profiles;

-- Create security definer function
CREATE OR REPLACE FUNCTION get_user_building_id(user_id UUID)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT building_id FROM profiles WHERE id = user_id;
$$;

-- Users can read their own profile
CREATE POLICY "Users can view their own profile" ON profiles
    FOR SELECT USING (id = auth.uid());

-- Users can read profiles in their building (using function to avoid recursion)
CREATE POLICY "Users can view profiles in their building" ON profiles
    FOR SELECT USING (
        building_id IS NOT NULL AND
        building_id = get_user_building_id(auth.uid())
    );
```

Then click "RUN" and test again!

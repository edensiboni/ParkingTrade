# How to Run Database Migrations in Supabase

## Important: Clear Your SQL Editor First!

The error you're seeing suggests there might be old SQL or error messages still in the editor. Follow these steps carefully:

## Step-by-Step Instructions

### 1. Open Supabase SQL Editor
- Go to your Supabase project dashboard
- Click on "SQL Editor" in the left sidebar
- **Clear any existing SQL** in the editor (select all and delete)

### 2. Run the First Migration

Copy the **ENTIRE** contents of `supabase/migrations/001_initial_schema.sql` and paste it into the SQL Editor.

**Important**: 
- Make sure you copy the ENTIRE file
- Don't copy any error messages
- Don't copy partial SQL
- The file should start with `-- Enable UUID extension` and end with `);`

Click "Run" (or press Cmd+Enter / Ctrl+Enter).

### 3. Verify Success

You should see:
- ✅ "Success. No rows returned"
- Or a message indicating the migration completed

### 4. Run the Second Migration

Clear the SQL Editor again, then copy the **ENTIRE** contents of `supabase/migrations/002_overlap_constraint.sql` and paste it.

Click "Run".

### 5. Create Test Building

After both migrations succeed, run this to create a test building:

```sql
INSERT INTO buildings (name, invite_code, approval_required)
VALUES ('Test Building', 'TEST123', false);
```

## Troubleshooting

### If you get "relation already exists" errors:
Some tables might already exist. You can either:
1. **Option A**: Drop everything and start fresh (for development):
   ```sql
   DROP TABLE IF EXISTS messages CASCADE;
   DROP TABLE IF EXISTS booking_requests CASCADE;
   DROP TABLE IF EXISTS parking_spots CASCADE;
   DROP TABLE IF EXISTS profiles CASCADE;
   DROP TABLE IF EXISTS buildings CASCADE;
   DROP TYPE IF EXISTS booking_status CASCADE;
   DROP TYPE IF EXISTS profile_status CASCADE;
   ```
   Then run the migrations again.

2. **Option B**: Run only the parts that are missing (more careful approach)

### If you get policy conflicts:
If policies already exist, drop them first:
```sql
DROP POLICY IF EXISTS "Users can view all buildings for joining" ON buildings;
DROP POLICY IF EXISTS "Users can view profiles in their building" ON profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON profiles;
DROP POLICY IF EXISTS "Users can insert their own profile" ON profiles;
-- ... (drop all policies, then recreate them)
```

### If you see the "OLD" error:
- Make sure you're using the updated `001_initial_schema.sql` file
- The file should NOT contain any `OLD.` references
- If you see `OLD.status` anywhere, you're using an old version

## Quick Verification

After running migrations, verify everything was created:

```sql
-- Check tables exist
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
ORDER BY table_name;

-- Should show: buildings, booking_requests, messages, parking_spots, profiles

-- Check policies exist
SELECT policyname, tablename 
FROM pg_policies 
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

-- Should show multiple policies for each table
```

## Alternative: Use Supabase CLI

If you prefer, you can use the Supabase CLI:

```bash
# Install Supabase CLI
npm install -g supabase

# Login
supabase login

# Link to your project
supabase link --project-ref your-project-ref

# Run migrations
supabase db push
```

This will automatically run all migrations in order.

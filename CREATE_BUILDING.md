# How to Create Test Building in Supabase

## Step-by-Step: Create Test Building

### Option 1: Using SQL Editor (Recommended)

1. **Open Supabase Dashboard**
   - Go to: https://supabase.com/dashboard
   - Select your project: `vxbsxhgzqblogekfeizr`

2. **Open SQL Editor**
   - In the left sidebar, click **"SQL Editor"** (icon looks like `</>`)
   - Or click: https://supabase.com/dashboard/project/vxbsxhgzqblogekfeizr/sql

3. **Create New Query**
   - Click the **"New query"** button (top right)
   - Or press `Cmd+N` (Mac) / `Ctrl+N` (Windows)

4. **Paste This SQL Code**
   ```sql
   INSERT INTO buildings (name, invite_code, approval_required)
   VALUES ('Test Building', 'TEST123', false);
   ```

5. **Run the Query**
   - Click the **"RUN"** button (green button, bottom right)
   - Or press `Cmd+Enter` (Mac) / `Ctrl+Enter` (Windows)

6. **Verify It Was Created**
   - You should see a success message: "Success. No rows returned"
   - To verify, run this query:
     ```sql
     SELECT * FROM buildings;
     ```
   - You should see a row with:
     - name: "Test Building"
     - invite_code: "TEST123"
     - approval_required: false

---

## Option 2: Using Table Editor (Alternative)

1. **Open Supabase Dashboard**
   - Go to: https://supabase.com/dashboard
   - Select your project

2. **Open Table Editor**
   - In the left sidebar, click **"Table Editor"**
   - Or navigate: https://supabase.com/dashboard/project/vxbsxhgzqblogekfeizr/editor

3. **Select `buildings` Table**
   - Click on the **`buildings`** table in the list
   - If you don't see it, make sure you ran the migrations first!

4. **Insert New Row**
   - Click the **"Insert"** button (or **"+"** button)
   - Fill in the form:
     - **name**: `Test Building`
     - **invite_code**: `TEST123`
     - **approval_required**: `false` (uncheck the box)
   - Click **"Save"**

---

## Quick Verification

After creating the building, verify it exists:

**Run this in SQL Editor:**
```sql
SELECT * FROM buildings;
```

You should see:
- A row with `invite_code = 'TEST123'`
- `name = 'Test Building'`
- `approval_required = false`

---

## What's Next?

After creating the test building:

1. ✅ Run the app with your credentials
2. ✅ Sign up with a phone number
3. ✅ Join building with code: `TEST123`
4. ✅ Start testing!

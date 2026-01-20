# What is the Invite Code?

## What It Is
The **invite code** is a unique code that allows users to join a specific building in the Parking Trade app. Each building has its own invite code.

## How It Works
1. **Building administrators** create buildings and set invite codes
2. **Residents** use the invite code to join their building
3. Once joined, residents can:
   - Add their parking spots
   - Request spots from other residents
   - Approve/reject booking requests
   - Chat with other residents

## For Testing: Create a Test Building

Since you're testing, you need to create a test building first:

### Step 1: Go to Supabase SQL Editor
1. Open: https://supabase.com/dashboard/project/wdypfzsrpaqkhnyysjih/sql
2. Click **"New query"**

### Step 2: Create Test Building
Paste this SQL and click **"RUN"**:

```sql
INSERT INTO buildings (name, invite_code, approval_required)
VALUES ('Test Building', 'TEST123', false);
```

This creates:
- **Building name**: "Test Building"
- **Invite code**: `TEST123`
- **Approval required**: `false` (anyone can join immediately)

### Step 3: Use the Invite Code
1. In your app, on the "Join Building" screen
2. Enter invite code: `TEST123`
3. Optionally add a display name
4. Tap "Join Building"
5. You'll be redirected to the parking spots screen

## Check if Building Exists

To verify if the building already exists:

1. **Supabase SQL Editor:**
   ```sql
   SELECT * FROM buildings;
   ```

2. **Look for:**
   - A building with invite_code = `TEST123`
   - If it exists, you can use it
   - If not, create it using the SQL above

## Creating Buildings with Approval

If you want a building that requires approval:

```sql
INSERT INTO buildings (name, invite_code, approval_required)
VALUES ('Approval Building', 'APPROVE123', true);
```

With `approval_required = true`:
- Users can join with the code
- But they'll be in "pending" status
- Need to wait for approval from building admin

## Multiple Buildings

You can create multiple buildings:

```sql
-- Building 1
INSERT INTO buildings (name, invite_code, approval_required)
VALUES ('Building A', 'BUILDINGA', false);

-- Building 2
INSERT INTO buildings (name, invite_code, approval_required)
VALUES ('Building B', 'BUILDINGB', false);
```

Each building is separate - users in Building A can't see spots from Building B.

## Quick Test

1. **Create test building** (SQL above)
2. **In app**: Enter `TEST123`
3. **Join building**
4. **Add parking spots**
5. **Start testing!**

# How to Create a Second Tenant Account for Testing

## Quick Steps

### Step 1: Sign Out from Current Account

1. **In the app**, go to any screen (Parking Spots, Bookings, etc.)
2. **Look for a menu/settings icon** (or we'll add a sign out button)
3. **Tap "Sign Out"**
4. You'll be redirected to the Sign In screen

### Step 2: Sign Up with New Phone Number

1. **Enter a different phone number** (must be different from your first account)
   - Example: If first account is `+972528916004`, use `+972528916005` or any other number
   - Format: `+[country code][number]` (e.g., `+972528916005`)

2. **Tap "Send OTP"**
3. **Enter the OTP code** you receive via SMS
4. **You'll be signed in** as a new user

### Step 3: Join the Same Building

1. **You'll see "Join Building" screen** (since you're a new user)
2. **Enter the same invite code** you used for the first account:
   - Example: `TEST123`
3. **Optionally add a display name** (e.g., "Tenant 2")
4. **Tap "Join Building"**

### Step 4: Test the Feature

Now you have two accounts in the same building:

1. **Account 1** (original):
   - Has parking spots
   - Can see Account 2's spots (if Account 2 adds any)
   - Can book Account 2's spots

2. **Account 2** (new):
   - Can see Account 1's spots
   - Can book Account 1's spots
   - Can add their own spots

## Testing Scenarios

### Scenario 1: See Each Other's Spots
1. **As Account 1**: Add a parking spot (e.g., "A-123")
2. **Sign out** and **Sign in as Account 2**
3. **Go to "Request Spot"** (via the car icon in top right)
4. **You should see Account 1's spot "A-123"** in the available spots list

### Scenario 2: Book Each Other's Spots
1. **As Account 1**: Add spot "A-123" and set availability period
2. **Sign out** and **Sign in as Account 2**
3. **Go to "Request Spot"**
4. **Select Account 1's spot "A-123"**
5. **Select booking time** (must overlap with availability period)
6. **Request the spot**
7. **Sign out** and **Sign in as Account 1**
8. **Go to "Bookings"** to see the pending request
9. **Approve or reject** the booking

## Important Notes

- **Different phone numbers required**: Each account needs a unique phone number
- **Same building**: Both accounts must join the same building (use same invite code)
- **Real phone numbers**: You need real phone numbers that can receive SMS OTP
- **Twilio trial**: If using Twilio trial account, make sure both numbers are verified

## Quick Test Setup

1. **Account 1**: `+972528916004` → Join building `TEST123` → Add spot "A-123"
2. **Account 2**: `+972528916005` (or any other number) → Join building `TEST123` → See Account 1's spots

## Troubleshooting

- **Can't see other's spots?** Make sure both accounts are in the same building
- **Can't sign out?** Check if there's a menu button, or we'll add a sign out button
- **OTP not received?** Check Twilio configuration and phone number format

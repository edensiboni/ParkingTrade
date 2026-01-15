# Testing Guide - Parking Trade App

## Pre-Testing Checklist

- [ ] Flutter dependencies installed (`flutter pub get`)
- [ ] Supabase project created and migrations run
- [ ] Test building created (invite code: TEST123)
- [ ] Supabase credentials configured
- [ ] Phone auth enabled in Supabase
- [ ] Edge Functions deployed (or testing without them)

## Manual Testing Scenarios

### 1. Authentication Flow

**Test Case 1.1: Phone Number Login**
1. Launch app
2. Enter phone number (format: +1234567890)
3. Tap "Send OTP"
4. **Expected**: OTP sent (check Supabase logs for code)
5. Enter OTP code
6. Tap "Verify OTP"
7. **Expected**: User authenticated, redirected to building join screen

**Test Case 1.2: Invalid OTP**
1. Enter phone number
2. Send OTP
3. Enter wrong OTP
4. **Expected**: Error message displayed

---

### 2. Building Join Flow

**Test Case 2.1: Join Building (No Approval Required)**
1. After authentication, enter invite code: `TEST123`
2. Optionally enter display name
3. Tap "Join Building"
4. **Expected**: Successfully joined, redirected to parking spots screen

**Test Case 2.2: Invalid Invite Code**
1. Enter invalid invite code (e.g., "INVALID")
2. Tap "Join Building"
3. **Expected**: Error message "Invalid invite code"

**Test Case 2.3: Join Building (Approval Required)**
1. Create building with `approval_required = true` in database
2. Join with invite code
3. **Expected**: Redirected to pending approval screen
4. **Expected**: Can check status or sign out

---

### 3. Parking Spot Management

**Test Case 3.1: Add Parking Spot**
1. On parking spots screen, tap "+" button
2. Enter spot identifier (e.g., "A-101")
3. Tap "Add Spot"
4. **Expected**: Spot appears in list, marked as active

**Test Case 3.2: Toggle Spot Active/Inactive**
1. Find a spot in the list
2. Toggle the switch
3. **Expected**: Spot status changes, switch reflects new state
4. **Expected**: Inactive spots don't appear in booking requests

**Test Case 3.3: Duplicate Spot Identifier**
1. Try to add a spot with the same identifier as existing spot
2. **Expected**: Error message (database constraint violation)

---

### 4. Booking Request Flow

**Setup**: Requires 2 users in the same building

**Test Case 4.1: Create Booking Request**
1. **User B**: Go to Bookings tab → "Request Spot" tab
2. Select a spot (owned by User A)
3. Select start time (future date/time)
4. Select end time (after start time)
5. Tap "Request Spot"
6. **Expected**: Request created, success message shown
7. **User A**: Go to Bookings tab → "Pending" tab
8. **Expected**: Request appears in pending list

**Test Case 4.2: Invalid Time Range**
1. Select end time before start time
2. **Expected**: Error message "end_time must be after start_time"

**Test Case 4.3: Request Own Spot**
1. Try to request a spot you own
2. **Expected**: Error message "Cannot request your own parking spot"

**Test Case 4.4: Request Spot in Different Building**
1. Create user in different building
2. Try to request spot from first building
3. **Expected**: Error message about building mismatch

---

### 5. Booking Approval Flow

**Test Case 5.1: Approve Booking Request**
1. **User A**: View pending request
2. Tap on request to open details
3. Tap "Approve" button
4. **Expected**: Request status changes to "approved"
5. **User B**: View active bookings
6. **Expected**: Approved booking appears in active list

**Test Case 5.2: Reject Booking Request**
1. **User A**: View pending request
2. Tap "Reject" button
3. **Expected**: Request status changes to "rejected"
4. **User B**: View bookings
5. **Expected**: Rejected booking appears (may be filtered out)

**Test Case 5.3: Unauthorized Approval**
1. **User C**: Try to approve booking for User A's spot
2. **Expected**: Error message "Only the spot owner can approve/reject"

**Test Case 5.4: Double-Booking Prevention**
1. **User A**: Approve booking for Spot X, Time 10am-12pm
2. **User B**: Create request for Spot X, Time 11am-1pm (overlaps)
3. **User A**: Try to approve second request
4. **Expected**: Error message "This time slot overlaps with an existing approved booking"
5. Database should prevent the overlap (exclusion constraint)

---

### 6. Booking Cancellation

**Test Case 6.1: Borrower Cancels Booking**
1. **User B**: View approved booking
2. Tap "Cancel Booking"
3. Confirm cancellation
4. **Expected**: Booking status changes to "cancelled"
5. **User A**: View bookings
6. **Expected**: Cancelled booking visible (may show as cancelled)

**Test Case 6.2: Lender Cancels Pending Request**
1. **User A**: View pending request
2. Cancel it
3. **Expected**: Request cancelled (if policy allows)

---

### 7. Real-time Chat

**Test Case 7.1: Send Message**
1. Open booking detail
2. Tap "Open Chat"
3. Type a message
4. Tap send button
5. **Expected**: Message appears in chat immediately

**Test Case 7.2: Real-time Updates**
1. **User A**: Open chat for a booking
2. **User B**: Send a message in the same chat
3. **Expected**: Message appears in User A's chat in real-time (without refresh)

**Test Case 7.3: Message History**
1. Close chat
2. Reopen chat for same booking
3. **Expected**: Previous messages are visible, ordered by timestamp

**Test Case 7.4: Chat Scoped to Booking**
1. **User A**: Open chat for Booking 1
2. **User B**: Send message in Booking 2
3. **Expected**: Message does NOT appear in User A's chat for Booking 1

---

### 8. Privacy Features

**Test Case 8.1: Phone Number Not Exposed**
1. **User A**: View another user's profile (if visible)
2. **Expected**: Phone number is NOT displayed
3. Check database directly
4. **Expected**: Phone numbers not in profiles table (only in auth.users)

**Test Case 8.2: Chat Uses User IDs**
1. Inspect chat messages in database
2. **Expected**: Messages reference sender_id (UUID), not phone numbers

---

### 9. Edge Cases

**Test Case 9.1: Network Errors**
1. Disconnect network
2. Try to create booking request
3. **Expected**: Appropriate error message

**Test Case 9.2: Expired Session**
1. Wait for session to expire (or manually expire)
2. Try to perform authenticated action
3. **Expected**: Redirected to login screen

**Test Case 9.3: Concurrent Booking Requests**
1. **User B** and **User C**: Both request same spot, same time
2. **User A**: Approve one
3. **User A**: Try to approve the other
4. **Expected**: Second approval fails (overlap prevention)

---

## Database Verification Queries

Run these in Supabase SQL Editor to verify data integrity:

```sql
-- Check all buildings
SELECT * FROM buildings;

-- Check user profiles
SELECT id, building_id, status, display_name, created_at 
FROM profiles;

-- Check parking spots
SELECT id, resident_id, building_id, spot_identifier, is_active 
FROM parking_spots;

-- Check booking requests
SELECT id, spot_id, borrower_id, lender_id, start_time, end_time, status 
FROM booking_requests 
ORDER BY created_at DESC;

-- Check for overlapping approved bookings (should return empty)
SELECT b1.id, b1.spot_id, b1.start_time, b1.end_time,
       b2.id, b2.start_time, b2.end_time
FROM booking_requests b1
JOIN booking_requests b2 
  ON b1.spot_id = b2.spot_id 
  AND b1.id < b2.id
  AND b1.status = 'approved' 
  AND b2.status = 'approved'
WHERE tstzrange(b1.start_time, b1.end_time) && tstzrange(b2.start_time, b2.end_time);

-- Check messages
SELECT id, booking_id, sender_id, content, created_at 
FROM messages 
ORDER BY booking_id, created_at;
```

## Performance Testing

1. **Load Testing**: Create 100+ booking requests, verify app performance
2. **Real-time Updates**: Have multiple users in same chat, verify no lag
3. **Database Queries**: Check query performance in Supabase dashboard

## Security Testing

1. **RLS Policies**: Try to access other users' data directly via API
2. **Edge Functions**: Verify authentication is required
3. **Input Validation**: Try SQL injection, XSS in text fields
4. **Authorization**: Try to approve bookings you don't own


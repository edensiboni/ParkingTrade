# ParkingTrade — Full Project Specification

## 1. Overview

**ParkingTrade** is a building-gated parking spot borrowing and sharing mobile application for residents of the same building.

The product is designed as a **closed, trust-based resident system**, not a public marketplace. Its main purpose is to allow neighbors to temporarily share unused parking spots in a structured, private, and convenient way.

The system currently supports:

- Phone OTP authentication
- Building join flow via invite code
- Optional building approval requirement
- Parking spot creation and management
- Spot availability windows
- Booking request and approval flow
- Booking-scoped private chat
- Database-level prevention of overlapping approved bookings

## 2. Product Goals

### 2.1 Primary Goals

- Only residents of the **same building** can view and borrow each other’s parking spots
- Spot owners control **when** their spot is available
- No two approved bookings can overlap for the same spot
- Borrower and lender can communicate through **in-app chat**
- Users do not need to expose personal phone numbers to one another
- The product should feel simple, local, and trust-based

### 2.2 Product Philosophy

ParkingTrade is intended to digitize the kind of informal resident coordination that already happens in building WhatsApp groups, such as:

- “Does anyone have a free parking spot for two hours?”
- “Yes, mine is free.”

The app formalizes that process with:

- resident-only access
- structured spot availability
- booking requests and approvals
- privacy-safe communication
- booking conflict prevention

## 3. Roles

### 3.1 Approved Tenant

A resident whose membership status is `approved`.

Capabilities:

- Add and manage their own parking spots
- Activate or deactivate their spots
- Set spot availability periods
- Browse available spots in their building
- Request bookings
- Approve or reject requests for their own spots
- Participate in booking chat

### 3.2 Pending Tenant

A resident whose membership status is `pending`.

Capabilities:

- Can sign in
- Has joined a building
- Cannot access normal building features until approved

### 3.3 Rejected Tenant

A resident whose membership status is `rejected`.

Capabilities:

- Cannot use building-related features

### 3.4 Building Admin

Currently **not implemented as a first-class in-app role**.

Current behavior implies that someone must be able to approve or reject pending users, but there is no formal admin UI yet. Approval is currently assumed to happen manually or through future tooling.

## 4. High-Level Architecture

### 4.1 Frontend

- Flutter
- Material 3 UI
- Service-based architecture
- Screens for authentication, onboarding, spots, bookings, and chat

### 4.2 Backend

- Supabase Auth for phone OTP authentication
- Supabase Postgres for relational data
- Supabase Row Level Security (RLS) for access control
- Supabase Realtime for live chat
- Supabase Edge Functions for validated server-side flows

### 4.3 Supporting Integrations

- Firebase Core
- Firebase Messaging
- flutter_local_notifications

### 4.4 Runtime Configuration

The app expects:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

These are typically provided using `--dart-define`.

## 5. Core Domain Model

### 5.1 Buildings

Represents a single residential building or resident network.

**Fields:**

- `id`
- `name`
- `invite_code`
- `approval_required`
- `created_at`

**Purpose:**

- Defines the trust boundary
- Gates membership
- Determines whether new users are auto-approved or pending

### 5.2 Profiles

Represents the app-level resident profile and membership state.

**Fields:**

- `id` (references `auth.users.id`)
- `building_id`
- `status`
- `display_name`
- `created_at`
- `updated_at`

**Purpose:**

- Connects authentication identity to building membership
- Controls onboarding state
- Controls access to the product

### 5.3 Parking Spots

Represents a parking spot owned by a resident.

**Fields:**

- `id`
- `resident_id`
- `building_id`
- `spot_identifier`
- `is_active`
- `created_at`

**Rules:**

- Belongs to one owner
- Belongs to one building
- `spot_identifier` must be unique within a building
- Inactive spots cannot be requested

### 5.4 Booking Requests

Represents a borrower requesting to use a parking spot during a time range.

**Fields:**

- `id`
- `spot_id`
- `borrower_id`
- `lender_id`
- `start_time`
- `end_time`
- `status`
- `created_at`
- `updated_at`

**Purpose:**

- Tracks the full booking request lifecycle
- Preserves borrower and lender roles
- Supports approvals, rejection, cancellation, and completion

### 5.5 Messages

Represents chat messages associated with a specific booking.

**Fields:**

- `id`
- `booking_id`
- `sender_id`
- `content`
- `created_at`

**Purpose:**

- Enables coordination between borrower and lender
- Keeps communication contextual and private

### 5.6 Spot Availability Periods

Represents the time windows during which a spot may be available.

**Fields:**

- `id`
- `spot_id`
- `start_time`
- `end_time`
- `is_recurring`
- `recurring_pattern`
- `created_at`

**Purpose:**

- Allows owners to define when their spot is available
- Supports future recurring schedules

**Important Rule:**

- If a spot has no availability periods, it is treated as **always available**

## 6. Enums

### 6.1 `profile_status`

- `pending`
- `approved`
- `rejected`

### 6.2 `booking_status`

- `pending`
- `approved`
- `rejected`
- `cancelled`
- `completed`

## 7. User Flows

### 7.1 Authentication and Routing

#### Authentication

Users sign in using **phone OTP** through Supabase Auth.

**Flow:**

1. User enters phone number
2. OTP is sent
3. User enters OTP
4. Auth session is created

#### Post-Authentication Routing

After login, the app checks the user’s profile and routes accordingly:

- No profile -> `JoinBuildingScreen`
- Profile exists but has no building -> `JoinBuildingScreen`
- Profile status is `pending` -> `PendingApprovalScreen`
- Profile status is `approved` -> `ParkingSpotsScreen`

This means the app is gated behind:

1. authentication
2. building membership
3. approval state

### 7.2 Join Building

Users join a building via **invite code**.

**Inputs:**

- `invite_code`
- optional `display_name`

**Behavior:**

- Look up building by invite code
- Assign building to the user profile
- Set status:
  - `approved` if approval is not required
  - `pending` if approval is required
- Store optional display name

**Important Rule:**

- A user should not be able to switch between buildings freely once already attached to one

### 7.3 Pending Approval

Users who joined a building that requires approval are routed to `PendingApprovalScreen`.

**Current behavior:**

- User is informed their account is awaiting approval
- User can refresh status
- User can sign out

**Current limitation:**

- No admin approval UI is implemented yet

### 7.4 Add and Manage Parking Spots

Approved users land on `ParkingSpotsScreen`, which acts as the home screen.

**Capabilities:**

- View owned spots
- Add a new spot
- Toggle spot active/inactive
- Manage availability windows
- Navigate to bookings-related areas

#### Add Spot

Users enter a human-readable parking spot identifier, for example:

- `A-123`
- `Level 2 - Spot 45`

**Rules:**

- Spot belongs to one user
- Spot belongs to one building
- Identifier must be unique within that building
- Inactive spots are not requestable

### 7.5 Manage Availability

Availability is managed per spot using `ManageAvailabilityScreen`.

**Capabilities:**

- Add availability periods
- View availability periods
- Delete availability periods

#### Current Rules

A spot is considered available if:

1. `is_active = true`
2. and either:
   - it has no availability periods
   - or the requested time overlaps an availability period

#### Current Limitation

The schema supports recurrence using:

- `is_recurring`
- `recurring_pattern`

However, the current UI and service logic treat availability as non-recurring time ranges only.

### 7.6 Discover Spots and Request Booking

There are two conceptual booking discovery patterns reflected in the project.

#### Time-First Request Flow

Screen: `RequestSpotScreen`

**Flow:**

1. User selects start and end time
2. App loads available spots for that range
3. User selects a spot
4. User submits a booking request

#### Marketplace-Style Spot Discovery

A marketplace-style spot list may also exist depending on the current implementation branch.

**Flow:**

1. User sees spots that have upcoming availability
2. User chooses a spot
3. User selects an available booking slot
4. User submits a booking request

#### Booking Request Rules

A booking request may be created only if:

- Borrower has a profile
- Borrower belongs to a building
- Borrower is approved
- Spot is active
- Borrower and spot belong to the same building
- Borrower is not requesting their own spot
- Requested time range is valid

#### Blocking Logic

Availability calculations currently treat **approved and pending bookings** as blocking in some app-level slot computations.

However, the hard database guarantee only applies to **approved bookings**.

### 7.7 Approve or Reject Booking

Spot owners can review incoming requests and approve or reject them.

**Input:**

- `booking_id`
- `action = approve | reject`

**Rules:**

- Only the spot owner can approve or reject
- Booking must still be `pending`

**Outcomes:**

- Approve -> booking status becomes `approved`
- Reject -> booking status becomes `rejected`

### 7.8 Booking Chat

Each booking may have a private chat between borrower and lender.

**Behavior:**

- Messages are tied to `booking_id`
- Only borrower and lender may read or send messages
- Messages update in realtime using Supabase Realtime

**Purpose:**

- Coordinate arrival
- Clarify details
- Handle last-minute communication
- Avoid sharing phone numbers

## 8. Business Rules

### 8.1 Building Gating

The system is fundamentally building-gated.

**Rules:**

- Users should only see relevant data from their building
- Building membership defines the trust boundary
- Booking and chat visibility is narrower than building visibility

#### Access Expectations

- Spots: visible within same building
- Profiles: visible within same building
- Bookings: visible only to borrower or lender
- Messages: visible only to borrower or lender
- Only approved members may create booking requests

### 8.2 Availability Rules

A spot is bookable if:

1. The spot is active
2. And either:
   - it has no availability periods
   - or the request overlaps at least one availability period
3. And the request does not conflict with blocking bookings according to app logic

#### Backward Compatibility Rule

If a spot has no availability periods, it is considered always available.

### 8.3 Double-Booking Prevention

Two **approved** bookings for the same spot must never overlap.

This is enforced at the **database level** using a Postgres exclusion constraint on:

- `spot_id`
- overlapping `tstzrange(start_time, end_time)`
- filtered to rows where `status = 'approved'`

#### Why This Matters

Even if:

- app logic fails
- multiple approvals happen concurrently
- race conditions occur

the database still prevents invalid overlapping approved bookings.

This is the strongest correctness guarantee in the system.

### 8.4 Privacy Rules

The system intentionally avoids exposing phone numbers to other residents.

**Privacy model:**

- Phone number is used only for authentication
- Users interact via profile display names
- Coordination happens in booking-scoped chat
- Users do not need to exchange personal contact details

### 8.5 Time Handling

Booking and availability logic must preserve intended local wall-clock meaning.

**Requirements:**

- Time comparisons must be normalized consistently
- Availability and bookings must behave predictably across devices and timezones
- Backend checks must remain deterministic

## 9. Database Schema Summary

### 9.1 `buildings`

**Fields:**

- `id`
- `name`
- `invite_code`
- `approval_required`
- `created_at`

### 9.2 `profiles`

**Fields:**

- `id`
- `building_id`
- `status`
- `display_name`
- `created_at`
- `updated_at`

**Relationship:**

- One profile per authenticated user

### 9.3 `parking_spots`

**Fields:**

- `id`
- `resident_id`
- `building_id`
- `spot_identifier`
- `is_active`
- `created_at`

**Constraint:**

- Unique `(building_id, spot_identifier)`

### 9.4 `booking_requests`

**Fields:**

- `id`
- `spot_id`
- `borrower_id`
- `lender_id`
- `start_time`
- `end_time`
- `status`
- `created_at`
- `updated_at`

**Validation:**

- `end_time > start_time`

**Constraint:**

- Exclusion constraint preventing overlapping approved bookings for the same spot

### 9.5 `messages`

**Fields:**

- `id`
- `booking_id`
- `sender_id`
- `content`
- `created_at`

### 9.6 `spot_availability_periods`

**Fields:**

- `id`
- `spot_id`
- `start_time`
- `end_time`
- `is_recurring`
- `recurring_pattern`
- `created_at`

## 10. Security and RLS Model

The backend relies heavily on **Row Level Security (RLS)**.

### 10.1 Buildings

**Policy intent:**

- Readable broadly enough to support joining by invite code

### 10.2 Profiles

**Policy intent:**

- User can insert and update their own profile
- Profiles are readable within the same building

### 10.3 Parking Spots

**Policy intent:**

- Building members can read spots in their building
- Only owners can insert, update, or delete their spots

### 10.4 Booking Requests

**Policy intent:**

- Only borrower and lender can read a booking
- Borrower can create booking requests
- Lender can update requests for approval or rejection
- Borrower may update bookings for cancellation flows

### 10.5 Messages

**Policy intent:**

- Only the booking participants can read or send messages

### 10.6 Spot Availability Periods

**Policy intent:**

- Spot owner manages availability periods
- Building members can read availability data

### Important Security Note

The project includes a fix for RLS recursion in profile policies using a helper function to safely resolve the user’s building.

## 11. Backend APIs / Edge Functions

### 11.1 `join-building`

**Purpose:**

Attach an authenticated user to a building.

**Auth:**

- Requires authenticated user JWT

**Input:**

```json
{
  "invite_code": "string",
  "display_name": "string?"
}
```

**Behavior:**

- Finds building by invite code
- Upserts user profile membership
- Sets profile status based on building approval requirements

**Returns conceptually:**

```json
{
  "success": true,
  "building": {
    "id": "uuid",
    "name": "string"
  },
  "status": "approved | pending",
  "requires_approval": true
}
```

### 11.2 `create-booking-request`

**Purpose:**

Create a booking request with validation.

**Auth:**

- Requires authenticated user JWT

**Input:**

```json
{
  "spot_id": "uuid",
  "start_time": "timestamp",
  "end_time": "timestamp"
}
```

**Behavior:**

- Validates borrower membership and approval status
- Validates spot ownership and building match
- Rejects self-booking
- Creates a pending booking request

**Returns conceptually:**

```json
{
  "success": true,
  "booking": {}
}
```

**Implementation Note:**

This path may currently be split between edge function usage and direct Flutter DB writes. Production architecture should standardize this.

### 11.3 `approve-booking`

**Purpose:**

Approve or reject a pending booking request.

**Auth:**

- Requires authenticated user JWT

**Input:**

```json
{
  "booking_id": "uuid",
  "action": "approve"
}
```

or

```json
{
  "booking_id": "uuid",
  "action": "reject"
}
```

**Behavior:**

- Verifies user is the spot owner
- Verifies booking is still pending
- Updates booking status

**Returns conceptually:**

```json
{
  "success": true,
  "booking": {}
}
```

**Error semantics:**

- `403` if caller is not the lender/owner
- validation error if booking is not pending
- conflict-like error if approval would violate overlap constraints

## 12. Frontend Architecture

### 12.1 App Bootstrap

`main.dart` is responsible for:

- Initializing Firebase
- Validating Supabase config
- Initializing Supabase
- Initializing notifications
- Launching the app

### 12.2 Routing

Routing is driven by:

- authentication state
- existence of profile
- building membership
- profile approval status

**Main route destinations:**

- Authentication screen
- Join building screen
- Pending approval screen
- Home / parking spots screen

### 12.3 Service Layer

#### `AuthService`

Responsibilities:

- Phone OTP sign-in
- OTP verification
- Sign out
- Profile read/update

#### `BuildingService`

Responsibilities:

- Join building
- Load building-related state

#### `ParkingSpotService`

Responsibilities:

- Spot CRUD
- Availability CRUD
- Spot availability checks
- Available slot calculations

#### `BookingService`

Responsibilities:

- Create booking request
- Load bookings
- Load pending requests
- Cancel bookings
- Approve/reject integration
- Compute available spots

#### `ChatService`

Responsibilities:

- Send messages
- List messages
- Stream messages in realtime

#### `NotificationService`

Responsibilities:

- Request notification permissions
- Initialize local notifications
- Get FCM token
- Display foreground notifications
- Handle notification interactions

## 13. Screen Inventory

### Authentication

- `PhoneAuthScreen`

### Building

- `JoinBuildingScreen`
- `PendingApprovalScreen`

### Spots

- `ParkingSpotsScreen`
- `AddSpotScreen`
- `ManageAvailabilityScreen`

### Bookings

- `BookingsScreen`
- `RequestSpotScreen`
- `PendingRequestsScreen`
- `BookingDetailScreen`
- Potentially `AvailableSpotsScreen` depending on current implementation state

### Chat

- `ChatScreen`

### Shared UI

- Loading indicator and similar shared components

## 14. Integrations and Operational Requirements

### 14.1 Supabase

Used for:

- Authentication
- Database
- RLS
- Realtime
- Edge functions

**Requirements:**

- Configure `SUPABASE_URL`
- Configure `SUPABASE_ANON_KEY`
- Apply migrations
- Deploy required edge functions

#### Important Migrations

- Initial schema migration
- Booking overlap exclusion constraint migration
- Availability periods migration

### 14.2 Phone OTP Provider

Phone authentication depends on Supabase phone auth configuration and SMS provider setup.

Without proper phone auth setup, authentication will not work in production.

### 14.3 Firebase and Push Notifications

Push notifications are not required for core functionality, but are highly valuable for UX.

**Future notification use cases:**

- New booking request
- Request approved
- Request rejected
- New chat message
- Booking reminders

**Current state:**

- Client scaffolding exists
- FCM token persistence appears incomplete
- Full push delivery pipeline is not yet implemented

## 15. Non-Functional Requirements

### 15.1 Privacy

- Phone numbers must not be exposed to other users
- User interaction should rely on display names and booking-scoped chat

### 15.2 Consistency

- Booking overlap prevention must remain enforced at DB level
- Request and approval flows must remain deterministic

### 15.3 Security

- RLS is central to the architecture
- App and backend flows must not bypass intended access rules

### 15.4 Realtime Responsiveness

- Chat should update live
- Booking flows should feel responsive even before push notifications are fully implemented

### 15.5 Extensibility

The current architecture should support future additions such as:

- recurring availability
- admin tooling
- notification sending
- better discovery UX
- analytics and moderation features

## 16. Current Implementation Status

### 16.1 Implemented or Substantially Present

- Phone OTP authentication
- Building join flow
- Profile-based app routing
- Parking spots CRUD
- Active/inactive spot control
- Availability periods
- Booking request flow
- Booking approval and rejection
- Booking-scoped chat
- RLS-based access control
- DB-level overlap prevention for approved bookings

### 16.2 Partially Implemented

- Available marketplace UX
- Slot computation UX
- Notification client scaffolding
- Some backend flows split between direct DB access and edge functions

### 16.3 Stubbed / TODO

- Building admin role and approval UI
- Persisting FCM tokens
- Sending actual push notifications
- Recurring availability behavior
- Unified canonical backend path for all critical flows
- Rejected-user experience definition

## 17. Known Gaps and Design Improvements

### 17.1 Admin Approval Workflow

Missing:

- Building admin role
- Admin dashboard
- Pending user approval/rejection UI
- Approval audit trail

### 17.2 Notification Pipeline

Missing:

- Token storage in backend
- Event-driven push sends
- Deep linking from notifications

### 17.3 Backend Flow Consistency

Needs standardization for:

- building join flow
- booking creation flow

### 17.4 Recurring Availability

Missing:

- recurrence UI
- recurrence evaluation logic
- recurring conflict handling

### 17.5 Product UX Clarification

Needs clearer product decisions around:

- primary discovery flow
- rejected user experience
- admin operational model

## 18. Concise Product Summary

**ParkingTrade v1** is a private, building-only resident mobile application that enables neighbors to temporarily share unused parking spots through invite-code-gated membership, approval-aware onboarding, spot registration, optional availability windows, booking request and approval flows, and booking-scoped private chat. The backend is powered by Supabase with Row Level Security and a database-level exclusion constraint that prevents overlapping approved bookings for the same spot.

## 19. Recommended Next Milestone

### Building Admin Workflow + Unified Booking Backend + Notifications

Recommended next phase should include:

#### Admin / Approval

- Introduce building admin role
- Add pending-member approval UI
- Add reject / approve / revoke membership flows

#### Backend Consistency

- Choose one canonical path for building join
- Choose one canonical path for booking creation
- Move more validation into backend APIs

#### Notifications

- Persist FCM tokens
- Send push notifications for:
  - new request
  - approval
  - rejection
  - chat message
- Deep link taps into the correct screen

#### Availability Improvements

- Recurring schedules
- Better slot generation
- Calendar-style availability UI

## 20. Suggested Future Deliverables

This specification can later be split into:

- PRD
- Technical specification
- API contract document
- Acceptance criteria document
- Developer onboarding guide
- `SPEC.md` repository reference

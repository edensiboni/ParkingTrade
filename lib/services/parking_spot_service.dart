import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/parking_spot.dart';
import '../models/spot_availability_period.dart';

class ParkingSpotService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Get user's parking spots
  Future<List<ParkingSpot>> getUserSpots() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final response = await _supabase
        .from('parking_spots')
        .select()
        .eq('resident_id', user.id)
        .order('created_at', ascending: false);

    return (response as List).map((json) => ParkingSpot.fromJson(json)).toList();
  }

  // Add a new parking spot
  Future<ParkingSpot> addSpot({
    required String buildingId,
    required String spotIdentifier,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final response = await _supabase
        .from('parking_spots')
        .insert({
          'resident_id': user.id,
          'building_id': buildingId,
          'spot_identifier': spotIdentifier,
          'is_active': true,
        })
        .select()
        .single();

    return ParkingSpot.fromJson(response);
  }

  // Update spot (toggle active/inactive or update identifier)
  Future<ParkingSpot> updateSpot({
    required String spotId,
    bool? isActive,
    String? spotIdentifier,
  }) async {
    final updates = <String, dynamic>{};
    if (isActive != null) {
      updates['is_active'] = isActive;
    }
    if (spotIdentifier != null) {
      updates['spot_identifier'] = spotIdentifier;
    }

    if (updates.isEmpty) {
      throw Exception('No updates provided');
    }

    final response = await _supabase
        .from('parking_spots')
        .update(updates)
        .eq('id', spotId)
        .select()
        .single();

    return ParkingSpot.fromJson(response);
  }

  // Delete parking spot
  Future<void> deleteSpot(String spotId) async {
    await _supabase
        .from('parking_spots')
        .delete()
        .eq('id', spotId);
  }

  // Get availability periods for a spot
  Future<List<SpotAvailabilityPeriod>> getAvailabilityPeriods(String spotId) async {
    final response = await _supabase
        .from('spot_availability_periods')
        .select()
        .eq('spot_id', spotId)
        .order('start_time', ascending: true);

    return (response as List)
        .map((json) => SpotAvailabilityPeriod.fromJson(json))
        .toList();
  }

  // Add availability period for a spot
  Future<SpotAvailabilityPeriod> addAvailabilityPeriod({
    required String spotId,
    required DateTime startTime,
    required DateTime endTime,
    bool isRecurring = false,
    String? recurringPattern,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // Verify user owns the spot
    final spot = await _supabase
        .from('parking_spots')
        .select('resident_id')
        .eq('id', spotId)
        .single();

    if (spot['resident_id'] != user.id) {
      throw Exception('You can only set availability for your own spots');
    }

    // CRITICAL FIX: Treat the input DateTime as a "naive" local time
    // and convert it to UTC explicitly. The DateTime created from date picker
    // is in local timezone, but we want to store it as if it were UTC
    // (or convert it properly to UTC).
    // 
    // The issue: DateTime(year, month, day, hour, minute) creates a LOCAL time.
    // When we call toIso8601String(), it converts to UTC, which can shift the date.
    // 
    // Solution: Extract the local date/time components and create a UTC DateTime
    // that represents the same "wall clock" time in UTC.
    final localStart = startTime.toLocal();
    final localEnd = endTime.toLocal();
    
    // Create UTC DateTime with the same date/time components
    // This ensures the date doesn't shift when stored
    final utcStart = DateTime.utc(
      localStart.year,
      localStart.month,
      localStart.day,
      localStart.hour,
      localStart.minute,
    );
    final utcEnd = DateTime.utc(
      localEnd.year,
      localEnd.month,
      localEnd.day,
      localEnd.hour,
      localEnd.minute,
    );

    // Debug: Print what we're storing
    debugPrint('💾 Storing availability period:');
    debugPrint('   Input (local): ${startTime.toLocal()} to ${endTime.toLocal()}');
    debugPrint('   Converting to UTC (same wall clock): ${utcStart} to ${utcEnd}');
    debugPrint('   ISO string: ${utcStart.toIso8601String()} to ${utcEnd.toIso8601String()}');
    
    final response = await _supabase
        .from('spot_availability_periods')
        .insert({
          'spot_id': spotId,
          'start_time': utcStart.toIso8601String(),
          'end_time': utcEnd.toIso8601String(),
          'is_recurring': isRecurring,
          if (recurringPattern != null) 'recurring_pattern': recurringPattern,
        })
        .select()
        .single();
    
    // Debug: Print what was stored
    debugPrint('✅ Stored period:');
    debugPrint('   From DB: ${response['start_time']} to ${response['end_time']}');
    final storedStart = DateTime.parse(response['start_time'] as String);
    final storedEnd = DateTime.parse(response['end_time'] as String);
    debugPrint('   Parsed (local): ${storedStart.toLocal()} to ${storedEnd.toLocal()}');
    debugPrint('   Parsed (UTC): ${storedStart.toUtc()} to ${storedEnd.toUtc()}');

    return SpotAvailabilityPeriod.fromJson(response);
  }

  // Delete availability period
  Future<void> deleteAvailabilityPeriod(String periodId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // Note: RLS policy ensures only spot owners can delete their availability periods
    await _supabase
        .from('spot_availability_periods')
        .delete()
        .eq('id', periodId);
  }

  // Check if a spot is available during a time period
  Future<bool> isSpotAvailable({
    required String spotId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    // CRITICAL FIX: Normalize input times the same way we store availability periods
    // Treat the input as "naive" local time and convert to UTC with same date/time components
    final localStart = startTime.toLocal();
    final localEnd = endTime.toLocal();
    
    final requestedStartUtc = DateTime.utc(
      localStart.year,
      localStart.month,
      localStart.day,
      localStart.hour,
      localStart.minute,
    );
    final requestedEndUtc = DateTime.utc(
      localEnd.year,
      localEnd.month,
      localEnd.day,
      localEnd.hour,
      localEnd.minute,
    );
    
    // Get all availability periods for this spot
    final periods = await getAvailabilityPeriods(spotId);

    if (periods.isEmpty) {
      // If no availability periods set, spot is always available (backward compatibility)
      debugPrint('🔍 Spot $spotId has no availability periods - treating as always available');
      return true;
    }

    // Debug: Print periods and requested time
    debugPrint('🔍 Checking availability for spot $spotId');
    debugPrint('📅 Requested (local): ${startTime.toIso8601String()} to ${endTime.toIso8601String()}');
    debugPrint('📅 Requested (UTC): ${requestedStartUtc.toIso8601String()} to ${requestedEndUtc.toIso8601String()}');
    debugPrint('📋 Found ${periods.length} availability periods');

    // Check if requested time overlaps with any availability period
    for (final period in periods) {
      final periodStartUtc = period.startTime.toUtc();
      final periodEndUtc = period.endTime.toUtc();
      
      debugPrint('  ⏰ Period (UTC): ${periodStartUtc.toIso8601String()} to ${periodEndUtc.toIso8601String()}');
      debugPrint('  📆 Period dates: ${periodStartUtc.year}-${periodStartUtc.month.toString().padLeft(2, '0')}-${periodStartUtc.day.toString().padLeft(2, '0')} ${periodStartUtc.hour.toString().padLeft(2, '0')}:${periodStartUtc.minute.toString().padLeft(2, '0')} to ${periodEndUtc.year}-${periodEndUtc.month.toString().padLeft(2, '0')}-${periodEndUtc.day.toString().padLeft(2, '0')} ${periodEndUtc.hour.toString().padLeft(2, '0')}:${periodEndUtc.minute.toString().padLeft(2, '0')}');
      debugPrint('  📆 Requested dates: ${requestedStartUtc.year}-${requestedStartUtc.month.toString().padLeft(2, '0')}-${requestedStartUtc.day.toString().padLeft(2, '0')} ${requestedStartUtc.hour.toString().padLeft(2, '0')}:${requestedStartUtc.minute.toString().padLeft(2, '0')} to ${requestedEndUtc.year}-${requestedEndUtc.month.toString().padLeft(2, '0')}-${requestedEndUtc.day.toString().padLeft(2, '0')} ${requestedEndUtc.hour.toString().padLeft(2, '0')}:${requestedEndUtc.minute.toString().padLeft(2, '0')}');
      
      // Use the normalized UTC times for comparison
      // Note: We're comparing UTC times that were created from local times
      // by treating the local date/time components as UTC
      final overlaps = requestedStartUtc.isBefore(periodEndUtc) && 
                       requestedEndUtc.isAfter(periodStartUtc);
      
      // Also show raw comparison for debugging
      debugPrint('  🔄 Overlap check:');
      debugPrint('     ${requestedStartUtc.toIso8601String()} < ${periodEndUtc.toIso8601String()} = ${requestedStartUtc.isBefore(periodEndUtc)}');
      debugPrint('     ${requestedEndUtc.toIso8601String()} > ${periodStartUtc.toIso8601String()} = ${requestedEndUtc.isAfter(periodStartUtc)}');
      debugPrint('     Result: $overlaps');
      
      if (overlaps) {
        debugPrint('  ✅ Period overlaps! Checking for approved bookings...');
        
        // Found an availability period that overlaps
        // Now check if there are any approved OR pending bookings that would block this time
        // Pending bookings also block to prevent double-booking
        final user = _supabase.auth.currentUser;
        if (user != null) {
          // Check for overlapping approved and pending bookings manually
          final allBookings = await _supabase
              .from('booking_requests')
              .select('start_time, end_time, status')
              .eq('spot_id', spotId)
              .inFilter('status', ['approved', 'pending']);

          bool hasBlockingBooking = false;
          if (allBookings.isNotEmpty) {
            for (final booking in allBookings) {
              final bookingStart = DateTime.parse(booking['start_time'] as String);
              final bookingEnd = DateTime.parse(booking['end_time'] as String);
              final bookingStatus = booking['status'] as String;
              
              // Normalize booking times (same way we store them)
              final localStart = bookingStart.toLocal();
              final localEnd = bookingEnd.toLocal();
              
              final bookingStartUtc = DateTime.utc(
                localStart.year,
                localStart.month,
                localStart.day,
                localStart.hour,
                localStart.minute,
              );
              final bookingEndUtc = DateTime.utc(
                localEnd.year,
                localEnd.month,
                localEnd.day,
                localEnd.hour,
                localEnd.minute,
              );
              
              // Check if booking overlaps with requested time
              if (requestedStartUtc.isBefore(bookingEndUtc) && requestedEndUtc.isAfter(bookingStartUtc)) {
                debugPrint('  ❌ Blocked by $bookingStatus booking: ${bookingStart.toIso8601String()} to ${bookingEnd.toIso8601String()}');
                hasBlockingBooking = true;
                break;
              }
            }
          }

          if (hasBlockingBooking) {
            return false;
          }
        }
        
        // Availability period exists and no approved bookings block it
        debugPrint('  ✅ Spot is available!');
        return true;
      }
    }

    // No availability period overlaps with requested time
    debugPrint('  ❌ No availability period overlaps with requested time');
    return false;
  }

  // Get available time slots for a spot (availability periods minus approved bookings)
  // Returns a list of time ranges that are actually available for booking
  Future<List<Map<String, DateTime>>> getAvailableTimeSlots({
    required String spotId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Default to next 30 days if no date range specified
    final now = DateTime.now();
    final searchStart = startDate ?? now;
    final searchEnd = endDate ?? now.add(const Duration(days: 30));

    // Normalize search dates to UTC
    final searchStartUtc = DateTime.utc(
      searchStart.year,
      searchStart.month,
      searchStart.day,
      0,
      0,
    );
    final searchEndUtc = DateTime.utc(
      searchEnd.year,
      searchEnd.month,
      searchEnd.day,
      23,
      59,
    );

    // Get all availability periods for this spot
    final periods = await getAvailabilityPeriods(spotId);
    
    // Get all approved AND pending bookings for this spot
    // Pending bookings should also be considered to prevent double-booking
    // We'll get both and treat them the same way for availability calculation
    final allBookings = await _supabase
        .from('booking_requests')
        .select('start_time, end_time, status')
        .eq('spot_id', spotId)
        .inFilter('status', ['approved', 'pending']);
    
    // Filter to only bookings that overlap with search range
    final relevantBookings = (allBookings as List).where((booking) {
      final bookingStart = DateTime.parse(booking['start_time'] as String);
      final bookingEnd = DateTime.parse(booking['end_time'] as String);
      
      // Normalize booking times
      final localStart = bookingStart.toLocal();
      final localEnd = bookingEnd.toLocal();
      
      final bookingStartUtc = DateTime.utc(
        localStart.year,
        localStart.month,
        localStart.day,
        localStart.hour,
        localStart.minute,
      );
      final bookingEndUtc = DateTime.utc(
        localEnd.year,
        localEnd.month,
        localEnd.day,
        localEnd.hour,
        localEnd.minute,
      );
      
      // Check if booking overlaps with search range
      return bookingStartUtc.isBefore(searchEndUtc) && bookingEndUtc.isAfter(searchStartUtc);
    }).toList();

    // Normalize bookings to UTC (same way we store them)
    final bookings = <Map<String, DateTime>>[];
    for (final booking in relevantBookings) {
      final bookingStart = DateTime.parse(booking['start_time'] as String);
      final bookingEnd = DateTime.parse(booking['end_time'] as String);
      
      final localStart = bookingStart.toLocal();
      final localEnd = bookingEnd.toLocal();
      
      bookings.add({
        'start': DateTime.utc(
          localStart.year,
          localStart.month,
          localStart.day,
          localStart.hour,
          localStart.minute,
        ),
        'end': DateTime.utc(
          localEnd.year,
          localEnd.month,
          localEnd.day,
          localEnd.hour,
          localEnd.minute,
        ),
      });
    }

    // Calculate available slots by subtracting bookings from periods
    final availableSlots = <Map<String, DateTime>>[];
    
    for (final period in periods) {
      final periodStartUtc = period.startTime.toUtc();
      final periodEndUtc = period.endTime.toUtc();
      
      // Skip periods outside search range
      if (periodEndUtc.isBefore(searchStartUtc) || periodStartUtc.isAfter(searchEndUtc)) {
        continue;
      }
      
      // Find bookings that overlap with this period
      final overlappingBookings = bookings.where((booking) {
        final bookingStart = booking['start']!;
        final bookingEnd = booking['end']!;
        return bookingStart.isBefore(periodEndUtc) && bookingEnd.isAfter(periodStartUtc);
      }).toList();
      
      if (overlappingBookings.isEmpty) {
        // No bookings, entire period is available
        availableSlots.add({
          'start': periodStartUtc,
          'end': periodEndUtc,
        });
      } else {
        // Sort bookings by start time
        overlappingBookings.sort((a, b) => a['start']!.compareTo(b['start']!));
        
        // Calculate available slots between bookings
        DateTime currentStart = periodStartUtc;
        
        for (final booking in overlappingBookings) {
          final bookingStart = booking['start']!;
          final bookingEnd = booking['end']!;
          
          // If there's a gap before this booking, add it as available
          if (currentStart.isBefore(bookingStart)) {
            availableSlots.add({
              'start': currentStart,
              'end': bookingStart,
            });
          }
          
          // Move current start to after this booking
          currentStart = currentStart.isAfter(bookingEnd) ? currentStart : bookingEnd;
        }
        
        // Add remaining time after last booking
        if (currentStart.isBefore(periodEndUtc)) {
          availableSlots.add({
            'start': currentStart,
            'end': periodEndUtc,
          });
        }
      }
    }
    
    // Sort by start time
    availableSlots.sort((a, b) => a['start']!.compareTo(b['start']!));
    
    return availableSlots;
  }
}


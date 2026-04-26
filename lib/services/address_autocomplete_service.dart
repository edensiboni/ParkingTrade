import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/places_config.dart';

/// A single address suggestion from Places Autocomplete.
class AddressSuggestion {
  final String displayText;
  final String? placeId;

  const AddressSuggestion({required this.displayText, this.placeId});
}

/// Lat/lng pair returned from Place Details.
class LatLng {
  final double lat;
  final double lng;

  const LatLng({required this.lat, required this.lng});
}

/// Wraps Google Places Autocomplete (address) with debouncing.
/// On web, uses Supabase Edge Function to avoid CORS; on mobile, calls Google directly if key set.
class AddressAutocompleteService {
  static const _debounceMs = 300;
  Timer? _debounceTimer;
  String? _lastQuery;
  List<AddressSuggestion>? _lastResult;

  static const _autocompleteBaseUrl =
      'https://maps.googleapis.com/maps/api/place/autocomplete/json';
  static const _detailsBaseUrl =
      'https://maps.googleapis.com/maps/api/place/details/json';

  /// True if autocomplete can be used (web: always try Edge Function; mobile: need key).
  static bool get isAvailable => kIsWeb || PlacesConfig.isConfigured;

  /// Returns address suggestions for [input]. Debounced by [_debounceMs].
  /// Returns empty list if input too short or request fails.
  Future<List<AddressSuggestion>> suggest(String input) async {
    final trimmed = input.trim();
    if (trimmed.length < 3) return [];
    if (!kIsWeb && !PlacesConfig.isConfigured) return [];

    if (_lastQuery == trimmed && _lastResult != null) {
      return _lastResult!;
    }

    _debounceTimer?.cancel();
    final completer = Completer<List<AddressSuggestion>>();
    _debounceTimer = Timer(
      const Duration(milliseconds: _debounceMs),
      () async {
        _debounceTimer = null;
        try {
          final result = kIsWeb
              ? await _fetchViaEdgeFunction(trimmed)
              : await _fetchSuggestions(trimmed);
          _lastQuery = trimmed;
          _lastResult = result;
          if (!completer.isCompleted) completer.complete(result);
        } catch (e) {
          if (!completer.isCompleted) completer.complete([]);
        }
      },
    );

    return completer.future;
  }

  /// Fetches lat/lng for a [placeId] using Place Details API.
  /// Returns null if the key is not configured or the request fails.
  Future<LatLng?> fetchLatLng(String placeId) async {
    if (placeId.isEmpty) return null;
    try {
      if (kIsWeb) {
        return await _fetchLatLngViaEdgeFunction(placeId);
      } else if (PlacesConfig.isConfigured) {
        return await _fetchLatLngDirect(placeId);
      }
    } catch (_) {}
    return null;
  }

  void cancel() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  // ── Autocomplete ──────────────────────────────────────────────────────────────

  /// On web: call our Edge Function (avoids CORS; API key stays server-side).
  Future<List<AddressSuggestion>> _fetchViaEdgeFunction(String input) async {
    final response = await Supabase.instance.client.functions.invoke(
      'places-autocomplete',
      body: {'input': input},
    );
    if (response.status != 200 || response.data == null) return [];
    final body = response.data is Map
        ? response.data as Map<String, dynamic>
        : _parseJson(response.data is String ? response.data as String : '{}');
    if (body == null) return [];
    final predictions = body['predictions'];
    if (predictions is! List) return [];
    return _parsePredictions(predictions);
  }

  Future<List<AddressSuggestion>> _fetchSuggestions(String input) async {
    final uri = Uri.parse(_autocompleteBaseUrl).replace(
      queryParameters: {
        'input': input,
        'key': PlacesConfig.placesApiKey,
        'types': 'address',
      },
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) return [];
    final body = _parseJson(response.body);
    if (body == null) return [];
    final predictions = body['predictions'];
    if (predictions is! List) return [];
    return _parsePredictions(predictions);
  }

  // ── Place Details / LatLng ────────────────────────────────────────────────────

  Future<LatLng?> _fetchLatLngViaEdgeFunction(String placeId) async {
    final response = await Supabase.instance.client.functions.invoke(
      'places-autocomplete',
      body: {'place_id': placeId, 'action': 'details'},
    );
    if (response.status != 200 || response.data == null) return null;
    final body = response.data is Map
        ? response.data as Map<String, dynamic>
        : _parseJson(response.data is String ? response.data as String : '{}');
    return _extractLatLng(body);
  }

  Future<LatLng?> _fetchLatLngDirect(String placeId) async {
    final uri = Uri.parse(_detailsBaseUrl).replace(
      queryParameters: {
        'place_id': placeId,
        'key': PlacesConfig.placesApiKey,
        'fields': 'geometry',
      },
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) return null;
    final body = _parseJson(response.body);
    return _extractLatLng(body);
  }

  static LatLng? _extractLatLng(dynamic body) {
    if (body is! Map) return null;
    final result = body['result'];
    if (result is! Map) return null;
    final geometry = result['geometry'];
    if (geometry is! Map) return null;
    final location = geometry['location'];
    if (location is! Map) return null;
    final lat = (location['lat'] as num?)?.toDouble();
    final lng = (location['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LatLng(lat: lat, lng: lng);
  }

  // ── Shared helpers ────────────────────────────────────────────────────────────

  static List<AddressSuggestion> _parsePredictions(List<dynamic> predictions) {
    return predictions
        .map((e) {
          if (e is! Map) return null;
          final description = e['description'] as String?;
          if (description == null || description.isEmpty) return null;
          return AddressSuggestion(
            displayText: description,
            placeId: e['place_id'] as String?,
          );
        })
        .whereType<AddressSuggestion>()
        .toList();
  }

  static dynamic _parseJson(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
}

import 'dart:convert';

import 'package:http/http.dart' as http;

class GoongLocationDetails {
  const GoongLocationDetails({
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.staticMapUrl,
    required this.mapsUrl,
    this.placeId,
  });

  final double latitude;
  final double longitude;
  final String address;
  final String staticMapUrl;
  final String mapsUrl;
  final String? placeId;
}

class GoongService {
  static const _defaultHeaders = {'User-Agent': 'Mozilla/5.0'};
  static const _maptilesKey = String.fromEnvironment(
    'GOONG_MAPTILES_KEY',
    defaultValue: 'MNeXzpbvfziWB5WZ05HbsSi9u25PDwUAtwbU76or',
  );
  static const _apiKey = String.fromEnvironment(
    'GOONG_API_KEY',
    defaultValue: 'AhWwwqjjSxp2jwZnQ5hatCmFTxprUq0D4kYV9yGn',
  );

  static bool get isConfigured => _apiKey.isNotEmpty;

  static Future<GoongLocationDetails> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    if (!isConfigured) {
      throw Exception('Missing Goong API key.');
    }

    final uri = Uri.parse(
      'https://rsapi.goong.io/Geocode?latlng=$latitude,$longitude&api_key=$_apiKey',
    );
    final response = await http.get(uri, headers: _defaultHeaders);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      throw Exception('Goong reverse geocoding failed.');
    }

    final results = body['results'];
    Map<String, dynamic>? firstResult;
    if (results is List && results.isNotEmpty && results.first is Map) {
      firstResult = Map<String, dynamic>.from(results.first as Map);
    }

    final address =
        firstResult?['formatted_address']?.toString().trim().isNotEmpty == true
        ? firstResult!['formatted_address'].toString().trim()
        : '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
    final placeId = firstResult?['place_id']?.toString();

    return GoongLocationDetails(
      latitude: latitude,
      longitude: longitude,
      address: address,
      placeId: placeId,
      staticMapUrl: buildStaticMapUrl(latitude: latitude, longitude: longitude),
      mapsUrl: buildMapsUrl(
        latitude: latitude,
        longitude: longitude,
        placeId: placeId,
      ),
    );
  }

  static String buildMapsUrl({
    required double latitude,
    required double longitude,
    String? placeId,
  }) {
    if (placeId != null && placeId.trim().isNotEmpty) {
      return 'https://maps.goong.io/?pid=${Uri.encodeComponent(placeId.trim())}';
    }

    return 'https://maps.goong.io/?lat=${latitude.toStringAsFixed(6)}'
        '&lng=${longitude.toStringAsFixed(6)}&zoom=16';
  }

  static String buildStaticMapUrl({
    required double latitude,
    required double longitude,
    int width = 600,
    int height = 320,
  }) {
    final destinationLatitude = latitude + 0.00035;
    final destinationLongitude = longitude + 0.00035;

    return 'https://rsapi.goong.io/staticmap/route'
        '?origin=${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}'
        '&destination=${destinationLatitude.toStringAsFixed(6)},${destinationLongitude.toStringAsFixed(6)}'
        '&vehicle=car'
        '&width=$width'
        '&height=$height'
        '&api_key=$_apiKey';
  }

  static String get maptilesKey => _maptilesKey;
}

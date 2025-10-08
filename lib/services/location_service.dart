import 'package:geolocator/geolocator.dart';

class LocationService {
  /// Check if location services are enabled
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Check and request location permissions
  Future<LocationPermission> checkAndRequestPermission() async {
    bool serviceEnabled = await isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.'
      );
    }

    return permission;
  }

  /// Get current position with error handling
  Future<Position> getCurrentPosition() async {
    await checkAndRequestPermission();
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  /// Calculate distance between two coordinates in kilometers
  double calculateDistance(
      double startLatitude,
      double startLongitude,
      double endLatitude,
      double endLongitude,
      ) {
    return Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    ) / 1000; // Convert to kilometers
  }

  /// Get formatted address from coordinates (stub - implement with your preferred geocoding service)
  Future<String> getAddressFromCoordinates(double latitude, double longitude) async {
    // Implement with your preferred geocoding service
    // For example: Google Maps Geocoding API or OpenStreetMap Nominatim
    return '$latitude, $longitude';
  }

  /// Check if location settings need to be enabled
  Future<bool> openLocationSettings() {
    return Geolocator.openLocationSettings();
  }

  /// Check if app settings need to be opened to enable permissions
  Future<bool> openAppSettings() {
    return Geolocator.openAppSettings();
  }
}

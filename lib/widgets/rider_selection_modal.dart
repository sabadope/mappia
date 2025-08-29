import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class RiderSelectionModal extends StatelessWidget {
  final List<Map<String, dynamic>> availableRiders;
  final Function(Map<String, dynamic>) onRiderSelected;
  final Function() onCancel;
  final Position restaurantPosition;

  const RiderSelectionModal({
    Key? key,
    required this.availableRiders,
    required this.onRiderSelected,
    required this.onCancel,
    required this.restaurantPosition,
  }) : super(key: key);

  String _calculateDistance(double lat, double lng) {
    final distanceInMeters = Geolocator.distanceBetween(
      restaurantPosition.latitude,
      restaurantPosition.longitude,
      lat,
      lng,
    );
    
    if (distanceInMeters > 1000) {
      return '${(distanceInMeters / 1000).toStringAsFixed(1)} km away';
    } else {
      return '${distanceInMeters.toStringAsFixed(0)} meters away';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select a Rider'),
      content: SizedBox(
        width: double.maxFinite,
        child: availableRiders.isEmpty
            ? const Text('No riders available at the moment. Please try again later.')
            : ListView.builder(
                shrinkWrap: true,
                itemCount: availableRiders.length,
                itemBuilder: (context, index) {
                  final rider = availableRiders[index];
                  return ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.delivery_dining),
                    ),
                    title: Text(rider['name'] ?? 'Rider ${index + 1}'),
                    subtitle: Text(
                      _calculateDistance(
                        rider['latitude'] ?? 0.0,
                        rider['longitude'] ?? 0.0,
                      ),
                    ),
                    onTap: () => onRiderSelected(rider),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

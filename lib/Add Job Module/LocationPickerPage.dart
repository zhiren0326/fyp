import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({super.key});

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  GoogleMapController? mapController;
  LatLng? _markerPosition;
  final TextEditingController _addressController = TextEditingController();
  final Set<Marker> _markers = {};
  bool _isConfirmEnabled = false;

  @override
  void initState() {
    super.initState();
    _getCurrentLocationWithConfirmation();
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
    if (_markerPosition != null) {
      mapController!.animateCamera(CameraUpdate.newLatLng(_markerPosition!));
      _setMarker(_markerPosition!);
    }
  }

  void _setMarker(LatLng position) {
    setState(() {
      _markerPosition = position;
      _markers.clear();
      _markers.add(Marker(markerId: const MarkerId("selected"), position: position));
    });
  }

  Future<void> _getCurrentLocationWithConfirmation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final currentLatLng = LatLng(position.latitude, position.longitude);
      final placemarks = await placemarkFromCoordinates(currentLatLng.latitude, currentLatLng.longitude);
      final place = placemarks.first;
      final address = '${place.street}, ${place.locality}, ${place.country}';

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text("Use Current Location"),
          content: Text("Do you want to use your current location?\n\n$address"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                const defaultLatLng = LatLng(3.1390, 101.6869); // Kuala Lumpur
                _setMarker(defaultLatLng);
                _addressController.clear();
                setState(() {
                  _isConfirmEnabled = false;
                });
                mapController?.animateCamera(CameraUpdate.newLatLng(defaultLatLng));
              },
              child: const Text("No"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _setMarker(currentLatLng);
                mapController?.animateCamera(CameraUpdate.newLatLng(currentLatLng));
                _updateAddress(currentLatLng);
              },
              child: const Text("Yes"),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _updateAddress(LatLng location) async {
    try {
      final placemarks = await placemarkFromCoordinates(location.latitude, location.longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final address = '${place.street}, ${place.locality}, ${place.country}';
        _addressController.text = address;
        setState(() {
          _isConfirmEnabled = true;
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  Future<void> _searchAddress(String query) async {
    try {
      final locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        final target = LatLng(locations.first.latitude, locations.first.longitude);
        mapController?.animateCamera(CameraUpdate.newLatLng(target));
        _setMarker(target);
        _updateAddress(target);
      }
    } catch (e) {
      debugPrint('Address not found: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Address not found.")),
      );
    }
  }

  void _confirmLocation() {
    if (_isConfirmEnabled && _addressController.text.isNotEmpty) {
      Navigator.pop(context, _addressController.text);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter an address before confirming.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pick a Location')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _addressController,
              onSubmitted: _searchAddress,
              decoration: InputDecoration(
                hintText: 'Enter an address...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _searchAddress(_addressController.text),
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _markerPosition == null
                ? const Center(child: CircularProgressIndicator())
                : GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(target: _markerPosition!, zoom: 14),
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              markers: _markers,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: ElevatedButton(
              onPressed: _confirmLocation,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                disabledBackgroundColor: Colors.orange.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text("Confirm Location", style: TextStyle(color: Colors.white)),
            ),
          )
        ],
      ),
    );
  }
}

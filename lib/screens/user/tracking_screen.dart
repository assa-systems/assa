import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});
  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  final MapController _mapController = MapController();
  // AFIT Kaduna approximate center
  static const LatLng _afitCenter = LatLng(10.6120, 7.4452);

  List<Map<String, dynamic>> _campusLocations = [];
  List<Map<String, dynamic>> _onlineDrivers = [];
  StreamSubscription? _locationsSub;
  StreamSubscription? _driversSub;

  bool _studentAddMode = false;

  @override
  void initState() {
    super.initState();
    _listenToLocations();
    _listenToDrivers();
  }

  void _listenToLocations() {
    _locationsSub = FirebaseFirestore.instance
        .collection('campus_locations')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _campusLocations = snap.docs
            .where((d) => !(d.data()['deleted'] == true))
            .map((d) => {'id': d.id, ...d.data()})
            .toList();
      });
    });
  }

  void _listenToDrivers() {
    _driversSub = FirebaseFirestore.instance
        .collection('drivers')
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _onlineDrivers = snap.docs
            .where((d) => d.data()['liveLocation'] != null)
            .map((d) => {'id': d.id, ...d.data()})
            .toList();
      });
    });
  }

  void _onMapTap(TapPosition tapPos, LatLng latlng) {
    if (!_studentAddMode) return;
    _showAddLocationDialog(latlng);
  }

  Future<void> _showAddLocationDialog(LatLng latlng) async {
    final nameCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Suggest a Location', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📍 ${latlng.latitude.toStringAsFixed(5)}, ${latlng.longitude.toStringAsFixed(5)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Location Name',
                hintText: 'e.g. Library, Parade Ground...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              await FirebaseFirestore.instance.collection('campus_locations').add({
                'name': name,
                'lat': latlng.latitude,
                'lng': latlng.longitude,
                'category': 'Student Suggested',
                'addedBy': 'student',
                'createdAt': FieldValue.serverTimestamp(),
              });
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location suggested! Visible to all users.'), backgroundColor: Color(0xFF10B981)),
      );
    }
    setState(() {
      _studentAddMode = false;
    });
  }

  void _showLocationInfo(Map<String, dynamic> loc) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on_rounded, color: Color(0xFF2563EB), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(loc['name'] ?? 'Location',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ],
            ),
            if (loc['category'] != null)
              Padding(
                padding: const EdgeInsets.only(left: 30, bottom: 8),
                child: Text(loc['category'], style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ),
            if (loc['photoUrl'] != null && (loc['photoUrl'] as String).isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(loc['photoUrl'], width: double.infinity, height: 180, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        height: 180,
                        decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
                        child: const Center(child: Icon(Icons.image_not_supported, size: 48, color: Colors.grey)))),
              )
            else
              Container(
                width: double.infinity,
                height: 100,
                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                child: const Center(child: Text('No photo yet', style: TextStyle(color: Colors.grey))),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _locationsSub?.cancel();
    _driversSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        title: const Text('🗺️ Campus Shuttle Tracker', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        actions: [
          if (_studentAddMode)
            TextButton.icon(
              onPressed: () => setState(() => _studentAddMode = false),
              icon: const Icon(Icons.close, color: Colors.white, size: 18),
              label: const Text('Cancel', style: TextStyle(color: Colors.white)),
            )
          else
            TextButton.icon(
              onPressed: () => setState(() => _studentAddMode = true),
              icon: const Icon(Icons.add_location_alt_rounded, color: Color(0xFF10B981), size: 20),
              label: const Text('Add Location', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _afitCenter,
              initialZoom: 16.0,
              onTap: _onMapTap,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.assa.app',
              ),
              MarkerLayer(
                markers: [
                  // Campus location pins
                  ..._campusLocations.map((loc) {
                    final lat = (loc['lat'] as num?)?.toDouble() ?? 0;
                    final lng = (loc['lng'] as num?)?.toDouble() ?? 0;
                    if (lat == 0 && lng == 0) return null;
                    return Marker(
                      point: LatLng(lat, lng),
                      width: 44,
                      height: 44,
                      child: GestureDetector(
                        onTap: () => _showLocationInfo(loc),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                          ),
                          child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 22),
                        ),
                      ),
                    );
                  }).whereType<Marker>(),

                  // Online driver shuttle markers
                  ..._onlineDrivers.map((driver) {
                    final loc = driver['liveLocation'] as Map<String, dynamic>?;
                    if (loc == null) return null;
                    final lat = (loc['lat'] as num?)?.toDouble() ?? 0;
                    final lng = (loc['lng'] as num?)?.toDouble() ?? 0;
                    if (lat == 0 && lng == 0) return null;
                    return Marker(
                      point: LatLng(lat, lng),
                      width: 48,
                      height: 48,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                        ),
                        child: const Text('🚌', style: TextStyle(fontSize: 20)),
                      ),
                    );
                  }).whereType<Marker>(),
                ],
              ),
            ],
          ),

          // Top status bar
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              color: const Color(0xCC0F172A),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.circle, color: Color(0xFF10B981), size: 10),
                  const SizedBox(width: 6),
                  Text('Campus Shuttle Mode  •  ${_onlineDrivers.length} active',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('${_campusLocations.length} locations',
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),

          // Add mode hint
          if (_studentAddMode)
            Positioned(
              bottom: 20, left: 16, right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.touch_app_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 10),
                    Expanded(child: Text('Tap the map at the exact location to add a pin',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

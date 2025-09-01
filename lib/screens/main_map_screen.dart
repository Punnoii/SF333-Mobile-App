import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'login_screen.dart';
import 'forum_screen.dart';
import 'chat_list_screen.dart';
import 'profile_screen.dart';
import 'incident_report_screen.dart';
import 'incident_detail_screen.dart';

class MainMapScreen extends StatefulWidget {
  static const String routeName = '/main';
  const MainMapScreen({super.key});

  @override
  State<MainMapScreen> createState() => _MainMapScreenState();
}

class _MainMapScreenState extends State<MainMapScreen> {
  int currentIndex = 1; // Start with Home (map) tab
  final MapController mapController = MapController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final double _minZoom = 3;
  final double _maxZoom = 18;
  double _currentZoom = 12;
  LatLng _currentCenter = const LatLng(13.7563, 100.5018);
  bool _showPopup = false;
  LatLng? _selectedLocation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PAISABAI'),
        centerTitle: false,
        actions: [
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
      endDrawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: const [
              ListTile(leading: Icon(Icons.info_outline), title: Text('About')),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: currentIndex,
        children: [
          _buildChatList(),
          _buildMap(),
          const ForumScreen(),
          _buildProfile(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: currentIndex,
        onTap: (i) async {
          if ((i == 0 || i == 3) && FirebaseAuth.instance.currentUser == null) {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
            if (FirebaseAuth.instance.currentUser == null) return;
          }
          setState(() => currentIndex = i);
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.message_outlined), label: 'Chat'),
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.forum_outlined), label: 'Forum'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return Stack(
      children: [
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: _currentCenter,
            initialZoom: _currentZoom,
            minZoom: _minZoom,
            maxZoom: _maxZoom,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
            onMapEvent: (event) {
              // Keep track of center/zoom for controls
              setState(() {
                _currentZoom = event.camera.zoom;
                _currentCenter = event.camera.center;
              });
            },
            onTap: (tapPosition, point) {
              setState(() {
                _selectedLocation = point;
                _showPopup = true;
              });
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.paisabai_app',
            ),
            // Show all incidents as markers
            StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('incidents').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                
                final incidents = snapshot.data!.docs;
                return MarkerLayer(
                  markers: incidents.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final lat = data['latitude'] as double;
                    final lng = data['longitude'] as double;
                    
                    return Marker(
                      point: LatLng(lat, lng),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => IncidentDetailScreen(
                                incident: data,
                                incidentId: doc.id,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: _getCategoryColor(data['category']),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.warning,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            if (_selectedLocation != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _selectedLocation!,
                    child: const Icon(
                      Icons.location_pin,
                      color: Colors.red,
                      size: 40,
                    ),
                  ),
                ],
              ),
          ],
        ),
        // Map popup
        if (_showPopup && _selectedLocation != null)
          Positioned(
            bottom: 120,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2B2B2B),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Location Selected',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _showPopup = false;
                            _selectedLocation = null;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Lat: ${_selectedLocation!.latitude.toStringAsFixed(4)}, '
                    'Lng: ${_selectedLocation!.longitude.toStringAsFixed(4)}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.report_problem),
                        label: const Text('Report'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () async {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null) {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const LoginScreen()),
                            );
                            if (FirebaseAuth.instance.currentUser == null) return;
                          }
                          
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => IncidentReportScreen(
                                latitude: _selectedLocation!.latitude,
                                longitude: _selectedLocation!.longitude,
                              ),
                            ),
                          );
                          
                          if (result == true) {
                            setState(() {
                              _showPopup = false;
                              _selectedLocation = null;
                            });
                          }
                        },
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.close),
                        label: const Text('Cancel'),
                        onPressed: () {
                          setState(() {
                            _showPopup = false;
                            _selectedLocation = null;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          right: 12,
          bottom: 90,
          child: Column(
            children: [
              _ZoomButton(
                icon: Icons.add,
                onPressed: () {
                  final next = (_currentZoom + 1).clamp(_minZoom, _maxZoom);
                  mapController.move(_currentCenter, next.toDouble());
                },
              ),
              const SizedBox(height: 8),
              _ZoomButton(
                icon: Icons.remove,
                onPressed: () {
                  final next = (_currentZoom - 1).clamp(_minZoom, _maxZoom);
                  mapController.move(_currentCenter, next.toDouble());
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatList() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Please login to view chats'));
    }
    return const ChatListScreen();
  }

  Widget _buildProfile() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Please login to view your profile'));
    }
    return const ProfileScreen();
  }
  
  Color _getCategoryColor(String? category) {
    switch (category) {
      case 'Traffic':
        return Colors.orange;
      case 'Accident':
        return Colors.red;
      case 'Road Work':
        return Colors.yellow[700]!;
      case 'Hazard':
        return Colors.purple;
      case 'Crime':
        return Colors.red[900]!;
      case 'Emergency':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  const _ZoomButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.6),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}



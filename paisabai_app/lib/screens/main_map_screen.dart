import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';
import 'edit_profile_screen.dart';

class MainMapScreen extends StatefulWidget {
  static const String routeName = '/main';
  const MainMapScreen({super.key});

  @override
  State<MainMapScreen> createState() => _MainMapScreenState();
}

class _MainMapScreenState extends State<MainMapScreen> {
  int currentIndex = 0;
  final MapController mapController = MapController();
  final double _minZoom = 3;
  final double _maxZoom = 18;
  double _currentZoom = 12;
  LatLng _currentCenter = const LatLng(13.7563, 100.5018);

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
          const Center(child: Text('Messages')),
          _buildMap(),
          _buildProfile(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (i) async {
          if (i == 2 && FirebaseAuth.instance.currentUser == null) {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
            if (FirebaseAuth.instance.currentUser == null) return;
          }
          setState(() => currentIndex = i);
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.message_outlined), label: 'Message'),
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
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
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.paisabai_app',
            ),
          ],
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

  Widget _buildProfile() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Please login to view your profile'));
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(radius: 32, child: Icon(Icons.person, size: 36)),
          const SizedBox(height: 12),
          Text(user.email ?? 'Unknown'),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                  ).then((_) => setState(() {}));
                },
                child: const Text('Edit Profile'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (!mounted) return;
                  setState(() => currentIndex = 1);
                },
                child: const Text('Logout'),
              ),
            ],
          ),
        ],
      ),
    );
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



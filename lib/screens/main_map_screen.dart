import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  int _unreadChatCount = 0;

  @override
  void initState() {
    super.initState();
    _listenToUnreadMessages();
  }

  void _listenToUnreadMessages() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    // Listen to all chats where current user is a participant
    _firestore
        .collection('chats')
        .where('participants', arrayContains: currentUser.uid)
        .snapshots()
        .listen((chatSnapshot) {
      int totalUnread = 0;
      
      for (var chatDoc in chatSnapshot.docs) {
        final chatData = chatDoc.data();
        final lastReadTimestamp = chatData['lastRead_${currentUser.uid}'] as Timestamp?;
        final lastMessageTimestamp = chatData['lastMessageTimestamp'] as Timestamp?;
        final lastSenderId = chatData['lastSenderId'] as String?;
        
        // If there's a new message after last read and it's not from current user
        if (lastMessageTimestamp != null && 
            lastSenderId != currentUser.uid &&
            (lastReadTimestamp == null || lastMessageTimestamp.compareTo(lastReadTimestamp) > 0)) {
          totalUnread++;
        }
      }
      
      if (mounted) {
        setState(() {
          _unreadChatCount = totalUnread;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Colors.tealAccent, Colors.cyan],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            'PAISABAI',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        centerTitle: false,
        backgroundColor: Colors.black.withOpacity(0.9),
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.black.withOpacity(0.9),
                Colors.grey[900]!.withOpacity(0.9),
              ],
            ),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.tealAccent, Colors.cyan],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu, color: Colors.black),
                onPressed: () => Scaffold.of(ctx).openEndDrawer(),
              ),
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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.grey[900]!.withOpacity(0.95),
              Colors.black.withOpacity(0.98),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.tealAccent.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: currentIndex,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: Colors.tealAccent,
          unselectedItemColor: Colors.grey[400],
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
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
          items: [
            BottomNavigationBarItem(
              icon: Stack(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: currentIndex == 0 ? Colors.tealAccent.withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.message_outlined),
                  ),
                  if (_unreadChatCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Colors.red, Colors.redAccent],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.4),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          _unreadChatCount > 99 ? '99+' : _unreadChatCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              label: 'Chat',
            ),
            BottomNavigationBarItem(
              icon: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: currentIndex == 1 ? Colors.tealAccent.withOpacity(0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.home_outlined),
              ),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: currentIndex == 2 ? Colors.tealAccent.withOpacity(0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.forum_outlined),
              ),
              label: 'Forum',
            ),
            BottomNavigationBarItem(
              icon: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: currentIndex == 3 ? Colors.tealAccent.withOpacity(0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_outline),
              ),
              label: 'Profile',
            ),
          ],
        ),
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
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _getCategoryColor(data['category']),
                                _getCategoryColor(data['category']).withOpacity(0.8),
                              ],
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: _getCategoryColor(data['category']).withOpacity(0.4),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.warning,
                            color: Colors.white,
                            size: 18,
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
        // Map popup with enhanced styling
        if (_showPopup && _selectedLocation != null)
          Positioned(
            bottom: 120,
            left: 20,
            right: 20,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF2B2B2B),
                    Colors.grey[800]!,
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.tealAccent.withOpacity(0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.tealAccent.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
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
                      Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Colors.red, Colors.redAccent],
                          ),
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.report_problem),
                          label: const Text('Report'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
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
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.grey[700]!, Colors.grey[600]!],
                          ),
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.close),
                          label: const Text('Cancel'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                          onPressed: () {
                            setState(() {
                              _showPopup = false;
                              _selectedLocation = null;
                            });
                          },
                        ),
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
              _EnhancedZoomButton(
                icon: Icons.add,
                onPressed: () {
                  final next = (_currentZoom + 1).clamp(_minZoom, _maxZoom);
                  mapController.move(_currentCenter, next.toDouble());
                },
              ),
              const SizedBox(height: 8),
              _EnhancedZoomButton(
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

class _EnhancedZoomButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  const _EnhancedZoomButton({required this.icon, required this.onPressed});

  @override
  State<_EnhancedZoomButton> createState() => _EnhancedZoomButtonState();
}

class _EnhancedZoomButtonState extends State<_EnhancedZoomButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.black.withOpacity(0.8),
                  Colors.grey[800]!.withOpacity(0.9),
                ],
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.tealAccent.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.tealAccent.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTapDown: (_) => _animationController.forward(),
                onTapUp: (_) => _animationController.reverse(),
                onTapCancel: () => _animationController.reverse(),
                onTap: widget.onPressed,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    widget.icon,
                    color: Colors.tealAccent,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}



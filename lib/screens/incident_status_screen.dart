import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';
import 'dart:math';
import 'incident_detail_screen.dart';
import '../constants/disability_types.dart';
import '../services/cloudinary_service.dart';
import '../services/theme_service.dart';

class IncidentStatusScreen extends StatefulWidget {
  static const String routeName = '/incident-status';
  const IncidentStatusScreen({super.key});

  @override
  State<IncidentStatusScreen> createState() => _IncidentStatusScreenState();
}

class _IncidentStatusScreenState extends State<IncidentStatusScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Position? _currentPosition;
  bool _isLoadingLocation = false;
  String _selectedStatus = 'all';
  String _searchQuery = '';
  bool _onlyNearby = false;
  final double _nearbyRadiusKm = 10;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });
    final messenger = ScaffoldMessenger.of(context);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied');
      }

      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = position;
      });
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('ไม่สามารถดึงตำแหน่งปัจจุบันได้ กรุณาตรวจสอบการอนุญาต'),
        ),
      );
    } finally {
      setState(() {
        _isLoadingLocation = false;
        if (_currentPosition == null) {
          _onlyNearby = false;
        }
      });
    }
  }


  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'รอแจ้ง';
      case 'in_progress':
        return 'กำลังดำเนินการ';
      case 'resolved':
        return 'แก้ไขแล้ว';
      case 'completed':
        return 'เสร็จสิ้น';
      case 'closed':
        return 'ปิดเหตุ';
      default:
        return 'ไม่ทราบสถานะ';
    }
  }

  Future<void> _updateIncidentStatus(String incidentId, String newStatus, {String? fixerImage, String? fixerDetails}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final messenger = ScaffoldMessenger.of(context);

    try {
      Map<String, dynamic> updateData = {
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (newStatus == 'in_progress') {
        updateData['fixerId'] = user.uid;
        updateData['fixerEmail'] = user.email;
        if (fixerImage != null) updateData['fixerImageUrl'] = fixerImage;
        if (fixerDetails != null) updateData['fixerDetails'] = fixerDetails;
      }

      await _firestore.collection('incidents').doc(incidentId).update(updateData);

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('สถานะอัปเดตเป็น${_getStatusText(newStatus)}แล้ว')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('อัปเดตสถานะไม่สำเร็จ กรุณาลองใหม่อีกครั้ง'),
        ),
      );
    }
  }

  Future<void> _showFixerDialog(String incidentId) async {
    final TextEditingController detailsController = TextEditingController();
    File? selectedImage;
    final ImagePicker picker = ImagePicker();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('รายละเอียดการซ่อมแซม'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: detailsController,
                  decoration: const InputDecoration(
                    labelText: 'รายละเอียดการซ่อมแซม',
                    hintText: 'อธิบายขั้นตอนการแก้ปัญหา',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                if (selectedImage != null) ...[
                  Container(
                    height: 100,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      image: DecorationImage(
                        image: FileImage(selectedImage!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                ElevatedButton.icon(
                  onPressed: () async {
                    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                    if (image != null) {
                      setDialogState(() {
                        selectedImage = File(image.path);
                      });
                    }
                  },
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('เลือกรูปภาพ'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                if (detailsController.text.trim().isEmpty) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('กรุณากรอกรายละเอียดการซ่อมแซม')),
                  );
                  return;
                }

                String? imageUrl;
                if (selectedImage != null) {
                  final user = FirebaseAuth.instance.currentUser!;
                  final timestamp = DateTime.now().millisecondsSinceEpoch;
                  imageUrl = await CloudinaryService.uploadProfileImage(
                    selectedImage!, 
                    'fixer_${user.uid}_$timestamp'
                  );
                }

                navigator.pop();
                await _updateIncidentStatus(
                  incidentId, 
                  'in_progress',
                  fixerImage: imageUrl,
                  fixerDetails: detailsController.text.trim(),
                );
              },
              child: const Text('ยืนยัน'),
            ),
          ],
        ),
      ),
    );
  }

  Stream<QuerySnapshot> _getIncidentsStream() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Stream.empty();
    }

    // Always use simple query with only reporterId filter to avoid composite index
    // We'll handle status filtering and sorting in the UI
    return _firestore.collection('incidents')
        .where('reporterId', isEqualTo: currentUser.uid)
        .snapshots();
  }

  double? _calculateDistanceKm(dynamic lat, dynamic lng) {
    if (_currentPosition == null || lat is! num || lng is! num) return null;
    const double earthRadius = 6371;
    final double latDiff = _degreesToRadians(lat.toDouble() - _currentPosition!.latitude);
    final double lngDiff = _degreesToRadians(lng.toDouble() - _currentPosition!.longitude);
    final double a = sin(latDiff / 2) * sin(latDiff / 2) +
        cos(_degreesToRadians(_currentPosition!.latitude)) * cos(_degreesToRadians(lat.toDouble())) *
            sin(lngDiff / 2) * sin(lngDiff / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  Widget _buildFilterControls(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.filter_list, size: 20),
              const SizedBox(width: 8),
              const Text('สถานะ: '),
              Expanded(
                child: DropdownButton<String>(
                  value: _selectedStatus,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('ทั้งหมด')),
                    DropdownMenuItem(value: 'pending', child: Text('รอการตรวจสอบ')),
                    DropdownMenuItem(value: 'in_progress', child: Text('กำลังดำเนินการ')),
                    DropdownMenuItem(value: 'completed', child: Text('เสร็จสิ้น')),
                    DropdownMenuItem(value: 'closed', child: Text('ปิดเหตุ')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedStatus = value!;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'ค้นหาหมุดหรือที่อยู่',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _searchQuery = '';
                          _searchController.clear();
                        });
                      },
                    )
                  : null,
              filled: true,
              fillColor: isDark ? Colors.grey[900] : Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'เฉพาะเหตุภายใน ${_nearbyRadiusKm.toStringAsFixed(0)} กม. รอบตำแหน่งฉัน',
                  style: TextStyle(
                    color: isDark ? Colors.grey[300] : Colors.black87,
                    fontSize: 13,
                  ),
                ),
              ),
              Switch.adaptive(
                value: _onlyNearby && _currentPosition != null,
                onChanged: _currentPosition == null
                    ? null
                    : (value) {
                        setState(() {
                          _onlyNearby = value;
                        });
                      },
              ),
            ],
          ),
          if (_currentPosition == null)
            Text(
              'เปิดการระบุตำแหน่งเพื่อใช้ตัวกรองรัศมี',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);
    final isDark = themeService.isDarkMode;
    
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Colors.tealAccent, Colors.cyan],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds),
            child: const Text(
              'เหตุที่ฉันแจ้ง',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          backgroundColor: isDark ? Colors.black.withValues(alpha: 0.9) : Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark ? [
                  Colors.black.withValues(alpha: 0.9),
                  Colors.grey[900]!.withValues(alpha: 0.9),
                ] : [
                  Colors.white,
                  Colors.grey[50]!,
                ],
              ),
            ),
          ),
          actions: [
            IconButton(
              onPressed: _getCurrentLocation,
              icon: _isLoadingLocation 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
            ),
          ],
        ),
        body: Column(
          children: [
            // Filter controls
            _buildFilterControls(isDark),
            // Incidents list
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _getIncidentsStream(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text('เกิดข้อผิดพลาดในการโหลดข้อมูล'),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  List<QueryDocumentSnapshot> incidents = snapshot.data?.docs ?? [];

                  // Filter by status if not 'all'
                  List<QueryDocumentSnapshot> filteredIncidents = incidents;
                  if (_selectedStatus != 'all') {
                    filteredIncidents = filteredIncidents.where((incident) {
                      final data = incident.data() as Map<String, dynamic>;
                      final status = data['status'] ?? 'pending';
                      return status == _selectedStatus;
                    }).toList();
                  }

                  final query = _searchQuery.trim().toLowerCase();
                  if (query.isNotEmpty) {
                    filteredIncidents = filteredIncidents.where((incident) {
                      final data = incident.data() as Map<String, dynamic>;
                      final searchable = <String?>[
                        data['title']?.toString(),
                        data['description']?.toString(),
                        data['formattedAddress']?.toString(),
                      ];
                      final address = data['address'];
                      if (address is Map<String, dynamic>) {
                        searchable.addAll([
                          address['houseNumber']?.toString(),
                          address['road']?.toString(),
                          address['subdistrict']?.toString(),
                          address['district']?.toString(),
                          address['province']?.toString(),
                        ]);
                      }
                      return searchable.whereType<String>().any((value) => value.toLowerCase().contains(query));
                    }).toList();
                  }

                  if (_onlyNearby && _currentPosition != null) {
                    filteredIncidents = filteredIncidents.where((incident) {
                      final data = incident.data() as Map<String, dynamic>;
                      final distance = _calculateDistanceKm(data['latitude'], data['longitude']);
                      return distance != null && distance <= _nearbyRadiusKm;
                    }).toList();
                  }

                  if (filteredIncidents.isEmpty) {
                    String emptyMessage = 'ยังไม่มีการแจ้งเหตุของคุณ';
                    if (query.isNotEmpty || (_onlyNearby && _currentPosition != null)) {
                      emptyMessage = 'ไม่พบเหตุที่ตรงกับคำค้นหาหรือรัศมีที่เลือก';
                    } else if (_selectedStatus != 'all') {
                      emptyMessage = 'ไม่พบเหตุสถานะ ${_getStatusText(_selectedStatus)}';
                    }
                    return Center(
                      child: Text(
                        emptyMessage,
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.grey[600] : Colors.black54,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  if (_onlyNearby && _currentPosition != null) {
                    filteredIncidents.sort((a, b) {
                      final dataA = a.data() as Map<String, dynamic>;
                      final dataB = b.data() as Map<String, dynamic>;
                      final distanceA = _calculateDistanceKm(dataA['latitude'], dataA['longitude']) ?? double.infinity;
                      final distanceB = _calculateDistanceKm(dataB['latitude'], dataB['longitude']) ?? double.infinity;
                      return distanceA.compareTo(distanceB);
                    });
                  } else {
                    // Always sort incidents by timestamp (descending order - newest first)
                    filteredIncidents.sort((a, b) {
                      final aTimestamp = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                      final bTimestamp = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                      
                      if (aTimestamp == null && bTimestamp == null) return 0;
                      if (aTimestamp == null) return 1;
                      if (bTimestamp == null) return -1;
                      
                      return bTimestamp.compareTo(aTimestamp); // Descending order
                    });
                  }

                  return ListView.builder(
                    itemCount: filteredIncidents.length,
                    itemBuilder: (context, index) {
                      final incident = filteredIncidents[index];
                      final data = incident.data() as Map<String, dynamic>;
                      final incidentId = incident.id;

                      // Ensure data has proper field names for compatibility
                      final normalizedData = Map<String, dynamic>.from(data);
                      if (!normalizedData.containsKey('reporterId') && normalizedData.containsKey('reportedBy')) {
                        normalizedData['reporterId'] = normalizedData['reportedBy'];
                      }
                      if (!normalizedData.containsKey('reporterEmail') && normalizedData.containsKey('reportedBy')) {
                        // Try to get email from user document if not available
                        normalizedData['reporterEmail'] = 'ไม่ทราบ';
                      }
                      
                      return _IncidentCard(
                        incidentId: incidentId,
                        data: normalizedData,
                        currentPosition: _currentPosition,
                        onStatusUpdate: _updateIncidentStatus,
                        onShowFixerDialog: _showFixerDialog,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncidentCard extends StatelessWidget {
  final String incidentId;
  final Map<String, dynamic> data;
  final Position? currentPosition;
  final Function(String, String, {String? fixerImage, String? fixerDetails}) onStatusUpdate;
  final Function(String) onShowFixerDialog;

  const _IncidentCard({
    required this.incidentId,
    required this.data,
    this.currentPosition,
    required this.onStatusUpdate,
    required this.onShowFixerDialog,
  });

  double? _getDistance() {
    if (currentPosition == null) return null;
    
    final lat = data['latitude'] as double?;
    final lng = data['longitude'] as double?;
    
    if (lat == null || lng == null) return null;
    
    const double earthRadius = 6371;
    double dLat = _degreesToRadians(lat - currentPosition!.latitude);
    double dLon = _degreesToRadians(lng - currentPosition!.longitude);
    
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(currentPosition!.latitude)) * cos(_degreesToRadians(lat)) *
        sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  String? _getReadableAddress() {
    final formatted = data['formattedAddress'];
    if (formatted is String && formatted.trim().isNotEmpty) {
      return formatted;
    }
    final address = data['address'];
    if (address is Map<String, dynamic>) {
      final parts = [
        address['houseNumber'],
        address['road'],
        address['subdistrict'],
        address['district'],
        address['province'],
        address['postcode'],
      ]
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      if (parts.isNotEmpty) {
        return parts.join(' ');
      }
    }
    return null;
  }

  String? _getCoordinateText() {
    final lat = data['latitude'];
    final lng = data['longitude'];
    if (lat is num && lng is num) {
      return 'ละติจูด ${lat.toStringAsFixed(4)}, ลองจิจูด ${lng.toStringAsFixed(4)}';
    }
    return null;
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'รอแจ้ง';
      case 'in_progress':
        return 'กำลังดำเนินการ';
      case 'completed':
        return 'เสร็จสิ้น';
      default:
        return 'ไม่ทราบสถานะ';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  List<DisabilityTypeOption> _getDisabilityTypes() {
    final types = data['affectedDisabilityTypes'];
    if (types is Iterable) {
      return types
          .map((value) => DisabilityTypes.get(value?.toString()))
          .whereType<DisabilityTypeOption>()
          .toList();
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);
    final isDark = themeService.isDarkMode;
    final currentUser = FirebaseAuth.instance.currentUser;
    final status = data['status'] ?? 'pending';
    final distance = _getDistance();
    final disabilityTypes = _getDisabilityTypes();
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 8,
        shadowColor: Colors.tealAccent.withValues(alpha: 0.2),
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark ? [
                const Color(0xFF2B2B2B),
                Colors.grey[800]!.withValues(alpha: 0.9),
              ] : [
                Colors.white,
                Colors.grey[50]!,
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _getStatusColor(status).withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getStatusColor(status),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _getStatusText(status),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (distance != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.tealAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${distance.toStringAsFixed(1)} กม.',
                          style: TextStyle(
                            color: isDark ? Colors.tealAccent : Colors.teal,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  data['title'] ?? 'ไม่มีหัวข้อ',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  data['description'] ?? 'ไม่มีรายละเอียด',
                  style: TextStyle(
                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (disabilityTypes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: disabilityTypes.map((type) {
                      final bgColor = type.color.withValues(alpha: isDark ? 0.25 : 0.15);
                      return Chip(
                        label: Text(
                          type.label,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        avatar: Icon(type.icon, size: 16, color: type.color),
                        backgroundColor: bgColor,
                        shape: StadiumBorder(
                          side: BorderSide(color: type.color.withValues(alpha: 0.6)),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                if (_getReadableAddress() != null || _getCoordinateText() != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 16, color: isDark ? Colors.red[200] : Colors.red),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _getReadableAddress() ?? _getCoordinateText()!,
                          style: TextStyle(
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (data['imageUrl'] != null && data['imageUrl'].toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: data['imageUrl'],
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                      errorWidget: (context, url, error) => Container(
                        height: 150,
                        color: isDark ? Colors.grey[800] : Colors.grey[300],
                        child: Icon(Icons.broken_image, size: 50, color: isDark ? Colors.grey[600] : Colors.grey[500]),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.person, size: 16, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                    const SizedBox(width: 4),
                    FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('users')
                      .doc(data['reporterId'] ?? data['reportedBy'])
                      .get(),
                  builder: (context, snapshot) {
                    final userData = snapshot.data?.data() as Map<String, dynamic>?;
                    final reporterName = userData?['email']?.split('@')[0] ?? 
                                       data['reporterEmail']?.split('@')[0] ?? 
                                       'ไม่ทราบผู้แจ้ง';
                    
                    return Text(
                      reporterName,
                          style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontSize: 12,
                      ),
                    );
                  },
                ),
                    const Spacer(),
                    if (data['timestamp'] != null)
                      Text(
                        DateFormat('dd/MM/yy HH:mm').format((data['timestamp'] as Timestamp).toDate()),
                        style: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => IncidentDetailScreen(
                                incident: data,
                                incidentId: incidentId,
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.tealAccent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('ดูรายละเอียด'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Action buttons based on user role and status
                    if (currentUser?.uid == (data['reporterId'] ?? data['reportedBy'])) ...[
                      // Reporter can change their own incident status
                      Expanded(
                        child: PopupMenuButton<String>(
                          onSelected: (newStatus) => onStatusUpdate(incidentId, newStatus),
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'pending',
                              child: Row(
                                children: [
                                  Icon(Icons.pending, color: Colors.orange),
                                  SizedBox(width: 8),
                                  Text('รอแจ้ง'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'in_progress',
                              child: Row(
                                children: [
                                  Icon(Icons.work, color: Colors.blue),
                                  SizedBox(width: 8),
                                  Text('กำลังดำเนินการ'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'completed',
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle, color: Colors.green),
                                  SizedBox(width: 8),
                                  Text('เสร็จสิ้น'),
                                ],
                              ),
                            ),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.tealAccent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.edit, color: Colors.black, size: 16),
                                SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'เปลี่ยนสถานะ',
                                    style: TextStyle(color: Colors.black, fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ] else if (status == 'pending') ...[
                      // Non-reporters can take jobs
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => onShowFixerDialog(incidentId),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          //TODO dont know this function . check later
                          child: const Text('ขอรับงาน'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

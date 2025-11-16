import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../constants/disability_types.dart';
import '../services/theme_service.dart';
import 'comment_screen.dart';

class IncidentDetailScreen extends StatefulWidget {
  final Map<String, dynamic> incident;
  final String incidentId;
  
  const IncidentDetailScreen({
    super.key,
    required this.incident,
    required this.incidentId,
  });

  @override
  State<IncidentDetailScreen> createState() => _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends State<IncidentDetailScreen> {
  bool _isBookmarked = false;
  bool _bookmarkBusy = false;

  @override
  void initState() {
    super.initState();
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final bookmarkedBy = widget.incident['bookmarkedBy'];
    if (userId != null && bookmarkedBy is Iterable) {
      _isBookmarked = bookmarkedBy.map((e) => e?.toString()).contains(userId);
    }
  }

  Future<void> _deleteIncident(BuildContext context) async {
    try {
      await FirebaseFirestore.instance
          .collection('incidents')
          .doc(widget.incidentId)
          .delete();
      
      if (context.mounted) {
        Navigator.pop(context, true); // Return true to indicate deletion
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ลบเหตุเรียบร้อยแล้ว')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ลบเหตุไม่สำเร็จ กรุณาลองใหม่อีกครั้ง')),
        );
      }
    }
  }

  Future<void> _approveCompletion(BuildContext context) async {
    try {
      await FirebaseFirestore.instance
          .collection('incidents')
          .doc(widget.incidentId)
          .update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
        'approvedBy': FirebaseAuth.instance.currentUser?.uid,
      });
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('งานได้รับการอนุมัติเรียบร้อยแล้ว')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถอนุมัติการทำงานได้ กรุณาลองใหม่อีกครั้ง')),
        );
      }
    }
  }

  String _getStatusText(String? status) {
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

  Color _getStatusColor(String? status) {
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

  String? _getReadableAddress() {
    final formatted = widget.incident['formattedAddress'];
    if (formatted is String && formatted.trim().isNotEmpty) {
      return formatted;
    }

    final rawAddress = widget.incident['address'];
    if (rawAddress is Map<String, dynamic>) {
      final parts = [
        rawAddress['houseNumber'],
        rawAddress['road'],
        rawAddress['subdistrict'],
        rawAddress['district'],
        rawAddress['province'],
        rawAddress['postcode'],
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
    final lat = widget.incident['latitude'];
    final lng = widget.incident['longitude'];
    if (lat is num && lng is num) {
      return 'ละติจูด ${lat.toStringAsFixed(4)}, ลองจิจูด ${lng.toStringAsFixed(4)}';
    }
    return null;
  }

  List<DisabilityTypeOption> _getDisabilityTypes() {
    final types = widget.incident['affectedDisabilityTypes'];
    if (types is Iterable) {
      return types
          .map((value) => DisabilityTypes.get(value?.toString()))
          .whereType<DisabilityTypeOption>()
          .toList();
    }
    return [];
  }

  Future<void> _toggleBookmark() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _bookmarkBusy) return;
    setState(() {
      _bookmarkBusy = true;
    });
    try {
      await FirebaseFirestore.instance.collection('incidents').doc(widget.incidentId).update({
        'bookmarkedBy': _isBookmarked
            ? FieldValue.arrayRemove([user.uid])
            : FieldValue.arrayUnion([user.uid]),
      });
      if (mounted) {
        setState(() {
          _isBookmarked = !_isBookmarked;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกหมุดไม่สำเร็จ กรุณาลองอีกครั้ง')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _bookmarkBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reportedAt =
        widget.incident['reportedAt'] as Timestamp? ?? widget.incident['timestamp'] as Timestamp?;
    final imageUrl = widget.incident['imageUrl'] as String?;
    final currentUser = FirebaseAuth.instance.currentUser;
    final isOwner = currentUser?.uid == widget.incident['reportedBy'];
    final themeService = Provider.of<ThemeService>(context);
    final isDark = themeService.isDarkMode;
    final addressText = _getReadableAddress();
    final coordinateText = _getCoordinateText();
    final disabilityTypes = _getDisabilityTypes();
    final canBookmark = currentUser != null;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.incident['title'] ?? 'รายละเอียดเหตุ'),
        backgroundColor: isDark ? Colors.black : Colors.white,
        actions: [
          IconButton(
            tooltip: 'ดูความคิดเห็น',
            icon: Icon(
              Icons.chat_bubble_outline,
              color: isDark ? Colors.grey[300] : Colors.grey[700],
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CommentScreen(incidentId: widget.incidentId),
                ),
              );
            },
          ),
          if (canBookmark)
            IconButton(
              icon: Icon(
                _isBookmarked ? Icons.star : Icons.star_border,
                color: _isBookmarked ? Colors.amber : (isDark ? Colors.grey[400] : Colors.grey[700]),
              ),
              onPressed: _bookmarkBusy ? null : _toggleBookmark,
            ),
          if (isOwner)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: isDark ? Colors.grey[900] : Colors.white,
                    title: Text(
                      'ลบเหตุ',
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    ),
                    content: Text(
                      'ยืนยันการลบเหตุนี้หรือไม่? การกระทำนี้ไม่สามารถย้อนกลับได้',
                      style: TextStyle(color: isDark ? Colors.grey[300] : Colors.black87),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'ยกเลิก',
                          style: TextStyle(color: isDark ? Colors.grey[400] : Colors.black54),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _deleteIncident(context);
                        },
                        child: const Text('ลบ', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _getCategoryColor(widget.incident['category']),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                widget.incident['category'] ?? 'ไม่ทราบประเภท',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (disabilityTypes.isNotEmpty) ...[
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
                    avatar: Icon(type.icon, size: 18, color: type.color),
                    backgroundColor: bgColor,
                    shape: StadiumBorder(
                      side: BorderSide(color: type.color.withValues(alpha: 0.6)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],
            
            // Title
            Text(
              widget.incident['title'] ?? 'ยังไม่มีชื่อเหตุ',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            
            // Location
            if (addressText != null || coordinateText != null) ...[
              Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.red, size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      addressText ?? coordinateText!,
                      style: TextStyle(color: isDark ? Colors.grey : Colors.black54),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            
            // Reported by and time
            FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(widget.incident['reportedBy'])
                  .get(),
              builder: (context, snapshot) {
                final userData = snapshot.data?.data() as Map<String, dynamic>?;
                final reporterName = userData?['email']?.split('@')[0] ?? widget.incident['reporterEmail']?.split('@')[0] ?? 'ไม่ทราบผู้ใช้';
                
                return Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                      child: userData?['profileImageUrl'] != null
                          ? ClipOval(
                              child: CachedNetworkImage(
                                imageUrl: userData!['profileImageUrl'],
                                width: 24,
                                height: 24,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => const CircularProgressIndicator(),
                                errorWidget: (context, url, error) => const Icon(Icons.person, size: 16),
                              ),
                            )
                          : const Icon(Icons.person, size: 16),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'รายงานโดย $reporterName',
                      style: TextStyle(color: isDark ? Colors.grey : Colors.black54),
                    ),
                    if (reportedAt != null) ...[
                      Text(' • ', style: TextStyle(color: isDark ? Colors.grey : Colors.black54)),
                      Text(
                        DateFormat('MMM d, yyyy HH:mm').format(reportedAt.toDate()),
                        style: TextStyle(color: isDark ? Colors.grey : Colors.black54),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            
            // Image if available
            if (imageUrl != null && imageUrl.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                  errorWidget: (context, url, error) => Container(
                    height: 200,
                    color: isDark ? Colors.grey[800] : Colors.grey[200],
                    child: const Center(child: Icon(Icons.broken_image)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            
            // Description
            if (widget.incident['description'] != null &&
                widget.incident['description'].toString().isNotEmpty) ...[
              Text(
                'รายละเอียด',
                style: TextStyle(
                  fontSize: 18, 
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.incident['description'],
                style: TextStyle(
                  fontSize: 16, 
                  height: 1.5,
                  color: isDark ? Colors.grey[300] : Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
            ],
            
            // Status
            Row(
              children: [
                Text('สถานะ: ', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getStatusColor(widget.incident['status']),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _getStatusText(widget.incident['status']),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Fixer information (if in progress or completed)
            if (widget.incident['fixerId'] != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.blue.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.build, color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'ผู้แก้ไข',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .doc(widget.incident['fixerId'])
                          .get(),
                      builder: (context, snapshot) {
                        final userData = snapshot.data?.data() as Map<String, dynamic>?;
                        final fixerName = userData?['email']?.split('@')[0] ?? 'ไม่ทราบชื่อ';
                        
                        return Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: isDark ? Colors.grey[700] : Colors.grey[300],
                              child: userData?['profileImageUrl'] != null
                                  ? ClipOval(
                                      child: CachedNetworkImage(
                                        imageUrl: userData!['profileImageUrl'],
                                        width: 32,
                                        height: 32,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) => const CircularProgressIndicator(),
                                        errorWidget: (context, url, error) => const Icon(Icons.person, size: 20),
                                      ),
                                    )
                                  : const Icon(Icons.person, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              fixerName,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    if (widget.incident['fixerDetails'] != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'รายละเอียดการแก้ไข:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.incident['fixerDetails'],
                        style: TextStyle(
                          color: isDark ? Colors.grey[300] : Colors.grey[700],
                        ),
                      ),
                    ],
                    if (widget.incident['fixerImageUrl'] != null) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: widget.incident['fixerImageUrl'],
                          width: double.infinity,
                          height: 150,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                          errorWidget: (context, url, error) => Container(
                            height: 150,
                            color: isDark ? Colors.grey[700] : Colors.grey[200],
                            child: const Center(child: Icon(Icons.broken_image)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            
            // Approval button for reporter when work is submitted
            if (widget.incident['status'] == 'in_progress' && 
                widget.incident['fixerId'] != null && 
                widget.incident['fixerDetails'] != null &&
                currentUser?.uid == widget.incident['reportedBy']) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.green, Colors.lightGreen],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white, size: 32),
                    const SizedBox(height: 8),
                    const Text(
                      'งานได้รับการส่งมอบแล้ว',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'กรุณาตรวจสอบและอนุมัติการทำงาน',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: isDark ? Colors.grey[900] : Colors.white,
                            title: Text(
                              'อนุมัติการทำงาน',
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                            ),
                            content: Text(
                              'คุณต้องการอนุมัติการทำงานนี้และเปลี่ยนสถานะเป็น "เสร็จสิ้น" หรือไม่?',
                              style: TextStyle(color: isDark ? Colors.grey[300] : Colors.black87),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(
                                  'ยกเลิก',
                                  style: TextStyle(color: isDark ? Colors.grey[400] : Colors.black54),
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _approveCompletion(context);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('อนุมัติ'),
                              ),
                            ],
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      child: const Text(
                        'อนุมัติการทำงาน',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
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

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';

class IncidentReportScreen extends StatefulWidget {
  const IncidentReportScreen({super.key});

  @override
  State<IncidentReportScreen> createState() => _IncidentReportScreenState();
}

class _IncidentReportScreenState extends State<IncidentReportScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  List<Map<String, dynamic>> _incidents = [];
  bool _isLoading = true;
  String _selectedFilter = 'All';
  
  final List<String> _statusFilters = [
    'All',
    'pending',
    'in_progress', 
    'resolved',
    'closed'
  ];
  
  final Map<String, Color> _statusColors = {
    'pending': Colors.orange,
    'in_progress': Colors.blue,
    'resolved': Colors.green,
    'closed': Colors.grey,
  };
  
  final Map<String, String> _statusLabels = {
    'pending': 'รอดำเนินการ',
    'in_progress': 'กำลังดำเนินการ',
    'resolved': 'แก้ไขแล้ว',
    'closed': 'ปิดเหตุ',
  };
  
  final Map<String, IconData> _categoryIcons = {
    'Traffic': Icons.traffic,
    'Accident': Icons.car_crash,
    'Road Work': Icons.construction,
    'Hazard': Icons.warning,
    'Crime': Icons.security,
    'Emergency': Icons.emergency,
    'Other': Icons.report_problem,
  };

  final Map<String, String> _categoryLabels = {
    'Traffic': 'การจราจร',
    'Accident': 'อุบัติเหตุ',
    'Road Work': 'ซ่อมถนน',
    'Hazard': 'จุดอันตราย',
    'Crime': 'เหตุอาชญากรรม',
    'Emergency': 'เหตุฉุกเฉิน',
    'Other': 'อื่นๆ',
  };

  String _getStatusLabel(String status) => _statusLabels[status] ?? 'ไม่ทราบสถานะ';
  String _getCategoryLabel(String category) => _categoryLabels[category] ?? category;

  @override
  void initState() {
    super.initState();
    _loadIncidents();
  }
  
  Future<void> _loadIncidents() async {
    try {
      final snapshot = await _firestore
          .collection('incidents')
          .orderBy('reportedAt', descending: true)
          .get();
      
      setState(() {
        _incidents = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถโหลดรายการเหตุได้ กรุณาลองใหม่อีกครั้ง')),
        );
      }
    }
  }
  
  List<Map<String, dynamic>> get _filteredIncidents {
    if (_selectedFilter == 'All') {
      return _incidents;
    }
    return _incidents.where((incident) => incident['status'] == _selectedFilter).toList();
  }
  
  String _getTimeAgo(Timestamp? timestamp) {
    if (timestamp == null) return 'ไม่ทราบเวลา';
    
    final now = DateTime.now();
    final date = timestamp.toDate();
    final difference = now.difference(date);
    
    if (difference.inDays > 0) {
      return '${difference.inDays} วันก่อน';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ชั่วโมงก่อน';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} นาทีก่อน';
    } else {
      return 'เพิ่งสักครู่';
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);
    final isDark = themeService.isDarkMode;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('สถานะเหตุแจ้ง', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: isDark ? Colors.black : Colors.white,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.filter_list, color: isDark ? Colors.tealAccent : Colors.teal),
            onSelected: (value) {
              setState(() {
                _selectedFilter = value;
              });
            },
            itemBuilder: (context) => _statusFilters.map((filter) {
              return PopupMenuItem(
                value: filter,
                child: Row(
                  children: [
                    if (filter != 'All') 
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _statusColors[filter] ?? Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                    if (filter != 'All') const SizedBox(width: 8),
                    Text(filter == 'All' ? 'ทุกสถานะ' : _getStatusLabel(filter)),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredIncidents.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.report_outlined,
                        size: 64,
                        color: isDark ? Colors.grey[600] : Colors.grey[500],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'ไม่พบเหตุที่รายงาน',
                        style: TextStyle(
                          fontSize: 18,
                          color: isDark ? Colors.grey[400] : Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _selectedFilter == 'All' 
                            ? 'ยังไม่มีการแจ้งเหตุ'
                            : 'ไม่พบเหตุสถานะ ${_getStatusLabel(_selectedFilter)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.grey[500] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadIncidents,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _filteredIncidents.length,
                    itemBuilder: (context, index) {
                      final incident = _filteredIncidents[index];
                      final status = incident['status'] ?? 'pending';
                      final category = incident['category'] ?? 'Other';
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        elevation: 2,
                        color: isDark ? Colors.grey[850] : Colors.white,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _statusColors[status]?.withValues(alpha: 0.2) ?? Colors.grey.withValues(alpha: 0.2),
                            child: Icon(
                              _categoryIcons[category] ?? Icons.report_problem,
                              color: _statusColors[status] ?? Colors.grey,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            incident['title'] ?? 'ยังไม่มีชื่อเหตุ',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                incident['description'] ?? 'ไม่มีรายละเอียด',
                                style: TextStyle(
                                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                                  fontSize: 14,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _statusColors[status]?.withValues(alpha: 0.2) ?? Colors.grey.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      _getStatusLabel(status),
                                      style: TextStyle(
                                        color: _statusColors[status] ?? Colors.grey,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _getCategoryLabel(category),
                                    style: TextStyle(
                                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _getTimeAgo(incident['reportedAt']),
                                style: TextStyle(
                                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (incident['latitude'] != null && incident['longitude'] != null)
                                Icon(
                                  Icons.location_on,
                                  size: 16,
                                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                                ),
                            ],
                          ),
                          onTap: () {
                            // TODO: Navigate to incident detail screen
                            _showIncidentDetails(incident);
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
  
  void _showIncidentDetails(Map<String, dynamic> incident) {
    final themeService = Provider.of<ThemeService>(context, listen: false);
    final isDark = themeService.isDarkMode;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[600] : Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      incident['title'] ?? 'ยังไม่มีชื่อเหตุ',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _statusColors[incident['status']]?.withValues(alpha: 0.2) ?? Colors.grey.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            _getStatusLabel(incident['status'] ?? 'pending'),
                            style: TextStyle(
                              color: _statusColors[incident['status']] ?? Colors.grey,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _getCategoryLabel(incident['category'] ?? 'Other'),
                          style: TextStyle(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (incident['description'] != null && incident['description'].toString().isNotEmpty) ...[
                      Text(
                        'รายละเอียด',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        incident['description'],
                        style: TextStyle(
                          color: isDark ? Colors.grey[300] : Colors.grey[700],
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (incident['latitude'] != null && incident['longitude'] != null) ...[
                      Text(
                        'ตำแหน่ง',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[800] : Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'ละติจูด ${incident['latitude'].toStringAsFixed(4)}, ลองจิจูด ${incident['longitude'].toStringAsFixed(4)}',
                                style: TextStyle(
                                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    Text(
                      'รายงานเมื่อ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getTimeAgo(incident['reportedAt']),
                      style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    }
}

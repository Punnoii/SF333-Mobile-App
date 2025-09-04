import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';

class IncidentDetailScreen extends StatelessWidget {
  final Map<String, dynamic> incident;
  final String incidentId;
  
  const IncidentDetailScreen({
    super.key,
    required this.incident,
    required this.incidentId,
  });

  Future<void> _deleteIncident(BuildContext context) async {
    try {
      await FirebaseFirestore.instance
          .collection('incidents')
          .doc(incidentId)
          .delete();
      
      if (context.mounted) {
        Navigator.pop(context, true); // Return true to indicate deletion
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Incident deleted successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting incident: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reportedAt = incident['reportedAt'] as Timestamp?;
    final imageUrl = incident['imageUrl'] as String?;
    final currentUser = FirebaseAuth.instance.currentUser;
    final isOwner = currentUser?.uid == incident['reportedBy'];
    final themeService = Provider.of<ThemeService>(context);
    final isDark = themeService.isDarkMode;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(incident['title'] ?? 'Incident Details'),
        backgroundColor: isDark ? Colors.black : Colors.white,
        actions: [
          if (isOwner)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: isDark ? Colors.grey[900] : Colors.white,
                    title: Text(
                      'Delete Incident',
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    ),
                    content: Text(
                      'Are you sure you want to delete this incident? This action cannot be undone.',
                      style: TextStyle(color: isDark ? Colors.grey[300] : Colors.grey[700]),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'Cancel',
                          style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _deleteIncident(context);
                        },
                        child: const Text('Delete', style: TextStyle(color: Colors.red)),
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
                color: _getCategoryColor(incident['category']),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                incident['category'] ?? 'Unknown',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Title
            Text(
              incident['title'] ?? 'No Title',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            
            // Location
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.red, size: 16),
                const SizedBox(width: 4),
                Text(
                  'Lat: ${incident['latitude']?.toStringAsFixed(4)}, Lng: ${incident['longitude']?.toStringAsFixed(4)}',
                  style: TextStyle(color: isDark ? Colors.grey : Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Reported by and time
            FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(incident['reportedBy'])
                  .get(),
              builder: (context, snapshot) {
                final userData = snapshot.data?.data() as Map<String, dynamic>?;
                final reporterName = userData?['email']?.split('@')[0] ?? 'Unknown User';
                
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
                      'Reported by $reporterName',
                      style: TextStyle(color: isDark ? Colors.grey : Colors.grey[600]),
                    ),
                    if (reportedAt != null) ...[
                      Text(' • ', style: TextStyle(color: isDark ? Colors.grey : Colors.grey[600])),
                      Text(
                        DateFormat('MMM d, yyyy HH:mm').format(reportedAt.toDate()),
                        style: TextStyle(color: isDark ? Colors.grey : Colors.grey[600]),
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
            if (incident['description'] != null && incident['description'].toString().isNotEmpty) ...[
              Text(
                'Description',
                style: TextStyle(
                  fontSize: 18, 
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                incident['description'],
                style: TextStyle(
                  fontSize: 16, 
                  height: 1.5,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
              const SizedBox(height: 20),
            ],
            
            // Status
            Row(
              children: [
                Text('Status: ', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: incident['status'] == 'active' ? Colors.green : Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    incident['status']?.toUpperCase() ?? 'UNKNOWN',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
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

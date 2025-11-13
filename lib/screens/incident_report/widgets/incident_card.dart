import 'package:flutter/material.dart';

import '../../../models/incident.dart';
import '../incident_report_styles.dart';

class IncidentCard extends StatelessWidget {
  const IncidentCard({
    super.key,
    required this.incident,
    required this.isDark,
    required this.statusLabel,
    required this.categoryLabel,
    required this.locationPreview,
    required this.distanceKm,
    required this.reportedText,
    required this.onTap,
  });

  final Incident incident;
  final bool isDark;
  final String statusLabel;
  final String categoryLabel;
  final String? locationPreview;
  final double? distanceKm;
  final String reportedText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = kIncidentStatusColors[incident.status] ?? Colors.grey;
    final categoryIcon = kIncidentCategoryIcons[incident.category] ?? Icons.report_problem;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 2,
      color: isDark ? Colors.grey[850] : Colors.white,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.2),
          child: Icon(
            categoryIcon,
            color: statusColor,
            size: 20,
          ),
        ),
        title: Text(
          incident.title.isNotEmpty ? incident.title : 'ยังไม่มีชื่อเหตุ',
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
              incident.description.isNotEmpty ? incident.description : 'ไม่มีรายละเอียด',
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
                    color: statusColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  categoryLabel,
                  style: TextStyle(
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            if (locationPreview != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 14, color: Colors.red),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      locationPreview!,
                      style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              reportedText,
              style: TextStyle(
                color: isDark ? Colors.grey[500] : Colors.grey[600],
                fontSize: 12,
              ),
            ),
            if (distanceKm != null) ...[
              const SizedBox(height: 4),
              Text(
                '${distanceKm!.toStringAsFixed(1)} กม.',
                style: TextStyle(
                  color: isDark ? Colors.tealAccent : Colors.teal,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

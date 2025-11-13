import 'package:flutter/material.dart';

const Map<String, Color> kIncidentStatusColors = {
  'pending': Colors.orange,
  'in_progress': Colors.blue,
  'resolved': Colors.green,
  'closed': Colors.grey,
};

const Map<String, IconData> kIncidentCategoryIcons = {
  'Traffic': Icons.traffic,
  'Accident': Icons.car_crash,
  'Road Work': Icons.construction,
  'Hazard': Icons.warning,
  'Crime': Icons.security,
  'Emergency': Icons.emergency,
  'Other': Icons.report_problem,
};

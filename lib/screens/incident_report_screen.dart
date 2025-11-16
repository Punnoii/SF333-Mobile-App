import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/incident.dart';
import '../repositories/incident_repository.dart';
import '../services/theme_service.dart';
import '../viewmodels/incident_report_view_model.dart';
import 'incident_report/incident_report_styles.dart';
import 'incident_report/widgets/incident_card.dart';
import 'incident_report/widgets/incident_empty_state.dart';
import 'incident_report/widgets/incident_filters_bar.dart';
import 'incident_detail_screen.dart';

class IncidentReportScreen extends StatelessWidget {
  const IncidentReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
          IncidentReportViewModel(repository: IncidentRepository())..loadIncidents(),
      child: const _IncidentReportView(),
    );
  }
}

class _IncidentReportView extends StatefulWidget {
  const _IncidentReportView();

  @override
  State<_IncidentReportView> createState() => _IncidentReportViewState();
}

class _IncidentReportViewState extends State<_IncidentReportView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    final viewModel = context.watch<IncidentReportViewModel>();
    final isDark = themeService.isDarkMode;

    if (_searchController.text != viewModel.searchQuery) {
      _searchController.value = TextEditingValue(
        text: viewModel.searchQuery,
        selection: TextSelection.collapsed(offset: viewModel.searchQuery.length),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final message = viewModel.errorMessage;
      if (message != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        viewModel.clearError();
      }
    });

    final incidents = viewModel.filteredIncidents;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'สถานะเหตุแจ้ง',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: isDark ? Colors.black : Colors.white,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.filter_list, color: isDark ? Colors.tealAccent : Colors.teal),
            initialValue: viewModel.selectedFilter,
            onSelected: viewModel.updateFilter,
            itemBuilder: (context) => viewModel.statusFilters
                .map((filter) {
                  final color = kIncidentStatusColors[filter] ?? Colors.grey;
                  return PopupMenuItem(
                    value: filter,
                    child: Row(
                      children: [
                        if (filter != 'All')
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                        if (filter != 'All') const SizedBox(width: 8),
                        Text(filter == 'All' ? 'ทุกสถานะ' : viewModel.getStatusLabel(filter)),
                      ],
                    ),
                  );
                })
                .toList(),
          ),
        ],
      ),
      body: viewModel.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                IncidentFiltersBar(
                  searchController: _searchController,
                  onSearchChanged: viewModel.updateSearchQuery,
                  onClearSearch: () {
                    _searchController.clear();
                    viewModel.updateSearchQuery('');
                  },
                  isDark: isDark,
                  isLocating: viewModel.isLocating,
                  locationAvailable: viewModel.currentPosition != null,
                  onlyNearby: viewModel.onlyNearby,
                  nearbyRadiusKm: viewModel.nearbyRadiusKm,
                  onRequestLocation: viewModel.requestLocation,
                  onNearbyChanged: (value) {
                    viewModel.setOnlyNearby(value);
                  },
                  hasQuery: viewModel.searchQuery.trim().isNotEmpty,
                ),
                Expanded(
                  child: incidents.isEmpty
                      ? IncidentEmptyState(
                          isDark: isDark,
                          title: 'ไม่พบเหตุที่รายงาน',
                          subtitle: viewModel.searchQuery.trim().isNotEmpty ||
                                  (viewModel.onlyNearby && viewModel.currentPosition != null)
                              ? 'ไม่พบเหตุที่ตรงกับคำค้นหาหรือรัศมีที่เลือก'
                              : viewModel.selectedFilter == 'All'
                                  ? 'ยังไม่มีการแจ้งเหตุ'
                                  : 'ไม่พบเหตุสถานะ ${viewModel.getStatusLabel(viewModel.selectedFilter)}',
                        )
                      : RefreshIndicator(
                          onRefresh: viewModel.refresh,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: incidents.length,
                            itemBuilder: (context, index) {
                              final incident = incidents[index];
                              final locationPreview =
                                  viewModel.getDisplayAddress(incident) ?? _formatCoordinates(incident);
                              final distance = viewModel.calculateDistanceKm(incident);
                              final reportedText =
                                  viewModel.formatTimeAgo(incident.reportedAt?.toDate());
                              final disabilityTypes = viewModel.disabilityConfigs(incident);

                              return IncidentCard(
                                incident: incident,
                                isDark: isDark,
                                statusLabel: viewModel.getStatusLabel(incident.status),
                                categoryLabel: viewModel.getCategoryLabel(incident.category),
                                disabilityTypes: disabilityTypes,
                                locationPreview: locationPreview,
                                distanceKm: distance,
                                reportedText: reportedText,
                                isBookmarked: viewModel.isBookmarked(incident),
                                onToggleBookmark: () => viewModel.toggleBookmark(incident),
                                onTap: () => _openIncidentDetail(context, incident),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  String? _formatCoordinates(Incident incident) {
    if (incident.latitude == null || incident.longitude == null) return null;
    return 'ละติจูด ${incident.latitude!.toStringAsFixed(4)}, ลองจิจูด ${incident.longitude!.toStringAsFixed(4)}';
  }

  Future<void> _openIncidentDetail(BuildContext context, Incident incident) {
    final incidentMap = {
      'title': incident.title,
      'description': incident.description,
      'status': incident.status,
      'category': incident.category,
      'reporterId': incident.reporterId,
      'reporterName': incident.reporterName,
      'reporterEmail': incident.reporterEmail,
      'bookmarkedBy': incident.bookmarkedBy,
      'affectedDisabilityTypes': incident.affectedDisabilityTypes,
      'latitude': incident.latitude,
      'longitude': incident.longitude,
      'reportedAt': incident.reportedAt,
      'timestamp': incident.reportedAt,
      'formattedAddress': incident.formattedAddress,
      'address': incident.address,
    };

    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: true,
        barrierColor: Colors.transparent,
        pageBuilder: (_, __, ___) => IncidentDetailScreen(
          incident: incidentMap,
          incidentId: incident.id,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1, 0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;
          final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }
}

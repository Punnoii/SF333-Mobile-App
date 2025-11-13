import 'package:flutter/material.dart';

class IncidentFiltersBar extends StatelessWidget {
  const IncidentFiltersBar({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.isDark,
    required this.isLocating,
    required this.locationAvailable,
    required this.onlyNearby,
    required this.nearbyRadiusKm,
    required this.onRequestLocation,
    required this.onNearbyChanged,
    required this.hasQuery,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final bool isDark;
  final bool isLocating;
  final bool locationAvailable;
  final bool onlyNearby;
  final double nearbyRadiusKm;
  final Future<void> Function() onRequestLocation;
  final ValueChanged<bool> onNearbyChanged;
  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: 'ค้นหาหมุดหรือที่อยู่',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: hasQuery
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: onClearSearch,
                    )
                  : null,
              filled: true,
              fillColor: isDark ? Colors.grey[900] : Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'เฉพาะเหตุภายใน ${nearbyRadiusKm.toStringAsFixed(0)} กม. รอบตำแหน่งฉัน',
                  style: TextStyle(
                    color: isDark ? Colors.grey[300] : Colors.black87,
                    fontSize: 13,
                  ),
                ),
              ),
              IconButton(
                onPressed: isLocating
                    ? null
                    : () {
                        onRequestLocation();
                      },
                icon: isLocating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                tooltip: 'อัปเดตตำแหน่งปัจจุบัน',
              ),
              Switch.adaptive(
                value: onlyNearby && locationAvailable,
                onChanged: locationAvailable ? onNearbyChanged : null,
              ),
            ],
          ),
          if (!locationAvailable)
            Text(
              'แตะไอคอนตำแหน่งเพื่อเปิดใช้งานตัวกรองระยะ',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
        ],
      ),
    );
  }
}

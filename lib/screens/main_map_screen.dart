import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';
import '../services/location_service.dart';
import '../services/logging_service.dart';
import 'chat_list_screen.dart';
import 'profile_screen.dart';
import 'incident_detail_screen.dart';
import 'login_screen.dart';
import 'incident_report_screen.dart';
import 'incident_form_screen.dart';

class MainMapScreen extends StatefulWidget {
  static const String routeName = '/main';
  const MainMapScreen({super.key});

  @override
  State<MainMapScreen> createState() => _MainMapScreenState();
}

class _MainMapScreenState extends State<MainMapScreen> {
  static const String _logCategory = 'MainMapScreen';
  int currentIndex = 1; // Start with Home (map) tab
  final MapController mapController = MapController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot>? _unreadSubscription;
  final double _minZoom = 3;
  final double _maxZoom = 18;
  double _currentZoom = 12;
  LatLng _currentCenter = const LatLng(13.7563, 100.5018); // Bangkok default
  LatLng? _selectedLocation;
  bool _showPopup = false;
  int _unreadChatCount = 0;
  Position? _currentPosition;
  bool _isLoadingLocation = false;
  bool _isRequestingPermission = false;
  final TextEditingController _searchController = TextEditingController();
  bool _showSearchResults = false;
  List<Map<String, dynamic>> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _listenToUnreadMessages();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounceTimer?.cancel();
    _unreadSubscription?.cancel();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    // Prevent multiple concurrent location requests
    if (_isLoadingLocation || _isRequestingPermission) {
      return;
    }

    setState(() {
      _isLoadingLocation = true;
    });

    String errorDetails = '';
    
    try {
      // Check location service with longer timeout
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          errorDetails = 'Location service check timed out';
          return false;
        },
      );
      
      if (!serviceEnabled) {
        errorDetails = 'Location services are disabled in device settings';
        throw Exception('Location services are disabled.');
      }

      // Check permission with longer timeout
      LocationPermission permission = await Geolocator.checkPermission().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          errorDetails = 'Permission check timed out';
          return LocationPermission.denied;
        },
      );
      
      if (permission == LocationPermission.denied) {
        // Set flag to prevent multiple permission requests
        if (_isRequestingPermission) {
          return;
        }
        setState(() {
          _isRequestingPermission = true;
        });
        
        try {
          // Request permission with longer timeout
          permission = await Geolocator.requestPermission().timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              errorDetails = 'Permission request timed out';
              return LocationPermission.denied;
            },
          );
          if (permission == LocationPermission.denied) {
            errorDetails = 'Location permission denied by user';
            throw Exception('Location permissions are denied');
          }
        } finally {
          setState(() {
            _isRequestingPermission = false;
          });
        }
      }

      if (permission == LocationPermission.deniedForever) {
        errorDetails = 'Location permission permanently denied. Enable in Settings > Privacy & Security > Location Services';
        throw Exception('Location permissions are permanently denied');
      }

      // Get position with more reasonable timeout and better accuracy options
      Position position;
      try {
        // Try high accuracy first
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        ).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw Exception('High accuracy location timed out');
          },
        );
      } catch (e) {
        // Fallback to medium accuracy if high accuracy fails
        LoggingService.warning(
          'High accuracy failed: $e, trying medium accuracy',
          category: _logCategory,
        );
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 8),
        ).timeout(
          const Duration(seconds: 12),
          onTimeout: () {
            throw Exception('Medium accuracy location also timed out');
          },
        );
      }
      
      // Validate coordinates are reasonable (not default/error values)
      if (position.latitude != 0.0 && position.longitude != 0.0) {
        setState(() {
          _currentPosition = position;
          _currentCenter = LatLng(position.latitude, position.longitude);
        });
        
        // Move map to current location
        if (!mounted) return;
        mapController.move(_currentCenter, 15.0);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location found: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        errorDetails = 'Invalid coordinates received (0,0)';
        throw Exception('Invalid location coordinates');
      }
    } catch (e) {
      if (!mounted) return;
      // Use Bangkok default on any error
      setState(() {
        _currentCenter = const LatLng(13.7563, 100.5018); // Bangkok default
      });
      mapController.move(_currentCenter, 12.0);
      
      // Show detailed error message
      final errorMessage = errorDetails.isNotEmpty 
          ? 'Location Error: $errorDetails' 
          : 'Location Error: ${e.toString()}';
          
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$errorMessage\nUsing Bangkok default location'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _getCurrentLocation(),
          ),
        ),
      );
    } finally {
      setState(() {
        _isLoadingLocation = false;
        _isRequestingPermission = false;
      });
    }
  }

  Timer? _searchDebounceTimer;
  
  void _searchLocations(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }

    // Cancel previous timer
    _searchDebounceTimer?.cancel();
    
    // Debounce API calls - wait 500ms before making API request
    _searchDebounceTimer = Timer(const Duration(milliseconds: 500), () async {
      await _performSearch(query);
    });
    
    // Show immediate results from static database
    await _performStaticSearch(query);
  }
  
  Future<void> _performStaticSearch(String query) async {
    // Search incidents
    final incidentResults = await _searchIncidents(query);
    
    // Search places from static database only
    final staticLocationResults = await _searchPlaces(query);
    
    // Show static results immediately
    final staticResults = [...incidentResults, ...staticLocationResults];
    
    setState(() {
      _searchResults = staticResults;
      _showSearchResults = staticResults.isNotEmpty;
    });
  }
  
  Future<void> _performSearch(String query) async {
    // Search incidents
    final incidentResults = await _searchIncidents(query);
    
    // Search places from static database
    final staticLocationResults = await _searchPlaces(query);
    
    // Search places from external API (Nominatim) - only if query is longer than 3 characters
    List<Map<String, dynamic>> apiLocationResults = [];
    if (query.length > 3) {
      try {
        apiLocationResults = await _searchPlacesFromAPI(query);
      } catch (e, stack) {
        LoggingService.error(
          'API search failed, using static database only',
          error: e,
          stackTrace: stack,
          category: _logCategory,
        );
        // Continue with static results only
      }
    }
    
    // Combine results with static results first (higher priority)
    final allResults = [...incidentResults, ...staticLocationResults, ...apiLocationResults];

    setState(() {
      _searchResults = allResults;
      _showSearchResults = allResults.isNotEmpty;
    });
  }

  Future<List<Map<String, dynamic>>> _searchPlaces(String query) async {
    // Google Maps-level comprehensive Thai locations database
    final places = {
      // Major Cities & Provinces
      'bangkok': {'lat': 13.7563, 'lng': 100.5018, 'name': 'Bangkok'},
      'phuket': {'lat': 7.8804, 'lng': 98.3923, 'name': 'Phuket'},
      'chiang mai': {'lat': 18.7883, 'lng': 98.9853, 'name': 'Chiang Mai'},
      'pattaya': {'lat': 12.9236, 'lng': 100.8825, 'name': 'Pattaya'},
      'hua hin': {'lat': 12.5708, 'lng': 99.9581, 'name': 'Hua Hin'},
      'krabi': {'lat': 8.0863, 'lng': 98.9063, 'name': 'Krabi'},
      'koh samui': {'lat': 9.5018, 'lng': 100.0038, 'name': 'Koh Samui'},
      'ayutthaya': {'lat': 14.3692, 'lng': 100.5877, 'name': 'Ayutthaya'},
      'sukhothai': {'lat': 17.0061, 'lng': 99.8230, 'name': 'Sukhothai'},
      'kanchanaburi': {'lat': 14.0227, 'lng': 99.5328, 'name': 'Kanchanaburi'},
      'chiang rai': {'lat': 19.9105, 'lng': 99.8406, 'name': 'Chiang Rai'},
      'nakhon ratchasima': {'lat': 14.9799, 'lng': 102.0977, 'name': 'Nakhon Ratchasima (Korat)'},
      'udon thani': {'lat': 17.4138, 'lng': 102.7878, 'name': 'Udon Thani'},
      'khon kaen': {'lat': 16.4419, 'lng': 102.8359, 'name': 'Khon Kaen'},
      'rayong': {'lat': 12.6807, 'lng': 101.2538, 'name': 'Rayong'},
      'songkhla': {'lat': 7.1756, 'lng': 100.6135, 'name': 'Songkhla'},
      'nakhon si thammarat': {'lat': 8.4304, 'lng': 99.9631, 'name': 'Nakhon Si Thammarat'},
      
      // Universities & Higher Education
      'Chulalongkorn University': {'lat': 13.7367, 'lng': 100.5332},
      'Chulalongkorn University Main Campus': {'lat': 13.7367, 'lng': 100.5332},
      'Chulalongkorn University Sasin Graduate Institute': {'lat': 13.7367, 'lng': 100.5332},
      
      // Silpakorn University - Multiple Campuses
      'Silpakorn University Wang Tha Phra Campus': {'lat': 13.8167, 'lng': 100.0437},
      'Silpakorn University Sanam Chandra Palace Campus': {'lat': 13.8167, 'lng': 100.0437},
      'Silpakorn University Phetchaburi IT Campus': {'lat': 13.1067, 'lng': 99.9437},
      'SU': {'lat': 13.8167, 'lng': 100.0437},
      
      // Thammasat University - Multiple Campuses
      'Thammasat University Tha Prachan Campus': {'lat': 13.7567, 'lng': 100.4967},
      'Thammasat University Rangsit Campus': {'lat': 14.0697, 'lng': 100.6056},
      'Thammasat University Lampang Campus': {'lat': 18.2888, 'lng': 99.4907},
      'Thammasat University Pattaya Campus': {'lat': 12.7967, 'lng': 100.8756},
      'Thammasat University Sirindhorn International Institute of Technology': {'lat': 14.0697, 'lng': 100.6056},
      
      // Kasetsart University - Multiple Campuses
      'Kasetsart University': {'lat': 13.8462, 'lng': 100.5717},
      'Kasetsart University Bangkhen Campus': {'lat': 13.8462, 'lng': 100.5717},
      'Kasetsart University Kamphaeng Saen Campus': {'lat': 14.0297, 'lng': 99.9756},
      'Kasetsart University Sriracha Campus': {'lat': 13.1756, 'lng': 100.9256},
      'Kasetsart University Sakon Nakhon Campus': {'lat': 17.1556, 'lng': 104.1356},
      'Kasetsart University Chalermphrakiat Sakon Nakhon Province Campus': {'lat': 17.1556, 'lng': 104.1356},
      
      // Mahidol University - Multiple Campuses
      'Mahidol University Salaya Campus': {'lat': 13.7946, 'lng': 100.3256},
      'Mahidol University Phayathai Campus': {'lat': 13.7656, 'lng': 100.5356},
      'Mahidol University Amnatcharoen Campus': {'lat': 15.8656, 'lng': 104.6256},
      'Mahidol University Kanchanaburi Campus': {'lat': 14.0256, 'lng': 99.5356},
      'Mahidol University International College': {'lat': 13.7946, 'lng': 100.3256},
      'Mahidol University College of Management': {'lat': 13.7946, 'lng': 100.3256},
      'assumption university': {'lat': 13.6167, 'lng': 100.6037, 'name': 'Assumption University'},
      'bangkok university': {'lat': 13.7767, 'lng': 100.5437, 'name': 'Bangkok University'},
      'dhurakij pundit university': {'lat': 13.7467, 'lng': 100.5637, 'name': 'Dhurakij Pundit University'},
      'siam university': {'lat': 13.7267, 'lng': 100.4837, 'name': 'Siam University'},
      'chiang mai university': {'lat': 18.8067, 'lng': 98.9537, 'name': 'Chiang Mai University'},
      'prince of songkla university': {'lat': 7.0067, 'lng': 100.4937, 'name': 'Prince of Songkla University'},
      'khon kaen university': {'lat': 16.4667, 'lng': 102.8137, 'name': 'Khon Kaen University'},
      
      // International Schools & Famous Schools
      'nist international school': {'lat': 13.7167, 'lng': 100.5937, 'name': 'NIST International School'},
      'international school bangkok': {'lat': 13.7467, 'lng': 100.5737, 'name': 'International School Bangkok'},
      'bangkok patana school': {'lat': 13.6967, 'lng': 100.5437, 'name': 'Bangkok Patana School'},
      'shrewsbury international school': {'lat': 13.6767, 'lng': 100.5237, 'name': 'Shrewsbury International School'},
      'harrow international school': {'lat': 13.9167, 'lng': 100.6437, 'name': 'Harrow International School Bangkok'},
      'regents international school': {'lat': 13.7067, 'lng': 100.5537, 'name': 'Regents International School Pattaya'},
      'ruamrudee international school': {'lat': 13.7267, 'lng': 100.5637, 'name': 'Ruamrudee International School'},
      'wells international school': {'lat': 13.7367, 'lng': 100.5837, 'name': 'Wells International School'},
      'st andrews international school': {'lat': 13.7567, 'lng': 100.5937, 'name': 'St. Andrews International School'},
      'concordian international school': {'lat': 13.7667, 'lng': 100.6037, 'name': 'Concordian International School'},
      'triamudom suksa school': {'lat': 13.7467, 'lng': 100.5337, 'name': 'Triamudom Suksa School'},
      'chulalongkorn university demonstration school': {'lat': 13.7367, 'lng': 100.5237, 'name': 'Chulalongkorn University Demonstration School'},
      'mahidol wittayanusorn school': {'lat': 13.7967, 'lng': 100.3137, 'name': 'Mahidol Wittayanusorn School'},
      'assumption college': {'lat': 13.7267, 'lng': 100.5437, 'name': 'Assumption College Bangkok'},
      'saint gabriel college': {'lat': 13.7167, 'lng': 100.5537, 'name': 'Saint Gabriel\'s College'},
      
      // Famous Restaurants & Street Food
      'gaggan': {'lat': 13.7367, 'lng': 100.5437, 'name': 'Gaggan (Restaurant)'},
      'le du': {'lat': 13.7267, 'lng': 100.5337, 'name': 'Le Du (Restaurant)'},
      'sorn': {'lat': 13.7167, 'lng': 100.5237, 'name': 'Sorn (Restaurant)'},
      'paste bangkok': {'lat': 13.7467, 'lng': 100.5537, 'name': 'Paste Bangkok'},
      'bo.lan': {'lat': 13.7067, 'lng': 100.5137, 'name': 'Bo.Lan (Restaurant)'},
      'jay fai': {'lat': 13.7567, 'lng': 100.5037, 'name': 'Jay Fai (Street Food)'},
      'thip samai': {'lat': 13.7667, 'lng': 100.5137, 'name': 'Thip Samai (Pad Thai)'},
      'som tam nua': {'lat': 13.7367, 'lng': 100.5637, 'name': 'Som Tam Nua'},
      'krua apsorn': {'lat': 13.7467, 'lng': 100.5037, 'name': 'Krua Apsorn'},
      'raan jay fai': {'lat': 13.7567, 'lng': 100.5037, 'name': 'Raan Jay Fai'},
      'supanniga eating room': {'lat': 13.7267, 'lng': 100.5437, 'name': 'Supanniga Eating Room'},
      'err urban rustic thai': {'lat': 13.7167, 'lng': 100.5337, 'name': 'Err Urban Rustic Thai'},
      'nahm': {'lat': 13.7067, 'lng': 100.5237, 'name': 'Nahm (Restaurant)'},
      'blue elephant': {'lat': 13.7367, 'lng': 100.5137, 'name': 'Blue Elephant Restaurant'},
      'sirocco': {'lat': 13.7167, 'lng': 100.5137, 'name': 'Sirocco Restaurant'},
      'vertigo': {'lat': 13.7267, 'lng': 100.5237, 'name': 'Vertigo Restaurant'},
      'cabbages and condoms': {'lat': 13.7467, 'lng': 100.5637, 'name': 'Cabbages and Condoms Restaurant'},
      'mango tree': {'lat': 13.7367, 'lng': 100.5337, 'name': 'Mango Tree Restaurant'},
      'baan khanitha': {'lat': 13.7267, 'lng': 100.5437, 'name': 'Baan Khanitha Restaurant'},
      'sala rim naam': {'lat': 13.7167, 'lng': 100.5037, 'name': 'Sala Rim Naam'},
      
      // Coffee Shops & Cafes
      'roast coffee': {'lat': 13.7367, 'lng': 100.5637, 'name': 'Roast Coffee & Eatery'},
      'dean & deluca': {'lat': 13.7467, 'lng': 100.5537, 'name': 'Dean & DeLuca'},
      'starbucks': {'lat': 13.7567, 'lng': 100.5437, 'name': 'Starbucks'},
      'true coffee': {'lat': 13.7667, 'lng': 100.5337, 'name': 'True Coffee'},
      'coffee bean': {'lat': 13.7767, 'lng': 100.5237, 'name': 'The Coffee Bean & Tea Leaf'},
      'factory coffee': {'lat': 13.7867, 'lng': 100.5137, 'name': 'Factory Coffee'},
      'rocket coffeebar': {'lat': 13.7967, 'lng': 100.5037, 'name': 'Rocket Coffeebar'},
      'brave roasters': {'lat': 13.8067, 'lng': 100.4937, 'name': 'Brave Roasters'},
      'roots coffee': {'lat': 13.8167, 'lng': 100.4837, 'name': 'Roots Coffee Roaster'},
      'casa lapin': {'lat': 13.8267, 'lng': 100.4737, 'name': 'Casa Lapin'},
      
      // Luxury Hotels
      'mandarin oriental bangkok': {'lat': 13.7248, 'lng': 100.5151, 'name': 'Mandarin Oriental Bangkok'},
      'shangri la bangkok': {'lat': 13.7148, 'lng': 100.5251, 'name': 'Shangri-La Hotel Bangkok'},
      'peninsula bangkok': {'lat': 13.7048, 'lng': 100.5351, 'name': 'The Peninsula Bangkok'},
      'four seasons bangkok': {'lat': 13.7348, 'lng': 100.5451, 'name': 'Four Seasons Hotel Bangkok'},
      'st regis bangkok': {'lat': 13.7448, 'lng': 100.5551, 'name': 'The St. Regis Bangkok'},
      'conrad bangkok': {'lat': 13.7548, 'lng': 100.5651, 'name': 'Conrad Bangkok'},
      'grand hyatt erawan': {'lat': 13.7648, 'lng': 100.5751, 'name': 'Grand Hyatt Erawan Bangkok'},
      'intercontinental bangkok': {'lat': 13.7748, 'lng': 100.5851, 'name': 'InterContinental Bangkok'},
      'westin grande sukhumvit': {'lat': 13.7848, 'lng': 100.5951, 'name': 'The Westin Grande Sukhumvit'},
      'marriott marquis': {'lat': 13.7948, 'lng': 100.6051, 'name': 'Bangkok Marriott Marquis Queen\'s Park'},
      'okura prestige': {'lat': 13.8048, 'lng': 100.6151, 'name': 'The Okura Prestige Bangkok'},
      'park hyatt bangkok': {'lat': 13.8148, 'lng': 100.6251, 'name': 'Park Hyatt Bangkok'},
      'rosewood bangkok': {'lat': 13.8248, 'lng': 100.6351, 'name': 'Rosewood Bangkok'},
      'waldorf astoria': {'lat': 13.8348, 'lng': 100.6451, 'name': 'Waldorf Astoria Bangkok'},
      'banyan tree bangkok': {'lat': 13.8448, 'lng': 100.6551, 'name': 'Banyan Tree Bangkok'},
      'lebua state tower': {'lat': 13.7148, 'lng': 100.5151, 'name': 'Lebua at State Tower'},
      'centara grand': {'lat': 13.7248, 'lng': 100.5251, 'name': 'Centara Grand at CentralWorld'},
      'anantara riverside': {'lat': 13.7348, 'lng': 100.5351, 'name': 'Anantara Riverside Bangkok Resort'},
      'chatrium hotel': {'lat': 13.7448, 'lng': 100.5451, 'name': 'Chatrium Hotel Riverside Bangkok'},
      'royal orchid sheraton': {'lat': 13.7548, 'lng': 100.5551, 'name': 'Royal Orchid Sheraton Hotel & Towers'},
      
      // Budget Hotels & Hostels
      'khao san palace': {'lat': 13.7590, 'lng': 100.4977, 'name': 'Khao San Palace Hotel'},
      'lub d': {'lat': 13.7690, 'lng': 100.5077, 'name': 'Lub d Bangkok Siam'},
      'mad monkey hostel': {'lat': 13.7790, 'lng': 100.5177, 'name': 'Mad Monkey Hostel Bangkok'},
      'the yard hostel': {'lat': 13.7890, 'lng': 100.5277, 'name': 'The Yard Hostel'},
      'nap park hostel': {'lat': 13.7990, 'lng': 100.5377, 'name': 'Nap Park Hostel at Khao San'},
      'bodega bangkok': {'lat': 13.8090, 'lng': 100.5477, 'name': 'Bodega Bangkok'},
      'once again hostel': {'lat': 13.8190, 'lng': 100.5577, 'name': 'Once Again Hostel'},
      'saphaipae hostel': {'lat': 13.8290, 'lng': 100.5677, 'name': 'Saphaipae Hostel'},
      'the overstay': {'lat': 13.8390, 'lng': 100.5777, 'name': 'The Overstay'},
      'baan dinso': {'lat': 13.8490, 'lng': 100.5877, 'name': 'Baan Dinso @ Ratchadamnoen'},
      
      // Hospitals & Medical Centers
      'bumrungrad hospital': {'lat': 13.7467, 'lng': 100.5637, 'name': 'Bumrungrad International Hospital'},
      'bangkok hospital': {'lat': 13.7367, 'lng': 100.5537, 'name': 'Bangkok Hospital'},
      'samitivej hospital': {'lat': 13.7267, 'lng': 100.5437, 'name': 'Samitivej Hospital'},
      'siriraj hospital': {'lat': 13.7567, 'lng': 100.4737, 'name': 'Siriraj Hospital'},
      'chulalongkorn hospital': {'lat': 13.7367, 'lng': 100.5337, 'name': 'King Chulalongkorn Memorial Hospital'},
      'ramathibodi hospital': {'lat': 13.7667, 'lng': 100.5237, 'name': 'Ramathibodi Hospital'},
      'phyathai hospital': {'lat': 13.7767, 'lng': 100.5337, 'name': 'Phyathai Hospital'},
      'vejthani hospital': {'lat': 13.7867, 'lng': 100.5437, 'name': 'Vejthani Hospital'},
      'paolo hospital': {'lat': 13.7967, 'lng': 100.5537, 'name': 'Paolo Hospital Phaholyothin'},
      'bnh hospital': {'lat': 13.8067, 'lng': 100.5637, 'name': 'BNH Hospital'},
      
      // Bangkok Districts & Areas
      'silom': {'lat': 13.7307, 'lng': 100.5418, 'name': 'Silom'},
      'sukhumvit': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Sukhumvit'},
      'thonglor': {'lat': 13.7308, 'lng': 100.5698, 'name': 'Thonglor'},
      'ekkamai': {'lat': 13.7198, 'lng': 100.5850, 'name': 'Ekkamai'},
      'phrom phong': {'lat': 13.7308, 'lng': 100.5698, 'name': 'Phrom Phong'},
      'asok intersection': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Asok Intersection'},
      'nana plaza': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Nana Plaza'},
      'ploenchit': {'lat': 13.7460, 'lng': 100.5348, 'name': 'Ploenchit'},
      'ratchathewi': {'lat': 13.7563, 'lng': 100.5018, 'name': 'Ratchathewi'},
      'victory monument': {'lat': 13.7647, 'lng': 100.5370, 'name': 'Victory Monument'},
      'yaowarat': {'lat': 13.7398, 'lng': 100.5067, 'name': 'Yaowarat (Chinatown)'},
      'khaosan road': {'lat': 13.7590, 'lng': 100.4977, 'name': 'Khaosan Road'},
      'chatuchak market': {'lat': 13.7998, 'lng': 100.5498, 'name': 'Chatuchak Weekend Market'},
      'lat phrao': {'lat': 13.8198, 'lng': 100.5698, 'name': 'Lat Phrao'},
      'ramkhamhaeng': {'lat': 13.7598, 'lng': 100.6098, 'name': 'Ramkhamhaeng'},
      'on nut': {'lat': 13.7048, 'lng': 100.5998, 'name': 'On Nut'},
      'bearing': {'lat': 13.6598, 'lng': 100.6098, 'name': 'Bearing'},
      'samut prakan province': {'lat': 13.5998, 'lng': 100.5998, 'name': 'Samut Prakan Province'},
      'saphan phut': {'lat': 13.7398, 'lng': 100.5098, 'name': 'Saphan Phut'},
      // Huai Khwang already listed in districts section
      'wang thonglang': {'lat': 13.7798, 'lng': 100.5998, 'name': 'Wang Thonglang'},
      'din daeng': {'lat': 13.7698, 'lng': 100.5598, 'name': 'Din Daeng'},
      'phaya thai': {'lat': 13.7598, 'lng': 100.5398, 'name': 'Phaya Thai'},
      'dusit': {'lat': 13.7798, 'lng': 100.5198, 'name': 'Dusit'},
      'bang sue': {'lat': 13.8198, 'lng': 100.5298, 'name': 'Bang Sue'},
      'chatuchak park': {'lat': 13.8098, 'lng': 100.5498, 'name': 'Chatuchak Park'},
      'saphan taksin': {'lat': 13.7198, 'lng': 100.5098, 'name': 'Saphan Taksin'},
      'krung thonburi': {'lat': 13.7098, 'lng': 100.4898, 'name': 'Krung Thonburi'},
      'khlong toei': {'lat': 13.7198, 'lng': 100.5598, 'name': 'Khlong Toei'},
      'watthana': {'lat': 13.7398, 'lng': 100.5798, 'name': 'Watthana'},
      'vadhana': {'lat': 13.7298, 'lng': 100.5398, 'name': 'Vadhana'},
      'pathum wan': {'lat': 13.7398, 'lng': 100.5298, 'name': 'Pathum Wan'},
      'bang rak district': {'lat': 13.7198, 'lng': 100.5198, 'name': 'Bang Rak District'},
      'sathorn': {'lat': 13.7198, 'lng': 100.5298, 'name': 'Sathorn'},
      'yan nawa': {'lat': 13.6998, 'lng': 100.5298, 'name': 'Yan Nawa'},
      'thung mahamek': {'lat': 13.7098, 'lng': 100.5198, 'name': 'Thung Mahamek'},
      'klong san': {'lat': 13.7098, 'lng': 100.4998, 'name': 'Klong San'},
      'bang pho district': {'lat': 13.6998, 'lng': 100.4998, 'name': 'Bang Pho District'},
      'bangkok yai': {'lat': 13.7198, 'lng': 100.4798, 'name': 'Bangkok Yai'},
      'bangkok noi': {'lat': 13.7598, 'lng': 100.4798, 'name': 'Bangkok Noi'},
      'taling chan': {'lat': 13.7698, 'lng': 100.4398, 'name': 'Taling Chan'},
      'thawi watthana': {'lat': 13.7798, 'lng': 100.4098, 'name': 'Thawi Watthana'},
      'bang khae': {'lat': 13.7098, 'lng': 100.4098, 'name': 'Bang Khae'},
      'phasi charoen': {'lat': 13.6998, 'lng': 100.4398, 'name': 'Phasi Charoen'},
      'bang bon': {'lat': 13.6598, 'lng': 100.3998, 'name': 'Bang Bon'},
      'rat burana': {'lat': 13.6798, 'lng': 100.4598, 'name': 'Rat Burana'},
      'chom thong district': {'lat': 13.6698, 'lng': 100.4298, 'name': 'Chom Thong District'},
      'bang khun thian': {'lat': 13.6398, 'lng': 100.4298, 'name': 'Bang Khun Thian'},
      'nong khaem': {'lat': 13.6898, 'lng': 100.3598, 'name': 'Nong Khaem'},
      'min buri': {'lat': 13.8198, 'lng': 100.7298, 'name': 'Min Buri'},
      'lat krabang': {'lat': 13.7298, 'lng': 100.7598, 'name': 'Lat Krabang'},
      'nong chok': {'lat': 13.8598, 'lng': 100.8598, 'name': 'Nong Chok'},
      'khlong sam wa': {'lat': 13.8698, 'lng': 100.7098, 'name': 'Khlong Sam Wa'},
      'sai mai': {'lat': 13.9098, 'lng': 100.6598, 'name': 'Sai Mai'},
      'don mueang': {'lat': 13.9198, 'lng': 100.6098, 'name': 'Don Mueang'},
      'laksi': {'lat': 13.8798, 'lng': 100.5798, 'name': 'Laksi'},
      'lak song': {'lat': 13.6798, 'lng': 100.6398, 'name': 'Lak Song'},
      'prawet': {'lat': 13.6898, 'lng': 100.6698, 'name': 'Prawet'},
      'suan luang': {'lat': 13.7098, 'lng': 100.6398, 'name': 'Suan Luang'},
      'saphan phut market': {'lat': 13.7398, 'lng': 100.5098, 'name': 'Saphan Phut Market'},
      'pak khlong talat': {'lat': 13.7498, 'lng': 100.4998, 'name': 'Pak Khlong Talat (Flower Market)'},
      'wang burapha phirom': {'lat': 13.7598, 'lng': 100.4998, 'name': 'Wang Burapha Phirom'},
      'phra nakhon': {'lat': 13.7598, 'lng': 100.5098, 'name': 'Phra Nakhon'},
      'samphanthawong': {'lat': 13.7398, 'lng': 100.5098, 'name': 'Samphanthawong'},
      'pom prap sattru phai': {'lat': 13.7498, 'lng': 100.5198, 'name': 'Pom Prap Sattru Phai'},
      'khlong toei port': {'lat': 13.6998, 'lng': 100.5598, 'name': 'Khlong Toei Port'},
      'queen sirikit park': {'lat': 13.7298, 'lng': 100.5898, 'name': 'Queen Sirikit Park'},
      'benjakiti park': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Benjakiti Park'},
      'lumpini park': {'lat': 13.7298, 'lng': 100.5398, 'name': 'Lumpini Park'},
      'sanam luang': {'lat': 13.7548, 'lng': 100.4948, 'name': 'Sanam Luang'},
      'rot fai park': {'lat': 13.8098, 'lng': 100.5598, 'name': 'Rot Fai Park (Chatuchak)'},
      'suan rot fai': {'lat': 13.8098, 'lng': 100.5598, 'name': 'Suan Rot Fai'},
      // See main Bangkok landmarks section for King Rama IX Park
      'santiphap park': {'lat': 13.7798, 'lng': 100.5098, 'name': 'Santiphap Park'},
      'wachirabenchathat park': {'lat': 13.8098, 'lng': 100.5598, 'name': 'Wachirabenchathat Park'},
      'suan santi chaiprakarn': {'lat': 13.7598, 'lng': 100.4898, 'name': 'Suan Santi Chaiprakarn'},
      'romaneenart park': {'lat': 13.7398, 'lng': 100.5698, 'name': 'Romaneenart Park'},
      'benchasiri park': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Benchasiri Park'},
      'chuvit garden': {'lat': 13.7398, 'lng': 100.5598, 'name': 'Chuvit Garden'},
      'suan phlu market': {'lat': 13.7098, 'lng': 100.5298, 'name': 'Suan Phlu Market'},
      'huai khwang night market': {'lat': 13.7698, 'lng': 100.5798, 'name': 'Huai Khwang Night Market'},
      'saphan phut night market': {'lat': 13.7398, 'lng': 100.5098, 'name': 'Saphan Phut Night Market'},
      'wang thonglang market': {'lat': 13.7798, 'lng': 100.5998, 'name': 'Wang Thonglang Market'},
      'khlong toei market': {'lat': 13.7198, 'lng': 100.5598, 'name': 'Khlong Toei Market'},
      'lat mayom floating market': {'lat': 13.7698, 'lng': 100.4398, 'name': 'Lat Mayom Floating Market'},
      'taling chan floating market': {'lat': 13.7698, 'lng': 100.4398, 'name': 'Taling Chan Floating Market'},
      'bang pho market': {'lat': 13.6998, 'lng': 100.4998, 'name': 'Bang Pho Market'},
      'minburi market': {'lat': 13.8198, 'lng': 100.7298, 'name': 'Minburi Market'},
      'lat krabang market': {'lat': 13.7298, 'lng': 100.7598, 'name': 'Lat Krabang Market'},
      'nong chok market': {'lat': 13.8598, 'lng': 100.8598, 'name': 'Nong Chok Market'},
      'don mueang market': {'lat': 13.9198, 'lng': 100.6098, 'name': 'Don Mueang Market'},
      'laksi market': {'lat': 13.8798, 'lng': 100.5798, 'name': 'Laksi Market'},
      'bang sue market': {'lat': 13.8198, 'lng': 100.5298, 'name': 'Bang Sue Market'},
      'chatuchak weekend market': {'lat': 13.7998, 'lng': 100.5498, 'name': 'Chatuchak Weekend Market'},
      'jj green market': {'lat': 13.7998, 'lng': 100.5498, 'name': 'JJ Green Market'},
      'rot fai market ratchada': {'lat': 13.7598, 'lng': 100.5698, 'name': 'Rot Fai Market Ratchada'},
      'indy night market': {'lat': 13.7398, 'lng': 100.5598, 'name': 'Indy Night Market'},
      'artbox market': {'lat': 13.7398, 'lng': 100.5598, 'name': 'Artbox Market'},
      'asiatique the riverfront': {'lat': 13.7048, 'lng': 100.5048, 'name': 'Asiatique The Riverfront'},
      'icon siam': {'lat': 13.7268, 'lng': 100.5068, 'name': 'ICONSIAM'},
      'river city': {'lat': 13.7198, 'lng': 100.5098, 'name': 'River City Bangkok'},
      'warehouse 30': {'lat': 13.7098, 'lng': 100.5198, 'name': 'Warehouse 30'},
      'lhong 1919': {'lat': 13.7098, 'lng': 100.4998, 'name': 'Lhong 1919'},
      'tha maharaj': {'lat': 13.7548, 'lng': 100.4948, 'name': 'Tha Maharaj'},
      'chang chui': {'lat': 13.7698, 'lng': 100.4698, 'name': 'Chang Chui Creative Park'},
      'the commons': {'lat': 13.7298, 'lng': 100.5698, 'name': 'The Commons Thonglor'},
      'the street ratchada': {'lat': 13.7598, 'lng': 100.5698, 'name': 'The Street Ratchada'},
      'saphan phut tower': {'lat': 13.7398, 'lng': 100.5098, 'name': 'Saphan Phut Tower'},
      'baiyoke tower': {'lat': 13.7548, 'lng': 100.5398, 'name': 'Baiyoke Tower II'},
      'mahanakhon': {'lat': 13.7198, 'lng': 100.5298, 'name': 'King Power Mahanakhon'},
      'state tower': {'lat': 13.7148, 'lng': 100.5151, 'name': 'State Tower'},
      'sathorn unique tower': {'lat': 13.7098, 'lng': 100.5198, 'name': 'Sathorn Unique Tower'},
      'moon bar': {'lat': 13.7148, 'lng': 100.5151, 'name': 'Moon Bar (Banyan Tree)'},
      'sky bar': {'lat': 13.7148, 'lng': 100.5151, 'name': 'Sky Bar (Lebua)'},
      'octave rooftop bar': {'lat': 13.7398, 'lng': 100.5598, 'name': 'Octave Rooftop Bar'},
      'red sky bar': {'lat': 13.7248, 'lng': 100.5251, 'name': 'Red Sky Bar'},
      'zoom sky bar': {'lat': 13.7398, 'lng': 100.5598, 'name': 'Zoom Sky Bar'},
      'above eleven': {'lat': 13.7298, 'lng': 100.5598, 'name': 'Above Eleven'},
      'vanilla sky': {'lat': 13.7398, 'lng': 100.5698, 'name': 'Vanilla Sky'},
      'three sixty': {'lat': 13.7398, 'lng': 100.5598, 'name': 'Three Sixty Lounge'},
      'cloud 47': {'lat': 13.7398, 'lng': 100.5598, 'name': 'Cloud 47 Rooftop Bar'},
      'char rooftop bar': {'lat': 13.7398, 'lng': 100.5598, 'name': 'Char Rooftop Bar'},
      
      // Additional Bangkok Areas
      'banglamphu': {'lat': 13.7590, 'lng': 100.4977, 'name': 'Banglamphu'},
      'pratunam': {'lat': 13.7498, 'lng': 100.5398, 'name': 'Pratunam'},
      'ratchaprasong': {'lat': 13.7448, 'lng': 100.5398, 'name': 'Ratchaprasong'},
      'wireless road': {'lat': 13.7398, 'lng': 100.5498, 'name': 'Wireless Road'},
      'langsuan': {'lat': 13.7348, 'lng': 100.5448, 'name': 'Langsuan'},
      'chidlom': {'lat': 13.7448, 'lng': 100.5448, 'name': 'Chidlom'},
      'rajdamri': {'lat': 13.7398, 'lng': 100.5348, 'name': 'Rajdamri'},
      'sala daeng': {'lat': 13.7298, 'lng': 100.5348, 'name': 'Sala Daeng'},
      'chong nonsi': {'lat': 13.7198, 'lng': 100.5248, 'name': 'Chong Nonsi'},
      'surasak': {'lat': 13.7098, 'lng': 100.5148, 'name': 'Surasak'},
      'bang wa': {'lat': 13.6998, 'lng': 100.4398, 'name': 'Bang Wa'},
      'pho nimit': {'lat': 13.6898, 'lng': 100.4498, 'name': 'Pho Nimit'},
      'talad phlu': {'lat': 13.6798, 'lng': 100.4598, 'name': 'Talad Phlu'},
      'wutthakat': {'lat': 13.6698, 'lng': 100.4698, 'name': 'Wutthakat'},
      'bang phai': {'lat': 13.6598, 'lng': 100.4798, 'name': 'Bang Phai'},
      'bang yi khan': {'lat': 13.6498, 'lng': 100.4898, 'name': 'Bang Yi Khan'},
      'sirindhorn': {'lat': 13.6398, 'lng': 100.4998, 'name': 'Sirindhorn'},
      'phutthamonthon sai 1': {'lat': 13.6298, 'lng': 100.5098, 'name': 'Phutthamonthon Sai 1'},
      'phutthamonthon sai 2': {'lat': 13.6198, 'lng': 100.5198, 'name': 'Phutthamonthon Sai 2'},
      'phutthamonthon sai 3': {'lat': 13.6098, 'lng': 100.5298, 'name': 'Phutthamonthon Sai 3'},
      'phutthamonthon sai 4': {'lat': 13.5998, 'lng': 100.5398, 'name': 'Phutthamonthon Sai 4'},
      'bang mod': {'lat': 13.5898, 'lng': 100.5498, 'name': 'Bang Mod'},
      'hua mak': {'lat': 13.7598, 'lng': 100.6398, 'name': 'Hua Mak'},
      'ramkhamhaeng university main': {'lat': 13.7598, 'lng': 100.6098, 'name': 'Ramkhamhaeng University Main Campus'},
      'the mall ramkhamhaeng': {'lat': 13.7598, 'lng': 100.6198, 'name': 'The Mall Ramkhamhaeng'},
      'airport rail link makkasan': {'lat': 13.7598, 'lng': 100.5598, 'name': 'Airport Rail Link Makkasan'},
      'ratchada': {'lat': 13.7598, 'lng': 100.5698, 'name': 'Ratchada'},
      'ratchadaphisek': {'lat': 13.7698, 'lng': 100.5698, 'name': 'Ratchadaphisek'},
      'sutthisan': {'lat': 13.7798, 'lng': 100.5698, 'name': 'Sutthisan'},
      'huai khwang': {'lat': 13.7698, 'lng': 100.5798, 'name': 'Huai Khwang'},
      'thailand cultural centre': {'lat': 13.7598, 'lng': 100.5598, 'name': 'Thailand Cultural Centre'},
      'phra ram 9': {'lat': 13.7598, 'lng': 100.5798, 'name': 'Phra Ram 9'},
      'petchaburi': {'lat': 13.7498, 'lng': 100.5598, 'name': 'Petchaburi'},
      'thong lo': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Thong Lo'},
      'phrom phong station': {'lat': 13.7298, 'lng': 100.5598, 'name': 'Phrom Phong Station'},
      'emporium': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Emporium'},
      'emquartier': {'lat': 13.7298, 'lng': 100.5698, 'name': 'EmQuartier'},
      'benjasiri park': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Benjasiri Park'},
      // Terminal 21 already listed in Sukhumvit landmarks
      'exchange tower': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Exchange Tower'},
      'times square': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Times Square'},
      'robinson sukhumvit': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Robinson Sukhumvit'},
      'soi cowboy': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Soi Cowboy'},
      // see districts section for Nana Plaza
      // see hospitals section for Bumrungrad Hospital
      'central embassy': {'lat': 13.7448, 'lng': 100.5448, 'name': 'Central Embassy'},
      'gaysorn': {'lat': 13.7448, 'lng': 100.5398, 'name': 'Gaysorn Village'},
      'amarin plaza': {'lat': 13.7448, 'lng': 100.5348, 'name': 'Amarin Plaza'},
      // Erawan Shrine already listed earlier
      'big c ratchadamri': {'lat': 13.7448, 'lng': 100.5348, 'name': 'Big C Ratchadamri'},
      'central chidlom': {'lat': 13.7448, 'lng': 100.5448, 'name': 'Central Chidlom'},
      'all seasons place': {'lat': 13.7348, 'lng': 100.5448, 'name': 'All Seasons Place'},
      'park ventures': {'lat': 13.7348, 'lng': 100.5348, 'name': 'Park Ventures Ecoplex'},
      'mercury ville': {'lat': 13.7348, 'lng': 100.5248, 'name': 'Mercury Ville'},
      'lumpini tower': {'lat': 13.7298, 'lng': 100.5398, 'name': 'Lumpini Tower'},
      'dusit thani': {'lat': 13.7298, 'lng': 100.5348, 'name': 'Dusit Thani Bangkok'},
      'montien hotel': {'lat': 13.7298, 'lng': 100.5298, 'name': 'Montien Hotel'},
      'narai hotel': {'lat': 13.7298, 'lng': 100.5248, 'name': 'Narai Hotel'},
      'holiday inn silom': {'lat': 13.7298, 'lng': 100.5198, 'name': 'Holiday Inn Bangkok Silom'},
      'lebua tower': {'lat': 13.7148, 'lng': 100.5151, 'name': 'Lebua at State Tower'},
      'shangri la hotel': {'lat': 13.7148, 'lng': 100.5251, 'name': 'Shangri-La Hotel Bangkok'},
      'peninsula hotel': {'lat': 13.7048, 'lng': 100.5351, 'name': 'The Peninsula Bangkok'},
      'oriental hotel': {'lat': 13.7248, 'lng': 100.5151, 'name': 'Mandarin Oriental Bangkok'},
      // Royal Orchid Sheraton already listed in riverside hotels
      'millennium hilton': {'lat': 13.7148, 'lng': 100.5051, 'name': 'Millennium Hilton Bangkok'},
      'chatrium riverside': {'lat': 13.7448, 'lng': 100.5451, 'name': 'Chatrium Hotel Riverside Bangkok'},
      // Anantara Riverside already listed in riverside hotels
      'avani riverside': {'lat': 13.7248, 'lng': 100.5251, 'name': 'Avani Riverside Bangkok Hotel'},
      'ramada plaza': {'lat': 13.7148, 'lng': 100.5151, 'name': 'Ramada Plaza Bangkok Menam Riverside'},
      
      // Specific Sois (Side Streets) - Sukhumvit Area
      'soi 1': {'lat': 13.7378, 'lng': 100.5501, 'name': 'Sukhumvit Soi 1'},
      'soi 3': {'lat': 13.7378, 'lng': 100.5521, 'name': 'Sukhumvit Soi 3'},
      'soi 5': {'lat': 13.7378, 'lng': 100.5541, 'name': 'Sukhumvit Soi 5'},
      'soi 7': {'lat': 13.7378, 'lng': 100.5561, 'name': 'Sukhumvit Soi 7'},
      'soi 8': {'lat': 13.7378, 'lng': 100.5571, 'name': 'Sukhumvit Soi 8'},
      'soi 11': {'lat': 13.7378, 'lng': 100.5581, 'name': 'Sukhumvit Soi 11'},
      'soi 13': {'lat': 13.7378, 'lng': 100.5591, 'name': 'Sukhumvit Soi 13'},
      'soi 15': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Sukhumvit Soi 15'},
      'soi 16': {'lat': 13.7378, 'lng': 100.5611, 'name': 'Sukhumvit Soi 16'},
      'soi 19': {'lat': 13.7378, 'lng': 100.5621, 'name': 'Sukhumvit Soi 19'},
      'soi 21': {'lat': 13.7378, 'lng': 100.5631, 'name': 'Sukhumvit Soi 21'},
      'soi 22': {'lat': 13.7378, 'lng': 100.5641, 'name': 'Sukhumvit Soi 22'},
      'soi 23': {'lat': 13.7378, 'lng': 100.5651, 'name': 'Sukhumvit Soi 23'},
      'soi 24': {'lat': 13.7378, 'lng': 100.5661, 'name': 'Sukhumvit Soi 24'},
      'soi 26': {'lat': 13.7378, 'lng': 100.5671, 'name': 'Sukhumvit Soi 26'},
      'soi 31': {'lat': 13.7378, 'lng': 100.5681, 'name': 'Sukhumvit Soi 31'},
      'soi 33': {'lat': 13.7378, 'lng': 100.5691, 'name': 'Sukhumvit Soi 33'},
      'soi 35': {'lat': 13.7378, 'lng': 100.5701, 'name': 'Sukhumvit Soi 35'},
      'soi 36': {'lat': 13.7378, 'lng': 100.5711, 'name': 'Sukhumvit Soi 36'},
      'soi 38': {'lat': 13.7378, 'lng': 100.5721, 'name': 'Sukhumvit Soi 38'},
      'soi 39': {'lat': 13.7378, 'lng': 100.5731, 'name': 'Sukhumvit Soi 39'},
      'soi 49': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Sukhumvit Soi 49 (Thonglor)'},
      'soi 55': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Sukhumvit Soi 55 (Thonglor)'},
      'soi 63': {'lat': 13.7198, 'lng': 100.5850, 'name': 'Sukhumvit Soi 63 (Ekkamai)'},
      'soi 71': {'lat': 13.7098, 'lng': 100.5950, 'name': 'Sukhumvit Soi 71'},
      'soi 77': {'lat': 13.7048, 'lng': 100.5998, 'name': 'Sukhumvit Soi 77 (On Nut)'},
      'soi 81': {'lat': 13.6998, 'lng': 100.6048, 'name': 'Sukhumvit Soi 81'},
      'soi 101': {'lat': 13.6598, 'lng': 100.6098, 'name': 'Sukhumvit Soi 101 (Bearing)'},
      'soi 103': {'lat': 13.6548, 'lng': 100.6118, 'name': 'Sukhumvit Soi 103'},
      'soi 107': {'lat': 13.6498, 'lng': 100.6138, 'name': 'Sukhumvit Soi 107'},
      
      // Silom Area Sois
      'silom soi 1': {'lat': 13.7307, 'lng': 100.5318, 'name': 'Silom Soi 1'},
      'silom soi 2': {'lat': 13.7307, 'lng': 100.5328, 'name': 'Silom Soi 2'},
      'silom soi 4': {'lat': 13.7307, 'lng': 100.5338, 'name': 'Silom Soi 4'},
      'silom soi 6': {'lat': 13.7307, 'lng': 100.5348, 'name': 'Silom Soi 6'},
      'silom soi 8': {'lat': 13.7307, 'lng': 100.5358, 'name': 'Silom Soi 8'},
      'thaniya plaza': {'lat': 13.7307, 'lng': 100.5368, 'name': 'Thaniya Plaza'},
      'patpong': {'lat': 13.7307, 'lng': 100.5378, 'name': 'Patpong'},
      'patpong 1': {'lat': 13.7307, 'lng': 100.5378, 'name': 'Patpong 1'},
      'patpong 2': {'lat': 13.7307, 'lng': 100.5388, 'name': 'Patpong 2'},
      
      // Convenience Stores (7-Eleven locations)
      '7 eleven siam': {'lat': 13.7460, 'lng': 100.5348, 'name': '7-Eleven Siam Square'},
      '7 eleven asok': {'lat': 13.7378, 'lng': 100.5601, 'name': '7-Eleven Asok'},
      '7 eleven thonglor': {'lat': 13.7298, 'lng': 100.5698, 'name': '7-Eleven Thonglor'},
      '7 eleven ekkamai': {'lat': 13.7198, 'lng': 100.5850, 'name': '7-Eleven Ekkamai'},
      '7 eleven silom': {'lat': 13.7307, 'lng': 100.5418, 'name': '7-Eleven Silom'},
      '7 eleven sathorn': {'lat': 13.7198, 'lng': 100.5298, 'name': '7-Eleven Sathorn'},
      '7 eleven ploenchit': {'lat': 13.7460, 'lng': 100.5348, 'name': '7-Eleven Ploenchit'},
      '7 eleven phrom phong': {'lat': 13.7308, 'lng': 100.5698, 'name': '7-Eleven Phrom Phong'},
      '7 eleven nana': {'lat': 13.7378, 'lng': 100.5601, 'name': '7-Eleven Nana'},
      '7 eleven victory monument': {'lat': 13.7647, 'lng': 100.5370, 'name': '7-Eleven Victory Monument'},
      '7 eleven chatuchak': {'lat': 13.7998, 'lng': 100.5498, 'name': '7-Eleven Chatuchak'},
      '7 eleven khaosan': {'lat': 13.7590, 'lng': 100.4977, 'name': '7-Eleven Khaosan Road'},
      '7 eleven pratunam': {'lat': 13.7498, 'lng': 100.5398, 'name': '7-Eleven Pratunam'},
      '7 eleven ratchathewi': {'lat': 13.7563, 'lng': 100.5018, 'name': '7-Eleven Ratchathewi'},
      '7 eleven huai khwang': {'lat': 13.7698, 'lng': 100.5798, 'name': '7-Eleven Huai Khwang'},
      '7 eleven ramkhamhaeng': {'lat': 13.7598, 'lng': 100.6098, 'name': '7-Eleven Ramkhamhaeng'},
      '7 eleven on nut': {'lat': 13.7048, 'lng': 100.5998, 'name': '7-Eleven On Nut'},
      '7 eleven bearing': {'lat': 13.6598, 'lng': 100.6098, 'name': '7-Eleven Bearing'},
      
      // Family Mart locations
      'family mart siam': {'lat': 13.7460, 'lng': 100.5358, 'name': 'FamilyMart Siam Square'},
      'family mart asok': {'lat': 13.7378, 'lng': 100.5611, 'name': 'FamilyMart Asok'},
      'family mart thonglor': {'lat': 13.7298, 'lng': 100.5708, 'name': 'FamilyMart Thonglor'},
      'family mart silom': {'lat': 13.7307, 'lng': 100.5428, 'name': 'FamilyMart Silom'},
      'family mart terminal 21': {'lat': 13.7378, 'lng': 100.5601, 'name': 'FamilyMart Terminal 21'},
      'family mart emquartier': {'lat': 13.7298, 'lng': 100.5698, 'name': 'FamilyMart EmQuartier'},
      'family mart central world': {'lat': 13.7472, 'lng': 100.5398, 'name': 'FamilyMart Central World'},
      'family mart mbk': {'lat': 13.7441, 'lng': 100.5300, 'name': 'FamilyMart MBK'},
      
      // Local Pharmacies
      'boots siam paragon': {'lat': 13.7460, 'lng': 100.5348, 'name': 'Boots Siam Paragon'},
      'boots terminal 21': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Boots Terminal 21'},
      'boots central world': {'lat': 13.7472, 'lng': 100.5398, 'name': 'Boots Central World'},
      'boots emquartier': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Boots EmQuartier'},
      'watsons siam': {'lat': 13.7460, 'lng': 100.5358, 'name': 'Watsons Siam Square'},
      'watsons asok': {'lat': 13.7378, 'lng': 100.5611, 'name': 'Watsons Asok'},
      'watsons thonglor': {'lat': 13.7298, 'lng': 100.5708, 'name': 'Watsons Thonglor'},
      'watsons silom': {'lat': 13.7307, 'lng': 100.5428, 'name': 'Watsons Silom'},
      'fascino pharmacy': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Fascino Pharmacy'},
      'pharmacy one': {'lat': 13.7460, 'lng': 100.5348, 'name': 'Pharmacy One'},
      
      // Gas Stations (PTT, Shell, Esso)
      'ptt siam': {'lat': 13.7460, 'lng': 100.5348, 'name': 'PTT Gas Station Siam'},
      'ptt asok': {'lat': 13.7378, 'lng': 100.5601, 'name': 'PTT Gas Station Asok'},
      'ptt thonglor': {'lat': 13.7298, 'lng': 100.5698, 'name': 'PTT Gas Station Thonglor'},
      'ptt silom': {'lat': 13.7307, 'lng': 100.5418, 'name': 'PTT Gas Station Silom'},
      'ptt sathorn': {'lat': 13.7198, 'lng': 100.5298, 'name': 'PTT Gas Station Sathorn'},
      'ptt victory monument': {'lat': 13.7647, 'lng': 100.5370, 'name': 'PTT Gas Station Victory Monument'},
      'shell siam': {'lat': 13.7460, 'lng': 100.5358, 'name': 'Shell Gas Station Siam'},
      'shell asok': {'lat': 13.7378, 'lng': 100.5611, 'name': 'Shell Gas Station Asok'},
      'shell thonglor': {'lat': 13.7298, 'lng': 100.5708, 'name': 'Shell Gas Station Thonglor'},
      'shell silom': {'lat': 13.7307, 'lng': 100.5428, 'name': 'Shell Gas Station Silom'},
      'esso siam': {'lat': 13.7460, 'lng': 100.5368, 'name': 'Esso Gas Station Siam'},
      'esso asok': {'lat': 13.7378, 'lng': 100.5621, 'name': 'Esso Gas Station Asok'},
      'bangchak siam': {'lat': 13.7460, 'lng': 100.5378, 'name': 'Bangchak Gas Station Siam'},
      'bangchak thonglor': {'lat': 13.7298, 'lng': 100.5718, 'name': 'Bangchak Gas Station Thonglor'},
      
      // ATMs and Banks
      'kasikorn siam': {'lat': 13.7460, 'lng': 100.5348, 'name': 'Kasikorn Bank Siam'},
      'kasikorn asok': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Kasikorn Bank Asok'},
      'kasikorn thonglor': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Kasikorn Bank Thonglor'},
      'kasikorn silom': {'lat': 13.7307, 'lng': 100.5418, 'name': 'Kasikorn Bank Silom'},
      'bangkok bank siam': {'lat': 13.7460, 'lng': 100.5358, 'name': 'Bangkok Bank Siam'},
      'bangkok bank asok': {'lat': 13.7378, 'lng': 100.5611, 'name': 'Bangkok Bank Asok'},
      'bangkok bank thonglor': {'lat': 13.7298, 'lng': 100.5708, 'name': 'Bangkok Bank Thonglor'},
      'bangkok bank silom': {'lat': 13.7307, 'lng': 100.5428, 'name': 'Bangkok Bank Silom'},
      'scb siam': {'lat': 13.7460, 'lng': 100.5368, 'name': 'Siam Commercial Bank Siam'},
      'scb asok': {'lat': 13.7378, 'lng': 100.5621, 'name': 'Siam Commercial Bank Asok'},
      'scb thonglor': {'lat': 13.7298, 'lng': 100.5718, 'name': 'Siam Commercial Bank Thonglor'},
      'krungsri siam': {'lat': 13.7460, 'lng': 100.5378, 'name': 'Krungsri Bank Siam'},
      'krungsri asok': {'lat': 13.7378, 'lng': 100.5631, 'name': 'Krungsri Bank Asok'},
      'tmc siam': {'lat': 13.7460, 'lng': 100.5388, 'name': 'TMB Bank Siam'},
      'tmc asok': {'lat': 13.7378, 'lng': 100.5641, 'name': 'TMB Bank Asok'},
      
      // Small Local Restaurants & Street Food
      'som tam jay so': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Som Tam Jay So (Street Food)'},
      'khao tom pui': {'lat': 13.7460, 'lng': 100.5348, 'name': 'Khao Tom Pui (Rice Porridge)'},
      'kuay teow reua': {'lat': 13.7307, 'lng': 100.5418, 'name': 'Kuay Teow Reua (Boat Noodles)'},
      'mango sticky rice lady': {'lat': 13.7590, 'lng': 100.4977, 'name': 'Mango Sticky Rice Lady Khaosan'},
      'pad thai thip samai': {'lat': 13.7667, 'lng': 100.5137, 'name': 'Pad Thai Thip Samai'},
      'jay fai crab omelette': {'lat': 13.7567, 'lng': 100.5037, 'name': 'Jay Fai Crab Omelette'},
      'boat noodles victory monument': {'lat': 13.7647, 'lng': 100.5370, 'name': 'Boat Noodles Victory Monument'},
      'khao soi mae sai': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Khao Soi Mae Sai Thonglor'},
      'som tam der': {'lat': 13.7367, 'lng': 100.5637, 'name': 'Som Tam Der'},
      'krua thai': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Krua Thai Local Restaurant'},
      'nai mong hoi tod': {'lat': 13.7590, 'lng': 100.4977, 'name': 'Nai Mong Hoi Tod (Oyster Pancake)'},
      'roti mataba': {'lat': 13.7590, 'lng': 100.4977, 'name': 'Roti Mataba Khaosan'},
      'khao pad american': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Khao Pad American (Fried Rice)'},
      'moo ping': {'lat': 13.7460, 'lng': 100.5348, 'name': 'Moo Ping (Grilled Pork Skewers)'},
      'sai krok isan': {'lat': 13.7647, 'lng': 100.5370, 'name': 'Sai Krok Isan (Fermented Sausage)'},
      'larb udon': {'lat': 13.7647, 'lng': 100.5370, 'name': 'Larb Udon (Spicy Meat Salad)'},
      'khao kriab pak moh': {'lat': 13.7590, 'lng': 100.4977, 'name': 'Khao Kriab Pak Moh (Dumpling)'},
      'kanom krok': {'lat': 13.7590, 'lng': 100.4977, 'name': 'Kanom Krok (Coconut Pancakes)'},
      'thai tea uncle': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Thai Tea Uncle'},
      'coconut ice cream cart': {'lat': 13.7460, 'lng': 100.5348, 'name': 'Coconut Ice Cream Cart'},
      
      // Small Local Shops & Services
      'tailor shop sukhumvit': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Tailor Shop Sukhumvit'},
      'laundry shop thonglor': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Laundry Shop Thonglor'},
      'barber shop silom': {'lat': 13.7307, 'lng': 100.5418, 'name': 'Barber Shop Silom'},
      'nail salon asok': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Nail Salon Asok'},
      'massage shop khaosan': {'lat': 13.7590, 'lng': 100.4977, 'name': 'Massage Shop Khaosan'},
      'phone repair shop mbk': {'lat': 13.7441, 'lng': 100.5300, 'name': 'Phone Repair Shop MBK'},
      'key cutting service': {'lat': 13.7460, 'lng': 100.5348, 'name': 'Key Cutting Service'},
      'shoe repair shop': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Shoe Repair Shop'},
      'photocopy shop': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Photocopy Shop'},
      'internet cafe': {'lat': 13.7590, 'lng': 100.4977, 'name': 'Internet Cafe'},
      'travel agency khaosan': {'lat': 13.7590, 'lng': 100.4977, 'name': 'Travel Agency Khaosan'},
      'currency exchange': {'lat': 13.7460, 'lng': 100.5348, 'name': 'Currency Exchange'},
      'gold shop yaowarat': {'lat': 13.7398, 'lng': 100.5067, 'name': 'Gold Shop Yaowarat'},
      'flower shop': {'lat': 13.7460, 'lng': 100.5348, 'name': 'Flower Shop'},
      'fruit vendor': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Fruit Vendor'},
      'newspaper stand': {'lat': 13.7460, 'lng': 100.5348, 'name': 'Newspaper Stand'},
      'lottery ticket seller': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Lottery Ticket Seller'},
      
      // Residential Buildings & Condos
      'the address asoke': {'lat': 13.7378, 'lng': 100.5601, 'name': 'The Address Asoke'},
      'noble remix': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Noble Remix Thonglor'},
      'the emporio place': {'lat': 13.7298, 'lng': 100.5698, 'name': 'The Emporio Place'},
      'quattro thonglor': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Quattro by Sansiri Thonglor'},
      'via 31': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Via 31 Condominium'},
      'the lofts asoke': {'lat': 13.7378, 'lng': 100.5601, 'name': 'The Lofts Asoke'},
      'terminal 21 residence': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Terminal 21 Residence'},
      'noble reveal': {'lat': 13.7198, 'lng': 100.5850, 'name': 'Noble Reveal Ekkamai'},
      'the nest sukhumvit 22': {'lat': 13.7378, 'lng': 100.5641, 'name': 'The Nest Sukhumvit 22'},
      'noble be33': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Noble BE33 Sukhumvit'},
      'the room sukhumvit 21': {'lat': 13.7378, 'lng': 100.5631, 'name': 'The Room Sukhumvit 21'},
      'circle condominium': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Circle Condominium'},
      'h sukhumvit 43': {'lat': 13.7298, 'lng': 100.5698, 'name': 'H Sukhumvit 43'},
      'the diplomat 39': {'lat': 13.7298, 'lng': 100.5698, 'name': 'The Diplomat 39'},
      'noble solo': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Noble Solo Thonglor'},
      'the room sathorn': {'lat': 13.7198, 'lng': 100.5298, 'name': 'The Room Sathorn'},
      'ivy thonglor': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Ivy Thonglor'},
      'the lumpini 24': {'lat': 13.7298, 'lng': 100.5398, 'name': 'The Lumpini 24'},
      'ashton asoke': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Ashton Asoke'},
      'rhythm sukhumvit': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Rhythm Sukhumvit'},
      
      // Small Neighborhood Markets
      'fresh market thonglor': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Fresh Market Thonglor'},
      'villa market sukhumvit': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Villa Market Sukhumvit'},
      'tops market asok': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Tops Market Asok'},
      'foodland silom': {'lat': 13.7307, 'lng': 100.5418, 'name': 'Foodland Silom'},
      'big c mini': {'lat': 13.7460, 'lng': 100.5348, 'name': 'Big C Mini'},
      'lotus express': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Lotus Express'},
      'makro': {'lat': 13.7598, 'lng': 100.6098, 'name': 'Makro Ramkhamhaeng'},
      'tesco lotus': {'lat': 13.7647, 'lng': 100.5370, 'name': 'Tesco Lotus Victory Monument'},
      'gourmet market': {'lat': 13.7460, 'lng': 100.5348, 'name': 'Gourmet Market Siam Paragon'},
      'dean deluca': {'lat': 13.7467, 'lng': 100.5537, 'name': 'Dean & DeLuca'},
      
      // Local Clinics & Small Medical Centers
      'dental clinic sukhumvit': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Dental Clinic Sukhumvit'},
      'skin clinic thonglor': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Skin Clinic Thonglor'},
      'eye clinic silom': {'lat': 13.7307, 'lng': 100.5418, 'name': 'Eye Clinic Silom'},
      'vet clinic asok': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Veterinary Clinic Asok'},
      'physiotherapy clinic': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Physiotherapy Clinic'},
      'acupuncture clinic': {'lat': 13.7307, 'lng': 100.5418, 'name': 'Acupuncture Clinic'},
      
      // Local Gyms & Fitness Centers
      'fitness first siam': {'lat': 13.7460, 'lng': 100.5348, 'name': 'Fitness First Siam'},
      'fitness first asok': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Fitness First Asok'},
      'virgin active': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Virgin Active Thonglor'},
      'california wow': {'lat': 13.7307, 'lng': 100.5418, 'name': 'California WOW Silom'},
      'true fitness': {'lat': 13.7378, 'lng': 100.5601, 'name': 'True Fitness'},
      'anytime fitness': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Anytime Fitness'},
      'muay thai gym': {'lat': 13.7590, 'lng': 100.4977, 'name': 'Muay Thai Gym Khaosan'},
      'yoga studio': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Yoga Studio'},
      'pilates studio': {'lat': 13.7307, 'lng': 100.5418, 'name': 'Pilates Studio'},
      
      // Local Temples & Small Shrines
      'erawan shrine': {'lat': 13.7448, 'lng': 100.5398, 'name': 'Erawan Shrine'},
      'trimurti shrine': {'lat': 13.7472, 'lng': 100.5398, 'name': 'Trimurti Shrine'},
      'ganesha shrine': {'lat': 13.7472, 'lng': 100.5398, 'name': 'Ganesha Shrine'},
      'lak mueang': {'lat': 13.7548, 'lng': 100.4948, 'name': 'Lak Mueang (City Pillar Shrine)'},
      'wat pathum wanaram': {'lat': 13.7460, 'lng': 100.5348, 'name': 'Wat Pathum Wanaram'},
      'wat hua lamphong': {'lat': 13.7398, 'lng': 100.5167, 'name': 'Wat Hua Lamphong'},
      'wat khaek': {'lat': 13.7307, 'lng': 100.5418, 'name': 'Wat Khaek (Sri Mariamman Temple)'},
      'wat chaeng': {'lat': 13.7198, 'lng': 100.4898, 'name': 'Wat Chaeng'},
      'wat yan nawa': {'lat': 13.6998, 'lng': 100.5298, 'name': 'Wat Yan Nawa'},
      'wat thong nopphakhun': {'lat': 13.7698, 'lng': 100.4798, 'name': 'Wat Thong Nopphakhun'},
      
      // Local Parks & Green Spaces
      // Benjakiti Park already listed earlier
      // Benchasiri Park already listed earlier
      // Lumpini Park already listed earlier
      // Chuvit Garden already listed earlier
      // Romaneenart Park already listed earlier
      // Santiphap Park already listed earlier
      // Suan Santi Chaiprakarn already listed earlier
      'saranrom park': {'lat': 13.7498, 'lng': 100.4998, 'name': 'Saranrom Park'},
      // Suan Rot Fai already listed earlier
      // King Rama IX Park already listed earlier
      
      // Local Internet Cafes & Co-working Spaces
      'hubba to': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Hubba-TO Co-working Space'},
      'launchpad': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Launchpad Co-working'},
      'the hive': {'lat': 13.7298, 'lng': 100.5698, 'name': 'The Hive Thonglor'},
      'glowfish': {'lat': 13.7307, 'lng': 100.5418, 'name': 'Glowfish Offices'},
      'regus': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Regus Business Center'},
      'spaces': {'lat': 13.7460, 'lng': 100.5348, 'name': 'Spaces Co-working'},
      'wework': {'lat': 13.7378, 'lng': 100.5601, 'name': 'WeWork'},
      'dojo bali': {'lat': 13.7298, 'lng': 100.5698, 'name': 'Dojo Bali Co-working'},
      
      // Khon Kaen University
      // Khon Kaen University main campus already listed earlier
      'KKU': {'lat': 16.4419, 'lng': 102.8236},
      'Khon Kaen University Faculty of Medicine': {'lat': 16.4419, 'lng': 102.8236},
      'Khon Kaen University Faculty of Engineering': {'lat': 16.4419, 'lng': 102.8236},
      'Khon Kaen University Faculty of Agriculture': {'lat': 16.4419, 'lng': 102.8236},
      
      // Naresuan University
      'Naresuan University': {'lat': 16.7419, 'lng': 100.1936},
      'NU': {'lat': 16.7419, 'lng': 100.1936},
      'Naresuan University Faculty of Medicine': {'lat': 16.7419, 'lng': 100.1936},
      'Naresuan University Faculty of Engineering': {'lat': 16.7419, 'lng': 100.1936},
      'Naresuan University Faculty of Science': {'lat': 16.7419, 'lng': 100.1936},
      
      // Burapha University - Multiple Campuses
      'Burapha University Bangsaen Campus': {'lat': 13.2781, 'lng': 100.9298},
      'Burapha University Chanthaburi Campus': {'lat': 12.6103, 'lng': 102.1038},
      'Burapha University Sakaeo Campus': {'lat': 13.8239, 'lng': 102.0697},
      
      // Walailak University
      'Walailak University': {'lat': 8.6781, 'lng': 99.8956},
      'WU': {'lat': 8.6781, 'lng': 99.8956},
      'Walailak University Faculty of Medicine': {'lat': 8.6781, 'lng': 99.8956},
      'Walailak University Faculty of Engineering': {'lat': 8.6781, 'lng': 99.8956},
      
      // Suranaree University of Technology
      'Suranaree University of Technology': {'lat': 14.8781, 'lng': 102.0156},
      'SUT': {'lat': 14.8781, 'lng': 102.0156},
      'SUT Faculty of Engineering': {'lat': 14.8781, 'lng': 102.0156},
      'SUT Faculty of Science': {'lat': 14.8781, 'lng': 102.0156},
      
      // Rajamangala University of Technology - Multiple Campuses
      'Rajamangala University of Technology Thanyaburi': {'lat': 14.0381, 'lng': 100.7256},
      'RMUTT': {'lat': 14.0381, 'lng': 100.7256},
      'Rajamangala University of Technology Krungthep': {'lat': 13.7281, 'lng': 100.5156},
      'RMUTK': {'lat': 13.7281, 'lng': 100.5156},
      'Rajamangala University of Technology Phra Nakhon': {'lat': 13.7681, 'lng': 100.5056},
      'RMUTP': {'lat': 13.7681, 'lng': 100.5056},
      'Rajamangala University of Technology Rattanakosin': {'lat': 13.7181, 'lng': 100.4956},
      'RMUTR': {'lat': 13.7181, 'lng': 100.4956},
      'TSU': {'lat': 7.5581, 'lng': 99.6156},
      'Thaksin University Songkhla Campus': {'lat': 7.5581, 'lng': 99.6156},
      'Thaksin University Phatthalung Campus': {'lat': 7.6181, 'lng': 100.0756},
      
      'Ubon Ratchathani University': {'lat': 15.2481, 'lng': 104.8456},
      'UBU': {'lat': 15.2481, 'lng': 104.8456},
      'UBU Faculty of Medicine': {'lat': 15.2481, 'lng': 104.8456},
      'UBU Faculty of Engineering': {'lat': 15.2481, 'lng': 104.8456},
      
      'Mae Fah Luang University': {'lat': 20.0381, 'lng': 99.8756},
      'MFU': {'lat': 20.0381, 'lng': 99.8756},
      'MFU School of Medicine': {'lat': 20.0381, 'lng': 99.8756},
      'MFU School of Engineering': {'lat': 20.0381, 'lng': 99.8756},
      
      // Shopping Centers & Malls
      'siam paragon': {'lat': 13.7460, 'lng': 100.5348, 'name': 'Siam Paragon'},
      'mbk': {'lat': 13.7441, 'lng': 100.5300, 'name': 'MBK Center'},
      'terminal 21': {'lat': 13.7378, 'lng': 100.5601, 'name': 'Terminal 21'},
      'central world': {'lat': 13.7472, 'lng': 100.5398, 'name': 'Central World'},
      // EmQuartier already listed in Sukhumvit landmarks
      'iconsiam': {'lat': 13.7267, 'lng': 100.5101, 'name': 'ICONSIAM'},
      'siam center': {'lat': 13.7460, 'lng': 100.5348, 'name': 'Siam Center'},
      'siam discovery': {'lat': 13.7460, 'lng': 100.5348, 'name': 'Siam Discovery'},
      'platinum fashion mall': {'lat': 13.7563, 'lng': 100.5018, 'name': 'Platinum Fashion Mall'},
      'pratunam market': {'lat': 13.7563, 'lng': 100.5018, 'name': 'Pratunam Market'},
      'jj green': {'lat': 13.7998, 'lng': 100.5501, 'name': 'JJ Green Night Market'},
      'rot fai market': {'lat': 13.7998, 'lng': 100.5501, 'name': 'Rot Fai Market'},
      'asiatique': {'lat': 13.7048, 'lng': 100.5065, 'name': 'Asiatique The Riverfront'},
      'the mall bangkapi': {'lat': 13.7598, 'lng': 100.6401, 'name': 'The Mall Bangkapi'},
      'seacon square': {'lat': 13.6598, 'lng': 100.6001, 'name': 'Seacon Square'},
      'mega bangna': {'lat': 13.6598, 'lng': 100.6001, 'name': 'Mega Bangna'},
      'central ladprao': {'lat': 13.8198, 'lng': 100.6101, 'name': 'Central Ladprao'},
      'union mall': {'lat': 13.8198, 'lng': 100.6101, 'name': 'Union Mall'},
      'future park rangsit': {'lat': 14.0598, 'lng': 100.6201, 'name': 'Future Park Rangsit'},
      
      // Temples & Religious Sites
      'grand palace': {'lat': 13.7500, 'lng': 100.4915, 'name': 'Grand Palace'},
      'wat pho': {'lat': 13.7468, 'lng': 100.4929, 'name': 'Wat Pho (Temple of Reclining Buddha)'},
      'wat arun': {'lat': 13.7437, 'lng': 100.4887, 'name': 'Wat Arun (Temple of Dawn)'},
      'wat saket': {'lat': 13.7563, 'lng': 100.5018, 'name': 'Wat Saket (Golden Mount)'},
      'wat benchamabophit': {'lat': 13.7563, 'lng': 100.5018, 'name': 'Wat Benchamabophit (Marble Temple)'},
      'wat suthat': {'lat': 13.7563, 'lng': 100.5018, 'name': 'Wat Suthat'},
      'wat traimit': {'lat': 13.7398, 'lng': 100.5066, 'name': 'Wat Traimit (Golden Buddha)'},
      'wat mahathat': {'lat': 14.3692, 'lng': 100.5877, 'name': 'Wat Mahathat (Ayutthaya)'},
      'wat chaiwatthanaram': {'lat': 14.3692, 'lng': 100.5877, 'name': 'Wat Chaiwatthanaram'},
      'wat phra singh': {'lat': 18.7883, 'lng': 98.9853, 'name': 'Wat Phra Singh (Chiang Mai)'},
      'wat doi suthep': {'lat': 18.8048, 'lng': 98.9218, 'name': 'Wat Phra That Doi Suthep'},
      'wat rong khun': {'lat': 19.8242, 'lng': 99.7634, 'name': 'Wat Rong Khun (White Temple)'},
      
      // Markets & Street Food
      // Chatuchak Weekend Market already listed earlier
      'damnoen saduak floating market': {'lat': 13.5225, 'lng': 100.1075, 'name': 'Damnoen Saduak Floating Market'},
      'amphawa floating market': {'lat': 13.4198, 'lng': 99.9598, 'name': 'Amphawa Floating Market'},
      'maeklong railway market': {'lat': 13.4198, 'lng': 99.9598, 'name': 'Maeklong Railway Market'},
      // Saphan Phut Night Market already listed earlier
      // Huai Khwang Night Market already listed earlier
      // Wang Thonglang Market already listed earlier
      // Lat Mayom Floating Market already listed earlier
      // Khlong Toei Market already listed earlier
      
      // Transportation Hubs
      'suvarnabhumi airport': {'lat': 13.6900, 'lng': 100.7501, 'name': 'Suvarnabhumi Airport (BKK)'},
      'don mueang airport': {'lat': 13.9126, 'lng': 100.6070, 'name': 'Don Mueang Airport (DMK)'},
      'hua lamphong station': {'lat': 13.7398, 'lng': 100.5166, 'name': 'Hua Lamphong Railway Station'},
      'bang sue grand station': {'lat': 13.8198, 'lng': 100.5301, 'name': 'Bang Sue Grand Station'},
      'mo chit bus terminal': {'lat': 13.8198, 'lng': 100.5501, 'name': 'Mo Chit Bus Terminal'},
      'ekkamai bus terminal': {'lat': 13.7198, 'lng': 100.5850, 'name': 'Ekkamai Bus Terminal'},
      'southern bus terminal': {'lat': 13.6598, 'lng': 100.4801, 'name': 'Southern Bus Terminal'},
      
      // BTS Stations (Major)
      'bts siam': {'lat': 13.7460, 'lng': 100.5348, 'name': 'BTS Siam Station'},
      'bts asok': {'lat': 13.7378, 'lng': 100.5601, 'name': 'BTS Asok Station'},
      'bts phrom phong': {'lat': 13.7308, 'lng': 100.5698, 'name': 'BTS Phrom Phong Station'},
      'bts thong lo': {'lat': 13.7308, 'lng': 100.5698, 'name': 'BTS Thong Lo Station'},
      'bts ekkamai': {'lat': 13.7198, 'lng': 100.5850, 'name': 'BTS Ekkamai Station'},
      'bts on nut': {'lat': 13.7048, 'lng': 100.6001, 'name': 'BTS On Nut Station'},
      'bts bearing': {'lat': 13.6598, 'lng': 100.6001, 'name': 'BTS Bearing Station'},
      'bts mo chit': {'lat': 13.8198, 'lng': 100.5501, 'name': 'BTS Mo Chit Station'},
      'bts chatuchak park': {'lat': 13.7998, 'lng': 100.5501, 'name': 'BTS Chatuchak Park Station'},
      'bts victory monument': {'lat': 13.7563, 'lng': 100.5018, 'name': 'BTS Victory Monument Station'},
      
      // MRT Stations (Major)
      'mrt sukhumvit': {'lat': 13.7378, 'lng': 100.5601, 'name': 'MRT Sukhumvit Station'},
      'mrt silom': {'lat': 13.7307, 'lng': 100.5418, 'name': 'MRT Silom Station'},
      'mrt chatuchak park': {'lat': 13.7998, 'lng': 100.5501, 'name': 'MRT Chatuchak Park Station'},
      'mrt lat phrao': {'lat': 13.8198, 'lng': 100.6101, 'name': 'MRT Lat Phrao Station'},
      'mrt ratchadaphisek': {'lat': 13.7798, 'lng': 100.5601, 'name': 'MRT Ratchadaphisek Station'},
      
      // Hotels & Accommodations
      'mandarin oriental': {'lat': 13.7248, 'lng': 100.5151, 'name': 'Mandarin Oriental Bangkok'},
      'shangri la': {'lat': 13.7248, 'lng': 100.5151, 'name': 'Shangri-La Hotel Bangkok'},
      // The Peninsula Bangkok already listed earlier
      'lebua': {'lat': 13.7248, 'lng': 100.5151, 'name': 'Lebua at State Tower'},
      // Centara Grand already listed earlier
      'intercontinental': {'lat': 13.7308, 'lng': 100.5698, 'name': 'InterContinental Bangkok'},
      
      // Islands & Beaches
      'koh phi phi': {'lat': 7.7407, 'lng': 98.7784, 'name': 'Koh Phi Phi'},
      'koh lanta': {'lat': 7.5649, 'lng': 99.0404, 'name': 'Koh Lanta'},
      'koh tao': {'lat': 10.0956, 'lng': 99.8397, 'name': 'Koh Tao'},
      'koh phangan': {'lat': 9.7382, 'lng': 100.0270, 'name': 'Koh Phangan'},
      'koh chang': {'lat': 12.0407, 'lng': 102.3350, 'name': 'Koh Chang'},
      'koh samet': {'lat': 12.5649, 'lng': 101.4604, 'name': 'Koh Samet'},
      'railay beach': {'lat': 8.0123, 'lng': 98.8407, 'name': 'Railay Beach'},
      'ao nang': {'lat': 8.0363, 'lng': 98.8263, 'name': 'Ao Nang Beach'},
      'patong beach': {'lat': 7.8967, 'lng': 98.2967, 'name': 'Patong Beach'},
      'kata beach': {'lat': 7.8167, 'lng': 98.2967, 'name': 'Kata Beach'},
      'karon beach': {'lat': 7.8367, 'lng': 98.2967, 'name': 'Karon Beach'},
      'bang tao beach': {'lat': 8.0167, 'lng': 98.2767, 'name': 'Bang Tao Beach'},
      'lamai beach': {'lat': 9.4618, 'lng': 100.0538, 'name': 'Lamai Beach'},
      'chaweng beach': {'lat': 9.5318, 'lng': 100.0738, 'name': 'Chaweng Beach'},
      
      // National Parks & Nature
      'khao yai national park': {'lat': 14.4292, 'lng': 101.3717, 'name': 'Khao Yai National Park'},
      'erawan national park': {'lat': 14.3717, 'lng': 99.1417, 'name': 'Erawan National Park'},
      'doi inthanon': {'lat': 18.5892, 'lng': 98.4817, 'name': 'Doi Inthanon National Park'},
      'khao sok national park': {'lat': 8.9117, 'lng': 98.5317, 'name': 'Khao Sok National Park'},
      'similan islands': {'lat': 8.6417, 'lng': 97.6417, 'name': 'Similan Islands'},
      'surin islands': {'lat': 9.4417, 'lng': 97.8717, 'name': 'Surin Islands'},
    };

    final results = <Map<String, dynamic>>[];
    final queryLower = query.toLowerCase();

    for (final entry in places.entries) {
      final name = entry.value['name'] as String?;
      final displayName = name ?? entry.key;
      
      // Search in both key and name (if exists)
      bool matches = entry.key.toLowerCase().contains(queryLower);
      if (!matches && name != null) {
        matches = name.toLowerCase().contains(queryLower);
      }
      
      if (matches) {
        results.add({
          'title': displayName,
          'latitude': entry.value['lat'],
          'longitude': entry.value['lng'],
          'id': 'place_${entry.key}',
          'type': 'place',
        });
      }
    }
    
    // Sort results by relevance (exact matches first, then partial matches)
    results.sort((a, b) {
      final aTitle = (a['title'] as String).toLowerCase();
      final bTitle = (b['title'] as String).toLowerCase();
      
      // Exact matches first
      if (aTitle.startsWith(queryLower) && !bTitle.startsWith(queryLower)) return -1;
      if (!aTitle.startsWith(queryLower) && bTitle.startsWith(queryLower)) return 1;
      
      // Then alphabetical
      return aTitle.compareTo(bTitle);
    });
    
    // Limit to top 10 results for better performance
    return results;
  }

  void _handleMapTap(LatLng point) {
    // Single tap - show popup with pin
    setState(() {
      _selectedLocation = point;
      _showPopup = true;
      _showSearchResults = false;
    });
  }

  // Search places from external API using LocationService
  Future<List<Map<String, dynamic>>> _searchPlacesFromAPI(String query) async {
    return await LocationService.searchPlaces(query);
  }

  // Search incidents
  Future<List<Map<String, dynamic>>> _searchIncidents(String query) async {
    try {
      final querySnapshot = await _firestore
          .collection('incidents')
          .where('title', isGreaterThanOrEqualTo: query)
          .where('title', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(10)
          .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'type': 'incident',
          'title': data['title'] ?? 'Incident',
          'latitude': data['latitude'] ?? 0.0,
          'longitude': data['longitude'] ?? 0.0,
          'id': doc.id,
          'source': 'incident',
        };
      }).toList();
    } catch (e, stack) {
      LoggingService.error(
        'Error searching incidents',
        error: e,
        stackTrace: stack,
        category: _logCategory,
      );
      return [];
    }
  }


  Future<void> _listenToUnreadMessages() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _unreadSubscription?.cancel();
    _unreadSubscription = _firestore
        .collection('chats')
        .where('participants', arrayContains: user.uid)
        .snapshots()
        .listen((snapshot) async {
      int chatsWithUnreadMessages = 0;
      
      // Process all chats in parallel to reduce flickering
      final futures = snapshot.docs.map((doc) async {
        final data = doc.data();
        final chatId = doc.id;
        
        // Check if this chat has any unread messages
        final lastReadTime = data['lastRead_${user.uid}'] ?? Timestamp.fromDate(DateTime(2020));
        
        try {
          final allMessages = await _firestore
              .collection('chats')
              .doc(chatId)
              .collection('messages')
              .where('timestamp', isGreaterThan: lastReadTime)
              .limit(1) // Only need to check if there's at least one
              .get();
              
          // Check if there are any messages from other users
          return allMessages.docs.any((doc) {
            final messageData = doc.data();
            return messageData['senderId'] != user.uid;
          });
        } catch (e, stack) {
          LoggingService.error(
            'Error checking unread messages for chat $chatId',
            error: e,
            stackTrace: stack,
            category: _logCategory,
          );
          return false;
        }
      }).toList();
      
      final results = await Future.wait(futures);
      chatsWithUnreadMessages = results.where((hasUnread) => hasUnread).length;
      
      if (mounted) {
        setState(() {
          _unreadChatCount = chatsWithUnreadMessages;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        final isDark = themeService.isDarkMode;
        
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            // Handle back button - stay on main screen
          },
          child: Scaffold(
      appBar: AppBar(
        title: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: isDark 
              ? [Colors.tealAccent, Colors.cyan]
              : [Colors.teal, Colors.teal.shade700],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: Text(
            'PAISABAI',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ),
        centerTitle: false,
        backgroundColor: isDark ? Colors.black.withValues(alpha: 0.9) : Colors.white,
        elevation: isDark ? 0 : 1,
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
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark 
                  ? [Colors.tealAccent, Colors.cyan]
                  : [Colors.teal, Colors.teal.shade600],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Builder(
              builder: (ctx) => IconButton(
                icon: Icon(Icons.menu, color: isDark ? Colors.black : Colors.white),
                onPressed: () => Scaffold.of(ctx).openEndDrawer(),
              ),
            ),
          ),
        ],
      ),
      endDrawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              Consumer<ThemeService>(
                builder: (context, themeService, child) {
                  return ListTile(
                    leading: Icon(
                      themeService.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                    ),
                    title: Text(themeService.isDarkMode ? 'Light Mode' : 'Dark Mode'),
                    onTap: () {
                      themeService.toggleTheme();
                      Navigator.pop(context);
                    },
                  );
                },
              ),
              const ListTile(
                leading: Icon(Icons.info_outline), 
                title: Text('About')
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: currentIndex,
        children: [
          const ChatListScreen(),
          _buildMapWithSearch(),
          const IncidentReportScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark ? [
              Colors.grey[900]!.withValues(alpha: 0.95),
              Colors.black.withValues(alpha: 0.98),
            ] : [
              Colors.white.withValues(alpha: 0.95),
              Colors.grey[100]!.withValues(alpha: 0.98),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: isDark 
                ? Colors.tealAccent.withValues(alpha: 0.1)
                : Colors.teal.withValues(alpha: 0.1),
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
          selectedItemColor: isDark ? Colors.tealAccent : Colors.teal,
          unselectedItemColor: isDark ? Colors.grey : Colors.black54,
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
                      color: currentIndex == 0 
                        ? (isDark ? Colors.tealAccent.withValues(alpha: 0.2) : Colors.teal.withValues(alpha: 0.2))
                        : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.message_outlined),
                  ),
                  if (_unreadChatCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '$_unreadChatCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              label: 'Chat',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.map),
              label: 'Map',
            ),
            BottomNavigationBarItem(
              icon: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: currentIndex == 2 
                    ? (isDark ? Colors.tealAccent.withValues(alpha: 0.2) : Colors.teal.withValues(alpha: 0.2))
                    : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.assignment_outlined),
              ),
              label: 'Status',
            ),
            BottomNavigationBarItem(
              icon: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: currentIndex == 3 
                    ? (isDark ? Colors.tealAccent.withValues(alpha: 0.2) : Colors.teal.withValues(alpha: 0.2))
                    : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_outline),
              ),
              label: 'Profile',
            ),
          ],
        ),
      ),
    ),
          );
      },
    );
  }

  Widget _buildMapWithSearch() {
    final themeService = Provider.of<ThemeService>(context);
    final isDark = themeService.isDarkMode;
    
    return Scaffold(
      body: Stack(
        children: [
          _buildMap(),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: _buildSearchBar(isDark),
          ),
          if (_showSearchResults && _searchResults.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 78,
              left: 16,
              right: 16,
              child: _buildSearchResults(isDark),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
        decoration: InputDecoration(
          hintText: 'Search places...',
          hintStyle: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
          prefixIcon: Icon(
            Icons.search,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _showSearchResults = false;
                      _searchResults = [];
                    });
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        ),
        onChanged: (value) {
          setState(() {
            // Update suffix icon visibility
          });
          _searchLocations(value);
        },
        onTap: () {
          if (_searchResults.isNotEmpty) {
            setState(() {
              _showSearchResults = true;
            });
          }
        },
      ),
    );
  }

  Widget _buildSearchResults(bool isDark) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final result = _searchResults[index];
          final isPlace = result['type'] == 'place';
          return ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isPlace ? 
                  (result['source'] == 'api' ? Colors.green.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1)) : 
                  Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isPlace ? Icons.place : Icons.report_problem,
                color: isPlace ? 
                  (result['source'] == 'api' ? Colors.green : Colors.blue) : 
                  Colors.orange,
                size: 20,
              ),
            ),
            title: Text(
              result['title'],
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPlace ? 'Location' : 'Incident',
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                if (result['source'] == 'api')
                  Text(
                    'From OpenStreetMap',
                    style: TextStyle(
                      color: Colors.green[600],
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
            trailing: result['source'] == 'api' ? 
              Icon(Icons.public, color: Colors.green[600], size: 16) : 
              Icon(
                Icons.north_west,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                size: 16,
              ),
            onTap: () {
              final targetLat = result['latitude'] as double;
              final targetLng = result['longitude'] as double;
              final targetZoom = isPlace ? 15.0 : 16.0;
              
              // Move map to location
              mapController.move(LatLng(targetLat, targetLng), targetZoom);
              
              setState(() {
                _showSearchResults = false;
                _currentCenter = LatLng(targetLat, targetLng);
                _currentZoom = targetZoom;
                
                if (!isPlace) {
                  _selectedLocation = LatLng(targetLat, targetLng);
                  _showPopup = true;
                }
              });
              
              // Clear search and hide keyboard
              _searchController.clear();
              FocusScope.of(context).unfocus();
              
              // Show confirmation
              final messenger = ScaffoldMessenger.of(context);
              messenger.showSnackBar(
                SnackBar(
                  content: Text('Moved to ${result['title']}'),
                  duration: const Duration(seconds: 2),
                  backgroundColor: Colors.teal,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMap() {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        setState(() {
          _showSearchResults = false;
        });
      },
      child: Stack(
        children: [
          // FlutterMap should be first in the stack
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: _currentCenter,
              initialZoom: _currentZoom,
              minZoom: _minZoom,
              maxZoom: _maxZoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.doubleTapZoom,
              ),
              onTap: (tapPosition, point) => _handleMapTap(point),
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
                                  _getCategoryColor(data['category']).withValues(alpha: 0.8),
                                ],
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: _getCategoryColor(data['category']).withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
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
              // Current location marker
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              // Selected location marker
              if (_selectedLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedLocation!,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.white,
                          size: 16,
                        ),
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
            child: Consumer<ThemeService>(
              builder: (context, themeService, child) {
                final isDark = themeService.isDarkMode;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark ? [
                    const Color(0xFF2B2B2B),
                    Colors.grey[800]!,
                  ] : [
                    Colors.white,
                    Colors.grey[50]!,
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark 
                    ? Colors.tealAccent.withValues(alpha: 0.3)
                    : Colors.teal.withValues(alpha: 0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark 
                      ? Colors.black.withValues(alpha: 0.4)
                      : Colors.grey.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: isDark 
                      ? Colors.tealAccent.withValues(alpha: 0.1)
                      : Colors.teal.withValues(alpha: 0.1),
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
                      Text(
                        'Location Selected',
                        style: TextStyle(
                          fontSize: 16, 
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
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
                    style: TextStyle(color: isDark ? Colors.grey : Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  // Report action button
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.red, Colors.redAccent],
                        ),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.report_problem, size: 18),
                        label: const Text('Report', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        onPressed: () async {
                          final navigator = Navigator.of(context);
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null) {
                            await navigator.push(
                              MaterialPageRoute(builder: (_) => const LoginScreen()),
                            );
                            if (FirebaseAuth.instance.currentUser == null) return;
                          }
                          
                          final result = await navigator.push(
                            MaterialPageRoute(
                              builder: (_) => IncidentFormScreen(
                                latitude: _selectedLocation?.latitude,
                                longitude: _selectedLocation?.longitude,
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
                  ),
                  const SizedBox(height: 8),
                  // Second row with Cancel button
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.grey[700]!, Colors.grey[600]!],
                        ),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Cancel', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                  ),
                ],
              ),
            );
              },
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
      ),
    );
  }

  // ignore: unused_element
  Widget _buildChatList() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Please login to view chats'));
    }
    return const ChatListScreen();
  }

  // ignore: unused_element
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
    final themeService = Provider.of<ThemeService>(context);
    final isDark = themeService.isDarkMode;
    
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
                colors: isDark ? [
                  Colors.black.withValues(alpha: 0.8),
                  Colors.grey[800]!.withValues(alpha: 0.9),
                ] : [
                  Colors.white.withValues(alpha: 0.9),
                  Colors.grey[100]!.withValues(alpha: 0.9),
                ],
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark 
                  ? Colors.tealAccent.withValues(alpha: 0.3)
                  : Colors.teal.withValues(alpha: 0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark 
                    ? Colors.black.withValues(alpha: 0.4)
                    : Colors.grey.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: isDark 
                    ? Colors.tealAccent.withValues(alpha: 0.1)
                    : Colors.teal.withValues(alpha: 0.1),
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
                    color: isDark ? Colors.tealAccent : Colors.teal,
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

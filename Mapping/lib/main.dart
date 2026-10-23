import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const IndiaGazetteerMapApp());
}

class IndiaGazetteerMapApp extends StatelessWidget {
  const IndiaGazetteerMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'India Gazetteer — 660,000+ Points Map',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF0284C7),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
      ),
      home: const IndiaMapScreen(),
    );
  }
}

class IndiaMapScreen extends StatefulWidget {
  const IndiaMapScreen({super.key});

  @override
  State<IndiaMapScreen> createState() => _IndiaMapScreenState();
}

class _IndiaMapScreenState extends State<IndiaMapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  Database? _db;
  List<Map<String, dynamic>> _visiblePoints = [];
  List<Map<String, dynamic>> _searchResults = [];

  final Set<String> _selectedClasses = {'P', 'H', 'T', 'A', 'S'};
  final int _minPopulation = 0;

  @override
  void initState() {
    super.initState();
    _initDatabase();
  }

  Future<void> _initDatabase() async {
    try {
      final dbPath = p.join(Directory.current.path, 'india_gazetteer.db');
      if (File(dbPath).existsSync()) {
        _db = await openDatabase(dbPath, readOnly: true);
        if (mounted) {
          setState(() {});
          _fetchViewportPoints();
        }
      }
    } catch (e) {
      debugPrint('Database init error: $e');
    }
  }

  Future<void> _fetchViewportPoints() async {
    if (_db == null) return;
    try {
      final bounds = _mapController.camera.visibleBounds;
      final minLat = bounds.south;
      final maxLat = bounds.north;
      final minLng = bounds.west;
      final maxLng = bounds.east;

      final classes = _selectedClasses.map((c) => "'$c'").join(',');
      if (classes.isEmpty) {
        if (mounted) setState(() => _visiblePoints = []);
        return;
      }

      final results = await _db!.rawQuery('''
        SELECT geonameid, name, latitude, longitude, feature_class, feature_code, population, elevation, dem
        FROM places
        WHERE latitude BETWEEN ? AND ?
          AND longitude BETWEEN ? AND ?
          AND feature_class IN ($classes)
          AND population >= ?
        ORDER BY population DESC
        LIMIT 1500
      ''', [minLat, maxLat, minLng, maxLng, _minPopulation]);

      if (mounted) {
        setState(() {
          _visiblePoints = results;
        });
      }
    } catch (e) {
      debugPrint('Error fetching points: $e');
    }
  }

  Future<void> _searchPlaces(String query) async {
    if (_db == null || query.trim().length < 2) {
      if (mounted) {
        setState(() {
          _searchResults = [];
        });
      }
      return;
    }

    final results = await _db!.rawQuery('''
      SELECT geonameid, name, latitude, longitude, feature_class, population, admin1_code
      FROM places
      WHERE name LIKE ? || '%' OR asciiname LIKE ? || '%'
      ORDER BY population DESC, length(name) ASC
      LIMIT 10
    ''', [query.trim(), query.trim()]);

    if (mounted) {
      setState(() {
        _searchResults = results;
      });
    }
  }

  Color _getColorForClass(String? fc) {
    switch (fc) {
      case 'P':
        return const Color(0xFF38BDF8); // Populated Place
      case 'H':
        return const Color(0xFF06B6D4); // Water
      case 'T':
        return const Color(0xFFEAB308); // Mountain
      case 'A':
        return const Color(0xFFEC4899); // Admin
      case 'S':
        return const Color(0xFFA855F7); // POI
      default:
        return const Color(0xFF94A3B8);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(22.3511148, 78.6677428),
              initialZoom: 5.0,
              minZoom: 4.0,
              maxZoom: 18.0,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) {
                  _fetchViewportPoints();
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.rbpssk.mapping',
              ),
              CircleLayer(
                circles: _visiblePoints.map((pt) {
                  final lat = (pt['latitude'] as num).toDouble();
                  final lng = (pt['longitude'] as num).toDouble();
                  final fc = pt['feature_class'] as String?;
                  final pop = (pt['population'] as num?)?.toInt() ?? 0;

                  double radius = 4;
                  if (pop > 500000) {
                    radius = 8;
                  } else if (pop > 100000) {
                    radius = 6;
                  }

                  return CircleMarker(
                    point: LatLng(lat, lng),
                    radius: radius,
                    color: _getColorForClass(fc),
                    borderColor: Colors.white70,
                    borderStrokeWidth: 1,
                  );
                }).toList(),
              ),
            ],
          ),

          // Search HUD
          Positioned(
            top: 20,
            left: 20,
            width: 360,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                    boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 16)],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _searchPlaces,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      icon: const Icon(Icons.search, color: Color(0xFF38BDF8)),
                      hintText: 'Search India (e.g. Pune, Delhi)...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchResults = []);
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                if (_searchResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    constraints: const BoxConstraints(maxHeight: 260),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18)],
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final item = _searchResults[index];
                        final name = item['name'] as String;
                        final lat = (item['latitude'] as num).toDouble();
                        final lng = (item['longitude'] as num).toDouble();
                        final pop = (item['population'] as num?)?.toInt() ?? 0;

                        return ListTile(
                          dense: true,
                          title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            'Coords: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}${pop > 0 ? ' • Pop: $pop' : ''}',
                            style: const TextStyle(color: Colors.white60, fontSize: 11),
                          ),
                          onTap: () {
                            _searchController.text = name;
                            setState(() => _searchResults = []);
                            _mapController.move(LatLng(lat, lng), 12);
                            Future.delayed(const Duration(milliseconds: 300), _fetchViewportPoints);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Bottom Stats Bar
          Positioned(
            bottom: 20,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Text('Total Records: ', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const Text('660,045', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(width: 16),
                  const Text('Visible: ', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  Text(
                    '${_visiblePoints.length} pts',
                    style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

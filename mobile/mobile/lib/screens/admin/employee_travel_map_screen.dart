import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/tracking_service.dart';
import '../../core/services/tracking_database.dart';
import 'employee_table_screen.dart';

class EmployeeTravelMapScreen extends StatefulWidget {
  final int? initialEmployeeId;
  final String? initialEmployeeCode;
  final String? initialEmployeeName;
  final String? initialSessionUuid;

  const EmployeeTravelMapScreen({
    Key? key,
    this.initialEmployeeId,
    this.initialEmployeeCode,
    this.initialEmployeeName,
    this.initialSessionUuid,
  }) : super(key: key);

  @override
  State<EmployeeTravelMapScreen> createState() => _EmployeeTravelMapScreenState();
}

class _EmployeeTravelMapScreenState extends State<EmployeeTravelMapScreen> {
  final MapController _mapController = MapController();
  final ApiClient _apiClient = ApiClient();

  // Employee Context State (Resolved from navigation / session)
  int? _resolvedUserId;
  String _employeeCode = '';
  String _employeeName = '';
  bool _hasEmployeeContext = false;
  bool _isAdmin = false;

  // Configuration State
  DateTime _selectedDate = DateTime.now();

  // Map & Route Data State
  List<LatLng> _routePoints = [];
  List<Map<String, dynamic>> _rawPoints = [];
  Map<String, dynamic>? _sessionDetail;

  bool _isLoading = false;
  bool _hasSearched = false;
  bool _showPoints = true;
  bool _isOfflineMode = false;
  List<Map<String, dynamic>> _availableSessions = [];
  int? _selectedSessionId;
  String? _loadError;

  // Live Stream & Route Playback
  StreamSubscription<Map<String, dynamic>>? _livePointsSub;
  StreamSubscription<Map<String, dynamic>>? _liveAddressSub;
  Map<String, dynamic>? _liveResolvedAddress;
  bool _followLive = true;
  bool _isPlaying = false;
  Timer? _playbackTimer;
  int _playbackIndex = 0;

  @override
  void initState() {
    super.initState();
    _liveResolvedAddress = TrackingService.instance.currentResolvedAddress;
    _initEmployeeContext();
    _subscribeToLivePoints();
    _subscribeToLiveAddress();
  }

  @override
  void dispose() {
    _livePointsSub?.cancel();
    _liveAddressSub?.cancel();
    _playbackTimer?.cancel();
    _playbackTimer = null;
    super.dispose();
  }

  void _subscribeToLivePoints() {
    _livePointsSub?.cancel();
    _livePointsSub = TrackingService.instance.pointStream.listen((pointData) {
      if (!mounted) return;
      final sessionUuid = pointData['session_uuid'] as String?;
      final currentUuid = _sessionDetail?['session_uuid'] ?? widget.initialSessionUuid ?? TrackingService.instance.activeSessionUuid;

      final isCurrentActiveRecording = TrackingService.instance.isActive &&
          (sessionUuid == TrackingService.instance.activeSessionUuid) &&
          (_resolvedUserId == null || _resolvedUserId == TrackingService.instance.activeUserId);

      if (sessionUuid == currentUuid || isCurrentActiveRecording) {
        final lat = (pointData['latitude'] as num).toDouble();
        final lng = (pointData['longitude'] as num).toDouble();
        final newCoord = LatLng(lat, lng);

        setState(() {
          _rawPoints.add(pointData);
          _routePoints.add(newCoord);
          if (_sessionDetail != null) {
            _sessionDetail!['total_distance_meters'] = TrackingService.instance.totalDistanceMeters;
            _sessionDetail!['point_count'] = _rawPoints.length;
          }
        });
        if (_followLive && mounted) {
          _mapController.move(newCoord, _mapController.camera.zoom);
        }
      }
    });
  }


  void _subscribeToLiveAddress() {
    _liveAddressSub?.cancel();
    _liveAddressSub = TrackingService.instance.addressStream.listen((addr) {
      if (!mounted) return;
      setState(() {
        _liveResolvedAddress = addr;
      });
    });
  }

  Future<void> _initEmployeeContext() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('role') ?? 'USER';
    _isAdmin = (role == 'ADMIN');

    if (widget.initialEmployeeId != null) {
      _resolvedUserId = widget.initialEmployeeId;
      _employeeCode = widget.initialEmployeeCode ?? '${widget.initialEmployeeId}';
      _employeeName = widget.initialEmployeeName ?? 'Employee #$_employeeCode';
      _hasEmployeeContext = true;
    } else if (!_isAdmin) {
      // Non-admin viewing their own travel map
      _resolvedUserId = prefs.getInt('user_id') ?? 0;
      _employeeCode = prefs.getString('employee_id') ?? '$_resolvedUserId';
      _employeeName = prefs.getString('name') ?? 'My Travel Route';
      _hasEmployeeContext = true;
    } else {
      // Admin opened page without preselected employee context
      _hasEmployeeContext = false;
    }

    if (mounted) {
      setState(() {});
      if (_hasEmployeeContext) {
        _loadRoute();
      }
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF203F92),
              onPrimary: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _loadRoute([int? overrideSessionId]) async {
    if (!_hasEmployeeContext || _resolvedUserId == null) return;

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _loadError = null;
      _routePoints = [];
      _rawPoints = [];
      _sessionDetail = null;
    });

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    try {
      final sessionsRes = await _apiClient.get(
        '/api/tracking/sessions?user_id=$_resolvedUserId&work_date=$dateStr',
      );

      if (sessionsRes is List) {
        final sessionsList = sessionsRes.map((s) => Map<String, dynamic>.from(s)).toList();
        _availableSessions = sessionsList;

        if (sessionsList.isNotEmpty) {
          Map<String, dynamic> session = sessionsList.first;
          if (overrideSessionId != null) {
            session = sessionsList.firstWhere(
              (s) => s['id'] == overrideSessionId,
              orElse: () => sessionsList.first,
            );
          } else if (_selectedSessionId != null) {
            session = sessionsList.firstWhere(
              (s) => s['id'] == _selectedSessionId,
              orElse: () => sessionsList.first,
            );
          } else if (widget.initialSessionUuid != null) {
            session = sessionsList.firstWhere(
              (s) => s['session_uuid'] == widget.initialSessionUuid,
              orElse: () => sessionsList.first,
            );
          }

          _selectedSessionId = session['id'];
          final sessionId = session['id'];
          final routeRes = await _apiClient.get('/api/tracking/sessions/$sessionId/route');

          if (routeRes is Map) {
            final ptsList = (routeRes['points'] ?? routeRes['route_points'] ?? []) as List;
            final serverPoints = ptsList.map((p) => Map<String, dynamic>.from(p)).toList();

            // Merge with any un-synced points currently stored in local SQLite cache
            final sessionUuid = (session['session_uuid'] as String?) ?? widget.initialSessionUuid;
            List<Map<String, dynamic>> combinedPoints = serverPoints;
            if (sessionUuid != null) {
              try {
                final localPoints = await TrackingDatabase.instance.getSessionReconstructedPoints(sessionUuid);
                if (localPoints.isNotEmpty) {
                  final serverClientIds = serverPoints.map((p) => p['client_point_id']).toSet();
                  final extraLocalPoints = localPoints.where((p) => !serverClientIds.contains(p['client_point_id'])).toList();
                  if (extraLocalPoints.isNotEmpty) {
                    combinedPoints = [...serverPoints, ...extraLocalPoints];
                    combinedPoints.sort((a, b) => ((a['sequence_number'] ?? 0) as int).compareTo((b['sequence_number'] ?? 0) as int));
                  }
                }
              } catch (_) {}
            }

            final latLngs = combinedPoints
                .map((p) => LatLng((p['latitude'] as num).toDouble(), (p['longitude'] as num).toDouble()))
                .toList();

            setState(() {
              _isOfflineMode = false;
              _sessionDetail = Map<String, dynamic>.from(routeRes['session'] ?? session);
              _rawPoints = combinedPoints;
              _routePoints = latLngs;
              _isLoading = false;
            });

            if (latLngs.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _fitRouteBounds());
            } else if (_sessionDetail?['start_latitude'] != null && _sessionDetail?['start_longitude'] != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _mapController.move(
                  LatLng((_sessionDetail!['start_latitude'] as num).toDouble(),
                         (_sessionDetail!['start_longitude'] as num).toDouble()),
                  15.0,
                );
              });
            }
            return;
          }
        }
      }

      setState(() {
        _availableSessions = [];
        _selectedSessionId = null;
        _isLoading = false;
      });
    } catch (e) {
      // Offline fallback: check local sqlite database for sessions and points
      try {
        final localSessions = await TrackingDatabase.instance.getLocalSessionsForDate(dateStr);
        if (localSessions.isNotEmpty) {
          final session = localSessions.first;
          final sessionUuid = session['session_uuid'] as String;
          final localPoints = await TrackingDatabase.instance.getSessionReconstructedPoints(sessionUuid);
          final latLngs = localPoints
              .map((p) => LatLng((p['latitude'] as num).toDouble(), (p['longitude'] as num).toDouble()))
              .toList();

          if (mounted) {
            setState(() {
              _isOfflineMode = true;
              _availableSessions = localSessions;
              _selectedSessionId = session['id'] as int?;
              _sessionDetail = Map<String, dynamic>.from(session);
              _rawPoints = localPoints;
              _routePoints = latLngs;
              _isLoading = false;
              _loadError = null;
            });
            if (latLngs.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _fitRouteBounds());
            }
            return;
          }
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = e.toString().replaceFirst('Exception: ', '');
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load travel route: $_loadError'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  int _playbackSpeed = 1;

  void _startPlayback() {
    if (_routePoints.isEmpty) return;
    _playbackTimer?.cancel();
    setState(() {
      _isPlaying = true;
      if (_playbackIndex >= _routePoints.length - 1) {
        _playbackIndex = 0;
      }
    });

    final intervalMs = (1000 / _playbackSpeed).round();
    _playbackTimer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_playbackIndex < _routePoints.length - 1) {
        setState(() {
          _playbackIndex++;
        });
        _mapController.move(_routePoints[_playbackIndex], _mapController.camera.zoom);
      } else {
        _stopPlayback();
      }
    });
  }

  void _pausePlayback() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    setState(() {
      _isPlaying = false;
    });
  }

  void _stopPlayback() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    if (mounted) {
      setState(() {
        _isPlaying = false;
      });
    }
  }

  void _togglePlaybackSpeed() {
    int nextSpeed = 1;
    if (_playbackSpeed == 1) {
      nextSpeed = 2;
    } else if (_playbackSpeed == 2) {
      nextSpeed = 5;
    } else {
      nextSpeed = 1;
    }

    setState(() {
      _playbackSpeed = nextSpeed;
    });
    if (_isPlaying) {
      _startPlayback();
    }
  }

  /// Splits route into distinct polylines across gaps (>15 min delay or tracking pause)
  List<Polyline> _buildRoutePolylines() {
    if (_rawPoints.isEmpty) {
      if (_routePoints.isNotEmpty) {
        return [
          Polyline(
            points: _routePoints,
            strokeWidth: 4.5,
            color: const Color(0xFF1D4ED8),
          ),
        ];
      }
      return [];
    }

    final List<Polyline> lines = [];
    List<LatLng> currentSegment = [];

    for (int i = 0; i < _rawPoints.length; i++) {
      final pt = _rawPoints[i];
      final lat = (pt['latitude'] as num).toDouble();
      final lng = (pt['longitude'] as num).toDouble();
      final coord = LatLng(lat, lng);
      final isGap = pt['is_gap'] == 1 || pt['is_gap'] == true;

      if (isGap && currentSegment.isNotEmpty) {
        if (currentSegment.length >= 2) {
          lines.add(Polyline(
            points: List<LatLng>.from(currentSegment),
            strokeWidth: 4.5,
            color: const Color(0xFF1D4ED8),
          ));
        }
        currentSegment = [];
      }

      currentSegment.add(coord);
    }

    if (currentSegment.length >= 2) {
      lines.add(Polyline(
        points: List<LatLng>.from(currentSegment),
        strokeWidth: 4.5,
        color: const Color(0xFF1D4ED8),
      ));
    }

    return lines;
  }

  void _showPointDetails(int index) {
    if (index < 0 || index >= _rawPoints.length) return;
    final pt = _rawPoints[index];
    final lat = (pt['latitude'] as num).toDouble();
    final lng = (pt['longitude'] as num).toDouble();
    final acc = pt['accuracy_meters'] ?? pt['accuracy'] ?? 0;
    final speed = pt['speed_mps'] ?? pt['speed'];
    final speedKmh = speed != null ? ((speed as num) * 3.6).toStringAsFixed(1) : '0.0';
    final alt = pt['altitude_meters'] ?? pt['altitude'];
    final timeStr = _formatTime(pt['recorded_at'] ?? pt['captured_at']);
    final isGap = pt['is_gap'] == 1 || pt['is_gap'] == true;
    final syncStatus = pt['sync_status'] ?? 'SYNCED';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Point #${pt['sequence_number'] ?? (index + 1)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1D4ED8),
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: syncStatus == 'SYNCED' ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      syncStatus == 'SYNCED' ? 'Cloud Synced' : 'Offline Queue',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: syncStatus == 'SYNCED' ? const Color(0xFF15803D) : const Color(0xFFB45309),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.access_time_rounded, size: 18, color: Color(0xFF64748B)),
                  const SizedBox(width: 8),
                  Text('Time: $timeStr (IST)', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  if (isGap) ...[
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('GAP FIX', style: TextStyle(color: Color(0xFFB91C1C), fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 18, color: Color(0xFF64748B)),
                  const SizedBox(width: 8),
                  Text('Coords: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF334155))),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.gps_fixed_rounded, size: 18, color: Color(0xFF64748B)),
                  const SizedBox(width: 8),
                  Text('Accuracy: ±${(acc as num).toStringAsFixed(1)} m',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF334155))),
                  const SizedBox(width: 16),
                  const Icon(Icons.speed_rounded, size: 18, color: Color(0xFF64748B)),
                  const SizedBox(width: 8),
                  Text('Speed: $speedKmh km/h',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF334155))),
                ],
              ),
              if (alt != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.terrain_rounded, size: 18, color: Color(0xFF64748B)),
                    const SizedBox(width: 8),
                    Text('Altitude: ${(alt as num).toStringAsFixed(1)} m',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF334155))),
                  ],
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _fitRouteBounds() {
    if (_routePoints.isEmpty) return;
    if (_routePoints.length == 1) {
      _mapController.move(_routePoints.first, 15.0);
      return;
    }
    final bounds = LatLngBounds.fromPoints(_routePoints);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50),
      ),
    );
  }

  void _zoomIn() {
    _mapController.move(
      _mapController.camera.center,
      _mapController.camera.zoom + 1,
    );
  }

  void _zoomOut() {
    _mapController.move(
      _mapController.camera.center,
      _mapController.camera.zoom - 1,
    );
  }

  String _formatTime(dynamic iso) {
    if (iso == null || '$iso'.isEmpty) return '--:--';
    try {
      final dt = DateTime.parse('$iso').toLocal();
      return DateFormat('hh:mm a').format(dt);
    } catch (_) {
      return '$iso';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: SafeArea(
        child: Column(
          children: [
            // Header Bar
            _buildHeader(),

            // Main Body Content
            Expanded(
              child: !_hasEmployeeContext
                  ? _buildMissingEmployeeState()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // B. Travel Map Configuration Card
                          _buildConfigurationCard(),
                          const SizedBox(height: 20),

                          // C. Travel Summary Cards
                          _buildTravelSummarySection(),
                          const SizedBox(height: 20),

                          // D. Recorded Travel Route Map Card
                          _buildRecordedMapCard(),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // A. Header Bar
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFDCE4F0))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 8),
          const Text(
            'Employee Travel Map',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFDCE4F0)),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF203F92), size: 20),
              tooltip: 'Refresh Route',
              onPressed: _hasEmployeeContext && !_isLoading ? _loadRoute : null,
            ),
          ),
        ],
      ),
    );
  }

  // B. Travel Map Configuration Card
  Widget _buildConfigurationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE4F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Travel Map Configuration',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 600;
              if (isWide) {
                return Row(
                  children: [
                    Expanded(child: _buildDatePickerField()),
                    const SizedBox(width: 16),
                    _buildViewRouteButton(),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _buildDatePickerField(),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, child: _buildViewRouteButton()),
                  ],
                );
              }
            },
          ),
          if (_availableSessions.length > 1) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: _selectedSessionId,
                  items: _availableSessions.map((s) {
                    final sTime = _formatTime(s['start_time']);
                    final sStatus = (s['status'] ?? 'COMPLETED').toString().toUpperCase();
                    final sDist = ((s['total_distance_meters'] ?? 0) / 1000.0).toStringAsFixed(2);
                    return DropdownMenuItem<int>(
                      value: s['id'] as int,
                      child: Text(
                        'Session #${s['id']} ($sTime) • $sStatus • $sDist km',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                      ),
                    );
                  }).toList(),
                  onChanged: (newId) {
                    if (newId != null && newId != _selectedSessionId) {
                      _selectedSessionId = newId;
                      _loadRoute(newId);
                    }
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDatePickerField() {
    final formattedDate = DateFormat('dd MMM yyyy').format(_selectedDate);

    return InkWell(
      onTap: _selectDate,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined, size: 18, color: Color(0xFF475569)),
            const SizedBox(width: 12),
            Text(
              formattedDate,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
            const Spacer(),
            const Icon(Icons.calendar_month_rounded, size: 20, color: Color(0xFF64748B)),
          ],
        ),
      ),
    );
  }

  Widget _buildViewRouteButton() {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF203F92),
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(180, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 22),
      ),
      icon: _isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.menu_book_rounded, size: 20),
      label: const Text(
        'View Travel Route',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2),
      ),
      onPressed: _isLoading ? null : _loadRoute,
    );
  }

  // C. Travel Summary Section
  Widget _buildTravelSummarySection() {
    final distMeters = _sessionDetail?['total_distance_meters'];
    final distanceKm = distMeters != null
        ? ((distMeters as num) / 1000.0).toStringAsFixed(2)
        : '0.00';

    final totalPoints = _rawPoints.isNotEmpty
        ? _rawPoints.length
        : (_sessionDetail?['point_count'] ?? 0);

    final status = (_sessionDetail?['status'] ?? 'COMPLETED').toString().toUpperCase();
    final isCompleted = status == 'COMPLETED';
    final isActive = status == 'ACTIVE' || status == 'RECORDING';

    final startTimeStr = _formatTime(_sessionDetail?['start_time']);
    final endTimeStr = _formatTime(_sessionDetail?['end_time']);

    final formattedDate = DateFormat('dd MMM yyyy').format(_selectedDate);
    final dayOfWeek = DateFormat('EEEE').format(_selectedDate);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE4F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.bar_chart_rounded, color: Color(0xFF203F92), size: 22),
              SizedBox(width: 8),
              Text(
                'Travel Summary',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  // 1. Employee
                  _buildMetricCard(
                    iconBg: const Color(0xFFEFF6FF),
                    iconColor: const Color(0xFF2563EB),
                    icon: Icons.person_rounded,
                    label: 'Employee',
                    value: _employeeName,
                    subValue: 'ID: $_employeeCode',
                    minWidth: 150,
                  ),
                  // 2. Date
                  _buildMetricCard(
                    iconBg: const Color(0xFFEFF6FF),
                    iconColor: const Color(0xFF2563EB),
                    icon: Icons.calendar_today_rounded,
                    label: 'Date',
                    value: formattedDate,
                    subValue: dayOfWeek,
                    minWidth: 140,
                  ),
                  // 3. Tracking Status
                  _buildStatusMetricCard(
                    status: isCompleted ? 'Completed' : (isActive ? 'Active' : 'Pending'),
                    isCompleted: isCompleted,
                    isActive: isActive,
                  ),
                  // 4. Start Time
                  _buildMetricCard(
                    iconBg: const Color(0xFFEFF6FF),
                    iconColor: const Color(0xFF2563EB),
                    icon: Icons.access_time_rounded,
                    label: 'Start Time',
                    value: startTimeStr,
                    minWidth: 130,
                  ),
                  // 5. End Time
                  _buildMetricCard(
                    iconBg: const Color(0xFFFFF7ED),
                    iconColor: const Color(0xFFF97316),
                    icon: Icons.access_time_rounded,
                    label: 'End Time',
                    value: endTimeStr,
                    minWidth: 130,
                  ),
                  // 6. Travel Distance
                  _buildMetricCard(
                    iconBg: const Color(0xFFFAF5FF),
                    iconColor: const Color(0xFF9333EA),
                    icon: Icons.alt_route_rounded,
                    label: 'Travel Distance',
                    value: '$distanceKm km',
                    minWidth: 140,
                  ),
                  // 7. Total Points
                  _buildMetricCard(
                    iconBg: const Color(0xFFFDF2F8),
                    iconColor: const Color(0xFFDB2777),
                    icon: Icons.location_on_rounded,
                    label: 'Total Points',
                    value: '$totalPoints',
                    minWidth: 120,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required Color iconBg,
    required Color iconColor,
    required IconData icon,
    required String label,
    required String value,
    String? subValue,
    double minWidth = 130,
  }) {
    return Container(
      constraints: BoxConstraints(minWidth: minWidth),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
              ),
              if (subValue != null) ...[
                const SizedBox(height: 1),
                Text(
                  subValue,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusMetricCard({
    required String status,
    required bool isCompleted,
    required bool isActive,
  }) {
    final pillBg = isCompleted
        ? const Color(0xFFDEF7EC)
        : (isActive ? const Color(0xFFDBEAFE) : const Color(0xFFF1F5F9));
    final pillColor = isCompleted
        ? const Color(0xFF047857)
        : (isActive ? const Color(0xFF1E40AF) : const Color(0xFF475569));

    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isCompleted ? const Color(0xFFECFDF5) : const Color(0xFFEFF6FF),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: isCompleted ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Tracking Status',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: pillBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: pillColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // D. Recorded Travel Route Map Card
  Widget _buildRecordedMapCard() {
    final initialCenter = _routePoints.isNotEmpty
        ? _routePoints.first
        : (_sessionDetail?['start_latitude'] != null && _sessionDetail?['start_longitude'] != null
            ? LatLng((_sessionDetail!['start_latitude'] as num).toDouble(), (_sessionDetail!['start_longitude'] as num).toDouble())
            : const LatLng(18.5204, 73.8567));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE4F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Toolbar (Responsive)
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 640;
              final toolbarButtons = [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _followLive ? const Color(0xFF2563EB) : const Color(0xFF334155),
                    side: BorderSide(color: _followLive ? const Color(0xFF2563EB) : const Color(0xFFCBD5E1)),
                    backgroundColor: _followLive ? const Color(0xFFEFF6FF) : Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: Icon(_followLive ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded, size: 16),
                  label: Text(_followLive ? 'Following Live' : 'Follow Off', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  onPressed: () => setState(() => _followLive = !_followLive),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF334155),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.center_focus_strong_rounded, size: 16),
                  label: const Text('Fit to Route', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  onPressed: _routePoints.isNotEmpty ? _fitRouteBounds : null,
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _showPoints ? const Color(0xFF203F92) : const Color(0xFF64748B),
                    side: BorderSide(color: _showPoints ? const Color(0xFF203F92) : const Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: Icon(_showPoints ? Icons.location_on_rounded : Icons.location_off_rounded, size: 16),
                  label: Text(_showPoints ? 'Hide Points' : 'Show Points', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  onPressed: () => setState(() => _showPoints = !_showPoints),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 18, color: Color(0xFF334155)),
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    tooltip: 'Refresh Route',
                    onPressed: _isLoading ? null : _loadRoute,
                  ),
                ),
              ];

              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.map_outlined, color: Color(0xFF203F92), size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Recorded Travel Route',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: toolbarButtons),
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  const Icon(Icons.map_outlined, color: Color(0xFF203F92), size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    'Recorded Travel Route',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const Spacer(),
                  ...toolbarButtons,
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          // Offline Mode Banner
          if (_isOfflineMode) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.wifi_off_rounded, color: Color(0xFFD97706), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Offline Mode: Displaying locally persisted GPS trajectory from device SQLite cache.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Route Playback Control Bar
          if (_routePoints.length > 1) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(_isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
                    color: const Color(0xFF203F92),
                    iconSize: 32,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: _isPlaying ? 'Pause Playback' : 'Play Route History',
                    onPressed: _isPlaying ? _pausePlayback : _startPlayback,
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _togglePlaybackSpeed,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: const Size(42, 28),
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                    ),
                    child: Text(
                      '${_playbackSpeed}x',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Color(0xFF203F92),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        activeTrackColor: const Color(0xFF203F92),
                        thumbColor: const Color(0xFF203F92),
                      ),
                      child: Slider(
                        value: _playbackIndex.clamp(0, _routePoints.length - 1).toDouble(),
                        min: 0,
                        max: (_routePoints.length - 1).toDouble(),
                        onChanged: (val) {
                          final idx = val.round();
                          setState(() {
                            _playbackIndex = idx;
                          });
                          _mapController.move(_routePoints[idx], _mapController.camera.zoom);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_playbackIndex + 1}/${_routePoints.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],


          // Live OpenStreetMap Reverse-Geocoded Telemetry Card
          _buildLiveAddressTelemetryCard(),
          const SizedBox(height: 12),
          // Interactive Map Area
          Container(
            height: 520,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: initialCenter,
                    initialZoom: 14.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.rbpssk.fieldstaff.attendance',
                    ),
                    // Polyline route with gap handling
                    if (_routePoints.isNotEmpty)
                      PolylineLayer(
                        polylines: _buildRoutePolylines(),
                      ),
                    // Checkpoint dots with click-to-inspect
                    if (_showPoints && _routePoints.length > 2)
                      CircleLayer(
                        circles: List.generate(_routePoints.length, (idx) {
                          if (idx == 0 || idx == _routePoints.length - 1) return null;
                          return CircleMarker(
                            point: _routePoints[idx],
                            radius: 4.0,
                            color: const Color(0xFF2563EB),
                            borderColor: Colors.white,
                            borderStrokeWidth: 1.5,
                          );
                        }).whereType<CircleMarker>().toList(),
                      ),
                    // Markers: Fixed Start, Dynamic Moving Marker, End Marker
                    if (_routePoints.isNotEmpty)
                      MarkerLayer(
                        markers: [
                          // 1. Fixed Start Marker (always at original session origin)
                          Marker(
                            point: _routePoints.first,
                            width: 70,
                            height: 60,
                            child: GestureDetector(
                              onTap: () => _showPointDetails(0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'Start',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const Icon(Icons.location_on_rounded, color: Color(0xFF10B981), size: 30),
                                ],
                              ),
                            ),
                          ),
                          // 2. Playback moving marker
                          if (_isPlaying && _playbackIndex < _routePoints.length)
                            Marker(
                              point: _routePoints[_playbackIndex],
                              width: 80,
                              height: 70,
                              child: GestureDetector(
                                onTap: () => _showPointDetails(_playbackIndex),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4F46E5),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Pt #${_playbackIndex + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const Icon(Icons.navigation_rounded, color: Color(0xFF4F46E5), size: 32),
                                  ],
                                ),
                              ),
                            )
                          // 3. Live Moving Location Marker (when session is active and not playing back)
                          else if ((_sessionDetail?['status'] == 'RECORDING' || _sessionDetail?['status'] == 'ACTIVE') && _routePoints.isNotEmpty)
                            Marker(
                              point: _routePoints.last,
                              width: 80,
                              height: 70,
                              child: GestureDetector(
                                onTap: () => _showPointDetails(_routePoints.length - 1),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2563EB),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'Current GPS',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Stack(
                                      alignment: Alignment.center,
                                      children: const [
                                        Icon(Icons.trip_origin_rounded, color: Color(0xFF93C5FD), size: 34),
                                        Icon(Icons.circle, color: Color(0xFF1D4ED8), size: 16),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            )
                          // 4. Completed End Marker
                          else if (_routePoints.length > 1)
                            Marker(
                              point: _routePoints.last,
                              width: 70,
                              height: 60,
                              child: GestureDetector(
                                onTap: () => _showPointDetails(_routePoints.length - 1),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.location_on_rounded, color: Color(0xFFDC2626), size: 30),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDC2626),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'End',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),

                // Zoom controls on bottom-left
                Positioned(
                  left: 14,
                  bottom: 14,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: _zoomIn,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.add, size: 20, color: Color(0xFF334155)),
                          ),
                        ),
                        Container(height: 1, width: 36, color: const Color(0xFFE2E8F0)),
                        InkWell(
                          onTap: _zoomOut,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.remove, size: 20, color: Color(0xFF334155)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Layer attribution on bottom-right
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.layers_outlined, size: 16, color: Color(0xFF334155)),
                        SizedBox(width: 6),
                        Text(
                          'OpenStreetMap',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                        ),
                      ],
                    ),
                  ),
                ),

                // Loading overlay
                if (_isLoading)
                  Container(
                    color: Colors.white.withOpacity(0.6),
                    child: const Center(
                      child: CircularProgressIndicator(color: Color(0xFF203F92)),
                    ),
                  ),

                // Empty state overlay (Section 4 honest state handling)
                if (!_isLoading && _hasSearched && _routePoints.isEmpty)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                      margin: const EdgeInsets.symmetric(horizontal: 28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1A000000),
                            blurRadius: 16,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Builder(
                        builder: (_) {
                          if (_loadError != null) {
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline_rounded, size: 40, color: Color(0xFFDC2626)),
                                const SizedBox(height: 8),
                                const Text(
                                  'Error Loading Route',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _loadError!,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton(
                                  onPressed: _loadRoute,
                                  child: const Text('Retry'),
                                ),
                              ],
                            );
                          }

                          if (_availableSessions.isEmpty) {
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.event_busy_rounded, size: 40, color: Color(0xFF64748B)),
                                const SizedBox(height: 8),
                                Text(
                                  'No Tracking Sessions on ${DateFormat('dd MMM yyyy').format(_selectedDate)}',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'The employee has no recorded duty tracking sessions for this date.',
                                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            );
                          }

                          final status = (_sessionDetail?['status'] ?? '').toString().toUpperCase();
                          final isActive = status == 'RECORDING' || status == 'ACTIVE';

                          if (isActive) {
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.gps_fixed_rounded, size: 40, color: Color(0xFF2563EB)),
                                const SizedBox(height: 8),
                                const Text(
                                  'Session Active — No GPS Points Yet',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Tracking session started at ${_formatTime(_sessionDetail?['start_time'])}, but no GPS coordinates have arrived yet.',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            );
                          }

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.route_outlined, size: 40, color: Color(0xFF64748B)),
                              const SizedBox(height: 8),
                              const Text(
                                'Completed Session — No Route Recorded',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Session completed with 0 breadcrumbs recorded (${_formatTime(_sessionDetail?['start_time'])} – ${_formatTime(_sessionDetail?['end_time'])}).',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Missing Employee Context State
  Widget _buildMissingEmployeeState() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(32),
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFDCE4F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFFEFF6FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_search_rounded, color: Color(0xFF2563EB), size: 28),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Employee Selected',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'To view employee travel routes, please select an employee from the Employee List or Admin Dashboard.',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF203F92),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              icon: const Icon(Icons.badge_rounded, size: 18),
              label: const Text('Open Employee List', style: TextStyle(fontWeight: FontWeight.w600)),
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const EmployeeTableScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildLiveAddressTelemetryCard() {
    final addr = _liveResolvedAddress;
    final village = addr?['village'] ?? '—';
    final locality = addr?['locality'] ?? '—';
    final road = addr?['road'] ?? '—';
    final district = addr?['district'] ?? 'Sangli / Kolhapur';
    final state = addr?['state'] ?? 'Maharashtra';
    final display = addr?['display_name'] ?? (TrackingService.instance.isActive ? 'Resolving live location name...' : 'Live GPS standby');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFF16A34A)),
              const SizedBox(width: 6),
              const Text(
                'Live Location (OpenStreetMap Reverse-Geocode)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF166534),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  addr != null ? 'RESOLVED' : (TrackingService.instance.isActive ? 'RESOLVING...' : 'STANDBY'),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF15803D),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Text('Village: $village •', style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B), fontWeight: FontWeight.w600)),
              Text('Locality: $locality •', style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B), fontWeight: FontWeight.w600)),
              Text('Road: $road •', style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B), fontWeight: FontWeight.w600)),
              Text('District: $district, $state', style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B), fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            display,
            style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../models/attendance_request_model.dart';

class AttendanceRequestsScreen extends StatefulWidget {
  const AttendanceRequestsScreen({Key? key}) : super(key: key);

  @override
  State<AttendanceRequestsScreen> createState() => _AttendanceRequestsScreenState();
}

class _AttendanceRequestsScreenState extends State<AttendanceRequestsScreen> {
  final ApiClient _apiClient = ApiClient();
  bool _isLoading = true;
  List<AttendanceRequestModel> _requests = [];
  String _statusFilter = 'PENDING'; // 'PENDING', 'ALL', 'APPROVED', 'REJECTED'
  String? _authToken;

  @override
  void initState() {
    super.initState();
    _loadTokenAndRequests();
  }

  Future<void> _loadTokenAndRequests() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString('access_token');
    await _fetchRequests();
  }

  Future<void> _fetchRequests() async {
    setState(() => _isLoading = true);
    try {
      String endpoint = ApiConstants.adminAttendanceRequests;
      if (_statusFilter != 'ALL') {
        endpoint += '?status=$_statusFilter';
      }
      final res = await _apiClient.get(endpoint);
      final list = (res as List).map((item) => AttendanceRequestModel.fromJson(item)).toList();
      setState(() {
        _requests = list;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load requests: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleApprove(AttendanceRequestModel req) async {
    final noteController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.check_circle_rounded, color: AppColors.success, size: 28),
            SizedBox(width: 8),
            Text('Approve Attendance'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Approve attendance for ${req.fullName} (${req.employeeId})?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Official record will be created using server time: ${req.serverFormattedDate} ${req.serverFormattedTime}',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'Admin Note (Optional)',
                hintText: 'e.g. Verified site selfie on duty',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text('Approve Attendance'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _apiClient.post(
        ApiConstants.adminApproveAttendanceRequest(req.id),
        body: {'admin_notes': noteController.text.trim()},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Request #${req.id} approved! Attendance created successfully.'),
            backgroundColor: AppColors.success,
          ),
        );
        _fetchRequests();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Approval failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleReject(AttendanceRequestModel req) async {
    final noteController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.cancel_rounded, color: AppColors.error, size: 28),
            SizedBox(width: 8),
            Text('Reject Attendance Request'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reject attendance request #${req.id} for ${req.fullName}?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'Rejection Reason (Required)',
                hintText: 'e.g. Not at assigned site / Invalid selfie',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (noteController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a rejection reason.')),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Reject Request'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _apiClient.post(
        ApiConstants.adminRejectAttendanceRequest(req.id),
        body: {'admin_notes': noteController.text.trim()},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Request #${req.id} rejected.'),
            backgroundColor: AppColors.warning,
          ),
        );
        _fetchRequests();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rejection failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showEnlargedImage(int reqId) {
    final imageUrl = _authToken != null && _authToken!.isNotEmpty
        ? '${_apiClient.baseUrl}${ApiConstants.adminAttendanceRequestImage(reqId)}?token=$_authToken'
        : '${_apiClient.baseUrl}${ApiConstants.adminAttendanceRequestImage(reqId)}';
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(
                  imageUrl,
                  headers: _authToken != null ? {'Authorization': 'Bearer $_authToken'} : null,
                  fit: BoxFit.contain,
                  loadingBuilder: (ctx, child, progress) {
                    if (progress == null) return child;
                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                  },
                  errorBuilder: (_, __, ___) => const Center(
                    child: Text('Evidence image unavailable', style: TextStyle(color: Colors.white70)),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _statusFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppColors.textPrimary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (_) {
        setState(() => _statusFilter = value);
        _fetchRequests();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Review Queue'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _fetchRequests,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                _buildFilterChip('Pending Review', 'PENDING'),
                const SizedBox(width: 8),
                _buildFilterChip('All Requests', 'ALL'),
                const SizedBox(width: 8),
                _buildFilterChip('Approved', 'APPROVED'),
                const SizedBox(width: 8),
                _buildFilterChip('Rejected', 'REJECTED'),
              ],
            ),
          ),

          // Request List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _fetchRequests,
                    child: _requests.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.inbox_rounded, size: 64, color: AppColors.textSecondary),
                                const SizedBox(height: 12),
                                Text(
                                  _statusFilter == 'PENDING'
                                      ? 'No pending attendance requests.'
                                      : 'No requests found for selected filter.',
                                  style: const TextStyle(fontSize: 15, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _requests.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 16),
                            itemBuilder: (ctx, i) {
                              final req = _requests[i];
                              final isPending = req.status == 'PENDING';
                              final imageUrl = _authToken != null && _authToken!.isNotEmpty
                                  ? '${_apiClient.baseUrl}${ApiConstants.adminAttendanceRequestImage(req.id)}?token=$_authToken'
                                  : '${_apiClient.baseUrl}${ApiConstants.adminAttendanceRequestImage(req.id)}';

                              Color statusColor;
                              Color statusBg;
                              if (req.status == 'APPROVED') {
                                statusColor = const Color(0xFF15803D);
                                statusBg = const Color(0xFFDCFCE7);
                              } else if (req.status == 'REJECTED') {
                                statusColor = const Color(0xFFBE123C);
                                statusBg = const Color(0xFFFFF1F2);
                              } else {
                                statusColor = const Color(0xFFB45309);
                                statusBg = const Color(0xFFFEF3C7);
                              }

                              return Card(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 2,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Top Header: Employee & Status
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                req.fullName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 17,
                                                  color: AppColors.textPrimary,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'ID: ${req.employeeId}  •  Req #${req.id}',
                                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                              ),
                                            ],
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: statusBg,
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              req.status,
                                              style: TextStyle(
                                                color: statusColor,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 20),

                                      // Evidence Image Preview (Tap to enlarge)
                                      InkWell(
                                        onTap: () => _showEnlargedImage(req.id),
                                        borderRadius: BorderRadius.circular(12),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Stack(
                                            children: [
                                              Container(
                                                height: 190,
                                                width: double.infinity,
                                                color: Colors.black87,
                                                child: Image.network(
                                                  imageUrl,
                                                  headers: _authToken != null
                                                      ? {'Authorization': 'Bearer $_authToken'}
                                                      : null,
                                                  fit: BoxFit.cover,
                                                  loadingBuilder: (ctx, child, progress) {
                                                    if (progress == null) return child;
                                                    return const Center(
                                                      child: CircularProgressIndicator(color: Colors.white),
                                                    );
                                                  },
                                                  errorBuilder: (_, __, ___) => const Center(
                                                    child: Text(
                                                      'Evidence selfie unavailable',
                                                      style: TextStyle(color: Colors.white70),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                top: 8,
                                                right: 8,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black.withOpacity(0.7),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: const [
                                                      Icon(Icons.zoom_in, color: Colors.white, size: 14),
                                                      SizedBox(width: 4),
                                                      Text('Enlarge', style: TextStyle(color: Colors.white, fontSize: 11)),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 14),

                                      // Audit Telemetry Details Grid
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF8FAFC),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: const Color(0xFFE2E8F0)),
                                        ),
                                        child: Column(
                                          children: [
                                            _buildTelemetryRow(
                                              'Server Time:',
                                              '${req.serverFormattedDate} • ${req.serverFormattedTime}',
                                              Icons.access_time_filled_rounded,
                                              valueColor: AppColors.primary,
                                            ),
                                            const SizedBox(height: 6),
                                            _buildTelemetryRow(
                                              'Shift:',
                                              req.shiftName ?? 'Dayin / Assigned Shift',
                                              Icons.calendar_today_rounded,
                                            ),
                                            const SizedBox(height: 6),
                                            _buildTelemetryRow(
                                              'Location:',
                                              req.locationName ?? req.assignedLocationName ?? 'GPS Site',
                                              Icons.location_on_rounded,
                                            ),
                                            const SizedBox(height: 6),
                                            Builder(
                                              builder: (_) {
                                                final bool hasValidCoords = !(req.latitude == 0.0 && req.longitude == 0.0) &&
                                                    req.latitude.abs() <= 90.0 &&
                                                    req.longitude.abs() <= 180.0 &&
                                                    req.distanceFromLocation >= 0 &&
                                                    req.distanceFromLocation < 1000000.0;

                                                return Column(
                                                  children: [
                                                    _buildTelemetryRow(
                                                      'Coordinates:',
                                                      hasValidCoords
                                                          ? ', '
                                                          : 'Unavailable / Not Fixed (0.0, 0.0)',
                                                      Icons.gps_fixed_rounded,
                                                      valueColor: hasValidCoords ? null : AppColors.warning,
                                                    ),
                                                    const SizedBox(height: 6),
                                                    _buildTelemetryRow(
                                                      'Distance:',
                                                      hasValidCoords
                                                          ? ' m  ()'
                                                          : 'N/A (Location Verification Unavailable)',
                                                      Icons.straighten_rounded,
                                                      valueColor: hasValidCoords
                                                          ? (req.isWithinGeofence ? AppColors.success : AppColors.error)
                                                          : AppColors.warning,
                                                    ),
                                                    if (hasValidCoords && req.gpsAccuracy != null) ...[
                                                      const SizedBox(height: 6),
                                                      _buildTelemetryRow(
                                                        'GPS Accuracy:',
                                                        '\u00b1 m',
                                                        Icons.my_location_rounded,
                                                      ),
                                                    ] else if (!hasValidCoords) ...[
                                                      const SizedBox(height: 6),
                                                      _buildTelemetryRow(
                                                        'GPS Accuracy:',
                                                        'N/A (Indoor / Assistance Mode)',
                                                        Icons.my_location_rounded,
                                                        valueColor: AppColors.textSecondary,
                                                      ),
                                                    ],
                                                  ],
                                                );
                                              },
                                            ),
                                            const SizedBox(height: 6),
                                            _buildTelemetryRow(
                                              'Reason:',
                                              req.rejectionReasonTrigger ?? 'Face verification failed',
                                              Icons.info_outline_rounded,
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Admin notes if previously reviewed
                                      if (req.adminNotes != null && req.adminNotes!.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEFF6FF),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: const Color(0xFFBFDBFE)),
                                          ),
                                          child: Text(
                                            'Admin Notes: ${req.adminNotes}',
                                            style: const TextStyle(fontSize: 12, color: Color(0xFF1E40AF)),
                                          ),
                                        ),
                                      ],

                                      // Action Buttons: APPROVE / REJECT
                                      if (isPending) ...[
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: () => _handleReject(req),
                                                icon: const Icon(Icons.cancel_rounded, color: AppColors.error),
                                                label: const Text(
                                                  'REJECT',
                                                  style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error),
                                                ),
                                                style: OutlinedButton.styleFrom(
                                                  side: const BorderSide(color: AppColors.error),
                                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: ElevatedButton.icon(
                                                onPressed: () => _handleApprove(req),
                                                icon: const Icon(Icons.check_circle_rounded),
                                                label: const Text(
                                                  'APPROVE',
                                                  style: TextStyle(fontWeight: FontWeight.bold),
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: AppColors.success,
                                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryRow(String label, String value, IconData icon, {Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        SizedBox(
          width: 95,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

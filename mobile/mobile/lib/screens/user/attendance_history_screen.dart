import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/services/server_time_service.dart';
import '../../models/attendance_model.dart';
import '../../models/attendance_request_model.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({Key? key}) : super(key: key);

  @override
  State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> with SingleTickerProviderStateMixin {
  final _apiClient = ApiClient();
  final _serverTimeService = ServerTimeService();
  late TabController _tabController;

  bool _isLoading = true;
  List<AttendanceRecordModel> _records = [];
  List<AttendanceRequestModel> _requests = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchAllData();
  }

  Future<void> _fetchAllData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Fetch online attendance logs
      List<AttendanceRecordModel> listAtt = [];
      try {
        final resAtt = await _apiClient.get(ApiConstants.userAttendanceHistory);
        if (resAtt is List) {
          listAtt = resAtt.map((item) => AttendanceRecordModel.fromJson(item)).toList();
        }
      } catch (netErr) {
        debugPrint('[AttendanceHistory] Network error fetching history: $netErr');
      }

      // 2. Fetch attendance requests
      List<AttendanceRequestModel> listReq = [];
      try {
        final resReq = await _apiClient.get(ApiConstants.userAttendanceRequests);
        if (resReq is List) {
          listReq = resReq.map((item) => AttendanceRequestModel.fromJson(item)).toList();
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _records = listAtt;
          _requests = listReq;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to load attendance history. Please check your connection.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Groups records by date string (e.g. "2026-09-25")
  Map<String, List<AttendanceRecordModel>> _groupRecordsByDate() {
    final Map<String, List<AttendanceRecordModel>> grouped = {};

    for (final r in _records) {
      final dateKey = r.attendanceDate.isNotEmpty ? r.attendanceDate : 'Unknown Date';
      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(r);
    }

    // Sort dates descending
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    final Map<String, List<AttendanceRecordModel>> sorted = {};
    for (final k in sortedKeys) {
      // Sort punches descending by timestamp
      grouped[k]!.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      sorted[k] = grouped[k]!;
    }

    return sorted;
  }

  String _getDateHeaderTitle(String dateStr) {
    try {
      final serverNow = _serverTimeService.estimatedCurrentServerTime;
      final recordDate = DateTime.parse(dateStr);

      final isToday = recordDate.year == serverNow.year &&
                      recordDate.month == serverNow.month &&
                      recordDate.day == serverNow.day;

      final yesterday = serverNow.subtract(const Duration(days: 1));
      final isYesterday = recordDate.year == yesterday.year &&
                          recordDate.month == yesterday.month &&
                          recordDate.day == yesterday.day;

      if (isToday) return "Today's Attendance";
      if (isYesterday) return "Yesterday";
      return DateFormat('dd MMM yyyy').format(recordDate);
    } catch (_) {
      return dateStr;
    }
  }

  Widget _buildAttendanceTab() {
    final grouped = _groupRecordsByDate();

    if (grouped.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.event_busy_rounded, size: 54, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text(
              'No attendance records found.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      itemCount: grouped.length,
      itemBuilder: (ctx, i) {
        final dateKey = grouped.keys.elementAt(i);
        final recordsForDate = grouped[dateKey]!;
        final headerTitle = _getDateHeaderTitle(dateKey);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10, top: 6),
              child: Text(
                headerTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            ...recordsForDate.map((record) => _buildSimpleAttendanceCard(record)).toList(),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildSimpleAttendanceCard(AttendanceRecordModel record) {
    final timeStr = record.displayTime;
    final classification = record.attendanceClassification;
    final isOnTime = classification == 'ON_TIME';
    final shiftName = record.shiftName ?? 'General Shift';

    // Status label formatting: "Present · On Time" or "Present · Late"
    String statusLabel = isOnTime ? 'Present · On Time' : 'Present · Late';
    Color badgeBg = isOnTime ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7);
    Color badgeBorder = isOnTime ? AppColors.success : AppColors.warning;
    Color badgeText = isOnTime ? const Color(0xFF166534) : const Color(0xFF92400E);
    IconData badgeIcon = isOnTime ? Icons.check_circle_rounded : Icons.schedule_rounded;

    if (record.verificationStatus == 'REVIEW_REQUIRED') {
      statusLabel = 'Pending Review';
      badgeBg = const Color(0xFFFEF3C7);
      badgeBorder = const Color(0xFFF59E0B);
      badgeText = const Color(0xFFB45309);
      badgeIcon = Icons.help_outline_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Punch Time & Shift
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                timeStr,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                shiftName,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

          // Right: Simple Employee-Friendly Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: badgeBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(badgeIcon, size: 14, color: badgeText),
                const SizedBox(width: 5),
                Text(
                  statusLabel,
                  style: TextStyle(
                    color: badgeText,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestsTab() {
    if (_requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.inbox_rounded, size: 54, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text(
              'No attendance requests submitted.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      itemCount: _requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final req = _requests[i];
        final isApproved = req.status == 'APPROVED';
        final isRejected = req.status == 'REJECTED';

        Color statusColor = const Color(0xFFB45309);
        Color statusBg = const Color(0xFFFEF3C7);
        if (isApproved) {
          statusColor = const Color(0xFF166534);
          statusBg = const Color(0xFFDCFCE7);
        } else if (isRejected) {
          statusColor = const Color(0xFF991B1B);
          statusBg = const Color(0xFFFEE2E2);
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    req.requestDate,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      req.status,
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (req.rejectionReasonTrigger != null && req.rejectionReasonTrigger!.isNotEmpty) ...[
                Text(
                  'Reason: ${req.rejectionReasonTrigger}',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
              if (req.adminNotes != null && req.adminNotes!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Admin Note: ${req.adminNotes}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Attendance History',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'My Attendance'),
            Tab(text: 'Requests'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAttendanceTab(),
                _buildRequestsTab(),
              ],
            ),
    );
  }
}

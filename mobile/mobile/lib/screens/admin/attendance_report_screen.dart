import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../models/attendance_model.dart';
import '../../core/utils/responsive_util.dart';

class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({Key? key}) : super(key: key);

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  final _apiClient = ApiClient();
  bool _isLoading = true;
  List<AttendanceRecordModel> _records = [];

  @override
  void initState() {
    super.initState();
    _fetchReport();
  }

  Future<void> _fetchReport() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final res = await _apiClient.get(ApiConstants.adminAttendance);
      final list = (res as List).map((item) => AttendanceRecordModel.fromJson(item)).toList();
      if (mounted) {
        setState(() {
          _records = list;
        });
      }
    } catch (e) {
      debugPrint('Error fetching attendance report: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Attendance Log'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchReport,
              child: ResponsiveContainer(
                maxWidth: context.isDesktop ? 1440 : (context.isTablet ? 960 : double.infinity),
                padding: EdgeInsets.zero,
                child: _records.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.assignment_outlined, size: 60, color: AppColors.textSecondary),
                            SizedBox(height: 12),
                            Text(
                              'No attendance records found.',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: ResponsiveUtil.screenPadding(context),
                        itemCount: _records.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (ctx, i) {
                          final rec = _records[i];
                          return Card(
                            child: Padding(
                              padding: ResponsiveUtil.cardPadding(context),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              rec.fullName,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              'ID: ${rec.employeeId} • ${rec.shiftCode ?? "Shift"}: ${rec.shiftName ?? "General"}',
                                              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _getClassificationColor(rec.attendanceClassification).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: _getClassificationColor(rec.attendanceClassification)),
                                        ),
                                        child: Text(
                                          rec.attendanceClassification,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: _getClassificationColor(rec.attendanceClassification),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 18),
                                  Row(
                                    children: [
                                      const Icon(Icons.access_time_filled_rounded, size: 16, color: AppColors.textSecondary),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          '${rec.attendanceDate} • ${rec.timestamp.split("T").last.split(".").first}',
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  // Location & Verification Status Badges
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      _buildStatusChip(
                                        Icons.location_on,
                                        'LOCATION PASS (${rec.verifiedDistanceMeters.toStringAsFixed(1)}m)',
                                        AppColors.success,
                                      ),
                                      _buildStatusChip(
                                        Icons.face_retouching_natural_rounded,
                                        'FACE MATCH (${rec.faceSimilarityScore.toStringAsFixed(2)})',
                                        AppColors.success,
                                      ),
                                      _buildStatusChip(
                                        Icons.verified_rounded,
                                        'LIVENESS PASS',
                                        AppColors.success,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
    );
  }

  Widget _buildStatusChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  Color _getClassificationColor(String code) {
    switch (code) {
      case 'ON_TIME':
        return AppColors.success;
      case 'LATE':
        return AppColors.warning;
      case 'HALF_DAY':
        return Colors.orange;
      case 'AFTERNOON_PUNCH':
        return Colors.purple;
      case 'SECOND_HALF':
        return Colors.indigo;
      default:
        return AppColors.primary;
    }
  }
}

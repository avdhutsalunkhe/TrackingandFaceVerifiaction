import 'package:flutter/material.dart';
import '../../core/services/tracking_database.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/app_theme.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({Key? key}) : super(key: key);

  @override
  State<NotificationCenterScreen> createState() => _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  String _filter = 'ALL'; // 'ALL' or 'UNREAD'

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    final list = await TrackingDatabase.instance.getAllNotifications();
    if (mounted) {
      setState(() {
        _notifications = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _markAsRead(int id) async {
    await TrackingDatabase.instance.markNotificationRead(id);
    await NotificationService.instance.refreshUnreadCount();
    _loadNotifications();
  }

  Future<void> _markAllAsRead() async {
    await TrackingDatabase.instance.markAllNotificationsRead();
    await NotificationService.instance.refreshUnreadCount();
    _loadNotifications();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All notifications marked as read')),
      );
    }
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Notifications'),
        content: const Text('Are you sure you want to delete all notification history?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await TrackingDatabase.instance.clearAllNotifications();
      await NotificationService.instance.refreshUnreadCount();
      _loadNotifications();
    }
  }

  String _formatTimestamp(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoString;
    }
  }

  IconData _getIconForCategory(String category) {
    switch (category.toUpperCase()) {
      case 'ATTENDANCE':
        return Icons.verified_user_rounded;
      case 'TRACKING':
        return Icons.navigation_rounded;
      case 'UPDATE':
        return Icons.system_update_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _getColorForCategory(String category) {
    switch (category.toUpperCase()) {
      case 'ATTENDANCE':
        return const Color(0xFF10B981);
      case 'TRACKING':
        return const Color(0xFF2563EB);
      case 'UPDATE':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filter == 'UNREAD'
        ? _notifications.where((n) => (n['is_read'] ?? 0) == 0).toList()
        : _notifications;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_notifications.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.done_all_rounded),
              tooltip: 'Mark all as read',
              onPressed: _markAllAsRead,
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'Clear all',
              onPressed: _clearAll,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Filter Tabs
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                ChoiceChip(
                  label: Text('All (${_notifications.length})'),
                  selected: _filter == 'ALL',
                  onSelected: (val) {
                    if (val) setState(() => _filter = 'ALL');
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(
                    'Unread (${_notifications.where((n) => (n['is_read'] ?? 0) == 0).length})',
                  ),
                  selected: _filter == 'UNREAD',
                  onSelected: (val) {
                    if (val) setState(() => _filter = 'UNREAD');
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              _filter == 'UNREAD' ? 'No unread notifications' : 'No notifications yet',
                              style: TextStyle(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadNotifications,
                        child: ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final item = filtered[idx];
                            final id = item['id'] as int;
                            final title = item['title'] as String? ?? 'Notification';
                            final message = item['message'] as String? ?? '';
                            final ts = item['timestamp'] as String? ?? '';
                            final category = item['category'] as String? ?? 'SYSTEM';
                            final isRead = (item['is_read'] ?? 0) == 1;

                            return Container(
                              color: isRead ? Colors.white : const Color(0xFFF0FDF4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: _getColorForCategory(category).withOpacity(0.12),
                                  child: Icon(
                                    _getIconForCategory(category),
                                    color: _getColorForCategory(category),
                                    size: 22,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: TextStyle(
                                          fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _formatTimestamp(ts),
                                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                    ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    message,
                                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                                  ),
                                ),
                                onTap: () {
                                  if (!isRead) _markAsRead(id);
                                },
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
}

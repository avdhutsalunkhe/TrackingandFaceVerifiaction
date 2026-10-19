import 'package:flutter/material.dart';

class AttendanceBadge extends StatelessWidget {
  final String status;
  final bool isLarge;

  const AttendanceBadge({
    Key? key,
    required this.status,
    this.isLarge = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color text;
    IconData icon;

    switch (status.toUpperCase()) {
      case 'PRESENT':
        bg = const Color(0xFFDCFCE7);
        text = const Color(0xFF15803D);
        icon = Icons.check_circle_rounded;
        break;
      case 'LATE':
        bg = const Color(0xFFFEF3C7);
        text = const Color(0xFFB45309);
        icon = Icons.access_time_rounded;
        break;
      case 'REJECTED':
      case 'FAILED':
        bg = const Color(0xFFFEE2E2);
        text = const Color(0xFFB91C1C);
        icon = Icons.cancel_rounded;
        break;
      default:
        bg = const Color(0xFFF1F5F9);
        text = const Color(0xFF475569);
        icon = Icons.info_rounded;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isLarge ? 14 : 10,
        vertical: isLarge ? 8 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: isLarge ? 18 : 14, color: text),
          const SizedBox(width: 5),
          Text(
            status.toUpperCase(),
            style: TextStyle(
              color: text,
              fontSize: isLarge ? 14 : 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

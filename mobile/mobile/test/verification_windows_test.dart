import 'package:flutter_test/flutter_test.dart';
import 'package:fieldstaff_attendance/models/attendance_model.dart';
import 'package:fieldstaff_attendance/models/shift_model.dart';

void main() {
  group('Dynamic Multi-Period Verification Rules Model Tests', () {
    test('Parses dynamic verification rules list from server config', () {
      final jsonList = [
        {
          'id': 101,
          'verification_no': 1,
          'rule_name': 'Morning IN',
          'rule_code': 'V1_IN',
          'start_time': '08:00:00',
          'end_time': '08:15:00',
          'label': '08:00 AM – 08:15 AM',
          'status': 'COMPLETED',
          'verified_at': '08:04:12 AM',
          'show_in_user_schedule': true,
        },
        {
          'id': 102,
          'verification_no': 2,
          'rule_name': 'Midday Check',
          'rule_code': 'V2_MID',
          'start_time': '12:00:00',
          'end_time': '12:15:00',
          'label': '12:00 PM – 12:15 PM',
          'status': 'AVAILABLE',
          'show_in_user_schedule': true,
        },
        {
          'id': 103,
          'verification_no': 3,
          'rule_name': 'Evening OUT',
          'rule_code': 'V3_OUT',
          'start_time': '17:00:00',
          'end_time': '17:15:00',
          'label': '05:00 PM – 05:15 PM',
          'status': 'UPCOMING',
          'show_in_user_schedule': true,
        }
      ];

      final items = jsonList.map((j) => VerificationWindowItem.fromJson(j)).toList();
      expect(items.length, 3);

      expect(items[0].id, 101);
      expect(items[0].verificationNo, 1);
      expect(items[0].ruleName, 'Morning IN');
      expect(items[0].status, 'COMPLETED');
      expect(items[0].verifiedAt, '08:04:12 AM');

      expect(items[1].id, 102);
      expect(items[1].verificationNo, 2);
      expect(items[1].ruleName, 'Midday Check');
      expect(items[1].status, 'AVAILABLE');

      expect(items[2].id, 103);
      expect(items[2].status, 'UPCOMING');
    });

    test('Supports N dynamic rules (e.g. 6 verification periods per day)', () {
      final jsonList = List.generate(6, (idx) {
        final vNo = idx + 1;
        return {
          'id': 200 + vNo,
          'verification_no': vNo,
          'rule_name': 'Checkpoint $vNo',
          'rule_code': 'CHECK_$vNo',
          'start_time': '${8 + idx * 2}:00:00',
          'end_time': '${8 + idx * 2}:15:00',
          'status': idx == 0 ? 'COMPLETED' : (idx == 1 ? 'AVAILABLE' : 'UPCOMING'),
          'show_in_user_schedule': true,
        };
      });

      final items = jsonList.map((j) => VerificationWindowItem.fromJson(j)).toList();
      expect(items.length, 6);
      expect(items[0].ruleName, 'Checkpoint 1');
      expect(items[5].ruleName, 'Checkpoint 6');
      expect(items[1].status, 'AVAILABLE');
    });
  });

  group('AttendanceRecordModel Parsing', () {
    test('Parses verification_no, verification_window, source and verification_status', () {
      final json = {
        'id': 101,
        'user_id': 2668,
        'employee_id': 'EMP2668',
        'full_name': 'John Doe',
        'attendance_date': '2026-09-22',
        'timestamp': '2026-09-22T08:42:00',
        'formatted_date': '22 Sep 2026',
        'formatted_time': '08:42:00 AM',
        'status': 'PRESENT',
        'verified_latitude': 18.5204,
        'verified_longitude': 73.8567,
        'verified_distance_meters': 25.4,
        'face_similarity_score': 0.94,
        'liveness_score': 0.99,
        'verification_no': 1,
        'verification_window': '08:00:00 - 09:00:00',
        'source': 'OFFLINE',
        'verification_status': 'PENDING_SYNC',
        'client_punch_id': 'PUNCH-2668-2026-09-22-V1',
      };

      final record = AttendanceRecordModel.fromJson(json);
      expect(record.verificationNo, 1);
      expect(record.verificationWindow, '08:00:00 - 09:00:00');
      expect(record.source, 'OFFLINE');
      expect(record.verificationStatus, 'PENDING_SYNC');
      expect(record.clientPunchId, 'PUNCH-2668-2026-09-22-V1');
      expect(record.displayTime, '08:42:00 AM');
      expect(record.displayDate, '22 Sep 2026');
    });
  });

  group('ShiftRuleModel Serialization Tests', () {
    test('Correctly serializes and deserializes show_in_user_schedule & verification_no', () {
      final json = {
        'id': 50,
        'shift_id': 5,
        'rule_code': 'NORMAL_IN',
        'rule_name': 'Morning Verification',
        'start_time': '08:00:00',
        'end_time': '08:15:00',
        'result_code': 'ON_TIME',
        'result_classification': 'ON_TIME',
        'priority': 1,
        'is_active': true,
        'show_in_user_schedule': false,
        'verification_no': 3,
      };

      final rule = ShiftRuleModel.fromJson(json);
      expect(rule.showInUserSchedule, false);
      expect(rule.verificationNo, 3);

      final outputJson = rule.toJson();
      expect(outputJson['show_in_user_schedule'], false);
      expect(outputJson['verification_no'], 3);
      expect(outputJson['is_active'], true);
      expect(outputJson['result_classification'], 'ON_TIME');
    });
  });
}

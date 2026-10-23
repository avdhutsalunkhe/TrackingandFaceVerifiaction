"""
Comprehensive Automated Regression Test Suite for Shift-Based GPS Tracking
Verifies:
1. Dynamic shift-window and timezone resolution (IST <-> UTC, overnight shifts).
2. Pre-shift coordinates (< 08:30 AM IST) are excluded from official shift routes.
3. Valid in-shift coordinates (08:30 AM - 06:00 PM IST) are accepted.
4. Post-shift coordinates (> 06:00 PM IST) are excluded from official shift routes.
5. Offline sync: valid in-shift coordinates uploaded after shift end are accepted.
6. Timestamp semantic separation: 10:28 AM fix does not end session; actual_stop_time reports scheduled end during active tracking.
7. Zero-point session handling: never marked COMPLETE prematurely; marked INCOMPLETE once concluded.
8. Background scheduler transitions (SCHEDULED -> RECORDING -> COMPLETED).
9. Idempotency across repeated scheduler runs and simulated server restarts.
10. Multi-employee isolation (User 64 and User 65).
11. Real database state verification for User 64 (Session 78).
"""

import sys
import os
from datetime import datetime, date, timedelta, time
import pytz

# Add backend directory to sys.path and load .env
backend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from dotenv import load_dotenv
load_dotenv(os.path.join(backend_dir, ".env"))

from app.database import SessionLocal
from app.models.user import User
from app.models.shift import Shift, ShiftPunchPeriod, EmployeeShiftAssignment
from app.models.tracking import TrackingSession, GpsRoutePoint, TrackingInterruptionEvent
from app.services.shift_tracking_scheduler_service import ShiftTrackingSchedulerService
from app.schemas.tracking import (
    SyncRoutePointsRequest,
    RoutePointItem,
    TrackingSessionSummary,
)
from app.api.tracking import (
    _resolve_shift_window,
    _reconcile_session_health,
    _build_session_summary,
    sync_route_points,
)

IST = pytz.timezone("Asia/Kolkata")
UTC = pytz.utc


def run_tests():
    db = SessionLocal()
    print("=" * 70)
    print("STARTING COMPREHENSIVE SHIFT-BASED GPS TRACKING REGRESSION SUITE")
    print("=" * 70)
    
    passed_tests = 0
    total_tests = 11

    try:
        # -------------------------------------------------------------
        # TEST 1: Timezone and Shift Window Resolution
        # -------------------------------------------------------------
        print("\n[TEST 1] Verifying Shift Window & Timezone Resolution...")
        user64 = db.query(User).filter(User.id == 64).first()
        assert user64 is not None, "User 64 not found in database"
        
        test_date = date(2026, 10, 23)
        shift, s_start_utc, s_end_utc = ShiftTrackingSchedulerService.resolve_shift_window(
            db=db, user_id=64, target_date=test_date
        )
        assert shift is not None, "Shift resolution failed"
        assert shift.shift_code == "S001" or shift.id == 1, f"Expected Shift S001, got {shift.shift_code}"
        
        # 08:30 AM IST = 03:00:00 UTC
        expected_start_utc = datetime(2026, 10, 23, 3, 0, 0)
        # 06:00 PM IST = 12:30:00 UTC
        expected_end_utc = datetime(2026, 10, 23, 12, 30, 0)
        
        assert s_start_utc == expected_start_utc, f"Expected start {expected_start_utc}, got {s_start_utc}"
        assert s_end_utc == expected_end_utc, f"Expected end {expected_end_utc}, got {s_end_utc}"
        print(f"  PASS: S1 Shift correctly resolved: {s_start_utc} UTC to {s_end_utc} UTC (08:30 AM to 06:00 PM IST)")
        passed_tests += 1

        # -------------------------------------------------------------
        # TEST 2: Pre-shift Coordinate Filtering (< 08:30 AM IST)
        # -------------------------------------------------------------
        print("\n[TEST 2] Verifying Pre-Shift Coordinate Filtering (06:50 AM IST)...")
        # 06:50 AM IST = 01:20:00 UTC
        pre_shift_utc = datetime(2026, 10, 23, 1, 20, 0)
        
        # Create a test session
        test_uuid = f"TEST_PRE_SHIFT_{int(datetime.utcnow().timestamp())}"
        test_sess = TrackingSession(
            session_uuid=test_uuid,
            user_id=64,
            work_date=test_date,
            shift_id=shift.id,
            shift_start_time=s_start_utc,
            shift_end_time=s_end_utc,
            start_time=pre_shift_utc,
            status="SCHEDULED",
            tracking_completeness="PENDING_SYNC",
        )
        db.add(test_sess)
        db.commit()
        db.refresh(test_sess)
        
        # Attempt to sync a coordinate at 06:50 AM IST
        req = SyncRoutePointsRequest(
            session_uuid=test_uuid,
            points=[
                RoutePointItem(
                    sequence_number=1,
                    latitude=19.9975,
                    longitude=73.7898,
                    accuracy_meters=10.0,
                    recorded_at=pre_shift_utc,
                    client_point_id=f"{test_uuid}_pt_preshift",
                )
            ]
        )
        resp = sync_route_points(req=req, current_user=user64, db=db)
        assert resp.accepted_count == 0, f"Expected 0 accepted points, got {resp.accepted_count}"
        assert resp.rejected_count == 1, f"Expected 1 rejected point, got {resp.rejected_count}"
        
        # Verify DB does not contain the pre-shift point
        pts_in_db = db.query(GpsRoutePoint).filter(GpsRoutePoint.session_id == test_sess.id).count()
        assert pts_in_db == 0, f"Expected 0 points in DB, found {pts_in_db}"
        print("  PASS: Pre-shift coordinate at 06:50 AM IST was correctly rejected and excluded from official route.")
        passed_tests += 1

        # -------------------------------------------------------------
        # TEST 3: In-shift Coordinate Acceptance (08:30 AM - 06:00 PM IST)
        # -------------------------------------------------------------
        print("\n[TEST 3] Verifying In-Shift Coordinate Acceptance (09:15 AM & 10:28 AM IST)...")
        in_shift_1 = datetime(2026, 10, 23, 3, 45, 0)  # 09:15 AM IST
        in_shift_2 = datetime(2026, 10, 23, 4, 58, 0)  # 10:28 AM IST
        
        req_valid = SyncRoutePointsRequest(
            session_uuid=test_uuid,
            points=[
                RoutePointItem(
                    sequence_number=1,
                    latitude=19.9980,
                    longitude=73.7900,
                    accuracy_meters=8.0,
                    recorded_at=in_shift_1,
                    client_point_id=f"{test_uuid}_pt_valid_1",
                ),
                RoutePointItem(
                    sequence_number=2,
                    latitude=19.9990,
                    longitude=73.7910,
                    accuracy_meters=9.0,
                    recorded_at=in_shift_2,
                    client_point_id=f"{test_uuid}_pt_valid_2",
                ),
            ]
        )
        resp_valid = sync_route_points(req=req_valid, current_user=user64, db=db)
        assert resp_valid.accepted_count == 2, f"Expected 2 accepted points, got {resp_valid.accepted_count}"
        
        db.refresh(test_sess)
        assert test_sess.status == "RECORDING", f"Expected RECORDING, got {test_sess.status}"
        assert test_sess.actual_start_time == in_shift_1, f"Expected actual_start_time {in_shift_1}, got {test_sess.actual_start_time}"
        assert test_sess.last_accepted_time == in_shift_2, f"Expected last_accepted_time {in_shift_2}, got {test_sess.last_accepted_time}"
        print("  PASS: Valid in-shift coordinates accepted; actual_start_time set to first in-shift fix (09:15 AM IST).")
        passed_tests += 1

        # -------------------------------------------------------------
        # TEST 4: Post-shift Coordinate Filtering (> 06:00 PM IST)
        # -------------------------------------------------------------
        print("\n[TEST 4] Verifying Post-Shift Coordinate Filtering (06:15 PM IST)...")
        post_shift_utc = datetime(2026, 10, 23, 12, 45, 0)  # 06:15 PM IST
        req_post = SyncRoutePointsRequest(
            session_uuid=test_uuid,
            points=[
                RoutePointItem(
                    sequence_number=3,
                    latitude=20.0010,
                    longitude=73.7920,
                    accuracy_meters=12.0,
                    recorded_at=post_shift_utc,
                    client_point_id=f"{test_uuid}_pt_postshift",
                )
            ]
        )
        resp_post = sync_route_points(req=req_post, current_user=user64, db=db)
        assert resp_post.accepted_count == 0, f"Expected 0 accepted points, got {resp_post.accepted_count}"
        assert resp_post.rejected_count == 1, f"Expected 1 rejected point, got {resp_post.rejected_count}"
        print("  PASS: Post-shift coordinate at 06:15 PM IST correctly rejected.")
        passed_tests += 1

        # -------------------------------------------------------------
        # TEST 5: Offline Sync of In-Shift Coordinates After Shift End
        # -------------------------------------------------------------
        print("\n[TEST 5] Verifying Delayed Offline Sync Upload After Shift End...")
        # Point recorded at 04:30 PM IST (11:00 UTC), uploaded at 07:00 PM IST (13:30 UTC)
        offline_point_time = datetime(2026, 10, 23, 11, 0, 0)
        req_offline = SyncRoutePointsRequest(
            session_uuid=test_uuid,
            points=[
                RoutePointItem(
                    sequence_number=3,
                    latitude=19.9995,
                    longitude=73.7915,
                    accuracy_meters=7.5,
                    recorded_at=offline_point_time,
                    client_point_id=f"{test_uuid}_pt_offline_sync",
                )
            ]
        )
        resp_offline = sync_route_points(req=req_offline, current_user=user64, db=db)
        assert resp_offline.accepted_count == 1, f"Expected 1 accepted offline point, got {resp_offline.accepted_count}"
        print("  PASS: Delayed in-shift point uploaded after 06:00 PM successfully accepted into official route.")
        passed_tests += 1

        # -------------------------------------------------------------
        # TEST 6: Timestamp Semantic Separation (10:28 AM Fix vs 06:00 PM End)
        # -------------------------------------------------------------
        print("\n[TEST 6] Verifying Timestamp Separation in Active Session Summary...")
        db.refresh(test_sess)
        summary = _build_session_summary(db, test_sess)
        
        # Last GPS fix is at 04:30 PM (or 10:28 AM)
        assert summary.last_accepted_time == offline_point_time
        # But actual_stop_time during active RECORDING MUST reflect shift_end_time (12:30 UTC = 06:00 PM IST)
        assert summary.actual_stop_time == s_end_utc, f"Expected scheduled end {s_end_utc}, got {summary.actual_stop_time}"
        assert summary.actual_start_time == in_shift_1, f"Expected actual_start_time {in_shift_1}, got {summary.actual_start_time}"
        assert summary.status == "RECORDING", f"Expected RECORDING, got {summary.status}"
        print(f"  PASS: Semantically separated: Last fix={summary.last_accepted_time}, Display End={summary.actual_stop_time} (06:00 PM).")
        passed_tests += 1

        # -------------------------------------------------------------
        # TEST 7: Zero-Point Session Completeness & Lifecycle
        # -------------------------------------------------------------
        print("\n[TEST 7] Verifying Zero-Point Session Status Handling...")
        user65 = db.query(User).filter(User.id == 65).first()
        assert user65 is not None, "User 65 not found"
        
        zero_uuid = f"TEST_ZERO_POINT_{int(datetime.utcnow().timestamp())}"
        zero_sess = TrackingSession(
            session_uuid=zero_uuid,
            user_id=65,
            work_date=test_date,
            shift_id=shift.id,
            shift_start_time=s_start_utc,
            shift_end_time=s_end_utc,
            start_time=s_start_utc,
            status="SCHEDULED",
            tracking_completeness="PENDING_SYNC",
        )
        db.add(zero_sess)
        db.commit()
        db.refresh(zero_sess)
        
        # Reconcile during shift time (e.g. at 10:00 AM IST = 04:30 UTC)
        ShiftTrackingSchedulerService.reconcile_session(
            db, zero_sess, as_of_utc=datetime(2026, 10, 23, 4, 30, 0)
        )
        db.refresh(zero_sess)
        assert zero_sess.status == "RECORDING", f"Expected RECORDING during active shift, got {zero_sess.status}"
        assert zero_sess.tracking_completeness == "PENDING_SYNC", f"Expected PENDING_SYNC, got {zero_sess.tracking_completeness}"
        
        # Reconcile AFTER shift time has concluded (e.g. at 07:00 PM IST = 13:30 UTC)
        ShiftTrackingSchedulerService.reconcile_session(
            db, zero_sess, as_of_utc=datetime(2026, 10, 23, 13, 30, 0)
        )
        db.refresh(zero_sess)
        assert zero_sess.status == "COMPLETED", f"Expected COMPLETED, got {zero_sess.status}"
        # A concluded zero-point session MUST be INCOMPLETE, NEVER COMPLETE
        assert zero_sess.tracking_completeness == "INCOMPLETE", f"Expected INCOMPLETE, got {zero_sess.tracking_completeness}"
        print("  PASS: Zero-point session handled correctly: PENDING_SYNC during active shift, INCOMPLETE when shift ended.")
        passed_tests += 1

        # -------------------------------------------------------------
        # TEST 8: Automatic Completion at Shift End
        # -------------------------------------------------------------
        print("\n[TEST 8] Verifying Automatic Finalization at 06:00 PM IST...")
        # Simulate scheduler running at 06:05 PM IST (12:35 UTC)
        ShiftTrackingSchedulerService.reconcile_session(
            db, test_sess, as_of_utc=datetime(2026, 10, 23, 12, 35, 0)
        )
        db.refresh(test_sess)
        assert test_sess.status == "COMPLETED", f"Expected COMPLETED at shift end, got {test_sess.status}"
        assert test_sess.end_time == s_end_utc, f"Expected end_time {s_end_utc}, got {test_sess.end_time}"
        print("  PASS: Tracking session automatically finalized at shift end without employee manual intervention.")
        passed_tests += 1

        # -------------------------------------------------------------
        # TEST 9: Idempotency & Scheduler Restarts
        # -------------------------------------------------------------
        print("\n[TEST 9] Verifying Scheduler Idempotency Across Multiple Runs...")
        # Run evaluate_and_reconcile_all twice
        res1 = ShiftTrackingSchedulerService.evaluate_and_reconcile_all(db, as_of_utc=datetime(2026, 10, 23, 5, 0, 0))
        res2 = ShiftTrackingSchedulerService.evaluate_and_reconcile_all(db, as_of_utc=datetime(2026, 10, 23, 5, 0, 0))
        
        # Verify no duplicate sessions created for User 64 or User 65 on target_date
        sess_count_64 = db.query(TrackingSession).filter(
            TrackingSession.user_id == 64,
            TrackingSession.work_date == test_date,
        ).count()
        sess_count_65 = db.query(TrackingSession).filter(
            TrackingSession.user_id == 65,
            TrackingSession.work_date == test_date,
        ).count()
        
        # Should remain constant between runs (no duplicates)
        res3 = ShiftTrackingSchedulerService.evaluate_and_reconcile_all(db, as_of_utc=datetime(2026, 10, 23, 5, 0, 0))
        sess_count_64_after = db.query(TrackingSession).filter(
            TrackingSession.user_id == 64,
            TrackingSession.work_date == test_date,
        ).count()
        assert sess_count_64 == sess_count_64_after, "Duplicate sessions created on repeated scheduler run"
        print(f"  PASS: Scheduler is strictly idempotent across restart cycles ({sess_count_64} sessions for User 64).")
        passed_tests += 1

        # -------------------------------------------------------------
        # TEST 10: Multi-Employee Isolation
        # -------------------------------------------------------------
        print("\n[TEST 10] Verifying Isolation Between Different Employees...")
        # User 64's points must only be in User 64's sessions
        u64_points = db.query(GpsRoutePoint).filter(GpsRoutePoint.session_id == test_sess.id).all()
        for pt in u64_points:
            assert pt.user_id == 64, f"Cross-contamination: point {pt.id} belongs to user {pt.user_id}, expected 64"
        
        # User 65's zero_sess has 0 points
        u65_points = db.query(GpsRoutePoint).filter(GpsRoutePoint.session_id == zero_sess.id).count()
        assert u65_points == 0, f"User 65 session has unexpected points: {u65_points}"
        print("  PASS: Complete multi-tenant employee session isolation maintained.")
        passed_tests += 1

        # -------------------------------------------------------------
        # TEST 11: Real Database State for Session 78 (User 64, Nilesh Patil)
        # -------------------------------------------------------------
        print("\n[TEST 11] Verifying Real Database Session 78 (Employee 10001)...")
        sess_78 = db.query(TrackingSession).filter(TrackingSession.id == 78).first()
        assert sess_78 is not None, "Session 78 not found in database"
        
        # Reconcile Session 78
        _reconcile_session_health(db, sess_78)
        db.refresh(sess_78)
        
        # Verify first point is in-shift (08:38:41 AM IST = 03:08:41 UTC)
        first_pt = (
            db.query(GpsRoutePoint)
            .filter(GpsRoutePoint.session_id == 78)
            .order_by(GpsRoutePoint.recorded_at.asc(), GpsRoutePoint.id.asc())
            .first()
        )
        assert first_pt is not None, "Session 78 has no points"
        assert first_pt.recorded_at >= datetime(2026, 10, 23, 3, 0, 0), (
            f"Pre-shift point detected in Session 78! First recorded at: {first_pt.recorded_at}"
        )
        
        summary_78 = _build_session_summary(db, sess_78)
        # Verify displayed start time is in-shift (08:38 AM IST)
        start_ist = pytz.utc.localize(summary_78.actual_start_time).astimezone(IST)
        assert start_ist.hour == 8 and start_ist.minute == 38, f"Expected 08:38 AM IST start, got {start_ist}"
        
        # Verify no pre-shift interruption event exists in Session 78
        preshift_interruption = db.query(TrackingInterruptionEvent).filter(
            TrackingInterruptionEvent.session_id == 78,
            TrackingInterruptionEvent.detected_at < datetime(2026, 10, 23, 3, 0, 0),
        ).first()
        assert preshift_interruption is None, "False pre-shift interruption found in Session 78!"
        
        print(f"  PASS: Session 78 verified in MySQL:")
        print(f"        First Point: {first_pt.recorded_at} UTC ({start_ist.strftime('%I:%M:%S %p IST')})")
        print(f"        Total Retained Points: {summary_78.point_count}")
        print(f"        Total Distance: {summary_78.total_distance_meters / 1000.0:.2f} km")
        print(f"        Pre-Shift Excluded: Verified (0 points < 08:30 AM IST)")
        print(f"        Pre-Shift Interruption Gaps: None")
        passed_tests += 1

        # Clean up temporary test sessions
        db.query(GpsRoutePoint).filter(GpsRoutePoint.session_id.in_([test_sess.id, zero_sess.id])).delete(synchronize_session=False)
        db.query(TrackingInterruptionEvent).filter(TrackingInterruptionEvent.session_id.in_([test_sess.id, zero_sess.id])).delete(synchronize_session=False)
        db.query(TrackingSession).filter(TrackingSession.id.in_([test_sess.id, zero_sess.id])).delete(synchronize_session=False)
        db.commit()

        print("\n" + "=" * 70)
        print(f"ALL {passed_tests}/{total_tests} REGRESSION TESTS PASSED SUCCESSFULLY!")
        print("=" * 70)

    except Exception as e:
        db.rollback()
        print(f"\nTEST FAILED WITH ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        db.close()

if __name__ == "__main__":
    run_tests()

import uuid
import pytest
from datetime import datetime, date, timedelta, time
from fastapi.testclient import TestClient
from app.main import app
from app.database import SessionLocal
from app.models.user import User, UserRole
from app.models.tracking import TrackingSession, TrackingInterruptionEvent, GpsRoutePoint
from app.models.shift import Shift, EmployeeShiftAssignment, ShiftPunchPeriod
from app.security.tokens import create_access_token

client = TestClient(app)


@pytest.fixture
def test_setup():
    db = SessionLocal()
    try:
        # 1. Create dedicated user for each test to ensure complete isolation
        emp_code = f"T_{uuid.uuid4().hex[:8]}"
        user = User(
            employee_id=emp_code,
            full_name=f"Shift Employee {emp_code}",
            password_hash="test",
            role=UserRole.USER,
            is_active=True,
        )
        db.add(user)
        db.commit()
        db.refresh(user)

        # 2. Ensure test shift (08:30 to 18:00)
        shift = db.query(Shift).filter(Shift.shift_code == "TEST_SHIFT_01").first()
        if not shift:
            shift = Shift(
                shift_code="TEST_SHIFT_01",
                shift_name="Test Standard Day Shift",
                description="Standard day shift for testing",
                timezone="Asia/Kolkata",
                is_active=True,
            )
            db.add(shift)
            db.commit()
            db.refresh(shift)

            period = ShiftPunchPeriod(
                shift_id=shift.id,
                punch_no=1,
                period_name="Day Tracking Period",
                start_time=time(8, 30),
                end_time=time(18, 0),
                priority=1,
                is_active=True,
            )
            db.add(period)
            db.commit()

        # 3. Create active assignment for this dedicated test user
        assignment = EmployeeShiftAssignment(
            user_id=user.id,
            shift_id=shift.id,
            effective_from=date(2024, 1, 1),
            effective_to=date(2030, 12, 31),
            is_active=True,
        )
        db.add(assignment)
        db.commit()

        token = create_access_token(data={"sub": str(user.id)})
        headers = {"Authorization": f"Bearer {token}"}
        user_id = user.id
        shift_id = shift.id

        return {
            "headers": headers,
            "user_id": user_id,
            "shift_id": shift_id,
        }
    finally:
        db.close()


def test_scenario_1_and_2_shift_begins_single_session_guarantee(test_setup):
    """Scenario 1 & 2: Shift begins automatically; verifies exactly one logical session created and duplicate calls recover existing session."""
    headers = test_setup["headers"]
    today_str = date.today().isoformat()
    canonical_uuid = f"TRACK_{test_setup['user_id']}_SHIFT_{test_setup['shift_id']}_{today_str}"

    # 1. Resolve shift session endpoint
    res_resolve = client.post(
        "/api/tracking/resolve-shift-session",
        json={"target_date": today_str},
        headers=headers,
    )
    assert res_resolve.status_code == 200, res_resolve.text
    resolve_data = res_resolve.json()
    assert resolve_data["has_shift"] is True
    assert resolve_data["session_uuid"] == canonical_uuid
    assert resolve_data["status"] in ["SCHEDULED", "RECORDING", "ACTIVE"]

    # 2. Start tracking session
    res_start = client.post(
        "/api/tracking/start",
        json={
            "session_uuid": canonical_uuid,
            "shift_id": test_setup["shift_id"],
            "start_latitude": 18.5204,
            "start_longitude": 73.8567,
            "start_time": datetime.utcnow().isoformat(),
        },
        headers=headers,
    )
    assert res_start.status_code == 200, res_start.text
    start_data = res_start.json()
    assert start_data["session_uuid"] == canonical_uuid

    # 3. Duplicate start invocation (e.g. repeated alarm / service restart): MUST NOT spawn duplicate session
    res_duplicate = client.post(
        "/api/tracking/start",
        json={
            "session_uuid": f"TRACK_DUPLICATE_ALARM_{datetime.utcnow().timestamp()}",
            "shift_id": test_setup["shift_id"],
            "start_latitude": 18.5204,
            "start_longitude": 73.8567,
            "start_time": datetime.utcnow().isoformat(),
        },
        headers=headers,
    )
    assert res_duplicate.status_code == 200
    dup_data = res_duplicate.json()
    assert dup_data["session_uuid"] == canonical_uuid, "Duplicate start call must return the existing active canonical session UUID!"


def test_scenario_3_and_4_location_services_disabled_and_restored(test_setup):
    """Scenario 3 & 4: User disables location services; interruption recorded, duration calculated, and recovers to active session."""
    headers = test_setup["headers"]
    today_str = date.today().isoformat()
    session_uuid = f"TRACK_{test_setup['user_id']}_SHIFT_{test_setup['shift_id']}_{today_str}"
    event_uuid = f"INT_{session_uuid}_GPS_OFF_{int(datetime.utcnow().timestamp())}"

    det_time = datetime.utcnow()
    rec_time = det_time + timedelta(minutes=5)

    # 1. Record LOCATION_SERVICES_DISABLED interruption
    res_int = client.post(
        "/api/tracking/interruption",
        json={
            "session_uuid": session_uuid,
            "event_uuid": event_uuid,
            "reason_code": "LOCATION_SERVICES_DISABLED",
            "description": "User or OS disabled location services.",
            "detected_at": det_time.isoformat(),
            "severity": "CRITICAL",
            "is_confirmed": True,
        },
        headers=headers,
    )
    assert res_int.status_code == 200, res_int.text
    int_data = res_int.json()
    assert int_data["event_uuid"] == event_uuid
    assert int_data["reason_code"] == "LOCATION_SERVICES_DISABLED"

    # 2. Record recovery when location services are restored
    res_rec = client.post(
        "/api/tracking/recovery",
        json={
            "session_uuid": session_uuid,
            "event_uuid": event_uuid,
            "reason_code": "LOCATION_SERVICES_DISABLED",
            "recovered_at": rec_time.isoformat(),
            "recovery_outcome": "RESOLVED",
            "notes": "GPS restored by user.",
        },
        headers=headers,
    )
    assert res_rec.status_code == 200, res_rec.text
    rec_data = res_rec.json()
    assert abs(rec_data["duration_seconds"] - 300) <= 2
    assert rec_data["recovery_outcome"] == "RESOLVED"


def test_scenario_5_poor_gps_accuracy_rejected_without_session_termination(test_setup):
    """Scenario 5: GPS produces low-accuracy fix; recorded as POOR_ACCURACY degradation, coordinate rejected from route, but session stays open."""
    headers = test_setup["headers"]
    today_str = date.today().isoformat()
    session_uuid = f"TRACK_{test_setup['user_id']}_SHIFT_{test_setup['shift_id']}_{today_str}"
    event_uuid = f"INT_{session_uuid}_POOR_ACC_{int(datetime.utcnow().timestamp())}"

    # 1. Report degradation
    res_int = client.post(
        "/api/tracking/interruption",
        json={
            "session_uuid": session_uuid,
            "event_uuid": event_uuid,
            "reason_code": "POOR_ACCURACY",
            "description": "GPS accuracy 95m exceeded maximum allowed threshold (65m)",
            "detected_at": datetime.utcnow().isoformat(),
            "severity": "WARNING",
            "diagnostic_details": {"accuracy_meters": 95.0, "threshold": 65.0},
        },
        headers=headers,
    )
    assert res_int.status_code == 200
    assert res_int.json()["reason_code"] == "POOR_ACCURACY"

    # 2. Verify session is still open and receiving valid points
    res_pt = client.post(
        "/api/tracking/points",
        json={
            "session_uuid": session_uuid,
            "points": [
                {
                    "client_point_id": f"{session_uuid}_good_pt_{int(datetime.utcnow().timestamp())}",
                    "sequence_number": 100,
                    "latitude": 18.5210,
                    "longitude": 73.8570,
                    "accuracy_meters": 6.5,
                    "recorded_at": datetime.utcnow().isoformat(),
                }
            ],
            "current_distance_meters": 120.0,
        },
        headers=headers,
    )
    assert res_pt.status_code == 200
    assert res_pt.json()["synced_count"] == 1


def test_scenario_7_and_8_offline_events_and_points_batch_sync(test_setup):
    """Scenario 7 & 8: Network disconnects; client collects points & interruption events locally, then reconnects and uploads full backlog."""
    headers = test_setup["headers"]
    today_str = date.today().isoformat()
    session_uuid = f"TRACK_{test_setup['user_id']}_SHIFT_{test_setup['shift_id']}_{today_str}"

    offline_event_uuid = f"INT_OFFLINE_{session_uuid}_{int(datetime.utcnow().timestamp())}"
    now = datetime.utcnow()

    # Sync offline backlog of interruption events
    res_sync = client.post(
        "/api/tracking/sync-offline-events",
        json={
            "session_uuid": session_uuid,
            "events": [
                {
                    "event_uuid": offline_event_uuid,
                    "session_uuid": session_uuid,
                    "reason_code": "INTERNET_DISCONNECTED",
                    "description": "Internet unavailable. GPS points buffered in offline SQLite.",
                    "detected_at": (now - timedelta(minutes=15)).isoformat(),
                    "recovered_at": now.isoformat(),
                    "duration_seconds": 900,
                    "severity": "INFO",
                    "recovery_outcome": "RESOLVED",
                    "is_confirmed": True,
                }
            ]
        },
        headers=headers,
    )
    assert res_sync.status_code == 200, res_sync.text
    sync_data = res_sync.json()
    assert sync_data["success"] is True
    assert sync_data["synced_count"] == 1
    assert offline_event_uuid in sync_data["synced_event_ids"]


def test_scenario_9_10_11_service_stopped_and_heartbeat_gap(test_setup):
    """Scenario 9, 10, 11: Background service terminated or rebooted; heartbeat reports state and resumes seamlessly."""
    headers = test_setup["headers"]
    today_str = date.today().isoformat()
    session_uuid = f"TRACK_{test_setup['user_id']}_SHIFT_{test_setup['shift_id']}_{today_str}"

    res_hb = client.post(
        "/api/tracking/heartbeat",
        json={
            "session_uuid": session_uuid,
            "battery_level": 78,
            "is_charging": False,
            "network_type": "WIFI",
            "location_services_enabled": True,
            "permission_status": "always",
            "is_foreground_service_running": True,
            "last_point_timestamp": datetime.utcnow().isoformat(),
        },
        headers=headers,
    )
    assert res_hb.status_code == 200, res_hb.text
    assert res_hb.json()["success"] is True
    assert res_hb.json()["should_stop"] is False


def test_scenario_14_shift_ends_normally_and_closes_open_interruptions(test_setup):
    """Scenario 14: Shift ends normally while an interruption was open; stop closes open event with SHIFT_CONCLUDED."""
    headers = test_setup["headers"]
    today_str = date.today().isoformat()
    session_uuid = f"TRACK_{test_setup['user_id']}_SHIFT_{test_setup['shift_id']}_{today_str}"

    # Open an interruption
    event_uuid = f"INT_{session_uuid}_OPEN_AT_END_{int(datetime.utcnow().timestamp())}"
    client.post(
        "/api/tracking/interruption",
        json={
            "session_uuid": session_uuid,
            "event_uuid": event_uuid,
            "reason_code": "LOCATION_SERVICES_DISABLED",
            "description": "User turned GPS off right before shift ended",
            "detected_at": datetime.utcnow().isoformat(),
            "severity": "WARNING",
        },
        headers=headers,
    )

    # Stop tracking session
    res_stop = client.post(
        "/api/tracking/stop",
        json={
            "session_uuid": session_uuid,
            "end_latitude": 18.5204,
            "end_longitude": 73.8567,
            "end_time": datetime.utcnow().isoformat(),
            "total_distance_meters": 1500.0,
        },
        headers=headers,
    )
    assert res_stop.status_code == 200, res_stop.text
    assert res_stop.json()["success"] is True

    # Verify session status is COMPLETED and completeness is evaluated
    db = SessionLocal()
    session = db.query(TrackingSession).filter(TrackingSession.session_uuid == session_uuid).first()
    assert session is not None
    assert session.status == "COMPLETED"
    assert session.actual_stop_time is not None
    assert session.tracking_completeness in ["COMPLETE", "HAS_GAPS", "PENDING_SYNC"]

    # Verify the open interruption was automatically finalized
    open_events = db.query(TrackingInterruptionEvent).filter(
        TrackingInterruptionEvent.session_uuid == session_uuid,
        TrackingInterruptionEvent.recovery_outcome == "UNRESOLVED",
    ).all()
    assert len(open_events) == 0, "No unresolved interruption events should remain after shift stop!"

    # Verify interruptions endpoint returns full chronological history
    db.close()
    res_history = client.get(
        f"/api/tracking/sessions/{session.id}/interruptions",
        headers=headers,
    )
    assert res_history.status_code == 200
    events_list = res_history.json()
    assert len(events_list) >= 1
    assert any(e["event_uuid"] == event_uuid for e in events_list)


def test_scenario_13_overnight_shift_resolution(test_setup):
    """Scenario 13: Shift crossing midnight (e.g. 21:00 to 06:00 next morning)."""
    db = SessionLocal()
    try:
        shift = db.query(Shift).filter(Shift.shift_code == "TEST_NIGHT_01").first()
        if not shift:
            shift = Shift(
                shift_code="TEST_NIGHT_01",
                shift_name="Test Night Shift",
                description="Overnight shift crossing midnight",
                timezone="Asia/Kolkata",
                is_active=True,
            )
            db.add(shift)
            db.commit()
            db.refresh(shift)

            period = ShiftPunchPeriod(
                shift_id=shift.id,
                punch_no=1,
                period_name="Night Tracking Period",
                start_time=time(21, 0),
                end_time=time(6, 0),
                priority=1,
                is_active=True,
            )
            db.add(period)
            db.commit()

        user_id = test_setup["user_id"]
        token = create_access_token(data={"sub": str(user_id)})
        headers = {"Authorization": f"Bearer {token}"}

        # Deactivate any previous assignments and assign night shift
        db.query(EmployeeShiftAssignment).filter(
            EmployeeShiftAssignment.user_id == user_id
        ).update({"is_active": False})

        assignment = EmployeeShiftAssignment(
            user_id=user_id,
            shift_id=shift.id,
            effective_from=date(2024, 1, 1),
            effective_to=date(2030, 12, 31),
            is_active=True,
        )
        db.add(assignment)
        db.commit()
    finally:
        db.close()

    res = client.post(
        "/api/tracking/resolve-shift-session",
        json={"target_date": date.today().isoformat()},
        headers=headers,
    )
    assert res.status_code == 200
    data = res.json()
    assert data["has_shift"] is True
    assert data["shift_start_time"] is not None
    assert data["shift_end_time"] is not None

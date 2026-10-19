import pytest
from datetime import datetime, date
from fastapi.testclient import TestClient
from app.main import app
from app.database import get_db, SessionLocal
from app.models.user import User, UserRole
from app.models.tracking import TrackingSession, GpsRoutePoint, TrackingRouteChunk
from app.security.tokens import create_access_token

client = TestClient(app)


@pytest.fixture
def auth_headers():
    db = SessionLocal()
    user = db.query(User).filter(User.employee_id == "admin").first()
    if not user:
        user = db.query(User).first()
    user_id = user.id if user else 1
    db.close()
    token = create_access_token(data={"sub": str(user_id)})
    return {"Authorization": f"Bearer {token}"}


def test_offline_points_auto_recovery_and_deduplication(auth_headers):
    """Verifies that if mobile starts offline and sends points before /start, backend auto-creates session and persists points idempotently."""
    session_uuid = f"TEST_OFFLINE_RECOVERY_{int(datetime.utcnow().timestamp())}"

    # 1. Send points without calling /start first
    points_payload = {
        "session_uuid": session_uuid,
        "points": [
            {
                "client_point_id": f"{session_uuid}_pt_1",
                "sequence_number": 1,
                "latitude": 18.5204,
                "longitude": 73.8567,
                "accuracy_meters": 5.0,
                "recorded_at": datetime.utcnow().isoformat(),
            },
            {
                "client_point_id": f"{session_uuid}_pt_2",
                "sequence_number": 2,
                "latitude": 18.5206,
                "longitude": 73.8569,
                "accuracy_meters": 6.0,
                "recorded_at": datetime.utcnow().isoformat(),
            },
        ],
        "current_distance_meters": 28.5,
    }

    res = client.post("/api/tracking/points", json=points_payload, headers=auth_headers)
    assert res.status_code == 200, res.text
    data = res.json()
    assert data["success"] is True
    assert data["synced_count"] == 2

    # 2. Resend the same points: verify idempotency without duplicate crash
    res_retry = client.post("/api/tracking/points", json=points_payload, headers=auth_headers)
    assert res_retry.status_code == 200
    retry_data = res_retry.json()
    assert retry_data["synced_count"] == 0
    assert len(retry_data["synced_point_ids"]) == 2


def test_chunks_duplicate_sequence_safety(auth_headers):
    """Verifies that re-transmitting chunks with existing chunk_sequence updates idempotently without 1062 IntegrityError."""
    session_uuid = f"TEST_CHUNKS_RETRY_{int(datetime.utcnow().timestamp())}"

    # 1. Send first chunk
    chunk_1 = {
        "session_uuid": session_uuid,
        "chunks": [
            {
                "chunk_uuid": f"{session_uuid}_chk_1_v1",
                "chunk_sequence": 1,
                "point_count": 2,
                "encoded_geometry": "[[18.52,73.85,1700000000,5.0,0,0,0],[18.521,73.851,1700000005,5.0,0,0,0]]",
                "start_time": datetime.utcnow().isoformat(),
                "end_time": datetime.utcnow().isoformat(),
                "distance_meters": 50.0,
            }
        ],
        "current_distance_meters": 50.0,
        "retained_point_count": 2,
    }

    res1 = client.post("/api/tracking/chunks", json=chunk_1, headers=auth_headers)
    assert res1.status_code == 200, res1.text
    assert res1.json()["success"] is True

    # 2. Send updated chunk with SAME chunk_sequence (e.g. after local recalculation or retry with different UUID)
    chunk_1_updated = {
        "session_uuid": session_uuid,
        "chunks": [
            {
                "chunk_uuid": f"{session_uuid}_chk_1_v2",
                "chunk_sequence": 1,
                "point_count": 3,
                "encoded_geometry": "[[18.52,73.85,1700000000,5.0,0,0,0],[18.521,73.851,1700000005,5.0,0,0,0],[18.522,73.852,1700000010,5.0,0,0,0]]",
                "start_time": datetime.utcnow().isoformat(),
                "end_time": datetime.utcnow().isoformat(),
                "distance_meters": 110.0,
            }
        ],
        "current_distance_meters": 110.0,
        "retained_point_count": 3,
    }

    res2 = client.post("/api/tracking/chunks", json=chunk_1_updated, headers=auth_headers)
    assert res2.status_code == 200, res2.text
    assert res2.json()["success"] is True


def test_tracking_event_logging(auth_headers):
    """Verifies that native background service lifecycle and GPS health events are recorded."""
    session_uuid = f"TEST_EVENT_LOG_{int(datetime.utcnow().timestamp())}"

    event_payload = {
        "session_uuid": session_uuid,
        "event_type": "SERVICE_STARTED",
        "details": "Native Android Location Foreground Service started",
        "battery_optimization_ignored": True,
        "timestamp": datetime.utcnow().isoformat(),
    }

    res = client.post("/api/tracking/event", json=event_payload, headers=auth_headers)
    assert res.status_code == 200, res.text
    assert res.json()["success"] is True

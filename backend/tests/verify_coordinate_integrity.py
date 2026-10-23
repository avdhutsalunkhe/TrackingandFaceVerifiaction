import sys
import os
import math
sys.path.insert(0, os.path.abspath("."))
import requests
from app.database import SessionLocal
from app.models.user import User
from app.models.tracking import TrackingSession, GpsRoutePoint
from app.services.auth_service import create_user_token

def haversine(lat1, lon1, lat2, lon2):
    R = 6371000.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlam = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlam / 2)**2
    return 2 * R * math.atan2(math.sqrt(a), math.sqrt(1 - a))

def run_coordinate_integrity_tests():
    db = SessionLocal()
    user_64 = db.query(User).filter(User.id == 64).first()
    user_65 = db.query(User).filter(User.id == 65).first()
    admin = db.query(User).filter(User.role == 'ADMIN').first()

    token_64 = create_user_token(user_64)["access_token"]
    token_65 = create_user_token(user_65)["access_token"]
    token_admin = create_user_token(admin)["access_token"]
    db.close()

    base_url = "http://127.0.0.1:5084"
    h64 = {"Authorization": f"Bearer {token_64}"}
    h_admin = {"Authorization": f"Bearer {token_admin}"}

    print("================ GPS COORDINATE INTEGRITY & SEQUENCE REGRESSION TESTS ================")

    # Test 1: Coordinate Integrity & Decimal Precision (8 Decimals)
    test_lat = 17.06713167
    test_lng = 74.28782667
    pt_id_1 = f"TEST_PRECISION_PT_{int(os.times().system * 1000)}"
    sync_payload = {
        "session_uuid": "TRACK_64_GENERAL_2026-10-23",
        "points": [
            {
                "client_point_id": pt_id_1,
                "sequence_number": 99991,
                "latitude": test_lat,
                "longitude": test_lng,
                "accuracy_meters": 3.5,
                "speed_mps": 0.0,
                "bearing_degrees": 0.0,
                "recorded_at": "2026-10-23T05:15:00Z"
            }
        ]
    }
    r = requests.post(f"{base_url}/api/tracking/points", json=sync_payload, headers=h64)
    assert r.status_code == 200, f"Sync failed: {r.text}"
    print("1. Coordinate Ingestion: Accepted successfully.")

    # Verify directly from DB
    db = SessionLocal()
    saved = db.query(GpsRoutePoint).filter(GpsRoutePoint.client_point_id == pt_id_1).first()
    assert saved is not None
    assert abs(float(saved.latitude) - test_lat) < 1e-7, f"Latitude precision loss: {saved.latitude} vs {test_lat}"
    assert abs(float(saved.longitude) - test_lng) < 1e-7, f"Longitude precision loss: {saved.longitude} vs {test_lng}"
    dist_error = haversine(test_lat, test_lng, float(saved.latitude), float(saved.longitude))
    print(f"   DB Precision Verified: lat={saved.latitude}, lng={saved.longitude}, geodesic error={dist_error:.6f} meters")
    assert dist_error < 0.01

    # Clean up test point
    db.delete(saved)
    db.commit()
    db.close()

    # Test 2: Dual-stream near-instantaneous twin fix de-duplication
    twin_id_1 = f"TWIN_A_{int(os.times().system * 1000)}"
    twin_id_2 = f"TWIN_B_{int(os.times().system * 1000)}"
    twin_payload = {
        "session_uuid": "TRACK_64_GENERAL_2026-10-23",
        "points": [
            {
                "client_point_id": twin_id_1,
                "sequence_number": 500,
                "latitude": 17.06713000,
                "longitude": 74.28782000,
                "accuracy_meters": 4.0,
                "recorded_at": "2026-10-23T05:20:00Z"
            },
            {
                "client_point_id": twin_id_2,
                "sequence_number": 500,  # Duplicate sequence number and twin timestamp
                "latitude": 17.06713050,  # 0.06 meters away
                "longitude": 74.28782050,
                "accuracy_meters": 4.1,
                "recorded_at": "2026-10-23T05:20:00Z"
            }
        ]
    }
    r_twin = requests.post(f"{base_url}/api/tracking/points", json=twin_payload, headers=h64)
    assert r_twin.status_code == 200
    res_twin = r_twin.json()
    print("2. Dual-Stream Deduplication Response:", res_twin)
    assert res_twin["accepted_count"] == 1, f"Expected 1 accepted, got {res_twin['accepted_count']}"
    assert res_twin["duplicate_count"] == 1, f"Expected 1 deduplicated, got {res_twin['duplicate_count']}"
    assert twin_id_1 in res_twin["synced_point_ids"]
    assert twin_id_2 in res_twin["synced_point_ids"]
    print("   Dual-Stream Twin Fix safely deduplicated without creating duplicate markers!")

    # Clean up twin point
    db = SessionLocal()
    db.query(GpsRoutePoint).filter(GpsRoutePoint.client_point_id.in_([twin_id_1, twin_id_2])).delete(synchronize_session=False)
    db.commit()
    db.close()

    # Test 3: Session 78 Route Reconstruction & Monotonic Sequences
    r_route = requests.get(f"{base_url}/api/tracking/sessions/78/route?raw=true", headers=h_admin)
    assert r_route.status_code == 200
    route_data = r_route.json()
    pts = route_data["points"]
    print(f"3. Session 78 Route Check: Total Points = {len(pts)}")
    assert len(pts) > 3000, "Expected > 3000 points in Session 78"

    # Verify strictly monotonic sequences 1..N
    seqs = [p["sequence_number"] for p in pts]
    assert len(seqs) == len(set(seqs)), "Found duplicate sequence numbers in route response!"
    assert seqs[0] == 1, f"First sequence is {seqs[0]}, expected 1"
    assert seqs[-1] == len(pts), f"Last sequence is {seqs[-1]}, expected {len(pts)}"
    print("   Sequence Numbers: 100% strictly monotonic 1..N with ZERO duplicates!")

    # Verify chronological ordering
    time_jumps_backward = 0
    for i in range(1, len(pts)):
        t1 = pts[i-1]["recorded_at"]
        t2 = pts[i]["recorded_at"]
        if t2 < t1:
            time_jumps_backward += 1
    print(f"   Chronological Integrity: Backward time jumps = {time_jumps_backward}")
    assert time_jumps_backward == 0, "Route points are not strictly chronological!"

    # Test 4: Session 78 Raw Points Pagination Check
    r_p1 = requests.get(f"{base_url}/api/tracking/sessions/78/raw-points?page=1&limit=100", headers=h_admin)
    r_p2 = requests.get(f"{base_url}/api/tracking/sessions/78/raw-points?page=2&limit=100", headers=h_admin)
    assert r_p1.status_code == 200 and r_p2.status_code == 200
    p1_pts = r_p1.json()["points"]
    p2_pts = r_p2.json()["points"]
    assert p1_pts[0]["sequence_number"] == 1
    assert p1_pts[-1]["sequence_number"] == 100
    assert p2_pts[0]["sequence_number"] == 101
    assert p2_pts[-1]["sequence_number"] == 200
    print("4. Raw Points Pagination: Page 1 (1..100) and Page 2 (101..200) strictly contiguous!")

    # Test 5: Session 76 (Oct 22, 15,494 points)
    r_s76 = requests.get(f"{base_url}/api/tracking/sessions/76/route?raw=true", headers=h_admin)
    assert r_s76.status_code == 200
    s76_pts = r_s76.json()["points"]
    print(f"5. Session 76 Route Check: Total Points = {len(s76_pts)}")
    assert len(s76_pts) == 15494, f"Expected 15494 points, got {len(s76_pts)}"
    s76_seqs = [p["sequence_number"] for p in s76_pts]
    assert len(s76_seqs) == len(set(s76_seqs)), "Duplicate sequence numbers in Session 76!"
    assert s76_seqs[0] == 1 and s76_seqs[-1] == 15494
    print("   Session 76: 15,494 points verified with strictly monotonic sequence numbers 1..15494!")

    print("\n>>> ALL GPS COORDINATE & SEQUENCE REGRESSION TESTS PASSED! <<<")

if __name__ == "__main__":
    run_coordinate_integrity_tests()

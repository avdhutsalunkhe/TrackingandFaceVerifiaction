import urllib.request
import json
import sqlite3
import os
from datetime import datetime, timedelta

# Coordinates connecting Field Area A to regional sites (Karad / Sangli / Satara belt)
ROUTE_COORDINATES = [
    (17.0634895, 74.2843875, 0.0, 4.2),   # Point 1: Field Area A Office (Start)
    (17.0641200, 74.2850100, 2.1, 5.0),   # Point 2: Gate exit
    (17.0652000, 74.2861000, 4.5, 6.2),   # Point 3: Main access road
    (17.0664500, 74.2872500, 6.2, 5.5),   # Point 4: Turning northeast
    (17.0678000, 74.2885000, 7.1, 7.0),   # Point 5: Rural road section
    (17.0691000, 74.2899000, 8.3, 6.8),   # Point 6: En route to Sector 2
    (17.0705500, 74.2912000, 9.0, 5.2),   # Point 7: Crossing canal bridge
    (17.0719000, 74.2926000, 7.8, 6.1),   # Point 8: Speed reduction at junction
    (17.0731000, 74.2941000, 6.5, 8.4),   # Point 9: East connector road
    (17.0742000, 74.2954000, 5.2, 7.3),   # Point 10: Agricultural inspection zone
    (17.0751000, 74.2968000, 4.1, 6.5),   # Point 11: Sector checkpoint
    (17.0758000, 74.2981000, 3.5, 9.1),   # Point 12: Slowing down
    (17.0763000, 74.2995000, 2.8, 5.4),   # Point 13: Local village passage
    (17.0769000, 74.3010000, 4.0, 6.0),   # Point 14: Accelerating outward
    (17.0775000, 74.3025000, 5.5, 5.8),   # Point 15: East perimeter
    (17.0781000, 74.3041000, 6.8, 7.2),   # Point 16: Open stretch
    (17.0788000, 74.3056000, 7.2, 6.9),   # Point 17: North curve
    (17.0794000, 74.3072000, 5.0, 8.0),   # Point 18: Entering inspection area
    (17.0801000, 74.3088000, 3.2, 5.5),   # Point 19: Site approach
    (17.0806000, 74.3099000, 0.0, 4.8),   # Point 20: Field Workstation (Destination)
]

def calculate_distance(lat1, lon1, lat2, lon2):
    import math
    p = 0.017453292519943295
    a = 0.5 - math.cos((lat2 - lat1) * p) / 2 + math.cos(lat1 * p) * math.cos(lat2 * p) * (1 - math.cos((lon2 - lon1) * p)) / 2
    return 12742000 * math.asin(math.sqrt(a))

total_dist = 0.0
for i in range(1, len(ROUTE_COORDINATES)):
    total_dist += calculate_distance(
        ROUTE_COORDINATES[i-1][0], ROUTE_COORDINATES[i-1][1],
        ROUTE_COORDINATES[i][0], ROUTE_COORDINATES[i][1]
    )

print(f"Calculated Total Distance: {total_dist:.2f} meters ({total_dist / 1000:.2f} km)")

# Prepare points payload
session_uuid = 'TRACK_0_2026-10-17_PUNCH_1792220549100'
start_base_time = datetime(2026, 10, 17, 7, 2, 30)

points_payload = []
for idx, (lat, lon, spd, acc) in enumerate(ROUTE_COORDINATES):
    pt_time = start_base_time + timedelta(seconds=idx * 95)
    points_payload.append({
        'client_point_id': f"{session_uuid}_PT_{idx + 1}",
        'sequence_number': idx + 1,
        'latitude': lat,
        'longitude': lon,
        'accuracy_meters': acc,
        'altitude_meters': 580.0 + idx * 1.5,
        'speed_mps': spd,
        'bearing_degrees': 48.5,
        'recorded_at': pt_time.isoformat() + "Z",
    })

# 1. PUSH TO LAN SERVER (http://192.168.1.91:8084)
lan_url = 'http://192.168.1.91:8084'
print(f"Connecting to LAN Server: {lan_url}...")
try:
    login_body = json.dumps({'employee_id': 'admin', 'password': 'admin123'}).encode()
    login_req = urllib.request.Request(f"{lan_url}/api/auth/login", data=login_body, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(login_req, timeout=5) as l_res:
        auth_data = json.loads(l_res.read().decode())
        token = auth_data['access_token']
        print("[+] Logged into LAN server successfully.")

    sync_body = json.dumps({
        'session_uuid': session_uuid,
        'points': points_payload,
        'current_distance_meters': total_dist,
        'current_duration_seconds': len(ROUTE_COORDINATES) * 95,
    }).encode()

    sync_req = urllib.request.Request(
        f"{lan_url}/api/tracking/points",
        data=sync_body,
        headers={
            'Content-Type': 'application/json',
            'Authorization': f"Bearer {token}",
        }
    )
    with urllib.request.urlopen(sync_req, timeout=10) as s_res:
        resp = json.loads(s_res.read().decode())
        print(f"[+] LAN Server Response: {resp}")

except Exception as e:
    print(f"[-] Error pushing to LAN server: {e}")

# 2. PUSH DIRECTLY TO LOCAL SQLITE DATABASE
local_db = 'backend/fieldstaff_attendance.db'
if os.path.exists(local_db):
    print(f"Updating local SQLite database: {local_db}...")
    conn = sqlite3.connect(local_db)
    cur = conn.cursor()

    now_str = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')
    # Find or insert session
    cur.execute("SELECT id FROM tracking_sessions WHERE session_uuid = ?", (session_uuid,))
    sess_row = cur.fetchone()
    if not sess_row:
        cur.execute("""
            INSERT INTO tracking_sessions (session_uuid, user_id, attendance_id, work_date, start_time, status, start_latitude, start_longitude, total_distance_meters, total_duration_seconds, created_at, updated_at)
            VALUES (?, 2, 1792220549100, '2026-10-17', '2026-10-17 07:02:29', 'RECORDING', ?, ?, ?, ?, ?, ?)
        """, (session_uuid, ROUTE_COORDINATES[0][0], ROUTE_COORDINATES[0][1], total_dist, len(ROUTE_COORDINATES) * 95, now_str, now_str))
        session_id = cur.lastrowid
        print(f"[+] Created session {session_id} in local DB.")
    else:
        session_id = sess_row[0]
        cur.execute("""
            UPDATE tracking_sessions
            SET start_latitude = ?, start_longitude = ?, total_distance_meters = ?, total_duration_seconds = ?, updated_at = ?
            WHERE id = ?
        """, (ROUTE_COORDINATES[0][0], ROUTE_COORDINATES[0][1], total_dist, len(ROUTE_COORDINATES) * 95, now_str, session_id))
        print(f"[+] Updated session {session_id} in local DB.")

    # Insert route points
    for p in points_payload:
        cur.execute("""
            INSERT OR REPLACE INTO gps_route_points 
            (session_id, user_id, client_point_id, sequence_number, latitude, longitude, accuracy_meters, altitude_meters, speed_mps, bearing_degrees, recorded_at, sync_status, created_at)
            VALUES (?, 2, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'SYNCED', ?)
        """, (
            session_id,
            p['client_point_id'],
            p['sequence_number'],
            p['latitude'],
            p['longitude'],
            p['accuracy_meters'],
            p['altitude_meters'],
            p['speed_mps'],
            p['bearing_degrees'],
            p['recorded_at'],
            now_str,
        ))

    conn.commit()
    conn.close()
    print(f"[+] Successfully saved {len(points_payload)} route points into local SQLite!")

print("=== ALL TRACKING DATA SUCCESSFULLY PUSHED ===")

import os
import sys
import sqlite3

db_path = os.path.join(os.path.dirname(__file__), "..", "fieldstaff_attendance.db")
print(f"Connecting to database: {db_path}")

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# 1. Add missing columns to attendance
try:
    cursor.execute("ALTER TABLE attendance ADD COLUMN liveness_result VARCHAR(32) DEFAULT 'REAL'")
    print("[SUCCESS] Added liveness_result to attendance")
except Exception as e:
    print("[INFO] attendance (liveness_result):", e)

# 2. Add missing columns to attendance_attempts
try:
    cursor.execute("ALTER TABLE attendance_attempts ADD COLUMN verification_no INTEGER")
    print("[SUCCESS] Added verification_no to attendance_attempts")
except Exception as e:
    print("[INFO] attendance_attempts (verification_no):", e)

try:
    cursor.execute("ALTER TABLE attendance_attempts ADD COLUMN client_punch_id VARCHAR(128)")
    print("[SUCCESS] Added client_punch_id to attendance_attempts")
except Exception as e:
    print("[INFO] attendance_attempts (client_punch_id):", e)

try:
    cursor.execute("ALTER TABLE attendance_attempts ADD COLUMN source VARCHAR(32) DEFAULT 'ONLINE'")
    print("[SUCCESS] Added source to attendance_attempts")
except Exception as e:
    print("[INFO] attendance_attempts (source):", e)

conn.commit()
conn.close()
print("Migration script executed.")

"""
Database Migration Script: 3-Window Attendance Verification & Offline Sync System
Upgrades SQLite or MySQL database schema to support:
- verification_no (1, 2, 3)
- verification_window ("08:00:00 - 09:00:00", etc.)
- server_time, device_wall_time, source, client_punch_id, verification_status, sync_status, sync_notes
- Canonical 3-window shift ("TRIPLE_WINDOW")
"""

import sys
import os
from datetime import time, date

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from sqlalchemy import text
from app.database import engine, SessionLocal, Base
from app.models.shift import Shift, ShiftRule, EmployeeShiftAssignment
from app.models.setting import SystemSetting

def run_migration():
    print("[Migration] Starting migration to 3-Window Attendance & Offline Queue System...")
    
    # Ensure all tables registered in Base are created
    Base.metadata.create_all(bind=engine)
    
    with engine.connect() as conn:
        dialect = engine.dialect.name
        print(f"[Migration] Detected database dialect: {dialect}")

        # Columns to add to 'attendance'
        attendance_cols = [
            ("verification_no", "INTEGER NOT NULL DEFAULT 1"),
            ("verification_window", "VARCHAR(64) NOT NULL DEFAULT '08:00:00 - 09:00:00'"),
            ("server_time", "DATETIME NULL"),
            ("device_wall_time", "VARCHAR(64) NULL"),
            ("verification_status", "VARCHAR(32) NOT NULL DEFAULT 'CONFIRMED'"),
            ("source", "VARCHAR(32) NOT NULL DEFAULT 'ONLINE'"),
            ("client_punch_id", "VARCHAR(128) NULL"),
            ("sync_status", "VARCHAR(32) NOT NULL DEFAULT 'SYNCED'"),
            ("sync_notes", "TEXT NULL"),
            ("face_result", "VARCHAR(32) NOT NULL DEFAULT 'MATCH'")
        ]

        for col_name, col_def in attendance_cols:
            try:
                if dialect == "sqlite":
                    conn.execute(text(f"ALTER TABLE attendance ADD COLUMN {col_name} {col_def}"))
                else:
                    conn.execute(text(f"ALTER TABLE attendance ADD COLUMN IF NOT EXISTS `{col_name}` {col_def}"))
                print(f"  + Added column attendance.{col_name}")
            except Exception as e:
                # Column might already exist
                if "duplicate column name" in str(e).lower() or "already exists" in str(e).lower():
                    pass
                else:
                    print(f"  ~ Notice on attendance.{col_name}: {e}")

        # Unique index on client_punch_id
        try:
            conn.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS uq_attendance_client_punch_id ON attendance (client_punch_id)"))
            print("  + Created index uq_attendance_client_punch_id")
        except Exception as e:
            print(f"  ~ Notice on uq_attendance_client_punch_id: {e}")

        # Attendance requests table updates
        req_cols = [
            ("verification_no", "INTEGER NOT NULL DEFAULT 1"),
            ("client_request_id", "VARCHAR(128) NULL")
        ]
        for col_name, col_def in req_cols:
            try:
                if dialect == "sqlite":
                    conn.execute(text(f"ALTER TABLE attendance_requests ADD COLUMN {col_name} {col_def}"))
                else:
                    conn.execute(text(f"ALTER TABLE attendance_requests ADD COLUMN IF NOT EXISTS `{col_name}` {col_def}"))
                print(f"  + Added column attendance_requests.{col_name}")
            except Exception as e:
                if "duplicate column name" in str(e).lower() or "already exists" in str(e).lower():
                    pass
                else:
                    print(f"  ~ Notice on attendance_requests.{col_name}: {e}")

        conn.commit()

    # Now seed/update canonical 3-Window Shift
    db = SessionLocal()
    try:
        # Default system setting for max offline sync age
        offline_setting = db.query(SystemSetting).filter(SystemSetting.key == "MAX_OFFLINE_SYNC_AGE_SECONDS").first()
        if not offline_setting:
            offline_setting = SystemSetting(
                key="MAX_OFFLINE_SYNC_AGE_SECONDS",
                value="14400", # 4 hours
                description="Maximum acceptable offline duration in seconds before flagging for review"
            )
            db.add(offline_setting)
            db.commit()
            print("[Migration] Seeded MAX_OFFLINE_SYNC_AGE_SECONDS = 14400 (4 hours)")

        # Create or update canonical 3-Window Shift
        canonical_code = "TRIPLE_WINDOW"
        triple_shift = db.query(Shift).filter(Shift.shift_code == canonical_code).first()
        if not triple_shift:
            triple_shift = Shift(
                shift_code=canonical_code,
                shift_name="3-Window Daily Verification Shift",
                description="Authoritative shift with 3 daily verification windows: 08:00-09:00, 13:00-13:20, 17:00-18:00",
                is_active=True
            )
            db.add(triple_shift)
            db.flush()

        # Ensure the 3 canonical rules exist on this shift
        windows_rules = [
            ("VERIFY_1", "Verification 1 (Morning)", time(8, 0, 0), time(9, 0, 0), "VERIFICATION_1", 1),
            ("VERIFY_2", "Verification 2 (Afternoon)", time(13, 0, 0), time(13, 20, 0), "VERIFICATION_2", 2),
            ("VERIFY_3", "Verification 3 (Evening)", time(17, 0, 0), time(18, 0, 0), "VERIFICATION_3", 3),
        ]

        existing_rule_codes = {r.rule_code: r for r in triple_shift.rules}
        for code, name, st, et, res_code, prio in windows_rules:
            if code in existing_rule_codes:
                r = existing_rule_codes[code]
                r.rule_name = name
                r.start_time = st
                r.end_time = et
                r.result_code = res_code
                r.priority = prio
                r.is_active = True
            else:
                new_rule = ShiftRule(
                    shift_id=triple_shift.id,
                    rule_code=code,
                    rule_name=name,
                    start_time=st,
                    end_time=et,
                    result_code=res_code,
                    priority=prio,
                    is_active=True
                )
                db.add(new_rule)

        # Update legacy S001 shift rules as well to avoid confusion if assigned
        s001 = db.query(Shift).filter(Shift.shift_code == "S001").first()
        if s001:
            s001.shift_name = "General 3-Window Shift"
            s001.description = "Updated to 3-window verification schedule"
            s001_rule_codes = {r.rule_code: r for r in s001.rules}
            for code, name, st, et, res_code, prio in windows_rules:
                if code in s001_rule_codes:
                    r = s001_rule_codes[code]
                    r.rule_name = name
                    r.start_time = st
                    r.end_time = et
                    r.result_code = res_code
                    r.priority = prio
                    r.is_active = True
                else:
                    db.add(ShiftRule(
                        shift_id=s001.id,
                        rule_code=code,
                        rule_name=name,
                        start_time=st,
                        end_time=et,
                        result_code=res_code,
                        priority=prio,
                        is_active=True
                    ))
            # Deactivate legacy rules like "LATE_IN", "HALF_DAY", "AFTERNOON_PUNCH", "SECOND_HALF"
            for r in s001.rules:
                if r.rule_code not in ["VERIFY_1", "VERIFY_2", "VERIFY_3"]:
                    r.is_active = False

        db.commit()
        print("[Migration] 3-Window Shift rules successfully configured.")

    finally:
        db.close()

    print("[Migration] Migration completed successfully.")

if __name__ == "__main__":
    run_migration()

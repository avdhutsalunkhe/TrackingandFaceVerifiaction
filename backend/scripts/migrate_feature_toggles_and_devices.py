"""
Migration: Feature Toggles and Device ID Registration
Adds face_enabled, geofence_enabled, shift_enabled, travel_map_enabled, device_id,
device_registered_at, device_model to the users table.
Migrates existing users by safely inferring active features.
"""

from app.database import engine
from sqlalchemy import text

def run_migration():
    with engine.connect() as conn:
        cols = [c[0] for c in conn.execute(text('DESCRIBE users')).fetchall()]
        print(f"Existing users columns: {cols}")

        if 'face_enabled' not in cols:
            print("Adding face_enabled...")
            conn.execute(text("ALTER TABLE users ADD COLUMN face_enabled TINYINT(1) NOT NULL DEFAULT 1"))

        if 'geofence_enabled' not in cols:
            print("Adding geofence_enabled...")
            conn.execute(text("ALTER TABLE users ADD COLUMN geofence_enabled TINYINT(1) NOT NULL DEFAULT 1"))

        if 'shift_enabled' not in cols:
            print("Adding shift_enabled...")
            conn.execute(text("ALTER TABLE users ADD COLUMN shift_enabled TINYINT(1) NOT NULL DEFAULT 1"))

        if 'travel_map_enabled' not in cols:
            print("Adding travel_map_enabled...")
            conn.execute(text("ALTER TABLE users ADD COLUMN travel_map_enabled TINYINT(1) NOT NULL DEFAULT 1"))

        if 'device_id' not in cols:
            print("Adding device_id...")
            conn.execute(text("ALTER TABLE users ADD COLUMN device_id VARCHAR(128) NULL"))
            conn.execute(text("CREATE INDEX idx_users_device_id ON users(device_id)"))

        if 'device_registered_at' not in cols:
            print("Adding device_registered_at...")
            conn.execute(text("ALTER TABLE users ADD COLUMN device_registered_at DATETIME NULL"))

        if 'device_model' not in cols:
            print("Adding device_model...")
            conn.execute(text("ALTER TABLE users ADD COLUMN device_model VARCHAR(128) NULL"))

        conn.commit()

        # Migrate existing configurations
        users = conn.execute(text("SELECT id, employee_id, role FROM users")).fetchall()
        for u in users:
            uid, eid, role = u[0], u[1], u[2]
            has_face = bool(conn.execute(text("SELECT id FROM face_templates WHERE user_id=:uid"), {"uid": uid}).fetchone())
            has_geo = bool(conn.execute(text("SELECT id FROM geofences WHERE user_id=:uid"), {"uid": uid}).fetchone())
            has_shift = bool(conn.execute(text("SELECT id FROM employee_shift_assignments WHERE user_id=:uid"), {"uid": uid}).fetchone())
            has_track = bool(conn.execute(text("SELECT id FROM tracking_sessions WHERE user_id=:uid"), {"uid": uid}).fetchone())

            face_on = 1 if has_face or role == 'ADMIN' else 0
            geo_on = 1 if has_geo or role == 'ADMIN' else 0
            shift_on = 1 if has_shift else 0
            track_on = 1 if has_track or role in ('ADMIN', 'USER') else 0

            conn.execute(text("""
                UPDATE users 
                SET face_enabled = :face_on,
                    geofence_enabled = :geo_on,
                    shift_enabled = :shift_on,
                    travel_map_enabled = :track_on
                WHERE id = :uid
            """), {
                "face_on": face_on,
                "geo_on": geo_on,
                "shift_on": shift_on,
                "track_on": track_on,
                "uid": uid
            })

        conn.commit()
        print("Feature toggles and device migration complete.")

if __name__ == "__main__":
    run_migration()

from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker
from app.config import settings

# Configure engine with connection pool & pre-ping for reliability
connect_args = {}
if "sqlite" in settings.DATABASE_URL:
    connect_args = {"check_same_thread": False}

engine = create_engine(
    settings.DATABASE_URL,
    pool_pre_ping=True,
    pool_recycle=3600,
    connect_args=connect_args,
    echo=settings.DEBUG and False # Set to True if SQL query debugging is desired
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

def run_auto_migrations(target_engine):
    """Ensure new schema columns exist on existing databases."""
    try:
        from sqlalchemy import inspect, text
        inspector = inspect(target_engine)
        tables = inspector.get_table_names()

        def safe_add_column(table_name, col_name, sql_clause):
            if table_name in tables:
                columns = [c["name"] for c in inspector.get_columns(table_name)]
                if col_name not in columns:
                    try:
                        with target_engine.begin() as conn:
                            conn.execute(text(f"ALTER TABLE {table_name} ADD COLUMN {col_name} {sql_clause}"))
                    except Exception as ex:
                        print(f"[AutoMigration] Failed adding {col_name} to {table_name}: {ex}")

        def safe_modify_column(table_name, col_name, sql_type_clause):
            if table_name in tables and "sqlite" not in str(target_engine.url):
                try:
                    with target_engine.begin() as conn:
                        conn.execute(text(f"ALTER TABLE {table_name} MODIFY COLUMN {col_name} {sql_type_clause}"))
                except Exception as ex:
                    print(f"[AutoMigration] Notice modifying {col_name} in {table_name}: {ex}")

        safe_add_column("shift_rules", "verification_no", "INTEGER NOT NULL DEFAULT 1")
        safe_add_column("shift_rules", "show_in_user_schedule", "BOOLEAN NOT NULL DEFAULT 1")
        safe_add_column("shift_rules", "result_classification", "VARCHAR(64) NULL")
        safe_add_column("shift_rules", "updated_at", "DATETIME NULL")

        safe_add_column("shifts", "timezone", "VARCHAR(64) NOT NULL DEFAULT 'Asia/Kolkata'")
        safe_add_column("shifts", "day_type_policy_id", "INTEGER NULL")
        safe_add_column("shifts", "attendance_policy_id", "INTEGER NULL")

        safe_add_column("users", "department", "VARCHAR(128) NULL")
        safe_add_column("users", "department_id", "INTEGER NULL")
        safe_add_column("users", "unit_number", "INTEGER NULL")
        safe_add_column("users", "designation", "VARCHAR(128) NULL")

        safe_add_column("attendance", "verification_rule_id", "INTEGER NULL")

        safe_add_column("attendance_attempts", "verification_rule_id", "INTEGER NULL")

        safe_add_column("gps_route_points", "is_gap", "INTEGER NOT NULL DEFAULT 0")

        # Storage-efficient tracking sessions summary & route chunks
        safe_add_column("tracking_sessions", "retained_point_count", "INTEGER NOT NULL DEFAULT 0")
        safe_add_column("tracking_sessions", "last_accepted_latitude", "DECIMAL(11, 8) NULL")
        safe_add_column("tracking_sessions", "last_accepted_longitude", "DECIMAL(11, 8) NULL")
        safe_add_column("tracking_sessions", "last_accepted_time", "DATETIME NULL")
        safe_add_column("tracking_sessions", "last_heartbeat_time", "DATETIME NULL")
        safe_add_column("tracking_sessions", "last_sync_time", "DATETIME NULL")
        safe_add_column("tracking_sessions", "shift_start_time", "DATETIME NULL")
        safe_add_column("tracking_sessions", "shift_end_time", "DATETIME NULL")
        safe_add_column("tracking_sessions", "actual_start_time", "DATETIME NULL")
        safe_add_column("tracking_sessions", "actual_stop_time", "DATETIME NULL")
        safe_add_column("tracking_sessions", "device_id", "VARCHAR(128) NULL")
        safe_add_column("tracking_sessions", "tracking_completeness", "VARCHAR(32) NOT NULL DEFAULT 'COMPLETE'")

        if "tracking_route_chunks" not in tables:
            try:
                from app.models.tracking import TrackingRouteChunk
                TrackingRouteChunk.__table__.create(target_engine, checkfirst=True)
                print("[AutoMigration] Created tracking_route_chunks table")
            except Exception as ex:
                print(f"[AutoMigration] Failed creating tracking_route_chunks: {ex}")

        if "tracking_interruption_events" not in tables:
            try:
                from app.models.tracking import TrackingInterruptionEvent
                TrackingInterruptionEvent.__table__.create(target_engine, checkfirst=True)
                print("[AutoMigration] Created tracking_interruption_events table")
            except Exception as ex:
                print(f"[AutoMigration] Failed creating tracking_interruption_events: {ex}")

        # Upgrade users role enum & coordinates to full precision DECIMAL(11, 8)
        safe_modify_column("users", "role", "ENUM('ADMIN', 'USER', 'TIME_OFFICE') NOT NULL DEFAULT 'USER'")
        safe_modify_column("geofences", "latitude", "DECIMAL(11, 8) NOT NULL")
        safe_modify_column("geofences", "longitude", "DECIMAL(11, 8) NOT NULL")
        safe_modify_column("attendance", "verified_latitude", "DECIMAL(11, 8) NOT NULL")
        safe_modify_column("attendance", "verified_longitude", "DECIMAL(11, 8) NOT NULL")
        safe_modify_column("attendance_attempts", "latitude", "DECIMAL(11, 8) NULL")
        safe_modify_column("attendance_attempts", "longitude", "DECIMAL(11, 8) NULL")
        safe_modify_column("attendance_requests", "latitude", "DECIMAL(11, 8) NOT NULL")
        safe_modify_column("attendance_requests", "longitude", "DECIMAL(11, 8) NOT NULL")

        # Dynamic Punch Periods Table Migration
        if "shift_punch_periods" not in tables:
            try:
                from app.models.shift import ShiftPunchPeriod
                ShiftPunchPeriod.__table__.create(target_engine, checkfirst=True)
                print("[AutoMigration] Created shift_punch_periods table")
            except Exception as ex:
                print(f"[AutoMigration] Failed creating shift_punch_periods: {ex}")

        # Safe add punch_period_id to attendance and attendance_attempts
        safe_add_column("attendance", "punch_period_id", "INTEGER NULL")
        safe_add_column("attendance_attempts", "punch_period_id", "INTEGER NULL")

        # Sync legacy rules into shift_punch_periods if needed
        try:
            with target_engine.begin() as conn:
                conn.execute(text("UPDATE shift_rules SET updated_at = created_at WHERE updated_at IS NULL"))
                count_res = conn.execute(text("SELECT COUNT(*) FROM shift_punch_periods")).scalar()
                if count_res == 0 and "shift_rules" in tables:
                    conn.execute(text("""
                        INSERT INTO shift_punch_periods (
                            id, shift_id, punch_no, period_name, start_time, end_time,
                            show_in_user_schedule, is_active, priority, require_face_verification,
                            created_at, updated_at
                        )
                        SELECT 
                            id, shift_id, verification_no, rule_name, start_time, end_time,
                            show_in_user_schedule, is_active, priority, 1,
                            created_at, COALESCE(updated_at, created_at, CURRENT_TIMESTAMP)
                        FROM shift_rules
                    """))
                    print("[AutoMigration] Synced shift_rules to shift_punch_periods")

                # Backfill punch_period_id from verification_rule_id if empty
                conn.execute(text("""
                    UPDATE attendance 
                    SET punch_period_id = verification_rule_id 
                    WHERE punch_period_id IS NULL AND verification_rule_id IS NOT NULL
                """))
                conn.execute(text("""
                    UPDATE attendance_attempts 
                    SET punch_period_id = verification_rule_id 
                    WHERE punch_period_id IS NULL AND verification_rule_id IS NOT NULL
                """))
        except Exception as ex:
            print(f"[AutoMigration] Notice during legacy rules sync: {ex}")

        # Role Master Table Migration & Seeding
        if "role_masters" not in tables:
            try:
                from app.models.role import RoleMaster
                RoleMaster.__table__.create(target_engine, checkfirst=True)
                print("[AutoMigration] Created role_masters table")
            except Exception as ex:
                print(f"[AutoMigration] Failed creating role_masters: {ex}")

        # Holidays, WeeklyOffConfigs & ExtraWorkRequests Tables Migration
        if "holidays" not in tables:
            try:
                from app.models.policy import Holiday
                Holiday.__table__.create(target_engine, checkfirst=True)
                print("[AutoMigration] Created holidays table")
            except Exception as ex:
                print(f"[AutoMigration] Failed creating holidays: {ex}")

        if "weekly_off_configs" not in tables:
            try:
                from app.models.policy import WeeklyOffConfig
                WeeklyOffConfig.__table__.create(target_engine, checkfirst=True)
                print("[AutoMigration] Created weekly_off_configs table")
            except Exception as ex:
                print(f"[AutoMigration] Failed creating weekly_off_configs: {ex}")

        # Tracking Sessions & Route Points Migration
        if "tracking_sessions" not in tables:
            try:
                from app.models.tracking import TrackingSession, GpsRoutePoint
                TrackingSession.__table__.create(target_engine, checkfirst=True)
                GpsRoutePoint.__table__.create(target_engine, checkfirst=True)
                print("[AutoMigration] Created tracking_sessions and gps_route_points tables")
            except Exception as ex:
                print(f"[AutoMigration] Failed creating tracking tables: {ex}")
        else:
            try:
                with target_engine.begin() as conn:
                    if "mysql" in str(target_engine.url).lower():
                        conn.execute(text("ALTER TABLE tracking_sessions MODIFY COLUMN attendance_id BIGINT NULL;"))
                        # Ensure gps_route_points has employee_id and device_id columns
                        try:
                            conn.execute(text("ALTER TABLE gps_route_points ADD COLUMN employee_id VARCHAR(64) NULL;"))
                            conn.execute(text("CREATE INDEX idx_gps_route_points_emp ON gps_route_points (employee_id);"))
                        except Exception:
                            pass
                        try:
                            conn.execute(text("ALTER TABLE gps_route_points ADD COLUMN device_id VARCHAR(128) NULL;"))
                            conn.execute(text("CREATE INDEX idx_gps_route_points_dev ON gps_route_points (device_id);"))
                        except Exception:
                            pass
            except Exception:
                pass

        if "extra_work_requests" not in tables:
            try:
                from app.models.policy import ExtraWorkRequest
                ExtraWorkRequest.__table__.create(target_engine, checkfirst=True)
                print("[AutoMigration] Created extra_work_requests table")
            except Exception as ex:
                print(f"[AutoMigration] Failed creating extra_work_requests: {ex}")

        # Automatic Patch Update System Tables
        if "app_update_policies" not in tables:
            try:
                from app.models.app_update import AppUpdatePolicy
                AppUpdatePolicy.__table__.create(target_engine, checkfirst=True)
                print("[AutoMigration] Created app_update_policies table")
            except Exception as ex:
                print(f"[AutoMigration] Failed creating app_update_policies: {ex}")

        if "app_update_logs" not in tables:
            try:
                from app.models.app_update import AppUpdateLog
                AppUpdateLog.__table__.create(target_engine, checkfirst=True)
                print("[AutoMigration] Created app_update_logs table")
            except Exception as ex:
                print(f"[AutoMigration] Failed creating app_update_logs: {ex}")

        try:
            with target_engine.begin() as conn:
                role_count = conn.execute(text("SELECT COUNT(*) FROM role_masters")).scalar()
                if role_count == 0:
                    conn.execute(text("""
                        INSERT INTO role_masters (role_code, role_name, description, is_admin, permissions, is_system_role, is_active, created_at, updated_at)
                        VALUES 
                        ('ADMIN', 'System Administrator', 'Full administrative authority across all modules & settings', 1, 'attendance,requests,reports,shifts,departments,roles,settings', 1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
                        ('SUPERVISOR', 'Field & Office Supervisor', 'Operational supervisor with attendance management & approval power', 1, 'attendance,requests,reports,shifts', 1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
                        ('TIME_OFFICE', 'Time Office Executive', 'Desktop console operator managing shifts, rules & corrections', 1, 'attendance,requests,reports,shifts,departments', 1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
                        ('USER', 'Field Employee / Staff', 'Standard mobile attendance app user', 0, 'attendance', 1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                    """))
                    print("[AutoMigration] Seeded default Master Roles into role_masters")
        except Exception as ex:
            print(f"[AutoMigration] Notice during role_masters seed: {ex}")
    except Exception as e:
        print(f"[AutoMigration] Warning running column migrations: {e}")

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

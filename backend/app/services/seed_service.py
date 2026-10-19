from datetime import time
from sqlalchemy.orm import Session
from app.models.policy import AttendancePolicy, DayTypePolicy, ShiftEvent, DayType, EventType, PunchWindowMode
from app.models.shift import Shift, ShiftRule

class SeedService:
    @staticmethod
    def seed_default_policies_and_shifts(db: Session):
        """Seed standard configurable policies and sample shifts if missing."""
        # 1. Default Attendance Policy
        default_policy = db.query(AttendancePolicy).filter_by(name="Standard Strict Policy").first()
        if not default_policy:
            default_policy = AttendancePolicy(
                name="Standard Strict Policy",
                description="Strict window enforcement, missed punch approval required, out-of-sequence blocked.",
                missed_punch_enabled=True,
                missed_punch_requires_face=True,
                missed_punch_requires_liveness=True,
                missed_punch_requires_gps=True,
                missed_punch_requires_approval=True,
                allow_out_of_sequence=False,
                duplicate_punch_policy="REJECT",
                absence_calculation_mode="SESSION_BASED",
                half_day_enabled=True,
                full_day_absence_enabled=True
            )
            db.add(default_policy)
            db.commit()
            db.refresh(default_policy)

        # 2. Default Day Type Policy
        default_day_policy = db.query(DayTypePolicy).filter_by(day_type=DayType.NORMAL).first()
        if not default_day_policy:
            default_day_policy = DayTypePolicy(
                day_type=DayType.NORMAL,
                punch_window_mode=PunchWindowMode.STRICT,
                face_required=True,
                liveness_required=True,
                gps_required=True
            )
            db.add(default_day_policy)
            db.commit()
            db.refresh(default_day_policy)

        # 3. Sample Shift 1: General 2-Event Shift
        gen_shift = db.query(Shift).filter_by(shift_code="GEN01").first()
        if not gen_shift:
            gen_shift = Shift(
                shift_code="GEN01",
                shift_name="General Day Shift",
                description="Standard 9-hour single-session shift",
                timezone="Asia/Kolkata",
                attendance_policy_id=default_policy.id,
                day_type_policy_id=default_day_policy.id,
                is_active=True
            )
            db.add(gen_shift)
            db.commit()
            db.refresh(gen_shift)

            # Events
            ev1 = ShiftEvent(
                shift_id=gen_shift.id,
                sequence_no=1,
                session_id=1,
                event_type=EventType.IN,
                event_name="Morning IN",
                window_start=time(8, 0, 0),
                window_end=time(10, 0, 0),
                grace_period_seconds=300,
                is_required=True
            )
            ev2 = ShiftEvent(
                shift_id=gen_shift.id,
                sequence_no=2,
                session_id=1,
                event_type=EventType.OUT,
                event_name="Evening OUT",
                window_start=time(17, 0, 0),
                window_end=time(19, 0, 0),
                grace_period_seconds=300,
                is_required=True
            )
            db.add_all([ev1, ev2])
            db.commit()

        # 4. Sample Shift 2: Split Shift A (4 Events)
        split_shift = db.query(Shift).filter_by(shift_code="SPLIT01").first()
        if not split_shift:
            split_shift = Shift(
                shift_code="SPLIT01",
                shift_name="General Split Shift A",
                description="Two-session split shift with 4 distinct punch events",
                timezone="Asia/Kolkata",
                attendance_policy_id=default_policy.id,
                day_type_policy_id=default_day_policy.id,
                is_active=True
            )
            db.add(split_shift)
            db.commit()
            db.refresh(split_shift)

            # 4 Events for split shift
            s_ev1 = ShiftEvent(shift_id=split_shift.id, sequence_no=1, session_id=1, event_type=EventType.IN, event_name="Session 1 IN", window_start=time(6, 0, 0), window_end=time(7, 0, 0), grace_period_seconds=300)
            s_ev2 = ShiftEvent(shift_id=split_shift.id, sequence_no=2, session_id=1, event_type=EventType.OUT, event_name="Session 1 OUT", window_start=time(10, 0, 0), window_end=time(11, 0, 0), grace_period_seconds=300)
            s_ev3 = ShiftEvent(shift_id=split_shift.id, sequence_no=3, session_id=2, event_type=EventType.IN, event_name="Session 2 IN", window_start=time(16, 0, 0), window_end=time(17, 0, 0), grace_period_seconds=300)
            s_ev4 = ShiftEvent(shift_id=split_shift.id, sequence_no=4, session_id=2, event_type=EventType.OUT, event_name="Session 2 OUT", window_start=time(20, 0, 0), window_end=time(21, 0, 0), grace_period_seconds=300)
            db.add_all([s_ev1, s_ev2, s_ev3, s_ev4])
            db.commit()

        print("[SeedService] Default policies, day types, and configurable sample shifts seeded.")

    @staticmethod
    def seed_default_users(db: Session):
        """Seed default operational system users (admin, timeoffice) if missing."""
        from app.models.user import User, UserRole
        from app.security.hashing import get_password_hash

        # 1. Admin User
        admin_user = db.query(User).filter_by(employee_id="admin").first()
        if not admin_user:
            admin_user = User(
                employee_id="admin",
                full_name="System Administrator",
                password_hash=get_password_hash("admin123"),
                role=UserRole.ADMIN,
                is_active=True,
                must_change_password=False
            )
            db.add(admin_user)
            print("[SeedService] Created default admin user ('admin')")

        # 2. Time Office User
        time_office_user = db.query(User).filter_by(employee_id="timeoffice").first()
        if not time_office_user:
            time_office_user = User(
                employee_id="timeoffice",
                full_name="Time Office Operator",
                password_hash=get_password_hash("timeoffice123"),
                role=UserRole.TIME_OFFICE,
                is_active=True,
                must_change_password=False
            )
            db.add(time_office_user)
            print("[SeedService] Created default Time Office user ('timeoffice')")

        db.commit()


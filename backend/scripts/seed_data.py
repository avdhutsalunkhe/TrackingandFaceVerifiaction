import sys
import os
from datetime import time

# Add parent directory to sys.path so app modules can be imported
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from app.database import engine, SessionLocal, Base
from app.models.user import User, UserRole
from app.models.geofence import Geofence, AttendanceWindow
from app.security.hashing import get_password_hash

def seed():
    print("[Seed] Creating database tables...")
    Base.metadata.create_all(bind=engine)
    
    db = SessionLocal()
    try:
        # 1. Create Default Admin
        admin_user = db.query(User).filter(User.employee_id == "admin").first()
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
            db.commit()
            db.refresh(admin_user)
            print("[Seed] Admin user created: admin / admin123")
        else:
            print("[Seed] Admin user already exists.")

        # 2. Create Test Employee 2668
        emp_2668 = db.query(User).filter(User.employee_id == "2668").first()
        if not emp_2668:
            emp_2668 = User(
                employee_id="2668",
                full_name="Employee 2668",
                password_hash=get_password_hash("2668"),
                role=UserRole.USER,
                is_active=True,
                must_change_password=True # Enforce password change on first login
            )
            db.add(emp_2668)
            db.commit()
            db.refresh(emp_2668)
            print("[Seed] Employee 2668 created: 2668 / 2668 (must_change_password=True)")

            # Assign Geofence (Field Area A: 16.1234567, 74.1234567, Radius 100m)
            gf = Geofence(
                user_id=emp_2668.id,
                location_name="Field Area A",
                latitude=16.1234567,
                longitude=74.1234567,
                radius_meters=100.0,
                is_active=True
            )
            db.add(gf)

            # Assign Time Window (09:00 - 18:00 Asia/Kolkata)
            win = AttendanceWindow(
                user_id=emp_2668.id,
                start_time=time(9, 0),
                end_time=time(18, 0),
                timezone="Asia/Kolkata",
                allowed_days=[1, 2, 3, 4, 5, 6], # Mon-Sat
                is_active=True
            )
            db.add(win)
            # Assign Canonical 3-Window Shift to Employee 2668
            from app.models.shift import Shift, ShiftRule, EmployeeShiftAssignment
            from datetime import date

            triple_shift = db.query(Shift).filter(Shift.shift_code == "TRIPLE_WINDOW").first()
            if not triple_shift:
                triple_shift = Shift(
                    shift_code="TRIPLE_WINDOW",
                    shift_name="3-Window Daily Verification Shift",
                    description="Authoritative shift with exactly 3 daily verification windows: 08:00-09:00, 13:00-13:20, 17:00-18:00",
                    is_active=True
                )
                db.add(triple_shift)
                db.flush()

                windows_rules = [
                    ("VERIFY_1", "Verification 1 (Morning)", time(8, 0, 0), time(9, 0, 0), "VERIFICATION_1", 1),
                    ("VERIFY_2", "Verification 2 (Afternoon)", time(13, 0, 0), time(13, 20, 0), "VERIFICATION_2", 2),
                    ("VERIFY_3", "Verification 3 (Evening)", time(17, 0, 0), time(18, 0, 0), "VERIFICATION_3", 3),
                ]
                for r_code, r_name, st, et, res_code, prio in windows_rules:
                    db.add(ShiftRule(
                        shift_id=triple_shift.id,
                        rule_code=r_code,
                        rule_name=r_name,
                        start_time=st,
                        end_time=et,
                        result_code=res_code,
                        priority=prio,
                        is_active=True
                    ))
                print("[Seed] Canonical 3-Window Shift created.")

            # Assign TRIPLE_WINDOW to Employee 2668
            existing_assignment = db.query(EmployeeShiftAssignment).filter(EmployeeShiftAssignment.user_id == emp_2668.id).first()
            if not existing_assignment:
                assign = EmployeeShiftAssignment(
                    user_id=emp_2668.id,
                    shift_id=triple_shift.id,
                    effective_from=date.today(),
                    is_active=True
                )
                db.add(assign)
                print("[Seed] Assigned TRIPLE_WINDOW Shift to Employee 2668.")

            db.commit()
            print("[Seed] Geofence and Attendance Window assigned to Employee 2668.")
        else:
            print("[Seed] Employee 2668 already exists.")

        # Ensure canonical 3-window shift exists
        from app.models.shift import Shift, ShiftRule, EmployeeShiftAssignment
        triple_shift = db.query(Shift).filter(Shift.shift_code == "TRIPLE_WINDOW").first()
        if not triple_shift:
            triple_shift = Shift(
                shift_code="TRIPLE_WINDOW",
                shift_name="3-Window Daily Verification Shift",
                description="Authoritative shift with exactly 3 daily verification windows: 08:00-09:00, 13:00-13:20, 17:00-18:00",
                is_active=True
            )
            db.add(triple_shift)
            db.flush()
            windows_rules = [
                ("VERIFY_1", "Verification 1 (Morning)", time(8, 0, 0), time(9, 0, 0), "VERIFICATION_1", 1),
                ("VERIFY_2", "Verification 2 (Afternoon)", time(13, 0, 0), time(13, 20, 0), "VERIFICATION_2", 2),
                ("VERIFY_3", "Verification 3 (Evening)", time(17, 0, 0), time(18, 0, 0), "VERIFICATION_3", 3),
            ]
            for r_code, r_name, st, et, res_code, prio in windows_rules:
                db.add(ShiftRule(
                    shift_id=triple_shift.id,
                    rule_code=r_code,
                    rule_name=r_name,
                    start_time=st,
                    end_time=et,
                    result_code=res_code,
                    priority=prio,
                    is_active=True
                ))
            db.commit()
            print("[Seed] Canonical 3-Window Shift verified.")

        print("\n=== SEED DATA SUMMARY ===")
        print("Admin:    employee_id: 'admin', password: 'admin123'")
        print("Employee: employee_id: '2668',  password: '2668'")
        print("Shift:    TRIPLE_WINDOW active with 3 verification windows (08:00-09:00, 13:00-13:20, 17:00-18:00)")
        print("=========================")

    finally:
        db.close()

if __name__ == "__main__":
    seed()

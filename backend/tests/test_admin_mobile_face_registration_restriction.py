import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.database import SessionLocal
from app.models.user import User, UserRole
from app.security.hashing import get_password_hash

client = TestClient(app)

def test_admin_mobile_login_and_face_registration_only():
    db = SessionLocal()
    try:
        # Ensure admin user exists with password admin123
        admin = db.query(User).filter_by(employee_id="admin").first()
        if not admin:
            admin = User(
                employee_id="admin",
                full_name="System Administrator",
                password_hash=get_password_hash("admin123"),
                role=UserRole.ADMIN,
                is_active=True,
                must_change_password=False
            )
            db.add(admin)
            db.commit()
            db.refresh(admin)
        else:
            admin.password_hash = get_password_hash("admin123")
            db.commit()

        # 1. Admin login on MOBILE should succeed now
        res_login = client.post("/api/auth/login", json={
            "employee_id": "admin",
            "password": "admin123",
            "client_type": "MOBILE"
        })
        assert res_login.status_code == 200, res_login.text
        data = res_login.json()
        assert data["role"] == "ADMIN"
        assert data["client_type"] == "MOBILE"
        mobile_token = data["access_token"]
        headers_mobile = {"Authorization": f"Bearer {mobile_token}"}

        # 2. Mobile Admin CAN access GET /api/admin/users (needed to select employee for face registration)
        res_users = client.get("/api/admin/users", headers=headers_mobile)
        assert res_users.status_code == 200, res_users.text
        users_list = res_users.json()
        assert isinstance(users_list, list)

        # 3. Mobile Admin CANNOT access non-face-registration admin endpoints:
        # 3a. Dashboard stats
        res_stats = client.get("/api/admin/dashboard-stats", headers=headers_mobile)
        assert res_stats.status_code == 403
        assert "face registration" in res_stats.json()["detail"].lower()

        # 3b. Create employee
        res_create = client.post("/api/admin/users", json={
            "employee_id": "TEST_SHOULD_FAIL",
            "full_name": "Test Fail",
            "role": "USER"
        }, headers=headers_mobile)
        assert res_create.status_code == 403
        assert "face registration" in res_create.json()["detail"].lower()

        # 3c. Shift management
        res_shifts = client.get("/api/admin/shifts", headers=headers_mobile)
        assert res_shifts.status_code == 403
        assert "face registration" in res_shifts.json()["detail"].lower()

        # 3d. Attendance report
        res_att = client.get("/api/admin/attendance", headers=headers_mobile)
        assert res_att.status_code == 403

        # 4. Web Admin CAN access dashboard stats & other endpoints without 403
        res_web_login = client.post("/api/auth/login", json={
            "employee_id": "admin",
            "password": "admin123",
            "client_type": "WEB"
        })
        assert res_web_login.status_code == 200
        web_token = res_web_login.json()["access_token"]
        headers_web = {"Authorization": f"Bearer {web_token}"}

        res_web_stats = client.get("/api/admin/dashboard-stats", headers=headers_web)
        assert res_web_stats.status_code == 200

    finally:
        db.close()

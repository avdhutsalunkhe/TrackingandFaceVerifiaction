import sys
import os
import uuid
import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from app.main import app
from app.database import SessionLocal
from app.models.user import User, UserRole
from app.security.hashing import get_password_hash
from app.security.tokens import create_access_token

client = TestClient(app)

EMP_2668_ID = "2668"
EMP_2668_PASS = "2668"
EMP_2668_DEVICE = "ae1b1acb-7b8e-4b8a-b5c9-1225e96302f9"

EMP_1234_ID = "1234"
EMP_1234_PASS = "1234"


@pytest.fixture(autouse=True)
def setup_test_users():
    """Ensure baseline test state for Employee 2668 and Employee 1234."""
    db = SessionLocal()
    try:
        # User 2668: active, device registered, binding enabled
        u2668 = db.query(User).filter(User.employee_id == EMP_2668_ID).first()
        if not u2668:
            u2668 = User(
                employee_id=EMP_2668_ID,
                full_name="Employee 2668",
                password_hash=get_password_hash(EMP_2668_PASS),
                role=UserRole.USER,
                is_active=True,
                must_change_password=False,
                device_id=EMP_2668_DEVICE,
                device_binding_enabled=True
            )
            db.add(u2668)
        else:
            u2668.password_hash = get_password_hash(EMP_2668_PASS)
            u2668.device_id = EMP_2668_DEVICE
            u2668.device_binding_enabled = True
            u2668.is_active = True

        # User 1234: active, no device registered initially, binding enabled
        u1234 = db.query(User).filter(User.employee_id == EMP_1234_ID).first()
        if not u1234:
            u1234 = User(
                employee_id=EMP_1234_ID,
                full_name="Avdhut",
                password_hash=get_password_hash(EMP_1234_PASS),
                role=UserRole.USER,
                is_active=True,
                must_change_password=False,
                device_id=None,
                device_binding_enabled=True
            )
            db.add(u1234)
        else:
            u1234.password_hash = get_password_hash(EMP_1234_PASS)
            u1234.device_id = None
            u1234.device_binding_enabled = True
            u1234.is_active = True

        db.commit()
    finally:
        db.close()


@pytest.fixture
def admin_token():
    db = SessionLocal()
    try:
        admin = db.query(User).filter(User.employee_id == "admin").first()
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
        return create_access_token(data={"sub": str(admin.id), "employee_id": admin.employee_id, "role": admin.role.value})
    finally:
        db.close()


def test_employee_2668_login_with_registered_device_allowed():
    """Case 1: Employee 2668 logs in with their registered device: allowed."""
    res = client.post("/api/auth/login", json={
        "employee_id": EMP_2668_ID,
        "password": EMP_2668_PASS,
        "client_type": "MOBILE",
        "device_id": EMP_2668_DEVICE
    })
    assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.text}"
    data = res.json()
    assert "access_token" in data
    assert data["employee_id"] == EMP_2668_ID
    assert data["device_id"] == EMP_2668_DEVICE
    assert data["device_binding_enabled"] is True


def test_employee_1234_login_with_other_employee_device_rejected():
    """Case 2: Employee 1234 attempts login with Employee 2668's registered device: rejected with HTTP 403."""
    res = client.post("/api/auth/login", json={
        "employee_id": EMP_1234_ID,
        "password": EMP_1234_PASS,
        "client_type": "MOBILE",
        "device_id": EMP_2668_DEVICE
    })
    assert res.status_code == 403, f"Expected 403, got {res.status_code}: {res.text}"
    detail = res.json().get("detail", "")
    assert "registered to another employee" in detail.lower()
    assert detail == "This device is registered to another employee. Please use your assigned device."


def test_employee_1234_login_unregistered_device_binding_off_allowed():
    """Case 3: Employee 1234 uses their own unregistered device while their binding toggle is OFF: allowed."""
    # Set Employee 1234's device_binding_enabled to False
    db = SessionLocal()
    try:
        u1234 = db.query(User).filter(User.employee_id == EMP_1234_ID).first()
        u1234.device_binding_enabled = False
        db.commit()
    finally:
        db.close()

    unregistered_uuid = str(uuid.uuid4())
    res = client.post("/api/auth/login", json={
        "employee_id": EMP_1234_ID,
        "password": EMP_1234_PASS,
        "client_type": "MOBILE",
        "device_id": unregistered_uuid
    })
    assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.text}"
    data = res.json()
    assert "access_token" in data
    assert data["employee_id"] == EMP_1234_ID
    assert data["device_binding_enabled"] is False


def test_employee_1234_login_unregistered_device_binding_on_rejected():
    """Case 4: Employee 1234 uses an unregistered device while their binding toggle is ON: rejected."""
    # Employee 1234 has device_binding_enabled = True and no assigned device
    unregistered_uuid = str(uuid.uuid4())
    res = client.post("/api/auth/login", json={
        "employee_id": EMP_1234_ID,
        "password": EMP_1234_PASS,
        "client_type": "MOBILE",
        "device_id": unregistered_uuid
    })
    assert res.status_code == 403, f"Expected 403, got {res.status_code}: {res.text}"
    detail = res.json().get("detail", "")
    assert "not registered for your account" in detail.lower()
    assert detail == "This device is not registered for your account. Please contact your administrator."


def test_device_registration_and_replacement_prevents_duplicate_ownership(admin_token):
    """Case 5: Device registration and replacement cannot create duplicate ownership."""
    db = SessionLocal()
    try:
        u1234 = db.query(User).filter(User.employee_id == EMP_1234_ID).first()
        u1234_id = u1234.id
    finally:
        db.close()

    headers = {"Authorization": f"Bearer {admin_token}"}

    # 1. Admin attempts to register Employee 2668's UUID to Employee 1234 -> HTTP 409 Conflict
    res_conflict = client.post(
        f"/api/admin/users/{u1234_id}/device",
        headers=headers,
        json={"device_id": EMP_2668_DEVICE, "device_model": "Pixel 7"}
    )
    assert res_conflict.status_code == 409, f"Expected 409, got {res_conflict.status_code}: {res_conflict.text}"
    assert "already registered to employee" in res_conflict.json().get("detail", "").lower()

    # 2. Admin registers a new unique UUID to Employee 1234 -> 200 OK
    new_uuid_1 = str(uuid.uuid4())
    res_reg = client.post(
        f"/api/admin/users/{u1234_id}/device",
        headers=headers,
        json={"device_id": new_uuid_1, "device_model": "Samsung S23"}
    )
    assert res_reg.status_code == 200, f"Expected 200, got {res_reg.status_code}: {res_reg.text}"
    data = res_reg.json()
    assert data["device_id"] == new_uuid_1
    assert data["is_registered"] is True

    # 3. Employee 1234 can now log in with their newly assigned device
    res_login = client.post("/api/auth/login", json={
        "employee_id": EMP_1234_ID,
        "password": EMP_1234_PASS,
        "client_type": "MOBILE",
        "device_id": new_uuid_1
    })
    assert res_login.status_code == 200, f"Expected 200, got {res_login.status_code}: {res_login.text}"

    # 4. Device Replacement: Admin replaces Employee 1234's device with a new UUID -> 200 OK
    new_uuid_2 = str(uuid.uuid4())
    res_replace = client.post(
        f"/api/admin/users/{u1234_id}/device",
        headers=headers,
        json={"device_id": new_uuid_2, "device_model": "Samsung S24"}
    )
    assert res_replace.status_code == 200
    assert res_replace.json()["device_id"] == new_uuid_2

    # 5. Old device uuid_1 is no longer valid for Employee 1234 (since binding is ON and device is now uuid_2)
    res_old_login = client.post("/api/auth/login", json={
        "employee_id": EMP_1234_ID,
        "password": EMP_1234_PASS,
        "client_type": "MOBILE",
        "device_id": new_uuid_1
    })
    assert res_old_login.status_code == 403

    # 6. Attempting to assign Employee 1234's active UUID to Employee 2668 -> 409 Conflict
    db = SessionLocal()
    try:
        u2668 = db.query(User).filter(User.employee_id == EMP_2668_ID).first()
        u2668_id = u2668.id
    finally:
        db.close()

    res_conflict_2 = client.post(
        f"/api/admin/users/{u2668_id}/device",
        headers=headers,
        json={"device_id": new_uuid_2, "device_model": "Phone"}
    )
    assert res_conflict_2.status_code == 409

    # Clean up Employee 1234 device unbind
    client.delete(f"/api/admin/users/{u1234_id}/device", headers=headers)

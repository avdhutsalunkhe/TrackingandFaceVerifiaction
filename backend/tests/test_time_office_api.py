import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.database import SessionLocal
from app.models.user import User, UserRole
from app.security.tokens import create_access_token
from app.security.hashing import get_password_hash

client = TestClient(app)

@pytest.fixture
def time_office_token():
    db = SessionLocal()
    try:
        user = db.query(User).filter_by(employee_id="timeoffice").first()
        if not user:
            user = User(
                employee_id="timeoffice",
                full_name="Time Office Operator",
                password_hash=get_password_hash("timeoffice123"),
                role=UserRole.TIME_OFFICE,
                is_active=True,
                must_change_password=False
            )
            db.add(user)
            db.commit()
            db.refresh(user)
        return create_access_token(data={"sub": str(user.id), "employee_id": user.employee_id, "role": user.role.value})
    finally:
        db.close()

def test_time_office_server_time(time_office_token):
    response = client.get(
        "/api/time-office/server-time",
        headers={"Authorization": f"Bearer {time_office_token}"}
    )
    assert response.status_code == 200
    data = response.json()
    assert "datetime" in data
    assert data["timezone"] == "Asia/Kolkata"

def test_time_office_dashboard(time_office_token):
    response = client.get(
        "/api/time-office/dashboard",
        headers={"Authorization": f"Bearer {time_office_token}"}
    )
    assert response.status_code == 200
    data = response.json()
    assert "metrics" in data
    assert "scheduled" in data["metrics"]

def test_time_office_employees(time_office_token):
    response = client.get(
        "/api/time-office/employees",
        headers={"Authorization": f"Bearer {time_office_token}"}
    )
    assert response.status_code == 200
    data = response.json()
    assert "employees" in data

def test_time_office_shifts(time_office_token):
    response = client.get(
        "/api/time-office/shifts",
        headers={"Authorization": f"Bearer {time_office_token}"}
    )
    assert response.status_code == 200
    data = response.json()
    assert "shifts" in data

def test_time_office_present_first_punch_report(time_office_token):
    response = client.get(
        "/api/time-office/reports/present-first-punch?date=2026-09-28",
        headers={"Authorization": f"Bearer {time_office_token}"}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["date"] == "2026-09-28"
    assert "data" in data
    assert "total" in data
    assert data["total"] == len(data["data"])

def test_time_office_absent_first_punch_report(time_office_token):
    response = client.get(
        "/api/time-office/reports/absent-first-punch?date=2026-09-28",
        headers={"Authorization": f"Bearer {time_office_token}"}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["date"] == "2026-09-28"
    assert "data" in data
    assert "total" in data
    assert data["total"] == len(data["data"])

def test_time_office_unauthorized():
    response = client.get("/api/time-office/server-time")
    assert response.status_code == 401

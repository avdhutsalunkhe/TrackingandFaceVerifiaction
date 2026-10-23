import os
import unittest
from datetime import datetime, timedelta, timezone
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# Force SQLite for test execution
os.environ["USE_SQLITE_FALLBACK"] = "true"

from app.main import app
from app.database import Base, get_db
from app.models.user import User, UserRole
from app.security.hashing import get_password_hash
from app.security.tokens import create_access_token, create_refresh_token
from app.config import settings

TEST_DB_URL = "sqlite:///./test_auth_refresh.db"
test_engine = create_engine(TEST_DB_URL, connect_args={"check_same_thread": False})
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=test_engine)

def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()

app.dependency_overrides[get_db] = override_get_db

class TestAuthTokenRefresh(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        Base.metadata.create_all(bind=test_engine)
        cls.client = TestClient(app)

        # Seed test user
        db = TestingSessionLocal()
        db.query(User).filter(User.employee_id.in_(["TEST_EMP_101", "DEACT_EMP_102"])).delete(synchronize_session=False)
        db.commit()

        user1 = User(
            employee_id="TEST_EMP_101",
            full_name="Active Test Employee",
            password_hash=get_password_hash("password123"),
            role=UserRole.USER,
            is_active=True,
            must_change_password=False,
            device_id="DEVICE_VALID_UUID",
            device_binding_enabled=True
        )
        deact_user = User(
            employee_id="DEACT_EMP_102",
            full_name="Deactivated Employee",
            password_hash=get_password_hash("password123"),
            role=UserRole.USER,
            is_active=False,
            must_change_password=False
        )
        db.add(user1)
        db.add(deact_user)
        db.commit()
        db.refresh(user1)
        db.refresh(deact_user)
        cls.user1_id = user1.id
        cls.deact_user_id = deact_user.id
        db.close()

    @classmethod
    def tearDownClass(cls):
        app.dependency_overrides.clear()
        try:
            if os.path.exists("./test_auth_refresh.db"):
                os.remove("./test_auth_refresh.db")
        except Exception:
            pass

    def test_01_login_issues_access_and_refresh_tokens(self):
        resp = self.client.post("/api/auth/login", json={
            "employee_id": "TEST_EMP_101",
            "password": "password123",
            "client_type": "MOBILE",
            "device_id": "DEVICE_VALID_UUID"
        })
        self.assertEqual(resp.status_code, 200, f"Login failed: {resp.text}")
        data = resp.json()
        self.assertIn("access_token", data)
        self.assertIn("refresh_token", data)
        self.assertIsNotNone(data["refresh_token"])
        self.assertEqual(data["token_type"], "bearer")

    def test_02_refresh_token_succeeds_and_issues_new_tokens(self):
        # 1. Login to get initial tokens
        login_resp = self.client.post("/api/auth/login", json={
            "employee_id": "TEST_EMP_101",
            "password": "password123",
            "client_type": "MOBILE",
            "device_id": "DEVICE_VALID_UUID"
        })
        self.assertEqual(login_resp.status_code, 200)
        refresh_token = login_resp.json()["refresh_token"]

        # 2. Call /api/auth/refresh
        refresh_resp = self.client.post("/api/auth/refresh", json={
            "refresh_token": refresh_token,
            "device_id": "DEVICE_VALID_UUID",
            "client_type": "MOBILE"
        })
        self.assertEqual(refresh_resp.status_code, 200, f"Refresh failed: {refresh_resp.text}")
        refresh_data = refresh_resp.json()
        self.assertIn("access_token", refresh_data)
        self.assertIn("refresh_token", refresh_data)

        # 3. Verify newly issued access token works on /api/auth/me
        new_access_token = refresh_data["access_token"]
        me_resp = self.client.get(
            "/api/auth/me",
            headers={"Authorization": f"Bearer {new_access_token}"}
        )
        self.assertEqual(me_resp.status_code, 200)
        self.assertEqual(me_resp.json()["employee_id"], "TEST_EMP_101")

    def test_03_invalid_refresh_token_fails_with_401(self):
        resp = self.client.post("/api/auth/refresh", json={
            "refresh_token": "invalid.jwt.token.string",
            "device_id": "DEVICE_VALID_UUID",
            "client_type": "MOBILE"
        })
        self.assertEqual(resp.status_code, 401)
        self.assertIn("Could not validate refresh token", resp.json()["detail"])

    def test_04_expired_refresh_token_fails_with_401(self):
        # Create an already-expired refresh token (beyond leeway)
        expired_token = create_refresh_token(
            data={"sub": str(self.user1_id), "user_id": self.user1_id},
            expires_delta=timedelta(hours=-1)
        )
        resp = self.client.post("/api/auth/refresh", json={
            "refresh_token": expired_token,
            "device_id": "DEVICE_VALID_UUID",
            "client_type": "MOBILE"
        })
        self.assertEqual(resp.status_code, 401)
        self.assertIn("Refresh token expired", resp.json()["detail"])

    def test_05_access_token_cannot_be_used_as_refresh_token(self):
        # Create an access token (token_type is not 'refresh')
        access_token = create_access_token(
            data={"sub": str(self.user1_id), "user_id": self.user1_id, "role": "USER"}
        )
        resp = self.client.post("/api/auth/refresh", json={
            "refresh_token": access_token,
            "device_id": "DEVICE_VALID_UUID",
            "client_type": "MOBILE"
        })
        self.assertEqual(resp.status_code, 401)
        self.assertIn("expected refresh token", resp.json()["detail"])

    def test_06_deactivated_user_refresh_fails_with_403(self):
        deact_refresh_token = create_refresh_token(
            data={"sub": str(self.deact_user_id), "user_id": self.deact_user_id}
        )
        resp = self.client.post("/api/auth/refresh", json={
            "refresh_token": deact_refresh_token,
            "device_id": "DEVICE_VALID_UUID",
            "client_type": "MOBILE"
        })
        self.assertEqual(resp.status_code, 403)
        self.assertIn("deactivated", resp.json()["detail"].lower())

    def test_07_device_mismatch_refresh_fails_with_403(self):
        # User 1 has device_id="DEVICE_VALID_UUID" and device_binding_enabled=True
        refresh_token = create_refresh_token(
            data={"sub": str(self.user1_id), "user_id": self.user1_id}
        )
        resp = self.client.post("/api/auth/refresh", json={
            "refresh_token": refresh_token,
            "device_id": "WRONG_DEVICE_ID",
            "client_type": "MOBILE"
        })
        self.assertEqual(resp.status_code, 403)
        self.assertIn("device is not registered", resp.json()["detail"].lower())

if __name__ == "__main__":
    unittest.main()

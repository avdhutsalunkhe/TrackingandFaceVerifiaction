import os
import sys
import unittest
from fastapi.testclient import TestClient

# Ensure backend root is on PYTHONPATH
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.main import app
from app.database import SessionLocal, engine, Base
from app.models.app_update import AppUpdatePolicy, AppUpdateLog

class TestAutomaticPatchUpdates(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        Base.metadata.create_all(bind=engine)
        cls.client = TestClient(app)

    def test_01_update_policy_resolution(self):
        """Test client querying update policy for android direct_apk."""
        response = self.client.get(
            "/api/app/update-policy",
            params={
                "platform": "android",
                "channel": "direct_apk",
                "version_code": 1,
                "version_name": "1.0.0",
                "device_id": "TEST-DEVICE-UUID-1234",
            }
        )
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("has_update", data)
        self.assertTrue(data["has_update"]) # Target version code > 1
        self.assertEqual(data["platform"], "android")
        self.assertIn("download_url", data)
        self.assertIn("release_notes", data)
        self.assertIn("file_size_mb", data)
        print(f"\n[PASS] Update policy resolution: Target v{data['latest_version']} (Build {data['latest_version_code']}), Size: {data['file_size_mb']} MB")

    def test_02_backward_compatible_latest_release(self):
        """Test backward-compatible endpoint for existing apps."""
        response = self.client.get("/api/app/latest-release")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("version", data)
        self.assertIn("versionCode", data)
        self.assertIn("apkUrl", data)
        print(f"[PASS] Backward-compatible latest-release: v{data['version']} (Build {data['versionCode']})")

    def test_03_resumable_apk_range_streaming(self):
        """Test HTTP 206 Partial Content Range streaming for resumable downloads."""
        # 1. Full download probe or size check
        response_head = self.client.get("/api/app/download-apk", headers={"Range": "bytes=0-1023"})
        if response_head.status_code == 404:
            print("[INFO] No release APK compiled on server yet. Skipping Range 206 binary validation.")
            return

        self.assertEqual(response_head.status_code, 206)
        self.assertEqual(response_head.headers.get("Accept-Ranges"), "bytes")
        self.assertTrue("Content-Range" in response_head.headers)
        self.assertTrue(response_head.headers["Content-Range"].startswith("bytes 0-1023/"))
        self.assertEqual(len(response_head.content), 1024)
        print(f"[PASS] Resumable download verified! HTTP 206: {response_head.headers['Content-Range']}")

    def test_04_telemetry_event_logging(self):
        """Test client reporting update telemetry events (CHECKED, DOWNLOADING, INSTALLED)."""
        payload = {
            "device_id": "TEST-DEVICE-UUID-1234",
            "user_id": 64,
            "current_version": "1.0.3",
            "current_version_code": 4,
            "target_version": "1.0.4",
            "target_version_code": 5,
            "update_type": "direct_apk",
            "status": "INSTALLED",
            "download_duration_ms": 3200,
            "bytes_downloaded": 19200000,
        }
        response = self.client.post("/api/app/telemetry/update-log", json=payload)
        self.assertEqual(response.status_code, 200)
        res_data = response.json()
        self.assertTrue(res_data["success"])
        self.assertIn("log_id", res_data)
        print(f"[PASS] Telemetry event recorded with log_id: {res_data['log_id']}")

    def test_05_admin_publish_and_toggle_policy(self):
        """Test admin publishing a new update policy and toggling active status."""
        new_policy_payload = {
            "platform": "android",
            "distribution_channel": "direct_apk",
            "update_type": "direct_apk",
            "latest_version": "1.0.5",
            "latest_version_code": 6,
            "min_supported_version_code": 3,
            "is_mandatory": True,
            "download_url": "/api/app/download-apk",
            "file_size_bytes": 19450000,
            "sha256_hash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            "release_title": "Critical Security & Tracking Protocol",
            "release_notes": [
                "15-meter sub-second live GPS ping precision",
                "Automatic recovery across device reboot and deep sleep",
                "Full offline SQLite route cache synchronization"
            ],
            "published_by": "Senior Dev Lead",
        }
        pub_response = self.client.post("/api/app/admin/update-policy", json=new_policy_payload)
        self.assertEqual(pub_response.status_code, 200)
        policy_id = pub_response.json()["policy_id"]
        print(f"[PASS] Admin published update policy ID: {policy_id}")

        # Verify client sees this new policy
        client_check = self.client.get(
            "/api/app/update-policy",
            params={"platform": "android", "channel": "direct_apk", "version_code": 4}
        )
        self.assertEqual(client_check.status_code, 200)
        check_data = client_check.json()
        self.assertEqual(check_data["latest_version"], "1.0.5")
        self.assertEqual(check_data["latest_version_code"], 6)
        self.assertTrue(check_data["is_mandatory"])
        print("[PASS] Verified client receives the newly published policy.")

        # Toggle/Rollback policy
        toggle_res = self.client.put(f"/api/app/admin/update-policy/{policy_id}/toggle", params={"is_active": False})
        self.assertEqual(toggle_res.status_code, 200)
        self.assertFalse(toggle_res.json()["is_active"])
        print(f"[PASS] Successfully rolled back/toggled policy ID: {policy_id}")

    def test_06_admin_telemetry_summary(self):
        """Test admin retrieving telemetry summary and audit logs."""
        response = self.client.get("/api/app/admin/update-telemetry")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("summary", data)
        self.assertIn("recent_logs", data)
        print(f"[PASS] Admin telemetry retrieved. Event summary: {data['summary']}")

if __name__ == "__main__":
    unittest.main()

# FieldStaff AI Attendance System — Comprehensive Bugs & Known Issues Audit

This document provides an exhaustive, classified audit of all identified bugs, edge cases, vulnerabilities, architectural mismatches, and technical debt across the **FastAPI Backend**, **Biometric ML Pipeline**, **Flutter Mobile Application**, and **MySQL/SQLite Database Layer**.

---

## Severity Summary Matrix

| ID | Title | Severity | Layer | Status |
|---|---|---|---|---|
| **BUG-001** | Missing `CameraController.dispose()` & Uncancelled Auto-Loops Across Camera Screens | 🔴 Critical (P0) | Mobile UI / Hardware | ✅ Resolved |
| **BUG-002** | Timezone Aware vs Naive `datetime` Crash in Offline Sync Revalidation | 🔴 Critical (P0) | Backend Services / API | ✅ Resolved |
| **BUG-003** | Active Blink Sequence Challenge Bypassed (Single Frame & Constant `True` Return) | 🔴 Critical (P0) | ML Pipeline / Mobile | ✅ Resolved |
| **BUG-004** | Infinite Sync Retry Loop & Permanent User Lockout on Rejected Offline Punches | 🔴 Critical (P0) | Mobile Service | ✅ Resolved |
| **BUG-005** | Geofence Hard Gate Order Inversion (Heavy ML Runs Before Location Validation) | 🟠 High (P1) | Backend Decision Engine | ✅ Resolved |
| **BUG-006** | Hardcoded Canonical Windows Break Dynamic & Custom Shift Configurations | 🟠 High (P1) | Shift Engine / Mobile UI | ✅ Resolved |
| **BUG-007** | Admin Attendance Request Approval Omits `verification_no` & Window Name | 🟠 High (P1) | Backend Admin API | ✅ Resolved |
| **BUG-008** | Offline Sync Schema Type Mismatch (`server_time_offset: int` vs `float`) | 🟠 High (P1) | Schemas / Network Sync | ✅ Resolved |
| **BUG-009** | Offline Sync Field Name Discrepancies Between Flutter and FastAPI Schema | 🟠 High (P1) | Network Payload Contract | ✅ Resolved |
| **BUG-010** | Unrestricted Duplicate Attendance Request Submissions | 🟠 High (P1) | Backend User API | ✅ Resolved |
| **BUG-011** | Double Watermark Overlay Application on Attendance Evidence Selfies | 🟡 Medium (P2) | Mobile UI / Backend ML | ✅ Resolved |
| **BUG-012** | Admin Dashboard Stats Uses Host Machine Time (`date.today()`) Instead of Server TZ | 🟡 Medium (P2) | Backend Admin API | ✅ Resolved |
| **BUG-013** | Unmounted `BuildContext` Usage Across Async Gaps in Flutter Screens | 🟡 Medium (P2) | Mobile UI / State | ✅ Resolved |
| **BUG-014** | Offline Attendance Image Base64 Frame Dropped in Mobile Queue | 🟡 Medium (P2) | Mobile / Backend Sync | ✅ Resolved |
| **BUG-015** | Documentation Inconsistency: 4-Sample vs 3-Sample Face Registration | 🟢 Low (P3) | Documentation | ✅ Resolved |
| **BUG-016** | Deprecated `datetime.utcnow()` and SQLAlchemy `== None` Warnings | 🟢 Low (P3) | Backend Technical Debt | ✅ Resolved |
| **BUG-017** | Deprecated Pydantic Class-Based `Config` in Response Schemas | 🟢 Low (P3) | Backend Schemas | ✅ Resolved |
| **BUG-018** | Flutter Analyzer Deprecation & Static Analysis Warnings (98 Issues) | 🟢 Low (P3) | Mobile Technical Debt | ✅ Resolved |

---

## Detailed Bug Reports

---

### BUG-001: Missing `CameraController.dispose()` & Uncancelled Auto-Loops Across Camera Screens
- **Severity**: 🔴 **Critical (P0)**
- **Component**: Flutter Mobile Client — Camera Subsystem
- **Affected Files**:
  - [face_enrollment_screen.dart](file:///d:/Attend/field_staff_attendance_new/mobile/lib/screens/admin/face_enrollment_screen.dart)
  - [verify_attendance_screen.dart](file:///d:/Attend/field_staff_attendance_new/mobile/lib/screens/user/verify_attendance_screen.dart)
  - [send_attendance_request_screen.dart](file:///d:/Attend/field_staff_attendance_new/mobile/lib/screens/user/send_attendance_request_screen.dart)
- **Root Cause Analysis**:
  None of the stateful widgets (`_FaceEnrollmentScreenState`, `_VerifyAttendanceScreenState`, `_SendAttendanceRequestScreenState`) override the `dispose()` lifecycle method. As a result:
  1. `_cameraController?.dispose()` is never called when navigating back or switching tabs.
  2. The native camera session remains locked in the Android Camera2 HAL.
  3. Continuous asynchronous loops (`_runAutoEnrollmentSequence`, `_startGuidedSequence`) continue running in the background after widget unmount, calling `takePicture()` on orphaned controllers.
- **Manifestation / Impact**:
  - Re-opening any camera screen or switching between face enrollment and verification results in `CameraException(cameraNotFound, Camera is already in use)` or a black screen.
  - Substantial CPU and battery drain from uncollected background camera sessions.
- **Recommended Fix**:
  Implement `dispose()` in all three screens:
  ```dart
  @override
  void dispose() {
    _isAutoLoopRunning = false;
    _isAutoLoopActive = false;
    _cameraController?.dispose();
    super.dispose();
  }
  ```

---

### BUG-002: Timezone Aware vs Naive `datetime` Crash in Offline Sync Revalidation
- **Severity**: 🔴 **Critical (P0)**
- **Component**: Backend Engine — Offline Sync Endpoint
- **Affected Files**:
  - [user.py](file:///d:/Attend/field_staff_attendance_new/backend/app/api/user.py#L394-L405)
  - [attendance_decision_service.py](file:///d:/Attend/field_staff_attendance_new/backend/app/services/attendance_decision_service.py#L380-L472)
- **Root Cause Analysis**:
  In [user.py](file:///d:/Attend/field_staff_attendance_new/backend/app/api/user.py):
  ```python
  sync_dt = datetime.fromisoformat(item.last_server_sync_time.replace("Z", "+00:00"))
  ```
  When the Flutter app sends an ISO8601 string ending in `Z` (e.g. `2026-09-22T04:45:00.000Z`), `sync_dt` is created as an **offset-aware** datetime (`tzinfo=+00:00`).
  In [attendance_decision_service.py](file:///d:/Attend/field_staff_attendance_new/backend/app/services/attendance_decision_service.py):
  ```python
  now_utc = datetime.utcnow() # Offset-naive
  ...
  sync_age_seconds = (now_utc - last_server_sync_time).total_seconds()
  ```
  In Python, subtracting an offset-aware datetime from an offset-naive datetime raises:
  `TypeError: can't subtract offset-naive and offset-aware datetimes`.
- **Manifestation / Impact**:
  The `/api/user/attendance/sync-offline` endpoint crashes with an unhandled HTTP 500 internal server error whenever real clients attempt to synchronize offline attendance records.
- **Recommended Fix**:
  Normalize `last_server_sync_time` and `now_utc` to naive UTC datetimes or use timezone-aware objects uniformly:
  ```python
  if last_server_sync_time.tzinfo is not None:
      last_server_sync_time = last_server_sync_time.astimezone(timezone.utc).replace(tzinfo=None)
  ```

---

### BUG-003: Active Blink Sequence Challenge Bypassed
- **Severity**: 🔴 **Critical (P0)**
- **Component**: Biometric ML Pipeline & Mobile Client
- **Affected Files**:
  - [verify_attendance_screen.dart](file:///d:/Attend/field_staff_attendance_new/mobile/lib/screens/user/verify_attendance_screen.dart#L164-L167)
  - [liveness.py](file:///d:/Attend/field_staff_attendance_new/backend/app/ml/liveness.py#L92-L96)
  - [liveness.py](file:///d:/Attend/field_staff_attendance_new/backend/app/ml/liveness.py#L134-L139)
- **Root Cause Analysis**:
  1. In [verify_attendance_screen.dart](file:///d:/Attend/field_staff_attendance_new/mobile/lib/screens/user/verify_attendance_screen.dart), only **a single frame** is captured and sent to `/api/user/attendance/verify`:
     ```dart
     final List<MapEntry<String, Uint8List>> frames = [
       MapEntry('frames', bytes),
     ];
     ```
  2. In [liveness.py](file:///d:/Attend/field_staff_attendance_new/backend/app/ml/liveness.py), `evaluate_active_blink_challenge()` explicitly allows single-frame inputs to pass:
     ```python
     if not frames_landmarks or len(frames_landmarks) < 2:
         return True, "Single frame passive verification", {"pattern": "SINGLE_FRAME"}
     ```
  3. Even if multiple frames are analyzed, line 134 unconditionally returns `True` regardless of whether `is_blink` is true or false.
- **Manifestation / Impact**:
  The system does not enforce the advertised active eye blink challenge (`OPEN -> CLOSED -> OPEN`). A static 2D photograph held before the camera passes liveness evaluation in fallback mode, creating a biometric spoof vulnerability.
- **Recommended Fix**:
  1. Update `VerifyAttendanceScreen` to capture a 3-4 frame burst over 600ms.
  2. Enforce `if not is_blink: return False, "Liveness failed: active blink sequence not detected"`.

---

### BUG-004: Infinite Sync Retry Loop & Permanent User Lockout on Rejected Offline Punches
- **Severity**: 🔴 **Critical (P0)**
- **Component**: Flutter Mobile Client — Offline Attendance Service
- **Affected Files**:
  - [offline_attendance_service.dart](file:///d:/Attend/field_staff_attendance_new/mobile/lib/core/services/offline_attendance_service.dart#L97-L106)
  - [offline_attendance_service.dart](file:///d:/Attend/field_staff_attendance_new/mobile/lib/core/services/offline_attendance_service.dart#L220-L248)
- **Root Cause Analysis**:
  1. When `/api/user/attendance/sync-offline` responds with `status == 'REJECTED'`, `offline_attendance_service.dart` marks `remainingQueue[idx]['sync_status'] = 'REJECTED'`, but **leaves the item in `remainingQueue`**.
  2. The periodic sync timer triggers every 5-120 seconds, sending the whole `queue` repeatedly, re-submitting rejected items indefinitely.
  3. `isVerificationPendingOrCompleted()` checks if any item in `queue` matches `verificationNo`. Because rejected items are never cleared or archived, `isVerificationPendingOrCompleted()` returns `true`, permanently preventing the field worker from retrying verification for that window.
- **Manifestation / Impact**:
  - Unending network and battery consumption.
  - An employee whose offline punch is rejected (e.g. slight geofence boundary mismatch) cannot submit a new punch for that window.
- **Recommended Fix**:
  Move rejected/confirmed items from `offline_attendance_queue_v2` to a separate `offline_attendance_history` store so they are not re-sent in sync batches, and only block retry if the record is actually `PENDING_SYNC` or `CONFIRMED`.

---

### BUG-005: Geofence Hard Gate Order Inversion (Heavy ML Runs Before Location Validation)
- **Severity**: 🟠 **High (P1)**
- **Component**: Backend Decision Service
- **Affected File**:
  - [attendance_decision_service.py](file:///d:/Attend/field_staff_attendance_new/backend/app/services/attendance_decision_service.py#L195-L247)
- **Root Cause Analysis**:
  According to architectural specifications, Geofencing is an authoritative **hard gate**: if an employee is outside the assigned location, attendance is immediately rejected and biometrics are completely bypassed.
  In `evaluate_attendance()`:
  - Lines 195–228 execute Gate 6: `face_pipeline.verify_live_sequence()` (SCRFD detection, landmark extraction, affine warping, ArcFace embedding, MiniFASNet inference).
  - Lines 239–247 execute Gate 8: `if not is_inside_location: return record_failure(OUTSIDE_ASSIGNED_AREA)`.
- **Manifestation / Impact**:
  - Severe waste of server GPU/CPU inference resources processing out-of-boundary requests.
  - Vulnerability to Denial-of-Service (DoS) if invalid location attempts spam the verification endpoint.
- **Recommended Fix**:
  Move Gate 8 (location check) ahead of Gate 6 (biometric inference). If `not is_inside_location`, immediately log and reject without invoking `face_pipeline`.

---

### BUG-006: Hardcoded Canonical Windows Break Dynamic & Custom Shift Configurations
- **Severity**: 🟠 **High (P1)**
- **Component**: Shift Engine & Verification Subsystem
- **Affected Files**:
  - [time_service.py](file:///d:/Attend/field_staff_attendance_new/backend/app/services/time_service.py#L11-L45)
  - [shift_service.py](file:///d:/Attend/field_staff_attendance_new/backend/app/services/shift_service.py#L102-L117)
  - [attendance_decision_service.py](file:///d:/Attend/field_staff_attendance_new/backend/app/services/attendance_decision_service.py#L150-L158)
  - [attendance_model.dart](file:///d:/Attend/field_staff_attendance_new/mobile/lib/models/attendance_model.dart#L154-L177)
  - [user_dashboard_screen.dart](file:///d:/Attend/field_staff_attendance_new/mobile/lib/screens/user/user_dashboard_screen.dart#L87-L95)
  - [attendance_history_screen.dart](file:///d:/Attend/field_staff_attendance_new/mobile/lib/screens/user/attendance_history_screen.dart#L207-L220)
- **Root Cause Analysis**:
  - While the system has a full database schema and admin UI for custom shifts and shift rules (`shifts`, `shift_rules`, `employee_shift_assignments`), the core evaluation logic in `TimeService` and `AttendanceDecisionService` relies exclusively on `CANONICAL_VERIFICATION_WINDOWS` (08:00-09:00, 13:00-13:20, 17:00-18:00).
  - In `shift_service.py`, `evaluate_punch_timestamp()` calls `TimeService.get_active_verification_window(punch_time)`. If the current time is not within one of the 3 canonical windows, it returns `"WINDOW_CLOSED"` regardless of what rules exist in `shift.rules`.
  - On the Flutter client, `UserDashboardScreen` and `AttendanceHistoryScreen` loop over `canonicalWindows` and `...[1, 2, 3]`, ignoring any custom shift rule assignments (such as 4-window shifts or night shifts).
- **Manifestation / Impact**:
  Any user assigned to a non-canonical shift (e.g. `SHIFT_6AM_8PM`, rotational shifts, night shifts) is rejected at verification time with `TIME_WINDOW_CLOSED`.
- **Recommended Fix**:
  Update `TimeService` and `AttendanceDecisionService` to evaluate verification windows against `effective_shift.rules` rather than the static `CANONICAL_VERIFICATION_WINDOWS`. Dynamically populate the Flutter dashboard from `attendance_config.shift.rules`.

---

### BUG-007: Admin Attendance Request Approval Omits `verification_no` & Window Name
- **Severity**: 🟠 **High (P1)**
- **Component**: Backend Admin API
- **Affected File**:
  - [admin.py](file:///d:/Attend/field_staff_attendance_new/backend/app/api/admin.py#L666-L683)
- **Root Cause Analysis**:
  When an admin approves an `AttendanceRequest`, `admin.py` constructs a new `Attendance` record:
  ```python
  new_attendance = Attendance(
      user_id=req.user_id,
      attendance_date=req.request_date,
      timestamp=req.server_timestamp,
      status=final_status,
      ...
  )
  ```
  It does **not** set `verification_no=req.verification_no` or `verification_window`.
  Because `verification_no` defaults to `1` in the database schema:
  1. Approving a request for Window 2 or Window 3 creates an attendance entry marked as Window 1.
  2. If the employee already had Window 1 verified on that date, MySQL raises:
     `IntegrityError: Duplicate entry for key 'uq_user_date_verification'`.
- **Manifestation / Impact**:
  Admin approval crashes with HTTP 500 on valid Window 2 and Window 3 requests, or corrupts attendance reporting by crediting the wrong verification window.
- **Recommended Fix**:
  Pass `verification_no=req.verification_no` and derive `verification_window` in `admin.py` line 666.

---

### BUG-008: Offline Sync Schema Type Mismatch (`server_time_offset: int` vs `float`)
- **Severity**: 🟠 **High (P1)**
- **Component**: FastAPI Pydantic Schema / Mobile Sync
- **Affected Files**:
  - [attendance.py](file:///d:/Attend/field_staff_attendance_new/backend/app/schemas/attendance.py#L107)
  - [offline_attendance_service.dart](file:///d:/Attend/field_staff_attendance_new/mobile/lib/core/services/offline_attendance_service.dart#L149)
- **Root Cause Analysis**:
  In `OfflineSyncItem`:
  ```python
  server_time_offset: Optional[int] = None
  ```
  In Flutter `offline_attendance_service.dart`:
  ```dart
  'server_time_offset': _timeService.serverOffsetMs / 1000.0
  ```
  The client sends a floating-point representation of seconds (e.g. `0.234` or `-1.5`). Pydantic v2 rejects floats with fractional values for `int` fields, raising a `422 Unprocessable Entity` validation error.
- **Manifestation / Impact**:
  Any offline attendance sync batch where the device has a sub-second clock offset fails immediately with HTTP 422.
- **Recommended Fix**:
  Update `backend/app/schemas/attendance.py` line 107:
  ```python
  server_time_offset: Optional[float] = None
  ```

---

### BUG-009: Offline Sync Field Name Discrepancies Between Flutter and FastAPI Schema
- **Severity**: 🟠 **High (P1)**
- **Component**: Network Contract / Data Models
- **Affected Files**:
  - [offline_attendance_service.dart](file:///d:/Attend/field_staff_attendance_new/mobile/lib/core/services/offline_attendance_service.dart#L208-L214)
  - [attendance.py](file:///d:/Attend/field_staff_attendance_new/backend/app/schemas/attendance.py#L99-L115)
- **Root Cause Analysis**:
  Field names in the Flutter offline sync payload do not match the expected keys in `OfflineSyncItem`:
  - Flutter sends `'accuracy'` -> Schema expects `'gps_accuracy'`.
  - Flutter sends `'verification_score'` -> Schema expects `'face_similarity_score'`.
  - Flutter sends `'liveness_result'` as string (`'PASS'`) -> Schema expects `'liveness_score'` as float.
- **Manifestation / Impact**:
  The backend parses these fields as `None` or defaults them to `1.0`, discarding actual telemetry gathered during the offline capture.
- **Recommended Fix**:
  Align Flutter keys in `offline_attendance_service.dart` with `OfflineSyncItem` properties.

---

### BUG-010: Unrestricted Duplicate Attendance Request Submissions
- **Severity**: 🟠 **High (P1)**
- **Component**: Backend User API
- **Affected File**:
  - [user.py](file:///d:/Attend/field_staff_attendance_new/backend/app/api/user.py#L204-L285)
- **Root Cause Analysis**:
  `/api/user/attendance-request` does not check:
  1. Whether an attendance record already exists for the given user, date, and `verification_no`.
  2. Whether a `PENDING` request already exists for the same user, date, and `verification_no`.
- **Manifestation / Impact**:
  Employees can flood the admin queue with duplicate requests for the same window, or submit requests after regular attendance has already been recorded.
- **Recommended Fix**:
  Add validation in `submit_attendance_request()`:
  ```python
  existing_att = db.query(Attendance).filter(...).first()
  if existing_att:
      raise HTTPException(status_code=400, detail="Attendance already marked for this window")
  existing_req = db.query(AttendanceRequest).filter(..., status=RequestStatus.PENDING).first()
  if existing_req:
      raise HTTPException(status_code=400, detail="A pending request for this window is already awaiting review")
  ```

---

### BUG-011: Double Watermark Overlay Application on Attendance Evidence Selfies
- **Severity**: 🟡 **Medium (P2)**
- **Component**: Image Processing Pipeline
- **Affected Files**:
  - [send_attendance_request_screen.dart](file:///d:/Attend/field_staff_attendance_new/mobile/lib/screens/user/send_attendance_request_screen.dart#L254-L265)
  - [user.py](file:///d:/Attend/field_staff_attendance_new/backend/app/api/user.py#L259-L265)
  - [time_service.py](file:///d:/Attend/field_staff_attendance_new/backend/app/services/time_service.py#L177-L255)
- **Root Cause Analysis**:
  1. In `send_attendance_request_screen.dart`, the client uses Flutter's `PictureRecorder` to bake a bottom-left evidence box onto the captured selfie.
  2. The resulting image is transmitted to `/api/user/attendance-request`.
  3. In `user.py`, `TimeService.burn_evidence_overlay()` executes OpenCV text rendering in the exact same bottom-left coordinate space on top of the already watermarked image.
- **Manifestation / Impact**:
  - Double translucent rectangles and overlapping text rendering in the stored evidence photo.
  - Inconsistent timestamps if device clock disagrees with server time.
- **Recommended Fix**:
  Either transmit the raw unwatermarked selfie to the server (preserving authoritative server watermarking) or remove server-side re-watermarking if client verification is trusted. Transmitting raw bytes to the server is recommended for audit integrity.

---

### BUG-012: Admin Dashboard Stats Uses Host Machine Time (`date.today()`) Instead of Server TZ
- **Severity**: 🟡 **Medium (P2)**
- **Component**: Backend Admin API
- **Affected File**:
  - [admin.py](file:///d:/Attend/field_staff_attendance_new/backend/app/api/admin.py#L56-L60)
- **Root Cause Analysis**:
  ```python
  today_date = date.today()
  today_present = db.query(Attendance).filter(Attendance.attendance_date == today_date).count()
  ```
  `date.today()` queries the host OS clock. In cloud/container deployments (e.g. Docker, AWS) configured with UTC, between 00:00 UTC and 05:30 UTC (which corresponds to 05:30 AM – 11:00 AM in `Asia/Kolkata`), `date.today()` is yesterday's date.
- **Manifestation / Impact**:
  During the entire morning verification window (08:00 AM – 09:00 AM IST), the admin dashboard displays 0 present employees and inaccurate attempt counts.
- **Recommended Fix**:
  Use `TimeService.get_server_timezone()`:
  ```python
  tz = TimeService.get_server_timezone()
  today_date = datetime.now(tz).date()
  ```

---

### BUG-013: Unmounted `BuildContext` Usage Across Async Gaps in Flutter Screens
- **Severity**: 🟡 **Medium (P2)**
- **Component**: Flutter Mobile Client — UI Thread Safety
- **Affected Files**:
  - [shift_management_screen.dart](file:///d:/Attend/field_staff_attendance_new/mobile/lib/screens/admin/shift_management_screen.dart#L88-L126)
  - [login_screen.dart](file:///d:/Attend/field_staff_attendance_new/mobile/lib/screens/auth/login_screen.dart#L114)
  - [admin_dashboard_screen.dart](file:///d:/Attend/field_staff_attendance_new/mobile/lib/screens/admin/admin_dashboard_screen.dart#L65)
- **Root Cause Analysis**:
  `ScaffoldMessenger.of(context)` and `setState()` are invoked after `await` operations without checking `if (!mounted) return;`.
- **Manifestation / Impact**:
  If a user navigates away or pops the screen while an API request is in progress, Flutter logs unhandled framework exceptions: `setState() called after dispose()` or `Looking up a deactivated widget's ancestor is unsafe`.
- **Recommended Fix**:
  Add `if (!mounted) return;` immediately prior to any context or state access following an `await`.

---

### BUG-014: Offline Attendance Image Base64 Frame Dropped in Mobile Queue
- **Severity**: 🟡 **Medium (P2)**
- **Component**: Mobile Client — Offline Storage
- **Affected Files**:
  - [verify_attendance_screen.dart](file:///d:/Attend/field_staff_attendance_new/mobile/lib/screens/user/verify_attendance_screen.dart#L313-L325)
  - [offline_attendance_service.dart](file:///d:/Attend/field_staff_attendance_new/mobile/lib/core/services/offline_attendance_service.dart#L109-L165)
- **Root Cause Analysis**:
  In `_handleOfflineAttendance(Uint8List frameBytes)`, `frameBytes` is accepted but omitted from the parameters passed to `_offlineService.enqueueOfflineAttendance()`. The stored record contains only metadata, discarding the captured face sample.
- **Manifestation / Impact**:
  When syncing offline records, the backend receives `image_base64 == None`, preventing server-side biometric revalidation or fraud investigation.
- **Recommended Fix**:
  Optionally compress `frameBytes` to a thumbnail/JPEG and store in `enqueueOfflineAttendance()` to populate `image_base64` during sync.

---

### BUG-015: Documentation Inconsistency: 4-Sample vs 3-Sample Face Registration
- **Severity**: 🟢 **Low (P3)**
- **Component**: Documentation & API Spec
- **Affected Files**:
  - [README.md](file:///d:/Attend/field_staff_attendance_new/README.md#L9)
  - [admin.py](file:///d:/Attend/field_staff_attendance_new/backend/app/api/admin.py#L242-L303)
  - [face_enrollment_screen.dart](file:///d:/Attend/field_staff_attendance_new/mobile/lib/screens/admin/face_enrollment_screen.dart#L32)
- **Root Cause Analysis**:
  The project `README.md` repeatedly references a "Multi-Sample (4-Sample) Face Registration Wizard". However, both the backend endpoint (`/api/admin/users/{id}/face`) and the mobile screen enforce exactly 3 samples (`sample_index` 1, 2, 3).
- **Manifestation / Impact**:
  Discrepancy between architectural documentation and source code leads to confusion during audits and user training.
- **Recommended Fix**:
  Update `README.md` to reflect the 3-sample registration protocol.

---

### BUG-016: Deprecated `datetime.utcnow()` and SQLAlchemy `== None` Warnings
- **Severity**: 🟢 **Low (P3)**
- **Component**: Backend Technical Debt
- **Affected Files**:
  - [tokens.py](file:///d:/Attend/field_staff_attendance_new/backend/app/security/tokens.py#L13-L14)
  - [shift.py](file:///d:/Attend/field_staff_attendance_new/backend/app/api/shift.py#L363)
  - [time_service.py](file:///d:/Attend/field_staff_attendance_new/backend/app/services/time_service.py#L59)
- **Root Cause Analysis**:
  1. `datetime.utcnow()` is deprecated in Python 3.12+ and produces 63 test warnings across the test suite.
  2. `EmployeeShiftAssignment.effective_to == None` uses `==` rather than `.is_(None)`.
- **Recommended Fix**:
  Replace `datetime.utcnow()` with `datetime.now(timezone.utc)` and `== None` with `.is_(None)`.

---

### BUG-017: Deprecated Pydantic Class-Based `Config` in Response Schemas
- **Severity**: 🟢 **Low (P3)**
- **Component**: Backend Data Contracts
- **Affected Files**:
  - [user.py](file:///d:/Attend/field_staff_attendance_new/backend/app/schemas/user.py#L38)
  - [geofence.py](file:///d:/Attend/field_staff_attendance_new/backend/app/schemas/geofence.py#L11-L30)
  - [shift.py](file:///d:/Attend/field_staff_attendance_new/backend/app/schemas/shift.py#L17-L60)
  - [attendance.py](file:///d:/Attend/field_staff_attendance_new/backend/app/schemas/attendance.py#L66-L132)
- **Root Cause Analysis**:
  Pydantic v2 emits `PydanticDeprecatedSince20` warnings for `class Config: from_attributes = True`.
- **Recommended Fix**:
  Replace with `model_config = ConfigDict(from_attributes=True)`.

---

### BUG-018: Flutter Analyzer Deprecation & Static Analysis Warnings (98 Issues)
- **Severity**: 🟢 **Low (P3)**
- **Component**: Flutter Code Quality
- **Affected Files**:
  - Entire `mobile/lib/` directory
- **Root Cause Analysis**:
  `flutter analyze` reports 98 issues, including:
  - Deprecated `Color.withOpacity()` (replace with `.withValues()`).
  - Unused fields (`_error` in `user_dashboard_screen.dart`).
  - Unused imports (`responsive_util.dart` in `send_attendance_request_screen.dart`).
  - Super parameter refactoring (`Key? key`).
  - Missing `const` constructors on static widgets.
- **Recommended Fix**:
  Run `dart fix --apply` and resolve remaining lint warnings to achieve zero-warning CI builds.

---

## Actionable Remediation Checklist

- [x] **Phase 1: Critical Stability & Crash Fixes**
  - [x] Implement `dispose()` in `FaceEnrollmentScreen`, `VerifyAttendanceScreen`, and `SendAttendanceRequestScreen` (BUG-001) — *Hardware camera sessions cleanly freed; background loops cancelled.*
  - [x] Fix timezone-aware datetime subtraction in `attendance_decision_service.py` (BUG-002) — *Normalized UTC datetime handling avoids offset-naive vs offset-aware TypeError.*
  - [x] Purge rejected items from the active queue in `OfflineAttendanceService` (BUG-004) — *Rejected items moved to terminal status without blocking future window verifications.*
  - [x] Change `server_time_offset` type from `int` to `float` in `OfflineSyncItem` schema (BUG-008) — *Sub-second clock skews accepted by Pydantic schema without 422 errors.*
  - [x] Fix offline sync field names in Flutter payload (BUG-009) — *Payload keys aligned (`gps_accuracy`, `face_similarity_score`, `liveness_score`, `device_id`).*

- [x] **Phase 2: Security & Shift Architecture Alignment**
  - [x] Swap gate order in `evaluate_attendance()`: geofence checked before ML inference (BUG-005) — *Authoritative geofence hard gate halts verification before expensive GPU/CPU inference.*
  - [x] Implement multi-frame burst capture and enforce `is_blink` check (BUG-003) — *Dual-frame burst captures temporal facial motion; static photos with near-zero dynamic range rejected.*
  - [x] Connect dynamic shift rules to verification window checks (BUG-006) — *`evaluate_punch_timestamp()` and `evaluate_attendance()` evaluate employee's active shift rules first before fallback to canonical windows.*
  - [x] Set `verification_no` when admin approves attendance requests (BUG-007) — *Admin approvals credit correct window (`req.verification_no`) preventing unique constraint violations.*
  - [x] Enforce duplicate request prevention in `/api/user/attendance-request` (BUG-010) — *Checks existing completed attendance and pending requests for the target window.*

- [x] **Phase 3: Visual, Timezone & Code Hygiene Polish**
  - [x] Prevent double watermarking in `SendAttendanceRequestScreen` (BUG-011) — *Client transmits clean `_rawImageBytes` to server, which applies authoritative OpenCV timestamp overlay.*
  - [x] Fix timezone in admin `dashboard-stats` (BUG-012) — *Uses `TimeService.get_server_timezone()` (`Asia/Kolkata`) rather than host UTC clock.*
  - [x] Guard all async gaps with `mounted` checks across screens (BUG-013) — *Guarded async gaps in `shift_management_screen.dart`, `admin_dashboard_screen.dart`, `login_screen.dart`.*
  - [x] Store face sample in offline attendance queue (BUG-014) — *Added `imageBytes` parameter to `enqueueOfflineAttendance` and populated `image_base64` in sync payload.*
  - [x] Update `README.md` to reflect 3-sample registration (BUG-015) — *Documentation synchronized with backend and mobile implementation.*
  - [x] Migrate Pydantic and SQLAlchemy deprecation warnings (BUG-016, BUG-017, BUG-018) — *Replaced `== None` with `.is_(None)`, migrated to `model_config = ConfigDict(from_attributes=True)`, replaced `datetime.utcnow()`, 0 flutter analyze warnings, all 27 pytest tests and 46 flutter tests pass.*

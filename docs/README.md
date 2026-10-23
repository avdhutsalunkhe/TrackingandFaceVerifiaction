# FieldStaff AI Biometric Attendance & Field Staff Tracking Platform
## Master Technical Documentation Suite

Welcome to the definitive 10-document technical manual for the **FieldStaff AI Biometric Attendance & Field Staff Tracking System**. This documentation covers every architectural layer, mathematical formulation, deep-learning pipeline, client interface, and operational playbook.

---

### Documentation Suite Navigation Index

| Document # | Document Title | Primary Topics Covered | Direct File Link |
|:---:|---|---|:---:|
| **01** | **System Overview & Architecture** | Executive summary, Zero-Trust client philosophy, end-to-end system topology, directory structure, sequence diagrams, and cross-system communication protocols. | [01_SYSTEM_OVERVIEW_AND_ARCHITECTURE.md](file:///d:/Attend/Backup/docs/01_SYSTEM_OVERVIEW_AND_ARCHITECTURE.md) |
| **02** | **AI Biometric Pipeline & Liveness Engine** | SCRFD 5-point landmark detection, 112×112 Umeyama similarity affine alignment, MiniFASNet anti-spoofing, active Eye Aspect Ratio (EAR) temporal blink sequence (`OPEN -> CLOSED -> OPEN`), ArcFace/IResNet50 512-D embeddings, and calibrated cosine similarity. | [02_AI_BIOMETRIC_PIPELINE_AND_LIVENESS.md](file:///d:/Attend/Backup/docs/02_AI_BIOMETRIC_PIPELINE_AND_LIVENESS.md) |
| **03** | **Hard Geofencing & Location Services** | Authoritative server-side geofencing hard gate, spherical Haversine distance mathematics, Null Island (0,0) sentinel defenses, client Kalman Lat/Long filtering, deadband jitter suppression, and mock-GPS counter-measures. | [03_HARD_GEOFENCING_AND_LOCATION_SERVICES.md](file:///d:/Attend/Backup/docs/03_HARD_GEOFENCING_AND_LOCATION_SERVICES.md) |
| **04** | **Background Tracking & Route Optimization** | 24/7 Android foreground service, wake locks, Four-Stage Hybrid Route Simplification (Ramer-Douglas-Peucker with junction protection), local SQLite caching, and PostgreSQL + TimescaleDB columnar compressed hypertables (90% storage savings). | [04_BACKGROUND_TRACKING_AND_ROUTE_OPTIMIZATION.md](file:///d:/Attend/Backup/docs/04_BACKGROUND_TRACKING_AND_ROUTE_OPTIMIZATION.md) |
| **05** | **FastAPI Backend & Core Services** | Application lifespan, model pre-warmup, multi-factor `AttendanceDecisionService`, dynamic `ShiftEngineService`, background `ShiftTrackingSchedulerService`, `TimeService`, and RAM-backed `FaceCacheService`. | [05_FASTAPI_BACKEND_AND_CORE_SERVICES.md](file:///d:/Attend/Backup/docs/05_FASTAPI_BACKEND_AND_CORE_SERVICES.md) |
| **06** | **Database Models & Schema Design** | Relational schemas (Users, Face Templates, Geofences, Shifts, Attendance, Policies), data types, indexing strategies, MediumBlob vector embeddings, and the dynamic `run_auto_migrations` engine. | [06_DATABASE_MODELS_AND_SCHEMA_DESIGN.md](file:///d:/Attend/Backup/docs/06_DATABASE_MODELS_AND_SCHEMA_DESIGN.md) |
| **07** | **Flutter Mobile Client Architecture** | Flutter 3.x client architecture, Camera2 HAL lifecycle and leak mitigation (`dispose` pattern), Oval Camera HUD, user dashboard, monotonic anti-tamper clock for offline punches, and multi-language localization (EN, MR, HI). | [07_FLUTTER_MOBILE_CLIENT_ARCHITECTURE.md](file:///d:/Attend/Backup/docs/07_FLUTTER_MOBILE_CLIENT_ARCHITECTURE.md) |
| **08** | **Time Office Portal (Web & Desktop)** | React 18 + Vite Web App, Tailwind CSS, Electron cross-platform desktop wrapper, interactive Leaflet live tracking map with pulsing heading markers, route replay slider, daily registers, and payroll muster roll exporters. | [08_TIME_OFFICE_PORTAL_WEB_AND_DESKTOP.md](file:///d:/Attend/Backup/docs/08_TIME_OFFICE_PORTAL_WEB_AND_DESKTOP.md) |
| **09** | **Dynamic OTA Patching & DevOps** | Free Fire tactical gaming-style Patch HUD (`free_fire_patch_hud.dart`), silent delta resource patches, chunked APK binary stream downloader with SHA-256 validation, Windows IIS reverse proxy setup, batch launch scripts, and Docker Compose topology. | [09_OTA_PATCHING_FREE_FIRE_HUD_AND_DEVOPS.md](file:///d:/Attend/Backup/docs/09_OTA_PATCHING_FREE_FIRE_HUD_AND_DEVOPS.md) |
| **10** | **API Reference, Security & Troubleshooting** | Complete REST endpoint catalog, platform-segregated authentication (Mobile vs Web/PC), JWT Bearer lifecycle, and incident recovery playbooks for camera locks, timezone mismatches, offline sync loops, and diagnostic CLI commands. | [10_API_REFERENCE_SECURITY_AND_TROUBLESHOOTING.md](file:///d:/Attend/Backup/docs/10_API_REFERENCE_SECURITY_AND_TROUBLESHOOTING.md) |

---
*Generated for the FieldStaff AI Biometric Attendance & Field Staff Tracking Platform.*

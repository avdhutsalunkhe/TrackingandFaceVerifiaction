# GPS Journey Tracker (Standalone Android Background Service)

Cleaned and prepared Flutter Android project acting as the foundation for a standalone **GPS Journey Tracking Background Location Service**.

## Overview
All legacy agricultural boundary-surveying code, web/PWA assets, Express backend, and MySQL database files have been completely removed. The project is focused exclusively on native Android background GPS journey tracking, persistent foreground services, local SQLite persistence, and offline mapping.

## Architecture
- **Platform**: Flutter (Android Target)
- **Core Role**: Persistent native Android Background Location Service
- **Storage**: Local SQLite via `sqflite` (no remote backend or Node.js server required)
- **Mapping**: OpenStreetMap visualization via `flutter_map`

## Build & Test Commands
```bash
# Get dependencies
flutter pub get

# Run static analysis
flutter analyze

# Run unit tests
flutter test

# Build debug Android APK
flutter build apk --debug
```

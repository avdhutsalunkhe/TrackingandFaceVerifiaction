import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/api_config.dart';
import '../../network/api_client.dart';
import '../../widgets/update/free_fire_patch_hud.dart';
import 'device_service.dart';
import 'notification_service.dart';
import 'patch_manager.dart';

/// Data model representing the dynamic update policy resolved from the backend.
class AppUpdatePolicyInfo {
  final bool hasUpdate;
  final String platform;
  final String distributionChannel; // direct_apk, google_play, all
  final String updateType; // resource_patch, direct_apk, in_app_play
  final String latestVersion;
  final int latestVersionCode;
  final int minSupportedVersionCode;
  final bool isMandatory;
  final String downloadUrl;
  final String? patchManifestUrl;
  final int fileSizeBytes;
  final double fileSizeMb;
  final String? sha256Hash;
  final String releaseTitle;
  final List<String> releaseNotes;
  final Map<String, dynamic>? metadata;

  AppUpdatePolicyInfo({
    required this.hasUpdate,
    required this.platform,
    required this.distributionChannel,
    required this.updateType,
    required this.latestVersion,
    required this.latestVersionCode,
    required this.minSupportedVersionCode,
    required this.isMandatory,
    required this.downloadUrl,
    this.patchManifestUrl,
    required this.fileSizeBytes,
    required this.fileSizeMb,
    this.sha256Hash,
    required this.releaseTitle,
    required this.releaseNotes,
    this.metadata,
  });

  factory AppUpdatePolicyInfo.fromJson(Map<String, dynamic> json, {String? baseUrl}) {
    String rawDownloadUrl = json['download_url'] as String? ?? json['downloadUrl'] as String? ?? json['apkUrl'] as String? ?? '';
    if (rawDownloadUrl.isNotEmpty &&
        !rawDownloadUrl.startsWith('http://') &&
        !rawDownloadUrl.startsWith('https://') &&
        baseUrl != null &&
        baseUrl.isNotEmpty) {
      final cleanBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
      final cleanPath = rawDownloadUrl.startsWith('/') ? rawDownloadUrl : '/$rawDownloadUrl';
      rawDownloadUrl = '$cleanBase$cleanPath';
    }

    final rawBytes = json['file_size_bytes'] as int? ?? json['fileSizeBytes'] as int? ?? 0;
    final rawMb = (json['file_size_mb'] as num?)?.toDouble() ?? (rawBytes > 0 ? rawBytes / (1024 * 1024) : 0.0);

    final rawNotes = json['release_notes'] as List<dynamic>? ?? json['releaseNotes'] as List<dynamic>?;
    final notes = rawNotes?.map((e) => e.toString()).toList() ?? [];

    return AppUpdatePolicyInfo(
      hasUpdate: json['has_update'] as bool? ?? json['hasUpdate'] as bool? ?? false,
      platform: json['platform'] as String? ?? 'android',
      distributionChannel: json['distribution_channel'] as String? ?? json['distributionChannel'] as String? ?? 'direct_apk',
      updateType: json['update_type'] as String? ?? json['updateType'] as String? ?? 'direct_apk',
      latestVersion: json['latest_version'] as String? ?? json['version'] as String? ?? '1.0.0',
      latestVersionCode: json['latest_version_code'] as int? ?? json['versionCode'] as int? ?? 1,
      minSupportedVersionCode: json['min_supported_version_code'] as int? ?? json['minimumSupportedVersionCode'] as int? ?? 1,
      isMandatory: json['is_mandatory'] as bool? ?? json['forceUpdate'] as bool? ?? false,
      downloadUrl: rawDownloadUrl,
      patchManifestUrl: json['patch_manifest_url'] as String?,
      fileSizeBytes: rawBytes,
      fileSizeMb: rawMb,
      sha256Hash: json['sha256_hash'] as String? ?? json['sha256'] as String?,
      releaseTitle: json['release_title'] as String? ?? json['releaseTitle'] as String? ?? 'System Update Available',
      releaseNotes: notes,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

/// Senior engineer enterprise update system supporting:
/// - Developer-controlled dynamic backend policies (no hardcoded versions)
/// - Silent resource patches without APK reinstall
/// - Resumable HTTP 206 chunked APK downloads with SHA-256 verification
/// - Dual distribution (Google Play vs Direct APK)
/// - Background automatic periodic checks
/// - Free Fire MAX high-tech HUD dialog
class AppUpdateService {
  static final AppUpdateService instance = AppUpdateService._internal();
  AppUpdateService._internal();

  static const MethodChannel _updateChannel = MethodChannel('com.fieldstaff.attendance/app_update');

  /// Session memory for dismissed version codes so non-mandatory updates don't harass users
  static int? _dismissedVersionCode;

  /// Lock to prevent multiple concurrent update checks/downloads
  static bool _isCheckingOrUpdating = false;

  /// Periodic background timer
  Timer? _backgroundTimer;

  /// Start automatic background update checker respecting Android background restrictions
  void startPeriodicBackgroundCheck({Duration interval = const Duration(hours: 6)}) {
    _backgroundTimer?.cancel();
    _backgroundTimer = Timer.periodic(interval, (_) {
      _runSilentBackgroundUpdateCheck();
    });
    // Trigger initial silent check after 30 seconds of app start
    Future.delayed(const Duration(seconds: 30), () {
      _runSilentBackgroundUpdateCheck();
    });
  }

  /// Silent background check (does not show UI unless pre-downloaded APK is ready to install)
  Future<void> _runSilentBackgroundUpdateCheck() async {
    if (kIsWeb || !Platform.isAndroid || _isCheckingOrUpdating) return;

    try {
      final policy = await _fetchPolicyFromServer();
      if (policy == null || !policy.hasUpdate) return;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 1;

      if (policy.latestVersionCode <= currentBuildNumber) return;

      // 1. Silent Resource Patch Handling
      if (policy.updateType == 'resource_patch') {
        debugPrint('[AppUpdateService] Background silent resource patch detected: v${policy.latestVersion}');
        await _downloadAndApplyResourcePatch(policy, null, null, null);
        return;
      }

      // 2. Full APK Pre-download on unmetered network (WiFi)
      final isUnmetered = await isNetworkUnmetered();
      if (isUnmetered && !policy.isMandatory) {
        debugPrint('[AppUpdateService] Unmetered network available. Background pre-downloading APK...');
        final tempDir = await getTemporaryDirectory();
        final apkFile = File('${tempDir.path}/app-update.apk');
        final downloaded = await _downloadApkWithResume(
          policy: policy,
          targetFile: apkFile,
          progressNotifier: ValueNotifier<double>(0.0),
          speedNotifier: ValueNotifier<String>(''),
          errorNotifier: ValueNotifier<String>(''),
        );

        if (downloaded) {
          // Notify user that update is ready to install instantly
          await NotificationService.instance.showNotification(
            id: 9994,
            title: 'FieldStaff Update Ready',
            body: 'Version ${policy.latestVersion} is downloaded. Tap to update.',
            category: 'UPDATE',
          );
        }
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Silent background check skipped: $e');
    }
  }

  /// Main public update check invoked on UI startup or user button click
  Future<void> checkForUpdates(BuildContext context, {bool showNoUpdateNotice = false}) async {
    if (kIsWeb || !Platform.isAndroid) {
      if (showNoUpdateNotice && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('App is up to date (Web / Unsupported OS).')),
        );
      }
      return;
    }

    if (_isCheckingOrUpdating) return;
    _isCheckingOrUpdating = true;

    try {
      final policy = await _fetchPolicyFromServer();
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 1;
      final currentVersionName = packageInfo.version;

      if (policy == null || policy.latestVersionCode <= currentBuildNumber) {
        _isCheckingOrUpdating = false;
        if (showNoUpdateNotice && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('App is up to date (v$currentVersionName Build $currentBuildNumber).')),
          );
        }
        return;
      }

      // Check dismissed cache for optional updates
      if (!policy.isMandatory && _dismissedVersionCode == policy.latestVersionCode && !showNoUpdateNotice) {
        _isCheckingOrUpdating = false;
        return;
      }

      // Record telemetry check
      _logTelemetry(
        targetPolicy: policy,
        currentVersionCode: currentBuildNumber,
        currentVersion: currentVersionName,
        status: 'CHECKED',
      );

      // Present Free Fire MAX style update HUD
      if (context.mounted) {
        _showFreeFireUpdateDialog(context, policy, currentVersionName, currentBuildNumber);
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Check updates error: $e');
    } finally {
      _isCheckingOrUpdating = false;
    }
  }

  /// Fetch dynamic update policy from backend with failover support
  Future<AppUpdatePolicyInfo?> _fetchPolicyFromServer() async {
    final channel = await getDistributionChannel();
    final packageInfo = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 1;
    final currentVer = packageInfo.version;
    final deviceId = await DeviceService.instance.getDeviceId();

    final queryParams = 'platform=android&channel=$channel&version_code=$currentBuild&version_name=$currentVer&device_id=$deviceId';

    final activeBaseUrl = ApiClient().baseUrl.replaceAll(RegExp(r'/+$'), '');
    final candidateUrls = {
      if (activeBaseUrl.isNotEmpty) '$activeBaseUrl/api/app/update-policy?$queryParams',
      for (final host in ApiConfig.effectiveCandidates)
        '${host.replaceAll(RegExp(r'/+$'), '')}/api/app/update-policy?$queryParams',
      // Fallback endpoint
      if (activeBaseUrl.isNotEmpty) '$activeBaseUrl/api/app/latest-release?channel=$channel',
      for (final host in ApiConfig.effectiveCandidates)
        '${host.replaceAll(RegExp(r'/+$'), '')}/api/app/latest-release?channel=$channel',
    }.toList();

    for (final url in candidateUrls) {
      try {
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = json.decode(res.body) as Map<String, dynamic>;
          final parsed = AppUpdatePolicyInfo.fromJson(data, baseUrl: activeBaseUrl);
          return parsed;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Show Free Fire MAX style tactical HUD dialog
  void _showFreeFireUpdateDialog(
    BuildContext context,
    AppUpdatePolicyInfo policy,
    String currentVersion,
    int currentBuildNumber,
  ) {
    final progressNotifier = ValueNotifier<double>(0.0);
    final statusNotifier = ValueNotifier<UpdateHudStatus>(UpdateHudStatus.idle);
    final speedNotifier = ValueNotifier<String>('');
    final errorNotifier = ValueNotifier<String>('');

    showDialog(
      context: context,
      barrierDismissible: !policy.isMandatory,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (dialogCtx) {
        return FreeFirePatchHud(
          currentVersion: 'v$currentVersion (B$currentBuildNumber)',
          targetVersion: policy.latestVersion,
          targetVersionCode: policy.latestVersionCode,
          updateType: policy.updateType,
          fileSizeMb: policy.fileSizeMb,
          releaseNotes: policy.releaseNotes,
          isMandatory: policy.isMandatory,
          releaseTitle: policy.releaseTitle,
          progressNotifier: progressNotifier,
          statusNotifier: statusNotifier,
          speedNotifier: speedNotifier,
          errorNotifier: errorNotifier,
          onDismiss: () {
            _dismissedVersionCode = policy.latestVersionCode;
            Navigator.of(dialogCtx, rootNavigator: true).pop();
            _logTelemetry(
              targetPolicy: policy,
              currentVersionCode: currentBuildNumber,
              currentVersion: currentVersion,
              status: 'DISMISSED',
            );
          },
          onRetry: () {
            statusNotifier.value = UpdateHudStatus.idle;
            errorNotifier.value = '';
            _executeFlow(dialogCtx, policy, progressNotifier, statusNotifier, speedNotifier, errorNotifier, currentVersion, currentBuildNumber);
          },
          onStartUpdate: () {
            _executeFlow(dialogCtx, policy, progressNotifier, statusNotifier, speedNotifier, errorNotifier, currentVersion, currentBuildNumber);
          },
        );
      },
    );
  }

  /// Orchestrate patch vs APK installation execution
  Future<void> _executeFlow(
    BuildContext dialogCtx,
    AppUpdatePolicyInfo policy,
    ValueNotifier<double> progressNotifier,
    ValueNotifier<UpdateHudStatus> statusNotifier,
    ValueNotifier<String> speedNotifier,
    ValueNotifier<String> errorNotifier,
    String currentVersion,
    int currentBuildNumber,
  ) async {
    // 1. Silent Resource Patch Flow
    if (policy.updateType == 'resource_patch') {
      statusNotifier.value = UpdateHudStatus.downloading;
      final success = await _downloadAndApplyResourcePatch(policy, progressNotifier, speedNotifier, errorNotifier);
      if (success) {
        statusNotifier.value = UpdateHudStatus.appliedSilent;
        _logTelemetry(
          targetPolicy: policy,
          currentVersionCode: currentBuildNumber,
          currentVersion: currentVersion,
          status: 'APPLIED',
        );
        await Future.delayed(const Duration(milliseconds: 1600));
        if (dialogCtx.mounted) {
          Navigator.of(dialogCtx, rootNavigator: true).pop();
        }
      } else {
        statusNotifier.value = UpdateHudStatus.failed;
      }
      return;
    }

    // 2. Direct APK Flow
    statusNotifier.value = UpdateHudStatus.downloading;
    final tempDir = await getTemporaryDirectory();
    final apkFile = File('${tempDir.path}/app-update.apk');

    final downloaded = await _downloadApkWithResume(
      policy: policy,
      targetFile: apkFile,
      progressNotifier: progressNotifier,
      speedNotifier: speedNotifier,
      errorNotifier: errorNotifier,
    );

    if (!downloaded) {
      statusNotifier.value = UpdateHudStatus.failed;
      _logTelemetry(
        targetPolicy: policy,
        currentVersionCode: currentBuildNumber,
        currentVersion: currentVersion,
        status: 'FAILED',
        errorMessage: errorNotifier.value,
      );
      return;
    }

    // 3. Verification & Package Installation
    statusNotifier.value = UpdateHudStatus.verifying;
    final verified = await _verifySha256(apkFile, policy.sha256Hash);
    if (!verified) {
      statusNotifier.value = UpdateHudStatus.failed;
      errorNotifier.value = 'Integrity verification failed (SHA-256 mismatch).';
      if (await apkFile.exists()) await apkFile.delete();
      _logTelemetry(
        targetPolicy: policy,
        currentVersionCode: currentBuildNumber,
        currentVersion: currentVersion,
        status: 'FAILED',
        errorMessage: 'SHA-256 verification failed',
      );
      return;
    }

    statusNotifier.value = UpdateHudStatus.readyToInstall;
    _logTelemetry(
      targetPolicy: policy,
      currentVersionCode: currentBuildNumber,
      currentVersion: currentVersion,
      status: 'DOWNLOADED',
    );

    // Launch package installer via native FileProvider intent
    final installed = await launchApkInstaller(apkFile.path);
    if (installed) {
      _logTelemetry(
        targetPolicy: policy,
        currentVersionCode: currentBuildNumber,
        currentVersion: currentVersion,
        status: 'INSTALLED',
      );
    } else {
      statusNotifier.value = UpdateHudStatus.failed;
      errorNotifier.value = 'Package installation failed or permission denied.';
    }
  }

  /// Download and apply small silent resource patch
  Future<bool> _downloadAndApplyResourcePatch(
    AppUpdatePolicyInfo policy,
    ValueNotifier<double>? progressNotifier,
    ValueNotifier<String>? speedNotifier,
    ValueNotifier<String>? errorNotifier,
  ) async {
    try {
      final patchUrl = policy.patchManifestUrl ?? policy.downloadUrl;
      final response = await http.get(Uri.parse(patchUrl)).timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        errorNotifier?.value = 'HTTP ${response.statusCode}: Failed to fetch resource patch.';
        return false;
      }

      final bytes = response.bodyBytes;
      if (policy.sha256Hash != null && policy.sha256Hash!.isNotEmpty) {
        final computed = sha256.convert(bytes).toString();
        if (computed.toLowerCase() != policy.sha256Hash!.toLowerCase()) {
          errorNotifier?.value = 'Patch hash verification mismatch.';
          return false;
        }
      }

      final applied = await PatchManager.instance.applyResourcePatch(
        patchId: 'v${policy.latestVersionCode}',
        patchVersionCode: policy.latestVersionCode,
        versionString: policy.latestVersion,
        patchBytes: bytes,
        expectedSha256: policy.sha256Hash ?? '',
        metadata: policy.metadata,
      );

      return applied;
    } catch (e) {
      errorNotifier?.value = 'Patch error: $e';
      return false;
    }
  }

  /// Resumable HTTP 206 chunked APK downloader with speed tracking
  Future<bool> _downloadApkWithResume({
    required AppUpdatePolicyInfo policy,
    required File targetFile,
    required ValueNotifier<double> progressNotifier,
    required ValueNotifier<String> speedNotifier,
    required ValueNotifier<String> errorNotifier,
  }) async {
    final partFile = File('${targetFile.path}.part');
    final stopwatch = Stopwatch()..start();

    try {
      int existingBytes = 0;
      if (await partFile.exists()) {
        existingBytes = await partFile.length();
      }

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(policy.downloadUrl));

      if (existingBytes > 0) {
        request.headers['Range'] = 'bytes=$existingBytes-';
        debugPrint('[AppUpdateService] Resuming download from byte $existingBytes...');
      }

      final response = await client.send(request);
      final isPartial = response.statusCode == 206;
      final isFull = response.statusCode == 200;

      if (!isPartial && !isFull) {
        errorNotifier.value = 'Server returned HTTP ${response.statusCode}';
        return false;
      }

      IOSink sink;
      if (isPartial) {
        sink = partFile.openWrite(mode: FileMode.append);
      } else {
        existingBytes = 0;
        sink = partFile.openWrite(mode: FileMode.write);
      }

      final totalBytes = (response.contentLength ?? 0) + existingBytes;
      int receivedBytes = existingBytes;
      int speedWindowBytes = 0;
      int lastSpeedCheckMs = stopwatch.elapsedMilliseconds;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        speedWindowBytes += chunk.length;

        if (totalBytes > 0) {
          progressNotifier.value = (receivedBytes / totalBytes).clamp(0.0, 1.0);
        }

        final nowMs = stopwatch.elapsedMilliseconds;
        if (nowMs - lastSpeedCheckMs >= 600) {
          final elapsedSec = (nowMs - lastSpeedCheckMs) / 1000.0;
          final speedMb = (speedWindowBytes / (1024 * 1024)) / elapsedSec;
          speedNotifier.value = '${speedMb.toStringAsFixed(1)} MB/s';
          speedWindowBytes = 0;
          lastSpeedCheckMs = nowMs;
        }
      }

      await sink.flush();
      await sink.close();

      // Rename .part to target APK
      if (await targetFile.exists()) await targetFile.delete();
      await partFile.rename(targetFile.path);

      debugPrint('[AppUpdateService] APK download completed: ${targetFile.path} ($receivedBytes bytes)');
      return true;
    } catch (e) {
      errorNotifier.value = 'Download interrupted: $e';
      return false;
    } finally {
      stopwatch.stop();
    }
  }

  /// Strict SHA-256 file checksum verification
  Future<bool> _verifySha256(File file, String? expectedHash) async {
    if (expectedHash == null || expectedHash.isEmpty) return true;
    try {
      final digest = await sha256.bind(file.openRead()).first;
      final calculated = digest.toString().toLowerCase();
      final expected = expectedHash.trim().toLowerCase();
      final matches = calculated == expected;
      if (!matches) {
        debugPrint('[AppUpdateService] SHA-256 verification failed! Calculated: $calculated, Expected: $expected');
      }
      return matches;
    } catch (e) {
      debugPrint('[AppUpdateService] SHA-256 computation error: $e');
      return false;
    }
  }

  /// Launch system PackageInstaller via Android Native Channel and FileProvider
  Future<bool> launchApkInstaller(String apkPath) async {
    try {
      final bool? result = await _updateChannel.invokeMethod<bool>('installApk', {
        'filePath': apkPath,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[AppUpdateService] Native install error: ${e.code} - ${e.message}');
      if (e.code == 'PERMISSION_DENIED') {
        await _updateChannel.invokeMethod('openInstallPermissionSettings');
      }
      return false;
    } catch (e) {
      debugPrint('[AppUpdateService] General install invocation error: $e');
      return false;
    }
  }

  /// Get installer distribution source (e.g. google_play or direct_apk)
  Future<String> getDistributionChannel() async {
    if (!Platform.isAndroid) return 'direct_apk';
    try {
      final String? channel = await _updateChannel.invokeMethod<String>('getDistributionChannel');
      return channel ?? 'direct_apk';
    } catch (_) {
      return 'direct_apk';
    }
  }

  /// Check whether active connection is unmetered (WiFi or unlimited cellular)
  Future<bool> isNetworkUnmetered() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? unmetered = await _updateChannel.invokeMethod<bool>('isNetworkUnmetered');
      return unmetered ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Send telemetry event to backend asynchronously
  void _logTelemetry({
    required AppUpdatePolicyInfo targetPolicy,
    required int currentVersionCode,
    required String currentVersion,
    required String status,
    String? errorMessage,
    int? bytesDownloaded,
  }) async {
    try {
      final deviceId = await DeviceService.instance.getDeviceId();
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');

      final activeBaseUrl = ApiClient().baseUrl.replaceAll(RegExp(r'/+$'), '');
      if (activeBaseUrl.isEmpty) return;

      final payload = {
        'device_id': deviceId,
        'user_id': userId,
        'current_version': currentVersion,
        'current_version_code': currentVersionCode,
        'target_version': targetPolicy.latestVersion,
        'target_version_code': targetPolicy.latestVersionCode,
        'update_type': targetPolicy.updateType,
        'status': status,
        'bytes_downloaded': bytesDownloaded ?? targetPolicy.fileSizeBytes,
        'error_message': errorMessage,
      };

      http.post(
        Uri.parse('$activeBaseUrl/api/app/telemetry/update-log'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 4)).ignore();
    } catch (_) {}
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

import '../../config/api_config.dart';
import '../../network/api_client.dart';
import 'notification_service.dart';

class UpdateInfo {
  final String version;
  final int versionCode;
  final String apkUrl;
  final bool forceUpdate;
  final int minimumSupportedVersionCode;
  final List<String> releaseNotes;
  final String? sha256;

  UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.apkUrl,
    this.forceUpdate = false,
    this.minimumSupportedVersionCode = 1,
    this.releaseNotes = const [],
    this.sha256,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json, {String? baseUrl}) {
    String rawApkUrl = json['apkUrl'] as String? ?? json['apk_url'] as String? ?? '';
    if (rawApkUrl.isNotEmpty && !rawApkUrl.startsWith('http://') && !rawApkUrl.startsWith('https://') && baseUrl != null) {
      final cleanBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
      final cleanPath = rawApkUrl.startsWith('/') ? rawApkUrl : '/$rawApkUrl';
      rawApkUrl = '$cleanBase$cleanPath';
    }

    return UpdateInfo(
      version: json['version'] as String? ?? '1.0.0',
      versionCode: json['versionCode'] as int? ?? json['version_code'] as int? ?? 1,
      apkUrl: rawApkUrl,
      forceUpdate: json['forceUpdate'] as bool? ?? json['force_update'] as bool? ?? false,
      minimumSupportedVersionCode: json['minimumSupportedVersionCode'] as int? ?? json['min_version_code'] as int? ?? 1,
      releaseNotes: (json['releaseNotes'] as List<dynamic>? ?? json['release_notes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      sha256: json['sha256'] as String?,
    );
  }
}

class AppUpdateService {
  static final AppUpdateService instance = AppUpdateService._internal();
  AppUpdateService._internal();

  /// Session cache for dismissed version code so the dialog does not repeatedly harass users
  static int? _dismissedVersionCode;

  Future<void> checkForUpdates(BuildContext context, {bool showNoUpdateNotice = false}) async {
    // 1. Never show APK update prompt on Web or non-Android platforms
    if (kIsWeb || !Platform.isAndroid) {
      if (showNoUpdateNotice && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('App is up to date.')),
        );
      }
      return;
    }

    try {
      final baseUrl = ApiClient().baseUrl.replaceAll(RegExp(r'/+$'), '');
      // Try active backend baseUrl first, followed by configured public/LAN backend candidates
      final candidateUrls = {
        if (baseUrl.isNotEmpty) '$baseUrl/api/app/latest-release',
        for (final host in ApiConfig.effectiveCandidates)
          '${host.replaceAll(RegExp(r'/+$'), '')}/api/app/latest-release',
      }.toList();

      http.Response? response;
      for (final url in candidateUrls) {
        try {
          final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
          if (res.statusCode == 200) {
            response = res;
            break;
          }
        } catch (_) {}
      }

      if (response == null || response.statusCode != 200) {
        if (showNoUpdateNotice && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('App is up to date.')),
          );
        }
        return;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final updateInfo = UpdateInfo.fromJson(data, baseUrl: baseUrl);

      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 1;

      if (updateInfo.versionCode > currentBuildNumber && context.mounted) {
        // If user already tapped "Later" for this version in the current session, don't re-prompt automatically
        if (!updateInfo.forceUpdate && _dismissedVersionCode == updateInfo.versionCode && !showNoUpdateNotice) {
          return;
        }

        // Record notification in local notification center
        await NotificationService.instance.showNotification(
          id: 9993,
          title: 'Update Available (v${updateInfo.version})',
          body: 'A new version with performance & tracking updates is ready.',
          category: 'UPDATE',
        );
        _showUpdateDialog(context, updateInfo);
      } else if (showNoUpdateNotice && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('App is up to date (Latest Version).')),
        );
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Update check skipped: $e');
    }
  }

  void _showUpdateDialog(BuildContext context, UpdateInfo update) {
    showDialog(
      context: context,
      barrierDismissible: !update.forceUpdate,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('App Update Available (v${update.version})'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('A new version of FieldStaff Attendance is ready for installation:'),
            if (update.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...update.releaseNotes.map((note) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $note', style: const TextStyle(fontSize: 13)),
                  )),
            ],
          ],
        ),
        actions: [
          if (!update.forceUpdate)
            TextButton(
              onPressed: () {
                _dismissedVersionCode = update.versionCode;
                Navigator.pop(ctx);
              },
              child: const Text('Later'),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0369A1),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _downloadAndInstallApk(context, update);
            },
            child: const Text('Update Now'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadAndInstallApk(BuildContext context, UpdateInfo update) async {
    final progressNotifier = ValueNotifier<double>(0.0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Downloading Update...'),
        content: ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (_, prog, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: prog > 0 ? prog : null),
              const SizedBox(height: 12),
              Text('${(prog * 100).toStringAsFixed(0)}% Completed'),
            ],
          ),
        ),
      ),
    );

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(update.apkUrl));
      final response = await client.send(request);

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;
      final bytes = <int>[];

      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          progressNotifier.value = receivedBytes / totalBytes;
        }
      }

      // Checksum verification
      if (update.sha256 != null && update.sha256!.isNotEmpty) {
        final calculatedHash = sha256.convert(bytes).toString();
        if (calculatedHash.toLowerCase() != update.sha256!.toLowerCase()) {
          throw Exception('APK SHA-256 verification failed.');
        }
      }

      // Save to temporary cache directory
      final tempDir = await getTemporaryDirectory();
      final apkFile = File('${tempDir.path}/app-update.apk');
      await apkFile.writeAsBytes(bytes);

      if (context.mounted) Navigator.pop(context);

      // Trigger system package installer
      await OpenFilex.open(apkFile.path);
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

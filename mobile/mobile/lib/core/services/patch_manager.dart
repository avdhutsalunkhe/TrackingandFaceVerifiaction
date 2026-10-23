import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Lightweight, secure resource & configuration patch manager.
/// Allows downloading, verifying, and applying changed assets, JSON configs,
/// translations, and dynamic parameters silently in background without reinstalling the APK.
class PatchManager {
  static final PatchManager instance = PatchManager._internal();
  PatchManager._internal();

  static const String _patchDirName = 'app_patches';
  static const String _activeManifestName = 'active_patch_manifest.json';

  Directory? _patchDirectory;
  Map<String, dynamic> _activeManifest = {};

  /// Initialize patch storage directory and load active patch manifest
  Future<void> init() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      _patchDirectory = Directory('${docDir.path}/$_patchDirName');
      if (!await _patchDirectory!.exists()) {
        await _patchDirectory!.create(recursive: true);
      }

      final manifestFile = File('${_patchDirectory!.path}/$_activeManifestName');
      if (await manifestFile.exists()) {
        final content = await manifestFile.readAsString();
        _activeManifest = json.decode(content) as Map<String, dynamic>;
        debugPrint('[PatchManager] Loaded active patch: ${_activeManifest['patch_id']} (v${_activeManifest['version']})');
      }
    } catch (e) {
      debugPrint('[PatchManager] Failed to initialize patch manager: $e');
    }
  }

  /// Get current applied patch version code or 0 if pure base APK
  int get activePatchVersionCode => (_activeManifest['patch_version_code'] as int?) ?? 0;

  /// Get patch directory path
  String? get patchDirPath => _patchDirectory?.path;

  /// Apply a resource patch downloaded from server
  Future<bool> applyResourcePatch({
    required String patchId,
    required int patchVersionCode,
    required String versionString,
    required List<int> patchBytes,
    required String expectedSha256,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      if (_patchDirectory == null) await init();

      // 1. Strict SHA-256 verification
      final computedHash = sha256.convert(patchBytes).toString().toLowerCase();
      if (computedHash != expectedSha256.toLowerCase()) {
        debugPrint('[PatchManager] Security rejection: Hash mismatch. Expected: $expectedSha256, Got: $computedHash');
        return false;
      }

      // 2. Unpack/save patch payload
      final patchFile = File('${_patchDirectory!.path}/patch_$patchId.bin');
      await patchFile.writeAsBytes(patchBytes);

      // If JSON configuration patch, save extracted configuration
      if (metadata != null && metadata.containsKey('config_payload')) {
        final configFile = File('${_patchDirectory!.path}/dynamic_config.json');
        await configFile.writeAsString(json.encode(metadata['config_payload']));
      }

      // 3. Update manifest
      _activeManifest = {
        'patch_id': patchId,
        'patch_version_code': patchVersionCode,
        'version': versionString,
        'sha256': computedHash,
        'applied_at': DateTime.now().toIso8601String(),
        'metadata': metadata ?? {},
      };

      final manifestFile = File('${_patchDirectory!.path}/$_activeManifestName');
      await manifestFile.writeAsString(json.encode(_activeManifest));
      debugPrint('[PatchManager] Successfully applied silent resource patch $patchId');
      return true;
    } catch (e) {
      debugPrint('[PatchManager] Error applying resource patch: $e');
      return false;
    }
  }

  /// Roll back to factory base app state if a patch is problematic
  Future<void> rollbackPatch() async {
    try {
      if (_patchDirectory == null) await init();
      final manifestFile = File('${_patchDirectory!.path}/$_activeManifestName');
      if (await manifestFile.exists()) {
        await manifestFile.delete();
      }
      _activeManifest.clear();
      debugPrint('[PatchManager] Rolled back all active resource patches to base factory state.');
    } catch (e) {
      debugPrint('[PatchManager] Rollback failed: $e');
    }
  }

  /// Read dynamic override for a resource or configuration file if patched
  Future<String?> readDynamicConfig(String configKey) async {
    if (_activeManifest.containsKey('metadata')) {
      final meta = _activeManifest['metadata'] as Map<String, dynamic>?;
      if (meta != null && meta.containsKey(configKey)) {
        return meta[configKey].toString();
      }
    }
    return null;
  }
}

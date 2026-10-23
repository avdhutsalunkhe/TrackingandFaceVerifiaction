import 'dart:ui';
import 'package:flutter/material.dart';

enum UpdateHudStatus {
  idle,
  downloading,
  verifying,
  readyToInstall,
  appliedSilent,
  failed,
}

class FreeFirePatchHud extends StatefulWidget {
  final String currentVersion;
  final String targetVersion;
  final int targetVersionCode;
  final String updateType; // resource_patch, direct_apk, in_app_play
  final double fileSizeMb;
  final List<String> releaseNotes;
  final bool isMandatory;
  final String releaseTitle;
  final VoidCallback onStartUpdate;
  final VoidCallback onDismiss;
  final VoidCallback onRetry;
  final ValueNotifier<double> progressNotifier;
  final ValueNotifier<UpdateHudStatus> statusNotifier;
  final ValueNotifier<String> speedNotifier;
  final ValueNotifier<String> errorNotifier;

  const FreeFirePatchHud({
    Key? key,
    required this.currentVersion,
    required this.targetVersion,
    required this.targetVersionCode,
    required this.updateType,
    required this.fileSizeMb,
    required this.releaseNotes,
    required this.isMandatory,
    this.releaseTitle = "TACTICAL PATCH AVAILABLE",
    required this.onStartUpdate,
    required this.onDismiss,
    required this.onRetry,
    required this.progressNotifier,
    required this.statusNotifier,
    required this.speedNotifier,
    required this.errorNotifier,
  }) : super(key: key);

  @override
  State<FreeFirePatchHud> createState() => _FreeFirePatchHudState();
}

class _FreeFirePatchHudState extends State<FreeFirePatchHud> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnimation = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color get _accentColor => widget.updateType == 'resource_patch'
      ? const Color(0xFF00E5FF) // Cyber Cyan
      : const Color(0xFFFF9900); // Tactical Amber Gold

  @override
  Widget build(BuildContext context) {
    final isPatch = widget.updateType == 'resource_patch';

    return WillPopScope(
      onWillPop: () async => !widget.isMandatory,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0F1D).withOpacity(0.96),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _accentColor.withOpacity(0.6),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _accentColor.withOpacity(0.25),
                blurRadius: 32,
                spreadRadius: 2,
              ),
              const BoxShadow(
                color: Colors.black87,
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top Tactical Header Beacon
                    _buildTacticalHeader(isPatch),
                    const SizedBox(height: 18),

                    // Version Transition Display (v1.0.3 -> v1.0.4)
                    _buildVersionHUD(),
                    const SizedBox(height: 16),

                    // Metrics Banner (File Size, Channel, Security)
                    _buildMetricsGrid(isPatch),
                    const SizedBox(height: 18),

                    // Release Notes Hologram Card
                    _buildReleaseNotesCard(),
                    const SizedBox(height: 20),

                    // Progress or Action Controls
                    _buildProgressAndControls(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTacticalHeader(bool isPatch) {
    return Row(
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accentColor.withOpacity(0.12 + (_pulseAnimation.value * 0.1)),
                border: Border.all(
                  color: _accentColor.withOpacity(0.7 + (_pulseAnimation.value * 0.3)),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _accentColor.withOpacity(0.3 * _pulseAnimation.value),
                    blurRadius: 14,
                  ),
                ],
              ),
              child: Icon(
                isPatch ? Icons.bolt_rounded : Icons.system_update_alt_rounded,
                color: _accentColor,
                size: 24,
              ),
            );
          },
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: _accentColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _accentColor.withOpacity(0.5), width: 1),
                    ),
                    child: Text(
                      isPatch ? 'RESOURCE PATCH' : (widget.isMandatory ? 'CRITICAL UPDATE' : 'CLIENT UPDATE'),
                      style: TextStyle(
                        color: _accentColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (!widget.isMandatory)
                    InkWell(
                      onTap: widget.onDismiss,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.08),
                        ),
                        child: const Icon(Icons.close, color: Colors.white70, size: 16),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                widget.releaseTitle.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVersionHUD() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildVersionBlock("INSTALLED", widget.currentVersion, Colors.white60),
          Icon(Icons.arrow_forward_ios_rounded, color: _accentColor, size: 16),
          _buildVersionBlock("NEW TARGET", "v${widget.targetVersion} (B${widget.targetVersionCode})", _accentColor),
        ],
      ),
    );
  }

  Widget _buildVersionBlock(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 0.8),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricsGrid(bool isPatch) {
    final sizeStr = widget.fileSizeMb > 0 ? '${widget.fileSizeMb.toStringAsFixed(1)} MB' : 'OPTIMIZED';

    return Row(
      children: [
        Expanded(
          child: _buildMetricTile(
            icon: Icons.data_usage_rounded,
            label: "DOWNLOAD SIZE",
            value: sizeStr,
            color: Colors.white70,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricTile(
            icon: Icons.verified_user_rounded,
            label: "SECURITY",
            value: "SHA-256 SIGNED",
            color: const Color(0xFF10B981), // Emerald Green
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({required IconData icon, required String label, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 0.5),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReleaseNotesCard() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 150),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.terminal_rounded, size: 14, color: _accentColor),
              const SizedBox(width: 6),
              const Text(
                "CHANGELOG / RECON PROTOCOL",
                style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: widget.releaseNotes.isEmpty
                ? const Text(
                    "• Performance, tracking accuracy, and security enhancements.",
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  )
                : ListView.builder(
                    itemCount: widget.releaseNotes.length,
                    shrinkWrap: true,
                    itemBuilder: (context, index) {
                      final note = widget.releaseNotes[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("▶ ", style: TextStyle(color: _accentColor, fontSize: 10)),
                            Expanded(
                              child: Text(
                                note,
                                style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressAndControls() {
    return ValueListenableBuilder<UpdateHudStatus>(
      valueListenable: widget.statusNotifier,
      builder: (context, status, _) {
        if (status == UpdateHudStatus.downloading || status == UpdateHudStatus.verifying) {
          return _buildDownloadProgressHUD(status);
        }

        if (status == UpdateHudStatus.failed) {
          return _buildFailureHUD();
        }

        if (status == UpdateHudStatus.appliedSilent) {
          return _buildAppliedSilentHUD();
        }

        // Idle State: Show Action Buttons
        return Row(
          children: [
            if (!widget.isMandatory) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onDismiss,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withOpacity(0.2)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("STANDBY", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [
                      _accentColor,
                      widget.updateType == 'resource_patch' ? const Color(0xFF0072FF) : const Color(0xFFFF5500),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _accentColor.withOpacity(0.4),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: widget.onStartUpdate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.flash_on_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        widget.updateType == 'resource_patch' ? "PATCH NOW" : "UPGRADE NOW",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDownloadProgressHUD(UpdateHudStatus status) {
    return Column(
      children: [
        ValueListenableBuilder<double>(
          valueListenable: widget.progressNotifier,
          builder: (context, progress, _) {
            final pct = (progress * 100).clamp(0.0, 100.0).toStringAsFixed(0);

            return Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      status == UpdateHudStatus.verifying ? "VERIFYING INTEGRITY..." : "DOWNLOADING PAYLOAD...",
                      style: TextStyle(
                        color: _accentColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    ValueListenableBuilder<String>(
                      valueListenable: widget.speedNotifier,
                      builder: (_, speed, __) => Text(
                        speed.isNotEmpty ? speed : "$pct%",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Stack(
                  children: [
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: progress > 0 ? progress.clamp(0.01, 1.0) : 0.05,
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          gradient: LinearGradient(
                            colors: [_accentColor.withOpacity(0.7), _accentColor],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _accentColor.withOpacity(0.8),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildFailureHUD() {
    return Column(
      children: [
        ValueListenableBuilder<String>(
          valueListenable: widget.errorNotifier,
          builder: (context, err, _) {
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      err.isNotEmpty ? err : "Network interrupted. Verification failed.",
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: widget.onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text("RE-ENGAGE / RETRY"),
          style: ElevatedButton.styleFrom(
            backgroundColor: _accentColor,
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(42),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  Widget _buildAppliedSilentHUD() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF10B981)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
          SizedBox(width: 8),
          Text(
            "RESOURCE PATCH APPLIED SUCCESSFULLY",
            style: TextStyle(
              color: Color(0xFF10B981),
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

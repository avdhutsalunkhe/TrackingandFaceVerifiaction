import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';

class GlobalSettingsDialog extends StatefulWidget {
  const GlobalSettingsDialog({Key? key}) : super(key: key);

  static Future<void> show(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (ctx) => const GlobalSettingsDialog(),
    );
  }

  @override
  State<GlobalSettingsDialog> createState() => _GlobalSettingsDialogState();
}

class _GlobalSettingsDialogState extends State<GlobalSettingsDialog> {
  final ApiClient _apiClient = ApiClient();
  final TextEditingController _thresholdController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  double _similarityThreshold = 0.65;
  double _livenessThreshold = 0.70;
  int _minFaceSize = 80;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchSettings();
  }

  Future<void> _fetchSettings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await _apiClient.get(ApiConstants.adminBiometricSettings);
      final sim = (res['similarity_threshold'] as num?)?.toDouble() ?? 0.65;
      final live = (res['liveness_confidence_threshold'] as num?)?.toDouble() ?? 0.70;
      final minSize = (res['min_face_size'] as num?)?.toInt() ?? 80;

      setState(() {
        _similarityThreshold = sim;
        _livenessThreshold = live;
        _minFaceSize = minSize;
        _thresholdController.text = sim.toStringAsFixed(2);
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _thresholdController.text = _similarityThreshold.toStringAsFixed(2);
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    final rawText = _thresholdController.text.trim();
    final parsed = double.tryParse(rawText);

    if (parsed == null || parsed < 0.0 || parsed > 1.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid similarity threshold between 0.00 and 1.00'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final res = await _apiClient.put(
        ApiConstants.adminBiometricSettings,
        body: {
          'similarity_threshold': parsed,
          'liveness_confidence_threshold': _livenessThreshold,
          'min_face_size': _minFaceSize,
        },
      );

      final updatedSim = (res['similarity_threshold'] as num?)?.toDouble() ?? parsed;

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Global similarity threshold updated to ${updatedSim.toStringAsFixed(2)} (${(updatedSim * 100).toInt()}%)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _applyPreset(double val) {
    setState(() {
      _similarityThreshold = val;
      _thresholdController.text = val.toStringAsFixed(2);
    });
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 420),
        child: _isLoading
            ? const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.tune_rounded, color: AppColors.primary, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Biometric Settings',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                            Text(
                              'Global Cosine Similarity Threshold',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppColors.error, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Description
                  const Text(
                    'Set the minimum face match confidence required to accept attendance globally across all employees:',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),

                  // Input Box for Threshold
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Similarity Threshold (0.00 - 1.00)',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${(_similarityThreshold * 100).toInt()}% Match',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _thresholdController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
                          decoration: InputDecoration(
                            hintText: 'e.g. 0.65',
                            prefixIcon: const Icon(Icons.speed_rounded, color: AppColors.primary),
                            suffixText: 'Score',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          onChanged: (val) {
                            final p = double.tryParse(val);
                            if (p != null && p >= 0.0 && p <= 1.0) {
                              setState(() {
                                _similarityThreshold = p;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        Slider(
                          value: _similarityThreshold.clamp(0.0, 1.0),
                          min: 0.0,
                          max: 1.0,
                          divisions: 100,
                          activeColor: AppColors.primary,
                          label: _similarityThreshold.toStringAsFixed(2),
                          onChanged: (val) {
                            setState(() {
                              _similarityThreshold = val;
                              _thresholdController.text = val.toStringAsFixed(2);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Quick Presets
                  const Text('Quick Presets:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildPresetChip('0.50 (Relaxed)', 0.50),
                      _buildPresetChip('0.60 (Smooth)', 0.60),
                      _buildPresetChip('0.65 (Standard)', 0.65),
                      _buildPresetChip('0.75 (Strict)', 0.75),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _isSaving ? null : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveSettings,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.save_rounded, size: 18),
                        label: Text(_isSaving ? 'Saving...' : 'Save Globally'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPresetChip(String label, double value) {
    final isSelected = (_similarityThreshold - value).abs() < 0.01;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      selectedColor: AppColors.primaryLight.withOpacity(0.2),
      onSelected: (_) => _applyPreset(value),
    );
  }
}

import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/services/location_service.dart';
import '../../core/utils/responsive_util.dart';

class GeofenceConfigScreen extends StatefulWidget {
  final int userId;
  final String employeeId;
  final String fullName;
  final Map<String, dynamic>? initialGeofence;

  const GeofenceConfigScreen({
    Key? key,
    required this.userId,
    required this.employeeId,
    required this.fullName,
    this.initialGeofence,
  }) : super(key: key);

  @override
  State<GeofenceConfigScreen> createState() => _GeofenceConfigScreenState();
}

class _GeofenceConfigScreenState extends State<GeofenceConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _locationNameController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _radiusController = TextEditingController(text: '100');

  final _apiClient = ApiClient();
  bool _isLoading = false;
  bool _isAcquiringGps = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialGeofence != null) {
      _locationNameController.text = widget.initialGeofence!['location_name'] ?? '';
      _latitudeController.text = widget.initialGeofence!['latitude']?.toString() ?? '';
      _longitudeController.text = widget.initialGeofence!['longitude']?.toString() ?? '';
      _radiusController.text = widget.initialGeofence!['radius_meters']?.toString() ?? '100';
    }
  }

  @override
  void dispose() {
    _locationNameController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  void _useCurrentLocation() async {
    setState(() => _isAcquiringGps = true);
    try {
      final pos = await LocationService.getCurrentPosition();
      if (pos != null) {
        setState(() {
          _latitudeController.text = pos.latitude.toString();
          _longitudeController.text = pos.longitude.toString();
        });
        if (_locationNameController.text.isEmpty) {
          _locationNameController.text = "Field Site (${pos.latitude}, ${pos.longitude})";
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to get GPS location: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      setState(() => _isAcquiringGps = false);
    }
  }

  void _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _apiClient.post(
        ApiConstants.adminUserGeofence(widget.userId),
        body: {
          'location_name': _locationNameController.text.trim(),
          'latitude': double.parse(_latitudeController.text.trim()),
          'longitude': double.parse(_longitudeController.text.trim()),
          'radius_meters': double.parse(_radiusController.text.trim()),
          'is_active': true,
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Geofence location assigned successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Assign Location: ${widget.employeeId}'),
      ),
      body: SafeArea(
        child: ResponsiveContainer(
          maxWidth: context.isDesktop ? 800 : 550,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            padding: ResponsiveUtil.screenPadding(context),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: ResponsiveUtil.cardPadding(context),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: AppColors.primaryLight,
                            child: Icon(Icons.person, color: Colors.white),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis),
                                Text('ID: ${widget.employeeId}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _locationNameController,
                    decoration: const InputDecoration(
                      labelText: 'Location Name *',
                      hintText: 'e.g. Field Site / North Farm',
                      prefixIcon: Icon(Icons.pin_drop_outlined),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Location name required' : null,
                  ),
                  const SizedBox(height: 16),

                  if (context.isSmallScreen) ...[
                    TextFormField(
                      controller: _latitudeController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Latitude *',
                        hintText: '16.1234567',
                        prefixIcon: Icon(Icons.my_location_rounded),
                      ),
                      validator: (v) => (v == null || double.tryParse(v) == null) ? 'Valid latitude required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _longitudeController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Longitude *',
                        hintText: '74.1234567',
                        prefixIcon: Icon(Icons.location_searching_rounded),
                      ),
                      validator: (v) => (v == null || double.tryParse(v) == null) ? 'Valid longitude required' : null,
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _latitudeController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Latitude *',
                              hintText: '16.1234567',
                              prefixIcon: Icon(Icons.my_location_rounded),
                            ),
                            validator: (v) => (v == null || double.tryParse(v) == null) ? 'Valid latitude required' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _longitudeController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Longitude *',
                              hintText: '74.1234567',
                              prefixIcon: Icon(Icons.location_searching_rounded),
                            ),
                            validator: (v) => (v == null || double.tryParse(v) == null) ? 'Valid longitude required' : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),

                  OutlinedButton.icon(
                    icon: _isAcquiringGps
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.gps_fixed_rounded, size: 18),
                    label: const Text('Use Current Device GPS Coords'),
                    onPressed: _isAcquiringGps ? null : _useCurrentLocation,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _radiusController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Allowed Radius (meters) *',
                      hintText: '100',
                      suffixText: 'meters',
                      prefixIcon: Icon(Icons.radar_rounded),
                    ),
                    validator: (v) {
                      if (v == null || double.tryParse(v) == null) return 'Valid radius required';
                      if (double.parse(v) <= 0) return 'Radius must be > 0';
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),

                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleSave,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Save Geofence Rules'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

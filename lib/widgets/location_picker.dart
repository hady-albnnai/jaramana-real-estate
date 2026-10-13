import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../core/theme/app_theme.dart';

/// مكوّن اختيار موقع على خريطة (OpenStreetMap — مجاني بدون API key)
/// يستخدم في add_offer_screen و edit_offer_screen
class LocationPicker extends StatefulWidget {
  final LatLng? initial;
  final void Function(LatLng location) onPicked;
  final double height;

  const LocationPicker({
    super.key,
    this.initial,
    required this.onPicked,
    this.height = 300,
  });

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  late LatLng _picked;
  final _mapController = MapController();
  bool _locating = false;

  // الموقع الافتراضي: مركز جرمانا، سوريا
  static const LatLng _jaramanaCenter = LatLng(33.4880, 36.3650);

  @override
  void initState() {
    super.initState();
    _picked = widget.initial ?? _jaramanaCenter;
  }

  /// ═══════════════════════════════════════════════════════════════════
  /// 📍 GP-002 (2026-08-15) — الإفصاح البارز قبل طلب إذن الموقع
  /// ═══════════════════════════════════════════════════════════════════
  /// سياسة Google Play (Permissions & APIs / Prominent Disclosure) تُلزم
  /// بإفصاح **داخل التطبيق** قبل طلب أي إذن حسّاس، يوضّح: ما البيانات،
  /// ولماذا، وأنها لا تُستخدم لغير الغرض المعلن. كان الإذن يُطلب مباشرةً
  /// عند الضغط على «موقعي الحالي» بلا أي شرح ⇒ سبب شائع لرفض المراجعة.
  ///
  /// يُعرض مرة واحدة لكل جلسة قبل أول طلب فعلي؛ إن رفض المستخدم لا نطلب
  /// الإذن من النظام إطلاقاً (احترام الرفض، لا إلحاح).
  bool _disclosureAccepted = false;

  Future<bool> _showLocationDisclosure() async {
    if (_disclosureAccepted) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Row(children: [
          Icon(Icons.location_on_outlined, color: AppTheme.primaryGold),
          SizedBox(width: 8),
          Expanded(
            child: Text('تحديد موقع العقار',
                style: TextStyle(color: AppTheme.primaryGold, fontSize: 18)),
          ),
        ]),
        content: const Text(
          'لتعبئة موقع العقار على الخريطة تلقائياً، يحتاج التطبيق إلى قراءة '
          'موقع جهازك الحالي.\n\n'
          '• يُستخدم الموقع لمرّة واحدة لتحريك مؤشّر الخريطة فقط.\n'
          '• لا نتتبّع موقعك في الخلفية، ولا نجمعه إلا عند ضغطك هذا الزر.\n'
          '• الموقع الدقيق لا يظهر للزوّار إطلاقاً — يراه موظفو المكتب '
          'والمصوّر المكلّف فقط لإتمام المعاينة.\n\n'
          'يمكنك دائماً تجاهل هذا وتحديد الموقع يدوياً بالضغط على الخريطة.',
          style: TextStyle(color: AppTheme.textWhite, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ليس الآن',
                style: TextStyle(color: AppTheme.textGrey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGold,
              foregroundColor: AppTheme.deepBlack,
            ),
            child: const Text('موافق، حدّد موقعي'),
          ),
        ],
      ),
    );
    if (ok == true) _disclosureAccepted = true;
    return ok == true;
  }

  Future<void> _useMyLocation() async {
    // 📍 GP-002: الإفصاح أولاً — لا يُطلب إذن النظام قبل موافقة صريحة.
    final agreed = await _showLocationDisclosure();
    if (!agreed) return;
    if (!mounted) return;

    setState(() => _locating = true);
    try {
      // طلب الإذن
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _snack('تم رفض إذن الموقع — يمكنك تحديد الموقع يدوياً على الخريطة');
        return;
      }

      // 📍 GP-002: `medium` تكفي تماماً لتحريك مؤشّر خريطة (~100م) ثم
      // يضبطه المستخدم بإصبعه. كانت `high` (GPS دقيق) وهي أعلى مما تحتاجه
      // الوظيفة، وطلب دقة زائدة يستدعي تدقيقاً أشد من مراجعي Google بلا
      // أي فائدة للمستخدم. (الإذن في المانيفست خُفِّض لـCOARSE تبعاً لذلك.)
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      final newLoc = LatLng(position.latitude, position.longitude);
      setState(() => _picked = newLoc);
      _mapController.move(newLoc, 15);
      widget.onPicked(newLoc);
    } catch (e) {
      _snack('فشل تحديد الموقع: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    AppTheme.showSnackBar(context, SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.4)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _picked,
                initialZoom: 13,
                onTap: (_, latLng) {
                  setState(() => _picked = latLng);
                  widget.onPicked(latLng);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.hadyalbnnai.jaramanarealestate',
                ),
                MarkerLayer(markers: [
                  Marker(
                    point: _picked,
                    width: 50,
                    height: 50,
                    child: const Icon(
                      Icons.location_on,
                      color: AppTheme.errorRed,
                      size: 50,
                    ),
                  ),
                ]),
              ],
            ),
            // أزرار التحكم
            Positioned(
              top: 8,
              right: 8,
              child: Column(children: [
                FloatingActionButton.small(
                  heroTag: 'loc',
                  backgroundColor: AppTheme.primaryGold,
                  foregroundColor: Colors.black,
                  onPressed: _locating ? null : _useMyLocation,
                  child: _locating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.my_location),
                ),
                const SizedBox(height: 6),
                FloatingActionButton.small(
                  heroTag: 'zoomin',
                  backgroundColor: AppTheme.surfaceBlack,
                  foregroundColor: AppTheme.primaryGold,
                  onPressed: () => _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom + 1),
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 6),
                FloatingActionButton.small(
                  heroTag: 'zoomout',
                  backgroundColor: AppTheme.surfaceBlack,
                  foregroundColor: AppTheme.primaryGold,
                  onPressed: () => _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom - 1),
                  child: const Icon(Icons.remove),
                ),
              ]),
            ),
            // الإحداثيات بأسفل
            Positioned(
              bottom: 8,
              left: 8,
              right: 70,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '📍 ${_picked.latitude.toStringAsFixed(5)}, ${_picked.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(color: Colors.white, fontSize: AppTheme.fontSizeCaption),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// عارض موقع للقراءة فقط (يستخدم في offer_detail_screen)
class LocationViewer extends StatelessWidget {
  final double lat;
  final double lng;
  final double height;

  const LocationViewer({
    super.key,
    required this.lat,
    required this.lng,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    final point = LatLng(lat, lng);
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: 15,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.hadyalbnnai.jaramanarealestate',
            ),
            MarkerLayer(markers: [
              Marker(
                point: point,
                width: 50,
                height: 50,
                child: const Icon(Icons.location_on,
                    color: AppTheme.errorRed, size: 50),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

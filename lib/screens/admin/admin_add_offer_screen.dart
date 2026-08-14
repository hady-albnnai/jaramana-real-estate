import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../core/constants/db_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/supabase_service.dart';
import '../../models/offer_model.dart';
import '../../models/user_model.dart';
import '../../services/storage_service.dart';
import '../../core/validation/input_validators.dart';
import '../../widgets/location_picker.dart';

/// شاشة إضافة عرض من الإدارة
/// - تختلف عن شاشة المستخدم في: اختيار صاحب العرض + حفظ added_by
/// - من يصل إليها: role >= UserRole.minAdmin فقط
/// - added_by = uid الموظف/المدير — يظهر فقط في لوحة الإدارة
class AdminAddOfferScreen extends StatefulWidget {
  const AdminAddOfferScreen({
    super.key,
    this.photoTaskId,
    this.presetOwnerUid,
    this.presetImages,
    this.presetPhone,
    this.presetLocation,
  });

  /// 📸 معرّف مهمة التصوير التي وُلد منها العرض (تُربط وتُغلق بعد النشر)
  final String? photoTaskId;

  /// مالك العرض مُسبقاً = صاحب طلب التصوير
  final String? presetOwnerUid;

  /// صور المصوّر المرفوعة (روابط جاهزة — لا يُعاد رفعها)
  final List<String>? presetImages;

  /// هاتف وموقع الطالب المستخرجان من ملاحظات المهمة
  final String? presetPhone;
  final String? presetLocation;

  bool get isFromPhotoTask => (photoTaskId ?? '').isNotEmpty;

  @override
  State<AdminAddOfferScreen> createState() => _AdminAddOfferScreenState();
}

class _AdminAddOfferScreenState extends State<AdminAddOfferScreen> {
  static const String _customCityOption = '__custom_city__';

  // ── الخطوات ──
  int _currentStep = 0;

  // ── بيانات العرض ──
  int? _selectedType;
  int? _selectedTrans;
  int? _selectedMainCat;
  int? _selectedSubCat;
  String? _selectedCityArea;
  int _cur = Currency.lbp;
  final _priceCtrl     = TextEditingController();
  final _locCtrl       = TextEditingController();
  final _descCtrl      = TextEditingController();
  final _specCtrl      = TextEditingController();
  final _ttlCtrl       = TextEditingController();
  final _customSubCtrl = TextEditingController();
  final _contactPhCtrl = TextEditingController();
  final _customCityCtrl = TextEditingController();

  // ── صاحب العرض ──
  UserModel? _selectedOwner;
  List<UserModel> _users = [];
  bool _loadingUsers = true;
  final _ownerSearchCtrl = TextEditingController();

  // ── الوسائط ──
  final List<XFile> _pickedImages = [];
  XFile? _docImage;
  LatLng? _pickedLocation;
  int? _selectedDocType;

  // ── المواعيد المتاحة (avl) ──
  static const _weekDays = [
    ('mon', 'الاثنين'), ('tue', 'الثلاثاء'), ('wed', 'الأربعاء'),
    ('thu', 'الخميس'),  ('fri', 'الجمعة'),    ('sat', 'السبت'),
    ('sun', 'الأحد'),
  ];
  final Map<String, bool> _avlDaysEnabled = {
    'mon': false, 'tue': false, 'wed': false, 'thu': false,
    'fri': false, 'sat': false, 'sun': false,
  };
  final Map<String, List<Map<String, String>>> _avlSlots = {
    'mon': [], 'tue': [], 'wed': [], 'thu': [],
    'fri': [], 'sat': [], 'sun': [],
  };

  bool _submitting = false;
  String _progressMsg = '';

  final _storage = StorageService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ConfigProvider>().loadConfig();
      _loadUsers();
    });
  }

  @override
  void dispose() {
    _priceCtrl.dispose(); _locCtrl.dispose(); _descCtrl.dispose();
    _specCtrl.dispose();  _ttlCtrl.dispose(); _customSubCtrl.dispose();
    _contactPhCtrl.dispose(); _customCityCtrl.dispose();
    _ownerSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final res = await SupabaseService().client
          .from(DbTables.users)
          .select('id, nm, ph, role, sts, i_del')
          .eq('i_del', 0)
          .eq('sts', 0)
          .order('nm');
      _users = (res as List)
          .map((d) => UserModel.fromSupabase(
              Map<String, dynamic>.from(d), d['id'] as String))
          .toList();
    } catch (_) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }
    if (mounted) setState(() => _loadingUsers = false);
    _applyPhotoTaskPreset();
  }

  /// 📸 تعبئة مسبقة عند القدوم من مهمة تصوير:
  /// المالك = صاحب الطلب · الصور = صور المصوّر (جاهزة) · الهاتف والموقع من الملاحظات.
  void _applyPhotoTaskPreset() {
    if (!widget.isFromPhotoTask || !mounted) return;
    final ownerUid = widget.presetOwnerUid ?? '';
    UserModel? owner;
    for (final u in _users) {
      if (u.uid == ownerUid) {
        owner = u;
        break;
      }
    }
    setState(() {
      if (owner != null) _selectedOwner = owner;
      if ((widget.presetPhone ?? '').isNotEmpty && _contactPhCtrl.text.trim().isEmpty) {
        _contactPhCtrl.text = widget.presetPhone!;
      } else if (owner != null && _contactPhCtrl.text.trim().isEmpty) {
        _contactPhCtrl.text = owner.ph;
      }
      if ((widget.presetLocation ?? '').isNotEmpty && _locCtrl.text.trim().isEmpty) {
        _locCtrl.text = widget.presetLocation!;
      }
    });
  }

  Map<String, List<String>> _buildAvl() {
    final result = <String, List<String>>{};
    for (final day in _weekDays) {
      final key = day.$1;
      if (_avlDaysEnabled[key] == true && _avlSlots[key]!.isNotEmpty) {
        result[key] = _avlSlots[key]!
            .where((s) => s['from']!.isNotEmpty && s['to']!.isNotEmpty)
            .map((s) => '${s['from']}-${s['to']}')
            .toList();
      }
    }
    return result;
  }

  Future<void> _submit() async {
    final auth      = context.read<AuthProvider>();
    final admin     = auth.userModel;

    if (admin == null || !admin.isAdmin) {
      _snack('غير مصرح لك بهذه العملية');
      return;
    }
    if (_selectedOwner == null) {
      _snack('يرجى اختيار صاحب العرض');
      return;
    }
    if (_selectedType == null || _selectedTrans == null ||
        _selectedMainCat == null ||
        _selectedCityArea == null ||
        (_selectedCityArea == _customCityOption && _customCityCtrl.text.trim().isEmpty) ||
        _locCtrl.text.trim().isEmpty) {
      _snack('يرجى إكمال البيانات الأساسية');
      return;
    }
    final effectivePhone = InputValidators.normalizeDigits(_contactPhCtrl.text.trim());
    if (effectivePhone.isEmpty) {
      _snack('رقم الهاتف للتواصل إلزامي');
      return;
    }
    final price = double.tryParse(InputValidators.normalizeDigits(_priceCtrl.text).replaceAll(',', '')) ?? 0.0;
    if (price <= 0) { _snack('يرجى إدخال سعر صالح'); return; }
    if (_selectedDocType == null) {
      _snack('يرجى اختيار نوع سند الملكية');
      return;
    }

    // 🖼️ IMG-001 (2026-08-15): صورة واحدة على الأقل — قرار المالك.
    // مسار الإدارة لا يمرّ بـ`photo_req`، فالسيرفر يرفضه بلا صور. نفحص هنا
    // لتظهر رسالة عربية فوراً بدل خطأ تقني بعد رفع السند وانتظار طويل.
    if (_pickedImages.isEmpty &&
        (widget.presetImages == null || widget.presetImages!.isEmpty)) {
      _snack('يرجى إضافة صورة واحدة على الأقل للعرض');
      return;
    }

    setState(() { _submitting = true; _progressMsg = 'جارٍ رفع الصور...'; });

    // 📸 صور المصوّر مرفوعة مسبقاً على التخزين ⇒ تُستخدم كما هي بلا رفع ثانٍ،
    // وتتقدّم على أي صور يضيفها الموظف يدوياً.
    List<String> imageUrls = [...(widget.presetImages ?? const <String>[])];
    if (_pickedImages.isNotEmpty) {
      final uploaded = await _storage.uploadOfferImages(
        files: _pickedImages,
        userId: _selectedOwner!.uid,
        onProgress: (d, t) {
          if (mounted) setState(() => _progressMsg = 'الصور ($d/$t)...');
        },
      );
      imageUrls = <String>{...imageUrls, ...uploaded}.toList();
    }

    setState(() => _progressMsg = 'جارٍ رفع السند...');
        String docUrl = '';
    if (_docImage != null) {
      docUrl = (await _storage.uploadOfferImage(
        xfile: _docImage!,
        userId: _selectedOwner!.uid,
        offerId: null,
      )) ?? '';
    }

    setState(() => _progressMsg = 'جارٍ إنشاء العرض...');
    final cityName = _selectedCityArea == _customCityOption
        ? _customCityCtrl.text.trim()
        : (_selectedCityArea?.trim() ?? '');
    final loc = {'r': 0, 'd': _locCtrl.text.trim(), 'city': cityName};

    final customSub = _customSubCtrl.text.trim();
    final catLabel  = customSub.isNotEmpty ? customSub : _catLabel();
    final autoTitle = '$catLabel في $cityName';
    final finalTitle = _ttlCtrl.text.trim().isNotEmpty
        ? _ttlCtrl.text.trim()
        : autoTitle;

    // الوسيط يُحدَّد تلقائياً إذا كان صاحب العرض وسيطاً
    final brkId = _selectedOwner!.role == UserRole.broker
        ? _selectedOwner!.uid
        : '';

    final offer = OfferModel(
      id: '',
      usrId:     _selectedOwner!.uid,
      brkId:     brkId,
      ttl:       finalTitle,
      typ:       _selectedType!,
      trx:       _selectedTrans!,
      cat:       _selectedMainCat!,
      sub:       (_selectedSubCat == null || _selectedSubCat == -1) ? 0 : _selectedSubCat!,
      contactPh: effectivePhone,
      prc:       price,
      cur:       _cur,
      loc:       loc,
      descript:  _descCtrl.text.trim().isNotEmpty
                   ? _descCtrl.text.trim()
                   : _locCtrl.text.trim(),
      // ⚠️ لا يُوضع وسم «مُصوَّر من المكتب» داخل specs: العمود مقروء anon عبر
      // REST ⇒ أي وسم فيه يتسرّب للزائر (مُثبت حيّاً 2026-07-29 — نفس درس doc_img).
      // المصدر الموثوق للتنويه هو photography_tasks.off_id المحمي، ويُقرأ عبر
      // إيدج admin-photography: offer_photo_info بحارس دور.
      specs:     {'details': _specCtrl.text, if (customSub.isNotEmpty) 'custom_sub': customSub},
      imgs:      imageUrls,
      vdo:       '',
      exactLoc:  _pickedLocation != null
                   ? '${_pickedLocation!.latitude},${_pickedLocation!.longitude}'
                   : '',
      docTp:     _selectedDocType ?? 0,
      docImg:    docUrl,
      avl:       _buildAvl(),
      addedBy:   admin.uid,  // ← من أضاف العرض (الموظف/المدير)
      sts:       OfferStatus.review,
      iPub:      0,
      tsCrt:     DateTime.now(),
    );

    OfferModel? created;
    try {
      // نستخدم RPC مخصصة للإدارة لتمرير added_by
      final res = await SupabaseService().invokeFunction('admin-offers', body: {'action': 'create_for_user', 'user_id': _selectedOwner!.uid, 'offer': {...offer.toMap(), 'added_by': admin.uid}, 'admin_uid': admin.uid}); final data = res.data as Map; final response = data['offer_id'];
      if (response != null && (response is List) && response.isNotEmpty) {
        final row = Map<String, dynamic>.from(response.first as Map);
        created = OfferModel.fromSupabase(row, row['id'] as String);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        _snack('فشل في إنشاء العرض: $e');
      }
      return;
    }

    if (created == null) {
      if (mounted) setState(() => _submitting = false);
      _snack('فشل إنشاء العرض، حاول مجدداً');
      return;
    }

    // 📸 القادم من مهمة تصوير: نشر مباشر + ربط المهمة وإغلاقها (قرار المالك).
    // ملاحظة: create_offer_internal تفرض sts=1 دائماً (حارس سيرفري لا يُضعَّف)،
    // لذا ننشر عبر مسار الاعتماد الرسمي admin-offers: review — نفس ما يفعله المدير.
    if (widget.isFromPhotoTask) {
      setState(() => _progressMsg = 'جارٍ نشر العرض...');
      var published = false;
      try {
        final res = await SupabaseService().invokeFunction('admin-offers', body: {
          'action': 'review',
          'admin_uid': admin.uid,
          'offer_id': created.id,
          'approve': true,
        });
        final d = res.data;
        published = d is Map && (d['success'] == true || d['result'] == true);
      } catch (_) {
        published = false;
      }

      // ربط المهمة بالعرض وإغلاقها (معتمدة) — عبر إيدج التصوير
      try {
        await SupabaseService().invokeFunction('admin-photography', body: {
          'action': 'link_offer',
          'admin_uid': admin.uid,
          'task_id': widget.photoTaskId,
          'offer_id': created.id,
        });
      } catch (_) {
        // الربط إثراء — فشله لا يُبطل العرض المنشور
      }

      if (mounted) setState(() => _submitting = false);
      if (mounted) Navigator.pop(context, true);
      _snack(published
          ? '✅ تم إنشاء العرض ونشره وربطه بمهمة التصوير'
          : '⚠️ أُنشئ العرض وربط بالمهمة — لكن النشر لم يكتمل، راجعه من «مراجعة العروض»');
      return;
    }

    if (mounted) setState(() => _submitting = false);
    if (mounted) Navigator.pop(context);
    _snack('✅ تم إنشاء العرض وإرساله للمراجعة');
  }

  void _snack(String m) {
    if (!mounted) return;
    AppTheme.showSnackBar(context, SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إضافة عرض — الإدارة'),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          Stepper(
            type: StepperType.vertical,
            currentStep: _currentStep,
            onStepTapped: (s) => setState(() => _currentStep = s),
            controlsBuilder: (_, __) => const SizedBox.shrink(),
            steps: [
              _stepOwner(),
              _stepBasics(),
              _stepDetails(),
              _stepMedia(),
              _stepAvl(),
              _stepDoc(),
            ],
          ),
          if (_submitting)
            Container(
              color: const Color.fromRGBO(0, 0, 0, 0.7),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: AppTheme.primaryGold),
                    AppTheme.gapHeightLarge,
                    Text(_progressMsg,
                        style: const TextStyle(color: AppTheme.textWhite)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Step 0: اختيار صاحب العرض ───
  Step _stepOwner() {
    final query = _ownerSearchCtrl.text.toLowerCase();
    final filtered = _users.where((u) {
      return u.nm.toLowerCase().contains(query) ||
          u.ph.contains(query);
    }).toList();

    return Step(
      title: Row(children: [
        const Text('صاحب العرض',
            style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        if (_selectedOwner != null) ...[
          AppTheme.gapWidthSmall,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.successGreen.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _selectedOwner!.nm.isNotEmpty ? _selectedOwner!.nm : _selectedOwner!.ph,
              style: const TextStyle(color: AppTheme.successGreen, fontSize: AppTheme.fontSizeSmall),
            ),
          ),
        ],
      ]),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // تنويه داخلي
          Container(
            padding: AppTheme.paddingAllMedium,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: AppTheme.radiusSmall,
              border: Border.all(color: Colors.amber.withOpacity(0.4)),
            ),
            child: const Row(children: [
              Icon(Icons.admin_panel_settings, color: Colors.amber, size: 16),
              AppTheme.gapWidthSmall,
              Expanded(
                child: Text(
                  'العرض يُضاف من الإدارة — سيُسجَّل من أضافه داخلياً.',
                  style: TextStyle(color: Colors.amber, fontSize: AppTheme.fontSizeSmall),
                ),
              ),
            ]),
          ),
          TextField(
            controller: _ownerSearchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'بحث عن المستخدم (الاسم أو الهاتف)',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
          AppTheme.gapHeightSmall,
          _loadingUsers
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGold))
              : SizedBox(
                  height: 220,
                  child: filtered.isEmpty
                      ? const Center(child: Text('لا يوجد مستخدم',
                          style: TextStyle(color: AppTheme.textGrey)))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final u = filtered[i];
                            final selected = _selectedOwner?.uid == u.uid;
                            return ListTile(
                              dense: true,
                              selected: selected,
                              selectedTileColor:
                                  AppTheme.primaryGold.withOpacity(0.1),
                              leading: CircleAvatar(
                                backgroundColor: AppTheme.primaryGold,
                                radius: 16,
                                child: Text(
                                  u.nm.isNotEmpty ? u.nm[0].toUpperCase() : '؟',
                                  style: const TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: AppTheme.fontSizeMedium),
                                ),
                              ),
                              title: Text(
                                u.nm.isNotEmpty ? u.nm : 'مجهول',
                                style: const TextStyle(
                                    color: AppTheme.textWhite, fontSize: AppTheme.fontSizeMedium),
                              ),
                              subtitle: Text(
                                u.ph + (u.role == UserRole.broker ? ' • وسيط' : ''),
                                style: const TextStyle(
                                    color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption),
                              ),
                              trailing: selected
                                  ? const Icon(Icons.check_circle,
                                      color: AppTheme.primaryGold)
                                  : null,
                              onTap: () => setState(() => _selectedOwner = u),
                            );
                          },
                        ),
                ),
          AppTheme.gapHeightMedium,
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedOwner == null
                  ? null
                  : () => setState(() => _currentStep = 1),
              child: const Text('التالي →'),
            ),
          ),
        ],
      ),
      isActive: _currentStep >= 0,
    );
  }

  // ─── Step 1: الأساسيات ───
  Step _stepBasics() {
    final mainCategories = _categoryGroupMap();
    final subCategories = _selectedMainCat != null
        ? _subCategoryMap(_selectedMainCat!)
        : <int, String>{};

    final cityItems = _cityOptions()
        .map((c) => DropdownMenuItem<String>(
              value: c,
              child: Text(c, overflow: TextOverflow.ellipsis),
            ))
        .toList()
      ..add(const DropdownMenuItem<String>(
          value: _customCityOption, child: Text('آخر (إدخال حر)')));

    return Step(
      title: const Text('الأساسيات',
          style: TextStyle(
              color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _dd('نوع العرض', ['عقار', 'سيارة'], _selectedType == null ? null : (_selectedType == 0 ? 'عقار' : 'سيارة'), (v) => setState(() {
                _selectedType = v == 'عقار' ? 0 : 1;
                _selectedMainCat = null;
                _selectedSubCat  = null;
              })),
          AppTheme.gapHeightLarge,
          _dd('نوع المعاملة', ['بيع', 'إيجار'],
              _selectedTrans == null ? null : (_selectedTrans == 0 ? 'بيع' : 'إيجار'),
              (v) => setState(() => _selectedTrans = v == 'بيع' ? 0 : 1)),
          AppTheme.gapHeightLarge,
          DropdownButtonFormField<int>(
            value: _selectedMainCat,
            dropdownColor: AppTheme.surfaceBlack,
            style: const TextStyle(color: AppTheme.textWhite),
            decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'التصنيف الرئيسي'),
            items: mainCategories.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() {
              _selectedMainCat = v;
              _selectedSubCat  = null;
              _customSubCtrl.clear();
            }),
            hint: const Text('اختر التصنيف',
                style: TextStyle(color: AppTheme.textGrey)),
          ),
          if (_selectedMainCat != null) ...[
            AppTheme.gapHeightMedium,
            DropdownButtonFormField<int>(
              value: _selectedSubCat,
              dropdownColor: AppTheme.surfaceBlack,
              style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeMedium),
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), labelText: 'التصنيف الفرعي'),
              items: [
                ...subCategories.entries.map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
                const DropdownMenuItem(value: -1, child: Text('آخر (يدوي)')),
              ],
              onChanged: (v) => setState(() {
                _selectedSubCat = v;
                if (v != -1) _customSubCtrl.clear();
              }),
              hint: const Text('اختر التصنيف الفرعي',
                  style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeMedium)),
            ),
            if (_selectedSubCat == -1)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: TextField(
                  controller: _customSubCtrl,
                  decoration: const InputDecoration(
                      labelText: 'اكتب التصنيف الفرعي يدوياً',
                      border: OutlineInputBorder()),
                ),
              ),
          ],
          AppTheme.gapHeightLarge,
          TextField(
            controller: _contactPhCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'رقم الهاتف للتواصل (إلزامي)',
              hintText: 'رقم جوال صاحب العرض أو المكتب',
              border: OutlineInputBorder(),
            ),
          ),
          AppTheme.gapHeightLarge,
          DropdownButtonFormField<String>(
            value: _selectedCityArea,
            dropdownColor: AppTheme.surfaceBlack,
            style: const TextStyle(color: AppTheme.textWhite),
            decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'المنطقة الرئيسية'),
            items: cityItems,
            onChanged: (v) => setState(() {
              _selectedCityArea = v;
              if (v != _customCityOption) _customCityCtrl.clear();
            }),
            hint: const Text('اختر المنطقة',
                style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeMedium)),
            menuMaxHeight: 300,
          ),
          if (_selectedCityArea == _customCityOption)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextField(
                controller: _customCityCtrl,
                decoration: const InputDecoration(
                    labelText: 'اكتب المنطقة يدوياً',
                    border: OutlineInputBorder()),
              ),
            ),
          AppTheme.gapHeightLarge,
          _buildLocationAutocomplete(),
          AppTheme.gapHeightMedium,
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => setState(() => _currentStep = 2),
              child: const Text('التالي →'),
            ),
          ),
        ]),
      ),
      isActive: _currentStep >= 1,
    );
  }

  // ─── Step 2: التفاصيل ───
  Step _stepDetails() => Step(
        title: const Text('التفاصيل',
            style: TextStyle(
                color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        content: Column(children: [
          TextField(
            controller: _ttlCtrl,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'عنوان مخصص (اختياري)',
              hintText: 'يُبنى تلقائياً إذا تُرك فارغاً',
              border: OutlineInputBorder(),
              counterStyle: TextStyle(color: AppTheme.textGrey),
            ),
          ),
          AppTheme.gapHeightMedium,
          Row(children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'السعر (إلزامي)',
                    border: OutlineInputBorder()),
              ),
            ),
            AppTheme.gapWidthSmall,
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<int>(
                value: _cur,
                dropdownColor: AppTheme.surfaceBlack,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: Currency.dollar, child: Text('دولار')),
                  DropdownMenuItem(value: Currency.lbp, child: Text('ل.س')),
                ],
                onChanged: (v) => setState(() => _cur = v ?? Currency.lbp),
              ),
            ),
          ]),
          AppTheme.gapHeightMedium,
          TextField(
            controller: _descCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'وصف تفصيلي للعرض (اختياري)',
              hintText: 'مميزات العرض، حالته، الطابق، المساحة...',
              border: OutlineInputBorder(),
            ),
          ),
          AppTheme.gapHeightMedium,
          TextField(
            controller: _specCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'المواصفات التقنية (اختيارية)',
              hintText: 'مثال: 3 غرف، 2 حمام، مساحة 150م²، طابق ثالث',
              border: OutlineInputBorder(),
            ),
          ),
          AppTheme.gapHeightMedium,
          // الخريطة
          const Row(children: [
            Icon(Icons.map, color: AppTheme.primaryGold, size: 18),
            SizedBox(width: 6),
            Text('الموقع الدقيق على الخريطة (اختياري)',
                style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeMedium)),
          ]),
          AppTheme.gapHeightSmall,
          LocationPicker(
            initial: _pickedLocation,
            onPicked: (loc) => setState(() => _pickedLocation = loc),
            height: 220,
          ),
          AppTheme.gapHeightMedium,
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => setState(() => _currentStep = 3),
              child: const Text('التالي →'),
            ),
          ),
        ]),
        isActive: _currentStep >= 2,
      );

  // ─── Step 3: الصور ───
  Step _stepMedia() => Step(
        title: const Text('الصور',
            style: TextStyle(
                color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ElevatedButton.icon(
            onPressed: _pickImages,
            icon: const Icon(Icons.add_photo_alternate),
            label: Text(
                'إضافة صور (${_pickedImages.length}/${StorageService.maxImages})'),
          ),
          AppTheme.gapHeightSmall,
          if (_pickedImages.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _pickedImages.asMap().entries.map((e) {
                return Stack(children: [
                  ClipRRect(
                      borderRadius: AppTheme.radiusSmall,
                      child: _thumb(e.value)),
                  Positioned(
                    top: -8, left: -8,
                    child: IconButton(
                      icon: const Icon(Icons.cancel, color: AppTheme.errorRed),
                      onPressed: () =>
                          setState(() => _pickedImages.removeAt(e.key)),
                    ),
                  ),
                ]);
              }).toList(),
            ),
          AppTheme.gapHeightMedium,
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => setState(() => _currentStep = 4),
              child: const Text('التالي →'),
            ),
          ),
        ]),
        isActive: _currentStep >= 3,
      );

  // ─── Step 4: المواعيد المتاحة (avl) ───
  Step _stepAvl() => Step(
        title: const Text('المواعيد المتاحة',
            style: TextStyle(
                color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('حدد الأيام والفترات الزمنية المتاحة للمعاينة.',
                style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody)),
            AppTheme.gapHeightLarge,
            ..._weekDays.map((day) {
              final key     = day.$1;
              final label   = day.$2;
              final enabled = _avlDaysEnabled[key] ?? false;
              final slots   = _avlSlots[key] ?? [];
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBlack,
                  borderRadius: AppTheme.radiusMedium,
                  border: Border.all(
                    color: enabled
                        ? AppTheme.primaryGold.withOpacity(0.5)
                        : Colors.white12,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => setState(() {
                        _avlDaysEnabled[key] = !enabled;
                        if (!enabled && slots.isEmpty) {
                          _avlSlots[key]!.add({'from': '', 'to': ''});
                        }
                      }),
                      borderRadius: AppTheme.radiusMedium,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(children: [
                          Icon(
                            enabled
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            color: enabled
                                ? AppTheme.primaryGold
                                : AppTheme.textGrey,
                            size: 20,
                          ),
                          AppTheme.gapWidthSmall,
                          Text(label,
                              style: TextStyle(
                                color: enabled
                                    ? AppTheme.textWhite
                                    : AppTheme.textGrey,
                                fontWeight: FontWeight.bold,
                              )),
                          const Spacer(),
                          if (enabled)
                            TextButton.icon(
                              onPressed: () => setState(() {
                                _avlSlots[key]!.add({'from': '', 'to': ''});
                              }),
                              icon: const Icon(Icons.add,
                                  size: 16, color: AppTheme.primaryGold),
                              label: const Text('فترة',
                                  style: TextStyle(
                                      color: AppTheme.primaryGold,
                                      fontSize: AppTheme.fontSizeSmall)),
                              style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero),
                            ),
                        ]),
                      ),
                    ),
                    if (enabled)
                      ...slots.asMap().entries.map((e) {
                        final i    = e.key;
                        final slot = e.value;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          child: Row(children: [
                            const Text('من',
                                style: TextStyle(
                                    color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _timeField(
                                value: slot['from'] ?? '',
                                hint: '09:00',
                                onChanged: (v) => setState(
                                    () => _avlSlots[key]![i]['from'] = v),
                              ),
                            ),
                            AppTheme.gapWidthSmall,
                            const Text('إلى',
                                style: TextStyle(
                                    color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _timeField(
                                value: slot['to'] ?? '',
                                hint: '12:00',
                                onChanged: (v) => setState(
                                    () => _avlSlots[key]![i]['to'] = v),
                              ),
                            ),
                            AppTheme.gapWidthXS,
                            IconButton(
                              icon: const Icon(Icons.remove_circle,
                                  color: AppTheme.errorRed, size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => setState(() {
                                _avlSlots[key]!.removeAt(i);
                                if (_avlSlots[key]!.isEmpty) {
                                  _avlDaysEnabled[key] = false;
                                }
                              }),
                            ),
                          ]),
                        );
                      }),
                    if (enabled) AppTheme.gapHeightSmall,
                  ],
                ),
              );
            }),
            AppTheme.gapHeightMedium,
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => setState(() => _currentStep = 5),
                child: const Text('التالي →'),
              ),
            ),
          ],
        ),
        isActive: _currentStep >= 4,
      );

  // ─── Step 5: السند والإرسال ───
  Step _stepDoc() {
    final config   = context.watch<ConfigProvider>().config;
    final docTypes = config?.documentTypes ?? {};

    return Step(
      title: const Text('السند والإرسال',
          style: TextStyle(
              color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
      content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('نوع سند الملكية (إلزامي)',
            style: TextStyle(
                color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          value: _selectedDocType,
          dropdownColor: AppTheme.surfaceBlack,
          style: const TextStyle(color: AppTheme.textWhite),
          decoration: const InputDecoration(border: OutlineInputBorder()),
          hint: const Text('اختر نوع السند',
              style: TextStyle(color: AppTheme.textGrey)),
          items: docTypes.entries
              .map((e) => DropdownMenuItem(
                    value: int.tryParse(e.key) ?? 0,
                    child: Text(e.value.toString()),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _selectedDocType = v),
        ),
        AppTheme.gapHeightMedium,
        const Text('صورة سند الملكية (اختيارية)',
            style: TextStyle(
                color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _pickDocImage,
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              color: AppTheme.surfaceBlack,
              borderRadius: AppTheme.radiusMedium,
              border: Border.all(
                color: _docImage != null
                    ? AppTheme.successGreen.withOpacity(0.4)
                    : AppTheme.primaryGold.withOpacity(0.3),
              ),
            ),
            child: _docImage == null
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.upload_file,
                            color: AppTheme.primaryGold, size: 32),
                        AppTheme.gapHeightXS,
                        Text('اضغط لرفع صورة السند',
                            style: TextStyle(
                                color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
                      ],
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: kIsWeb
                        ? Image.network(_docImage!.path,
                            fit: BoxFit.cover, width: double.infinity)
                        : Image.file(File(_docImage!.path),
                            fit: BoxFit.cover, width: double.infinity),
                  ),
          ),
        ),
        AppTheme.gapHeightXL,
        // تنويه داخلي
        Container(
          padding: AppTheme.paddingAllMedium,
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.08),
            borderRadius: AppTheme.radiusSmall,
            border: Border.all(color: Colors.amber.withOpacity(0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline, color: Colors.amber, size: 16),
            AppTheme.gapWidthSmall,
            Expanded(
              child: Text(
                'تنويه داخلي: هذا العرض أُضيف من قِبل ${context.read<AuthProvider>().userModel?.nm ?? "الإدارة"}',
                style: const TextStyle(color: Colors.amber, fontSize: AppTheme.fontSizeSmall),
              ),
            ),
          ]),
        ),
        AppTheme.gapHeightLarge,
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: const Text('إرسال العرض للمراجعة',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
      isActive: _currentStep >= 5,
    );
  }

  // ── مساعدات ──

  Widget _timeField({required String value, required String hint, required void Function(String) onChanged}) {
    final ctrl = TextEditingController(text: value)
      ..selection = TextSelection.collapsed(offset: value.length);
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.datetime,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeMedium),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      ),
      onChanged: onChanged,
    );
  }

  Future<void> _pickImages() async {
    final remaining = StorageService.maxImages - _pickedImages.length;
    if (remaining <= 0) { _snack('الحد الأقصى ${StorageService.maxImages} صور'); return; }
    final files = await _storage.pickMultiImages(limit: remaining);
    if (files.isNotEmpty) setState(() => _pickedImages.addAll(files));
  }

  Future<void> _pickDocImage() async {
    final file = await _storage.pickImage(fromCamera: false);
    if (file != null) setState(() => _docImage = file);
  }

  Widget _thumb(XFile file) {
    final err = Container(
        width: 70, height: 70, color: AppTheme.surfaceBlack,
        child: const Icon(Icons.image, color: AppTheme.primaryGold));
    if (kIsWeb) {
      return Image.network(file.path,
          width: 70, height: 70, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => err);
    }
    return Image.file(File(file.path),
        width: 70, height: 70, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => err);
  }

  String _catLabel() {
    if (_selectedMainCat == null) return 'عرض';
    final config = context.read<ConfigProvider>().config;
    final source = _selectedType == 1
        ? config?.vehicleCategories
        : config?.propertyCategories;
    if (source != null) {
      final main = source['$_selectedMainCat'];
      if (main is Map) {
        final subs = main['sub'] ?? main['children'];
        if (subs is List && _selectedSubCat != null &&
            _selectedSubCat! >= 0 && _selectedSubCat! < subs.length) {
          return subs[_selectedSubCat!].toString();
        }
        return main['nm']?.toString() ?? 'عرض';
      }
    }
    return _selectedType == 1 ? 'مركبة' : 'عقار';
  }

  Map<int, String> _categoryGroupMap() {
    final config = context.read<ConfigProvider>().config;
    final cats = _selectedType == 1 ? config?.vehicleCategories : config?.propertyCategories;
    if (cats != null && cats.isNotEmpty) {
      return (cats as Map).map((k, v) {
        final id = int.tryParse(k.toString()) ?? 0;
        final name = v is Map
            ? (v['nm']?.toString() ?? v.toString())
            : v.toString();
        return MapEntry(id, name);
      });
    }
    return {0: _selectedType == 1 ? 'مركبة' : 'عقار'};
  }

  Map<int, String> _subCategoryMap(int mainId) {
    final config = context.read<ConfigProvider>().config;
    final cats = _selectedType == 1 ? config?.vehicleCategories : config?.propertyCategories;
    final main = cats?['$mainId'];
    if (main is Map) {
      final subs = main['sub'] ?? main['children'];
      if (subs is List) {
        final result = <int, String>{};
        for (int i = 0; i < subs.length; i++) {
          result[i] = subs[i].toString();
        }
        return result;
      }
    }
    return {mainId: _categoryGroupMap()[mainId] ?? '—'};
  }

  List<String> _cityOptions() {
    final config = context.read<ConfigProvider>().config;
    return (config?.locations ?? [])
        .map((item) {
          if (item is String) return item.trim();
          if (item is Map) return (item['name'] ?? item['d'] ?? '').toString().trim();
          return item.toString().trim();
        })
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  Widget _buildLocationAutocomplete() {
    final locs = _cityOptions();
    return Autocomplete<String>(
      optionsBuilder: (v) {
        if (locs.isEmpty) return const Iterable<String>.empty();
        if (v.text.isEmpty) return locs.take(20);
        return locs.where((s) => s.toLowerCase().contains(v.text.toLowerCase()));
      },
      fieldViewBuilder: (ctx, ctrl, fn, _) {
        ctrl.text = _locCtrl.text;
        return TextField(
          controller: ctrl,
          focusNode: fn,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'وصف دقيق للموقع (إلزامي)',
            hintText: 'الحي، الشارع، المبنى...',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => _locCtrl.text = v,
        );
      },
      onSelected: (s) => setState(() => _locCtrl.text = s),
    );
  }

  Widget _dd(String label, List<String> items, String? value, Function(String) on) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: AppTheme.textGrey)),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          value: value, // كانت null دائماً — القائمة تظهر فاضية بعد الاختيار
          items: items
              .map((i) => DropdownMenuItem(value: i, child: Text(i)))
              .toList(),
          onChanged: (v) => on(v!),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      ]);
}

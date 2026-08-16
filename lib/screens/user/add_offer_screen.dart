import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/offer_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../core/constants/db_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/offer_model.dart';
import '../../services/storage_service.dart';
import '../../core/validation/input_validators.dart';
import '../../widgets/location_picker.dart';
import 'package:latlong2/latlong.dart';
import '../../core/network/supabase_service.dart';
import '../../core/utils/error_utils.dart';

class AddOfferScreen extends StatefulWidget {
  /// 📸 وضع طلب التصوير: يفتح شاشة إضافة العرض الكاملة مع تعديلات:
  /// - 3 خطوات فقط (أساسيات + تفاصيل/خريطة إلزامية + صور + إرسال)
  /// - إخفاء السند/العمولة/الإقرار/السوشيال/الفيديو/مواعيد المعاينة
  /// - الخريطة إلزامية (ليست اختيارية)
  /// - الزر: «إرسال طلب التصوير» بدل «نشر العرض»
  /// - بعد الحفظ: يُنشأ عرض مراجعة + مهمة تصوير مرتبطة
  final bool isPhotographyRequest;

  const AddOfferScreen({super.key, this.isPhotographyRequest = false});
  @override
  State<AddOfferScreen> createState() => _AddOfferScreenState();
}

class _AddOfferScreenState extends State<AddOfferScreen> {
  static const String _customCityOption = '__custom_city__';

  /// نص الإقرار والتعهد الكامل — يجب أن يقرأه المستخدم قبل الموافقة
  /// نص الإقرار والتعهد — يتغير حسب الدور (الوسيط معفى من العمولة)
  String get _pledgeFullText {
    final isBroker = context.read<AuthProvider>().isBroker;
    if (isBroker) {
      return 'أقرّ أنا الوسيط صاحب هذا العرض وأتعهد بما يلي:\n'
          '١) جميع البيانات المدخلة (النوع، المواصفات، السعر، الموقع، الصور، السند) صحيحة ودقيقة، وأتحمّل كامل المسؤولية القانونية عن أي خطأ أو تضليل فيها.\n'
          '٢) أنا المالك الشرعي للعقار/المركبة أو مخوَّل رسمياً بعرضه، وهو خالٍ من أي إشارات أو نزاعات تمنع البيع أو الإيجار.\n'
          '٣) أقرّ بأنني وسيط معتمد وبأن عروضي معفاة من عمولة المكتب.\n'
          '٤) ألتزم بعدم الالتفاف على المكتب بإتمام المعاملة مباشرةً مع الزبائن دون علمه.\n'
          '٥) يحق للإدارة حذف العرض أو تقييد الحساب عند ثبوت أي مخالفة لما تقدّم.';
    }
    return 'أقرّ أنا صاحب هذا العرض وأتعهد بما يلي:\n'
        '١) جميع البيانات المدخلة (النوع، المواصفات، السعر، الموقع، الصور، السند) صحيحة ودقيقة، وأتحمّل كامل المسؤولية القانونية عن أي خطأ أو تضليل فيها.\n'
        '٢) أنا المالك الشرعي للعقار/المركبة أو مخوَّل رسمياً بعرضه، وهو خالٍ من أي إشارات أو نزاعات تمنع البيع أو الإيجار.\n'
        '٣) ألتزم بتسديد عمولة المكتب كاملةً عند إتمام الصفقة عبره أو بوساطته — ٣٪ من قيمة البيع، وما يعادل أجرة نصف شهر عند الإيجار — ولو تمّت المعاملة لاحقاً مع طرف تعرّفت عليه عبر التطبيق.\n'
        '٤) أتعهد بعدم الالتفاف على المكتب بإتمام المعاملة مباشرةً مع الزبائن دون علمه.\n'
        '٥) يحق للإدارة حذف العرض أو تقييد الحساب عند ثبوت أي مخالفة لما تقدّم.';
  }

  int _currentStep = 0;

  /// تحكّم بتمرير الـ Stepper — بدونه عند الانتقال لخطوة جديدة يبقى الـ ListView
  /// على موضعه القديم فيفتح المستخدم الخطوة من نص الشاشة ويضطر يطلع يدوياً
  final ScrollController _stepScroll = ScrollController();

  /// انتقال لخطوة + إعادة التمرير للأعلى (بعد اكتمال بناء الفريم)
  void _goToStep(int step) {
    setState(() => _currentStep = step);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_stepScroll.hasClients) return;
      _stepScroll.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }
  int? _selectedType;
  int? _selectedTrans;
  int? _selectedMainCat;
  int? _selectedSubCat;
  String? _selectedCityArea;
  int _cur = Currency.lbp;
  final _priceCtrl = TextEditingController();
  final _locCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _ttlCtrl  = TextEditingController();
  final _customSubCtrl = TextEditingController();
  final _contactPhoneCtrl = TextEditingController();
  final _customCityCtrl = TextEditingController();
  /// إدخال حر لمنطقة السيارة عند اختيار «آخر (إدخال حر)»
  final _carCustomCityCtrl = TextEditingController();

  final List<XFile> _pickedImages = [];
  XFile? _docImage;
  LatLng? _pickedLocation;
  int? _selectedDocType;
  bool _agreePledge = false;
  bool _submitting = false;
  // افتراضي «جاهز بأي وقت» بقرار المالك — أقل احتكاك للمستخدم؛ التخصيص بالأيام اختياري (بطفّي السويتش)
  bool _anytimeReady = true;
  bool _wantVideo = false; // تشك بوكس إرفاق الفيديو عبر واتساب المكتب

  // checkbox للنشر التلقائي على السوشيال (مفعل افتراضياً)
  bool _autoPublishSocial = true;

  final _carBrandCtrl = TextEditingController();
  final _carModelCtrl = TextEditingController();
  final _carYearCtrl = TextEditingController();
  final _carColorCtrl = TextEditingController();
  final _carKmCtrl = TextEditingController();
  final _carPlateCtrl = TextEditingController();
  String? _carFuel;
  String? _carTransmission;
  /// منطقة تواجد السيارة — إلزامية (نفس مفهوم «المنطقة الرئيسية» للعقار)
  String? _carCityArea;
  int? _selectedCarDocType;
  int? _selectedPlateType;

  final _areaCtrl = TextEditingController();
  final _floorCtrl = TextEditingController();
  final _legalNotesCtrl = TextEditingController();
  String? _finishing;
  String? _direction;
  String _progressMsg = '';

  static const _weekDays = [
    ('mon', 'الاثنين'), ('tue', 'الثلاثاء'), ('wed', 'الأربعاء'),
    ('thu', 'الخميس'), ('fri', 'الجمعة'), ('sat', 'السبت'), ('sun', 'الأحد'),
  ];
  final Map<String, bool> _avlDaysEnabled = {
    'mon': false, 'tue': false, 'wed': false, 'thu': false, 'fri': false, 'sat': false, 'sun': false,
  };
  final Map<String, List<Map<String, String>>> _avlSlots = {
    'mon': [], 'tue': [], 'wed': [], 'thu': [], 'fri': [], 'sat': [], 'sun': [],
  };

  Map<String, List<String>> _buildAvl() {
    if (_anytimeReady) return {'any': ['00:00-23:59']};
    final result = <String, List<String>>{};
    for (final day in _weekDays) {
      final key = day.$1;
      if (_avlDaysEnabled[key] == true) {
        final slots = _avlSlots[key]!
            .where((s) => s['from']!.isNotEmpty && s['to']!.isNotEmpty)
            .map((s) => '${s['from']}-${s['to']}')
            .toList();
        // يوم مفعّل بلا فترة مكتملة يُهمل بالكامل — كان يُكتب كمصفوفة فارغة
        // {"mon":[]} فيصير الزر مفعّل (avl مو فارغة) بس ما في أي فترة للحجز
        if (slots.isNotEmpty) result[key] = slots;
      }
    }
    return result;
  }

  final _storage = StorageService();

  // ✅ Fix for Bug #2: Store time field controllers to prevent recreation on each build
  final Map<String, TextEditingController> _timeControllers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ConfigProvider>().loadConfig();
      // تعبئة تلقائية لرقم الهاتف من حساب المستخدم
      final user = context.read<AuthProvider>().userModel;
      if (user != null && user.ph.isNotEmpty) {
        // 📞 PHONE-001: القاعدة تخزّن +963… والتحقق يطلب 09… ⇒ نُطبّع
        // عند التعبئة، وإلا رُفض الطلب دائماً بـ«هاتف سوري غير صحيح».
        _contactPhoneCtrl.text = InputValidators.toLocalSyrianPhone(user.ph);
      }
    });
  }

  @override
  void dispose() {
    _priceCtrl.dispose(); _locCtrl.dispose(); _descCtrl.dispose();
    _ttlCtrl.dispose(); _customSubCtrl.dispose(); _contactPhoneCtrl.dispose();
    _customCityCtrl.dispose(); _carBrandCtrl.dispose(); _carModelCtrl.dispose();
    _carYearCtrl.dispose(); _carColorCtrl.dispose(); _carKmCtrl.dispose();
    _carPlateCtrl.dispose(); _areaCtrl.dispose(); _floorCtrl.dispose(); _legalNotesCtrl.dispose();
    _carCustomCityCtrl.dispose();
    _stepScroll.dispose();
    
    // ✅ Dispose all time controllers
    for (final controller in _timeControllers.values) {
      controller.dispose();
    }
    
    super.dispose();
  }

  // ✅ Helper method to get or create a persistent time controller
  TextEditingController _getTimeController(String dayKey, int slotIndex, String field) {
    final controllerKey = '${dayKey}_${slotIndex}_$field';
    if (!_timeControllers.containsKey(controllerKey)) {
      _timeControllers[controllerKey] = TextEditingController();
    }
    return _timeControllers[controllerKey]!;
  }


  Future<void> _pickDocImage() async {
    final file = await _storage.pickImage(fromCamera: false);
    if (file != null) setState(() => _docImage = file);
  }

  Future<String?> _uploadDocImage(String userId) async {
    if (_docImage == null) return null;
    try {
      return await _storage.uploadOfferImage(
        xfile: _docImage!,
        userId: userId,
        offerId: null, // سيتم تعيينه لاحقًا في Edge Function
      );
    } catch (e) {
      return null;
    }
  }

  Future<void> _pickImages() async {
    final remaining = StorageService.maxImages - _pickedImages.length;
    if (remaining <= 0) {
      _snack('الحد الأقصى ${StorageService.maxImages} صور');
      return;
    }
    final files = await _storage.pickMultiImages(limit: remaining);
    if (files.isNotEmpty) setState(() => _pickedImages.addAll(files));
  }

  /// فتح وجهة إرسال فيديو العرض — المالك يرسل الفيديو لمجموعة واتساب المكتب
  /// رابط واتساب الفيديو: مجموعة ← رقم خاص wa.me (مع نص جاهز) ← المفتاح القديم (توافقية).
  /// يعيد null إذا لم تضبط الإدارة أي وجهة. (الفيديو لا يُرفع لـ storage إطلاقاً)
  String? _videoWhatsAppUrl(String message) {
    final cfg = context.read<ConfigProvider>().config;
    final groupLink = (cfg?.videoRequestGroupLink ?? '').trim();
    if (groupLink.isNotEmpty) {
      return groupLink.startsWith('http') ? groupLink : 'https://$groupLink';
    }
    final dedicated = (cfg?.videoRequestWhatsApp ?? '').trim();
    if (dedicated.isNotEmpty) {
      var target = dedicated.replaceAll(RegExp(r'[^0-9]'), '');
      if (target.startsWith('0')) target = '963${target.substring(1)}';
      if (!target.startsWith('963')) target = '963$target';
      return 'https://wa.me/$target?text=${Uri.encodeComponent(message)}';
    }
    final old = (cfg?.texts['videoWhatsAppGroup']?.toString() ?? '').trim();
    if (old.isNotEmpty) return old.startsWith('http') ? old : 'https://$old';
    return null;
  }

  /// فتح واتساب المكتب مع نص تعريفي. بعد حفظ العرض يُمرّر رقمه فيُذكر حرفياً بالرسالة.
  /// true=انفتح واتساب، false=لا وجهة مضبوطة أو واتساب غير متاح.
  Future<bool> _launchVideoWhatsApp({int? offerNum}) async {
    final u = context.read<AuthProvider>().userModel;
    final phone = _contactPhoneCtrl.text.trim().isNotEmpty
        ? _contactPhoneCtrl.text.trim()
        : (u?.ph ?? '');
    final title = _ttlCtrl.text.trim();
    
    // ✅ Fix for Bug #3: استخدام اسم المستخدم (usr) إذا كان الاسم (nm) فارغاً
    // عند تسجيل حساب جديد عبر الهاتف أو الإيميل، يكون الاسم فارغاً حتى يحدده المستخدم
    // في هذه الحالة نستخدم اسم المستخدم (usr) الذي يتم تحديده عند إعداد الحساب
    final advertiserName = (u?.nm != null && u!.nm.trim().isNotEmpty) 
        ? u.nm 
        : (u?.usr ?? 'مستخدم');
    
    final msg = offerNum != null
        ? '🎬 فيديو للعرض #$offerNum\nالعنوان: $title\nالمعلن: $advertiserName\nالهاتف: $phone'
        : '🎬 فيديو عرض جديد\nالعنوان: $title\nالمعلن: $advertiserName\nالهاتف: $phone';
    final url = _videoWhatsAppUrl(msg);
    if (url == null) return false;
    try {
      final uri = Uri.parse(url);
      if (!await canLaunchUrl(uri)) return false;
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    final offerProv = context.read<OfferProvider>();
    final user = auth.userModel;
    if (user == null) { _snack('يجب تسجيل الدخول'); return; }

    if (_selectedType == null || _selectedTrans == null || _selectedMainCat == null ||
        (!widget.isPhotographyRequest && _selectedDocType == null)) {
      _snack(widget.isPhotographyRequest
          ? 'يرجى إكمال البيانات الأساسية'
          : 'يرجى إكمال البيانات الأساسية واختيار نوع السند');
      return;
    }

    // في طلب التصوير لا نطلب موقعاً دقيقاً أو خريطة؛ يتم التنسيق هاتفياً.

    // ═══════════════════════════════════════════════════════════════
    // 🖼️ IMG-001 (2026-08-15): صورة واحدة على الأقل — قرار المالك
    // ═══════════════════════════════════════════════════════════════
    // كان هنا سطر «إزالة شرط إلزامية الصورة (أصبحت اختيارية)». النتيجة:
    // 4 عروض منشورة بلا أي صورة بالإنتاج. القاعدة الجديدة تفرضها خادمياً
    // (`create_offer_internal`)، ونفرضها هنا أيضاً لتجيء الرسالة بالعربية
    // قبل رفع أي ملف بدل خطأ تقني بعد انتظار طويل.
    //
    // الاستثناء الوحيد: **طلب التصوير** — العرض يُنشأ ليأتي المصوّر
    // ويصوّره، فطلب صورة من المستخدم هنا يُلغي الخدمة من أساسها.
    if (!widget.isPhotographyRequest && _pickedImages.isEmpty) {
      _snack('يرجى إضافة صورة واحدة على الأقل للعرض');
      return;
    }

    // 📞 PHONE-001: التطبيع قبل الفحص — يقبل ما كتبه المستخدم بأي صيغة
    // (+963 / 00963 / 963 / 09) ويحوّله للمحلية، فلا يُرفض رقم صحيح.
    final effectivePhone = InputValidators.toLocalSyrianPhone(
        _contactPhoneCtrl.text.trim().isNotEmpty ? _contactPhoneCtrl.text.trim() : user.ph);
    if (!InputValidators.isValidSyrianMobile(effectivePhone)) { _snack('يرجى إدخال رقم هاتف سوري صحيح (09xxxxxxxx)'); return; }

    // حقول السيارة الإلزامية — اللوحة إلزامية بتسميتها لكن لم يكن هناك فرض برمجي، والمنطقة إلزامية بطلب المالك
    String? carCity;
    if (_selectedType == 1) {
      if (_carPlateCtrl.text.trim().isEmpty) { _snack('يرجى إدخال رقم اللوحة والمحافظة (إلزامي)'); return; }
      carCity = _carCityArea == _customCityOption ? _carCustomCityCtrl.text.trim() : (_carCityArea ?? '');
      if (carCity.isEmpty) { _snack('يرجى اختيار المنطقة الرئيسية للسيارة (إلزامي)'); return; }
    }

    // التوفر إلزامي — عرض بلا مواعيد معاينة = زر حجز يعمل ورسالة «لا توجد مواعيد متاحة حالياً»
    // (نفس البلاغ اللي صار على العروض المضافة قبل هالإصلاح — avl كانت تُحفظ {} بصمت)
    // 📸 وضع التصوير: المواعيد تُحدد لاحقاً عند إسناد المصوّر — لا نطلبها هنا
    final avlMap = widget.isPhotographyRequest ? {'any': ['00:00-23:59']} : _buildAvl();
    if (!widget.isPhotographyRequest && avlMap.isEmpty) {
      if (_selectedType != 1) _goToStep(3); // خطوة التوفر موجودة فقط بمسار العقارات
      _snack('حدد مواعيد المعاينة: فعّل «أنا جاهز للمعاينة في أي وقت» أو اختر يوماً واحداً على الأقل مع فترة مكتملة (من — إلى)');
      return;
    }

    setState(() { _submitting = true; _progressMsg = 'جاري رفع البيانات...'; });
    final docUrl = await _uploadDocImage(user.uid) ?? '';

    List<String> imageUrls = [];
    if (_pickedImages.isNotEmpty) {
      String? uploadError;
      try {
        imageUrls = await _storage.uploadOfferImages(files: _pickedImages, userId: user.uid, onProgress: (done, total) {
          if (mounted) setState(() => _progressMsg = 'جاري رفع الصور ($done/$total)...');
        });
      } catch (e) {
        // uploadOfferImages يرمي استثناء عند فشل كل الصور — كان يُكسر هنا سابقاً بدون التقاط
        // فيبقى المستخدم عالقاً على شاشة "جاري رفع الصور" للأبد
        uploadError = _storage.lastError ?? e.toString();
      }
      // فشل كل الصور → نوقف ونطلب إعادة المحاولة (لا ننشر عرضاً بدون صور رغماً عن المستخدم)
      if (imageUrls.isEmpty) {
        if (mounted) {
          setState(() { _submitting = false; _progressMsg = ''; });
          _snack('❌ فشل رفع الصور: ${uploadError ?? 'تحقق من الاتصال وحاول مجدداً'} — أعد المحاولة');
        }
        return;
      }
      // نجاح جزئي → نكمل بالصور الناجحة ونوضح للمستخدم
      if (imageUrls.length < _pickedImages.length) {
        _snack('تم رفع ${imageUrls.length} من ${_pickedImages.length} صور — سينشر العرض بالصور الناجحة');
      }
    }

    final loc = _selectedType == 1 ? {'r': 0, 'd': '', 'city': carCity ?? ''} : {'r': 0, 'd': _locCtrl.text, 'city': _selectedCityArea == _customCityOption ? _customCityCtrl.text : _selectedCityArea};

    // ── توليد نص المنشور الجاهز للسوشيال (فيسبوك + إنستغرام)
    final socialText = _generateSocialPostText();

    final offer = OfferModel(
      id: '', usrId: user.uid, ttl: _ttlCtrl.text.isNotEmpty ? _ttlCtrl.text : 'عرض جديد',
      typ: _selectedType!, trx: _selectedTrans!, cat: _selectedMainCat!, sub: _selectedSubCat ?? 0,
      contactPh: effectivePhone, prc: double.tryParse(InputValidators.normalizeDigits(_priceCtrl.text).replaceAll(',', '')) ?? 0, cur: _cur, loc: loc,
      descript: _descCtrl.text.isNotEmpty ? _descCtrl.text : _locCtrl.text,
      specs: {
        if (_selectedSubCat == -1 && _customSubCtrl.text.trim().isNotEmpty) 'custom_sub': _customSubCtrl.text.trim(),
        if (_selectedType == 0) ...{'area': InputValidators.normalizeDigits(_areaCtrl.text), 'floor': InputValidators.normalizeDigits(_floorCtrl.text), 'finishing': _finishing, 'direction': _direction, 'legal_notes': _legalNotesCtrl.text},
        if (_selectedType == 1) ...{'plate': InputValidators.normalizeDigits(_carPlateCtrl.text), 'brand': _carBrandCtrl.text, 'model': _carModelCtrl.text, 'year': InputValidators.normalizeDigits(_carYearCtrl.text), 'color': _carColorCtrl.text, 'fuel': _carFuel, 'transmission': _carTransmission, 'plate_type': _selectedPlateType},
      },
      imgs: imageUrls, vdo: '', exactLoc: _pickedLocation != null ? '${_pickedLocation!.latitude},${_pickedLocation!.longitude}' : '',
      docTp: widget.isPhotographyRequest ? 0 : (_selectedDocType ?? 0), docImg: docUrl, avl: avlMap, sts: OfferStatus.review, tsCrt: DateTime.now(),
      iSoc: widget.isPhotographyRequest ? 0 : (_autoPublishSocial ? 1 : 0),
      socTxt: widget.isPhotographyRequest ? '' : socialText,
    );

    try {
      final created = await offerProv.addOffer(offer,
          isPhotographyRequest: widget.isPhotographyRequest);
      if (!mounted) return;
      if (created == null) {
        setState(() => _submitting = false);
        _snack('❌ تعذر إنشاء العرض — تحقق من الاتصال وحاول مجدداً');
        return;
      }
      // 📸 وضع التصوير: إنشاء مهمة تصوير مرتبطة بالعرض + إشعار المكتب
      if (widget.isPhotographyRequest) {
        try {
          await SupabaseService().invokeFunction('admin-photography', body: {
            'action': 'request_photography_for_offer',
            'user_uid': user.uid,
            'offer_id': created.id,
          });
        } catch (_) {
          // فشل إنشاء مهمة التصوير لا يُبطل العرض — الموظف ينشئها يدوياً
        }
        if (!mounted) return;
        Navigator.pop(context, true); // true = تم إنشاء طلب تصوير
        _snack('✅ تم إرسال طلب التصوير بنجاح — سيتم التواصل معك قريباً');
        return;
      }

      if (_wantVideo) {
        // المستخدم طلب إرفاق فيديو ← نفتح واتساب المكتب مع نص فيه رقم العرض الفعلي
        final num0 = created.offerNumber ?? 0;
        final launched = await _launchVideoWhatsApp(offerNum: num0);
        if (!mounted) return;
        Navigator.pop(context);
        final waNum = (context.read<ConfigProvider>().config?.videoRequestWhatsApp ?? '').trim();
        _snack(launched
            ? 'تم إرسال العرض #$num0 للمراجعة ✅ — أكمل إرفاق الفيديو في واتساب'
            : 'تم إرسال العرض #$num0 ✅ — واتساب غير متاح حالياً؛ أرسل الفيديو يدوياً ${waNum.isNotEmpty ? 'على $waNum' : 'لمكتب العقارات'} واذكر رقم العرض الخاص بك');
      } else {
        Navigator.pop(context);
        _snack('تم إرسال العرض للمراجعة بنجاح ✅');
      }
    } catch (e) {
      if (mounted) { setState(() => _submitting = false); _snack(ErrorUtils.arabicMessage(e)); }
    }
  }

  void _snack(String m) => AppTheme.showSnackBar(context, SnackBar(content: Text(m)));

  /// آخر خطوة فعلياً: للسيارة 4 خطوات (بدون معاينة) وللعقار 5
  /// 📸 وضع التصوير: 3 خطوات فقط (أساسيات + تفاصيل/خريطة + صور/إرسال)
  int get _lastStep {
    if (widget.isPhotographyRequest) return 2;
    return _selectedType == 1 ? 3 : 4;
  }

  /// بناء عناصر dropdown رقمية المفاتيح بأمان — يتجاهل المفاتيح غير الرقمية
  /// والمكررة بدل ما يرمي FormatException ويجمّد الشاشة كلها
  List<DropdownMenuItem<int>> _intDropdownItems(Map<dynamic, dynamic> m) {
    final items = <DropdownMenuItem<int>>[];
    final seen = <int>{};
    for (final e in m.entries) {
      final k = int.tryParse(e.key.toString());
      if (k == null || !seen.add(k)) continue;
      items.add(DropdownMenuItem<int>(value: k, child: Text(e.value.toString())));
    }
    return items;
  }

  /// استخراج التصنيفات الفرعية بأمان — يدعم List و Map (داتا قديمة/مشوهة)
  List<dynamic> _subListOf(Map<dynamic, dynamic> cats, int mainCat) {
    final main = cats[mainCat.toString()];
    if (main is Map) {
      final s = main['sub'] ?? main['children'];
      if (s is List) return s;
      if (s is Map) return s.values.toList();
    }
    return const [];
  }

  /// اسم التصنيف الرئيسي بأمان مهما كان شكل القيمة (Map أو نص)
  String _mainCatName(dynamic v) {
    if (v is Map) return v['nm']?.toString() ?? v.toString();
    return v.toString();
  }

  /// صندوق تحذير عند فشل تحميل قسم من الإعدادات + زر إعادة التحميل
  Widget _warnBox(String msg) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: AppTheme.paddingAllMedium,
        decoration: BoxDecoration(
          color: AppTheme.errorRed.withOpacity(0.08),
          borderRadius: AppTheme.radiusSmall,
          border: Border.all(color: AppTheme.errorRed.withOpacity(0.35)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
          AppTheme.gapWidthSmall,
          Expanded(child: Text(msg, style: const TextStyle(color: Colors.redAccent, fontSize: AppTheme.fontSizeSmall))),
          TextButton(
            onPressed: () => context.read<ConfigProvider>().loadConfig(force: true),
            child: const Text('إعادة التحميل', style: TextStyle(fontSize: AppTheme.fontSizeSmall)),
          ),
        ]),
      );

  /// أزرار تنقّل واضحة بين الخطوات (كانت مفقودة — التنقل كان بالضغط على
  /// عنوان الخطوة فقط فوُهم أن الشاشة "لا تعمل" بعد تبويب الأساسيات)
  Widget _navRow({VoidCallback? onBack, VoidCallback? onNext}) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(children: [
        if (onBack != null)
          Expanded(
            child: OutlinedButton(
              onPressed: onBack,
              child: const Text('رجوع', maxLines: 1, softWrap: false, overflow: TextOverflow.fade),
            ),
          ),
        if (onBack != null && onNext != null) AppTheme.gapWidthSmall,
        if (onNext != null)
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: onNext,
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('التالي', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
      ]),
    );
  }

  /// تحقق الحد الأدنى قبل مغادرة خطوة الأساسيات
  bool _validateBasics() {
    if (_selectedType == null) { _snack('اختر نوع العرض (عقار / سيارة) أولاً'); return false; }
    if (_selectedTrans == null) { _snack('اختر نوع المعاملة (بيع / إيجار) أولاً'); return false; }
    if (_selectedMainCat == null) { _snack('اختر التصنيف الرئيسي أولاً'); return false; }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isPhotographyRequest ? 'طلب تصوير عقاري' : 'إضافة عرض جديد'),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(children: [
        Builder(builder: (context) {
          // 📸 وضع التصوير: 3 خطوات فقط (بلا مواعيد/سند/عمولة/إقرار/سوشيال)
          final steps = widget.isPhotographyRequest
              ? [_step1(), _step2(), _step3Photo()]
              : [_step1(), _step2(), _step3(), if (_selectedType != 1) _stepAvl(), _step4()];
          // حماية من RangeError: التبديل عقار (5 خطوات) → سيارة (4) وأنت بآخر خطوة
          final current = _currentStep.clamp(0, steps.length - 1);
          // ⚠️ مهم: Stepper بفلاتر فيه assert صارم (widget.steps.length == oldWidget.steps.length)
          // تغيير عدد الخطوات (عقار=5 / سيارة=4) على نفس الودجت يرمي exception أثناء البناء
          // فيتوقف بناء الفريم الجديد وتبقى الشاشة معلّقة على الفريم القديم — وهذا هو سبب
          // بلاغ "اخترت سيارة فطلعت تصنيفات عقارات وما عاد اشتغل شي" + تراكب الخطأ الأحمر.
          // الحل: مفتاح يتغير مع النوع → الـ Stepper يُبنى من جديد كنودجت مستقل بلا مقارنة.
          return Stepper(
            key: ValueKey('offer_steps_${_selectedType ?? -1}'),
            type: StepperType.vertical, currentStep: current,
            controller: _stepScroll,
            onStepTapped: (s) => _goToStep(s),
            controlsBuilder: (context, details) => const SizedBox.shrink(),
            steps: steps,
          );
        }),
        if (_submitting)
          Container(
            color: Colors.black.withOpacity(0.82),
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 42),
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBlack,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: AppTheme.primaryGold.withOpacity(0.4), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                          color: AppTheme.primaryGold, strokeWidth: 3),
                    ),
                    AppTheme.gapHeightXL,
                    Text(
                      _progressMsg,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppTheme.textWhite, fontSize: AppTheme.fontSizeMedium, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Step _step1() {
    // watch وليس read: التصنيفات تصل من السيرفر بعد فتح الشاشة — بدون watch
    // تبقى القوائم فارغة حتى أول تفاعل من المستخدم
    final config = context.watch<ConfigProvider>().config;
    final cityItems = (config?.locations ?? const []).map((e) => DropdownMenuItem<String>(value: e.toString(), child: Text(e.toString()))).toList();
    cityItems.add(const DropdownMenuItem(value: _customCityOption, child: Text('آخر (إدخال حر)')));

    final Map<String, dynamic> catsSource = _selectedType == 1 ? (config?.vehicleCategories ?? const {}) : (config?.propertyCategories ?? const {});
    final mainCatItems = <DropdownMenuItem<int>>[];
    final seenCatKeys = <int>{};
    for (final e in catsSource.entries) {
      final k = int.tryParse(e.key.toString());
      if (k == null || !seenCatKeys.add(k)) continue;
      mainCatItems.add(DropdownMenuItem<int>(value: k, child: Text(_mainCatName(e.value))));
    }

    return Step(
      title: const Text('الأساسيات', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
      content: Column(children: [
        _dd('نوع العرض', ['عقار', 'سيارة'], _selectedType == null ? null : (_selectedType == 0 ? 'عقار' : 'سيارة'), (v) => setState(() { _selectedType = v == 'عقار' ? 0 : 1; _selectedMainCat = null; _selectedSubCat = null; })),
        const SizedBox(height: 15),
        _dd('نوع المعاملة', ['بيع', 'إيجار'], _selectedTrans == null ? null : (_selectedTrans == 0 ? 'بيع' : 'إيجار'), (v) => setState(() => _selectedTrans = v == 'بيع' ? 0 : 1)),
        const SizedBox(height: 15),
        DropdownButtonFormField<int>(value: _selectedMainCat, items: mainCatItems, onChanged: mainCatItems.isEmpty ? null : (v) => setState(() { _selectedMainCat = v; _selectedSubCat = null; }), decoration: const InputDecoration(labelText: 'التصنيف الرئيسي', border: OutlineInputBorder())),
        if (mainCatItems.isEmpty) _warnBox('تعذّر تحميل التصنيفات من السيرفر'),
        const SizedBox(height: 15),
        if (_selectedMainCat != null) ...[
           DropdownButtonFormField<int>(
             value: _selectedSubCat,
             items: [
               ...(_subListOf(catsSource, _selectedMainCat!).asMap().entries.map((e) => DropdownMenuItem<int>(value: e.key, child: Text(e.value.toString())))),
               const DropdownMenuItem(value: -1, child: Text('آخر'))
             ],
             onChanged: (v) => setState(() { _selectedSubCat = v; if (v != -1) _customSubCtrl.clear(); }),
             decoration: const InputDecoration(labelText: 'التصنيف الفرعي', border: OutlineInputBorder()),
           ),
           if (_selectedSubCat == -1)
             Padding(
               padding: const EdgeInsets.only(top: 10),
               child: TextField(controller: _customSubCtrl, decoration: const InputDecoration(labelText: 'اكتب التصنيف الفرعي يدوياً', hintText: 'مثال: جرار صغير، مقطورة...', border: OutlineInputBorder())),
             ),
        ],
        const SizedBox(height: 15),
        TextField(controller: _contactPhoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف للتواصل (إلزامي)', hintText: 'مثال: 09xxxxxxxx', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone))),
        const SizedBox(height: 15),
        if (_selectedType == 0) ...[
          DropdownButtonFormField<String>(value: _selectedCityArea, items: cityItems, onChanged: (v) => setState(() => _selectedCityArea = v), decoration: const InputDecoration(labelText: 'المنطقة الرئيسية', border: OutlineInputBorder())),
          if (_selectedCityArea == _customCityOption) Padding(padding: const EdgeInsets.only(top: 10), child: TextField(controller: _customCityCtrl, decoration: const InputDecoration(labelText: 'اكتب المنطقة يدوياً', border: OutlineInputBorder()))),
          if (!widget.isPhotographyRequest) ...[
            const SizedBox(height: 15),
            TextField(controller: _locCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'وصف دقيق للموقع', hintText: 'بجانب مدرسة... شارع... الطابق...', border: OutlineInputBorder())),
          ],
        ],
        if (_selectedType == 1) ...[
          TextField(controller: _carPlateCtrl, decoration: const InputDecoration(labelText: 'رقم اللوحة والمحافظة (إلزامي)', hintText: 'مثال: 123456 - السويداء', border: OutlineInputBorder())),
          AppTheme.gapHeightSmall,
          TextField(controller: _carBrandCtrl, decoration: const InputDecoration(labelText: 'الماركة (إلزامي)', hintText: 'كيا، تويوتا، مرسيدس...', border: OutlineInputBorder())),
          AppTheme.gapHeightSmall,
          TextField(controller: _carModelCtrl, decoration: const InputDecoration(labelText: 'الموديل (إلزامي)', hintText: 'سيراتو، لاندكروزر، أكسنت...', border: OutlineInputBorder())),
          AppTheme.gapHeightSmall,
          // منطقة تواجد السيارة — إلزامية (نفس مصدر مناطق العقار: قائمة locs من الإعدادات)
          DropdownButtonFormField<String>(value: _carCityArea, items: cityItems, onChanged: (v) => setState(() => _carCityArea = v), decoration: const InputDecoration(labelText: 'المنطقة الرئيسية للسيارة (إلزامي)', border: OutlineInputBorder())),
          if (_carCityArea == _customCityOption) Padding(padding: const EdgeInsets.only(top: 10), child: TextField(controller: _carCustomCityCtrl, decoration: const InputDecoration(labelText: 'اكتب المنطقة يدوياً', border: OutlineInputBorder()))),
        ],
        _navRow(onNext: () { if (_validateBasics()) _goToStep(1); }),
      ]),
      isActive: _currentStep >= 0,
    );
  }

  Step _step2() => Step(
    title: const Text('التفاصيل والمواصفات', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
    content: Column(children: [
      TextField(controller: _ttlCtrl, maxLength: 80, decoration: const InputDecoration(labelText: 'عنوان العرض بالتطبيق (اختياري)', hintText: 'شقة فاخرة، سيارة نظيفة، أرض زراعية...', border: OutlineInputBorder())),
      AppTheme.gapHeightSmall,
      Row(children: [
        Expanded(flex: 3, child: TextField(controller: _priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر المتوقع (إلزامي)', border: OutlineInputBorder()))),
        AppTheme.gapWidthSmall,
        Expanded(flex: 3, child: DropdownButtonFormField<int>(value: _cur, isExpanded: true, items: const [DropdownMenuItem(value: 0, child: Text('دولار أمريكي', overflow: TextOverflow.ellipsis)), DropdownMenuItem(value: 1, child: Text('ليرة سورية', overflow: TextOverflow.ellipsis))], onChanged: (v) => setState(() => _cur = v ?? 1), decoration: const InputDecoration(border: OutlineInputBorder()))),
      ]),
      const SizedBox(height: 15),
      if (_selectedType == 0) ...[
        TextField(controller: _areaCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المساحة م²', border: OutlineInputBorder())),
        AppTheme.gapHeightMedium,
        _dd('الإكساء', ['ملكي', 'سوبر ديلوكس', 'ديلوكس', 'عادي', 'هيكل'], _finishing, (v) => setState(() => _finishing = v)),
        AppTheme.gapHeightMedium,
        TextField(controller: _floorCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الطابق', hintText: 'مثال: 3', border: OutlineInputBorder())),
      ],
      if (_selectedType == 1) ...[
        TextField(controller: _carYearCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'سنة الصنع (إلزامي)', border: OutlineInputBorder())),
        AppTheme.gapHeightSmall,
        _dd('نوع الوقود (اختياري)', ['بنزين', 'ديزل', 'هجين', 'كهرباء'], _carFuel, (v) => setState(() => _carFuel = v)),
        AppTheme.gapHeightSmall,
        _dd('ناقل الحركة (اختياري)', ['عادي', 'أوتوماتيك'], _carTransmission, (v) => setState(() => _carTransmission = v)),
        AppTheme.gapHeightSmall,
        TextField(controller: _carColorCtrl, decoration: const InputDecoration(labelText: 'اللون (اختياري)', border: OutlineInputBorder())),
        AppTheme.gapHeightSmall,
        TextField(controller: _carKmCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عدد الكيلومترات (اختياري)', border: OutlineInputBorder())),
      ],
      const SizedBox(height: 15),
      TextField(controller: _descCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'وصف إضافي (اختياري)', hintText: 'أي مميزات أو تفاصيل أخرى تود ذكرها للزبائن...', border: OutlineInputBorder())),
      AppTheme.gapHeightXL,
      if (_selectedType == 0 && !widget.isPhotographyRequest) ...[
        const Text(
          'الموقع الدقيق على الخريطة (اختياري)',
          style: TextStyle(
            color: AppTheme.primaryGold,
            fontWeight: FontWeight.bold,
            fontSize: AppTheme.fontSizeMedium,
          ),
        ),
        AppTheme.gapHeightSmall,
        LocationPicker(initial: _pickedLocation, onPicked: (loc) => setState(() => _pickedLocation = loc), height: 250),
      ],
      _navRow(onBack: () => _goToStep(0), onNext: () => _goToStep(2)),
    ]),
    isActive: _currentStep >= 1,
  );

  Step _step3() => Step(
    title: const Text('الصور والفيديو', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
    content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ElevatedButton.icon(onPressed: _pickImages, icon: const Icon(Icons.add_a_photo), label: Text('إضافة صور العرض (${_pickedImages.length}/${StorageService.maxImages})')),
      AppTheme.gapHeightSmall,
      if (_pickedImages.isNotEmpty) Wrap(spacing: 8, children: _pickedImages.asMap().entries.map((e) => Stack(children: [ClipRRect(borderRadius: AppTheme.radiusSmall, child: _thumb(e.value)), Positioned(top: -5, left: -5, child: IconButton(icon: const Icon(Icons.cancel, color: AppTheme.errorRed), onPressed: () => setState(() => _pickedImages.removeAt(e.key))))])).toList()),
      AppTheme.gapHeightXL,
      const Text('🎬 فيديو العرض (اختياري)', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeBody)),
      CheckboxListTile(
        value: _wantVideo,
        onChanged: (v) => setState(() => _wantVideo = v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        activeColor: AppTheme.primaryGold,
        title: const Text('أريد إرفاق فيديو للعرض (عبر واتساب المكتب)', style: TextStyle(color: Colors.black87, fontSize: AppTheme.fontSizeBody, fontWeight: FontWeight.bold)),
      ),
      if (_wantVideo) ...[
        Container(
          padding: AppTheme.paddingAllMedium,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppTheme.primaryGold.withOpacity(0.08),
            borderRadius: AppTheme.radiusMedium,
            border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3)),
          ),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('⚠️ يتم إرسال الفيديو عبر تطبيق واتساب — تأكد من تثبيت التطبيق على جهازك', style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall, height: 1.5)),
            SizedBox(height: 6),
            Text('ℹ️ سيفتح واتساب تلقائياً بعد الانتهاء من إضافة العرض، وستكون الرسالة جاهزة وتحتوي على رقم العرض الخاص بك — فقط أرفق الفيديو وأرسله', style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall, height: 1.5)),
          ]),
        ),
      ],
      _navRow(onBack: () => _goToStep(1), onNext: () => _goToStep(3)),
    ]),
    isActive: _currentStep >= 2,
  );

  /// 📸 الخطوة الثالثة بوضع التصوير: مراجعة وإرسال طلب التصوير (بدون صور أولية - Bug #25)
  /// بلا سند/عمولة/إقرار/سوشيال/فيديو — هذه كلها تُحدد لاحقاً عند نشر العرض.
  Step _step3Photo() => Step(
    title: const Text('مراجعة وإرسال الطلب', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
    content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ✅ Bug #25: إزالة حقل الصور الأولية تماماً من طلب التصوير
      // المصوّر المحترف هو من يلتقط الصور، ليس المستخدم

      // ── ملخص الطلب ──
      Container(
        padding: AppTheme.paddingAllLarge,
        decoration: BoxDecoration(
          color: AppTheme.surfaceBlack,
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(color: AppTheme.primaryGold.withOpacity(0.5), width: 1.2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.summarize, color: AppTheme.primaryGold, size: 20),
            AppTheme.gapWidthSmall,
            Text('ملخص طلب التصوير', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeMedium)),
          ]),
          AppTheme.gapHeightSmall,
          _summaryRow('نوع العرض', _selectedType == 0 ? 'عقار' : 'سيارة'),
          _summaryRow('المعاملة', _selectedTrans == 0 ? 'بيع' : 'إيجار'),
          if (_ttlCtrl.text.trim().isNotEmpty) _summaryRow('العنوان', _ttlCtrl.text.trim()),
          if (_priceCtrl.text.trim().isNotEmpty)
            _summaryRow('السعر', '${_priceCtrl.text} ${_cur == 0 ? 'دولار' : 'ل.س'}'),
          if (_pickedLocation != null)
            _summaryRow('الموقع', '📍 ${_pickedLocation!.latitude.toStringAsFixed(5)}, ${_pickedLocation!.longitude.toStringAsFixed(5)}'),
          _summaryRow('الصور', 'المصوّر المحترف سيلتقطها'),
        ]),
      ),

      // ── تذكير بالأجر ──
      if ((context.read<ConfigProvider>().config?.photographyPrice ?? 1000) > 0) ...[
        AppTheme.gapHeightMedium,
        Container(
          padding: AppTheme.paddingAllMedium,
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.1),
            borderRadius: AppTheme.radiusSmall,
            border: Border.all(color: Colors.amber.withOpacity(0.4)),
          ),
          child: Row(children: [
            const Icon(Icons.payments_outlined, color: Colors.amber, size: 18),
            AppTheme.gapWidthSmall,
            Expanded(
              child: Text(
                'أجر التصوير ${(context.read<ConfigProvider>().config?.photographyPrice ?? 1000).toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')} ل.س — يُدفع للمصوّر عند وصوله.',
                style: const TextStyle(color: Colors.amber, fontSize: AppTheme.fontSizeSmall, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ],

      AppTheme.gapHeightLarge,
      _navRow(onBack: () => _goToStep(1)),
      AppTheme.gapHeightSmall,
      SizedBox(
        width: double.infinity,
        height: 55,
        child: ElevatedButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: const Icon(Icons.photo_camera, size: 20),
          label: const Text('إرسال طلب التصوير', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeSubtitle)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold, foregroundColor: AppTheme.deepBlack),
        ),
      ),
    ]),
    isActive: _currentStep >= 2,
  );

  Widget _summaryRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 80,
        child: Text(label, style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
      ),
      Expanded(child: Text(value, style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSmall, fontWeight: FontWeight.w500))),
    ]),
  );

  Step _stepAvl() => Step(
    title: const Text('المواعيد المتاحة للمعاينة', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
    content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: AppTheme.paddingAllMedium,
        decoration: BoxDecoration(color: AppTheme.primaryGold.withOpacity(0.1), borderRadius: AppTheme.radiusMedium, border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3))),
        child: SwitchListTile(
          value: _anytimeReady,
          onChanged: (v) => setState(() => _anytimeReady = v),
          title: const Text('أنا جاهز للمعاينة في أي وقت', style: TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeMedium, fontWeight: FontWeight.bold)),
          subtitle: const Text('سيتمكن الزبائن من طلب موعد في أي وقت تراه الإدارة مناسباً', style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
          activeColor: AppTheme.primaryGold,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      AppTheme.gapHeightLarge,
      if (!_anytimeReady) ...[
        const Text('أو حدد أياماً وفترات زمنية محددة:', style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody)),
        AppTheme.gapHeightMedium,
        ..._weekDays.map((day) {
          final key = day.$1; final label = day.$2; final enabled = _avlDaysEnabled[key] ?? false; final slots = _avlSlots[key] ?? [];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusMedium, border: Border.all(color: enabled ? AppTheme.primaryGold.withOpacity(0.5) : AppTheme.textGrey.withOpacity(0.2))),
            child: Column(children: [
              ListTile(
                leading: Icon(enabled ? Icons.check_box : Icons.check_box_outline_blank, color: enabled ? AppTheme.primaryGold : AppTheme.textGrey),
                title: Text(label, style: TextStyle(color: enabled ? AppTheme.textWhite : AppTheme.textGrey, fontWeight: FontWeight.bold)),
                onTap: () => setState(() { _avlDaysEnabled[key] = !enabled; if (!enabled && slots.isEmpty) _avlSlots[key]!.add({'from': '', 'to': ''}); }),
                trailing: enabled ? IconButton(icon: const Icon(Icons.add, color: AppTheme.primaryGold, size: 20), onPressed: () => setState(() => _avlSlots[key]!.add({'from': '', 'to': ''}))) : null,
              ),
              if (enabled) ...slots.asMap().entries.map((entry) {
                final i = entry.key; final slot = entry.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(children: [
                    const Text('من', style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
                    AppTheme.gapWidthXS,
                    Expanded(child: _timeField(dayKey: key, slotIndex: i, field: 'from', hint: '09:00')),
                    AppTheme.gapWidthSmall,
                    const Text('إلى', style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
                    AppTheme.gapWidthXS,
                    Expanded(child: _timeField(dayKey: key, slotIndex: i, field: 'to', hint: '12:00')),
                    IconButton(icon: const Icon(Icons.remove_circle_outline, color: AppTheme.errorRed, size: 18), onPressed: () => setState(() => _avlSlots[key]!.removeAt(i))),
                  ]),
                );
              }),
            ]),
          );
        }),
      ],
      _navRow(onBack: () => _goToStep(2), onNext: () => _goToStep(4)),
    ]),
    isActive: _currentStep >= 3,
  );

  // ✅ Fixed: Use persistent controllers to prevent focus loss on each keystroke
  Widget _timeField({
    required String dayKey,
    required int slotIndex,
    required String field,
    required String hint,
  }) {
    final controller = _getTimeController(dayKey, slotIndex, field);
    final currentValue = _avlSlots[dayKey]?[slotIndex]?[field] ?? '';
    
    // Update controller text if it differs from stored value
    if (controller.text != currentValue) {
      controller.text = currentValue;
      controller.selection = TextSelection.collapsed(offset: currentValue.length);
    }
    
    return TextField(
      controller: controller,  // ✅ Persistent controller
      keyboardType: TextInputType.datetime,
      style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeBody),
      decoration: InputDecoration(
        hintText: hint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: (v) {
        setState(() => _avlSlots[dayKey]![slotIndex][field] = v);
      },
    );
  }

  Step _step4() {
    final config = context.watch<ConfigProvider>().config;
    final Map<String, dynamic> rawDocTp = config?.documentTypes ?? const {};
    final Map<String, dynamic> rawCarDocTp = config?.carDocumentTypes ?? const {};
    final Map<String, dynamic> rawPlateTp = config?.plateTypes ?? const {};

    // فلترة السندات لمنع تداخل السيارات بالعقارات — بقراءة آمنة بدون int.parse
    // (المفاتيح غير الرقمية كانت ترمي FormatException أثناء build فتجمّد الشاشة كلها)
    final propertyDocs = rawDocTp.entries
        .where((e) => (int.tryParse(e.key.toString()) ?? 99) < 6)
        .map((e) => DropdownMenuItem<int>(value: int.parse(e.key.toString()), child: Text(e.value.toString())))
        .toList();
    final carDocs = _intDropdownItems(rawCarDocTp);
    final plateTypes = _intDropdownItems(rawPlateTp);

    return Step(
      title: const Text('السند والعمولة', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
      content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_selectedType == 1) ...[
          const Text('سند ملكية السيارة (إلزامي)', style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeBody, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(value: _selectedCarDocType, items: carDocs, onChanged: carDocs.isEmpty ? null : (v) => setState(() { _selectedCarDocType = v; _selectedDocType = v; }), decoration: const InputDecoration(border: OutlineInputBorder())),
          if (carDocs.isEmpty) _warnBox('أنواع سندات السيارات غير محمّلة من السيرفر'),
          AppTheme.gapHeightMedium,
          const Text('نوع النمرة (إلزامي)', style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeBody, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(value: _selectedPlateType, items: plateTypes, onChanged: plateTypes.isEmpty ? null : (v) => setState(() => _selectedPlateType = v), decoration: const InputDecoration(border: OutlineInputBorder())),
          if (plateTypes.isEmpty) _warnBox('أنواع النمر غير محمّلة من السيرفر'),
        ] else ...[
          const Text('سند ملكية العقار (إلزامي)', style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeBody, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(value: _selectedDocType, items: propertyDocs, onChanged: propertyDocs.isEmpty ? null : (v) => setState(() => _selectedDocType = v), decoration: const InputDecoration(border: OutlineInputBorder())),
          if (propertyDocs.isEmpty) _warnBox('أنواع سندات الملكية غير محمّلة من السيرفر'),
        ],
        const SizedBox(height: 15),
        const Text('صورة سند الملكية (اختياري)', style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeBody, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        GestureDetector(onTap: _pickDocImage, child: Container(height: 120, width: double.infinity, decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusMedium, border: Border.all(color: _docImage != null ? AppTheme.successGreen : AppTheme.primaryGold.withOpacity(0.5))), child: _docImage == null ? const Center(child: Icon(Icons.upload_file, size: 40, color: AppTheme.primaryGold)) : ClipRRect(borderRadius: AppTheme.radiusMedium, child: kIsWeb ? Image.network(_docImage!.path, fit: BoxFit.cover) : Image.file(File(_docImage!.path), fit: BoxFit.cover, cacheWidth: 800)))),
        AppTheme.gapHeightXL,
        // ── تنبيه عمولة المكتب (يُخفى للوسيط — عروضه معفاة) ──
        if (!context.read<AuthProvider>().isBroker) ...[
        Container(
          padding: AppTheme.paddingAllLarge,
          decoration: BoxDecoration(color: AppTheme.primaryGold.withOpacity(0.1), borderRadius: AppTheme.radiusMedium, border: Border.all(color: AppTheme.primaryGold, width: 1.5)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [Icon(Icons.monetization_on, color: AppTheme.primaryGold, size: 28), AppTheme.gapWidthSmall, Text('تنبيه بخصوص عمولة المكتب', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: 15))]),
            AppTheme.gapHeightSmall,
            Text(_selectedTrans == 0 ? 'يتقاضى المكتب عمولة قدرها 3% من القيمة الإجمالية عند إتمام عملية البيع.' : 'يتقاضى المكتب عمولة تعادل أجرة نصف شهر عند إتمام عملية الإيجار.', style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeBody, height: 1.4)),
          ]),
        ),
        const SizedBox(height: 15),
        ],
        // ── تنويه الخدمات القانونية (منقول من تفاصيل العرض بطلب المدير + إضافة الاستشارات المأجورة) ──
        Container(
          width: double.infinity,
          padding: AppTheme.paddingAllLarge,
          decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusMedium, border: Border.all(color: AppTheme.primaryGold.withOpacity(0.5), width: 1.2)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(Icons.gavel, color: AppTheme.primaryGold, size: 22), AppTheme.gapWidthSmall, Expanded(child: Text('الضمان والتوثيق القانوني المعتمد ⚖️', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeMedium)))]),
            AppTheme.gapHeightSmall,
            Text('يقدم المكتب خدمة التوثيق القانوني المأجور وتنظيم العقود أصولاً لضمان حق الطرفين: تدقيق سندات الملكية (طابو، حكم محكمة، مواصلات) وخلوّها من الإشارات والنزاعات قبل إتمام الصفقة، إضافةً إلى تقديم الاستشارات القانونية المأجورة على يد محامين مختصين.', style: TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSmall, height: 1.6)),
            SizedBox(height: 6),
            Text('توثيق قانوني • عقود معتمدة • استشارات قانونية مأجورة', style: TextStyle(color: AppTheme.successGreen, fontSize: AppTheme.fontSizeCaption, fontWeight: FontWeight.bold)),
          ]),
        ),
        const SizedBox(height: 15),
        // ── الإقرار والتعهد — مقروء قبل الموافقة (كان نصاً أبيض بلا حاوية فيختفي، والآن داخل بطاقة داكنة) ──
        Container(
          decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusMedium, border: Border.all(color: AppTheme.primaryGold.withOpacity(0.5), width: 1.2)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: const Icon(Icons.description, color: AppTheme.primaryGold, size: 20),
                title: const Text('الإقرار والتعهد — اضغط للقراءة قبل الموافقة', style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeBody, fontWeight: FontWeight.bold)),
                iconColor: AppTheme.primaryGold, collapsedIconColor: AppTheme.primaryGold,
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                children: [Text(_pledgeFullText, style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSmall, height: 1.7))],
              ),
            ),
            CheckboxListTile(
              value: _agreePledge, onChanged: (v) => setState(() => _agreePledge = v ?? false),
              title: const Text('أوافق على الإقرار والتعهد وصحة البيانات المقدمة', style: TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeBody)),
              activeColor: AppTheme.primaryGold, checkColor: AppTheme.deepBlack,
              side: const BorderSide(color: AppTheme.primaryGold, width: 1.5),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8), controlAffinity: ListTileControlAffinity.leading,
            ),
          ]),
        ),

        // ── تشيك بوكس النشر التلقائي على صفحات السوشيال (مفعل تلقائياً)
        AppTheme.gapHeightSmall,
        Container(
          decoration: BoxDecoration(
            // سطح فاتح مع حد ذهبي — بالثيم الجديد surfaceBlack = أبيض (النص الداكن textWhite)
            color: AppTheme.surfaceBlack,
            borderRadius: AppTheme.radiusMedium,
            border: Border.all(color: AppTheme.primaryGold.withOpacity(0.4)),
          ),
          child: CheckboxListTile(
            value: _autoPublishSocial,
            onChanged: (v) => setState(() => _autoPublishSocial = v ?? true),
            title: const Text(
              'نشر العرض تلقائياً على صفحاتنا في فيسبوك وإنستغرام (وأي صفحات إضافية مضافة)',
              style: TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeBody, fontWeight: FontWeight.w500),
            ),
            subtitle: const Text(
              'سيتم إنشاء منشور جاهز من بيانات العرض ونشره بعد موافقة الإدارة (يمكنك إلغاء التفعيل).',
              style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption),
            ),
            activeColor: AppTheme.primaryGold,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),

        AppTheme.gapHeightSmall,
        _navRow(onBack: () => _goToStep(_selectedType == 1 ? 2 : 3)),
        AppTheme.gapHeightXS,
        SizedBox(width: double.infinity, height: 55, child: ElevatedButton(onPressed: _submitting ? null : _submit, child: const Text('نشر العرض للمراجعة الآن', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeSubtitle)))),
      ]),
      isActive: _currentStep >= _lastStep,
    );
  }

  Widget _thumb(XFile file) => kIsWeb ? Image.network(file.path, width: 70, height: 70, fit: BoxFit.cover) : Image.file(File(file.path), width: 70, height: 70, fit: BoxFit.cover, cacheWidth: 140);

  /// قائمة منسدلة بعنوان — كانت بلا value فتظهر فاضية بعد الاختيار
  /// (يوحي للمستخدم أن الشاشة "لا تعمل")، الآن تعرض الاختيار الحالي
  Widget _dd(String label, List<String> items, String? value, Function(String) on) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(color: value != null ? AppTheme.primaryGold : AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall, fontWeight: value != null ? FontWeight.bold : FontWeight.normal)), const SizedBox(height: 5), DropdownButtonFormField<String>(value: value, items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(), onChanged: (v) => on(v!), decoration: const InputDecoration(border: OutlineInputBorder()))]);

  /// توليد قالب منشور جاهز للنشر على صفحات السوشيال (فيسبوك/إنستغرام)
  /// يُستخدم عندما يكون _autoPublishSocial = true
  /// ⚠️ قاعدة صارمة بطلب المالك: لا هاتف للعميل/صاحب العرض أبداً — التواصل حصراً عبر واتساب المكتب
  String _generateSocialPostText() {
    final config = context.read<ConfigProvider>().config;
    final priceStr = _cur == 0
        ? '\$${_priceCtrl.text.isNotEmpty ? _priceCtrl.text : '---'}'
        : '${_priceCtrl.text.isNotEmpty ? _priceCtrl.text : '---'} ل.س';

    final isProperty = _selectedType == 0;
    final typeName = isProperty ? 'عقار' : 'سيارة';
    final emoji = isProperty ? '🏠' : '🚗';
    final transName = _selectedTrans == 0 ? 'للبيع' : 'للإيجار';
    final city = _selectedType == 1
        ? (_carCityArea == _customCityOption ? _carCustomCityCtrl.text.trim() : (_carCityArea ?? ''))
        : (_selectedCityArea == _customCityOption ? _customCityCtrl.text : (_selectedCityArea ?? ''));

    // التصنيف من الإعدادات (رئيسي — فرعي)
    final cats = isProperty ? (config?.propertyCategories ?? const {}) : (config?.vehicleCategories ?? const {});
    final entry = cats[(_selectedMainCat ?? -1).toString()];
    var mainCat = '';
    if (entry is Map) { mainCat = (entry['nm'] ?? '').toString(); } else if (entry != null) { mainCat = entry.toString(); }
    var subCat = _selectedSubCat == -1 ? _customSubCtrl.text.trim() : '';
    if (subCat.isEmpty && entry is Map && entry['sub'] is List) {
      final subs = entry['sub'] as List;
      if (_selectedSubCat != null && _selectedSubCat! >= 0 && _selectedSubCat! < subs.length) {
        subCat = subs[_selectedSubCat!].toString();
      }
    }
    final catJoined = [mainCat, subCat].where((e) => e.isNotEmpty).join(' — ');

    // المواصفات (بدون اللوحة والمستندات — بيانات حساسة لا تنشر)
    final specParts = <String>[
      if (isProperty) ...[
        if (_areaCtrl.text.trim().isNotEmpty) 'مساحة ${_areaCtrl.text.trim()} م²',
        if ((_finishing ?? '').toString().trim().isNotEmpty) 'إكساء $_finishing',
        if (_floorCtrl.text.trim().isNotEmpty) 'طابق ${_floorCtrl.text.trim()}',
        if ((_direction ?? '').toString().trim().isNotEmpty) 'اتجاه $_direction',
      ] else ...[
        if (_carBrandCtrl.text.trim().isNotEmpty) 'ماركة ${_carBrandCtrl.text.trim()}',
        if (_carModelCtrl.text.trim().isNotEmpty) 'موديل ${_carModelCtrl.text.trim()}',
        if (_carYearCtrl.text.trim().isNotEmpty) 'سنة ${_carYearCtrl.text.trim()}',
        if (_carColorCtrl.text.trim().isNotEmpty) 'اللون ${_carColorCtrl.text.trim()}',
        if ((_carFuel ?? '').toString().trim().isNotEmpty) 'وقود $_carFuel',
        if ((_carTransmission ?? '').toString().trim().isNotEmpty) 'ناقل $_carTransmission',
      ],
    ];

    final title = _ttlCtrl.text.isNotEmpty ? _ttlCtrl.text : 'عرض جديد';
    final desc = _descCtrl.text.isNotEmpty ? _descCtrl.text : _locCtrl.text;
    final wa = (config?.videoRequestWhatsApp ?? '').trim();
    final appLink = (config?.appDownloadLink ?? '').trim();

    return '''
$emoji $title

📌 $typeName $transName
${catJoined.isNotEmpty ? '🏷️ التصنيف: $catJoined' : ''}
💰 السعر: $priceStr
${city.isNotEmpty ? '📍 المنطقة: $city' : ''}
${specParts.isNotEmpty ? '${isProperty ? '📐' : '🔧'} المواصفات: ${specParts.join(' • ')}' : ''}

${desc.isNotEmpty ? desc : ''}

📱 التواصل والمعاينة حصراً عبر واتساب المكتب العقاري الإلكتروني:
${wa.isNotEmpty ? wa : ''}
${appLink.isNotEmpty ? '📲 لمتابعة كل العروض حمّل تطبيق «عقارات السويداء»:\n$appLink' : ''}
#عقارات_السويداء #السويداء ${isProperty ? '#عقارات' : '#سيارات'}
'''.trim();
  }
}

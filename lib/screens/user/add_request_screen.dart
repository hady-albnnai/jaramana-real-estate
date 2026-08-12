import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/request_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/db_constants.dart';
import '../../core/validation/input_validators.dart';
import '../../models/request_model.dart';

/// شاشة إضافة طلب (شراء / إيجار)
class AddRequestScreen extends StatefulWidget {
  const AddRequestScreen({super.key});

  @override
  State<AddRequestScreen> createState() => _AddRequestScreenState();
}

class _AddRequestScreenState extends State<AddRequestScreen> {
  int _currentStep = 0;
  int? _selectedType;    // 0=شراء, 1=استئجار
  int? _selectedElement; // 0=عقار, 1=سيارة
  int? _selectedMainCat;
  int? _selectedSubCat;
  final _customSubCtrl   = TextEditingController();
  final _clientNameCtrl  = TextEditingController();
  final _clientPhoneCtrl = TextEditingController();
  final _priceCtrl       = TextEditingController();
  final _notesCtrl       = TextEditingController();
  final _specsCtrl       = TextEditingController(); // المواصفات المطلوبة
  int _cur = Currency.lbp; // العملة — دولار أو ل.س

  bool _submitting = false;

  void _next() => setState(() { if (_currentStep < 2) _currentStep++; });
  void _prev() => setState(() { if (_currentStep > 0) _currentStep--; });

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // تعبئة تلقائية لاسم العميل ورقم هاتفه من حساب المستخدم
      final user = context.read<AuthProvider>().userModel;
      if (user != null) {
        // استخدام nm أولاً، ثم usr كـ fallback، ثم تركه فارغاً
        final displayName = user.nm.isNotEmpty ? user.nm : (user.usr ?? '');
        if (displayName.isNotEmpty) _clientNameCtrl.text = displayName;
        if (user.ph.isNotEmpty) _clientPhoneCtrl.text = user.ph;
      }
    });
  }

  @override
  void dispose() {
    _clientNameCtrl.dispose();
    _clientPhoneCtrl.dispose();
    _priceCtrl.dispose();
    _notesCtrl.dispose();
    _specsCtrl.dispose();
    _customSubCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedType == null || _selectedElement == null) {
      _snack('يرجى اختيار نوع الطلب والعنصر');
      return;
    }
    final clientName = _clientNameCtrl.text.trim();
    final clientPhone = InputValidators.normalizeDigits(_clientPhoneCtrl.text.trim());
    if (clientName.isEmpty || clientPhone.isEmpty) {
      _snack('اسم العميل وهاتفه إلزاميان');
      return;
    }
    if (!RegExp(r'^09[3-9]\d{7}$').hasMatch(clientPhone)) {
      _snack('يرجى إدخال رقم هاتف سوري صحيح للعميل (09xxxxxxxx)');
      return;
    }

    final auth      = context.read<AuthProvider>();
    final reqProv   = context.read<RequestProvider>();
    final user      = auth.userModel;
    if (user == null) return;

    setState(() => _submitting = true);

    // فحص الحصة عبر Edge Function حتى لا نفتح RPC مباشرة من العميل.
    final quota = await reqProv.canPublishRequest(user.uid);
    if (quota['allowed'] != true) {
      if (mounted) setState(() => _submitting = false);
      final reason = quota['reason']?.toString();
      _snack(reason == 'QUOTA_EXCEEDED'
          ? 'وصلت للحد الأقصى (${quota['limit']} طلب).'
          : (reason?.isNotEmpty == true ? reason! : 'تعذّر التحقق من حصتك، حاول لاحقاً.'));
      return;
    }

    final budget  = double.tryParse(InputValidators.normalizeDigits(_priceCtrl.text).replaceAll(',', '')) ?? 0;
    final element = _selectedElement ?? 0;

    // بناء specs من حقل المواصفات
    final specsText = _specsCtrl.text.trim();
    final specs = specsText.isNotEmpty
        ? {'details': specsText}
        : <String, dynamic>{};

    // التصنيف الفرعي
    final customSub = _customSubCtrl.text.trim();
    if (customSub.isNotEmpty) {
      specs['custom_sub'] = customSub;
    }

    final request = RequestModel(
      id:    '',
      typ:   _selectedType!,
      elm:   element,
      clNm:  clientName,
      clPh:  clientPhone,
      prc:   budget,
      cur:   _cur,
      notes: _notesCtrl.text.trim(),
      specs: specs,
      usrId: user.uid,
      sts:   0,
      tsCrt: DateTime.now(),
    );

    bool ok = false;
    try {
      ok = await reqProv.addRequest(request);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        final msg = e.toString();
        if (msg.contains('PHONE_INVALID') || msg.contains('PHONE_REQUIRED')) {
          _snack('رقم هاتف العميل غير صالح، يرجى إدخال رقم سوري صحيح');
        } else if (msg.contains('QUOTA_EXCEEDED')) {
          _snack('وصلت للحد الأقصى لعدد الطلبات المسموحة في باقتك');
        } else if (msg.contains('DUPLICATE_REQUEST')) {
          _snack('لديك طلب مشابه تم إرساله مؤخراً — انتظر قليلاً قبل إرسال طلب جديد');
        } else if (msg.contains('CLIENT_NAME') || msg.contains('TOO_SHORT')) {
          _snack('اسم العميل قصير جداً (يجب أن يكون حرفين على الأقل)');
        } else {
          _snack('فشل إرسال الطلب، حاول مجدداً');
        }
      }
      return;
    }

    if (!ok) {
      if (mounted) {
        setState(() => _submitting = false);
        _snack('فشل إرسال الطلب، حاول مجدداً');
      }
      return;
    }

    if (!mounted) return;
    setState(() => _submitting = false);

    // تجهيز بيانات الطلب بشكل صحيح لشاشة المطابقة
    final requestData = {
      'typ': request.elm,           // 0 = عقار, 1 = سيارة
      'trx': request.typ,           // 0 = بيع, 1 = إيجار
      'price': request.prc,
      'city': request.notes,        // مؤقتاً (يمكن تحسينه لاحقاً)
      'currency': request.cur,
    };

    // بعد إرسال الطلب، نذهب لشاشة العروض المطابقة
    // وعند الضغط على رجوع من العروض المطابقة نذهب لمواعيدي بدل إضافة طلب
    if (!mounted) return;
    context.go('/matching-offers', extra: requestData);
  }

  void _snack(String m) {
    if (!mounted) return;
    AppTheme.showSnackBar(context, SnackBar(content: Text(m)));
  }

  // ── مساعدات التصنيف من Config (مطابقة لشاشة العرض) ──

  Map<int, String> _mapFromDynamic(dynamic data) {
    final result = <int, String>{};
    if (data is Map) {
      data.forEach((key, value) {
        final id = int.tryParse(key.toString());
        if (id == null) return;
        if (value is String) {
          result[id] = value;
        } else if (value is Map) {
          result[id] = value['nm']?.toString() ??
              value['name']?.toString() ??
              value.toString();
        } else {
          result[id] = value.toString();
        }
      });
    } else if (data is List) {
      for (int i = 0; i < data.length; i++) {
        final value = data[i];
        if (value is String) {
          result[i] = value;
        } else if (value is Map) {
          result[i] = value['nm']?.toString() ??
              value['name']?.toString() ??
              value.toString();
        } else {
          result[i] = value.toString();
        }
      }
    }
    return result;
  }

  Map<int, String> _categoryGroupMap() {
    final config = context.read<ConfigProvider>().config;
    final categories = _selectedElement == 1
        ? config?.vehicleCategories
        : config?.propertyCategories;
    if (categories != null && categories.isNotEmpty) {
      return _mapFromDynamic(categories);
    }
    return {0: _selectedElement == 1 ? 'مركبة' : 'عقار'};
  }

  Map<int, String> _subCategoryMap(int mainId) {
    final config = context.read<ConfigProvider>().config;
    final categories = _selectedElement == 1
        ? config?.vehicleCategories
        : config?.propertyCategories;
    final mainItem = categories?['$mainId'];
    if (mainItem is Map) {
      final subSource = mainItem['sub'] ?? mainItem['children'] ?? mainItem;
      final subMap = _mapFromDynamic(subSource);
      if (subMap.isNotEmpty) return subMap;
    }
    return {mainId: _categoryGroupMap()[mainId] ?? '—'};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground,
        elevation: 0,
        title: const Text('إضافة طلب جديد',
            style: TextStyle(
                color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppTheme.textGrey),
          onPressed: () => context.pop(),
        ),
      ),
      body: Stack(
        children: [
          Stepper(
            type: StepperType.vertical,
            currentStep: _currentStep,
            onStepTapped: (s) => setState(() => _currentStep = s),
            onStepContinue: _next,
            onStepCancel: _prev,
            steps: [_step1(), _step2(), _step3()],
            controlsBuilder: (context, details) => Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Row(children: [
                ElevatedButton(
                  onPressed: _submitting
                      ? null
                      : (_currentStep == 2
                          ? _submit
                          : details.onStepContinue),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGold,
                    foregroundColor: AppTheme.deepBlack,
                  ),
                  child: Text(_currentStep == 2 ? 'إرسال الطلب' : 'التالي'),
                ),
                if (_currentStep > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: TextButton(
                      onPressed: details.onStepCancel,
                      child: const Text('السابق',
                          style: TextStyle(color: AppTheme.textGrey)),
                    ),
                  ),
              ]),
            ),
          ),
          if (_submitting)
            Container(
              color: const Color.fromRGBO(0, 0, 0, 0.6),
              child: const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryGold),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Step 1: نوع الطلب والتصنيف ───
  Step _step1() {
    final mainCategories = _selectedElement != null
        ? _categoryGroupMap()
        : <int, String>{};
    final subCategories = _selectedMainCat != null
        ? _subCategoryMap(_selectedMainCat!)
        : <int, String>{};

    return Step(
      title: const Text('نوع الطلب',
          style: TextStyle(
              color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
      content: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _dd('نوع الطلب', ['شراء', 'استئجار'],
            (v) => setState(() {
                  _selectedType = v == 'شراء' ? 0 : 1;
                })),
        AppTheme.gapHeightLarge,
        _dd('نوع العنصر', ['عقار', 'سيارة'],
            (v) => setState(() {
                  _selectedElement = v == 'عقار' ? 0 : 1;
                  _selectedMainCat = null;
                  _selectedSubCat  = null;
                  _customSubCtrl.clear();
                })),
        AppTheme.gapHeightLarge,
        if (_selectedElement != null) ...[
          DropdownButtonFormField<int>(
            value: _selectedMainCat,
            dropdownColor: AppTheme.surfaceBlack,
            style: const TextStyle(color: AppTheme.textWhite),
            decoration: const InputDecoration(
                labelText: 'التصنيف الرئيسي (اختياري)',
                border: OutlineInputBorder()),
            items: mainCategories.entries
                .map((e) =>
                    DropdownMenuItem(value: e.key, child: Text(e.value)))
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
                  labelText: 'التصنيف الفرعي (اختياري)',
                  border: OutlineInputBorder()),
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
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
          ],
        ],
        if (_selectedType != null) ...[
          AppTheme.gapHeightMedium,
          Container(
            padding: AppTheme.paddingAllSmall,
            decoration: BoxDecoration(
              color: AppTheme.surfaceBlack,
              border: Border.all(
                  color: AppTheme.primaryGold.withOpacity(0.4)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _selectedType == 0
                  ? 'المكتب يتقاضى عمولة 3% عند إتمام عملية الشراء.'
                  : 'المكتب يتقاضى أجرة نصف شهر عند إتمام عملية الاستئجار.',
              style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSmall),
            ),
          ),
        ],
      ]),
      isActive: _currentStep >= 0,
    );
  }

  // ─── Step 2: معلومات العميل والميزانية ───
  Step _step2() => Step(
        title: const Text('معلومات العميل',
            style: TextStyle(
                color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        content: Column(children: [
          TextField(
            controller: _clientNameCtrl,
            decoration: const InputDecoration(
              labelText: 'اسم العميل (إلزامي)',
              filled: true,
              fillColor: AppTheme.surfaceBlack,
              border: OutlineInputBorder(),
            ),
          ),
          AppTheme.gapHeightMedium,
          TextField(
            controller: _clientPhoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'هاتف العميل (إلزامي)',
              hintText: 'مثال: 09xxxxxxxx',
              filled: true,
              fillColor: AppTheme.surfaceBlack,
              border: OutlineInputBorder(),
            ),
          ),
          AppTheme.gapHeightMedium,
          // الميزانية + العملة
          Row(children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'الميزانية المتوقعة',
                  filled: true,
                  fillColor: AppTheme.surfaceBlack,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            AppTheme.gapWidthSmall,
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<int>(
                value: _cur,
                dropdownColor: AppTheme.surfaceBlack,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: AppTheme.surfaceBlack,
                ),
                items: const [
                  DropdownMenuItem(value: Currency.dollar, child: Text('دولار')),
                  DropdownMenuItem(value: Currency.lbp,    child: Text('ل.س')),
                ],
                onChanged: (v) => setState(() => _cur = v ?? Currency.lbp),
              ),
            ),
          ]),
          AppTheme.gapHeightSmall,
          // توضيح: بيانات العميل للإدارة وصاحب الطلب فقط
          Container(
            padding: AppTheme.paddingAllSmall,
            decoration: BoxDecoration(
              color: AppTheme.primaryGold.withOpacity(0.06),
              borderRadius: AppTheme.radiusSmall,
              border: Border.all(
                  color: AppTheme.primaryGold.withOpacity(0.2)),
            ),
            child: const Row(children: [
              Icon(Icons.lock_outline,
                  color: AppTheme.primaryGold, size: 14),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'بيانات العميل تظهر فقط لك وللإدارة — لا تُكشف لأي طرف آخر.',
                  style: TextStyle(
                      color: AppTheme.textGrey,
                      fontSize: AppTheme.fontSizeCaption,
                      height: 1.4),
                ),
              ),
            ]),
          ),
        ]),
        isActive: _currentStep >= 1,
      );

  // ─── Step 3: المواصفات والملاحظات ───
  Step _step3() => Step(
        title: const Text('المواصفات والملاحظات',
            style: TextStyle(
                color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        content: Column(children: [
          TextField(
            controller: _specsCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'المواصفات المطلوبة (اختيارية)',
              hintText:
                  'مثال: 3 غرف نوم، موقف سيارة، بالقرب من المدارس...',
              filled: true,
              fillColor: AppTheme.surfaceBlack,
              border: OutlineInputBorder(),
            ),
          ),
          AppTheme.gapHeightMedium,
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'ملاحظات إضافية (اختيارية)',
              filled: true,
              fillColor: AppTheme.surfaceBlack,
              border: OutlineInputBorder(),
            ),
          ),
          AppTheme.gapHeightLarge,
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: const Icon(Icons.send),
              label: Text(
                  _submitting ? 'جارٍ الإرسال...' : 'إرسال الطلب',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGold,
                foregroundColor: AppTheme.deepBlack,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
        ]),
        isActive: _currentStep >= 2,
      );

  Widget _dd(String label, List<String> items, Function(String) onSelected) =>
      DropdownButtonFormField<String>(
        value: null,
        items: items
            .map((i) => DropdownMenuItem(value: i, child: Text(i)))
            .toList(),
        onChanged: (v) => onSelected(v!),
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: AppTheme.surfaceBlack,
          border: OutlineInputBorder(borderRadius: AppTheme.radiusMedium),
        ),
      );
}

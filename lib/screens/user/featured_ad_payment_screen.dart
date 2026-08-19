import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../providers/payment_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/payment_model.dart';
import '../../services/storage_service.dart';
import '../../core/network/supabase_service.dart';
import '../../core/validation/input_validators.dart';

/// شاشة شراء «إعلان مميز» مدفوع لعرض محدد (قرار المالك 2026-07-26)
/// المدة 1-4 أسابيع، الأسعار من config.featuredAdPrices (fmsp بالسيرفر)
/// تعيد استخدام نمط شاشة دفع الباقة: قناة + إثبات + مرجع → tp=1 بجدول payments
class FeaturedAdPaymentScreen extends StatefulWidget {
  final String offerId;

  const FeaturedAdPaymentScreen({super.key, required this.offerId});

  @override
  State<FeaturedAdPaymentScreen> createState() =>
      _FeaturedAdPaymentScreenState();
}

class _FeaturedAdPaymentScreenState extends State<FeaturedAdPaymentScreen> {
  /// أرقام التحويل المهيكلة لأي قناة تُعرض عند توفرها (كود/رقم/سيرياتل/MTN)
  List<(String, String)> _channelNumbers(Map<String, dynamic> ch) {
    const fields = {
      'account_number': 'الكود / رقم الحساب',
      'number': 'الرقم',
      'syriatel_number': 'سيرياتل',
      'mtn_number': 'MTN',
    };
    final out = <(String, String)>[];
    for (final e in fields.entries) {
      // 2026-08-14: عند وجود الرقم الموحّد (number) تُتجاهل الحقول القديمة
      // لقناة تحويل الرصيد حتى لا يظهر الرقم مكرراً بمسميات مختلفة.
      if ((e.key == 'syriatel_number' || e.key == 'mtn_number') &&
          (ch['number'] ?? '').toString().isNotEmpty) {
        continue;
      }
      final v = (ch[e.key] ?? '').toString();
      if (v.isNotEmpty) out.add((e.value, v));
    }
    return out;
  }


  int _weeks = 1; // المدة المختارة (1-4)
  String _channel = '';
  final _refCtrl = TextEditingController();
  final _senderPhoneCtrl = TextEditingController(); // رقم هاتف المُحوِّل (Bug #35)
  XFile? _proofImage;
  bool _uploading = false;
  String _progress = '';

  final _storage = StorageService();

  @override
  void dispose() {
    _refCtrl.dispose();
    _senderPhoneCtrl.dispose();
    super.dispose();
  }

  /// هل القناة المختارة تحتاج رقم هاتف المُحوِّل؟
  bool get _needsSenderPhone => _channel == 'balance' || _channel == 'syriatel_cash';

  int _priceFor(int weeks, dynamic config) {
    if (config != null) {
      final p = config.featuredAdPrices['w$weeks'];
      if (p is num) return p.toInt();
      if (p != null) return int.tryParse('$p') ?? 0;
    }
    // افتراضيات احتياطية (مطابقة لافتراضيات ConfigModel)
    const def = {1: 50000, 2: 95000, 3: 135000, 4: 180000};
    return def[weeks] ?? 0;
  }

  String get _weeksLabel {
    switch (_weeks) {
      case 1:
        return 'أسبوع واحد';
      case 2:
        return 'أسبوعين';
      default:
        return '$_weeks أسابيع';
    }
  }

  Future<void> _pickProof() async {
    final file = await _storage.pickImage(fromCamera: false);
    if (file != null) {
      setState(() => _proofImage = file);
    }
  }

  Future<String?> _uploadProof(String userId) async {
    if (_proofImage == null) return null;
    try {
      final storage = SupabaseService().storage;
      final fileName = 'proof_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = '$userId/$fileName';

      final bytes = kIsWeb
          ? await _proofImage!.readAsBytes()
          : await (await _storage.compressImage(File(_proofImage!.path)) ??
                  File(_proofImage!.path))
              .readAsBytes();

      await storage.from(StorageService.paymentProofsBucket).uploadBinary(
            path,
            bytes,
            fileOptions:
                // upsert:false — انظر payment_screen.dart (سياسة SELECT مرفوضة أمنياً)
                const FileOptions(cacheControl: '3600', upsert: false),
          );
      return path;
    } catch (e) {
      return null;
    }
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    final paymentProv = context.read<PaymentProvider>();
    final config = context.read<ConfigProvider>().config;
    final user = auth.userModel;

    if (user == null) {
      _snack('يجب تسجيل الدخول أولاً');
      return;
    }
    if (_channel.isEmpty) {
      _snack('يرجى اختيار قناة الدفع');
      return;
    }
    if (_proofImage == null) {
      _snack('يرجى رفع إثبات الدفع');
      return;
    }
    final refNum = InputValidators.normalizeDigits(_refCtrl.text.trim());
    if (refNum.isEmpty) {
      _snack('يرجى إدخال رقم العملية / المرجع');
      return;
    }

    // Bug #35: التحقق من رقم هاتف المُحوِّل للقنوات اللي بتحتاجه
    String senderPhone = '';
    // 📞 PHONE-002 (2026-08-15) — قرار المالك: «الهاتف الذي تم التحويل منه
    // ليس إلزامياً». كان الحقل يوقف العملية كلياً إن تُرك فارغاً.
    // الآن: يُقبل فارغاً، وإن كُتب يُطبَّع ويُرسل (يفيد الإدارة بمطابقة
    // الحوالة). ولا نرفض رقماً قصيراً بصمت — نتجاهله فقط إن كان فارغاً.
    if (_needsSenderPhone) {
      final raw = _senderPhoneCtrl.text.trim();
      if (raw.isNotEmpty) {
        senderPhone = InputValidators.toLocalSyrianPhone(raw);
      }
    }

    final price = _priceFor(_weeks, config);
    if (price <= 0) {
      _snack('تعذّر تحديد السعر، حاول لاحقاً');
      return;
    }

    setState(() {
      _uploading = true;
      _progress = 'جارٍ رفع إثبات الدفع...';
    });

    final url = await _uploadProof(user.uid);
    if (url == null) {
      setState(() => _uploading = false);
      _snack('فشل رفع الإثبات، حاول مرة أخرى');
      return;
    }

    setState(() => _progress = 'جارٍ تسجيل الدفعة...');

    final payment = PaymentModel(
      id: '',
      uid: user.uid,
      tp: 1, // 1 = إعلان مميز مدفوع
      pkg: 0,
      amt: price.toDouble(),
      cur: 1, // ليرة سورية
      mtd: 0,
      channel: _channel,
      proof: url,
      ref: refNum,
      sts: 0, // قيد المراجعة
      // Bug #35: إضافة رقم هاتف المُحوِّل مع بيانات العرض
      meta: {
        'offer_id': widget.offerId,
        'weeks': _weeks,
        if (senderPhone.isNotEmpty) 'sender_phone': senderPhone,
      },
      tsCrt: DateTime.now(),
    );

    bool ok = false;
    try {
      ok = await paymentProv.makePayment(payment);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      final msg = e.toString();
      if (msg.contains('PENDING_PAYMENT_EXISTS')) {
        _snack('لديك دفعة إعلان مميز قيد المراجعة لهذا العرض — انتظر اعتمادها');
      } else if (msg.contains('NOT_OFFER_OWNER')) {
        _snack('لا يمكن شراء إعلان لعرض لا تملكه');
      } else if (msg.contains('MISSING_PAYMENT_PROOF_OR_REFERENCE')) {
        _snack('يرجى التأكد من رفع إثبات الدفع وإدخال رقم العملية');
      } else {
        _snack('فشل تسجيل الدفعة، حاول مجدداً');
      }
      return;
    }

    if (!mounted) return;
    setState(() => _uploading = false);

    if (ok) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.surfaceBlack,
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: AppTheme.successGreen, size: 28),
              AppTheme.gapWidthSmall,
              Text('تم إرسال طلبك',
                  style: TextStyle(color: AppTheme.textWhite)),
            ],
          ),
          content: Text(
            'تم تسجيل دفعة الإعلان المميز ($_weeksLabel) وهي قيد المراجعة.\n'
            'سيتم تفعيل التمييز فور اعتماد الإدارة للدفعة.',
            style: const TextStyle(color: AppTheme.textGrey, height: 1.5),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGold),
              child: const Text('حسناً',
                  style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      );
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ConfigProvider>().config;
    final channels = config?.enabledPayChannels ?? [];
    final price = _priceFor(_weeks, config);

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground,
        elevation: 0,
        title: const Text('شراء إعلان مميز',
            style: TextStyle(
                color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AppTheme.primaryGold, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: AppTheme.paddingAllXL,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── اختيار المدة ───
            const Text('مدة الإعلان المميز:',
                style: TextStyle(
                    color: AppTheme.primaryGold,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            AppTheme.gapHeightSmall,
            ...List.generate(4, (i) {
              final w = i + 1;
              final p = _priceFor(w, config);
              final selected = _weeks == w;
              final label = w == 1
                  ? 'أسبوع واحد'
                  : w == 2
                      ? 'أسبوعين'
                      : '$w أسابيع';
              return GestureDetector(
                onTap: () => setState(() => _weeks = w),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.primaryGold.withOpacity(0.12)
                        : AppTheme.surfaceBlack,
                    borderRadius: AppTheme.radiusMedium,
                    border: Border.all(
                      color: selected
                          ? AppTheme.primaryGold
                          : Colors.white12,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: selected
                          ? AppTheme.primaryGold
                          : AppTheme.textGrey,
                      size: 20,
                    ),
                    AppTheme.gapWidthSmall,
                    Expanded(
                      child: Text(label,
                          style: const TextStyle(
                              color: AppTheme.textWhite, fontSize: AppTheme.fontSizeMedium)),
                    ),
                    Text('$p ل.س',
                        style: const TextStyle(
                            color: AppTheme.primaryGold,
                            fontSize: AppTheme.fontSizeBody,
                            fontWeight: FontWeight.bold)),
                  ]),
                ),
              );
            }),
            AppTheme.gapHeightLarge,

            // ─── قناة الدفع ───
            const Text('قناة الدفع:',
                style: TextStyle(
                    color: AppTheme.primaryGold,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            AppTheme.gapHeightSmall,
            if (channels.isEmpty)
              const Text('لا توجد قنوات دفع مفعّلة حالياً',
                  style: TextStyle(color: AppTheme.textGrey)),
            ...channels.map((entry) {
              final key = entry.key;
              final ch = entry.value;
              final selected = _channel == key;
              final chName = (ch['name'] ?? key).toString();
              final chInstr = (ch['instructions'] ?? '').toString();
              return GestureDetector(
                onTap: () => setState(() => _channel = key),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: AppTheme.paddingAllMedium,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.primaryGold.withOpacity(0.12)
                        : AppTheme.surfaceBlack,
                    borderRadius: AppTheme.radiusMedium,
                    border: Border.all(
                      color: selected
                          ? AppTheme.primaryGold
                          : Colors.white12,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: selected
                              ? AppTheme.primaryGold
                              : AppTheme.textGrey,
                          size: 20,
                        ),
                        AppTheme.gapWidthSmall,
                        Text(chName,
                            style: const TextStyle(
                                color: AppTheme.textWhite,
                                fontSize: AppTheme.fontSizeMedium,
                                fontWeight: FontWeight.bold)),
                      ]),
                      if (selected && chInstr.isNotEmpty) ...[
                        AppTheme.gapHeightSmall,
                        Text(chInstr,
                            style: const TextStyle(
                                color: AppTheme.textGrey,
                                fontSize: AppTheme.fontSizeSmall,
                                height: 1.5)),
                      ],
                      if (selected)
                        for (final kv in _channelNumbers(ch))
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('${kv.$1}: ${kv.$2}',
                                style: const TextStyle(
                                    color: AppTheme.primaryGold,
                                    fontSize: AppTheme.fontSizeBody,
                                    fontWeight: FontWeight.bold)),
                          ),
                    ],
                  ),
                ),
              );
            }),
            AppTheme.gapHeightLarge,

            // Bug #35: حقل رقم هاتف المُحوِّل للقنوات اللي بتحتاجه
            if (_needsSenderPhone) ...[
              // 📞 PHONE-002: صار اختيارياً بقرار المالك
              const Text('📱 رقم هاتفك (الذي تم التحويل منه) — اختياري:',
                  style: TextStyle(
                      color: AppTheme.primaryGold,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
              AppTheme.gapHeightSmall,
              TextFormField(
                controller: _senderPhoneCtrl,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: const InputDecoration(
                  hintText: 'مثلاً: 09xxxxxxxx',
                  filled: true,
                  fillColor: AppTheme.surfaceBlack,
                  prefixIcon: Icon(Icons.phone, color: AppTheme.primaryGold),
                ),
              ),
              AppTheme.gapHeightLarge,
            ],

            // ─── إثبات الدفع ───
            const Text('إثبات الدفع:',
                style: TextStyle(
                    color: AppTheme.primaryGold,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            AppTheme.gapHeightSmall,
            GestureDetector(
              onTap: _uploading ? null : _pickProof,
              child: Container(
                width: double.infinity,
                padding: AppTheme.paddingAllLarge,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBlack,
                  borderRadius: AppTheme.radiusMedium,
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(children: [
                  Icon(
                    _proofImage == null
                        ? Icons.upload_file_outlined
                        : Icons.check_circle,
                    color: _proofImage == null
                        ? AppTheme.textGrey
                        : AppTheme.successGreen,
                  ),
                  AppTheme.gapWidthSmall,
                  Expanded(
                    child: Text(
                      _proofImage == null
                          ? 'اضغط لاختيار صورة إثبات الدفع (سكرين التحويل)'
                          : 'تم اختيار الصورة ✓ — اضغط للتغيير',
                      style: const TextStyle(
                          color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody),
                    ),
                  ),
                ]),
              ),
            ),
            AppTheme.gapHeightMedium,
            TextFormField(
              controller: _refCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppTheme.textWhite),
              decoration: const InputDecoration(
                labelText: 'رقم العملية / المرجع',
                hintText: 'مثال: 123456789',
                filled: true,
                fillColor: AppTheme.surfaceBlack,
                prefixIcon:
                    Icon(Icons.tag, color: AppTheme.primaryGold),
              ),
            ),
            AppTheme.gapHeightXXL,

            // ─── زر الإرسال ───
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _uploading ? null : _submit,
                icon: _uploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.star, color: Colors.black),
                label: Text(
                  _uploading ? _progress : 'تأكيد الشراء — $price ل.س',
                  style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../providers/payment_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/payment_model.dart';
import '../../services/storage_service.dart';
import '../../core/network/supabase_service.dart';
import '../../core/validation/input_validators.dart';
import '../../core/utils/app_utils.dart';
import '../../models/config_model.dart';

/// شاشة دفع اشتراك الباقة — Config-Driven (المرحلة 11)
///
/// تقرأ القنوات من `config.payChannels` بدل القنوات المضمّنة في الكود.
/// كل قناة تعرض بياناتها + تعليماتها ديناميكياً.
class PaymentScreen extends StatefulWidget {
  final int packageId;
  // السعر يُجلب من Config مباشرة — لا يُمرَّر من URL لمنع التلاعب

  const PaymentScreen({
    super.key,
    required this.packageId,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  String _channel = ''; // مفتاح القناة المختارة
  static const int _currency = 1; // عملة موحدة: ل.س (الدفع بالعملة المحلية فقط)
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

  String _normalizePhoneToLocalFormat(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return '';
    // 9639xxxxxxxx → 09xxxxxxxx
    if (digits.startsWith('963') && digits.length == 12) {
      return '0${digits.substring(3)}';
    }
    // 09xxxxxxxx (already local)
    if (digits.startsWith('09') && digits.length == 10) {
      return digits;
    }
    // 9xxxxxxxx (without leading 0)
    if (digits.startsWith('9') && digits.length == 9) {
      return '0$digits';
    }
    return digits;
  }

  /// 💱 PRICE-UNIT-001 (2026-08-15): السعر النهائي **بالليرة** أو `null`.
  ///
  /// قرار المالك: `pkg.<id>.pr` بالدولار (10 و25)، والتحصيل بالليرة عبر
  /// `fx.usd_syp`. الحساب صار في مكان واحد (`ConfigModel.packagePriceSyp`)
  /// يطابق `create_payment_internal` حرفاً بحرف ⇒ لا AMOUNT_MISMATCH.
  ///
  /// ⚠️ حُذفت الافتراضيات (`case 1: return 10`) بأمر المالك «بدي ما يكون شي
  /// افتراضي»: كانت تعيد قيمة **بالدولار** حيث يُتوقَّع مبلغ بالليرة، فلو غاب
  /// الإعداد لأرسلت الواجهة 10 بدل 150000 ⇒ رفض خادمي محيّر للمستخدم.
  /// الآن الغياب يُعلَن صراحةً (§13) والزر يُعطَّل.
  double? _priceFromConfig(ConfigModel? config) {
    final v = config?.packagePriceSyp(widget.packageId);
    return v?.toDouble();
  }

  String get _packageName {
    switch (widget.packageId) {
      case 1:
        return 'الفضية';
      case 2:
        return 'الذهبية';
      default:
        return '—';
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
      // المسار المعتمد في RLS: {uid}/{filename}
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
                // upsert:false — إلزامي: وضع upsert بالسيرفر يتطلب سياسة SELECT
                // التي تفتح خصوصية الوثائق؛ أسماء الملفات فريدة فلا حاجة له.
                const FileOptions(cacheControl: '3600', upsert: false),
          );
      // bucket خاص → نُرجع المسار فقط (admin يستخدم signed URL أو direct access)
      return path;
    } catch (e) {return null;
    }
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    final paymentProv = context.read<PaymentProvider>();
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

    setState(() {
      _uploading = true;
      _progress = 'جارٍ رفع إثبات الدفع...';
    });

    String proofUrl = '';
    final url = await _uploadProof(user.uid);
    if (url == null) {
      setState(() => _uploading = false);
      _snack('فشل رفع الإثبات، حاول مرة أخرى');
      return;
    }
    proofUrl = url;

    setState(() => _progress = 'جارٍ تسجيل الدفعة...');

    final config = context.read<ConfigProvider>().config;
    final priceSyp = _priceFromConfig(config);
    if (priceSyp == null) {
      // §13 No-Silent-Probes: نقص إعداد السعر يوقف العملية بإعلان صريح
      // بدل إرسال مبلغ مخترَع يرفضه السيرفر برسالة تقنية غامضة.
      setState(() => _uploading = false);
      _snack('تعذّر تحديد سعر الباقة — يرجى المحاولة لاحقاً أو مراسلة المكتب');
      return;
    }

    final payment = PaymentModel(
      id: '',
      uid: user.uid,
      tp: 0, // 0 = اشتراك باقة
      pkg: widget.packageId,
      amt: priceSyp,
      cur: _currency,
      mtd: 0, // legacy
      channel: _channel,
      proof: proofUrl,
      ref: refNum,
      sts: 0, // قيد المراجعة
      tsCrt: DateTime.now(),
      // Bug #35: إضافة رقم هاتف المُحوِّل للقنوات اللي بتحتاجه
      meta: senderPhone.isNotEmpty ? {'sender_phone': senderPhone} : const {},
    );

    bool ok = false;
    try {
      ok = await paymentProv.makePayment(payment);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      final msg = e.toString();
      if (msg.contains('PENDING_PAYMENT_EXISTS') || msg.contains('DUPLICATE_PENDING_PAYMENT')) {
        _snack('لديك دفعة قيد المراجعة حالياً لنفس الباقة، يرجى انتظار اعتمادها قبل إرسال دفعة جديدة');
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
              Text('تم بنجاح',
                  style: TextStyle(color: AppTheme.textWhite)),
            ],
          ),
          content: const Text(
            'تم تسجيل دفعتك بنجاح ✅\n\nستراجعها الإدارة خلال 24 ساعة وستصلك رسالة عند التفعيل.',
            style: TextStyle(color: AppTheme.textGrey),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                context.go('/user/home');
              },
              child: const Text('حسناً',
                  style: TextStyle(color: AppTheme.primaryGold)),
            ),
          ],
        ),
      );
    } else {
      _snack('حدث خطأ، حاول مرة أخرى');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    AppTheme.showSnackBar(context, SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ConfigProvider>().config;
    final channels = config?.enabledPayChannels ?? [];

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('دفع الاشتراك'),
        backgroundColor: AppTheme.scaffoldBackground,
        elevation: 0,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: AppTheme.paddingAllLarge,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _summaryCard(),
                AppTheme.gapHeightXL,
                _sectionTitle('💳 اختر قناة الدفع'),
                if (channels.isEmpty)
                  _emptyChannelsCard()
                else
                  ...channels.map((e) => _channelCard(e.key, e.value)),
                if (_channel.isNotEmpty) ...[
                  AppTheme.gapHeightXL,
                  _channelDetailsCard(_findChannel(channels, _channel)),
                  AppTheme.gapHeightXL,

                  // Bug #35: حقل رقم هاتف المُحوِّل للقنوات اللي بتحتاجه
                  if (_needsSenderPhone) ...[
                    // 📞 PHONE-002: صار اختيارياً بقرار المالك
                    _sectionTitle('📱 رقم هاتفك (الذي تم التحويل منه) — اختياري'),
                    TextField(
                      controller: _senderPhoneCtrl,
                      style: const TextStyle(color: AppTheme.textWhite),
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        hintText: 'مثلاً: 09xxxxxxxx',
                        prefixIcon: Icon(Icons.phone, color: AppTheme.primaryGold),
                      ),
                    ),
                    AppTheme.gapHeightXL,
                  ],

                  _sectionTitle('🔢 رقم العملية / المرجع'),
                  TextField(
                    controller: _refCtrl,
                    style: const TextStyle(color: AppTheme.textWhite),
                    decoration: const InputDecoration(
                      hintText: 'مثلاً: TRX-123456 / رقم الإيصال',
                      prefixIcon:
                          Icon(Icons.tag, color: AppTheme.primaryGold),
                    ),
                  ),
                  AppTheme.gapHeightXL,
                  _sectionTitle('📷 صورة إثبات الدفع'),
                  _proofPicker(),
                  AppTheme.gapHeightXXL,
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _uploading ? null : _submit,
                      icon: const Icon(Icons.check, color: Colors.black),
                      label: const Text('تأكيد الدفع',
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: AppTheme.fontSizeSubtitle)),
                    ),
                  ),
                ],
                AppTheme.gapHeightXL,
              ],
            ),
          ),
          if (_uploading)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                        color: AppTheme.primaryGold),
                    AppTheme.gapHeightLarge,
                    Text(_progress,
                        style: const TextStyle(color: AppTheme.textWhite)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Map<String, dynamic>? _findChannel(
      List<MapEntry<String, Map<String, dynamic>>> channels, String key) {
    for (final e in channels) {
      if (e.key == key) return e.value;
    }
    return null;
  }

  // ═══════════════════════════════════════════════════
  // Widgets
  // ═══════════════════════════════════════════════════

  Widget _summaryCard() {
    return Container(
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryGold, Color(0xFFFFD700)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppTheme.radiusLarge,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('الاشتراك بالباقة',
              style: TextStyle(color: Colors.black87, fontSize: AppTheme.fontSizeBody)),
          Text(_packageName,
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: AppTheme.fontSizeLarge,
                  fontWeight: FontWeight.bold)),
          const Divider(color: Colors.black26, height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('المبلغ المطلوب:',
                  style: TextStyle(color: Colors.black87)),
              Text(
                _getDisplayAmount(),
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getDisplayAmount() {
    final config = context.read<ConfigProvider>().config;
    final price = _priceFromConfig(config);
    // §13: لا نخترع رقماً عند نقص الإعداد — نقولها للمستخدم.
    if (price == null) return 'السعر غير متاح حالياً';
    return AppUtils.formatPrice(price, currency: 1);
  }


  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text,
            style: const TextStyle(
                color: AppTheme.primaryGold,
                fontWeight: FontWeight.bold,
                fontSize: AppTheme.fontSizeMedium)),
      );

  Widget _emptyChannelsCard() {
    return Container(
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.warningOrange.withOpacity(0.1),
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: AppTheme.warningOrange.withOpacity(0.5)),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppTheme.warningOrange),
          AppTheme.gapWidthSmall,
          Expanded(
            child: Text(
              'لا توجد قنوات دفع مفعّلة حالياً.\nيرجى التواصل مع الإدارة.',
              style: TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeBody),
            ),
          ),
        ],
      ),
    );
  }

  Widget _channelCard(String key, Map<String, dynamic> data) {
    final selected = _channel == key;
    final icon = (data['icon'] ?? '💳').toString();
    final name = (data['name'] ?? key).toString();
    return GestureDetector(
      onTap: () => setState(() => _channel = key),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: AppTheme.paddingAllLarge,
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryGold.withOpacity(0.15)
              : AppTheme.surfaceBlack,
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(
            color: selected
                ? AppTheme.primaryGold
                : Colors.white.withOpacity(0.08),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: AppTheme.fontSizeXL)),
            AppTheme.gapWidthMedium,
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  color: selected
                      ? AppTheme.primaryGold
                      : AppTheme.textWhite,
                  fontWeight: FontWeight.bold,
                  fontSize: AppTheme.fontSizeSubtitle,
                ),
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: selected
                  ? AppTheme.primaryGold
                  : AppTheme.textGrey,
            ),
          ],
        ),
      ),
    );
  }

  /// بطاقة تفاصيل القناة المختارة — تختلف حسب نوع القناة
  Widget _channelDetailsCard(Map<String, dynamic>? data) {
    if (data == null) return const SizedBox.shrink();
    final icon = (data['icon'] ?? '💳').toString();
    final name = (data['name'] ?? '').toString();
    final instructions = (data['instructions'] ?? '').toString();

    final fields = <Widget>[];

    switch (_channel) {
      case 'haram':
        if ((data['recipient_name'] ?? '').toString().isNotEmpty) {
          fields.add(_kv('اسم المستقبل', data['recipient_name'].toString()));
        }
        if ((data['recipient_phone'] ?? '').toString().isNotEmpty) {
          fields.add(_kv('رقم المستقبل', data['recipient_phone'].toString()));
        }
        break;
      case 'sham_cash':
        final qrUrl = (data['qr_image_url'] ?? '').toString();
        if (qrUrl.isNotEmpty) {
          fields.add(_qrImage(qrUrl));
          fields.add(AppTheme.gapHeightSmall);
        }
        if ((data['account_number'] ?? '').toString().isNotEmpty) {
          fields.add(_kv('رقم الحساب', data['account_number'].toString()));
        }
        break;
      case 'syriatel_cash':
        if ((data['number'] ?? '').toString().isNotEmpty) {
          fields.add(_kv('رقم التحويل', data['number'].toString()));
        }
        break;
      case 'balance':
        // 2026-08-14: رقم واحد موحّد = رقم المكتب الهاتفي (number).
        // الحقلان القديمان يُقرآن فقط إن بقيا معبّأين (توافق عكسي).
        if ((data['number'] ?? '').toString().isNotEmpty) {
          fields.add(_kv('رقم المكتب', data['number'].toString()));
        } else {
          if ((data['syriatel_number'] ?? '').toString().isNotEmpty) {
            fields.add(_kv('سيرياتل', data['syriatel_number'].toString()));
          }
          if ((data['mtn_number'] ?? '').toString().isNotEmpty) {
            fields.add(_kv('MTN', data['mtn_number'].toString()));
          }
        }
        break;
      case 'bank':
        if ((data['bank_name'] ?? '').toString().isNotEmpty) {
          fields.add(_kv('البنك', data['bank_name'].toString()));
        }
        if ((data['account_holder'] ?? '').toString().isNotEmpty) {
          fields.add(_kv('صاحب الحساب', data['account_holder'].toString()));
        }
        if ((data['account_number'] ?? '').toString().isNotEmpty) {
          fields.add(_kv('رقم الحساب', data['account_number'].toString()));
        }
        if ((data['iban'] ?? '').toString().isNotEmpty) {
          fields.add(_kv('IBAN', data['iban'].toString()));
        }
        if ((data['branch'] ?? '').toString().isNotEmpty) {
          fields.add(_kv('الفرع', data['branch'].toString()));
        }
        break;
    }

    return Container(
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 22)),
              AppTheme.gapWidthSmall,
              Text(name,
                  style: const TextStyle(
                      color: AppTheme.primaryGold,
                      fontWeight: FontWeight.bold,
                      fontSize: AppTheme.fontSizeSubtitle)),
            ],
          ),
          const Divider(color: AppTheme.textGrey, height: 18),
          if (fields.isEmpty)
            const Text(
              '⚠️ لم يتم إعداد بيانات هذه القناة بعد.\nيرجى التواصل مع الإدارة.',
              style: TextStyle(color: AppTheme.warningOrange, fontSize: AppTheme.fontSizeBody),
            )
          else
            ...fields,
          if (instructions.isNotEmpty) ...[
            AppTheme.gapHeightSmall,
            Container(
              padding: AppTheme.paddingAllMedium,
              decoration: BoxDecoration(
                color: AppTheme.infoBlue.withOpacity(0.08),
                borderRadius: AppTheme.radiusSmall,
                border: Border.all(color: AppTheme.infoBlue.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline,
                      color: Colors.lightBlueAccent, size: 18),
                  AppTheme.gapWidthSmall,
                  Expanded(
                    child: Text(
                      instructions,
                      style: const TextStyle(
                          color: AppTheme.textWhite, fontSize: 12.5, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _qrImage(String url) {
    return Center(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(color: AppTheme.primaryGold, width: 2),
        ),
        padding: AppTheme.paddingAllSmall,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            url,
            width: 180,
            height: 180,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Padding(
              padding: AppTheme.paddingAllXL,
              child: Text('فشل تحميل QR',
                  style: TextStyle(color: AppTheme.errorRed)),
            ),
            loadingBuilder: (_, child, p) => p == null
                ? child
                : const Padding(
                    padding: EdgeInsets.all(30),
                    child: CircularProgressIndicator(),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _proofPicker() {
    return Column(
      children: [
        GestureDetector(
          onTap: _pickProof,
          child: Container(
            height: 180,
            decoration: BoxDecoration(
              color: AppTheme.surfaceBlack,
              borderRadius: AppTheme.radiusMedium,
              border: Border.all(
                color: _proofImage != null
                    ? AppTheme.successGreen
                    : AppTheme.primaryGold.withOpacity(0.4),
                width: 1.5,
              ),
            ),
            child: _proofImage == null
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.upload_file,
                            color: AppTheme.primaryGold, size: 48),
                        AppTheme.gapHeightSmall,
                        Text(
                          'اضغط لرفع صورة إيصال التحويل',
                          style: TextStyle(
                              color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody),
                        ),
                      ],
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: kIsWeb
                        ? Image.network(_proofImage!.path,
                            fit: BoxFit.cover, width: double.infinity)
                        : Image.file(File(_proofImage!.path),
                            fit: BoxFit.cover, width: double.infinity),
                  ),
          ),
        ),
        if (_proofImage != null)
          TextButton.icon(
            onPressed: () => setState(() => _proofImage = null),
            icon: const Icon(Icons.close, color: AppTheme.errorRed),
            label: const Text('إزالة الصورة',
                style: TextStyle(color: AppTheme.errorRed)),
          ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 95,
            child: Text(k,
                style: const TextStyle(
                    color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
          ),
          Expanded(
            child: SelectableText(
              v,
              style: const TextStyle(
                  color: AppTheme.textWhite,
                  fontSize: AppTheme.fontSizeBody,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

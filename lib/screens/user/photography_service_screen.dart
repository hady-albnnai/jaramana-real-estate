import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/supabase_service.dart';
import '../../models/photography_task_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../widgets/bottom_nav_bar.dart';
import 'add_offer_screen.dart';
import '../../core/utils/error_utils.dart';
import '../../core/utils/app_utils.dart';

/// ════════════════════════════════════════════════════════════════════
/// شاشة خدمة التصوير العقاري — للمستخدمين العاديين والوسطاء (ليس للإدارة).
/// تشرح الخدمة بشكل واضح + نموذج طلب تصوير + قائمة بطلبات المستخدم وحالتها.
/// ════════════════════════════════════════════════════════════════════
class PhotographyServiceScreen extends StatefulWidget {
  const PhotographyServiceScreen({super.key});

  @override
  State<PhotographyServiceScreen> createState() =>
      _PhotographyServiceScreenState();
}

class _PhotographyServiceScreenState extends State<PhotographyServiceScreen> {
  List<PhotographyTaskModel> _myRequests = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMyRequests());
  }

  bool get _hasActiveRequest =>
      _myRequests.any((t) => t.sts == 0 || t.sts == 1 || t.sts == 2);

  /// 💰 أجر التصوير من إعدادات الإدارة (photoPrice) — 0 يعني مجاني.
  int get _photoFee =>
      context.watch<ConfigProvider>().config?.photographyPrice ?? 1000;

  /// الأجر بفواصل الآلاف: 1000 → «1,000»
  String get _photoFeeTxt => _photoFee.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

  Future<void> _loadMyRequests() async {
    final uid = context.read<AuthProvider>().userModel?.uid ?? '';
    if (uid.isEmpty) {
      setState(() {
        _loading = false;
        _myRequests = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await SupabaseService().invokeFunction(
        'admin-photography',
        body: {
          'action': 'my_photo_requests',
          'user_uid': uid,
        },
      );
      final data =
          response.data is Map ? Map<String, dynamic>.from(response.data) : null;
      if (!mounted) return;
      if (data != null && data['success'] == true) {
        final list = (data['tasks'] as List? ?? [])
            .map((row) => PhotographyTaskModel.fromSupabase(
                  Map<String, dynamic>.from(row as Map),
                  row['id'].toString(),
                ))
            .toList();
        setState(() {
          _myRequests = list;
          _loading = false;
        });
      } else {
        setState(() {
          _error = data?['error']?.toString() ?? 'فشل تحميل الطلبات';
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'فشل تحميل الطلبات — تحقق من اتصال الإنترنت';
        _loading = false;
      });
    }
  }

  void _snack(String m, {bool ok = false}) {
    if (!mounted) return;
    AppTheme.showSnackBar(
      context,
      SnackBar(
        content: Text(m),
        backgroundColor: ok ? AppTheme.successGreen : null,
      ),
    );
  }

  // ✅ Fix for Bug #23: تطبيع رقم الهاتف إلى الصيغة المحلية (09xxxxxxxx)
  // يتعامل مع الصيغ المختلفة: +963938123456, 963938123456, 0938123456, 938123456
  String _normalizePhoneToLocalFormat(String phone) {
    if (phone.isEmpty) return '';
    
    // إزالة جميع الأحرف غير الرقمية
    var cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');
    
    // إزالة كود الدولة إذا كان موجوداً
    if (cleaned.startsWith('963')) {
      cleaned = cleaned.substring(3);
    }
    
    // إضافة 0 في البداية إذا لم تكن موجودة
    if (!cleaned.startsWith('0')) {
      cleaned = '0$cleaned';
    }
    
    return cleaned;
  }

  // ═══════════════════════════════════════
  // نموذج طلب التصوير
  // ═══════════════════════════════════════
  Future<void> _showRequestForm() async {
    final auth = context.read<AuthProvider>();
    final user = auth.userModel;
    if (user == null) return;

    final nameCtrl = TextEditingController(text: user.nm);
    final descCtrl = TextEditingController();
    // الموقع الدقيق غير مطلوب؛ يتفق المستخدم والمصور عليه هاتفياً.
    // ✅ Fix for Bug #23: تطبيع رقم الهاتف إلى الصيغة المحلية (09xxxxxxxx)
    final normalizedPhone = _normalizePhoneToLocalFormat(user.ph);
    final phoneCtrl = TextEditingController(text: normalizedPhone);
    final notesCtrl = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.camera_alt, color: AppTheme.primaryGold, size: 24),
                  AppTheme.gapWidthSmall,
                  Text('طلب تصوير عقار',
                      style: TextStyle(
                          color: AppTheme.textWhite,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              AppTheme.gapHeightLarge,
              _field(nameCtrl, 'الاسم الثلاثي *', 'مثال: محمد أحمد الخطيب',
                  Icons.person),
              AppTheme.gapHeightMedium,
              _field(descCtrl, 'وصف العقار *', 'مثال: شقة 3 غرف طابق ثاني',
                  Icons.home_outlined),
              AppTheme.gapHeightMedium,
              _field(phoneCtrl, 'هاتف التواصل *', 'رقمك للتواصل وتأكيد الموعد',
                  Icons.phone,
                  keyboard: TextInputType.phone),
              AppTheme.gapHeightMedium,
              _field(notesCtrl, 'ملاحظات إضافية (اختياري)',
                  'مثال: أفضل وقت بعد الظهر...', Icons.note_alt_outlined,
                  maxLines: 2),
              // 💰 تذكير بالأجر قبل التأكيد — لا مفاجآت عند وصول المصوّر
              if (_photoFee > 0) ...[
                AppTheme.gapHeightMedium,
                Row(
                  children: [
                    const Icon(Icons.payments_outlined,
                        color: AppTheme.primaryGold, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'أجر التصوير $_photoFeeTxt ل.س، يُدفع للمصوّر عند وصوله.',
                        style: const TextStyle(
                            color: AppTheme.primaryGold,
                            fontSize: AppTheme.fontSizeSmall,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('إلغاء',
                          style: TextStyle(color: AppTheme.textGrey)),
                    ),
                  ),
                  AppTheme.gapWidthSmall,
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        if (nameCtrl.text.trim().isEmpty ||
                            descCtrl.text.trim().isEmpty ||
                            phoneCtrl.text.trim().isEmpty) {
                          // 🐛 إصلاح 2026-07-30: كان يعود صامتاً بلا أي تنبيه
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('يرجى تعبئة كل الحقول المطلوبة *'),
                              backgroundColor: AppTheme.errorRed,
                              duration: Duration(seconds: 2),
                            ),
                          );
                          return;
                        }
                        Navigator.pop(ctx, true);
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryGold),
                      child: const Text('إرسال الطلب',
                          style: TextStyle(
                              color: AppTheme.deepBlack,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) {
      nameCtrl.dispose();
      descCtrl.dispose();
      phoneCtrl.dispose();
      notesCtrl.dispose();
      return;
    }
    final fullName = nameCtrl.text.trim();
    final propertyDesc = descCtrl.text.trim();
    final contactPhone = phoneCtrl.text.trim();
    final requestNotes = notesCtrl.text.trim();
    nameCtrl.dispose();
    descCtrl.dispose();
    phoneCtrl.dispose();
    notesCtrl.dispose();

    try {
      final response = await SupabaseService().invokeFunction(
        'admin-photography',
        body: {
          'action': 'request_photography',
          'user_uid': user.uid,
          'full_name': fullName,
          'property_desc': propertyDesc,
          'contact_phone': contactPhone,
          'notes': requestNotes,
        },
      );
      final data =
          response.data is Map ? Map<String, dynamic>.from(response.data) : null;
      if (!mounted) return;
      if (data != null && data['success'] == true) {
        _snack('✅ تم إرسال طلب التصوير بنجاح', ok: true);
        _loadMyRequests();
      } else {
        final err = data?['error'] ?? 'خطأ غير معروف';
        if (err == 'ACTIVE_PHOTOGRAPHY_REQUEST_EXISTS') {
          _snack('لديك طلب تصوير نشط بالفعل — سيتم التواصل معك قريباً');
        } else {
          _snack(ErrorUtils.arabicMessage(err));
        }
      }
    } catch (e) {
      _snack('فشل إرسال طلب التصوير — تحقق من الاتصال وحاول مجدداً');
    }
  }

  Widget _field(TextEditingController ctrl, String label, String hint,
      IconData icon,
      {TextInputType? keyboard, int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      maxLines: maxLines,
      style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeMedium),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: AppTheme.fontSizeSmall),
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon, color: AppTheme.primaryGold, size: 20),
      ),
    );
  }

  // ═══════════════════════════════════════
  // الواجهة
  // ═══════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('خدمة التصوير العقاري'),
        backgroundColor: AppTheme.scaffoldBackground,
        foregroundColor: AppTheme.primaryGold,
        elevation: 0,
      ),
      body: RefreshIndicator(
        color: AppTheme.primaryGold,
        onRefresh: _loadMyRequests,
        child: ListView(
          padding: AppTheme.paddingAllLarge,
          children: [
            // ─── بطاقة شرح الخدمة ───
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryGold.withOpacity(0.18),
                    AppTheme.primaryGold.withOpacity(0.05),
                  ],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: AppTheme.radiusLarge,
                border:
                    Border.all(color: AppTheme.primaryGold.withOpacity(0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.photo_camera_front_rounded,
                          color: AppTheme.primaryGold, size: 28),
                      AppTheme.gapWidthSmall,
                      Expanded(
                        child: Text(
                          'صوّر عقارك باحتراف مع مصور المكتب',
                          style: TextStyle(
                            color: AppTheme.primaryGold,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  AppTheme.gapHeightMedium,
                  _explainRow(Icons.location_on_outlined,
                      'مصوّر محترف يزور عقارك في الموعد المتفق عليه'),
                  AppTheme.gapHeightSmall,
                  _explainRow(Icons.photo_library_outlined,
                      'التقاط صور وفيديو احترافية للعقار'),
                  AppTheme.gapHeightSmall,
                  _explainRow(Icons.trending_up_rounded,
                      'وسائط عالية الجودة تُنشر في العرض الخاص بك وتزيد فرص البيع أو الإيجار'),
                  // 💰 أجر الخدمة — يُقرأ من إعدادات الإدارة (photoPrice)؛ 0 = مجاني فيُخفى
                  if (_photoFee > 0) ...[
                    AppTheme.gapHeightMedium,
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGold.withOpacity(0.12),
                        borderRadius: AppTheme.radiusMedium,
                        border: Border.all(
                            color: AppTheme.primaryGold.withOpacity(0.45)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.payments_outlined,
                              color: AppTheme.primaryGold, size: 20),
                          AppTheme.gapWidthSmall,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'الخدمة مأجورة — $_photoFeeTxt ل.س',
                                  style: const TextStyle(
                                    color: AppTheme.primaryGold,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                AppTheme.gapHeightXXS,
                                const Text(
                                  'تُدفع للمصوّر عند وصوله لموقع العقار.',
                                  style: TextStyle(
                                      color: AppTheme.textGrey, fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            AppTheme.gapHeightLarge,

            // ─── زر طلب جديد ───
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () async {
                  // 📸 فتح شاشة إضافة العرض بوضع التصوير (خريطة إلزامية + بيانات كاملة)
                  final result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => const AddOfferScreen(isPhotographyRequest: true),
                    ),
                  );
                  if (result == true) _loadMyRequests();
                },
                icon: const Icon(Icons.add_a_photo_outlined,
                    color: AppTheme.deepBlack),
                label: Text(
                  _hasActiveRequest
                      ? 'طلب تصوير جديد (لديك طلب نشط)'
                      : 'طلب تصوير جديد',
                  style: const TextStyle(
                      color: AppTheme.deepBlack,
                      fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGold,
                  shape: RoundedRectangleBorder(
                      borderRadius: AppTheme.radiusMedium),
                ),
              ),
            ),
            AppTheme.gapHeightXXL,

            // ─── طلبات التصوير الخاصة بي ───
            const Row(
              children: [
                Icon(Icons.history, color: AppTheme.primaryGold, size: 18),
                AppTheme.gapWidthSmall,
                Text('طلبات التصوير الخاصة بي',
                    style: TextStyle(
                        color: AppTheme.primaryGold,
                        fontSize: AppTheme.fontSizeMedium,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            AppTheme.gapHeightMedium,
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Center(
                  child: CircularProgressIndicator(
                      color: AppTheme.primaryGold),
                ),
              )
            else if (_error != null)
              Container(
                padding: AppTheme.paddingAllXL,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBlack,
                  borderRadius: AppTheme.radiusMedium,
                ),
                child: Column(
                  children: [
                    Text(_error!,
                        style: const TextStyle(color: AppTheme.textGrey),
                        textAlign: TextAlign.center),
                    AppTheme.gapHeightSmall,
                    TextButton(
                      onPressed: _loadMyRequests,
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              )
            else if (_myRequests.isEmpty)
              Container(
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBlack,
                  borderRadius: AppTheme.radiusMedium,
                ),
                child: Column(
                  children: [
                    Icon(Icons.no_photography_outlined,
                        size: 44,
                        color: AppTheme.textGrey.withOpacity(0.4)),
                    AppTheme.gapHeightSmall,
                    const Text('ما عندك طلبات تصوير بعد',
                        style: TextStyle(color: AppTheme.textGrey)),
                    AppTheme.gapHeightXS,
                    const Text('اضغط "طلب تصوير جديد" لطلب أول جلسة تصوير',
                        style: TextStyle(
                            color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
                  ],
                ),
              )
            else
              ..._myRequests.map(_requestCard),

            const SizedBox(height: 30),
          ],
        ),
      ),
      bottomNavigationBar: const CustomBottomNavBar(currentIndex: 4),
    );
  }

  Future<void> _cancelRequest(PhotographyTaskModel t) async {
    // شاشة إدخال سبب الإلغاء الإلزامي
    final reasonCtrl = TextEditingController();
    String? validationError;

    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surfaceBlack,
          shape:
              RoundedRectangleBorder(borderRadius: AppTheme.radiusLarge),
          title: const Row(
            children: [
              Icon(Icons.cancel_outlined, color: AppTheme.errorRed, size: 22),
              AppTheme.gapWidthSmall,
              Text('إلغاء طلب التصوير',
                  style: TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSubtitle)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'إلغاء الطلب نهائي ولن تتمكن من استعادته.',
                style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody),
              ),
              AppTheme.gapHeightLarge,
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                autofocus: true,
                style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeMedium),
                decoration: InputDecoration(
                  labelText: 'سبب الإلغاء *',
                  labelStyle: const TextStyle(color: AppTheme.textGrey),
                  hintText: 'مثال: غيرت رأيي، لا أحتاج الخدمة...',
                  hintStyle: const TextStyle(color: AppTheme.textGrey),
                  errorText: validationError,
                  filled: true,
                  fillColor: AppTheme.scaffoldBackground,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.edit_note,
                      color: AppTheme.primaryGold),
                ),
                onChanged: (_) {
                  if (validationError != null) {
                    setDialogState(() => validationError = null);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('تراجع',
                  style: TextStyle(color: AppTheme.textGrey)),
            ),
            ElevatedButton(
              onPressed: () {
                final txt = reasonCtrl.text.trim();
                if (txt.isEmpty) {
                  setDialogState(
                      () => validationError = 'سبب الإلغاء مطلوب');
                  return;
                }
                Navigator.pop(ctx, txt);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
              child: const Text('تأكيد الإلغاء',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;

    final uid = context.read<AuthProvider>().userModel?.uid ?? '';
    try {
      final response = await SupabaseService().invokeFunction(
        'admin-photography',
        body: {
          'action': 'cancel_photo_request',
          'user_uid': uid,
          'task_id': t.id,
          'cancel_reason': reason,
        },
      );
      final data =
          response.data is Map ? Map<String, dynamic>.from(response.data) : null;
      if (!mounted) return;
      if (data != null && data['success'] == true) {
        _snack('✅ تم إلغاء طلب التصوير', ok: true);
        _loadMyRequests();
      } else {
        _snack('تعذر الإلغاء — الطلب لم يعد بانتظار');
      }
    } catch (e) {
      _snack('فشل الإلغاء — تحقق من الاتصال وحاول مجدداً');
    }
  }

  Widget _explainRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.primaryGold.withOpacity(0.9), size: 18),
        AppTheme.gapWidthSmall,
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
                color: AppTheme.textWhite, fontSize: 12.5, height: 1.5),
          ),
        ),
      ],
    );
  }

  Widget _requestCard(PhotographyTaskModel t) {
    final (label, color) = _requestStatusInfo(t);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.camera_alt_outlined, color: color, size: 18),
              AppTheme.gapWidthSmall,
              Expanded(
                child: Text(
                  t.ttl.isNotEmpty ? t.ttl : 'طلب تصوير عقار',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppTheme.textWhite,
                      fontWeight: FontWeight.bold,
                      fontSize: AppTheme.fontSizeBody),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: AppTheme.radiusSmall,
                  border: Border.all(color: color.withOpacity(0.5)),
                ),
                child: Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: AppTheme.fontSizeCaption,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          AppTheme.gapHeightSmall,
          Row(
            children: [
              const Icon(Icons.schedule,
                  size: 13, color: AppTheme.textGrey),
              AppTheme.gapWidthXS,
              Text(
                'أُرسل: ${_fmtDate(t.tsCrt)}',
                style:
                    const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption),
              ),
            ],
          ),
          if (t.photographerName.isNotEmpty) ...[
            AppTheme.gapHeightXS,
            Row(
              children: [
                const Icon(Icons.person_outline,
                    size: 13, color: AppTheme.infoBlue),
                AppTheme.gapWidthXS,
                Expanded(
                  child: Text(
                    'المصوّر: ${t.photographerName}${t.photographerPhone.isNotEmpty ? ' — ${AppUtils.displayPhone(t.photographerPhone)}' : ''}',
                    style: const TextStyle(
                        color: AppTheme.infoBlue,
                        fontSize: AppTheme.fontSizeCaption,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
          if (t.tsScheduled != null) ...[
            AppTheme.gapHeightXS,
            Row(
              children: [
                const Icon(Icons.event_available,
                    size: 13, color: AppTheme.successGreen),
                AppTheme.gapWidthXS,
                Expanded(
                  child: Text(
                    'موعد التصوير: ${_fmtDateTime(t.tsScheduled!)}',
                    style: const TextStyle(
                        color: AppTheme.successGreen,
                        fontSize: AppTheme.fontSizeCaption,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
          // الوسائط المعتمدة تظهر للمستخدم بعد اكتمال الجلسة
          if (t.sts == 3 && t.media.isNotEmpty) ...[
            AppTheme.gapHeightSmall,
            const Text('وسائط جلسة التصوير:',
                style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
            const SizedBox(height: 6),
            SizedBox(
              height: 72,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: t.media.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ClipRRect(
                    borderRadius: AppTheme.radiusSmall,
                    child: Image.network(
                      t.media[i],
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 72,
                        height: 72,
                        color: AppTheme.deepBlack,
                        child: const Icon(Icons.broken_image,
                            color: AppTheme.textGrey, size: 20),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          // 🐛 إصلاح 2026-07-30: إظهار سبب الرفض/الإلغاء (office_note)
          // كان المستخدم يرى «مرفوضة» بلا أي تفسير — الآن يرى سبب المكتب.
          if ((t.sts == 4 || t.sts == 5) && t.officeNote.isNotEmpty) ...[
            AppTheme.gapHeightSmall,
            Container(
              width: double.infinity,
              padding: AppTheme.paddingAllSmall,
              decoration: BoxDecoration(
                color: (t.sts == 4 ? AppTheme.errorRed : AppTheme.textGrey).withOpacity(0.1),
                borderRadius: AppTheme.radiusSmall,
                border: Border.all(
                    color: (t.sts == 4 ? AppTheme.errorRed : AppTheme.textGrey)
                        .withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    t.sts == 4 ? Icons.info_outline : Icons.cancel_outlined,
                    color: t.sts == 4 ? AppTheme.errorRed : AppTheme.textGrey,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      t.officeNote,
                      style: TextStyle(
                        color: t.sts == 4 ? AppTheme.errorRed : AppTheme.textGrey,
                        fontSize: AppTheme.fontSizeCaption,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          AppTheme.gapHeightSmall,
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showRequestDetails(t),
              icon: const Icon(Icons.receipt_long_outlined,
                  color: AppTheme.primaryGold, size: 17),
              label: const Text('عرض تفاصيل طلب التصوير',
                  style: TextStyle(color: AppTheme.primaryGold)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppTheme.primaryGold.withOpacity(0.45)),
              ),
            ),
          ),
          // زر الإلغاء — فقط للطلبات المعلّقة (لم يبدأ المصور بعد)
          if (t.sts == 0) ...[
            AppTheme.gapHeightSmall,
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _cancelRequest(t),
                icon: const Icon(Icons.cancel_outlined,
                    color: AppTheme.errorRed, size: 16),
                label: const Text('إلغاء الطلب',
                    style: TextStyle(color: AppTheme.errorRed, fontSize: AppTheme.fontSizeSmall)),
              ),
            ),
          ],
          // 💡 تحسين 2026-07-30: توضيح سبب عدم إمكانية الإلغاء
          // عندما يبدأ المصوّر (sts=1) أو تُرسل الصور (sts=2) يختفي زر الإلغاء
          // بلا تفسير. الآن رسالة قصيرة تُعلم المستخدم أن الإلغاء لم يعد متاحاً.
          if (t.sts == 1 || t.sts == 2) ...[
            AppTheme.gapHeightSmall,
            Row(
              children: [
                const Icon(Icons.info_outline,
                    color: Colors.amber, size: 13),
                AppTheme.gapWidthXS,
                Expanded(
                  child: Text(
                    'لا يمكن إلغاء الطلب بعد بدء التصوير — يرجى التواصل مع المكتب مباشرة إذا لزم الأمر',
                    style: const TextStyle(
                        color: Colors.amber, fontSize: 10.5),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showRequestDetails(PhotographyTaskModel task) async {
    final d = task.offerDetails;
    String text(String key) => d[key]?.toString().trim() ?? '';
    final loc = d['loc'] is Map
        ? Map<String, dynamic>.from(d['loc'] as Map)
        : <String, dynamic>{};
    final specs = d['specs'] is Map
        ? Map<String, dynamic>.from(d['specs'] as Map)
        : <String, dynamic>{};
    final type = int.tryParse(text('typ')) ?? 0;
    final transaction = int.tryParse(text('trx')) ?? 0;
    final price = num.tryParse(text('prc')) ?? 0;
    final currency = int.tryParse(text('cur')) ?? 1;
    final city = loc['city']?.toString().trim() ?? '';
    final area = loc['d']?.toString().trim() ?? '';
    final location = [city, area].where((v) => v.isNotEmpty).join(' — ');

    const specLabels = <String, String>{
      'area': 'المساحة',
      'floor': 'الطابق',
      'finishing': 'الإكساء',
      'direction': 'الاتجاه',
      'legal_notes': 'ملاحظات قانونية',
      'custom_sub': 'التصنيف',
      'plate': 'رقم اللوحة',
      'brand': 'الماركة',
      'model': 'الطراز',
      'year': 'سنة الصنع',
      'color': 'اللون',
      'fuel': 'الوقود',
      'transmission': 'ناقل الحركة',
      'plate_type': 'نوع اللوحة',
    };

    final detailRows = <Widget>[
      _requestDetailRow('حالة الطلب', _requestStatusInfo(task).$1),
      _requestDetailRow('نوع العرض', AppUtils.offerTypeText(type)),
      _requestDetailRow('نوع العملية', AppUtils.transactionText(transaction)),
      if (price > 0)
        _requestDetailRow('السعر', AppUtils.formatPrice(price, currency: currency)),
      if (location.isNotEmpty) _requestDetailRow('الموقع', location),
      if (text('descript').isNotEmpty)
        _requestDetailRow('الوصف', text('descript')),
      if (text('contact_ph').isNotEmpty)
        _requestDetailRow(
            'رقم التنسيق', AppUtils.displayPhone(text('contact_ph'))),
      ...specs.entries.where((e) => e.value.toString().trim().isNotEmpty).map(
            (e) => _requestDetailRow(
              specLabels[e.key] ?? 'تفصيل إضافي',
              e.value.toString(),
            ),
          ),
      if (task.photographerName.isNotEmpty)
        _requestDetailRow('المصوّر', task.photographerName),
      if (task.photographerPhone.isNotEmpty)
        _requestDetailRow(
            'هاتف المصوّر', AppUtils.displayPhone(task.photographerPhone)),
      if (task.tsScheduled != null)
        _requestDetailRow('موعد التصوير', _fmtDateTime(task.tsScheduled!)),
      _requestDetailRow('تاريخ إرسال الطلب', _fmtDateTime(task.tsCrt)),
    ];

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: Text(
          text('ttl').isNotEmpty ? text('ttl') : task.ttl,
          style: const TextStyle(
              color: AppTheme.primaryGold, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: detailRows,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _requestDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(label,
                style: const TextStyle(
                    color: AppTheme.textGrey,
                    fontSize: AppTheme.fontSizeCaption)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: AppTheme.textWhite,
                    fontSize: AppTheme.fontSizeSmall,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  (String, Color) _requestStatusInfo(PhotographyTaskModel task) {
    if (task.sts == 0 && task.photographerId.isNotEmpty) {
      return task.tsScheduled != null
          ? ('تم قبول الطلب وتحديد الموعد', AppTheme.successGreen)
          : ('تم قبول الطلب وجارٍ تنسيق الموعد', AppTheme.infoBlue);
    }
    switch (task.sts) {
      case 0:
        return ('قيد مراجعة الإدارة', AppTheme.warningOrange);
      case 1:
        return ('قيد التنفيذ', AppTheme.infoBlue);
      case 2:
        return ('مرسلة للمكتب', Colors.purple);
      case 3:
        return ('مكتملة', AppTheme.successGreen);
      case 4:
        return ('مرفوضة', AppTheme.errorRed);
      case 5:
        return ('ملغاة', AppTheme.textGrey);
      default:
        return ('غير معروف', AppTheme.textGrey);
    }
  }

  String _fmtDate(DateTime dt) =>
      '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';

  /// 📅 التاريخ **مع الساعة** بتوقيت الجهاز (دمشق) — موعد التصوير بلا ساعة لا معنى له.
  /// مرجع الإصلاح: بلاغ المالك 2026-07-28 «مو محدد الساعة».
  String _fmtDateTime(DateTime dt) {
    final l = dt.toLocal();
    final h = l.hour.toString().padLeft(2, '0');
    final m = l.minute.toString().padLeft(2, '0');
    return '${_fmtDate(l)} — الساعة $h:$m';
  }
}

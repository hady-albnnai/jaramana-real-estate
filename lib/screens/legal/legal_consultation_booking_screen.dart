import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_utils.dart';
import '../../core/network/supabase_service.dart';
import '../../core/constants/db_constants.dart';
import '../../core/validation/input_validators.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../providers/legal_provider.dart';
import '../../providers/payment_provider.dart';
import '../../models/payment_model.dart';
import '../../services/storage_service.dart';

/// شاشة الاستشارة القانونية — تدفق بسيط ونظيف
///
/// الشاشة الرئيسية تعرض:
/// 1. إذا في دفعة معلقة → "بانتظار التأكيد"
/// 2. إذا في دفعة مقبولة بدون استشارة → "إرسال الطلب"
/// 3. إذا في استشارة نشطة → "فتح المحادثة"
/// 4. أزرار "استشارة جديدة" / "جلسة حضورية"
class LegalConsultationBookingScreen extends StatefulWidget {
  const LegalConsultationBookingScreen({super.key});
  @override
  State<LegalConsultationBookingScreen> createState() => _State();
}

class _State extends State<LegalConsultationBookingScreen> {
  final _storage = StorageService();
  bool _loading = true;

  // البيانات
  Map<String, dynamic>? _pendingPayment;    // دفعة قيد المراجعة
  Map<String, dynamic>? _approvedPayment;   // دفعة مقبولة بدون استشارة
  Map<String, dynamic>? _activeConsultation; // استشارة نشطة (الأحدث)
  List<Map<String, dynamic>> _previousChats = [];

  // الـ Wizard
  int _screen = 0; // 0=رئيسية, 1=ارشادات, 2=اختيار نوع, 3=فحص قديمة, 4=موضوع, 5=دفع, 6=نجاح
  int _serviceType = 0;
  bool _isContinuing = false; // متابعة محادثة قديمة
  String? _continueChatId;
  final _subjectCtrl = TextEditingController();
  final List<XFile> _attachments = [];
  String _channel = '';
  final _refCtrl = TextEditingController();
  final _senderPhoneCtrl = TextEditingController();
  XFile? _proofImage;
  bool _submitting = false;

  static const _topicChips = ['عقد إيجار', 'نزاع عقاري', 'إرث', 'مخالفة مرورية', 'سند ملكية', 'عقد عمل', 'أخرى'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  @override
  void dispose() {
    _subjectCtrl.dispose(); _refCtrl.dispose(); _senderPhoneCtrl.dispose();
    super.dispose();
  }

  bool get _isLateNight => DateTime.now().hour >= 23 || DateTime.now().hour < 9;
  bool get _needsSenderPhone => _channel == 'balance' || _channel == 'syriatel_cash';

  String _normPhone(String p) {
    final d = p.replaceAll(RegExp(r'[^\d]'), '');
    if (d.startsWith('963') && d.length == 12) return '0${d.substring(3)}';
    if (d.startsWith('09') && d.length == 10) return d;
    if (d.startsWith('9') && d.length == 9) return '0$d';
    return d;
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final uid = context.read<AuthProvider>().userModel?.uid ?? '';
    if (uid.isEmpty) { setState(() => _loading = false); return; }
    try {
      // الدفعات
      final pays = await SupabaseService().client.from(DbTables.payments)
          .select('id, sts, amt, pkg, channel, ref, ts_crt')
          .eq('uid', uid).eq('tp', 2).order('ts_crt', ascending: false);
      
      Map<String, dynamic>? pending, approved;
      for (final p in pays as List) {
        final m = Map<String, dynamic>.from(p as Map);
        if (m['sts'] == 0 && pending == null) pending = m;
        else if (m['sts'] == 1 && approved == null) {
          // تأكد ما في استشارة مربوطة
          final cRes = await SupabaseService().client.from('legal_consultations')
              .select('id').eq('payment_id', m['id']).limit(1);
          if ((cRes as List).isEmpty) approved = m;
        }
      }

      // الاستشارات النشطة
      final consultRes = await SupabaseService().invokeFunction('legal-actions',
          body: {'action': 'list_my_consultations', 'user_uid': uid});
      final cData = consultRes.data as Map<String, dynamic>?;
      final all = cData?['success'] == true
          ? List<Map<String, dynamic>>.from(cData['consultations'] as List? ?? []) : <Map<String, dynamic>>[];
      
      Map<String, dynamic>? active;
      final previous = <Map<String, dynamic>>[];
      for (final c in all) {
        if ([0, 1, 4].contains(c['status']) && active == null) active = c;
        if (c['chat_started_at'] != null) {
          final dt = DateTime.tryParse(c['chat_started_at'].toString());
          if (dt != null && DateTime.now().difference(dt).inDays < 7) previous.add(c);
        }
      }

      if (mounted) setState(() {
        _pendingPayment = pending;
        _approvedPayment = approved;
        _activeConsultation = active;
        _previousChats = previous;
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
    context.read<LegalProvider>().fetchActiveLawyers();
  }

  void _goTo(int s) => setState(() => _screen = s);
  void _resetWizard() {
    _screen = 0; _serviceType = 0; _isContinuing = false; _continueChatId = null;
    _subjectCtrl.clear(); _attachments.clear(); _channel = ''; _proofImage = null; _refCtrl.clear(); _senderPhoneCtrl.clear();
  }

  // إرفاق
  void _pickAttachments() async {
    final rem = 5 - _attachments.length;
    if (rem <= 0) { _snack('الحد الأقصى 5 صور'); return; }
    final files = await ImagePicker().pickMultiImage(imageQuality: 60, maxWidth: 1280);
    if (files.isNotEmpty) setState(() => _attachments.addAll(files.take(rem)));
  }
  void _pickProof() async { final f = await _storage.pickImage(fromCamera: false); if (f != null) setState(() => _proofImage = f); }

  Future<List<String>> _uploadAttachments() async {
    if (_attachments.isEmpty) return [];
    final urls = <String>[];
    final uid = context.read<AuthProvider>().userModel?.uid ?? '';
    for (final f in _attachments) {
      try {
        final comp = await _storage.compressImage(File(f.path));
        final bytes = await (comp ?? File(f.path)).readAsBytes();
        final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.${f.path.split('.').last}';
        await SupabaseService().storage.from('consultation_files').uploadBinary(path, bytes, fileOptions: FileOptions(cacheControl: '3600', upsert: false));
        urls.add(path);
      } catch (_) {}
    }
    return urls;
  }

  Future<String?> _uploadProof(String uid) async {
    if (_proofImage == null) return null;
    try {
      final path = '$uid/proof_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = kIsWeb ? await _proofImage!.readAsBytes()
          : await (await _storage.compressImage(File(_proofImage!.path)) ?? File(_proofImage!.path)).readAsBytes();
      await SupabaseService().storage.from(StorageService.paymentProofsBucket).uploadBinary(path, bytes, fileOptions: FileOptions(cacheControl: '3600', upsert: false));
      return path;
    } catch (_) { return null; }
  }

  // الدفع
  Future<void> _pay() async {
    if (_subjectCtrl.text.trim().length < 10 && !_isContinuing) { _snack('اكتب موضوع الاستشارة (10 أحرف على الأقل)'); return; }
    if (_channel.isEmpty) { _snack('اختر قناة الدفع'); return; }
    if (_proofImage == null) { _snack('ارفع إثبات الدفع'); return; }
    final ref = InputValidators.normalizeDigits(_refCtrl.text.trim());
    if (ref.isEmpty) { _snack('أدخل رقم العملية'); return; }

    setState(() => _submitting = true);
    final user = context.read<AuthProvider>().userModel!;
    String sender = '';
    if (_needsSenderPhone) { sender = _normPhone(_senderPhoneCtrl.text.trim()); }

    final proof = await _uploadProof(user.uid);
    if (proof == null) { _snack('فشل رفع الإثبات'); setState(() => _submitting = false); return; }

    final price = _serviceType == 0 ? 500.0 : 2000.0;
    final payment = PaymentModel(
      id: '', uid: user.uid, tp: 2, pkg: _serviceType, amt: price, cur: 1, mtd: 0,
      channel: _channel, proof: proof, ref: ref, sts: 0, tsCrt: DateTime.now(),
      meta: {'service': 'legal_consultation', if (sender.isNotEmpty) 'sender_phone': sender, if (_isContinuing && _continueChatId != null) 'continue_chat': _continueChatId},
    );
    try {
      final ok = await context.read<PaymentProvider>().makePayment(payment);
      if (ok) { _goTo(6); _snack('✅ تم إرسال الدفعة'); } else { _snack('فشل تسجيل الدفعة'); }
    } catch (e) { _snack('خطأ: $e'); }
    if (mounted) setState(() => _submitting = false);
  }

  // إرسال الاستشارة
  Future<void> _submitConsultation() async {
    setState(() => _submitting = true);
    final atts = await _uploadAttachments();
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'book_consultation', 'user_uid': context.read<AuthProvider>().userModel?.uid ?? '',
        'service_type': _serviceType, 'subject': _subjectCtrl.text.trim(),
        'price': _serviceType == 0 ? 500 : 2000, 'attachments': atts,
      });
      if (res.data is Map && (res.data as Map)['success'] == true) {
        _snack('✅ تم إرسال الطلب — المحامي يدرس مشكلتك');
        _resetWizard(); _loadAll();
      } else { _snack((res.data as Map?)?['error']?.toString() ?? 'فشل'); }
    } catch (e) { _snack('خطأ: $e'); }
    if (mounted) setState(() => _submitting = false);
  }

  void _openChat(String id) => context.push('/legal/chat/$id');

  // ═══════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    switch (_screen) {
      case 0: return _buildHome();
      case 1: return _buildExplanation();
      case 2: return _buildChooseType();
      case 3: return _buildPreviousChats();
      case 4: return _buildSubjectForm();
      case 5: return _buildPaymentForm();
      case 6: return _buildSuccess();
      default: return _buildHome();
    }
  }

  // ── الشاشة الرئيسية ──
  Widget _buildHome() {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: const Text('الاستشارة القانونية', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold), onPressed: () => Navigator.pop(context)),
        actions: [IconButton(icon: const Icon(Icons.refresh, color: AppTheme.primaryGold), onPressed: _loadAll)]),
      body: _loading ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGold))
          : RefreshIndicator(color: AppTheme.primaryGold, onRefresh: _loadAll, child: _buildHomeContent()),
    );
  }

  Widget _buildHomeContent() {
    // الحالة 1: دفعة معلقة → انتظر فقط
    if (_pendingPayment != null) {
      return ListView(padding: AppTheme.paddingAllLarge, children: [
        AppTheme.gapHeightXL,
        const Center(child: Icon(Icons.hourglass_top, color: AppTheme.warningOrange, size: 64)),
        AppTheme.gapHeightLarge,
        const Center(child: Text('دفعتك قيد المراجعة', style: TextStyle(color: AppTheme.textWhite, fontSize: 18, fontWeight: FontWeight.bold))),
        AppTheme.gapHeightSmall,
        Center(child: Text('${(_pendingPayment!['amt'] as num).toStringAsFixed(0)} ل.س — ${(_pendingPayment!['pkg'] == 0) ? 'استشارة هاتفية' : 'جلسة حضورية'}', style: const TextStyle(color: AppTheme.textGrey, fontSize: 14))),
        AppTheme.gapHeightMedium,
        const Center(child: Text('ستصلك إشعار عند تأكيد الإدارة', style: TextStyle(color: AppTheme.textGrey, fontSize: 13))),
        AppTheme.gapHeightSmall,
        const Center(child: Text('عادة خلال ساعة', style: TextStyle(color: AppTheme.textGrey, fontSize: 12))),
      ]);
    }

    // الحالة 2: دفعة مقبولة بدون استشارة → أرسل الطلب
    if (_approvedPayment != null) {
      final pkg = (_approvedPayment!['pkg'] ?? 0) as int;
      return ListView(padding: AppTheme.paddingAllLarge, children: [
        AppTheme.gapHeightXL,
        const Center(child: Icon(Icons.check_circle, color: AppTheme.successGreen, size: 64)),
        AppTheme.gapHeightLarge,
        const Center(child: Text('تم تأكيد دفعتك ✅', style: TextStyle(color: AppTheme.successGreen, fontSize: 18, fontWeight: FontWeight.bold))),
        AppTheme.gapHeightSmall,
        Center(child: Text('${(_approvedPayment!['amt'] as num).toStringAsFixed(0)} ل.س — ${pkg == 0 ? 'استشارة هاتفية' : 'جلسة حضورية'}', style: const TextStyle(color: AppTheme.textGrey, fontSize: 14))),
        AppTheme.gapHeightXL,
        SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
          onPressed: () { _serviceType = pkg; _goTo(4); },
          icon: const Icon(Icons.send, color: Colors.black),
          label: const Text('إرسال الطلب للمحامي', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
        )),
      ]);
    }

    // الحالة 3: استشارة نشطة
    if (_activeConsultation != null) {
      final c = _activeConsultation!;
      final status = c['status'] ?? 0;
      final chatStarted = c['chat_started_at'] != null;
      final id = c['id'].toString();
      final alias = (c['lawyer_alias'] ?? '').toString();
      final subject = (c['subject'] ?? '').toString();
      final sType = (c['service_type'] ?? 0) as int;

      return ListView(padding: AppTheme.paddingAllLarge, children: [
        AppTheme.gapHeightLarge,
        Container(padding: AppTheme.paddingAllLarge,
          decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusLarge, border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3))),
          child: Column(children: [
            Row(children: [
              Icon(sType == 0 ? Icons.phone_in_talk : Icons.business, color: AppTheme.primaryGold, size: 24),
              AppTheme.gapWidthSmall,
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(sType == 0 ? 'استشارة هاتفية' : 'جلسة حضورية', style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 16)),
                Text(subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textGrey, fontSize: 12)),
              ])),
            ]),
            if (alias.isNotEmpty) ...[AppTheme.gapHeightXS, Text('⚖️ $alias', style: const TextStyle(color: AppTheme.primaryGold, fontSize: 13))],
            AppTheme.gapHeightLarge,
            if (status == 0) ...[
              const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.hourglass_empty, color: AppTheme.warningOrange, size: 20), SizedBox(width: 8), Text('بانتظار قبول المحامي', style: TextStyle(color: AppTheme.warningOrange, fontWeight: FontWeight.bold))]),
            ] else if (status == 4 || !chatStarted) ...[
              const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.menu_book, color: AppTheme.infoBlue, size: 20), SizedBox(width: 8), Text('المحامي يدرس مشكلتك', style: TextStyle(color: AppTheme.infoBlue, fontWeight: FontWeight.bold))]),
            ] else if (chatStarted) ...[
              SizedBox(width: double.infinity, height: 48, child: ElevatedButton.icon(
                onPressed: () => _openChat(id),
                icon: const Icon(Icons.chat, color: Colors.black),
                label: const Text('فتح المحادثة', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successGreen),
              )),
            ],
          ])),
        AppTheme.gapHeightXL,
        const Divider(color: Colors.white12),
        AppTheme.gapHeightMedium,
        _buildNewButtons(),
      ]);
    }

    // الحالة 4: لا شي — أزرار جديدة
    return ListView(padding: AppTheme.paddingAllLarge, children: [
      AppTheme.gapHeightXXL,
      const Center(child: Icon(Icons.gavel, color: AppTheme.primaryGold, size: 56)),
      AppTheme.gapHeightLarge,
      const Center(child: Text('الاستشارة القانونية', style: TextStyle(color: AppTheme.textWhite, fontSize: 20, fontWeight: FontWeight.bold))),
      AppTheme.gapHeightSmall,
      const Center(child: Text('احصل على استشارة قانونية من محامي المكتب', style: TextStyle(color: AppTheme.textGrey, fontSize: 13))),
      AppTheme.gapHeightXXL,
      _buildNewButtons(),
    ]);
  }

  Widget _buildNewButtons() {
    return Row(children: [
      Expanded(child: GestureDetector(
        onTap: () { _serviceType = 0; _goTo(1); },
        child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppTheme.primaryGold.withOpacity(0.08), borderRadius: AppTheme.radiusLarge, border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3))),
          child: Column(children: [
            const Icon(Icons.phone_in_talk, color: AppTheme.primaryGold, size: 32),
            const SizedBox(height: 8),
            const Text('استشارة هاتفية', style: TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 2),
            const Text('500 ل.س', style: TextStyle(color: AppTheme.primaryGold, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: AppTheme.primaryGold, borderRadius: AppTheme.radiusXL),
              child: const Text('الأكثر طلباً', style: TextStyle(color: AppTheme.deepBlack, fontSize: 9, fontWeight: FontWeight.bold))),
          ])))),
      AppTheme.gapWidthMedium,
      Expanded(child: GestureDetector(
        onTap: () { _serviceType = 1; _goTo(1); },
        child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppTheme.primaryGold.withOpacity(0.08), borderRadius: AppTheme.radiusLarge, border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3))),
          child: Column(children: [
            const Icon(Icons.business, color: AppTheme.primaryGold, size: 32),
            const SizedBox(height: 8),
            const Text('جلسة حضورية', style: TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 2),
            const Text('2,000 ل.س', style: TextStyle(color: AppTheme.primaryGold, fontSize: 12, fontWeight: FontWeight.bold)),
          ])))),
    ]);
  }

  // ── الإرشادات ──
  Widget _buildExplanation() {
    return Scaffold(backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: Text(_serviceType == 0 ? '⚖️ استشارة هاتفية' : '🏢 جلسة حضورية', style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold), onPressed: () => _goTo(0))),
      body: SingleChildScrollView(padding: AppTheme.paddingAllLarge, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Center(child: Icon(Icons.gavel, color: AppTheme.primaryGold, size: 48)),
        AppTheme.gapHeightLarge,
        _infoCard(Icons.phone_in_talk, 'استشارة هاتفية', '500 ل.س', '15 دقيقة', ['محادثة مع محامي المكتب', 'للأسئلة القانونية البسيطة', 'تجديد بـ 500 ل.س كل 15 دقيقة', 'المحادثة تبقى 7 أيام']),
        AppTheme.gapHeightMedium,
        _infoCard(Icons.business, 'جلسة حضورية', '2,000 ل.س', 'ساعة', ['اجتماع في مكتب المحامي', 'للمشاكل المعقدة', 'حجز موعد مسبق']),
        AppTheme.gapHeightXL,
        Container(width: double.infinity, padding: AppTheme.paddingAllMedium,
          decoration: BoxDecoration(color: AppTheme.warningOrange.withOpacity(0.1), borderRadius: AppTheme.radiusSmall, border: Border.all(color: AppTheme.warningOrange.withOpacity(0.4))),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('⚠️ الخطوات:', style: TextStyle(color: AppTheme.warningOrange, fontWeight: FontWeight.bold, fontSize: 13)),
            SizedBox(height: 6),
            Text('1️⃣ اكتب موضوع الاستشارة وأرفق المستندات', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.8)),
            Text('2️⃣ ادفع المبلغ — الإدارة تؤكد (عادة خلال ساعة)', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.8)),
            Text('3️⃣ أرسل الطلب للمحامي — يدرس ويفتح المحادثة', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.8)),
          ])),
        AppTheme.gapHeightLarge,
        SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
          onPressed: () => _goTo(_serviceType == 0 ? 3 : 4), // هاتفية → فحص قديمة / حضورية → موضوع مباشرة
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          label: const Text('متابعة', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
        )),
      ])));
  }

  Widget _infoCard(IconData icon, String title, String price, String dur, List<String> pts) {
    return Container(padding: AppTheme.paddingAllMedium, decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusMedium, border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: AppTheme.primaryGold, size: 20), AppTheme.gapWidthSmall, Text(title, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 14)), const Spacer(),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppTheme.primaryGold, borderRadius: AppTheme.radiusXL), child: Text(price, style: const TextStyle(color: AppTheme.deepBlack, fontWeight: FontWeight.bold, fontSize: 11)))]),
        Text('⏱️ $dur', style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)),
        const SizedBox(height: 8),
        ...pts.map((p) => Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('• $p', style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)))),
      ]));
  }

  // ── اختيار النوع ──
  Widget _buildChooseType() {
    return Scaffold(backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: const Text('اختر النوع', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold), onPressed: () => _goTo(1))),
      body: Padding(padding: AppTheme.paddingAllLarge, child: Column(children: [AppTheme.gapHeightXL,
        _typeCard(Icons.phone_in_talk, 'استشارة هاتفية', '500 ل.س — 15 دقيقة', 0),
        AppTheme.gapHeightLarge,
        _typeCard(Icons.business, 'جلسة حضورية', '2,000 ل.س — ساعة', 1),
      ])));
  }

  Widget _typeCard(IconData icon, String title, String sub, int sType) {
    return GestureDetector(onTap: () { _serviceType = sType; _goTo(sType == 0 ? 3 : 4); },
      child: Container(width: double.infinity, padding: AppTheme.paddingAllLarge,
        decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusLarge, border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3))),
        child: Row(children: [
          CircleAvatar(radius: 28, backgroundColor: AppTheme.primaryGold.withOpacity(0.2), child: Icon(icon, color: AppTheme.primaryGold, size: 28)),
          AppTheme.gapWidthMedium,
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 16)),
            Text(sub, style: const TextStyle(color: AppTheme.primaryGold, fontSize: 12, fontWeight: FontWeight.bold)),
          ])),
          const Icon(Icons.arrow_forward_ios, color: AppTheme.primaryGold, size: 16),
        ])));
  }

  // ── فحص المحادثات السابقة (هاتفية فقط) ──
  Widget _buildPreviousChats() {
    final chats = _previousChats;
    return Scaffold(backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: const Text('استشارة هاتفية', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold), onPressed: () => _goTo(1))),
      body: SingleChildScrollView(padding: AppTheme.paddingAllLarge, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (chats.isNotEmpty) ...[
          Text(chats.length == 1 ? 'لديك محادثة سابقة' : 'لديك ${chats.length} محادثات سابقة', style: const TextStyle(color: AppTheme.primaryGold, fontSize: 16, fontWeight: FontWeight.bold)),
          AppTheme.gapHeightSmall,
          const Text('هل تريد متابعة إحداها؟ (نفس المحامي — تجديد 500 ل.س)', style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
          AppTheme.gapHeightMedium,
          ...chats.map((c) {
            final id = c['id'].toString();
            final sel = _continueChatId == id;
            final subject = (c['subject'] ?? '').toString();
            final alias = (c['lawyer_alias'] ?? 'محامي المكتب').toString();
            final dt = DateTime.tryParse(c['chat_started_at']?.toString() ?? '');
            final daysLeft = dt != null ? 7 - DateTime.now().difference(dt).inDays : 0;
            return GestureDetector(onTap: () => setState(() => _continueChatId = sel ? null : id),
              child: Container(margin: const EdgeInsets.only(bottom: 8), padding: AppTheme.paddingAllMedium,
                decoration: BoxDecoration(color: sel ? AppTheme.primaryGold.withOpacity(0.12) : AppTheme.surfaceBlack, borderRadius: AppTheme.radiusMedium, border: Border.all(color: sel ? AppTheme.primaryGold : Colors.white12)),
                child: Row(children: [
                  Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off, color: sel ? AppTheme.primaryGold : AppTheme.textGrey),
                  AppTheme.gapWidthSmall,
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 13)),
                    Text('⚖️ $alias  •  📅 $daysLeft أيام متبقية', style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)),
                  ])),
                ])));
          }),
          AppTheme.gapHeightLarge,
          if (_continueChatId != null) SizedBox(width: double.infinity, height: 48, child: ElevatedButton.icon(
            onPressed: () { _isContinuing = true; _goTo(5); }, // مباشر للدفع
            icon: const Icon(Icons.payment, color: Colors.black),
            label: const Text('متابعة — دفع 500 ل.س', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
          )),
          AppTheme.gapHeightMedium,
        ],
        SizedBox(width: double.infinity, height: 48, child: OutlinedButton.icon(
          onPressed: () { _isContinuing = false; _continueChatId = null; _goTo(4); },
          icon: const Icon(Icons.add, color: AppTheme.primaryGold),
          label: Text(chats.isNotEmpty ? 'لا — أريد استشارة جديدة' : 'بدء استشارة جديدة', style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.primaryGold)),
        )),
      ])));
  }

  // ── موضوع الاستشارة ──
  Widget _buildSubjectForm() {
    return Scaffold(backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: Text(_serviceType == 0 ? 'استشارة هاتفية' : 'جلسة حضورية', style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold), onPressed: () => _goTo(_serviceType == 0 ? 3 : 1))),
      body: SingleChildScrollView(padding: AppTheme.paddingAllLarge, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('موضوع الاستشارة:', style: TextStyle(color: AppTheme.primaryGold, fontSize: 15, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightSmall,
        Wrap(spacing: 6, runSpacing: 6, children: _topicChips.map((c) => GestureDetector(onTap: () {
          final cur = _subjectCtrl.text;
          setState(() => _subjectCtrl.text = cur.isEmpty ? c : '$cur — $c');
        }, child: Chip(label: Text(c, style: const TextStyle(fontSize: 11)), backgroundColor: AppTheme.primaryGold.withOpacity(0.1), side: BorderSide(color: AppTheme.primaryGold.withOpacity(0.3))))).toList()),
        AppTheme.gapHeightSmall,
        TextField(controller: _subjectCtrl, maxLines: 4, maxLength: 500, style: const TextStyle(color: AppTheme.textWhite),
          decoration: const InputDecoration(hintText: 'اشرح مشكلتك القانونية...', filled: true, fillColor: AppTheme.surfaceBlack, border: OutlineInputBorder())),
        AppTheme.gapHeightLarge,
        const Text('المستندات (اختياري — حتى 5 صور):', style: TextStyle(color: AppTheme.primaryGold, fontSize: 14, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightSmall,
        GestureDetector(onTap: _pickAttachments, child: Container(width: double.infinity, padding: AppTheme.paddingAllMedium, decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusMedium, border: Border.all(color: Colors.white12)),
          child: Row(children: [const Icon(Icons.add_photo_alternate_outlined, color: AppTheme.primaryGold), AppTheme.gapWidthSmall, Text('إضافة صور (${_attachments.length}/5)', style: const TextStyle(color: AppTheme.textGrey))]))),
        if (_attachments.isNotEmpty) ...[AppTheme.gapHeightSmall,
          Wrap(spacing: 8, runSpacing: 8, children: _attachments.asMap().entries.map((e) => Stack(children: [
            ClipRRect(borderRadius: AppTheme.radiusSmall, child: kIsWeb ? Image.network(e.value.path, width: 60, height: 60, fit: BoxFit.cover) : Image.file(File(e.value.path), width: 60, height: 60, fit: BoxFit.cover)),
            Positioned(top: -5, right: -5, child: GestureDetector(onTap: () => setState(() => _attachments.removeAt(e.key)), child: const CircleAvatar(radius: 10, backgroundColor: AppTheme.errorRed, child: Icon(Icons.close, size: 12, color: Colors.white)))),
          ])).toList())],
        if (_isLateNight) ...[AppTheme.gapHeightMedium,
          Container(width: double.infinity, padding: AppTheme.paddingAllMedium, decoration: BoxDecoration(color: AppTheme.warningOrange.withOpacity(0.1), borderRadius: AppTheme.radiusSmall, border: Border.all(color: AppTheme.warningOrange.withOpacity(0.4))),
            child: const Row(children: [Icon(Icons.nightlight_round, color: AppTheme.warningOrange, size: 18), AppTheme.gapWidthSmall, Expanded(child: Text('الوقت متأخر — قد يتأخر الرد', style: TextStyle(color: AppTheme.warningOrange, fontSize: 12)))]))],
        AppTheme.gapHeightLarge,
        SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
          onPressed: () { if (_subjectCtrl.text.trim().length < 10) { _snack('اكتب وصف أطول (10 أحرف)'); return; } _goTo(5); },
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          label: const Text('متابعة للدفع', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
        )),
      ])));
  }

  // ── الدفع ──
  Widget _buildPaymentForm() {
    final config = context.watch<ConfigProvider>().config;
    final channels = config?.enabledPayChannels ?? [];
    final price = _serviceType == 0 ? 500 : 2000;
    return Scaffold(backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: const Text('الدفع', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold), onPressed: () => _goTo(_isContinuing ? 3 : 4))),
      body: SingleChildScrollView(padding: AppTheme.paddingAllLarge, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: double.infinity, padding: AppTheme.paddingAllMedium, decoration: BoxDecoration(color: AppTheme.primaryGold.withOpacity(0.1), borderRadius: AppTheme.radiusMedium, border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3))),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_isContinuing ? '🔄 تجديد محادثة' : (_serviceType == 0 ? '📞 استشارة هاتفية' : '🏢 جلسة حضورية'), style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold)),
              Text('$price ل.س', style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: 18))]),
            if (!_isContinuing && _subjectCtrl.text.isNotEmpty) ...[const SizedBox(height: 4), Text(_subjectCtrl.text.trim(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textGrey, fontSize: 11))],
          ])),
        AppTheme.gapHeightLarge,
        const Text('قناة الدفع:', style: TextStyle(color: AppTheme.textWhite, fontSize: 13, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightSmall,
        ...channels.map((e) {
          final sel = _channel == e.key; final name = (e.value['name'] ?? e.key).toString(); final icon = (e.value['icon'] ?? '💳').toString();
          return GestureDetector(onTap: () => setState(() => _channel = e.key), child: Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: sel ? AppTheme.primaryGold.withOpacity(0.15) : AppTheme.surfaceBlack, borderRadius: AppTheme.radiusSmall, border: Border.all(color: sel ? AppTheme.primaryGold : Colors.white12)),
            child: Row(children: [Text(icon, style: const TextStyle(fontSize: 16)), AppTheme.gapWidthSmall, Expanded(child: Text(name, style: TextStyle(color: sel ? AppTheme.primaryGold : AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 13))),
              Icon(sel ? Icons.check_circle : Icons.radio_button_unchecked, color: sel ? AppTheme.primaryGold : AppTheme.textGrey, size: 18)])));
        }),
        AppTheme.gapHeightMedium,
        if (_needsSenderPhone) ...[
          const Text('رقم الهاتف المحوَّل منه (اختياري):', style: TextStyle(color: AppTheme.textWhite, fontSize: 13)),
          AppTheme.gapHeightSmall,
          TextField(controller: _senderPhoneCtrl, keyboardType: TextInputType.phone, style: const TextStyle(color: AppTheme.textWhite), decoration: const InputDecoration(hintText: '09xxxxxxxx', prefixIcon: Icon(Icons.phone, color: AppTheme.primaryGold), filled: true, fillColor: AppTheme.surfaceBlack, border: OutlineInputBorder())),
          AppTheme.gapHeightMedium],
        const Text('رقم العملية:', style: TextStyle(color: AppTheme.textWhite, fontSize: 13, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightSmall,
        TextField(controller: _refCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AppTheme.textWhite), decoration: const InputDecoration(hintText: 'رقم الإيصال', prefixIcon: Icon(Icons.tag, color: AppTheme.primaryGold), filled: true, fillColor: AppTheme.surfaceBlack, border: OutlineInputBorder())),
        AppTheme.gapHeightMedium,
        const Text('إثبات الدفع:', style: TextStyle(color: AppTheme.textWhite, fontSize: 13, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightSmall,
        GestureDetector(onTap: _pickProof, child: Container(width: double.infinity, padding: AppTheme.paddingAllMedium, decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusSmall, border: Border.all(color: _proofImage != null ? AppTheme.successGreen : Colors.white12)),
          child: Row(children: [Icon(_proofImage == null ? Icons.upload_file : Icons.check_circle, color: _proofImage == null ? AppTheme.textGrey : AppTheme.successGreen), AppTheme.gapWidthSmall, Text(_proofImage == null ? 'اختر صورة إثبات الدفع' : 'تم ✓', style: const TextStyle(color: AppTheme.textGrey, fontSize: 13))]))),
        AppTheme.gapHeightLarge,
        SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
          onPressed: _submitting ? null : _pay,
          icon: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.payment, color: Colors.black),
          label: Text(_submitting ? 'جارٍ...' : 'ادفع $price ل.س', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
        )),
      ])));
  }

  // ── النجاح ──
  Widget _buildSuccess() {
    final isCont = _isContinuing;
    return Scaffold(backgroundColor: AppTheme.scaffoldBackground, body: Center(child: SingleChildScrollView(padding: AppTheme.paddingAllLarge, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.check_circle, color: AppTheme.successGreen, size: 64),
      AppTheme.gapHeightLarge,
      const Text('✅ تم إرسال الدفعة', style: TextStyle(color: AppTheme.textWhite, fontSize: 18, fontWeight: FontWeight.bold)),
      AppTheme.gapHeightMedium,
      Container(width: double.infinity, padding: AppTheme.paddingAllMedium, decoration: BoxDecoration(color: AppTheme.infoBlue.withOpacity(0.1), borderRadius: AppTheme.radiusMedium, border: Border.all(color: AppTheme.infoBlue.withOpacity(0.3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isCont ? '🔄 تجديد محادثة سابقة' : '📋 الخطوات التالية:', style: const TextStyle(color: AppTheme.infoBlue, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          const Text('1️⃣ الإدارة تراجع الدفعة (عادة خلال ساعة)', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.8)),
          Text(isCont ? '2️⃣ بعد التأكيد → تُفتح المحادثة تلقائياً' : '2️⃣ بعد التأكيد → ترسل الطلب للمحامي', style: const TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.8)),
          if (!isCont) const Text('3️⃣ المحامي يدرس ويفتح المحادثة', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.8)),
        ])),
      AppTheme.gapHeightXL,
      SizedBox(width: double.infinity, height: 48, child: ElevatedButton.icon(
        onPressed: () { _resetWizard(); _loadAll(); },
        icon: const Icon(Icons.home, color: Colors.black),
        label: const Text('العودة للرئيسية', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
      )),
      AppTheme.gapHeightMedium,
      const Text('ستصلك إشعار عند كل خطوة 👆', style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
    ]))));
  }

  void _snack(String m) { if (!mounted) return; AppTheme.showSnackBar(context, SnackBar(content: Text(m))); }
}

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

class LegalConsultationBookingScreen extends StatefulWidget {
  const LegalConsultationBookingScreen({super.key});
  @override
  State<LegalConsultationBookingScreen> createState() => _LegalConsultationBookingScreenState();
}

class _LegalConsultationBookingScreenState extends State<LegalConsultationBookingScreen> {
  final _storage = StorageService();
  bool _loading = true;

  // البيانات المحملة
  List<Map<String, dynamic>> _pendingPayments = [];  // دفعات قيد المراجعة
  List<Map<String, dynamic>> _approvedPayments = []; // دفعات مقبولة بدون استشارة
  List<Map<String, dynamic>> _activeConsultations = []; // استشارات نشطة
  List<Map<String, dynamic>> _previousChats = [];     // محادثات سابقة

  // حالة الـ Wizard
  bool _showWizard = false;
  bool _showExplanation = false;
  int _wizardStep = 0; // 0=نوع, 1=موضوع, 2=دفع, 3=نجاح
  int _selectedService = 0;
  final _subjectCtrl = TextEditingController();
  final List<XFile> _attachments = [];
  String _paymentChannel = '';
  final _refCtrl = TextEditingController();
  final _senderPhoneCtrl = TextEditingController();
  XFile? _proofImage;
  bool _submitting = false;
  String? _pendingPaymentId; // إذا في دفعة معلقة

  // chips المواضيع الجاهزة
  static const _topicChips = [
    'عقد إيجار', 'نزاع عقاري', 'إرث وتوزيع', 'مخالفة مرورية',
    'استفسار عن سند', 'مشكلة جيران', 'عقد عمل', 'أخرى',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _refCtrl.dispose();
    _senderPhoneCtrl.dispose();
    super.dispose();
  }

  bool get _isLateNight {
    final h = DateTime.now().hour;
    return h >= 23 || h < 9;
  }

  bool get _needsSenderPhone => _paymentChannel == 'balance' || _paymentChannel == 'syriatel_cash';
  bool get _hasPendingPayment => _pendingPayments.isNotEmpty;
  bool get _hasApprovedWithoutConsultation => _approvedPayments.isNotEmpty;

  String _normalizePhone(String phone) {
    final d = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (d.startsWith('963') && d.length == 12) return '0${d.substring(3)}';
    if (d.startsWith('09') && d.length == 10) return d;
    if (d.startsWith('9') && d.length == 9) return '0$d';
    return d;
  }

  /// تحميل كل البيانات
  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final uid = context.read<AuthProvider>().userModel?.uid ?? '';
    if (uid.isEmpty) { setState(() => _loading = false); return; }

    try {
      // جلب الدفعات (tp=2 = استشارة قانونية)
      final payments = await SupabaseService().client
          .from(DbTables.payments)
          .select('id, sts, amt, pkg, channel, ref, meta, ts_crt')
          .eq('uid', uid)
          .eq('tp', 2)
          .order('ts_crt', ascending: false);

      final pending = <Map<String, dynamic>>[];
      final approved = <Map<String, dynamic>>[];
      for (final p in payments as List) {
        final m = Map<String, dynamic>.from(p as Map);
        if (m['sts'] == 0) pending.add(m);
        else if (m['sts'] == 1) approved.add(m);
      }

      // جلب الاستشارات
      final consultRes = await SupabaseService().invokeFunction(
        'legal-actions',
        body: {'action': 'list_my_consultations', 'user_uid': uid},
      );
      final cData = consultRes.data as Map<String, dynamic>?;
      final allConsultations = cData != null && cData['success'] == true
          ? List<Map<String, dynamic>>.from(cData['consultations'] as List? ?? [])
          : <Map<String, dynamic>>[];

      // تصنيف الاستشارات
      final active = allConsultations.where((c) => [0, 1, 4].contains(c['status'])).toList();
      final previous = allConsultations.where((c) {
        final chatStarted = c['chat_started_at'] != null;
        if (!chatStarted) return false;
        final dt = DateTime.tryParse(c['chat_started_at'].toString());
        if (dt == null) return false;
        return DateTime.now().difference(dt).inDays < 7;
      }).toList();

      if (mounted) {
        setState(() {
          _pendingPayments = pending;
          _approvedPayments = approved;
          _activeConsultations = active;
          _previousChats = previous;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
    context.read<LegalProvider>().fetchActiveLawyers();
  }

  // ── إرفاق المستندات ──
  void _pickAttachments() async {
    final remaining = 5 - _attachments.length;
    if (remaining <= 0) { _snack('الحد الأقصى 5 صور'); return; }
    final files = await ImagePicker().pickMultiImage(imageQuality: 60, maxWidth: 1280);
    if (files.isNotEmpty) setState(() => _attachments.addAll(files.take(remaining)));
  }

  void _removeAttachment(int i) => setState(() => _attachments.removeAt(i));

  void _pickProof() async {
    final file = await _storage.pickImage(fromCamera: false);
    if (file != null) setState(() => _proofImage = file);
  }

  Future<List<String>> _uploadAttachments() async {
    if (_attachments.isEmpty) return [];
    final urls = <String>[];
    try {
      final uid = context.read<AuthProvider>().userModel?.uid ?? '';
      for (final file in _attachments) {
        final compressed = await _storage.compressImage(File(file.path));
        final bytes = await (compressed ?? File(file.path)).readAsBytes();
        final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.${file.path.split('.').last}';
        await SupabaseService().storage.from('consultation_files').uploadBinary(path, bytes, fileOptions: FileOptions(cacheControl: '3600', upsert: false));
        urls.add(path);
      }
    } catch (_) {}
    return urls;
  }

  Future<String?> _uploadProof(String userId) async {
    if (_proofImage == null) return null;
    try {
      final path = '$userId/proof_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = kIsWeb ? await _proofImage!.readAsBytes()
          : await (await _storage.compressImage(File(_proofImage!.path)) ?? File(_proofImage!.path)).readAsBytes();
      await SupabaseService().storage.from(StorageService.paymentProofsBucket).uploadBinary(path, bytes, fileOptions: FileOptions(cacheControl: '3600', upsert: false));
      return path;
    } catch (_) { return null; }
  }

  // ── الدفع ──
  Future<void> _pay() async {
    final subject = _subjectCtrl.text.trim();
    if (subject.isEmpty || subject.length < 10) { _snack('يرجى كتابة موضوع الاستشارة (10 أحرف على الأقل)'); return; }
    if (_paymentChannel.isEmpty) { _snack('يرجى اختيار قناة الدفع'); return; }
    if (_proofImage == null) { _snack('يرجى رفع إثبات الدفع'); return; }
    final refNum = InputValidators.normalizeDigits(_refCtrl.text.trim());
    if (refNum.isEmpty) { _snack('يرجى إدخال رقم العملية'); return; }

    setState(() => _submitting = true);
    final user = context.read<AuthProvider>().userModel;
    if (user == null) { setState(() => _submitting = false); return; }

    String senderPhone = '';
    if (_needsSenderPhone) {
      senderPhone = _normalizePhone(_senderPhoneCtrl.text.trim());
      if (senderPhone.length < 9) { _snack('رقم الهاتف غير صحيح'); setState(() => _submitting = false); return; }
    }

    final proofUrl = await _uploadProof(user.uid);
    if (proofUrl == null) { _snack('فشل رفع الإثبات'); setState(() => _submitting = false); return; }

    final price = _selectedService == 0 ? 500.0 : 2000.0;
    final payment = PaymentModel(
      id: '', uid: user.uid, tp: 2, pkg: _selectedService, amt: price, cur: 1, mtd: 0,
      channel: _paymentChannel, proof: proofUrl, ref: refNum, sts: 0, tsCrt: DateTime.now(),
      meta: {'service': 'legal_consultation', if (senderPhone.isNotEmpty) 'sender_phone': senderPhone},
    );

    try {
      final ok = await context.read<PaymentProvider>().makePayment(payment);
      if (ok) {
        setState(() { _wizardStep = 3; _pendingPaymentId = 'new'; });
        _snack('✅ تم إرسال الدفعة بنجاح');
      } else { _snack('فشل تسجيل الدفعة'); }
    } catch (e) { _snack('خطأ: $e'); }
    if (mounted) setState(() => _submitting = false);
  }

  // ── إرسال الاستشارة بعد قبول الدفعة ──
  Future<void> _submitConsultation({int? serviceType}) async {
    setState(() => _submitting = true);
    final attachmentPaths = await _uploadAttachments();
    final sType = serviceType ?? _selectedService;
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'book_consultation', 'user_uid': context.read<AuthProvider>().userModel?.uid ?? '',
        'service_type': sType, 'subject': _subjectCtrl.text.trim(),
        'price': sType == 0 ? 500 : 2000, 'attachments': attachmentPaths,
      });
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        _snack('✅ تم إرسال طلب الاستشارة — المحامي يدرس مشكلتك');
        _resetWizard();
        _loadAll();
      } else { _snack(data?['error']?.toString() ?? 'فشل إرسال الطلب'); }
    } catch (e) { _snack('خطأ: $e'); }
    if (mounted) setState(() => _submitting = false);
  }

  // ── تجديد محادثة ──
  Future<void> _renewChat(String consultId) async {
    setState(() => _submitting = true);
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'renew_chat', 'user_uid': context.read<AuthProvider>().userModel?.uid ?? '',
        'consultation_id': consultId,
      });
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        _snack('✅ تم تجديد المحادثة 15 دقيقة');
        if (mounted) context.push('/legal/chat/$consultId');
      } else { _snack(data?['error']?.toString() ?? 'فشل التجديد'); }
    } catch (e) { _snack('خطأ: $e'); }
    if (mounted) setState(() => _submitting = false);
  }

  void _resetWizard() {
    _showWizard = false;
    _showExplanation = false;
    _wizardStep = 0;
    _selectedService = 0;
    _subjectCtrl.clear();
    _attachments.clear();
    _paymentChannel = '';
    _proofImage = null;
    _refCtrl.clear();
    _senderPhoneCtrl.clear();
  }

  void _openChat(String id) => context.push('/legal/chat/$id');

  // ══════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_showExplanation) return _buildExplanation();
    if (_showWizard) return _buildWizard();

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: const Text('الاستشارة القانونية', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold), onPressed: () => Navigator.pop(context)),
        actions: [IconButton(icon: const Icon(Icons.refresh, color: AppTheme.primaryGold), onPressed: _loadAll)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGold))
          : RefreshIndicator(color: AppTheme.primaryGold, onRefresh: _loadAll, child: _buildDashboard()),
    );
  }

  // ── لوحة التحكم الرئيسية ──
  Widget _buildDashboard() {
    final hasActive = _activeConsultations.isNotEmpty;
    final hasPending = _hasPendingPayment;
    final hasApproved = _hasApprovedWithoutConsultation;
    final hasPrevious = _previousChats.isNotEmpty;
    final isEmpty = !hasActive && !hasPending && !hasApproved && !hasPrevious;

    return ListView(padding: AppTheme.paddingAllLarge, children: [
      // تنويه: طلب قيد المراجعة
      if (hasPending) ...[
        _pendingBanner(),
        AppTheme.gapHeightMedium,
      ],

      // الدفعات المقبولة بدون استشارة → زر إرسال
      if (hasApproved) ...[
        const Text('📤 دفعات مقبولة — أرسل طلبك للمحامي:', style: TextStyle(color: AppTheme.primaryGold, fontSize: 14, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightSmall,
        ..._approvedPayments.map(_approvedPaymentCard),
        AppTheme.gapHeightMedium,
      ],

      // الاستشارات النشطة
      if (hasActive) ...[
        const Text('📌 استشاراتي الحالية:', style: TextStyle(color: AppTheme.primaryGold, fontSize: 14, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightSmall,
        ..._activeConsultations.map(_activeConsultationCard),
        AppTheme.gapHeightMedium,
      ],

      // أزرار جديدة
      if (!hasPending) ...[
        Row(children: [
          Expanded(child: _newServiceButton(Icons.phone_in_talk, 'استشارة هاتفية', '500 ل.س', 0)),
          AppTheme.gapWidthMedium,
          Expanded(child: _newServiceButton(Icons.business, 'جلسة حضورية', '2,000 ل.س', 1)),
        ]),
        AppTheme.gapHeightMedium,
      ],

      // المحادثات السابقة
      if (hasPrevious) ...[
        const Text('📚 محادثات سابقة:', style: TextStyle(color: AppTheme.primaryGold, fontSize: 14, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightSmall,
        ..._previousChats.map(_previousChatCard),
      ],

      // حالة فارغة
      if (isEmpty)
        Center(child: Padding(padding: const EdgeInsets.only(top: 60), child: Column(children: [
          const Icon(Icons.gavel, color: AppTheme.textGrey, size: 64),
          AppTheme.gapHeightLarge,
          const Text('لا توجد استشارات حالياً', style: TextStyle(color: AppTheme.textGrey, fontSize: 16)),
          AppTheme.gapHeightSmall,
          const Text('اختر نوع الاستشارة للبدء', style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
        ]))),
    ]);
  }

  // ── بانر: طلب قيد المراجعة ──
  Widget _pendingBanner() {
    return Container(
      width: double.infinity, padding: AppTheme.paddingAllMedium,
      decoration: BoxDecoration(color: AppTheme.warningOrange.withOpacity(0.1), borderRadius: AppTheme.radiusMedium, border: Border.all(color: AppTheme.warningOrange.withOpacity(0.4))),
      child: Column(children: [
        const Row(children: [
          Icon(Icons.hourglass_top, color: AppTheme.warningOrange, size: 20),
          AppTheme.gapWidthSmall,
          Expanded(child: Text('لديك طلب دفع قيد المراجعة', style: TextStyle(color: AppTheme.warningOrange, fontWeight: FontWeight.bold, fontSize: 14))),
        ]),
        const SizedBox(height: 6),
        ..._pendingPayments.map((p) {
          final amt = (p['amt'] ?? 0) as num;
          final pkg = (p['pkg'] ?? 0) as int;
          return Padding(padding: const EdgeInsets.only(top: 2), child: Text(
            '${pkg == 0 ? 'هاتفية' : 'حضورية'} — ${amt.toStringAsFixed(0)} ل.س',
            style: const TextStyle(color: AppTheme.textGrey, fontSize: 12)));
        }),
        const SizedBox(height: 6),
        const Text('يرجى الانتظار حتى تأكيد الإدارة — ستصلك إشعار', style: TextStyle(color: AppTheme.textGrey, fontSize: 11)),
      ]),
    );
  }

  // ── بطاقة دفعة مقبولة بدون استشارة ──
  Widget _approvedPaymentCard(Map<String, dynamic> p) {
    final amt = (p['amt'] ?? 0) as num;
    final pkg = (p['pkg'] ?? 0) as int;
    final typeName = pkg == 0 ? 'استشارة هاتفية' : 'جلسة حضورية';
    return Container(
      margin: const EdgeInsets.only(bottom: 8), padding: AppTheme.paddingAllMedium,
      decoration: BoxDecoration(color: AppTheme.successGreen.withOpacity(0.08), borderRadius: AppTheme.radiusMedium, border: Border.all(color: AppTheme.successGreen.withOpacity(0.4))),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.check_circle, color: AppTheme.successGreen, size: 18),
          AppTheme.gapWidthSmall,
          Expanded(child: Text('$typeName — ${amt.toStringAsFixed(0)} ل.س', style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 13))),
        ]),
        AppTheme.gapHeightSmall,
        SizedBox(width: double.infinity, height: 40, child: ElevatedButton.icon(
          onPressed: () {
            _selectedService = pkg;
            _showWizard = true;
            _wizardStep = 1; // مباشرة لكتابة الموضوع
            setState(() {});
          },
          icon: const Icon(Icons.send, color: Colors.black, size: 16),
          label: const Text('إرسال الطلب للمحامي', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
        )),
      ]),
    );
  }

  // ── بطاقة استشارة نشطة ──
  Widget _activeConsultationCard(Map<String, dynamic> c) {
    final status = c['status'] ?? 0;
    final subject = (c['subject'] ?? '').toString();
    final alias = (c['lawyer_alias'] ?? '').toString();
    final chatStarted = c['chat_started_at'] != null;
    final id = c['id'].toString();
    final sType = (c['service_type'] ?? 0) as int;

    String statusLabel;
    Color statusColor;
    IconData statusIcon;

    if (status == 0) {
      statusLabel = 'بانتظار قبول المحامي';
      statusColor = AppTheme.warningOrange;
      statusIcon = Icons.hourglass_empty;
    } else if (status == 4 || (status == 1 && !chatStarted)) {
      statusLabel = 'قيد الدراسة — المحامي يجهّز';
      statusColor = AppTheme.infoBlue;
      statusIcon = Icons.menu_book;
    } else {
      statusLabel = 'مؤكدة';
      statusColor = AppTheme.successGreen;
      statusIcon = Icons.check_circle;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8), padding: AppTheme.paddingAllMedium,
      decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusMedium, border: Border.all(color: statusColor.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(statusIcon, color: statusColor, size: 18),
          AppTheme.gapWidthSmall,
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(sType == 0 ? '📞 استشارة هاتفية' : '🏢 جلسة حضورية', style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 13)),
            Text(subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: AppTheme.radiusSmall),
            child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold))),
        ]),
        if (alias.isNotEmpty) ...[const SizedBox(height: 4), Text('⚖️ $alias', style: const TextStyle(color: AppTheme.textGrey, fontSize: 11))],
        if (chatStarted && status == 1) ...[AppTheme.gapHeightSmall,
          SizedBox(width: double.infinity, height: 40, child: ElevatedButton.icon(
            onPressed: () => _openChat(id),
            icon: const Icon(Icons.chat, color: Colors.black, size: 16),
            label: const Text('فتح المحادثة', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successGreen),
          ))],
      ]),
    );
  }

  // ── بطاقة محادثة سابقة ──
  Widget _previousChatCard(Map<String, dynamic> c) {
    final subject = (c['subject'] ?? '').toString();
    final alias = (c['lawyer_alias'] ?? 'محامي المكتب').toString();
    final id = c['id'].toString();
    final chatStartedAt = DateTime.tryParse(c['chat_started_at']?.toString() ?? '');
    final daysLeft = chatStartedAt != null ? 7 - DateTime.now().difference(chatStartedAt).inDays : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8), padding: AppTheme.paddingAllMedium,
      decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusMedium, border: Border.all(color: Colors.white12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.history, color: AppTheme.textGrey, size: 16),
          AppTheme.gapWidthSmall,
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 12)),
            Text('⚖️ $alias', style: const TextStyle(color: AppTheme.textGrey, fontSize: 10)),
          ])),
          if (daysLeft > 0)
            Text('📅 $daysLeft أيام', style: TextStyle(color: daysLeft <= 2 ? AppTheme.errorRed : AppTheme.textGrey, fontSize: 10)),
        ]),
        AppTheme.gapHeightSmall,
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: () => _openChat(id),
            icon: const Icon(Icons.visibility, size: 14, color: AppTheme.textGrey),
            label: const Text('عرض', style: TextStyle(color: AppTheme.textGrey, fontSize: 11)),
            style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.white24)),
          )),
          AppTheme.gapWidthSmall,
          Expanded(child: ElevatedButton.icon(
            onPressed: () => _renewChat(id),
            icon: const Icon(Icons.refresh, size: 14, color: Colors.black),
            label: const Text('تجديد 500 ل.س', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
          )),
        ]),
      ]),
    );
  }

  // ── زر خدمة جديدة ──
  Widget _newServiceButton(IconData icon, String title, String price, int serviceType) {
    return GestureDetector(
      onTap: () { _selectedService = serviceType; _showExplanation = true; setState(() {}); },
      child: Container(
        padding: AppTheme.paddingAllMedium,
        decoration: BoxDecoration(color: AppTheme.primaryGold.withOpacity(0.08), borderRadius: AppTheme.radiusMedium, border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3))),
        child: Column(children: [
          Icon(icon, color: AppTheme.primaryGold, size: 28),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 2),
          Text(price, style: const TextStyle(color: AppTheme.primaryGold, fontSize: 11, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════
  // شاشة الإرشادات
  // ══════════════════════════════════════════
  Widget _buildExplanation() {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: Text(_selectedService == 0 ? '⚖️ استشارة هاتفية' : '🏢 جلسة حضورية', style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold), onPressed: () { setState(() { _showExplanation = false; }); })),
      body: SingleChildScrollView(padding: AppTheme.paddingAllLarge, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Center(child: Icon(Icons.gavel, color: AppTheme.primaryGold, size: 48)),
        AppTheme.gapHeightLarge,
        _serviceInfoCard(Icons.phone_in_talk, 'استشارة هاتفية', '500 ل.س', '15 دقيقة', [
          'محادثة مباشرة مع محامي المكتب', 'للأسئلة القانونية البسيطة',
          'يمكنك تجديد الوقت بـ 500 ل.س كل 15 دقيقة', 'المحادثة تبقى 7 أيام',
        ]),
        AppTheme.gapHeightMedium,
        _serviceInfoCard(Icons.business, 'جلسة حضورية', '2,000 ل.س', 'ساعة كاملة', [
          'اجتماع وجهاً لوجه في مكتب المحامي', 'للمشاكل المعقدة ودراسة المستندات',
          'تحجز موعد مسبق', 'يرجى الحضور قبل 10 دقائق',
        ]),
        AppTheme.gapHeightXL,
        Container(width: double.infinity, padding: AppTheme.paddingAllMedium,
          decoration: BoxDecoration(color: AppTheme.warningOrange.withOpacity(0.1), borderRadius: AppTheme.radiusSmall, border: Border.all(color: AppTheme.warningOrange.withOpacity(0.4))),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('⚠️ كيف تعمل؟', style: TextStyle(color: AppTheme.warningOrange, fontWeight: FontWeight.bold, fontSize: 13)),
            SizedBox(height: 6),
            Text('1️⃣ اكتب موضوع الاستشارة وأرفق المستندات', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.8)),
            Text('2️⃣ ادفع المبلغ عبر إحدى قنوات الدفع', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.8)),
            Text('3️⃣ الإدارة تؤكد الدفع (عادة خلال ساعة)', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.8)),
            Text('4️⃣ أرسل الطلب للمحامي — يدرس ويفتح المحادثة', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.8)),
          ])),
        AppTheme.gapHeightLarge,
        SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
          onPressed: () { setState(() { _showExplanation = false; _showWizard = true; _wizardStep = 0; }); },
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          label: const Text('متابعة', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
        )),
      ])),
    );
  }

  Widget _serviceInfoCard(IconData icon, String title, String price, String duration, List<String> points) {
    return Container(padding: AppTheme.paddingAllMedium,
      decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusMedium, border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: AppTheme.primaryGold, size: 20), AppTheme.gapWidthSmall,
          Text(title, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 14)),
          const Spacer(), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppTheme.primaryGold, borderRadius: AppTheme.radiusXL),
            child: Text(price, style: const TextStyle(color: AppTheme.deepBlack, fontWeight: FontWeight.bold, fontSize: 11)))]),
        const SizedBox(height: 4), Text('⏱️ $duration', style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)),
        const SizedBox(height: 8),
        ...points.map((p) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('• ', style: TextStyle(color: AppTheme.primaryGold, fontSize: 12)),
          Expanded(child: Text(p, style: const TextStyle(color: AppTheme.textGrey, fontSize: 11, height: 1.4)))]))),
      ]));
  }

  // ══════════════════════════════════════════
  // الـ Wizard (اختيار نوع → موضوع → دفع → نجاح)
  // ══════════════════════════════════════════
  Widget _buildWizard() {
    switch (_wizardStep) {
      case 0: return _buildChooseType();
      case 1: return _buildSubjectForm();
      case 2: return _buildPaymentForm();
      case 3: return _buildSuccessScreen();
      default: return _buildChooseType();
    }
  }

  Widget _buildChooseType() {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: const Text('اختر نوع الاستشارة', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold), onPressed: () { setState(() { _showWizard = false; }); })),
      body: Padding(padding: AppTheme.paddingAllLarge, child: Column(children: [AppTheme.gapHeightXL,
        _typeCard(Icons.phone_in_talk, 'استشارة هاتفية', '500 ل.س — 15 دقيقة', 'محادثة مباشرة مع محامي المكتب', 0),
        AppTheme.gapHeightLarge,
        _typeCard(Icons.business, 'جلسة حضورية', '2,000 ل.س — ساعة', 'اجتماع في مكتب المحامي', 1),
      ])),
    );
  }

  Widget _typeCard(IconData icon, String title, String subtitle, String desc, int sType) {
    return GestureDetector(
      onTap: () { setState(() { _selectedService = sType; _wizardStep = 1; }); },
      child: Container(width: double.infinity, padding: AppTheme.paddingAllLarge,
        decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusLarge, border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3))),
        child: Row(children: [
          CircleAvatar(radius: 28, backgroundColor: AppTheme.primaryGold.withOpacity(0.2), child: Icon(icon, color: AppTheme.primaryGold, size: 28)),
          AppTheme.gapWidthMedium,
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(title, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 16))),
              if (sType == 0) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppTheme.primaryGold, borderRadius: AppTheme.radiusXL),
                child: const Text('الأكثر طلباً', style: TextStyle(color: AppTheme.deepBlack, fontSize: 9, fontWeight: FontWeight.bold)))]),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: AppTheme.primaryGold, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2), Text(desc, style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)),
          ])),
          const Icon(Icons.arrow_forward_ios, color: AppTheme.primaryGold, size: 16),
        ])),
    );
  }

  Widget _buildSubjectForm() {
    final config = context.watch<ConfigProvider>().config;
    final officeAddress = _getNestedString(config, 'office', 'address');
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: Text(_selectedService == 0 ? 'استشارة هاتفية' : 'جلسة حضورية', style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold), onPressed: () { setState(() { _wizardStep = 0; }); })),
      body: SingleChildScrollView(padding: AppTheme.paddingAllLarge, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // موضوع
        const Text('موضوع الاستشارة:', style: TextStyle(color: AppTheme.primaryGold, fontSize: 15, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightSmall,
        // Chips
        Wrap(spacing: 6, runSpacing: 6, children: _topicChips.map((chip) => GestureDetector(
          onTap: () {
            final current = _subjectCtrl.text;
            setState(() { _subjectCtrl.text = current.isEmpty ? chip : '$current — $chip'; });
          },
          child: Chip(label: Text(chip, style: const TextStyle(fontSize: 11)), backgroundColor: AppTheme.primaryGold.withOpacity(0.1), side: BorderSide(color: AppTheme.primaryGold.withOpacity(0.3))),
        )).toList()),
        AppTheme.gapHeightSmall,
        TextField(controller: _subjectCtrl, maxLines: 4, maxLength: 500, style: const TextStyle(color: AppTheme.textWhite),
          decoration: const InputDecoration(hintText: 'اشرح مشكلتك القانونية باختصار...', filled: true, fillColor: AppTheme.surfaceBlack, border: OutlineInputBorder())),
        AppTheme.gapHeightLarge,

        // عنوان المكتب (للحضورية)
        if (_selectedService == 1 && officeAddress.isNotEmpty) ...[
          Container(width: double.infinity, padding: AppTheme.paddingAllMedium,
            decoration: BoxDecoration(color: AppTheme.infoBlue.withOpacity(0.1), borderRadius: AppTheme.radiusSmall, border: Border.all(color: AppTheme.infoBlue.withOpacity(0.3))),
            child: Row(children: [const Icon(Icons.location_on, color: AppTheme.infoBlue, size: 18), AppTheme.gapWidthSmall,
              Expanded(child: Text('📍 عنوان المكتب: $officeAddress', style: const TextStyle(color: AppTheme.textWhite, fontSize: 12)))])),
          AppTheme.gapHeightMedium,
        ],

        // إرفاق
        const Text('إرفاق المستندات (اختياري — حتى 5 صور):', style: TextStyle(color: AppTheme.primaryGold, fontSize: 14, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightSmall,
        GestureDetector(onTap: _pickAttachments, child: Container(width: double.infinity, padding: AppTheme.paddingAllMedium,
          decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusMedium, border: Border.all(color: Colors.white12)),
          child: Row(children: [const Icon(Icons.add_photo_alternate_outlined, color: AppTheme.primaryGold), AppTheme.gapWidthSmall,
            Text('إضافة صور (${_attachments.length}/5)', style: const TextStyle(color: AppTheme.textGrey))]))),
        if (_attachments.isNotEmpty) ...[AppTheme.gapHeightSmall,
          Wrap(spacing: 8, runSpacing: 8, children: _attachments.asMap().entries.map((e) => Stack(children: [
            ClipRRect(borderRadius: AppTheme.radiusSmall, child: kIsWeb ? Image.network(e.value.path, width: 60, height: 60, fit: BoxFit.cover) : Image.file(File(e.value.path), width: 60, height: 60, fit: BoxFit.cover)),
            Positioned(top: -5, right: -5, child: GestureDetector(onTap: () => _removeAttachment(e.key), child: const CircleAvatar(radius: 10, backgroundColor: AppTheme.errorRed, child: Icon(Icons.close, size: 12, color: Colors.white)))),
          ])).toList())],
        AppTheme.gapHeightLarge,

        if (_isLateNight) ...[
          Container(width: double.infinity, padding: AppTheme.paddingAllMedium,
            decoration: BoxDecoration(color: AppTheme.warningOrange.withOpacity(0.1), borderRadius: AppTheme.radiusSmall, border: Border.all(color: AppTheme.warningOrange.withOpacity(0.4))),
            child: const Row(children: [Icon(Icons.nightlight_round, color: AppTheme.warningOrange, size: 18), AppTheme.gapWidthSmall,
              Expanded(child: Text('الوقت متأخر — قد يتأخر الرد لبعد التاسعة صباحاً', style: TextStyle(color: AppTheme.warningOrange, fontSize: 12)))])),
          AppTheme.gapHeightMedium,
        ],

        SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
          onPressed: () {
            if (_subjectCtrl.text.trim().length < 10) { _snack('يرجى كتابة وصف أطول (10 أحرف)'); return; }
            setState(() => _wizardStep = 2);
          },
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          label: const Text('متابعة للدفع', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
        )),
      ])),
    );
  }

  Widget _buildPaymentForm() {
    final config = context.watch<ConfigProvider>().config;
    final channels = config?.enabledPayChannels ?? [];
    final price = _selectedService == 0 ? 500 : 2000;
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: const Text('الدفع', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold), onPressed: () => setState(() => _wizardStep = 1))),
      body: SingleChildScrollView(padding: AppTheme.paddingAllLarge, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ملخص
        Container(width: double.infinity, padding: AppTheme.paddingAllMedium,
          decoration: BoxDecoration(color: AppTheme.primaryGold.withOpacity(0.1), borderRadius: AppTheme.radiusMedium, border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3))),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_selectedService == 0 ? '📞 استشارة هاتفية' : '🏢 جلسة حضورية', style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold)),
              Text('$price ل.س', style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: 18))]),
            const SizedBox(height: 4),
            Text(_subjectCtrl.text.trim(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)),
            if (_attachments.isNotEmpty) Text('📎 ${_attachments.length} مستند مرفق', style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)),
          ])),
        AppTheme.gapHeightLarge,

        // قنوات الدفع
        const Text('قناة الدفع:', style: TextStyle(color: AppTheme.textWhite, fontSize: 13, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightSmall,
        ...channels.map((e) {
          final sel = _paymentChannel == e.key;
          final name = (e.value['name'] ?? e.key).toString();
          final icon = (e.value['icon'] ?? '💳').toString();
          return GestureDetector(onTap: () => setState(() => _paymentChannel = e.key),
            child: Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: sel ? AppTheme.primaryGold.withOpacity(0.15) : AppTheme.surfaceBlack, borderRadius: AppTheme.radiusSmall, border: Border.all(color: sel ? AppTheme.primaryGold : Colors.white12)),
              child: Row(children: [Text(icon, style: const TextStyle(fontSize: 16)), AppTheme.gapWidthSmall,
                Expanded(child: Text(name, style: TextStyle(color: sel ? AppTheme.primaryGold : AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 13))),
                Icon(sel ? Icons.check_circle : Icons.radio_button_unchecked, color: sel ? AppTheme.primaryGold : AppTheme.textGrey, size: 18)])));
        }),
        AppTheme.gapHeightMedium,

        if (_needsSenderPhone) ...[
          const Text('رقم الهاتف المحوَّل منه (اختياري):', style: TextStyle(color: AppTheme.textWhite, fontSize: 13)),
          AppTheme.gapHeightSmall,
          TextField(controller: _senderPhoneCtrl, keyboardType: TextInputType.phone, style: const TextStyle(color: AppTheme.textWhite),
            decoration: const InputDecoration(hintText: '09xxxxxxxx', prefixIcon: Icon(Icons.phone, color: AppTheme.primaryGold), filled: true, fillColor: AppTheme.surfaceBlack, border: OutlineInputBorder())),
          AppTheme.gapHeightMedium,
        ],

        const Text('رقم العملية / المرجع:', style: TextStyle(color: AppTheme.textWhite, fontSize: 13, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightSmall,
        TextField(controller: _refCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AppTheme.textWhite),
          decoration: const InputDecoration(hintText: 'رقم الإيصال', prefixIcon: Icon(Icons.tag, color: AppTheme.primaryGold), filled: true, fillColor: AppTheme.surfaceBlack, border: OutlineInputBorder())),
        AppTheme.gapHeightMedium,

        const Text('إثبات الدفع:', style: TextStyle(color: AppTheme.textWhite, fontSize: 13, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightSmall,
        GestureDetector(onTap: _pickProof, child: Container(width: double.infinity, padding: AppTheme.paddingAllMedium,
          decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusSmall, border: Border.all(color: _proofImage != null ? AppTheme.successGreen : Colors.white12)),
          child: Row(children: [Icon(_proofImage == null ? Icons.upload_file : Icons.check_circle, color: _proofImage == null ? AppTheme.textGrey : AppTheme.successGreen),
            AppTheme.gapWidthSmall, Text(_proofImage == null ? 'اضغط لاختيار صورة إثبات الدفع' : 'تم ✓', style: const TextStyle(color: AppTheme.textGrey, fontSize: 13))]))),
        AppTheme.gapHeightLarge,

        SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
          onPressed: _submitting ? null : _pay,
          icon: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.payment, color: Colors.black),
          label: Text(_submitting ? 'جارٍ...' : 'ادفع $price ل.س', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
        )),
      ])),
    );
  }

  Widget _buildSuccessScreen() {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      body: Center(child: SingleChildScrollView(padding: AppTheme.paddingAllLarge, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.check_circle, color: AppTheme.successGreen, size: 64),
        AppTheme.gapHeightLarge,
        const Text('✅ تم إرسال الدفعة بنجاح', style: TextStyle(color: AppTheme.textWhite, fontSize: 18, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightMedium,
        Container(width: double.infinity, padding: AppTheme.paddingAllMedium,
          decoration: BoxDecoration(color: AppTheme.infoBlue.withOpacity(0.1), borderRadius: AppTheme.radiusMedium, border: Border.all(color: AppTheme.infoBlue.withOpacity(0.3))),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('📋 الخطوات التالية:', style: TextStyle(color: AppTheme.infoBlue, fontWeight: FontWeight.bold, fontSize: 13)),
            SizedBox(height: 8),
            Text('1️⃣ الإدارة تراجع الدفعة (عادة خلال ساعة)', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.8)),
            Text('2️⃣ ستصلك إشعار عند التأكيد', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.8)),
            Text('3️⃣ بعدها ترسل الطلب للمحامي', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.8)),
            Text('4️⃣ المحامي يدرس ويفتح المحادثة', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.8)),
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
      ]))),
    );
  }

  String _getNestedString(dynamic config, String key1, String key2) {
    try {
      final v = (config as dynamic)?.toJson?.call();
      if (v is Map) {
        final o = v[key1];
        if (o is Map) return (o[key2] ?? '').toString();
      }
    } catch (_) {}
    return '';
  }

  void _snack(String m) { if (!mounted) return; AppTheme.showSnackBar(context, SnackBar(content: Text(m))); }
}

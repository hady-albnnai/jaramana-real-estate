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
import '../../core/validation/input_validators.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../providers/legal_provider.dart';
import '../../providers/payment_provider.dart';
import '../../models/payment_model.dart';
import '../../services/storage_service.dart';

// ─── مراحل الـ Wizard ───
enum _WizardStep { explanation, chooseType, previousChats, form, payment, success }

class LegalConsultationBookingScreen extends StatefulWidget {
  const LegalConsultationBookingScreen({super.key});

  @override
  State<LegalConsultationBookingScreen> createState() => _LegalConsultationBookingScreenState();
}

class _LegalConsultationBookingScreenState extends State<LegalConsultationBookingScreen> {
  _WizardStep _step = _WizardStep.explanation;
  int _selectedService = 0; // 0=هاتفية, 1=حضورية
  final _subjectCtrl = TextEditingController();
  bool _submitting = false;
  List<Map<String, dynamic>> _myConsultations = [];
  bool _loadingConsultations = false;

  // المحادثة المختارة للمتابعة
  String? _selectedPreviousChatId;

  // إرفاق المستندات
  final List<XFile> _attachments = [];
  final _storage = StorageService();

  // الدفع
  String _paymentChannel = '';
  final _refCtrl = TextEditingController();
  final _senderPhoneCtrl = TextEditingController();
  XFile? _proofImage;

  // الحضورية
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMyConsultations();
      context.read<LegalProvider>().fetchActiveLawyers();
    });
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _refCtrl.dispose();
    _senderPhoneCtrl.dispose();
    super.dispose();
  }

  bool get _isLateNight {
    final hour = DateTime.now().hour;
    return hour >= 23 || hour < 9;
  }

  bool get _needsSenderPhone => _paymentChannel == 'balance' || _paymentChannel == 'syriatel_cash';

  String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.startsWith('963') && digits.length == 12) return '0${digits.substring(3)}';
    if (digits.startsWith('09') && digits.length == 10) return digits;
    if (digits.startsWith('9') && digits.length == 9) return '0$digits';
    return digits;
  }

  Future<void> _loadMyConsultations() async {
    setState(() => _loadingConsultations = true);
    try {
      final res = await SupabaseService().invokeFunction(
        'legal-actions',
        body: {'action': 'list_previous_chats', 'user_uid': context.read<AuthProvider>().userModel?.uid ?? ''},
      );
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        setState(() => _myConsultations = List<Map<String, dynamic>>.from(data['consultations'] as List? ?? []));
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingConsultations = false);
  }

  void _pickAttachments() async {
    final remaining = 5 - _attachments.length;
    if (remaining <= 0) { _snack('الحد الأقصى 5 صور'); return; }
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 60, maxWidth: 1280);
    if (files.isNotEmpty) setState(() => _attachments.addAll(files.take(remaining)));
  }

  void _removeAttachment(int index) => setState(() => _attachments.removeAt(index));

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
        final ext = file.path.split('.').last;
        final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
        await SupabaseService().storage.from('consultation_files').uploadBinary(
          path, bytes, fileOptions: FileOptions(cacheControl: '3600', upsert: false),
        );
        urls.add(path);
      }
    } catch (_) {}
    return urls;
  }

  Future<String?> _uploadProof(String userId) async {
    if (_proofImage == null) return null;
    try {
      final storage = SupabaseService().storage;
      final fileName = 'consultation_proof_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = '$userId/$fileName';
      final bytes = kIsWeb
          ? await _proofImage!.readAsBytes()
          : await (await _storage.compressImage(File(_proofImage!.path)) ?? File(_proofImage!.path)).readAsBytes();
      await storage.from(StorageService.paymentProofsBucket).uploadBinary(
        path, bytes, fileOptions: FileOptions(cacheControl: '3600', upsert: false),
      );
      return path;
    } catch (_) { return null; }
  }

  Future<void> _pay() async {
    final subject = _subjectCtrl.text.trim();
    if (subject.isEmpty) { _snack('يرجى كتابة موضوع الاستشارة'); return; }
    if (subject.length < 10) { _snack('يرجى كتابة وصف أطول'); return; }
    if (_paymentChannel.isEmpty) { _snack('يرجى اختيار قناة الدفع'); return; }
    if (_proofImage == null) { _snack('يرجى رفع إثبات الدفع'); return; }
    final refNum = InputValidators.normalizeDigits(_refCtrl.text.trim());
    if (refNum.isEmpty) { _snack('يرجى إدخال رقم العملية'); return; }

    String senderPhone = '';
    if (_needsSenderPhone) {
      senderPhone = _normalizePhone(_senderPhoneCtrl.text.trim());
      if (senderPhone.isEmpty || senderPhone.length < 9) { _snack('يرجى إدخال رقم الهاتف'); return; }
    }

    setState(() => _submitting = true);
    final auth = context.read<AuthProvider>();
    final user = auth.userModel;
    if (user == null) { _snack('يجب تسجيل الدخول'); setState(() => _submitting = false); return; }

    final proofUrl = await _uploadProof(user.uid);
    if (proofUrl == null) { _snack('فشل رفع الإثبات'); setState(() => _submitting = false); return; }

    final price = _selectedService == 0 ? 500.0 : 2000.0;
    final payment = PaymentModel(
      id: '', uid: user.uid, tp: 2, pkg: _selectedService, amt: price, cur: 1, mtd: 0,
      channel: _paymentChannel, proof: proofUrl, ref: refNum, sts: 0,
      tsCrt: DateTime.now(),
      meta: {
        'service': 'legal_consultation',
        if (senderPhone.isNotEmpty) 'sender_phone': senderPhone,
        if (_selectedPreviousChatId != null) 'renew_chat_id': _selectedPreviousChatId,
      },
    );

    try {
      final paymentProv = context.read<PaymentProvider>();
      final ok = await paymentProv.makePayment(payment);
      if (ok) {
        setState(() => _step = _WizardStep.success);
        _snack('✅ تم إرسال الدفعة بنجاح');
      } else {
        _snack('فشل تسجيل الدفعة');
      }
    } catch (e) { _snack('خطأ: $e'); }
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _submitConsultation() async {
    setState(() => _submitting = true);
    final attachmentPaths = await _uploadAttachments();
    try {
      final res = await SupabaseService().invokeFunction(
        'legal-actions',
        body: {
          'action': 'book_consultation',
          'user_uid': context.read<AuthProvider>().userModel?.uid ?? '',
          'service_type': _selectedService,
          'subject': _subjectCtrl.text.trim(),
          'price': _selectedService == 0 ? 500 : 2000,
          'attachments': attachmentPaths,
        },
      );
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        _snack('✅ تم إرسال طلب الاستشارة بنجاح');
        _resetForm();
        _loadMyConsultations();
      } else {
        _snack(data?['message']?.toString() ?? data?['error']?.toString() ?? 'فشل إرسال الطلب');
      }
    } catch (e) { _snack('حدث خطأ: $e'); }
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _renewChat(String consultId) async {
    setState(() => _submitting = true);
    try {
      final res = await SupabaseService().invokeFunction(
        'legal-actions',
        body: {
          'action': 'renew_chat',
          'user_uid': context.read<AuthProvider>().userModel?.uid ?? '',
          'consultation_id': consultId,
        },
      );
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        _snack('✅ تم تجديد المحادثة 15 دقيقة إضافية');
        if (mounted) context.push('/legal/chat/$consultId');
      } else {
        _snack(data?['error']?.toString() ?? 'فشل التجديد');
      }
    } catch (e) { _snack('خطأ: $e'); }
    if (mounted) setState(() => _submitting = false);
  }

  void _resetForm() {
    _subjectCtrl.clear();
    _attachments.clear();
    _paymentChannel = '';
    _proofImage = null;
    _refCtrl.clear();
    _senderPhoneCtrl.clear();
    _selectedPreviousChatId = null;
    _selectedDate = null;
    _selectedTime = null;
  }

  void _openChat(String consultId) => context.push('/legal/chat/$consultId');

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _WizardStep.explanation: return _buildExplanation();
      case _WizardStep.chooseType: return _buildChooseType();
      case _WizardStep.previousChats: return _buildPreviousChats();
      case _WizardStep.form: return _buildForm();
      case _WizardStep.payment: return _buildPayment();
      case _WizardStep.success: return _buildSuccess();
    }
  }

  // ─── شاشة الإرشادات ───
  Widget _buildExplanation() {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: const Text('الاستشارة القانونية', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold), onPressed: () => Navigator.pop(context))),
      body: SingleChildScrollView(padding: AppTheme.paddingAllLarge, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Center(child: Icon(Icons.gavel, color: AppTheme.primaryGold, size: 48)),
        AppTheme.gapHeightLarge,
        const Center(child: Text('⚖️ الخدمات القانونية', style: TextStyle(color: AppTheme.primaryGold, fontSize: 20, fontWeight: FontWeight.bold))),
        AppTheme.gapHeightXL,
        const Text('نوعا الاستشارة المتاحة:', style: TextStyle(color: AppTheme.textWhite, fontSize: 15, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightMedium,

        _serviceInfoCard(Icons.phone_in_talk, 'استشارة هاتفية', '500 ل.س', '15 دقيقة', [
          'اتصال صوتي مباشر مع محامي المكتب',
          'للأسئلة القانونية البسيطة والسريعة',
          'يمكنك تجديد الوقت بـ 500 ل.س كل 15 دقيقة',
          'المحادثة تبقى 7 أيام ثم تُحذف',
        ]),
        AppTheme.gapHeightMedium,
        _serviceInfoCard(Icons.business, 'جلسة حضورية', '2,000 ل.س', 'ساعة كاملة', [
          'اجتماع وجهاً لوجه في مكتب المحامي',
          'للمشاكل المعقدة ودراسة المستندات',
          'تحجز موعد مسبق بالتاريخ والوقت',
          'يرجى الحضور قبل 10 دقائق من الموعد',
        ]),
        AppTheme.gapHeightXL,

        Container(width: double.infinity, padding: AppTheme.paddingAllMedium,
          decoration: BoxDecoration(color: AppTheme.warningOrange.withOpacity(0.1), borderRadius: AppTheme.radiusSmall, border: Border.all(color: AppTheme.warningOrange.withOpacity(0.4))),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('⚠️ تنبيهات:', style: TextStyle(color: AppTheme.warningOrange, fontWeight: FontWeight.bold, fontSize: 13)),
            SizedBox(height: 6),
            Text('• الدفع يتم أولاً ثم تأكيد الإدارة قبل بدء الاستشارة', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.6)),
            Text('• عدم الرد خلال ساعة = إعادة تفعيل بدون دفع مجدداً', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.6)),
            Text('• المحادثة سرية — لا يظهر اسم المحامي الحقيقي', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.6)),
            Text('• يمكنك تحويل الاستشارة الهاتفية لحضورية مع خصم المبلغ المدفوع', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.6)),
          ])),
        AppTheme.gapHeightLarge,
        SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
          onPressed: () => setState(() => _step = _WizardStep.chooseType),
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          label: const Text('متابعة', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
        )),
      ])),
    );
  }

  Widget _serviceInfoCard(IconData icon, String title, String price, String duration, List<String> points) {
    return Container(
      padding: AppTheme.paddingAllMedium,
      decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusMedium, border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: AppTheme.primaryGold, size: 20),
          AppTheme.gapWidthSmall,
          Text(title, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 14)),
          const Spacer(),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppTheme.primaryGold, borderRadius: AppTheme.radiusXL),
            child: Text(price, style: const TextStyle(color: AppTheme.deepBlack, fontWeight: FontWeight.bold, fontSize: 11))),
        ]),
        const SizedBox(height: 4),
        Text('⏱️ $duration', style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)),
        const SizedBox(height: 8),
        ...points.map((p) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('• ', style: TextStyle(color: AppTheme.primaryGold, fontSize: 12)),
          Expanded(child: Text(p, style: const TextStyle(color: AppTheme.textGrey, fontSize: 11, height: 1.4))),
        ]))),
      ]),
    );
  }

  // ─── اختيار النوع ───
  Widget _buildChooseType() {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: const Text('اختر نوع الاستشارة', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold), onPressed: () => setState(() => _step = _WizardStep.explanation))),
      body: Padding(padding: AppTheme.paddingAllLarge, child: Column(children: [
        AppTheme.gapHeightXL,
        _typeCard(Icons.phone_in_talk, 'استشارة هاتفية', '500 ل.س — 15 دقيقة', 'استشارة سريعة عبر المحادثة', 0),
        AppTheme.gapHeightLarge,
        _typeCard(Icons.business, 'جلسة حضورية', '2,000 ل.س — ساعة كاملة', 'اجتماع في مكتب المحامي', 1),
      ])),
    );
  }

  Widget _typeCard(IconData icon, String title, String subtitle, String desc, int serviceType) {
    return GestureDetector(
      onTap: () {
        _selectedService = serviceType;
        if (serviceType == 0) {
          // هاتفية: فحص محادثات سابقة
          setState(() => _step = _WizardStep.previousChats);
        } else {
          // حضورية: مباشرة للفورم
          setState(() => _step = _WizardStep.form);
        }
      },
      child: Container(
        width: double.infinity, padding: AppTheme.paddingAllLarge,
        decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusLarge, border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3))),
        child: Row(children: [
          CircleAvatar(radius: 28, backgroundColor: AppTheme.primaryGold.withOpacity(0.2), child: Icon(icon, color: AppTheme.primaryGold, size: 28)),
          AppTheme.gapWidthMedium,
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: AppTheme.primaryGold, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(desc, style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)),
          ])),
          const Icon(Icons.arrow_forward_ios, color: AppTheme.primaryGold, size: 16),
        ]),
      ),
    );
  }

  // ─── فحص المحادثات السابقة (للهاتفية) ───
  Widget _buildPreviousChats() {
    final previousChats = _myConsultations.where((c) {
      final startedAt = c['chat_started_at'];
      if (startedAt == null) return false;
      final dt = DateTime.tryParse(startedAt.toString());
      if (dt == null) return false;
      return DateTime.now().difference(dt).inDays < 7;
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: const Text('استشارة هاتفية', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold), onPressed: () => setState(() => _step = _WizardStep.chooseType))),
      body: SingleChildScrollView(padding: AppTheme.paddingAllLarge, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (previousChats.isNotEmpty) ...[
          Text(previousChats.length == 1 ? 'لديك محادثة سابقة' : 'لديك ${previousChats.length} محادثات سابقة',
            style: const TextStyle(color: AppTheme.primaryGold, fontSize: 16, fontWeight: FontWeight.bold)),
          AppTheme.gapHeightSmall,
          const Text('هل تريد متابعة إحدى المحادثات السابقة؟', style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
          AppTheme.gapHeightMedium,
          ...previousChats.map((c) {
            final subject = (c['subject'] ?? '').toString();
            final alias = (c['lawyer_alias'] ?? 'محامي المكتب').toString();
            final id = c['id'].toString();
            final selected = _selectedPreviousChatId == id;
            return GestureDetector(
              onTap: () => setState(() => _selectedPreviousChatId = selected ? null : id),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8), padding: AppTheme.paddingAllMedium,
                decoration: BoxDecoration(
                  color: selected ? AppTheme.primaryGold.withOpacity(0.12) : AppTheme.surfaceBlack,
                  borderRadius: AppTheme.radiusMedium,
                  border: Border.all(color: selected ? AppTheme.primaryGold : Colors.white12)),
                child: Row(children: [
                  Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? AppTheme.primaryGold : AppTheme.textGrey),
                  AppTheme.gapWidthSmall,
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text('⚖️ $alias', style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)),
                  ])),
                ]),
              ),
            );
          }),
          AppTheme.gapHeightLarge,
          if (_selectedPreviousChatId != null)
            SizedBox(width: double.infinity, height: 48, child: ElevatedButton.icon(
              onPressed: () => setState(() => _step = _WizardStep.payment),
              icon: const Icon(Icons.chat, color: Colors.black),
              label: const Text('متابعة المحادثة — دفع 500 ل.س', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
            )),
          AppTheme.gapHeightMedium,
        ],
        // زر استشارة جديدة
        SizedBox(width: double.infinity, height: 48, child: OutlinedButton.icon(
          onPressed: () { _selectedPreviousChatId = null; setState(() => _step = _WizardStep.form); },
          icon: const Icon(Icons.add, color: AppTheme.primaryGold),
          label: Text(previousChats.isNotEmpty ? 'لا — أريد استشارة جديدة' : 'بدء استشارة جديدة',
            style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.primaryGold)),
        )),
      ])),
    );
  }

  // ─── فورم الاستشارة الجديدة ───
  Widget _buildForm() {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: Text(_selectedService == 0 ? 'استشارة هاتفية جديدة' : 'جلسة حضورية جديدة',
          style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold),
          onPressed: () => setState(() => _step = _selectedService == 0 ? _WizardStep.previousChats : _WizardStep.chooseType))),
      body: SingleChildScrollView(padding: AppTheme.paddingAllLarge, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // موضوع الاستشارة
        const Text('موضوع الاستشارة:', style: TextStyle(color: AppTheme.primaryGold, fontSize: 15, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightSmall,
        TextField(controller: _subjectCtrl, maxLines: 4, maxLength: 500, style: const TextStyle(color: AppTheme.textWhite),
          decoration: const InputDecoration(hintText: 'اشرح مشكلتك القانونية باختصار...', filled: true, fillColor: AppTheme.surfaceBlack, border: OutlineInputBorder())),
        AppTheme.gapHeightLarge,

        // إرفاق المستندات
        const Text('إرفاق المستندات (اختياري — حتى 5 صور):', style: TextStyle(color: AppTheme.primaryGold, fontSize: 15, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightSmall,
        GestureDetector(onTap: _pickAttachments, child: Container(width: double.infinity, padding: AppTheme.paddingAllMedium,
          decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusMedium, border: Border.all(color: Colors.white12)),
          child: Row(children: [const Icon(Icons.add_photo_alternate_outlined, color: AppTheme.primaryGold), AppTheme.gapWidthSmall,
            Text('إضافة صور (${_attachments.length}/5)', style: const TextStyle(color: AppTheme.textGrey))]))),
        if (_attachments.isNotEmpty) ...[
          AppTheme.gapHeightSmall,
          Wrap(spacing: 8, runSpacing: 8, children: _attachments.asMap().entries.map((e) => Stack(children: [
            ClipRRect(borderRadius: AppTheme.radiusSmall, child: kIsWeb
                ? Image.network(e.value.path, width: 70, height: 70, fit: BoxFit.cover)
                : Image.file(File(e.value.path), width: 70, height: 70, fit: BoxFit.cover)),
            Positioned(top: -5, right: -5, child: GestureDetector(onTap: () => _removeAttachment(e.key),
              child: const CircleAvatar(radius: 10, backgroundColor: AppTheme.errorRed, child: Icon(Icons.close, size: 12, color: Colors.white)))),
          ])).toList()),
        ],
        AppTheme.gapHeightLarge,

        // تنويه الوقت المتأخر
        if (_isLateNight) ...[
          Container(width: double.infinity, padding: AppTheme.paddingAllMedium,
            decoration: BoxDecoration(color: AppTheme.warningOrange.withOpacity(0.1), borderRadius: AppTheme.radiusSmall, border: Border.all(color: AppTheme.warningOrange.withOpacity(0.4))),
            child: const Row(children: [Icon(Icons.nightlight_round, color: AppTheme.warningOrange, size: 18), AppTheme.gapWidthSmall,
              Expanded(child: Text('الوقت متأخر — قد يتأخر الرد لبعد التاسعة صباحاً', style: TextStyle(color: AppTheme.warningOrange, fontSize: 12)))])),
          AppTheme.gapHeightMedium,
        ],

        // زر المتابعة للدفع
        SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
          onPressed: () {
            if (_subjectCtrl.text.trim().length < 10) { _snack('يرجى كتابة وصف أطول (10 أحرف على الأقل)'); return; }
            setState(() => _step = _WizardStep.payment);
          },
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          label: const Text('متابعة للدفع', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
        )),
      ])),
    );
  }

  // ─── شاشة الدفع ───
  Widget _buildPayment() {
    final config = context.watch<ConfigProvider>().config;
    final channels = config?.enabledPayChannels ?? [];
    final price = _selectedService == 0 ? 500 : 2000;
    final isRenewal = _selectedPreviousChatId != null;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: Text(isRenewal ? 'تجديد المحادثة' : 'الدفع', style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold),
          onPressed: () => setState(() => _step = isRenewal ? _WizardStep.previousChats : _WizardStep.form))),
      body: SingleChildScrollView(padding: AppTheme.paddingAllLarge, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ملخص
        Container(width: double.infinity, padding: AppTheme.paddingAllMedium,
          decoration: BoxDecoration(color: AppTheme.primaryGold.withOpacity(0.1), borderRadius: AppTheme.radiusMedium, border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3))),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(isRenewal ? 'تجديد 15 دقيقة' : (_selectedService == 0 ? 'استشارة هاتفية' : 'جلسة حضورية'),
                style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold)),
              Text('$price ل.س', style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: 18)),
            ]),
            if (isRenewal) ...[const SizedBox(height: 4),
              const Text('تجديد محادثة سابقة مع نفس المحامي', style: TextStyle(color: AppTheme.textGrey, fontSize: 11))],
          ])),
        AppTheme.gapHeightLarge,

        // قنوات الدفع
        const Text('قناة الدفع:', style: TextStyle(color: AppTheme.textWhite, fontSize: 13, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightSmall,
        ...channels.map((e) {
          final selected = _paymentChannel == e.key;
          final name = (e.value['name'] ?? e.key).toString();
          final icon = (e.value['icon'] ?? '💳').toString();
          return GestureDetector(
            onTap: () => setState(() => _paymentChannel = e.key),
            child: Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: selected ? AppTheme.primaryGold.withOpacity(0.15) : AppTheme.surfaceBlack, borderRadius: AppTheme.radiusSmall,
                border: Border.all(color: selected ? AppTheme.primaryGold : Colors.white12)),
              child: Row(children: [Text(icon, style: const TextStyle(fontSize: 16)), AppTheme.gapWidthSmall,
                Expanded(child: Text(name, style: TextStyle(color: selected ? AppTheme.primaryGold : AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 13))),
                Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, color: selected ? AppTheme.primaryGold : AppTheme.textGrey, size: 18)])),
          );
        }),
        AppTheme.gapHeightMedium,

        // حقل رقم المُحوِّل
        if (_needsSenderPhone) ...[
          const Text('رقم هاتفك (الذي تم التحويل منه):', style: TextStyle(color: AppTheme.textWhite, fontSize: 13)),
          AppTheme.gapHeightSmall,
          TextField(controller: _senderPhoneCtrl, keyboardType: TextInputType.phone, style: const TextStyle(color: AppTheme.textWhite),
            decoration: const InputDecoration(hintText: '09xxxxxxxx', prefixIcon: Icon(Icons.phone, color: AppTheme.primaryGold),
              filled: true, fillColor: AppTheme.surfaceBlack, border: OutlineInputBorder())),
          AppTheme.gapHeightMedium,
        ],

        // رقم العملية
        const Text('رقم العملية / المرجع:', style: TextStyle(color: AppTheme.textWhite, fontSize: 13)),
        AppTheme.gapHeightSmall,
        TextField(controller: _refCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AppTheme.textWhite),
          decoration: const InputDecoration(hintText: 'رقم الإيصال أو التحويل', prefixIcon: Icon(Icons.tag, color: AppTheme.primaryGold),
            filled: true, fillColor: AppTheme.surfaceBlack, border: OutlineInputBorder())),
        AppTheme.gapHeightMedium,

        // إثبات الدفع
        const Text('إثبات الدفع:', style: TextStyle(color: AppTheme.textWhite, fontSize: 13)),
        AppTheme.gapHeightSmall,
        GestureDetector(onTap: _pickProof, child: Container(width: double.infinity, padding: AppTheme.paddingAllMedium,
          decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusSmall,
            border: Border.all(color: _proofImage != null ? AppTheme.successGreen : Colors.white12)),
          child: Row(children: [
            Icon(_proofImage == null ? Icons.upload_file : Icons.check_circle, color: _proofImage == null ? AppTheme.textGrey : AppTheme.successGreen),
            AppTheme.gapWidthSmall,
            Text(_proofImage == null ? 'اضغط لاختيار صورة إثبات الدفع' : 'تم اختيار الصورة ✓', style: const TextStyle(color: AppTheme.textGrey, fontSize: 13))]))),
        AppTheme.gapHeightLarge,

        // زر الدفع
        SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
          onPressed: _submitting ? null : _pay,
          icon: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.payment, color: Colors.black),
          label: Text(_submitting ? 'جارٍ المعالجة...' : 'ادفع $price ل.س', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
        )),
      ])),
    );
  }

  // ─── شاشة النجاح ───
  Widget _buildSuccess() {
    final isRenewal = _selectedPreviousChatId != null;
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      body: Center(child: SingleChildScrollView(padding: AppTheme.paddingAllLarge, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.check_circle, color: AppTheme.successGreen, size: 64),
        AppTheme.gapHeightLarge,
        const Text('✅ تم إرسال الدفعة بنجاح', style: TextStyle(color: AppTheme.textWhite, fontSize: 18, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightMedium,
        Text(isRenewal ? 'بانتظار تأكيد الإدارة لتجديد المحادثة' : 'بانتظار تأكيد الإدارة — سيتم إشعارك عند الموافقة',
          style: const TextStyle(color: AppTheme.textGrey, fontSize: 14), textAlign: TextAlign.center),
        AppTheme.gapHeightSmall,
        const Text('بعدها يمكنك إرسال طلب الاستشارة للمحامي', style: const TextStyle(color: AppTheme.textGrey, fontSize: 12), textAlign: TextAlign.center),
        AppTheme.gapHeightXL,
        if (isRenewal)
          SizedBox(width: double.infinity, height: 48, child: ElevatedButton.icon(
            onPressed: () { _renewChat(_selectedPreviousChatId!); },
            icon: const Icon(Icons.chat, color: Colors.black),
            label: const Text('تجديد المحادثة الآن', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
          ))
        else
          SizedBox(width: double.infinity, height: 48, child: ElevatedButton.icon(
            onPressed: _submitting ? null : _submitConsultation,
            icon: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.send, color: Colors.black),
            label: Text(_submitting ? 'جارٍ الإرسال...' : 'إرسال الطلب للمحامي الآن', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
          )),
        AppTheme.gapHeightMedium,
        TextButton(onPressed: () { _resetForm(); Navigator.pop(context); }, child: const Text('العودة للرئيسية', style: TextStyle(color: AppTheme.textGrey))),
      ]))),
    );
  }

  void _snack(String m) { if (!mounted) return; AppTheme.showSnackBar(context, SnackBar(content: Text(m))); }
}

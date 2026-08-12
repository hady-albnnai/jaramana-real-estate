import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_utils.dart';
import '../../core/network/supabase_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/legal_provider.dart';
import '../../services/storage_service.dart';

class LegalConsultationBookingScreen extends StatefulWidget {
  const LegalConsultationBookingScreen({super.key});

  @override
  State<LegalConsultationBookingScreen> createState() => _LegalConsultationBookingScreenState();
}

class _LegalConsultationBookingScreenState extends State<LegalConsultationBookingScreen> {
  int _selectedService = 0;
  final _subjectCtrl = TextEditingController();
  bool _submitting = false;
  List<Map<String, dynamic>> _myConsultations = [];
  bool _loadingConsultations = false;
  bool _showExplanation = true; // شاشة الشرح

  // إرفاق المستندات (حتى 5 صور)
  final List<XFile> _attachments = [];
  final _storage = StorageService();
  bool _uploadingAttachments = false;

  final List<Map<String, dynamic>> _services = [
    {
      'title': 'استشارة هاتفية صوتية',
      'price': 500,
      'duration': '15 دقيقة',
      'icon': Icons.phone_in_talk,
      'desc': 'اتصال صوتي مباشر مع محامي المكتب للإجابة عن استفساراتك القانونية البسيطة وتوجيهك للحل المناسب.',
    },
    {
      'title': 'جلسة استشارة مكتبية حضورية',
      'price': 2000,
      'duration': 'لغاية ساعة واحدة',
      'icon': Icons.business,
      'desc': 'اجتماع حضوري وجهاً لوجه في مكتب المستشار القانوني لدراسة الملفات المعقدة وفرز المستندات ومناقشة تفاصيل العقود.',
    },
  ];

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
    super.dispose();
  }

  /// هل الوقت بين 11 ليلاً و 9 صباحاً؟
  bool get _isLateNight {
    final hour = DateTime.now().hour;
    return hour >= 23 || hour < 9;
  }

  Future<void> _loadMyConsultations() async {
    setState(() => _loadingConsultations = true);
    try {
      final res = await SupabaseService().invokeFunction(
        'legal-actions',
        body: {'action': 'list_my_consultations', 'user_uid': context.read<AuthProvider>().userModel?.uid ?? ''},
      );
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        setState(() {
          _myConsultations = List<Map<String, dynamic>>.from(data['consultations'] as List? ?? []);
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingConsultations = false);
  }

  Future<void> _pickAttachments() async {
    final remaining = 5 - _attachments.length;
    if (remaining <= 0) {
      _snack('الحد الأقصى 5 صور');
      return;
    }
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 60, maxWidth: 1280);
    if (files.isNotEmpty) {
      setState(() {
        _attachments.addAll(files.take(remaining));
      });
    }
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  /// رفع المستندات إلى consultation_files bucket مع ضغط
  Future<List<String>> _uploadAttachments() async {
    if (_attachments.isEmpty) return [];
    final urls = <String>[];
    setState(() => _uploadingAttachments = true);
    try {
      final uid = context.read<AuthProvider>().userModel?.uid ?? '';
      final supabaseStorage = SupabaseService().storage;
      for (final file in _attachments) {
        final compressed = await _storage.compressImage(File(file.path));
        final bytes = await (compressed ?? File(file.path)).readAsBytes();
        final ext = file.path.split('.').last;
        final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
        await supabaseStorage.from('consultation_files').uploadBinary(
          path, bytes,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: false, contentType: 'image/jpeg'),
        );
        urls.add(path);
      }
    } catch (_) {}
    setState(() => _uploadingAttachments = false);
    return urls;
  }

  Future<void> _submit() async {
    final subject = _subjectCtrl.text.trim();
    if (subject.isEmpty) { _snack('يرجى كتابة موضوع الاستشارة'); return; }
    if (subject.length < 10) { _snack('يرجى كتابة وصف أطول (10 أحرف على الأقل)'); return; }

    setState(() => _submitting = true);

    // رفع المرفقات
    final attachmentPaths = await _uploadAttachments();

    try {
      final res = await SupabaseService().invokeFunction(
        'legal-actions',
        body: {
          'action': 'book_consultation',
          'user_uid': context.read<AuthProvider>().userModel?.uid ?? '',
          'service_type': _selectedService,
          'subject': subject,
          'price': _services[_selectedService]['price'],
          'attachments': attachmentPaths,
        },
      );
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        _snack('✅ تم إرسال طلب الاستشارة بنجاح');
        _subjectCtrl.clear();
        _attachments.clear();
        _loadMyConsultations();
      } else {
        _snack(data?['message']?.toString() ?? data?['error']?.toString() ?? 'فشل إرسال الطلب');
      }
    } catch (e) {
      _snack('حدث خطأ: $e');
    }
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _reactivate(String consultId) async {
    try {
      final res = await SupabaseService().invokeFunction(
        'legal-actions',
        body: {
          'action': 'reactivate_consultation',
          'user_uid': context.read<AuthProvider>().userModel?.uid ?? '',
          'consultation_id': consultId,
        },
      );
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        _snack('✅ تم إعادة تفعيل الطلب — سيُشعَر المحامي مجدداً');
        _loadMyConsultations();
      } else {
        _snack(data?['error']?.toString() ?? 'فشل إعادة التفعيل');
      }
    } catch (e) {
      _snack('خطأ: $e');
    }
  }

  void _openChat(String consultId) {
    context.push('/legal/chat/$consultId');
  }

  @override
  Widget build(BuildContext context) {
    if (_showExplanation) return _buildExplanationScreen();

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground,
        elevation: 0,
        title: const Text('الاستشارة القانونية', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: AppTheme.paddingAllLarge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── اختيار الخدمة ──
            const Text('اختر نوع الاستشارة:', style: TextStyle(color: AppTheme.primaryGold, fontSize: 15, fontWeight: FontWeight.bold)),
            AppTheme.gapHeightSmall,
            ...List.generate(_services.length, (i) {
              final s = _services[i];
              final selected = _selectedService == i;
              return GestureDetector(
                onTap: () => setState(() => _selectedService = i),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: AppTheme.paddingAllMedium,
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.primaryGold.withOpacity(0.12) : AppTheme.surfaceBlack,
                    borderRadius: AppTheme.radiusMedium,
                    border: Border.all(color: selected ? AppTheme.primaryGold : Colors.white12, width: selected ? 1.5 : 1),
                  ),
                  child: Row(children: [
                    Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? AppTheme.primaryGold : AppTheme.textGrey, size: 20),
                    AppTheme.gapWidthSmall,
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(s['icon'] as IconData, color: AppTheme.primaryGold, size: 18),
                          AppTheme.gapWidthSmall,
                          Expanded(child: Text(s['title'] as String, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 14))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: AppTheme.primaryGold, borderRadius: AppTheme.radiusXL),
                            child: Text('${s['price']} ل.س', style: const TextStyle(color: AppTheme.deepBlack, fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text('⏱️ ${s['duration']}  —  ${s['desc']}', style: const TextStyle(color: AppTheme.textGrey, fontSize: 11, height: 1.4)),
                      ]),
                    ),
                  ]),
                ),
              );
            }),
            AppTheme.gapHeightLarge,

            // ── موضوع الاستشارة ──
            const Text('موضوع الاستشارة:', style: TextStyle(color: AppTheme.primaryGold, fontSize: 15, fontWeight: FontWeight.bold)),
            AppTheme.gapHeightSmall,
            TextField(
              controller: _subjectCtrl,
              maxLines: 4,
              maxLength: 500,
              style: const TextStyle(color: AppTheme.textWhite),
              decoration: const InputDecoration(
                hintText: 'اشرح مشكلتك القانونية باختصار...\nمثال: لدي نزاع مع المستأجر على قيمة الإيجار المتأخر...',
                filled: true, fillColor: AppTheme.surfaceBlack,
                border: OutlineInputBorder(),
              ),
            ),
            AppTheme.gapHeightLarge,

            // ── إرفاق المستندات ──
            const Text('إرفاق المستندات (اختياري — حتى 5 صور):', style: TextStyle(color: AppTheme.primaryGold, fontSize: 15, fontWeight: FontWeight.bold)),
            AppTheme.gapHeightSmall,
            GestureDetector(
              onTap: _pickAttachments,
              child: Container(
                width: double.infinity, padding: AppTheme.paddingAllMedium,
                decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusMedium, border: Border.all(color: Colors.white12)),
                child: Row(children: [
                  const Icon(Icons.add_photo_alternate_outlined, color: AppTheme.primaryGold),
                  AppTheme.gapWidthSmall,
                  Text('إضافة صور (${_attachments.length}/5)', style: const TextStyle(color: AppTheme.textGrey)),
                ]),
              ),
            ),
            if (_attachments.isNotEmpty) ...[
              AppTheme.gapHeightSmall,
              Wrap(spacing: 8, runSpacing: 8, children: _attachments.asMap().entries.map((e) => Stack(children: [
                ClipRRect(borderRadius: AppTheme.radiusSmall, child: kIsWeb
                    ? Image.network(e.value.path, width: 70, height: 70, fit: BoxFit.cover)
                    : Image.file(File(e.value.path), width: 70, height: 70, fit: BoxFit.cover)),
                Positioned(top: -5, right: -5, child: GestureDetector(onTap: () => _removeAttachment(e.key), child: const CircleAvatar(radius: 10, backgroundColor: AppTheme.errorRed, child: Icon(Icons.close, size: 12, color: Colors.white)))),
              ])).toList()),
            ],
            AppTheme.gapHeightLarge,

            // ── تنويه الوقت المتأخر ──
            if (_isLateNight) ...[
              Container(
                width: double.infinity, padding: AppTheme.paddingAllMedium,
                decoration: BoxDecoration(color: AppTheme.warningOrange.withOpacity(0.1), borderRadius: AppTheme.radiusSmall, border: Border.all(color: AppTheme.warningOrange.withOpacity(0.4))),
                child: const Row(children: [
                  Icon(Icons.nightlight_round, color: AppTheme.warningOrange, size: 18),
                  AppTheme.gapWidthSmall,
                  Expanded(child: Text('الوقت متأخر حالياً — قد يتأخر الرد لبعد التاسعة صباحاً', style: TextStyle(color: AppTheme.warningOrange, fontSize: 12))),
                ]),
              ),
              AppTheme.gapHeightMedium,
            ],

            // ── زر الإرسال ──
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                onPressed: _submitting || _uploadingAttachments ? null : _submit,
                icon: _submitting || _uploadingAttachments
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.send, color: Colors.black),
                label: Text(
                  _uploadingAttachments ? 'جارٍ رفع المستندات...' : _submitting ? 'جارٍ الإرسال...' : 'إرسال الطلب ودفع ${_services[_selectedService]['price']} ل.س',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
              ),
            ),
            AppTheme.gapHeightXXL,

            // ── استشاراتي السابقة ──
            const Text('استشاراتي:', style: TextStyle(color: AppTheme.primaryGold, fontSize: 15, fontWeight: FontWeight.bold)),
            AppTheme.gapHeightSmall,
            if (_loadingConsultations)
              const Center(child: CircularProgressIndicator(color: AppTheme.primaryGold))
            else if (_myConsultations.isEmpty)
              const Text('لا توجد استشارات سابقة', style: TextStyle(color: AppTheme.textGrey))
            else
              ..._myConsultations.map((c) => _consultationCard(c)),
          ],
        ),
      ),
    );
  }

  /// شاشة شرح الآلية
  Widget _buildExplanationScreen() {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: const Text('الاستشارة القانونية', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: AppTheme.paddingAllLarge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: Icon(Icons.gavel, color: AppTheme.primaryGold, size: 48)),
            AppTheme.gapHeightLarge,
            const Center(child: Text('⚖️ كيف تعمل الاستشارة القانونية؟', style: TextStyle(color: AppTheme.primaryGold, fontSize: 20, fontWeight: FontWeight.bold))),
            AppTheme.gapHeightXL,

            _stepRow('1', 'اشرح مشكلتك', 'اكتب موضوع الاستشارة باختصار وأرفق أي مستندات ذات صلة'),
            _stepRow('2', 'ادفع المبلغ', '500 ل.س للاستشارة الهاتفية — 2,000 ل.س للجلسة الحضورية'),
            _stepRow('3', 'انتظر الرد', 'سيتم الرد على طلبك خلال ساعة من تقديم الطلب'),
            _stepRow('4', 'المحامي يدرس', 'يدرس المحامي مشكلتك ومستنداتك قبل فتح المحادثة'),
            _stepRow('5', 'تفتح المحادثة', 'بعد القبول تبدأ محادثة مباشرة — مدة الاستشارة الهاتفية 15 دقيقة'),
            _stepRow('6', 'التقييم', 'بعد انتهاء الاستشارة قيّم تجربةك'),
            AppTheme.gapHeightXL,

            // تنويهات
            Container(
              width: double.infinity, padding: AppTheme.paddingAllMedium,
              decoration: BoxDecoration(color: AppTheme.warningOrange.withOpacity(0.1), borderRadius: AppTheme.radiusSmall, border: Border.all(color: AppTheme.warningOrange.withOpacity(0.4))),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('⚠️ تنبيهات مهمة:', style: TextStyle(color: AppTheme.warningOrange, fontWeight: FontWeight.bold, fontSize: 13)),
                SizedBox(height: 6),
                Text('• هذه الخدمة للاستشارات ذات الطابع البسيط', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.6)),
                Text('• إذا كانت مشكلتك معقدة يُفضل حجز موعد لاستشارة حضورية', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.6)),
                Text('• في حال عدم الرد خلال ساعة يمكنك إعادة تفعيل الطلب بدون دفع مجدداً', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.6)),
                Text('• مدة الاستشارة الهاتفية قابلة للتمديد 5 دقائق إضافية من المحامي', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.6)),
              ]),
            ),
            AppTheme.gapHeightMedium,

            if (_isLateNight) ...[
              Container(
                width: double.infinity, padding: AppTheme.paddingAllMedium,
                decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.15), borderRadius: AppTheme.radiusSmall, border: Border.all(color: Colors.indigo.withOpacity(0.4))),
                child: const Row(children: [
                  Icon(Icons.nightlight_round, color: Colors.indigo, size: 18),
                  AppTheme.gapWidthSmall,
                  Expanded(child: Text('الوقت متأخر حالياً — قد يتأخر الرد لبعد التاسعة صباحاً', style: TextStyle(color: Colors.indigoAccent, fontSize: 12))),
                ]),
              ),
              AppTheme.gapHeightMedium,
            ],

            AppTheme.gapHeightLarge,
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _showExplanation = false),
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                label: const Text('متابعة', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepRow(String num, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(radius: 14, backgroundColor: AppTheme.primaryGold, child: Text(num, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13))),
        AppTheme.gapWidthMedium,
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 2),
          Text(desc, style: const TextStyle(color: AppTheme.textGrey, fontSize: 12, height: 1.4)),
        ])),
      ]),
    );
  }

  Widget _consultationCard(Map<String, dynamic> c) {
    final status = c['status'] ?? 0;
    final (label, color) = _statusInfo(status);
    final serviceNames = ['استشارة هاتفية', 'جلسة مكتبية'];
    final sName = serviceNames[(c['service_type'] ?? 0) as int];
    final price = (c['price'] ?? 0) as num;
    final subject = (c['subject'] ?? '').toString();
    final tsCrt = c['ts_crt']?.toString().substring(0, 10) ?? '';
    final lawyerAlias = (c['lawyer_alias'] ?? '').toString();
    final chatStarted = c['chat_started_at'] != null;
    final chatExpired = c['chat_started_at'] != null && _isChatExpired(c);

    // التحقق: هل مرّت ساعة على الطلب المعلق؟
    bool canReactivate = false;
    if (status == 0 && c['ts_crt'] != null) {
      final createdAt = DateTime.tryParse(c['ts_crt'].toString());
      if (createdAt != null) {
        final hoursPassed = DateTime.now().difference(createdAt).inMinutes / 60.0;
        canReactivate = hoursPassed >= 1;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: AppTheme.paddingAllMedium,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(sName, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: AppTheme.radiusSmall), child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 4),
        Text(subject, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textGrey, fontSize: 12)),
        const SizedBox(height: 4),
        Row(children: [
          Text('$tsCrt', style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)),
          const Spacer(),
          Text('${price.toStringAsFixed(0)} ل.س', style: const TextStyle(color: AppTheme.primaryGold, fontSize: 11, fontWeight: FontWeight.bold)),
        ]),
        if (lawyerAlias.isNotEmpty && status >= 1) ...[
          const SizedBox(height: 4),
          Text('⚖️ $lawyerAlias', style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)),
        ],
        // أزرار الإجراءات
        if (chatStarted && !chatExpired) ...[
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: () => _openChat(c['id'].toString()),
            icon: const Icon(Icons.chat, size: 16),
            label: const Text('فتح المحادثة'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successGreen, foregroundColor: Colors.white),
          )),
        ],
        if (chatExpired) ...[
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: () => _openChat(c['id'].toString()),
            icon: const Icon(Icons.visibility, size: 16),
            label: const Text('عرض المحادثة (منتهية)', style: TextStyle(color: AppTheme.textGrey)),
          )),
        ],
        if (canReactivate) ...[
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: () => _reactivate(c['id'].toString()),
            icon: const Icon(Icons.refresh, size: 16, color: AppTheme.warningOrange),
            label: const Text('إعادة تفعيل الطلب (لم يتم الرد)', style: TextStyle(color: AppTheme.warningOrange, fontSize: 12)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.warningOrange)),
          )),
        ],
      ]),
    );
  }

  bool _isChatExpired(Map<String, dynamic> c) {
    final startedAt = c['chat_started_at'];
    if (startedAt == null) return false;
    final dt = DateTime.tryParse(startedAt.toString());
    if (dt == null) return true;
    final duration = (c['chat_duration_minutes'] ?? 15) as int;
    return DateTime.now().isAfter(dt.add(Duration(minutes: duration)));
  }

  (String, Color) _statusInfo(int sts) {
    switch (sts) {
      case 0: return ('بانتظار القبول', AppTheme.warningOrange);
      case 1: return ('مؤكدة', AppTheme.successGreen);
      case 2: return ('منتهية', AppTheme.textGrey);
      case 3: return ('ملغية', AppTheme.errorRed);
      case 4: return ('قيد الدراسة', AppTheme.infoBlue);
      default: return ('—', AppTheme.textGrey);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    AppTheme.showSnackBar(context, SnackBar(content: Text(m)));
  }
}

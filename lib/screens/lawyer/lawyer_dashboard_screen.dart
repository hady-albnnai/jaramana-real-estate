import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/supabase_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/legal_provider.dart';
import '../../models/expediting_task_model.dart';
import '../../widgets/e2e.dart';

class LawyerDashboardScreen extends StatefulWidget {
  const LawyerDashboardScreen({super.key});

  @override
  State<LawyerDashboardScreen> createState() => _LawyerDashboardScreenState();
}

class _LawyerDashboardScreenState extends State<LawyerDashboardScreen>
    with SingleTickerProviderStateMixin {
  final _whatsappCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  static const String _customDocsStorageKey = 'lawyer_expediting_custom_docs_v1';

  final _taskPropertyCtrl = TextEditingController();
  final _taskZoneCtrl = TextEditingController();
  final _taskNotesCtrl = TextEditingController();
  final _permanentDocTitleCtrl = TextEditingController();
  final _oneTimeDocTitleCtrl = TextEditingController();
  final List<Map<String, dynamic>> _selectedChecklist = [];
  final Map<int, List<Map<String, String>>> _customDocTemplates = {0: [], 1: []};

  bool _savingProfile = false;
  bool _creatingTask = false;
  bool _isAvailable = true; // 🟢 حالة توفر المحامي (is_active) — أُضيفت 2026-08-14
  bool _checking = true; // يمنع وميض شاشة الإعداد
  String? _selectedExpediterUid;
  int _selectedItemType = 0;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this); // +تبويب «أوقاتي» 2026-08-14
    _loadCustomDocumentTemplates();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final user = context.read<AuthProvider>().userModel;
    if (user == null) return;
    final legal = context.read<LegalProvider>();
    // 🔴 إلزامي قبل أي نداء: الإيدج يتحقق من الجلسة عبر user_uid بالجسم،
    // وبدونه ترتد كل الدوال USER_UID_REQUIRED وتبدو الشاشة «فارغة».
    legal.setActor(user.uid);
    await legal.checkLawyerProfile(user.uid);
    // 🟢 قراءة حالة التوفر الفعلية من ملف المحامي
    _isAvailable = (legal.lawyerProfile?['is_active'] ?? true) == true;
    if (legal.profileSetupComplete) {
      legal.fetchAvailableExpediters();
      legal.fetchLawyerAppointments();
      legal.fetchLawyerTasks();
      legal.fetchLawyerConsultations();
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  void dispose() {
    _whatsappCtrl.dispose(); _addressCtrl.dispose();
    _taskPropertyCtrl.dispose(); _taskZoneCtrl.dispose(); _taskNotesCtrl.dispose();
    _permanentDocTitleCtrl.dispose();
    _oneTimeDocTitleCtrl.dispose();
    _searchCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  void _snack(String m, {Color? bg}) {
    if (!mounted) return;
    AppTheme.showSnackBar(context,
      SnackBar(content: Text(m), backgroundColor: bg ?? AppTheme.primaryGold));
  }

  Future<void> _openAccountDetails() async {
    if (!mounted) return;
    context.push('/user/account-info');
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('تسجيل الخروج', style: TextStyle(color: AppTheme.textWhite)),
        content: const Text('هل تريد تسجيل الخروج من حساب المحامي؟', style: TextStyle(color: AppTheme.textGrey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: AppTheme.textGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تسجيل خروج', style: TextStyle(color: AppTheme.errorRed)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    context.go('/user/profile');
  }

  // ──────── حوار الملف الشخصي ────────
  void _showProfileDialog() {
    final user = context.read<AuthProvider>().userModel;
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Row(children: [
          Icon(Icons.person, color: AppTheme.primaryGold, size: 22),
          AppTheme.gapWidthSmall,
          Text('الملف الشخصي', style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeTitle)),
        ]),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user?.nm ?? '', style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeSubtitle)),
            Text(user?.ph ?? '', style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeMedium)),
            if (user?.usr != null && user!.usr!.isNotEmpty)
              Text('@${user.usr}', style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeBody)),
            AppTheme.gapHeightXL, const Divider(color: AppTheme.textGrey),
            const Text('تغيير كلمة المرور', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: 15)),
            AppTheme.gapHeightMedium,
            TextField(controller: oldCtrl, style: const TextStyle(color: AppTheme.textWhite),
              decoration: const InputDecoration(labelText: 'كلمة المرور الحالية', prefixIcon: Icon(Icons.lock_outline, color: AppTheme.primaryGold)),
              obscureText: true),
            AppTheme.gapHeightSmall,
            TextField(controller: newCtrl, style: const TextStyle(color: AppTheme.textWhite),
              decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة', prefixIcon: Icon(Icons.lock, color: AppTheme.primaryGold)),
              obscureText: true),
            AppTheme.gapHeightSmall,
            TextField(controller: confCtrl, style: const TextStyle(color: AppTheme.textWhite),
              decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور', prefixIcon: Icon(Icons.lock, color: AppTheme.primaryGold)),
              obscureText: true),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء', style: TextStyle(color: AppTheme.textGrey))),
          ElevatedButton(onPressed: () async {
            if (newCtrl.text != confCtrl.text) { _snack('كلمتا المرور غير متطابقتين', bg: AppTheme.errorRed); return; }
            if (newCtrl.text.length < 8) { _snack('كلمة المرور أقل من 8 أحرف', bg: AppTheme.errorRed); return; }
            try {
              final res = await SupabaseService().invokeFunction('user-account', body: {
                'action': 'change_password',
                'user_uid': user?.uid ?? '',
                'old_password': oldCtrl.text,
                'new_password': newCtrl.text,
              });
              final d = res.data as Map?;
              if (d?['success'] == true) { Navigator.pop(ctx); _snack('✅ تم تغيير كلمة المرور'); }
              else { _snack(d?['error']?.toString() ?? 'فشل', bg: AppTheme.errorRed); }
            } catch (e) { _snack('خطأ: $e', bg: AppTheme.errorRed); }
          }, child: const Text('حفظ')),
        ],
      ),
    );
  }

  // ──────── حفظ الإعداد الأولي ────────
  Future<void> _saveProfile() async {
    final user = context.read<AuthProvider>().userModel;
    if (user == null) return;
    if (_whatsappCtrl.text.trim().isEmpty) { _snack('يرجى إدخال رقم الواتساب', bg: AppTheme.errorRed); return; }
    setState(() => _savingProfile = true);
    final ok = await context.read<LegalProvider>().upsertLawyerProfile(
      targetUid: user.uid, whatsappPhone: _whatsappCtrl.text.trim(), officeAddress: _addressCtrl.text.trim());
    if (!mounted) return; setState(() => _savingProfile = false);
    if (ok) {
      _snack('✅ تم حفظ البيانات');
      final legal = context.read<LegalProvider>();
      legal.setActor(user.uid); // إلزامي قبل الجلب (وإلا USER_UID_REQUIRED)
      legal.fetchAvailableExpediters();
      legal.fetchLawyerAppointments();
      legal.fetchLawyerTasks();
      legal.fetchLawyerConsultations(); // كانت مفقودة هنا
    } else { _snack('فشل الحفظ', bg: AppTheme.errorRed); }
  }

  List<Map<String, String>> _baseDocumentTemplatesFor(int itemType) {
    if (itemType == 0) {
      return const [
        {'key': 'extract', 'title': 'إخراج قيد عقاري حديث'},
        {'key': 'area_stmt', 'title': 'بيان مساحة عقاري'},
        {'key': 'fin_clearance', 'title': 'براءة ذمة مالية وبلدية'},
        {'key': 'fin_record', 'title': 'قيد مالي للعقار'},
        {'key': 'sales_tax', 'title': 'ضريبة البيوع العقارية'},
        {'key': 'poa_chain', 'title': 'تسلسل وكالات كاتب بالعدل'},
      ];
    }
    return const [
      {'key': 'traffic_info', 'title': 'كشف اطلاع مروري'},
      {'key': 'traffic_clearance', 'title': 'براءة ذمة مرورية ومخالفات'},
      {'key': 'tech_inspect', 'title': 'كشف فني ومطابقة الأرقام'},
      {'key': 'title_deed', 'title': 'سند الملكية / ميكانيك المركبة'},
    ];
  }

  List<Map<String, String>> _documentTemplatesFor(int itemType) {
    return [
      ..._baseDocumentTemplatesFor(itemType),
      ...(_customDocTemplates[itemType] ?? const <Map<String, String>>[]),
    ];
  }

  bool _isBaseDocument(String key) {
    return _baseDocumentTemplatesFor(_selectedItemType).any((doc) => doc['key'] == key);
  }

  Future<void> _loadCustomDocumentTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_customDocsStorageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map) {
        final loaded = <int, List<Map<String, String>>>{0: [], 1: []};
        for (final type in [0, 1]) {
          final list = parsed[type.toString()];
          if (list is List) {
            loaded[type] = list
                .whereType<Map>()
                .map((item) => {
                      'key': item['key']?.toString() ?? '',
                      'title': item['title']?.toString() ?? '',
                    })
                .where((item) => item['key']!.isNotEmpty && item['title']!.isNotEmpty)
                .toList();
          }
        }
        if (mounted) {
          setState(() {
            _customDocTemplates
              ..clear()
              ..addAll(loaded);
          });
        }
      }
    } catch (_) {
      // تجاهل كاش تالف.
    }
  }

  Future<void> _saveCustomDocumentTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final serializable = {
      '0': _customDocTemplates[0] ?? [],
      '1': _customDocTemplates[1] ?? [],
    };
    await prefs.setString(_customDocsStorageKey, jsonEncode(serializable));
  }

  Map<String, dynamic> _newChecklistItem(String key, String title) {
    return {
      'key': key,
      'title': title,
      'status': 0,
      'required_copies': 1,
      'lawyer_instructions': '',
    };
  }

  void _toggleDocumentForTask(Map<String, String> doc, bool selected) {
    final key = doc['key']!;
    final title = doc['title']!;
    setState(() {
      if (selected) {
        if (!_selectedChecklist.any((item) => item['key'] == key)) {
          _selectedChecklist.add(_newChecklistItem(key, title));
        }
      } else {
        _selectedChecklist.removeWhere((item) => item['key'] == key);
      }
    });
  }

  void _changeItemType(int type) {
    if (_selectedItemType == type) return;
    setState(() {
      _selectedItemType = type;
      _selectedChecklist.clear();
      _permanentDocTitleCtrl.clear();
      _oneTimeDocTitleCtrl.clear();
      _taskPropertyCtrl.clear();
      _taskZoneCtrl.clear();
    });
  }

  Future<void> _addPermanentDocumentTemplate() async {
    final title = _permanentDocTitleCtrl.text.trim();
    if (title.length < 2) {
      _snack('اكتب اسم الوثيقة التي تريد إضافتها للقائمة', bg: AppTheme.errorRed);
      return;
    }
    final exists = _documentTemplatesFor(_selectedItemType)
        .any((doc) => doc['title']?.trim() == title);
    if (exists) {
      _snack('هذه الوثيقة موجودة مسبقاً في القائمة', bg: AppTheme.errorRed);
      return;
    }
    final key = 'saved_${_selectedItemType}_${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _customDocTemplates.putIfAbsent(_selectedItemType, () => []).add({'key': key, 'title': title});
      _permanentDocTitleCtrl.clear();
    });
    await _saveCustomDocumentTemplates();
    _snack('تمت إضافة الوثيقة للقائمة الدائمة');
  }

  Future<void> _deletePermanentDocumentTemplate(Map<String, String> doc) async {
    final key = doc['key'] ?? '';
    if (_isBaseDocument(key)) {
      _snack('لا يمكن حذف الوثائق الأساسية، يمكن حذف الوثائق المضافة فقط', bg: AppTheme.errorRed);
      return;
    }
    setState(() {
      _customDocTemplates[_selectedItemType]?.removeWhere((item) => item['key'] == key);
      _selectedChecklist.removeWhere((item) => item['key'] == key);
    });
    await _saveCustomDocumentTemplates();
    _snack('تم حذف الوثيقة من القائمة الدائمة');
  }

  void _addOneTimeDocument() {
    final title = _oneTimeDocTitleCtrl.text.trim();
    if (title.length < 2) {
      _snack('اكتب اسم الوثيقة الحرة المطلوبة لهذه المهمة', bg: AppTheme.errorRed);
      return;
    }
    final key = 'one_time_${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _selectedChecklist.add(_newChecklistItem(key, title));
      _oneTimeDocTitleCtrl.clear();
    });
  }

  void _addAllDefaultDocuments() {
    setState(() {
      for (final doc in _documentTemplatesFor(_selectedItemType)) {
        if (!_selectedChecklist.any((item) => item['key'] == doc['key'])) {
          _selectedChecklist.add(_newChecklistItem(doc['key']!, doc['title']!));
        }
      }
    });
  }

  // ──────── إنشاء مهمة ────────
  Future<void> _createTask() async {
    if (_selectedExpediterUid == null) { _snack('يرجى اختيار معقب', bg: AppTheme.errorRed); return; }
    if (_selectedChecklist.isEmpty) { _snack('يرجى إضافة وثيقة واحدة على الأقل للمعقب', bg: AppTheme.errorRed); return; }
    setState(() => _creatingTask = true);
    final ok = await context.read<LegalProvider>().createExpeditingTask(
      expediterUid: _selectedExpediterUid!, itemType: _selectedItemType,
      targetPropertyNum: _taskPropertyCtrl.text.trim(), targetZone: _taskZoneCtrl.text.trim(),
      notes: _taskNotesCtrl.text.trim(),
      checklist: _selectedChecklist.map((item) => Map<String, dynamic>.from(item)).toList());
    if (!mounted) return; setState(() => _creatingTask = false);
    if (ok) {
      _snack('✅ تم إرسال المهمة');
      _taskPropertyCtrl.clear(); _taskZoneCtrl.clear(); _taskNotesCtrl.clear();
      setState(() {
        _selectedExpediterUid = null;
        _selectedChecklist.clear();
      });
    } else { _snack('فشل إنشاء المهمة', bg: AppTheme.errorRed); }
  }

  @override
  Widget build(BuildContext context) {
    final legal = context.watch<LegalProvider>();
    if (_checking) return const Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      body: Center(child: CircularProgressIndicator(color: AppTheme.primaryGold)),
    );
    if (!legal.profileSetupComplete) return _buildSetupScreen();
    // 🗓️ بوابة إلزامية (قرار المالك 2026-08-14): لا يستطيع المحامي استخدام
    // شاشته قبل ضبط أوقاته — وإلا وصلته جلسات حضورية بلا مواعيد ممكنة.
    // قابلة للتعديل لاحقاً من تبويب «أوقاتي».
    if (!legal.hasAvailability) return _buildAvailabilityGate(legal);

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const E2E(id: 'e2e_screen_lawyer_dashboard', child: Text('⚖️ لوحة المحامي')), backgroundColor: AppTheme.scaffoldBackground,
        actions: [
          // 🟢 مفتاح التوفر (2026-08-14) — أول أسس الإسناد:
          // متاح ← الأقل انشغالاً ← الدور. كان is_active بلا كاتب إطلاقاً.
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_isAvailable ? 'متاح' : 'غير متاح',
                style: TextStyle(
                    color: _isAvailable ? AppTheme.successGreen : AppTheme.textGrey,
                    fontSize: 11, fontWeight: FontWeight.bold)),
            Switch(
              value: _isAvailable,
              activeColor: AppTheme.successGreen,
              onChanged: (v) => _toggleAvailability(context.read<LegalProvider>(), v),
            ),
          ]),
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: AppTheme.primaryGold),
            tooltip: 'الإشعارات',
            onPressed: () => context.push('/user/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined, color: AppTheme.primaryGold),
            tooltip: 'تفاصيل حسابي',
            onPressed: _openAccountDetails,
          ),
          IconButton(
            icon: const Icon(Icons.lock_outline, color: AppTheme.primaryGold),
            tooltip: 'تغيير كلمة المرور',
            onPressed: _showProfileDialog,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'تسجيل خروج',
            onPressed: _logout,
          ),
        ],
        bottom: TabBar(controller: _tabCtrl, indicatorColor: AppTheme.primaryGold,
          labelColor: AppTheme.primaryGold, unselectedLabelColor: AppTheme.textGrey,
          tabs: [
            Tab(
              // 🔔 شارة الطلبات الجديدة (status=0) — تلفت نظر المحامي فوراً
              icon: E2E(
                id: 'e2e_lawyer_tab_consultations',
                button: true,
                child: Builder(builder: (_) {
                  final newCount = legal.lawyerConsultations
                      .where((c) => (c['status'] ?? 0) == 0)
                      .length;
                  if (newCount == 0) return const Icon(Icons.gavel);
                  return Stack(clipBehavior: Clip.none, children: [
                    const Icon(Icons.gavel),
                    Positioned(
                      top: -4, right: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.errorRed,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('$newCount',
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ]);
                }),
              ),
              text: 'الاستشارات',
            ),
            const Tab(icon: E2E(id: 'e2e_lawyer_tab_appointments', button: true, child: Icon(Icons.calendar_month)), text: 'مواعيدي'),
            const Tab(icon: E2E(id: 'e2e_lawyer_tab_create_task', button: true, child: Icon(Icons.add_task)), text: 'إضافة مهمة'),
            const Tab(icon: E2E(id: 'e2e_lawyer_tab_sent_tasks', button: true, child: Icon(Icons.assignment)), text: 'المهام المرسلة'),
            const Tab(icon: E2E(id: 'e2e_lawyer_tab_slots', button: true, child: Icon(Icons.schedule)), text: 'أوقاتي'),
          ]),
      ),
      body: TabBarView(controller: _tabCtrl, children: [
        _buildConsultationsTab(legal),
        _buildAppointmentsTab(legal),
        _buildCreateTaskTab(legal),
        _buildSentTasksTab(legal),
        _slotsEditor(legal, isGate: false),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 🗓️ أوقات الدوام (2026-08-14) — أساس حجز الجلسات الحضورية
  // العميل لا يرى إلا ما يفتحه المحامي هنا، فتُلغى جولة التفاوض.
  // ═══════════════════════════════════════════════════════════════
  static const List<(String, String)> _weekDays = [
    ('sun', 'الأحد'), ('mon', 'الاثنين'), ('tue', 'الثلاثاء'),
    ('wed', 'الأربعاء'), ('thu', 'الخميس'), ('fri', 'الجمعة'), ('sat', 'السبت'),
  ];

  /// أوقات قيد التحرير: يوم → (مفعّل، من، إلى)
  final Map<String, (bool, TimeOfDay, TimeOfDay)> _draftSlots = {};
  bool _savingSlots = false;

  void _seedDraftFromProfile(LegalProvider legal) {
    if (_draftSlots.isNotEmpty) return;
    final cur = legal.availabilitySlots;
    for (final (key, _) in _weekDays) {
      final list = cur[key] ?? const <String>[];
      if (list.isNotEmpty) {
        final parts = list.first.split('-');
        _draftSlots[key] = (true, _parseTime(parts.first), _parseTime(parts.last));
      } else {
        _draftSlots[key] = (false, const TimeOfDay(hour: 9, minute: 0),
            const TimeOfDay(hour: 17, minute: 0));
      }
    }
  }

  TimeOfDay _parseTime(String s) {
    final p = s.split(':');
    return TimeOfDay(
        hour: int.tryParse(p.first) ?? 9,
        minute: p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0);
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime(String dayKey, bool isStart) async {
    final cur = _draftSlots[dayKey]!;
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? cur.$2 : cur.$3,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _draftSlots[dayKey] =
          isStart ? (cur.$1, picked, cur.$3) : (cur.$1, cur.$2, picked);
    });
  }

  Future<void> _saveSlots(LegalProvider legal) async {
    final avl = <String, List<String>>{};
    for (final e in _draftSlots.entries) {
      final (on, from, to) = e.value;
      if (!on) continue;
      if (_fmtTime(from).compareTo(_fmtTime(to)) >= 0) {
        _snack('يوم ${_dayName(e.key)}: وقت البداية يجب أن يسبق النهاية',
            bg: AppTheme.errorRed);
        return;
      }
      avl[e.key] = ['${_fmtTime(from)}-${_fmtTime(to)}'];
    }
    if (avl.isEmpty) {
      _snack('فعّل يوماً واحداً على الأقل', bg: AppTheme.errorRed);
      return;
    }
    setState(() => _savingSlots = true);
    final uid = context.read<AuthProvider>().userModel?.uid ?? '';
    final ok = await legal.saveAvailabilitySlots(lawyerUid: uid, avl: avl);
    if (!mounted) return;
    setState(() => _savingSlots = false);
    if (ok) {
      _snack('✅ حُفظت أوقاتك — العميل يرى هذه الأوقات فقط');
      legal.fetchLawyerConsultations();
      legal.fetchLawyerAppointments();
    } else {
      _snack(legal.error ?? 'فشل الحفظ', bg: AppTheme.errorRed);
    }
  }

  String _dayName(String key) =>
      _weekDays.firstWhere((d) => d.$1 == key, orElse: () => (key, key)).$2;

  Widget _slotsEditor(LegalProvider legal, {required bool isGate}) {
    _seedDraftFromProfile(legal);
    return ListView(padding: AppTheme.paddingAllLarge, children: [
      Container(
        padding: AppTheme.paddingAllMedium,
        decoration: BoxDecoration(
          color: (isGate ? AppTheme.warningOrange : AppTheme.infoBlue).withOpacity(0.10),
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(
              color: (isGate ? AppTheme.warningOrange : AppTheme.infoBlue).withOpacity(0.45)),
        ),
        child: Row(children: [
          Icon(isGate ? Icons.schedule : Icons.info_outline,
              color: isGate ? AppTheme.warningOrange : AppTheme.infoBlue),
          AppTheme.gapWidthSmall,
          Expanded(
            child: Text(
              isGate
                  ? 'حدّد أوقات دوامك للبدء. العميل لن يرى إلا هذه الأوقات عند حجز جلسة حضورية.'
                  : 'العميل يحجز ضمن هذه الأوقات فقط. المواعيد المحجوزة مسبقاً لا تتأثر بالتعديل.',
              style: const TextStyle(
                  color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSmall, height: 1.5),
            ),
          ),
        ]),
      ),
      AppTheme.gapHeightLarge,
      ..._weekDays.map((d) {
        final (key, name) = d;
        final (on, from, to) = _draftSlots[key]!;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.surfaceBlack,
            borderRadius: AppTheme.radiusMedium,
            border: Border.all(
                color: on ? AppTheme.primaryGold.withOpacity(0.45) : Colors.white12),
          ),
          child: Row(children: [
            SizedBox(
              width: 62,
              child: Text(name,
                  style: TextStyle(
                      color: on ? AppTheme.textWhite : AppTheme.textGrey,
                      fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            Switch(
              value: on,
              activeColor: AppTheme.primaryGold,
              onChanged: (v) => setState(() => _draftSlots[key] = (v, from, to)),
            ),
            if (on) ...[
              Expanded(child: _timeChip('من', _fmtTime(from), () => _pickTime(key, true))),
              const SizedBox(width: 6),
              Expanded(child: _timeChip('إلى', _fmtTime(to), () => _pickTime(key, false))),
            ] else
              const Expanded(
                child: Text('عطلة',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
              ),
          ]),
        );
      }),
      AppTheme.gapHeightLarge,
      SizedBox(
        width: double.infinity, height: 50,
        child: ElevatedButton.icon(
          onPressed: _savingSlots ? null : () => _saveSlots(legal),
          icon: _savingSlots
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Icon(Icons.save, color: Colors.black),
          label: Text(_savingSlots ? 'جارٍ الحفظ...' : (isGate ? 'حفظ والمتابعة' : 'حفظ الأوقات'),
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
        ),
      ),
      const SizedBox(height: 24),
    ]);
  }

  Widget _timeChip(String label, String value, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.primaryGold.withOpacity(0.10),
            borderRadius: AppTheme.radiusSmall,
            border: Border.all(color: AppTheme.primaryGold.withOpacity(0.4)),
          ),
          child: Column(children: [
            Text(label, style: const TextStyle(color: AppTheme.textGrey, fontSize: 9)),
            Text(value,
                style: const TextStyle(
                    color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: 14)),
          ]),
        ),
      );

  /// بوابة إلزامية قبل استخدام اللوحة
  Widget _buildAvailabilityGate(LegalProvider legal) => Scaffold(
        backgroundColor: AppTheme.scaffoldBackground,
        appBar: AppBar(
          title: const Text('🗓️ حدّد أوقات دوامك'),
          backgroundColor: AppTheme.scaffoldBackground,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.redAccent),
              tooltip: 'تسجيل خروج',
              onPressed: _logout,
            ),
          ],
        ),
        body: _slotsEditor(legal, isGate: true),
      );

  // ──────── شاشة الإعداد الأولي ────────
  Widget _buildSetupScreen() {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('⚖️ مرحباً أستاذ'),
        backgroundColor: AppTheme.scaffoldBackground,
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined, color: AppTheme.primaryGold),
            tooltip: 'تفاصيل حسابي',
            onPressed: _openAccountDetails,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'تسجيل خروج',
            onPressed: _logout,
          ),
        ],
      ),
      body: SingleChildScrollView(padding: AppTheme.paddingAllXL, child: Column(children: [
        AppTheme.gapHeightXL,
        Container(padding: AppTheme.paddingAllXL,
          decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3))),
          child: Column(children: [
            const Icon(Icons.gavel, size: 50, color: AppTheme.primaryGold), AppTheme.gapHeightMedium,
            const Text('أهلاً بك', style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeTitle, fontWeight: FontWeight.bold)),
            AppTheme.gapHeightSmall,
            const Text('يرجى إعداد رقم الواتساب المعتمد', style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeMedium)),
            AppTheme.gapHeightXXL,
            TextField(controller: _whatsappCtrl, style: const TextStyle(color: AppTheme.textWhite),
              decoration: const InputDecoration(labelText: 'رقم الواتساب المعتمد *', hintText: '+9639xxxxxxxx',
                prefixIcon: Icon(Icons.phone_android, color: AppTheme.primaryGold)),
              keyboardType: TextInputType.phone),
            AppTheme.gapHeightLarge,
            TextField(controller: _addressCtrl, style: const TextStyle(color: AppTheme.textWhite),
              decoration: const InputDecoration(labelText: 'عنوان المكتب (اختياري)', hintText: 'مقر الشركة',
                prefixIcon: Icon(Icons.location_on, color: AppTheme.primaryGold))),
            AppTheme.gapHeightXXL,
            SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
              onPressed: _savingProfile ? null : _saveProfile,
              icon: _savingProfile ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
              label: Text(_savingProfile ? 'جاري...' : 'حفظ ومتابعة', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeSubtitle)),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold,
                shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusMedium)))),
          ])),
      ])),
    );
  }

  // ──────── تبويب الاستشارات القانونية ────────
  // 🔎 فلترة الاستشارات (2026-08-14): كانت الجديدة والمكتملة والملغاة في
  // قائمة واحدة مختلطة — فوضى بعد 30 قضية.
  int _consultFilter = -1; // -1 الكل · 0 جديدة · 1 جارية · 5 بانتظار العميل · 2 مكتملة
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  List<Map<String, dynamic>> _filterConsults(List<Map<String, dynamic>> all) {
    var out = all;
    if (_consultFilter != -1) {
      out = out.where((c) => (c['status'] ?? 0) == _consultFilter).toList();
    }
    final q = _searchQuery.trim();
    if (q.isNotEmpty) {
      out = out.where((c) {
        final subj = (c['subject'] ?? '').toString();
        final cn = c['client_nm'];
        final nm = cn is Map ? (cn['nm'] ?? '').toString() : (cn ?? '').toString();
        return subj.contains(q) || nm.contains(q);
      }).toList();
    }
    return out;
  }

  /// 📊 بطاقة أداء المحامي — التقييم كان يُسجَّل ولا يراه إطلاقاً
  Widget _lawyerStatsCard(List<Map<String, dynamic>> all) {
    final done = all.where((c) => (c['status'] ?? 0) == 2).length;
    final active = all.where((c) => [0, 1, 5].contains(c['status'] ?? 0)).length;
    final rated = all
        .where((c) => c['rating'] != null && (c['rating'] as num) > 0)
        .toList();
    final avg = rated.isEmpty
        ? 0.0
        : rated.map((c) => (c['rating'] as num).toDouble()).reduce((a, b) => a + b) /
            rated.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: AppTheme.paddingAllMedium,
      decoration: BoxDecoration(
        color: AppTheme.primaryGold.withOpacity(0.07),
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.35)),
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _statCell('$done', 'منجزة', AppTheme.successGreen),
          Container(width: 1, height: 34, color: Colors.white12),
          _statCell('$active', 'نشطة', AppTheme.primaryGold),
          Container(width: 1, height: 34, color: Colors.white12),
          _statCell(rated.isEmpty ? '—' : avg.toStringAsFixed(1),
              rated.isEmpty ? 'لا تقييم' : 'تقييم (${rated.length})', AppTheme.warningOrange,
              star: rated.isNotEmpty),
        ]),
        if (rated.isNotEmpty) ...[
          const Divider(color: Colors.white12, height: 18),
          ...rated.reversed.take(2).map((c) {
            final cmt = (c['rating_comment'] ?? '').toString();
            final r = (c['rating'] as num).toInt();
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('★' * r,
                    style: const TextStyle(color: AppTheme.warningOrange, fontSize: 11)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(cmt.isEmpty ? 'بلا تعليق' : cmt,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
                ),
              ]),
            );
          }),
        ],
      ]),
    );
  }

  Widget _statCell(String value, String label, Color color, {bool star = false}) =>
      Column(children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (star) const Icon(Icons.star, color: AppTheme.warningOrange, size: 15),
          Text(value,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
        ]),
        Text(label,
            style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
      ]);

  Widget _filterBar(List<Map<String, dynamic>> all) {
    int cnt(int st) => st == -1 ? all.length : all.where((c) => (c['status'] ?? 0) == st).length;
    final chips = <(int, String)>[
      (-1, 'الكل'), (0, 'جديدة'), (1, 'جارية'), (5, 'بانتظار العميل'), (2, 'مكتملة'),
    ];
    return Column(children: [
      SizedBox(
        height: 38,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final ch in chips)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: ChoiceChip(
                selected: _consultFilter == ch.$1,
                onSelected: (_) => setState(() => _consultFilter = ch.$1),
                label: Text('${ch.$2} (${cnt(ch.$1)})',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _consultFilter == ch.$1 ? Colors.black : AppTheme.textGrey)),
                selectedColor: AppTheme.primaryGold,
                backgroundColor: AppTheme.surfaceBlack,
                shape: RoundedRectangleBorder(
                  borderRadius: AppTheme.radiusXL,
                  side: BorderSide(
                      color: _consultFilter == ch.$1
                          ? AppTheme.primaryGold
                          : Colors.white12),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: const TextStyle(color: AppTheme.textWhite, fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'بحث بالموضوع أو اسم العميل...',
          hintStyle: const TextStyle(color: AppTheme.textGrey, fontSize: 12),
          prefixIcon: const Icon(Icons.search, color: AppTheme.primaryGold, size: 18),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textGrey, size: 16),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
          filled: true,
          fillColor: AppTheme.surfaceBlack,
          border: OutlineInputBorder(borderRadius: AppTheme.radiusMedium),
        ),
      ),
    ]);
  }

  Widget _buildConsultationsTab(LegalProvider legal) {
    final consultations = legal.lawyerConsultations;

    // 2026-08-14: «فارغ» كان يعني أحياناً «فشل النداء» (USER_UID_REQUIRED)
    // فيظن المحامي أنه بلا طلبات. الآن الفشل يُعلن صراحةً مع زر إعادة محاولة.
    if (consultations.isEmpty && legal.error != null) {
      return Center(
        child: Padding(
          padding: AppTheme.paddingAllXL,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 56, color: AppTheme.errorRed),
            AppTheme.gapHeightMedium,
            const Text('تعذّر جلب الاستشارات',
                style: TextStyle(color: AppTheme.errorRed, fontSize: AppTheme.fontSizeSubtitle, fontWeight: FontWeight.bold)),
            AppTheme.gapHeightSmall,
            Text(legal.error!, textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
            AppTheme.gapHeightLarge,
            ElevatedButton.icon(
              onPressed: () => legal.fetchLawyerConsultations(),
              icon: const Icon(Icons.refresh, color: Colors.black),
              label: const Text('إعادة المحاولة', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
            ),
          ]),
        ),
      );
    }

    if (consultations.isEmpty) {
      return Stack(children: [
        ListView(), // ليعمل السحب للتحديث على القائمة الفارغة
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.gavel, size: 60, color: AppTheme.textGrey.withOpacity(0.4)),
            AppTheme.gapHeightMedium,
            const Text('لا توجد استشارات حالياً',
                style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSubtitle)),
            AppTheme.gapHeightSmall,
            const Text('عند حجز عميل لاستشارة قانونية، ستظهر هنا',
                style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody)),
            AppTheme.gapHeightLarge,
            TextButton.icon(
              onPressed: () => legal.fetchLawyerConsultations(),
              icon: const Icon(Icons.refresh, color: AppTheme.primaryGold, size: 18),
              label: const Text('تحديث', style: TextStyle(color: AppTheme.primaryGold)),
            ),
          ]),
        ),
      ]);
    }
    // 📊 إحصاءات + 🔎 فلترة فوق القائمة (أُضيفتا 2026-08-14)
    final shown = _filterConsults(consultations);
    return RefreshIndicator(
      onRefresh: () => legal.fetchLawyerConsultations(),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Column(children: [
            _lawyerStatsCard(consultations),
            _filterBar(consultations),
          ]),
        ),
        Expanded(
          child: shown.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 60),
                  Center(
                    child: Text('لا نتائج مطابقة للفلتر',
                        style: TextStyle(color: AppTheme.textGrey, fontSize: 14)),
                  ),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: shown.length,
                  itemBuilder: (_, i) => _consultationCard(shown[i], legal),
                ),
        ),
      ]),
    );
  }

  Widget _consultationCard(Map<String, dynamic> c, LegalProvider legal) {
    final sts = c['status'] ?? 0;
    final (label, color) = _consultStatusInfo(sts);
    final serviceNames = ['استشارة هاتفية', 'جلسة مكتبية'];
    final sIdx = (c['service_type'] ?? 0) as int;
    final sName = sIdx < serviceNames.length ? serviceNames[sIdx] : 'استشارة';
    final price = (c['price'] ?? 0) as num;
    final subject = (c['subject'] ?? '').toString();
    final clientName = c['client_nm']?.toString() ?? 'عميل';
    // substring(0,16) كان يرمي استثناء ويكسر البطاقة لو قصُر النص
    final tsRaw = c['ts_crt']?.toString() ?? '';
    final tsCrt = tsRaw.length >= 16 ? tsRaw.substring(0, 16) : tsRaw;
    final chatStarted = c['chat_started_at'] != null;
    final extended = c['extended'] == true;
    final consultId = c['id']?.toString() ?? '';
    final attachments = (c['attachments'] as List?) ?? [];
    final rejectNote = (c['reject_note'] ?? '').toString();
    // موعد الجلسة الحضورية (requested_slot) بتوقيت دمشق
    final slotRaw = c['requested_slot']?.toString() ?? '';
    String apptWhen = '';
    if (slotRaw.isNotEmpty) {
      final dt = DateTime.tryParse(slotRaw)?.toLocal();
      if (dt != null) {
        apptWhen = '${dt.year}/${dt.month.toString().padLeft(2, '0')}/'
            '${dt.day.toString().padLeft(2, '0')} — '
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    }
    final reassignCount = (c['reassign_count'] ?? 0) as int;
    final reassigned = reassignCount > 0;

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
          Row(children: [
            Icon(Icons.gavel, color: AppTheme.primaryGold, size: 18),
            AppTheme.gapWidthSmall,
            Expanded(
              child: Text(sName,
                  style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeMedium)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: AppTheme.radiusSmall),
              child: Text(label, style: TextStyle(color: color, fontSize: AppTheme.fontSizeCaption, fontWeight: FontWeight.bold)),
            ),
          ]),
          AppTheme.gapHeightSmall,
          Text('العميل: $clientName', style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeBody, fontWeight: FontWeight.w600)),
          AppTheme.gapHeightXS,
          Text(subject, style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
          // 📎 2026-08-14: كانت تُعرض كعدد فقط بلا أي وسيلة لفتحها ⇒ المحامي
          // يقرر قبول القضية دون رؤية سند الملكية. صارت زراً يفتح المستندات.
          if (attachments.isNotEmpty) ...[
            AppTheme.gapHeightXS,
            InkWell(
              onTap: () => _showAttachments(consultId, attachments.length),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.infoBlue.withOpacity(0.12),
                  borderRadius: AppTheme.radiusSmall,
                  border: Border.all(color: AppTheme.infoBlue.withOpacity(0.45)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.attach_file, color: AppTheme.infoBlue, size: 15),
                  const SizedBox(width: 5),
                  Text('عرض ${attachments.length} مستند',
                      style: const TextStyle(
                          color: AppTheme.infoBlue,
                          fontSize: AppTheme.fontSizeCaption,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(width: 3),
                  const Icon(Icons.open_in_new, color: AppTheme.infoBlue, size: 13),
                ]),
              ),
            ),
          ],

          // 🔄 وسم التحويل: يعرف المحامي أن الطلب وصله من زميل اعتذر عنه
          if (reassigned) ...[
            AppTheme.gapHeightXS,
            Text('🔄 مُحوَّلة إليك (محاولة رقم $reassignCount)',
                style: const TextStyle(color: AppTheme.warningOrange, fontSize: AppTheme.fontSizeCaption, fontWeight: FontWeight.bold)),
          ],

          // 📄 بانتظار استكمال بيانات العميل — يعرض ما طلبه المحامي بنفسه
          if (sts == 5) ...[
            AppTheme.gapHeightSmall,
            Container(
              width: double.infinity,
              padding: AppTheme.paddingAllMedium,
              decoration: BoxDecoration(
                color: AppTheme.infoBlue.withOpacity(0.08),
                borderRadius: AppTheme.radiusSmall,
                border: Border.all(color: AppTheme.infoBlue.withOpacity(0.35)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('⏳ بانتظار استكمال العميل للبيانات',
                    style: TextStyle(color: AppTheme.infoBlue, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeSmall)),
                if (rejectNote.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('طلبتَ: $rejectNote',
                      style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption, height: 1.4)),
                ],
              ]),
            ),
          ],

          // ❌ اعتذار نهائي — يبقى السبب ظاهراً للمرجع
          if (sts == 4 && rejectNote.isNotEmpty) ...[
            AppTheme.gapHeightXS,
            Text('سبب الاعتذار: $rejectNote',
                style: const TextStyle(color: AppTheme.errorRed, fontSize: AppTheme.fontSizeCaption)),
          ],
          const SizedBox(height: 6),
          Row(children: [
            Text('${price.toStringAsFixed(0)} ل.س', style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeBody, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(tsCrt, style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
          ]),

          // ── بانتظار التأكيد (sts=0): قبول/رفض + بدء محادثة ──
          if (sts == 0) ...[
            AppTheme.gapHeightSmall,
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                // 2026-08-14: الرفض صار موجَّهاً بالسبب — السبب يحدد الإجراء
                // التالي آلياً بدل الرفض النهائي الصامت الذي كان يترك العميل
                // أمام «المحامي يدرس مشكلتك» إلى الأبد وماله محجوز.
                onPressed: () => _showRejectDialog(legal, c['id']?.toString()),
                icon: const Icon(Icons.close, color: AppTheme.errorRed, size: 16),
                label: const Text('اعتذار', style: TextStyle(color: AppTheme.errorRed, fontSize: AppTheme.fontSizeSmall)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.errorRed)),
              )),
              AppTheme.gapWidthSmall,
              Expanded(child: ElevatedButton.icon(
                // 2026-08-14: كان زراً واحداً «قبول وبدء» يفتح المحادثة فوراً
                // فيبدأ عدّاد الـ15 دقيقة والمحامي لم يقرأ المستندات بعد.
                // الآن: قبول فقط، وبدء المحادثة قرار منفصل حين يكون جاهزاً.
                onPressed: () => _updateConsultationStatus(legal, c['id'], 1, ''),
                icon: const Icon(Icons.check_circle, color: Colors.black, size: 16),
                label: const Text('قبول القضية', style: TextStyle(color: Colors.black, fontSize: AppTheme.fontSizeSmall, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successGreen),
              )),
            ]),
          ],

          // ── 🏢 مؤكدة + حضورية: موعد فقط بلا محادثة (قرار المالك 2026-08-14)
          // كانت تعرض «بدء المحادثة» و«تمديد 5 دقائق» لجلسة في المكتب — عبث.
          if (sts == 1 && sIdx == 1) ...[
            AppTheme.gapHeightSmall,
            Container(
              width: double.infinity,
              padding: AppTheme.paddingAllMedium,
              decoration: BoxDecoration(
                color: AppTheme.primaryGold.withOpacity(0.08),
                borderRadius: AppTheme.radiusSmall,
                border: Border.all(color: AppTheme.primaryGold.withOpacity(0.35)),
              ),
              child: Row(children: [
                const Icon(Icons.event_available, color: AppTheme.primaryGold, size: 18),
                AppTheme.gapWidthSmall,
                Expanded(
                  child: Text(
                    apptWhen.isEmpty
                        ? 'جلسة في المكتب — راجع تبويب «مواعيدي»'
                        : 'موعد الجلسة: $apptWhen',
                    style: const TextStyle(
                        color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSmall,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ]),
            ),
            AppTheme.gapHeightSmall,
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: () => _tabCtrl.animateTo(1),
              icon: const Icon(Icons.calendar_month, color: AppTheme.primaryGold, size: 16),
              label: const Text('إدارة الموعد',
                  style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.primaryGold)),
            )),
          ],

          // ── 📞 مؤكدة + هاتفية: محادثة + تمديد + إتمام ──
          if (sts == 1 && sIdx != 1) ...[
            AppTheme.gapHeightSmall,
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: () async {
                // بدء المحادثة قرار منفصل — المؤقت يبدأ الآن لا عند القبول
                if (!chatStarted) {
                  final go = await _confirmStartChat();
                  if (go != true) return;
                  await _startChat(consultId);
                }
                if (mounted) context.push('/legal/chat/$consultId');
              },
              icon: const Icon(Icons.chat, color: Colors.black, size: 16),
              label: Text(chatStarted ? 'فتح المحادثة' : 'بدء المحادثة الآن',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
            )),
            AppTheme.gapHeightSmall,
            Row(children: [
              if (chatStarted && !extended)
                Expanded(child: OutlinedButton.icon(
                  onPressed: () => _extendChat(consultId),
                  icon: const Icon(Icons.timer, color: AppTheme.infoBlue, size: 16),
                  label: const Text('تمديد 5 دقائق', style: TextStyle(color: AppTheme.infoBlue, fontSize: AppTheme.fontSizeSmall)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.infoBlue)),
                )),
              if (chatStarted && !extended) AppTheme.gapWidthSmall,
              Expanded(child: ElevatedButton.icon(
                onPressed: () => _updateConsultationStatus(legal, c['id'], 2, ''),
                icon: const Icon(Icons.done_all, color: Colors.black, size: 16),
                label: const Text('إتمام', style: TextStyle(color: Colors.black, fontSize: AppTheme.fontSizeSmall, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              )),
            ]),
            if (extended) ...[
              AppTheme.gapHeightXS,
              const Text('⏱️ تم التمديد 5 دقائق إضافية (مرة واحدة فقط)',
                  style: TextStyle(color: AppTheme.infoBlue, fontSize: AppTheme.fontSizeCaption)),
            ],
          ],
        ],
      ),
    );
  }

  /// 2026-08-14: كانت تعرض «✅ بدأت المحادثة» حتى عند فشل السيرفر لأنها لم
  /// تقرأ data['success'] إطلاقاً — تشويش مباشر للمحامي.
  Future<void> _startChat(String consultId) async {
    try {
      final uid = context.read<AuthProvider>().userModel?.uid ?? '';
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'start_chat', 'user_uid': uid, 'consultation_id': consultId,
      });
      final data = res.data as Map<String, dynamic>?;
      if (!mounted) return;
      if (data != null && data['success'] == true) {
        _snack('✅ بدأت المحادثة');
        await context.read<LegalProvider>().fetchLawyerConsultations();
      } else {
        final err = data?['error']?.toString() ?? '';
        _snack(
          err == 'CHAT_ALREADY_STARTED'
              ? 'المحادثة مفتوحة أصلاً'
              : err.isEmpty ? 'فشل بدء المحادثة' : 'فشل بدء المحادثة: $err',
          bg: AppTheme.errorRed,
        );
      }
    } catch (e) {
      if (mounted) _snack('فشل بدء المحادثة', bg: AppTheme.errorRed);
    }
  }

  Future<void> _extendChat(String consultId) async {
    try {
      final uid = context.read<AuthProvider>().userModel?.uid ?? '';
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'extend_chat', 'user_uid': uid, 'consultation_id': consultId,
      });
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        if (mounted) _snack('✅ تم تمديد المحادثة 5 دقائق');
      } else {
        if (mounted) _snack(data?['error']?.toString() ?? 'فشل التمديد', bg: AppTheme.errorRed);
      }
    } catch (e) {
      if (mounted) _snack('خطأ: $e', bg: AppTheme.errorRed);
    }
  }

  (String, Color) _consultStatusInfo(int sts) {
    switch (sts) {
      case 0:
        return ('بانتظار التأكيد', AppTheme.warningOrange);
      case 1:
        return ('مؤكدة', AppTheme.successGreen);
      case 2:
        return ('مكتملة', Colors.teal);
      case 3:
        return ('ملغاة', AppTheme.textGrey);
      case 4:
        return ('مرفوضة', AppTheme.errorRed);
      case 5:
        return ('بانتظار بيانات العميل', AppTheme.infoBlue);
      default:
        return ('غير معروف', AppTheme.textGrey);
    }
  }

  /// تأكيد قبل بدء المحادثة — المؤقت يبدأ فوراً فلا يُفتح بالخطأ
  Future<bool?> _confirmStartChat() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surfaceBlack,
          title: const Text('بدء المحادثة الآن؟',
              style: TextStyle(color: AppTheme.primaryGold, fontSize: 16, fontWeight: FontWeight.bold)),
          content: const Text(
            'سيبدأ عدّاد وقت الاستشارة فور الفتح. تأكد أنك راجعت الموضوع والمستندات.',
            style: TextStyle(color: AppTheme.textWhite, fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('لاحقاً', style: TextStyle(color: AppTheme.textGrey))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
              child: const Text('ابدأ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

  /// 📎 عرض مستندات العميل بروابط موقّعة (bucket خاص)
  Future<void> _showAttachments(String consultId, int count) async {
    if (consultId.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: Row(children: [
          const Icon(Icons.folder_open, color: AppTheme.primaryGold, size: 20),
          AppTheme.gapWidthSmall,
          Text('مستندات العميل ($count)',
              style: const TextStyle(color: AppTheme.primaryGold, fontSize: 15, fontWeight: FontWeight.bold)),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<List<Map<String, String>>>(
            future: context.read<LegalProvider>().fetchConsultationFiles(consultId),
            builder: (_, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 110,
                  child: Center(child: CircularProgressIndicator(color: AppTheme.primaryGold)),
                );
              }
              final files = snap.data ?? [];
              if (files.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('تعذّر تحميل المستندات — حاول مجدداً',
                      style: TextStyle(color: AppTheme.errorRed, fontSize: 13)),
                );
              }
              return SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final f in files)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ClipRRect(
                        borderRadius: AppTheme.radiusSmall,
                        child: Image.network(
                          f['url'] ?? '',
                          fit: BoxFit.contain,
                          loadingBuilder: (_, child, p) => p == null
                              ? child
                              : const SizedBox(
                                  height: 90,
                                  child: Center(
                                      child: CircularProgressIndicator(color: AppTheme.primaryGold))),
                          errorBuilder: (_, __, ___) => Container(
                            padding: AppTheme.paddingAllMedium,
                            color: AppTheme.scaffoldBackground,
                            child: Row(children: [
                              const Icon(Icons.insert_drive_file, color: AppTheme.infoBlue),
                              AppTheme.gapWidthSmall,
                              Expanded(
                                child: Text(f['name'] ?? 'مستند',
                                    style: const TextStyle(color: AppTheme.textWhite, fontSize: 12)),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ),
                ]),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق', style: TextStyle(color: AppTheme.primaryGold)),
          ),
        ],
      ),
    );
  }

  /// ⚖️ نافذة الاعتذار عن الاستشارة — السبب يحدد الإجراء (أُضيفت 2026-08-14)
  Future<void> _showRejectDialog(LegalProvider legal, String? id) async {
    if (id == null) return;
    String reason = 'unavailable';
    final noteCtrl = TextEditingController();

    const options = <Map<String, String>>[
      {
        'code': 'need_info',
        'title': '📄 نقص تفاصيل أو مستندات',
        'sub': 'يعود الطلب للعميل ليستكمل ثم يرجع إليك — بلا دفع جديد',
      },
      {
        'code': 'unavailable',
        'title': '🚫 غير متوفر حالياً',
        'sub': 'يُحوَّل تلقائياً لمحامٍ آخر متاح',
      },
      {
        'code': 'out_of_scope',
        'title': '⚖️ خارج اختصاصي',
        'sub': 'يُحوَّل تلقائياً لمحامٍ آخر',
      },
      {
        'code': 'illegal',
        'title': '❌ الطلب مخالف / غير قانوني',
        'sub': 'رفض نهائي مع إخطار الإدارة للبتّ بالمبلغ',
      },
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppTheme.surfaceBlack,
          title: const Text('سبب الاعتذار',
              style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('السبب يحدد ما سيحدث للطلب — اختر بدقة.',
                  style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
              const SizedBox(height: 10),
              ...options.map((o) => RadioListTile<String>(
                    value: o['code']!,
                    groupValue: reason,
                    onChanged: (v) => setLocal(() => reason = v ?? reason),
                    activeColor: AppTheme.primaryGold,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(o['title']!,
                        style: const TextStyle(color: AppTheme.textWhite, fontSize: 13, fontWeight: FontWeight.bold)),
                    subtitle: Text(o['sub']!,
                        style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)),
                  )),
              const SizedBox(height: 6),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                maxLength: 400,
                style: const TextStyle(color: AppTheme.textWhite, fontSize: 13),
                decoration: InputDecoration(
                  labelText: (reason == 'need_info' || reason == 'illegal')
                      ? 'التفاصيل المطلوبة (إلزامي)'
                      : 'ملاحظة (اختياري)',
                  hintText: reason == 'need_info'
                      ? 'مثال: أرفق صورة سند الملكية وحدد رقم العقار'
                      : '',
                  filled: true,
                  fillColor: AppTheme.scaffoldBackground,
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('تراجع', style: TextStyle(color: AppTheme.textGrey))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
              child: const Text('تأكيد', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) { noteCtrl.dispose(); return; }

    final note = noteCtrl.text.trim();
    noteCtrl.dispose();
    if ((reason == 'need_info' || reason == 'illegal') && note.length < 5) {
      _snack('يرجى كتابة التفاصيل — العميل يحتاج معرفة السبب', bg: AppTheme.errorRed);
      return;
    }

    final res = await legal.rejectConsultation(
        id: id, reasonCode: reason, reasonNote: note,
        actorUid: context.read<AuthProvider>().userModel?.uid ?? '');
    if (!mounted) return;
    if (res == null) {
      _snack(legal.error ?? 'فشل تنفيذ الاعتذار', bg: AppTheme.errorRed);
      return;
    }
    switch (res['outcome']?.toString()) {
      case 'need_info':
        _snack('📄 أُعيد الطلب للعميل لاستكمال البيانات');
        break;
      case 'reassigned':
        _snack('🔄 حُوّل الطلب إلى ${res['lawyer_alias'] ?? 'محامٍ آخر'}');
        break;
      case 'escalated_to_admin':
        _snack('🚨 لا يوجد محامٍ متاح — أُخطرت الإدارة');
        break;
      default:
        _snack('❌ تم رفض الطلب وإخطار الإدارة');
    }
  }

  /// 🟢 تبديل حالة التوفر (يؤثر مباشرة على إسناد الطلبات الجديدة)
  Future<void> _toggleAvailability(LegalProvider legal, bool value) async {
    final uid = context.read<AuthProvider>().userModel?.uid ?? '';
    if (uid.isEmpty) return;
    final res = await legal.setAvailability(lawyerUid: uid, available: value);
    if (!mounted) return;
    if (res == null) {
      _snack(legal.error ?? 'فشل تحديث حالة التوفر', bg: AppTheme.errorRed);
      return;
    }
    setState(() => _isAvailable = value);
    final pending = (res['pending_count'] ?? 0) as int;
    if (!value && pending > 0) {
      _snack('⚠️ لديك $pending طلب لم يبدأ — اعتذر عنها بسبب «غير متوفر» لتحويلها لمحامٍ آخر');
    } else {
      _snack(value ? '🟢 أنت متاح لاستقبال الطلبات' : '⚪ لن تصلك طلبات جديدة');
    }
  }

  /// ترجع true عند النجاح (2026-08-14) — «قبول وبدء» يعتمد عليها لئلا
  /// يبدأ المحادثة بعد فشل القبول.
  Future<bool> _updateConsultationStatus(
      LegalProvider legal, String? id, int status, String errorLabel) async {
    if (id == null) return false;
    final action = status == 1 ? 'تأكيد' : status == 2 ? 'إتمام' : 'رفض';
    final ok = await legal.updateConsultationStatus(
        id: id, status: status,
        actorUid: context.read<AuthProvider>().userModel?.uid ?? '');
    if (!mounted) return;
    if (ok) {
      _snack('✅ تم $action الاستشارة');
    } else {
      _snack(legal.error ?? 'فشل $action الاستشارة', bg: AppTheme.errorRed);
    }
    return ok;
  }

  Widget _buildAppointmentsTab(LegalProvider legal) {
    final apps = legal.lawyerAppointments;
    if (apps.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => legal.fetchLawyerAppointments(),
        child: Stack(children: [
          ListView(),
          Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.event_busy, size: 60, color: AppTheme.textGrey.withOpacity(0.4)),
            AppTheme.gapHeightMedium,
            const Text('لا توجد مواعيد حالياً',
                style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSubtitle)),
            AppTheme.gapHeightSmall,
            const Text('الجلسات الحضورية التي يحجزها العملاء ضمن أوقاتك تظهر هنا',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody)),
            AppTheme.gapHeightLarge,
            TextButton.icon(
              onPressed: () => legal.fetchLawyerAppointments(),
              icon: const Icon(Icons.refresh, color: AppTheme.primaryGold, size: 18),
              label: const Text('تحديث', style: TextStyle(color: AppTheme.primaryGold)),
            ),
          ])),
        ]),
      );
    }
    return RefreshIndicator(onRefresh: () => legal.fetchLawyerAppointments(),
      child: ListView.builder(padding: AppTheme.paddingAllLarge, itemCount: apps.length,
        itemBuilder: (_, i) => _apptCard(apps[i])));
  }

  Widget _apptCard(Map<String, dynamic> a) {
    final sts = a['sts']?.toString() ?? '0';
    final c = sts == '0' ? AppTheme.warningOrange : sts == '1' ? AppTheme.successGreen : sts == '2' ? AppTheme.infoBlue : AppTheme.errorRed;
    final apptId = a['appt_id']?.toString() ?? '';
    // 🔒 2026-08-14: client_phone حُذف من الدالة والبطاقة — كان يمكّن المحامي
    // من الاتصال بالعميل خارج التطبيق (نقيض حماية نموذج العمل).
    final rawDt = a['dt']?.toString() ?? '';
    final dt = DateTime.tryParse(rawDt)?.toLocal();
    final when = dt == null
        ? (rawDt.length >= 16 ? rawDt.substring(0, 16) : rawDt)
        : '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}'
            '  —  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final isPast = dt != null && dt.isBefore(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: c.withOpacity(0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 4, height: 46, decoration: BoxDecoration(color: c, borderRadius: AppTheme.radiusXS)),
          AppTheme.gapWidthMedium,
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.business, color: AppTheme.primaryGold, size: 15),
              const SizedBox(width: 4),
              Text(a['client_name']?.toString() ?? 'عميل',
                  style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 15)),
            ]),
            const SizedBox(height: 3),
            Text(when, style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeSmall, fontWeight: FontWeight.bold)),
            if (isPast && sts == '1')
              const Text('⚠️ مرّ موعدها — سجّل النتيجة',
                  style: TextStyle(color: AppTheme.warningOrange, fontSize: AppTheme.fontSizeCaption)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: AppTheme.radiusXL),
            child: Text(sts == '0' ? 'بانتظار تأكيدك' : sts == '1' ? 'مؤكد' : sts == '2' ? 'تمّت' : 'ملغي',
                style: TextStyle(color: c, fontSize: AppTheme.fontSizeCaption, fontWeight: FontWeight.bold)),
          ),
        ]),

        // 📅 2026-08-14: كان التبويب للعرض فقط بلا أي زر رغم دعم السيرفر
        if (sts == '0') ...[
          AppTheme.gapHeightMedium,
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: () => _apptAction(apptId, 'cancel'),
              icon: const Icon(Icons.close, color: AppTheme.errorRed, size: 15),
              label: const Text('اعتذار', style: TextStyle(color: AppTheme.errorRed, fontSize: AppTheme.fontSizeSmall)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.errorRed)),
            )),
            AppTheme.gapWidthSmall,
            Expanded(child: ElevatedButton.icon(
              onPressed: () => _apptAction(apptId, 'confirm'),
              icon: const Icon(Icons.check_circle, color: Colors.black, size: 15),
              label: const Text('تأكيد الموعد', style: TextStyle(color: Colors.black, fontSize: AppTheme.fontSizeSmall, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successGreen),
            )),
          ]),
        ],
        if (sts == '1') ...[
          AppTheme.gapHeightMedium,
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: () => _apptAction(apptId, 'cancel'),
              icon: const Icon(Icons.event_busy, color: AppTheme.errorRed, size: 15),
              label: const Text('إلغاء', style: TextStyle(color: AppTheme.errorRed, fontSize: AppTheme.fontSizeSmall)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.errorRed)),
            )),
            AppTheme.gapWidthSmall,
            Expanded(child: ElevatedButton.icon(
              onPressed: () => _apptAction(apptId, 'complete'),
              icon: const Icon(Icons.done_all, color: Colors.black, size: 15),
              label: const Text('تمّت الجلسة', style: TextStyle(color: Colors.black, fontSize: AppTheme.fontSizeSmall, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            )),
          ]),
        ],
      ]),
    );
  }

  /// تنفيذ إجراء على موعد: confirm | complete | cancel (الإلغاء يفرض سبباً)
  Future<void> _apptAction(String apptId, String act) async {
    if (apptId.isEmpty) return;
    String reason = '';
    if (act == 'cancel') {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surfaceBlack,
          title: const Text('سبب الإلغاء',
              style: TextStyle(color: AppTheme.errorRed, fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('يصل السبب للعميل مع دعوته لاختيار موعد آخر.',
                style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl, maxLines: 3, maxLength: 300,
              style: const TextStyle(color: AppTheme.textWhite, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'مثال: طارئ في المحكمة — أعتذر',
                filled: true, fillColor: AppTheme.scaffoldBackground,
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('تراجع', style: TextStyle(color: AppTheme.textGrey))),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
                child: const Text('تأكيد', style: TextStyle(color: Colors.white))),
          ],
        ),
      );
      reason = ctrl.text.trim();
      ctrl.dispose();
      if (ok != true) return;
      if (reason.length < 5) {
        _snack('اكتب سبباً واضحاً للعميل', bg: AppTheme.errorRed);
        return;
      }
    }
    final legal = context.read<LegalProvider>();
    final done = await legal.lawyerAppointmentAction(
        appointmentId: apptId, apptAction: act, reason: reason);
    if (!mounted) return;
    if (done) {
      _snack(act == 'confirm'
          ? '✅ تم تأكيد الموعد وإشعار العميل'
          : act == 'complete' ? '🎉 سُجّلت الجلسة كمكتملة' : '⚠️ أُلغي الموعد وأُشعر العميل');
    } else {
      _snack(legal.error ?? 'فشل تنفيذ الإجراء', bg: AppTheme.errorRed);
    }
  }

  // ──────── تبويب إضافة مهمة ────────
  Widget _buildCreateTaskTab(LegalProvider legal) {
    final expediters = legal.availableExpediters;
    return SingleChildScrollView(padding: AppTheme.paddingAllLarge, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('📋 تكليف معقب', style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeTitle, fontWeight: FontWeight.bold)),
      AppTheme.gapHeightLarge, const Text('نوع المعاملة:', style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeMedium)),
      Row(children: [
        Expanded(child: _Chip(label: '🏠 عقار', selected: _selectedItemType == 0, onTap: () => _changeItemType(0), e2eId: 'e2e_task_type_property')),
        AppTheme.gapWidthMedium,
        Expanded(child: _Chip(label: '🚗 سيارة', selected: _selectedItemType == 1, onTap: () => _changeItemType(1), e2eId: 'e2e_task_type_vehicle')),
      ]), AppTheme.gapHeightLarge, const Text('المعقب:', style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeMedium)),
      expediters.isEmpty
          ? Container(padding: AppTheme.paddingAllLarge, decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusMedium,
              border: Border.all(color: AppTheme.warningOrange.withOpacity(0.3))),
              child: const Row(children: [Icon(Icons.info_outline, color: AppTheme.warningOrange, size: 18), AppTheme.gapWidthSmall,
                Expanded(child: Text('لا يوجد معقبين. أضف معقباً من إدارة الموظفين.', style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody)))]))
          : E2E(
              id: 'e2e_lawyer_expediter_dropdown',
              child: DropdownButtonFormField<String>(value: _selectedExpediterUid, dropdownColor: AppTheme.surfaceBlack,
              style: const TextStyle(color: AppTheme.textWhite),
              decoration: const InputDecoration(labelText: 'اختر المعقب', prefixIcon: Icon(Icons.person_search, color: AppTheme.primaryGold)),
              // 2026-08-14: كان يعرض الاسم والهاتف فقط ⇒ المحامي يختار أعمى
              // فيكدّس المهام على واحد وزميله فارغ. الآن: عدد المهام النشطة
              // ووسم «الأقل انشغالاً»، والقائمة مرتّبة بالأقل أولاً (نفس أسس
              // إسناد المحامين).
              items: expediters.map((e) {
                final busy = (e['active_tasks'] ?? 0) as int;
                final least = e['is_least_busy'] == true;
                return DropdownMenuItem(
                  value: e['id']?.toString(),
                  child: Row(children: [
                    Expanded(
                      child: Text('${e['nm']}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppTheme.textWhite)),
                    ),
                    if (least) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.successGreen.withOpacity(0.18),
                          borderRadius: AppTheme.radiusXL,
                        ),
                        child: const Text('الأقل انشغالاً',
                            style: TextStyle(color: AppTheme.successGreen, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Text('$busy مهمة',
                        style: TextStyle(
                            color: busy == 0
                                ? AppTheme.successGreen
                                : busy >= 5 ? AppTheme.errorRed : AppTheme.textGrey,
                            fontSize: 11, fontWeight: FontWeight.bold)),
                  ]),
                );
              }).toList(),
              onChanged: (v) => setState(() => _selectedExpediterUid = v)),
            ),
      AppTheme.gapHeightLarge,
      if (_selectedItemType == 0) ...[
        E2E(id: 'e2e_task_property_number', child: TextField(controller: _taskPropertyCtrl, style: const TextStyle(color: AppTheme.textWhite),
          decoration: const InputDecoration(labelText: 'رقم العقار', hintText: '12345'))),
        AppTheme.gapHeightMedium,
        E2E(id: 'e2e_task_property_zone', child: TextField(controller: _taskZoneCtrl, style: const TextStyle(color: AppTheme.textWhite),
          decoration: const InputDecoration(labelText: 'المنطقة العقارية', hintText: 'السويداء'))),
      ],
      if (_selectedItemType == 1)
        E2E(id: 'e2e_task_vehicle_number', child: TextField(controller: _taskPropertyCtrl, style: const TextStyle(color: AppTheme.textWhite),
          decoration: const InputDecoration(labelText: 'رقم المركبة', hintText: '123456'))),
      AppTheme.gapHeightLarge,
      _buildChecklistSelector(),
      AppTheme.gapHeightMedium,
      E2E(id: 'e2e_task_notes', child: TextField(controller: _taskNotesCtrl, style: const TextStyle(color: AppTheme.textWhite), maxLines: 3,
        decoration: const InputDecoration(labelText: 'تعليمات', hintText: 'ملاحظات للمعقب...'))),
      AppTheme.gapHeightXXL,
      E2E(id: 'e2e_lawyer_send_task', button: true, child: SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
        onPressed: _creatingTask ? null : _createTask,
        icon: _creatingTask ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
        label: Text(_creatingTask ? 'جاري...' : 'إرسال للمعقب', style: const TextStyle(fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold, shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusMedium))))),
    ]));
  }

  Widget _buildChecklistSelector() {
    final docs = _documentTemplatesFor(_selectedItemType);
    return Container(
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('الوثائق المطلوبة من المعقب:', style: TextStyle(color: AppTheme.primaryGold, fontSize: 15, fontWeight: FontWeight.bold)),
          AppTheme.gapHeightSmall,
          const Text('حدد وثيقة أو أكثر لنفس المهمة، ثم اضبط عدد النسخ والتعليمات لكل وثيقة.', style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall, height: 1.35)),
          AppTheme.gapHeightMedium,
          ...docs.map((doc) {
            final key = doc['key']!;
            final selected = _selectedChecklist.any((item) => item['key'] == key);
            final canDelete = !_isBaseDocument(key);
            return E2E(
              id: 'e2e_doc_$key',
              button: true,
              child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: selected ? AppTheme.primaryGold.withOpacity(0.1) : AppTheme.scaffoldBackground,
                borderRadius: AppTheme.radiusMedium,
                border: Border.all(color: selected ? AppTheme.primaryGold : AppTheme.textGrey.withOpacity(0.18)),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: selected,
                    activeColor: AppTheme.primaryGold,
                    onChanged: (value) => _toggleDocumentForTask(doc, value == true),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => _toggleDocumentForTask(doc, !selected),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(doc['title']!, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  if (canDelete)
                    IconButton(
                      tooltip: 'حذف من القائمة الدائمة',
                      onPressed: () => _deletePermanentDocumentTemplate(doc),
                      icon: const Icon(Icons.delete_outline, color: AppTheme.errorRed, size: 20),
                    ),
                ],
              ),
              ),
            );
          }),
          AppTheme.gapHeightSmall,
          OutlinedButton.icon(
            onPressed: _addAllDefaultDocuments,
            icon: const Icon(Icons.playlist_add_check, color: AppTheme.primaryGold),
            label: const Text('تحديد كل وثائق القائمة', style: TextStyle(color: AppTheme.primaryGold)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.primaryGold), minimumSize: const Size(double.infinity, 44)),
          ),
          AppTheme.gapHeightLarge,
          const Divider(color: Colors.white12),
          AppTheme.gapHeightSmall,
          const Text('إضافة وثيقة دائمة للقائمة:', style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeBody, fontWeight: FontWeight.bold)),
          AppTheme.gapHeightSmall,
          Row(children: [
            Expanded(
              child: TextField(
                controller: _permanentDocTitleCtrl,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: const InputDecoration(labelText: 'اسم الوثيقة الجديدة', hintText: 'تُحفظ في القائمة لهذا الجهاز'),
              ),
            ),
            AppTheme.gapWidthSmall,
            IconButton(
              tooltip: 'إضافة للقائمة',
              onPressed: _addPermanentDocumentTemplate,
              icon: const Icon(Icons.add_circle, color: AppTheme.primaryGold, size: 30),
            ),
          ]),
          AppTheme.gapHeightLarge,
          const Text('وثيقة لمرة واحدة لهذه المهمة فقط:', style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeBody, fontWeight: FontWeight.bold)),
          AppTheme.gapHeightSmall,
          Row(children: [
            Expanded(
              child: TextField(
                controller: _oneTimeDocTitleCtrl,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: const InputDecoration(labelText: 'نص حر', hintText: 'لا تُحفظ في القائمة الدائمة'),
              ),
            ),
            AppTheme.gapWidthSmall,
            IconButton(
              tooltip: 'إضافة للمهمة فقط',
              onPressed: _addOneTimeDocument,
              icon: const Icon(Icons.post_add, color: AppTheme.primaryGold, size: 30),
            ),
          ]),
          AppTheme.gapHeightLarge,
          const Divider(color: Colors.white12),
          AppTheme.gapHeightSmall,
          if (_selectedChecklist.isEmpty)
            const Text('لم تحدد أي وثيقة بعد. يجب تحديد وثيقة واحدة على الأقل.', style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall))
          else ...[
            Text('الوثائق المحددة (${_selectedChecklist.length}):', style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeBody, fontWeight: FontWeight.bold)),
            AppTheme.gapHeightSmall,
            ..._selectedChecklist.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final title = item['title']?.toString() ?? '';
              final rawCopies = int.tryParse((item['required_copies'] ?? 1).toString()) ?? 1;
              final copies = rawCopies < 1 ? 1 : (rawCopies > 10 ? 10 : rawCopies);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: AppTheme.paddingAllMedium,
                decoration: BoxDecoration(
                  color: AppTheme.scaffoldBackground,
                  borderRadius: AppTheme.radiusMedium,
                  border: Border.all(color: AppTheme.primaryGold.withOpacity(0.15)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(title, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeBody))),
                    IconButton(
                      onPressed: () => setState(() => _selectedChecklist.removeAt(index)),
                      icon: const Icon(Icons.delete_outline, color: AppTheme.errorRed, size: 20),
                    ),
                  ]),
                  DropdownButtonFormField<int>(
                    value: copies,
                    dropdownColor: AppTheme.surfaceBlack,
                    style: const TextStyle(color: AppTheme.textWhite),
                    decoration: const InputDecoration(labelText: 'عدد النسخ المطلوبة'),
                    items: List.generate(10, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1} نسخة'))),
                    onChanged: (value) => setState(() => item['required_copies'] = value ?? 1),
                  ),
                  AppTheme.gapHeightSmall,
                  TextFormField(
                    key: ValueKey('instr_${item['key']}'),
                    initialValue: item['lawyer_instructions']?.toString() ?? '',
                    maxLines: 2,
                    style: const TextStyle(color: AppTheme.textWhite),
                    decoration: const InputDecoration(labelText: 'تعليمات خاصة بهذه الوثيقة', hintText: 'مثال: نسختان مصدقتان / صورة واضحة / إحضار الأصل'),
                    onChanged: (value) => item['lawyer_instructions'] = value.trim(),
                  ),
                ]),
              );
            }),
          ],
        ],
      ),
    );
  }

  Future<void> _requestRevision(ExpeditingTaskModel task, ChecklistItemModel item) async {
    final ctrl = TextEditingController(text: item.revisionNotes);
    final notes = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: Text('إعادة ${item.title}', style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeSubtitle)),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          style: const TextStyle(color: AppTheme.textWhite),
          decoration: const InputDecoration(labelText: 'سبب الإعادة / المطلوب تصحيحه'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء', style: TextStyle(color: AppTheme.textGrey))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('إرسال للمعقب')),
        ],
      ),
    );
    ctrl.dispose();
    if (notes == null || !mounted) return;
    final ok = await context.read<LegalProvider>().requestChecklistRevision(
      taskId: task.id,
      itemKey: item.key,
      notes: notes,
    );
    if (!mounted) return;
    if (ok) {
      _snack('تمت إعادة الوثيقة للمعقب مع التعليمات');
      if (Navigator.canPop(context)) Navigator.pop(context);
    } else {
      _snack(context.read<LegalProvider>().error ?? 'فشل طلب إعادة الوثيقة', bg: AppTheme.errorRed);
    }
  }

  void _showTaskReviewDialog(ExpeditingTaskModel task) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: Text('تفاصيل مهمة التعقيب', style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeSubtitle)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.itemType == 0 ? 'نوع المهمة: عقار' : 'نوع المهمة: سيارة', style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold)),
                if (task.targetPropertyNum.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('الرقم/المرجع: ${task.targetPropertyNum}', style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
                ],
                if (task.targetZone.isNotEmpty) ...[
                  AppTheme.gapHeightXS,
                  Text('المنطقة: ${task.targetZone}', style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
                ],
                if (task.lawyerNotes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('تعليمات عامة: ${task.lawyerNotes}', style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
                ],
                AppTheme.gapHeightMedium,
                ...task.checklist.map((item) {
                  final imageUrl = item.attachmentSignedUrl.isNotEmpty
                      ? item.attachmentSignedUrl
                      : (item.attachmentUrl.startsWith('http') ? item.attachmentUrl : '');
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: AppTheme.paddingAllMedium,
                    decoration: BoxDecoration(
                      color: AppTheme.scaffoldBackground,
                      borderRadius: AppTheme.radiusMedium,
                      border: Border.all(color: item.status == 2 ? AppTheme.successGreen.withOpacity(0.45) : AppTheme.primaryGold.withOpacity(0.18)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(item.status == 2 ? Icons.check_circle : Icons.pending_actions, color: item.status == 2 ? AppTheme.successGreen : AppTheme.primaryGold, size: 18),
                        AppTheme.gapWidthSmall,
                        Expanded(child: Text(item.title, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold))),
                      ]),
                      const SizedBox(height: 6),
                      Text('عدد النسخ المطلوبة: ${item.requiredCopies}', style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeSmall)),
                      if (item.lawyerInstructions.isNotEmpty) Text('تعليماتك: ${item.lawyerInstructions}', style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
                      if (item.inputValue.isNotEmpty) Text('بيانات المعقب: ${item.inputValue}', style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSmall)),
                      if (item.notes.isNotEmpty) Text('ملاحظات المعقب: ${item.notes}', style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
                      if (item.revisionNotes.isNotEmpty) Text('طلب إعادة سابق: ${item.revisionNotes}', style: const TextStyle(color: AppTheme.errorRed, fontSize: AppTheme.fontSizeSmall)),
                      if (imageUrl.isNotEmpty) ...[
                        AppTheme.gapHeightSmall,
                        ClipRRect(
                          borderRadius: AppTheme.radiusMedium,
                          child: Image.network(imageUrl, height: 170, width: double.infinity, fit: BoxFit.cover),
                        ),
                      ] else ...[
                        AppTheme.gapHeightSmall,
                        const Text('لا توجد صورة مرفقة بعد', style: TextStyle(color: AppTheme.errorRed, fontSize: AppTheme.fontSizeSmall)),
                      ],
                      if (task.status == 2) ...[
                        AppTheme.gapHeightSmall,
                        OutlinedButton.icon(
                          onPressed: () => _requestRevision(task, item),
                          icon: const Icon(Icons.replay, color: AppTheme.errorRed, size: 18),
                          label: const Text('إعادة هذا السند للمعقب', style: TextStyle(color: AppTheme.errorRed)),
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.errorRed)),
                        ),
                      ],
                    ]),
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق', style: TextStyle(color: AppTheme.textGrey))),
          if (task.status == 2)
            ElevatedButton(onPressed: () { Navigator.pop(ctx); _approveTask(task); }, child: const Text('اعتماد المهمة')),
        ],
      ),
    );
  }

  Future<void> _approveTask(ExpeditingTaskModel task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('اعتماد مهمة التعقيب', style: TextStyle(color: AppTheme.primaryGold)),
        content: const Text(
          'هل تؤكد اعتماد إنجاز المعقب لهذه المهمة؟ سيتم إشعار المعقب بالاعتماد.',
          style: TextStyle(color: AppTheme.textGrey, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء', style: TextStyle(color: AppTheme.textGrey))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('اعتماد')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final ok = await context.read<LegalProvider>().approveExpeditingTask(taskId: task.id);
    if (!mounted) return;
    if (ok) {
      _snack('✅ تم اعتماد المهمة وإشعار المعقب');
    } else {
      _snack(context.read<LegalProvider>().error ?? 'فشل اعتماد المهمة', bg: AppTheme.errorRed);
    }
  }

  // ──────── تبويب المهام المرسلة ────────
  Widget _buildSentTasksTab(LegalProvider legal) {
    final tasks = legal.lawyerTasks;
    if (tasks.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.assignment_late, size: 60, color: AppTheme.textGrey.withOpacity(0.4)),
      AppTheme.gapHeightMedium, const Text('لا توجد مهام', style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSubtitle)),
    ]));
    return RefreshIndicator(onRefresh: () => legal.fetchLawyerTasks(),
      child: ListView.builder(padding: AppTheme.paddingAllLarge, itemCount: tasks.length, itemBuilder: (_, i) {
        final t = tasks[i]; final done = t.checklist.where((c) => c.status >= 2).length;
        final total = t.checklist.length; final c = t.status == 0 ? AppTheme.warningOrange : t.status == 1 ? AppTheme.infoBlue : AppTheme.successGreen;
        return Container(margin: const EdgeInsets.only(bottom: 12), padding: AppTheme.paddingAllLarge,
          decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusLarge, border: Border.all(color: c.withOpacity(0.3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(Icons.assignment, color: c, size: 20), AppTheme.gapWidthSmall,
              Expanded(child: Text(
                t.status == 0 ? 'انتظار' : t.status == 1 ? 'قيد الاستخراج' : t.status == 2 ? 'مكتملة' : 'معتمدة 🎉',
                style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeMedium))),
              Text(t.itemType == 0 ? '🏠 عقار' : '🚗 سيارة', style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeSmall))]),
            if (t.targetPropertyNum.isNotEmpty) ...[
              AppTheme.gapHeightSmall,
              Text('رقم: ${t.targetPropertyNum} | ${t.targetZone}', style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody))],
            Row(children: [Icon(Icons.checklist, size: 16, color: AppTheme.primaryGold), const SizedBox(width: 6),
              Text('$done / $total وثائق', style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody)),
              if (t.status == 2) ...[
                AppTheme.gapWidthSmall,
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppTheme.warningOrange.withOpacity(0.2), borderRadius: AppTheme.radiusMedium),
                  child: const Text('بانتظار اعتمادك', style: TextStyle(color: AppTheme.warningOrange, fontSize: AppTheme.fontSizeCaption, fontWeight: FontWeight.bold)))],
              if (t.status == 3) ...[
                AppTheme.gapWidthSmall,
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppTheme.successGreen.withOpacity(0.2), borderRadius: AppTheme.radiusMedium),
                  child: const Text('معتمد', style: TextStyle(color: AppTheme.successGreen, fontSize: AppTheme.fontSizeCaption, fontWeight: FontWeight.bold)))],
            ]),
            AppTheme.gapHeightMedium,
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: () => _showTaskReviewDialog(t),
              icon: const Icon(Icons.visibility, color: AppTheme.primaryGold),
              label: const Text('فتح تفاصيل المهمة والوثائق', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.primaryGold)),
            )),
            if (t.status == 2) ...[
              AppTheme.gapHeightSmall,
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                onPressed: () => _showTaskReviewDialog(t),
                icon: const Icon(Icons.verified, color: AppTheme.deepBlack),
                label: const Text('مراجعة ثم اعتماد إنجاز المعقب', style: TextStyle(color: AppTheme.deepBlack, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successGreen),
              )),
            ],
          ]));
      }));
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? e2eId;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.e2eId,
  });

  @override
  Widget build(BuildContext context) {
    final chip = GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: selected ? AppTheme.primaryGold.withOpacity(0.2) : AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: selected ? AppTheme.primaryGold : AppTheme.textGrey.withOpacity(0.3), width: selected ? 2 : 1)),
      child: Center(child: Text(label, style: TextStyle(color: selected ? AppTheme.primaryGold : AppTheme.textGrey,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal, fontSize: 15)))));
    return e2eId == null ? chip : E2E(id: e2eId!, button: true, child: chip);
  }
}

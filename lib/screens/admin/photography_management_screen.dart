import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/network/supabase_service.dart';
import '../../core/services/permission_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/offer_model.dart';
import '../../models/photography_task_model.dart';
import '../../models/user_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/photography_provider.dart';
import 'admin_add_offer_screen.dart';

class PhotographyManagementScreen extends StatefulWidget {
  const PhotographyManagementScreen({super.key});

  @override
  State<PhotographyManagementScreen> createState() => _PhotographyManagementScreenState();
}

class _PhotographyManagementScreenState extends State<PhotographyManagementScreen> {
  List<PhotographyTaskModel> _tasks = [];
  List<OfferModel> _offers = [];
  List<UserModel> _photographers = [];
  bool _loading = true;
  /// 📊 أرقام مجمّعة من إيدج admin-photography: stats (null قبل الجلب)
  Map<String, dynamic>? _stats;
  int? _filter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final photo = context.read<PhotographyProvider>();
    final admin = context.read<AdminProvider>();
    final results = await Future.wait([
      photo.getAllTasks(status: _filter),
      admin.getOffersForMediaReview(context.read<AuthProvider>().userModel?.uid ?? ''),
      admin.getAllUsers(),
    ]);
    if (!mounted) return;
    final users = results[2] as List<UserModel>;
    setState(() {
      _tasks = results[0] as List<PhotographyTaskModel>;
      _offers = results[1] as List<OfferModel>;
      _photographers = users
          .where((user) => PermissionService.has(user, PermissionKeys.photographerTasks))
          .toList();
      _loading = false;
    });
    _loadStats();
  }

  /// 📊 إحصاءات مجمّعة (الفلاتر تعرض قوائم فقط — هذه تعطي نظرة إدارية بأرقام).
  Future<void> _loadStats() async {
    final uid = context.read<AuthProvider>().userModel?.uid ?? '';
    if (uid.isEmpty) return;
    try {
      final res = await SupabaseService().invokeFunction(
        'admin-photography',
        body: {'action': 'stats', 'admin_uid': uid},
      );
      final d = res.data;
      if (d is Map && d['success'] == true && mounted) {
        setState(() => _stats = Map<String, dynamic>.from(d));
      }
    } catch (_) {
      // الإحصاءات إثراء — فشلها لا يمنع عرض المهام
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground,
        title: const Text('إدارة مهام التصوير'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_a_photo, color: AppTheme.primaryGold),
            onPressed: _showCreateTaskSheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryGold),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGold))
          : RefreshIndicator(
              color: AppTheme.primaryGold,
              onRefresh: _load,
              child: ListView(
                padding: AppTheme.paddingAllLarge,
                children: [
                  if (_stats != null) ...[
                    _statsBar(),
                    AppTheme.gapHeightMedium,
                  ],
                  _filters(),
                  AppTheme.gapHeightMedium,
                  if (_tasks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 100),
                      child: Center(child: Text('لا توجد مهام تصوير', style: TextStyle(color: AppTheme.textGrey))),
                    )
                  else
                    ..._tasks.map(_taskCard),
                ],
              ),
            ),
    );
  }

  /// 📊 شريط الأرقام: تكدّس · إنتاجية · تحويل لعروض · سرعة الإنجاز
  Widget _statsBar() {
    final s = _stats!;
    final st = Map<String, dynamic>.from(s['by_status'] ?? {});
    int n(String k) => int.tryParse('${st[k] ?? 0}') ?? 0;
    final avgH = s['avg_done_hours'];
    final top = (s['top_photographers'] as List?) ?? const [];

    String avgTxt() {
      if (avgH == null) return '—';
      final h = double.tryParse('$avgH') ?? 0;
      if (h < 24) return '${h.toStringAsFixed(1)} س';
      return '${(h / 24).toStringAsFixed(1)} يوم';
    }

    return Container(
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights, color: AppTheme.primaryGold, size: 18),
              const SizedBox(width: 6),
              Text('نظرة عامة — ${s['total'] ?? 0} طلب تصوير',
                  style: const TextStyle(
                      color: AppTheme.primaryGold,
                      fontSize: AppTheme.fontSizeMedium,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          AppTheme.gapHeightMedium,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statChip('بانتظار', n('pending'), AppTheme.warningOrange),
              _statChip('قيد التنفيذ', n('in_progress'), AppTheme.infoBlue),
              _statChip('بانتظار المراجعة', n('submitted'), Colors.purple),
              _statChip('معتمدة', n('approved'), AppTheme.successGreen),
              _statChip('مرفوضة', n('rejected'), AppTheme.errorRed),
              _statChip('ملغاة', n('cancelled'), AppTheme.textGrey),
            ],
          ),
          const Divider(color: Colors.white12, height: 22),
          Row(
            children: [
              Expanded(
                child: _statMetric(Icons.post_add, 'صارت عروضاً',
                    '${s['became_offers'] ?? 0}  (${s['conversion_pct'] ?? 0}%)'),
              ),
              Expanded(
                child: _statMetric(
                    Icons.timer_outlined, 'متوسط الإنجاز', avgTxt()),
              ),
            ],
          ),
          if (top.isNotEmpty) ...[
            AppTheme.gapHeightSmall,
            Text(
              'الأكثر إنجازاً: ${top.map((e) => '${e['name']} (${e['done']})').join(' · ')}',
              style: const TextStyle(color: AppTheme.textGrey, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statChip(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: AppTheme.radiusSmall,
        border: Border.all(color: color.withOpacity(0.40)),
      ),
      child: Text('$label: $value',
          style: TextStyle(
              color: color, fontSize: AppTheme.fontSizeSmall, fontWeight: FontWeight.bold)),
    );
  }

  Widget _statMetric(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryGold, size: 17),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
              Text(value,
                  style: const TextStyle(
                      color: AppTheme.textWhite,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filters() {
    final filters = <(String, int?)>[
      ('الكل', null),
      ('بانتظار', 0),
      ('قيد التنفيذ', 1),
      ('مرسلة', 2),
      ('معتمدة', 3),
      ('مرفوضة', 4),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((item) {
          final selected = _filter == item.$2;
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: ChoiceChip(
              label: Text(item.$1),
              selected: selected,
              selectedColor: AppTheme.primaryGold,
              backgroundColor: AppTheme.surfaceBlack,
              labelStyle: TextStyle(color: selected ? AppTheme.deepBlack : AppTheme.textWhite),
              side: BorderSide(color: AppTheme.primaryGold.withOpacity(0.25)),
              onSelected: (_) {
                setState(() => _filter = item.$2);
                _load();
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _taskCard(PhotographyTaskModel task) {
    final color = _statusColor(task.sts);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Padding(
        padding: AppTheme.paddingAllLarge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(backgroundColor: color.withOpacity(0.14), child: Icon(Icons.camera_alt, color: color)),
                AppTheme.gapWidthSmall,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.ttl.isEmpty ? 'مهمة تصوير' : task.ttl,
                          style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          Text(task.statusLabel, style: TextStyle(color: color, fontSize: AppTheme.fontSizeSmall)),
                          if (task.offId.isEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryGold.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppTheme.primaryGold.withOpacity(0.4)),
                              ),
                              child: const Text('طلب مستخدم',
                                  style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeXS)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (task.offId.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.open_in_new, color: AppTheme.primaryGold),
                    onPressed: () => context.push('/offer/${task.offId}'),
                  ),
              ],
            ),
            if (task.notes.isNotEmpty) ...[
              AppTheme.gapHeightSmall,
              Text(task.notes, style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody)),
            ],
            if (task.photographerNote.isNotEmpty) ...[
              AppTheme.gapHeightSmall,
              Text('ملاحظة المصور: ${task.photographerNote}', style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSmall)),
            ],
            AppTheme.gapHeightSmall,
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _badge('${task.media.length} وسائط', task.media.isEmpty ? AppTheme.warningOrange : AppTheme.successGreen),
                if (task.tsScheduled != null) _badge(_fmtDate(task.tsScheduled!), AppTheme.infoBlue),
              ],
            ),
            if (task.media.isNotEmpty) ...[
              AppTheme.gapHeightMedium,
              SizedBox(
                height: 76,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: task.media.length,
                  itemBuilder: (_, index) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ClipRRect(
                      borderRadius: AppTheme.radiusMedium,
                      child: Image.network(task.media[index], width: 76, height: 76, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(width: 76, height: 76, color: AppTheme.deepBlack, child: const Icon(Icons.broken_image, color: AppTheme.textGrey))),
                    ),
                  ),
                ),
              ),
            ],
            if (task.sts == 0) ...[
              const Divider(color: Colors.white12, height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _assignPhotographer(task),
                  icon: const Icon(Icons.person_add_alt_1,
                      color: AppTheme.primaryGold, size: 18),
                  label: Text(
                    task.photographerId.isEmpty
                        ? 'إسناد مصوّر'
                        : 'إعادة إسناد مصوّر',
                    style: const TextStyle(color: AppTheme.primaryGold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: AppTheme.primaryGold.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
            if (task.isSubmitted) ...[
              const Divider(color: Colors.white12, height: 24),
              // 📸 طلبات المستخدمين تصل بلا عرض (off_id فارغ) — الصور كانت تبقى
              // حبيسة المهمة بلا طريق لتصير عرضاً. هذا الزر يفتح شاشة الإضافة
              // محمّلة بصور المصوّر وبيانات الطالب، وينشر مباشرةً بعد الإكمال.
              if (task.offId.isEmpty) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _createOfferFromTask(task),
                    icon: const Icon(Icons.post_add, color: AppTheme.deepBlack),
                    label: const Text('إنشاء عرض من الصور',
                        style: TextStyle(
                            color: AppTheme.deepBlack,
                            fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryGold),
                  ),
                ),
                AppTheme.gapHeightSmall,
              ],
              if (task.isPhotoRequestOffer && task.offId.isNotEmpty) ...[
                const Text(
                  'اكتملت الصور وأصبح العرض ضمن مراجعة العروض العادية.',
                  style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall),
                ),
                AppTheme.gapHeightSmall,
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => context.push('/admin/review-offers'),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('فتح مراجعة العروض'),
                  ),
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _approveAndAttach(task),
                        icon: const Icon(Icons.check),
                        label: Text(task.offId.isEmpty
                            ? 'اعتماد فقط'
                            : 'اعتماد وربط بالعرض'),
                      ),
                    ),
                    AppTheme.gapWidthSmall,
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _rejectTask(task),
                        icon: const Icon(Icons.close, color: AppTheme.errorRed),
                        label: const Text('رفض', style: TextStyle(color: AppTheme.errorRed)),
                      ),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateTaskSheet() async {
    if (_photographers.isEmpty) {
      _snack('لا يوجد مستخدمون لديهم صلاحية photographer_tasks');
      return;
    }
    OfferModel? selectedOffer;
    UserModel? selectedPhotographer;
    final notesCtrl = TextEditingController();
    DateTime? scheduledAt;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceBlack,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              const Text('إنشاء مهمة تصوير', style: TextStyle(color: AppTheme.primaryGold, fontSize: 17, fontWeight: FontWeight.bold)),
              AppTheme.gapHeightMedium,
              DropdownButtonFormField<OfferModel>(
                dropdownColor: AppTheme.surfaceBlack,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: const InputDecoration(labelText: 'العرض'),
                items: _offers.take(100).map((offer) => DropdownMenuItem(value: offer, child: Text(offer.ttl, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (value) => setSheet(() => selectedOffer = value),
              ),
              AppTheme.gapHeightMedium,
              DropdownButtonFormField<UserModel>(
                dropdownColor: AppTheme.surfaceBlack,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: const InputDecoration(labelText: 'المصور'),
                items: _photographers.map((user) => DropdownMenuItem(value: user, child: Text(user.nm.isEmpty ? user.ph : user.nm))).toList(),
                onChanged: (value) => setSheet(() => selectedPhotographer = value),
              ),
              AppTheme.gapHeightMedium,
              TextField(
                controller: notesCtrl,
                maxLines: 3,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: const InputDecoration(labelText: 'ملاحظات التصوير'),
              ),
              AppTheme.gapHeightMedium,
              OutlinedButton.icon(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date == null) return;
                  final time = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
                  if (time == null) return;
                  setSheet(() => scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                },
                icon: const Icon(Icons.schedule, color: AppTheme.primaryGold),
                label: Text(scheduledAt == null ? 'تحديد موعد اختياري' : _fmtDate(scheduledAt!), style: const TextStyle(color: AppTheme.primaryGold)),
              ),
              AppTheme.gapHeightMedium,
              ElevatedButton.icon(
                onPressed: () async {
                  if (selectedOffer == null || selectedPhotographer == null) {
                    _snack('اختر العرض والمصور');
                    return;
                  }
                  final requestedBy = context.read<AuthProvider>().userModel?.uid ?? '';
                  final ok = await context.read<PhotographyProvider>().createTask(
                        offer: selectedOffer!,
                        photographerId: selectedPhotographer!.uid,
                        requestedBy: requestedBy,
                        notes: notesCtrl.text.trim(),
                        scheduledAt: scheduledAt,
                      );
                  if (!mounted) return;
                  Navigator.pop(ctx);
                  _snack(ok ? 'تم إنشاء مهمة التصوير' : 'فشل إنشاء المهمة');
                  _load();
                },
                icon: const Icon(Icons.save),
                label: const Text('إنشاء المهمة'),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  /// 📸 إنشاء عرض من صور مهمة تصوير (طلب مستخدم بلا عرض مسبق).
  /// المالك = صاحب الطلب (قرار المالك) · الصور جاهزة · النشر مباشر بعد الإكمال.
  Future<void> _createOfferFromTask(PhotographyTaskModel task) async {
    if (task.media.isEmpty) {
      _snack('لا توجد صور بهذه المهمة');
      return;
    }
    // الهاتف والموقع مخزّنان داخل notes بصيغة «الاسم: … | الموقع: … | الهاتف: …»
    String pick(String label) {
      for (final seg in task.notes.split('|')) {
        if (seg.contains('$label:')) return seg.split('$label:').last.trim();
      }
      return '';
    }

    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AdminAddOfferScreen(
          photoTaskId: task.id,
          presetOwnerUid: task.requestedBy,
          presetImages: task.media,
          presetPhone: pick('الهاتف'),
          presetLocation: pick('الموقع'),
        ),
      ),
    );
    if (created == true) _load();
  }

  Future<void> _approveAndAttach(PhotographyTaskModel task) async {
    final adminId = context.read<AuthProvider>().userModel?.uid ?? '';
    // المهام المرتبطة بعرض: اعتماد + ربط الوسائط بالعرض
    // طلبات المستخدم بلا عرض: اعتماد فقط (لا يوجد عرض للربط)
    final ok = task.offId.isNotEmpty
        ? await context.read<PhotographyProvider>().attachMediaToOffer(adminId, task)
        : await context.read<PhotographyProvider>().updateStatus(adminId, task.id, 3,
            officeNote: 'تم اعتماد التصوير');
    _snack(ok
        ? (task.offId.isNotEmpty ? 'تم اعتماد التصوير وربطه بالعرض' : 'تم اعتماد التصوير')
        : 'فشل اعتماد التصوير');
    _load();
  }

  /// إسناد مصور لمهمة بانتظار — يخدم بشكل خاص طلبات التصوير القادمة من المستخدمين
  Future<void> _assignPhotographer(PhotographyTaskModel task) async {
    if (_photographers.isEmpty) {
      _snack('لا يوجد مستخدمون لديهم صلاحية photographer_tasks');
      return;
    }
    UserModel? selected;
    DateTime? scheduledAt;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceBlack,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('إسناد مصوّر',
                  style: TextStyle(color: AppTheme.primaryGold, fontSize: 17, fontWeight: FontWeight.bold)),
              AppTheme.gapHeightMedium,
              DropdownButtonFormField<UserModel>(
                dropdownColor: AppTheme.surfaceBlack,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: const InputDecoration(labelText: 'المصور'),
                items: _photographers
                    .map((u) => DropdownMenuItem(value: u, child: Text(u.nm.isEmpty ? u.ph : u.nm)))
                    .toList(),
                onChanged: (v) => setSheet(() => selected = v),
              ),
              AppTheme.gapHeightMedium,
              OutlinedButton.icon(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date == null) return;
                  final time = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
                  if (time == null) return;
                  setSheet(() => scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                },
                icon: const Icon(Icons.schedule, color: AppTheme.primaryGold),
                label: Text(
                  scheduledAt == null ? 'تحديد موعد اختياري' : _fmtDate(scheduledAt!),
                  style: const TextStyle(color: AppTheme.primaryGold),
                ),
              ),
              AppTheme.gapHeightMedium,
              ElevatedButton.icon(
                onPressed: () async {
                  if (selected == null) {
                    _snack('اختر المصور');
                    return;
                  }
                  final ok = await context.read<PhotographyProvider>().assignTask(
                        taskId: task.id,
                        photographerId: selected!.uid,
                        scheduledAt: scheduledAt,
                      );
                  if (!mounted) return;
                  Navigator.pop(ctx);
                  _snack(ok ? 'تم إسناد المهمة للمصور' : 'فشل الإسناد');
                  _load();
                },
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('إسناد المهمة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _rejectTask(PhotographyTaskModel task) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('رفض التصوير', style: TextStyle(color: AppTheme.textWhite)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: AppTheme.textWhite),
          decoration: const InputDecoration(labelText: 'سبب الرفض'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('رفض')),
        ],
      ),
    );
    if (reason == null) return;
    final adminId = context.read<AuthProvider>().userModel?.uid ?? '';
    final ok = await context.read<PhotographyProvider>().updateStatus(adminId, task.id, 4, officeNote: reason);
    _snack(ok ? 'تم رفض التصوير' : 'فشل الرفض');
    _load();
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.13),
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: AppTheme.fontSizeXS, fontWeight: FontWeight.w600)),
    );
  }

  Color _statusColor(int status) {
    switch (status) {
      case 0:
        return AppTheme.warningOrange;
      case 1:
        return AppTheme.infoBlue;
      case 2:
        return AppTheme.primaryGold;
      case 3:
        return AppTheme.successGreen;
      case 4:
        return AppTheme.errorRed;
      default:
        return AppTheme.textGrey;
    }
  }

  String _fmtDate(DateTime date) =>
      '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  void _snack(String message) {
    if (!mounted) return;
    AppTheme.showSnackBar(context, SnackBar(content: Text(message)));
  }
}

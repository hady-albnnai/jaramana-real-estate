import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_utils.dart';
import '../../core/utils/error_utils.dart';
import '../../models/photography_task_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/photography_provider.dart';
import '../../services/storage_service.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/office_logo_placeholder.dart';

class PhotographerTasksScreen extends StatefulWidget {
  const PhotographerTasksScreen({super.key});

  @override
  State<PhotographerTasksScreen> createState() => _PhotographerTasksScreenState();
}

class _PhotographerTasksScreenState extends State<PhotographerTasksScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<PhotographyTaskModel> _allTasks = [];
  bool _loading = true;
  String? _loadError;

  // للتبويب المؤجلة — تقويم
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  // حالة رفع الصور لكل مهمة
  String? _expandedTaskId;
  final Map<String, List<XFile>> _tempMedia = {};
  final Map<String, TextEditingController> _notesControllers = {};
  final Map<String, bool> _isUploading = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tab.dispose();
    for (final c in _notesControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final userId = context.read<AuthProvider>().userModel?.uid ?? '';
    final provider = context.read<PhotographyProvider>();
    final tasks = await provider.getPhotographerTasks(userId);
    if (!mounted) return;
    setState(() {
      _allTasks = tasks;
      _loadError = provider.error == null
          ? null
          : ErrorUtils.arabicMessage(provider.error!);
      _loading = false;
    });
  }

  // ─── فلترة حسب التبويب ───

  List<PhotographyTaskModel> get _todayTasks {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    final tasks = _allTasks.where((t) =>
        (t.sts == 0 || t.sts == 1 || t.sts == 4) &&
        (t.tsScheduled == null || t.tsScheduled!.isBefore(tomorrow))).toList();
    tasks.sort((a, b) {
      if (a.tsScheduled == null) return 1;
      if (b.tsScheduled == null) return -1;
      return a.tsScheduled!.compareTo(b.tsScheduled!);
    });
    return tasks;
  }

  List<PhotographyTaskModel> get _postponedTasks {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    final tasks = _allTasks.where((t) =>
        (t.sts == 0 || t.sts == 1 || t.sts == 4) &&
        t.tsScheduled != null &&
        !t.tsScheduled!.isBefore(tomorrow)).toList();
    tasks.sort((a, b) => a.tsScheduled!.compareTo(b.tsScheduled!));
    return tasks;
  }

  List<PhotographyTaskModel> get _completedTasks {
    return _allTasks.where((t) => t.sts == 2 || t.sts == 3 || t.sts == 5).toList();
  }

  List<PhotographyTaskModel> get _selectedDayTasks {
    if (_selectedDay == null) return [];
    return _postponedTasks.where((t) {
      if (t.tsScheduled == null) return false;
      final local = t.tsScheduled!.toLocal();
      return local.year == _selectedDay!.year &&
          local.month == _selectedDay!.month &&
          local.day == _selectedDay!.day;
    }).toList();
  }

  // ─── إجراءات المصور ───

  Future<void> _startTask(PhotographyTaskModel task) async {
    if (!task.isInProgress) {
      final userId = context.read<AuthProvider>().userModel?.uid ?? '';
      final ok = await context.read<PhotographyProvider>().startTask(userId, task.id);
      if (!mounted) return;
      if (!ok) {
        final error = context.read<PhotographyProvider>().error;
        _snack(ErrorUtils.arabicMessage(error ?? 'TASK_START_FAILED'));
        return;
      }
    }
    setState(() {
      _expandedTaskId = task.id;
      _tempMedia[task.id] = [];
      _notesControllers[task.id] = TextEditingController(text: task.photographerNote);
    });
  }

  /// 🔄 اعتذار عن المهمة بسبب إلزامي — ترجع لطابور المكتب ويُشعَرون فوراً.
  Future<void> _declineTask(PhotographyTaskModel task) async {
    final ctrl = TextEditingController();
    String? err;

    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppTheme.surfaceBlack,
          shape: RoundedRectangleBorder(
              borderRadius: AppTheme.radiusLarge),
          title: const Row(
            children: [
              Icon(Icons.event_busy, color: AppTheme.errorRed, size: 22),
              AppTheme.gapWidthSmall,
              Expanded(
                child: Text('اعتذار عن المهمة',
                    style: TextStyle(
                        color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSubtitle)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'سترجع المهمة للمكتب لإسنادها لمصوّر آخر، وسيُبلَّغون بسببك.',
                style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody),
              ),
              AppTheme.gapHeightMedium,
              TextField(
                controller: ctrl,
                maxLines: 3,
                autofocus: true,
                style: const TextStyle(
                    color: AppTheme.textWhite, fontSize: AppTheme.fontSizeMedium),
                decoration: InputDecoration(
                  labelText: 'سبب الاعتذار *',
                  labelStyle: const TextStyle(color: AppTheme.textGrey),
                  hintText: 'مثال: عندي التزام طارئ بنفس الموعد',
                  hintStyle: const TextStyle(color: AppTheme.textGrey),
                  errorText: err,
                  filled: true,
                  fillColor: AppTheme.scaffoldBackground,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (err != null) setDlg(() => err = null);
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
                final txt = ctrl.text.trim();
                if (txt.isEmpty) {
                  setDlg(() => err = 'سبب الاعتذار مطلوب');
                  return;
                }
                Navigator.pop(ctx, txt);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.errorRed),
              child: const Text('تأكيد الاعتذار',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;

    final uid = context.read<AuthProvider>().userModel?.uid ?? '';
    final ok = await context
        .read<PhotographyProvider>()
        .declineTask(uid, task.id, reason);
    if (!mounted) return;
    final provider = context.read<PhotographyProvider>();
    _snack(ok
        ? 'تم الاعتذار — رجعت المهمة للمكتب'
        : ErrorUtils.arabicMessage(provider.error ?? 'TASK_DECLINE_FAILED'));
    if (ok) _load();
  }

  Future<void> _callRequester(PhotographyTaskModel task) async {
    final phone = task.requesterPhone.trim();
    if (phone.isEmpty) {
      _snack('رقم صاحب الطلب غير متوفر');
      return;
    }
    final launched = await launchUrl(Uri(scheme: 'tel', path: phone));
    if (!launched) _snack('تعذر فتح تطبيق الاتصال');
  }

  Future<void> _editSchedule(PhotographyTaskModel task) async {
    final now = DateTime.now();
    final current = task.tsScheduled?.toLocal();
    final initialDate = current != null && current.isAfter(now) ? current : now;
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: current != null
          ? TimeOfDay.fromDateTime(current)
          : TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;
    final scheduledAt = DateTime(
      date.year, date.month, date.day, time.hour, time.minute,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('تأكيد موعد التصوير',
            style: TextStyle(color: AppTheme.textWhite)),
        content: Text(
          'سيصبح موعد المهمة ${_fmtDate(scheduledAt)} وسيتم إشعار صاحب الطلب والإدارة.',
          style: const TextStyle(color: AppTheme.textGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('اعتماد الموعد'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final uid = context.read<AuthProvider>().userModel?.uid ?? '';
    final provider = context.read<PhotographyProvider>();
    final ok = await provider.rescheduleTask(uid, task.id, scheduledAt);
    if (!mounted) return;
    _snack(ok
        ? 'تم تعديل الموعد وإشعار صاحب الطلب والإدارة'
        : ErrorUtils.arabicMessage(provider.error ?? 'SCHEDULE_UPDATE_FAILED'));
    if (ok) _load();
  }

  Future<void> _pickMedia(String taskHash) async {
    final files = await StorageService().pickMultiImages(limit: 20);
    if (files.isNotEmpty) {
      setState(() {
        _tempMedia.putIfAbsent(taskHash, () => []).addAll(files);
      });
    }
  }

  Future<void> _takePhoto(String taskHash) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
    );
    if (file != null && mounted) {
      setState(() {
        _tempMedia.putIfAbsent(taskHash, () => []).add(file);
      });
    }
  }

  void _removeMedia(String taskHash, int index) {
    setState(() {
      _tempMedia[taskHash]?.removeAt(index);
    });
  }

  Future<void> _submitToOffice(PhotographyTaskModel task) async {
    final taskHash = task.id;
    final media = _tempMedia[taskHash];
    if (media == null || media.isEmpty) {
      _snack('يرجى رفع صورة واحدة على الأقل');
      return;
    }

    setState(() => _isUploading[taskHash] = true);

    try {
      final userId = context.read<AuthProvider>().userModel?.uid ?? '';
      final urls = await StorageService().uploadOfferImages(
        files: media,
        userId: userId,
        offerId: 'photography_${task.id}',
      );
      if (urls.isEmpty) {
        if (mounted) {
          setState(() => _isUploading[taskHash] = false);
          _snack('تعذر رفع الصور — تحقق من الاتصال وحاول مجدداً');
        }
        return;
      }
      // الدمج المحلي يحافظ على الصور السابقة عند إعادة تسليم مهمة مرفوضة.
      final allMedia = <String>{...task.media, ...urls}.toList();
      final notes = _notesControllers[taskHash]?.text.trim() ?? '';
      final provider = context.read<PhotographyProvider>();
      final ok = await provider.submitTask(
        photographerUid: userId,
        taskId: task.id,
        media: allMedia,
        photographerNote: notes,
      );

      if (!mounted) return;
      setState(() {
        _isUploading[taskHash] = false;
        if (ok) {
          _tempMedia.remove(taskHash);
          _notesControllers[taskHash]?.dispose();
          _notesControllers.remove(taskHash);
          _expandedTaskId = null;
        }
      });
      _snack(ok
          ? 'تم إرسال التصوير للمكتب ✓'
          : ErrorUtils.arabicMessage(provider.error ?? 'PHOTO_SUBMIT_FAILED'));
      if (ok) _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading[taskHash] = false);
      _snack(ErrorUtils.arabicMessage(e));
    }
  }

  // ─── البناء ───

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        leading: const AppBackButton(),
        backgroundColor: AppTheme.scaffoldBackground,
        title: const Text('مهام التصوير',
            style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: AppTheme.primaryGold), onPressed: _load),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppTheme.primaryGold,
          labelColor: AppTheme.primaryGold,
          unselectedLabelColor: AppTheme.textGrey,
          tabs: [
            Tab(text: 'الحالية (${_todayTasks.length})'),
            Tab(text: 'القادمة (${_postponedTasks.length})'),
            Tab(text: 'المنفذة (${_completedTasks.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGold))
          : _loadError != null
              ? _loadErrorView()
              : Column(
              children: [
                _summaryBar(),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      _buildTodayTab(),
                      _buildPostponedTab(),
                      _buildCompletedTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _loadErrorView() {
    return Center(
      child: Padding(
        padding: AppTheme.paddingAllLarge,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                color: AppTheme.errorRed, size: 42),
            AppTheme.gapHeightMedium,
            Text(_loadError ?? 'تعذر تحميل المهام',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textWhite)),
            AppTheme.gapHeightMedium,
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryBar() {
    final active = _allTasks.where((t) => t.isPending || t.isInProgress || t.isRejected).length;
    final waitingOffice = _allTasks.where((t) => t.isSubmitted).length;
    final done = _allTasks.where((t) => t.isApproved).length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: AppTheme.surfaceBlack,
      child: Row(
        children: [
          Expanded(child: _summaryItem('الحالية', active, AppTheme.infoBlue)),
          Expanded(child: _summaryItem('اليوم', _todayTasks.length, AppTheme.primaryGold)),
          Expanded(child: _summaryItem('لدى المكتب', waitingOffice, Colors.purple)),
          Expanded(child: _summaryItem('مكتملة', done, AppTheme.successGreen)),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, int value, Color color) {
    return Column(
      children: [
        Text('$value',
            style: TextStyle(
                color: color,
                fontSize: AppTheme.fontSizeSubtitle,
                fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(
                color: AppTheme.textGrey,
                fontSize: AppTheme.fontSizeCaption)),
      ],
    );
  }

  // ─── تبويب مهام اليوم ───

  Widget _buildTodayTab() {
    final tasks = _todayTasks;
    if (tasks.isEmpty) return _empty('لا توجد مهام حالية');
    return RefreshIndicator(
      color: AppTheme.primaryGold,
      onRefresh: _load,
      child: ListView.builder(
        padding: AppTheme.paddingAllMedium,
        itemCount: tasks.length,
        itemBuilder: (_, i) => _taskCard(tasks[i]),
      ),
    );
  }

  // ─── تبويب المؤجلة (مع تقويم) ───

  Widget _buildPostponedTab() {
    final tasks = _postponedTasks;
    if (tasks.isEmpty) return _empty('لا توجد مهام مؤجلة');

    // تجميع المهام حسب التاريخ للتقويم
    final tasksByDate = <DateTime, List<PhotographyTaskModel>>{};
    for (final t in tasks) {
      if (t.tsScheduled != null) {
        final local = t.tsScheduled!.toLocal();
        final key = DateTime(local.year, local.month, local.day);
        tasksByDate.putIfAbsent(key, () => []).add(t);
      }
    }

    // 💡 تحسين 2026-07-30: Pull-to-refresh كان مفقوداً من هذا التبويب
    return RefreshIndicator(
      color: AppTheme.primaryGold,
      onRefresh: _load,
      child: Column(children: [
      // تقويم بسيط — نعرض الأيام اللي فيها مهام
      Container(
        padding: AppTheme.paddingAllMedium,
        color: AppTheme.surfaceBlack,
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(
              icon: const Icon(Icons.chevron_right, color: AppTheme.primaryGold),
              onPressed: () => setState(() => _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1)),
            ),
            Text(
              '${_focusedDay.year} / ${_focusedDay.month}',
              style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeSubtitle),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_left, color: AppTheme.primaryGold),
              onPressed: () => setState(() => _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1)),
            ),
          ]),
          AppTheme.gapHeightSmall,
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tasksByDate.keys
                .where((date) => date.year == _focusedDay.year &&
                    date.month == _focusedDay.month)
                .map((date) {
              final isSelected = _selectedDay != null &&
                  date.year == _selectedDay!.year &&
                  date.month == _selectedDay!.month &&
                  date.day == _selectedDay!.day;
              final count = tasksByDate[date]!.length;
              return GestureDetector(
                onTap: () => setState(() => _selectedDay = date),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primaryGold : AppTheme.deepBlack,
                    borderRadius: AppTheme.radiusMedium,
                    border: Border.all(color: AppTheme.primaryGold.withOpacity(0.4)),
                  ),
                  child: Text(
                    '${date.day}/${date.month} ($count)',
                    style: TextStyle(
                      color: isSelected ? AppTheme.deepBlack : AppTheme.primaryGold,
                      fontWeight: FontWeight.bold,
                      fontSize: AppTheme.fontSizeBody,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ]),
      ),
      AppTheme.gapHeightSmall,
      Expanded(
        child: _selectedDayTasks.isEmpty
            ? _empty('اختر يوماً من الأعلى لعرض المهام')
            : ListView.builder(
                padding: AppTheme.paddingAllMedium,
                itemCount: _selectedDayTasks.length,
                itemBuilder: (_, i) => _taskCard(_selectedDayTasks[i]),
              ),
      ),
    ]));
  }

  // ─── تبويب المنفذة ───

  Widget _buildCompletedTab() {
    final tasks = _completedTasks;
    if (tasks.isEmpty) return _empty('لا توجد مهام منفذة');
    return RefreshIndicator(
      color: AppTheme.primaryGold,
      onRefresh: _load,
      child: ListView.builder(
        padding: AppTheme.paddingAllMedium,
        itemCount: tasks.length,
        itemBuilder: (_, i) => _completedCard(tasks[i]),
      ),
    );
  }

  // ─── بطاقة مهمة نشطة ───

  Future<void> _showTaskDetails(PhotographyTaskModel task) async {
    final d = task.offerDetails;
    String text(String key) => d[key]?.toString().trim() ?? '';
    final loc = d['loc'] is Map
        ? Map<String, dynamic>.from(d['loc'] as Map)
        : task.loc;
    final specs = d['specs'] is Map
        ? Map<String, dynamic>.from(d['specs'] as Map)
        : <String, dynamic>{};
    final type = int.tryParse(text('typ')) ?? 0;
    final transaction = int.tryParse(text('trx')) ?? 0;
    final price = num.tryParse(text('prc')) ?? 0;
    final currency = int.tryParse(text('cur')) ?? 1;
    final location = [loc['city'], loc['d']]
        .map((v) => v?.toString().trim() ?? '')
        .where((v) => v.isNotEmpty)
        .join(' — ');
    const labels = <String, String>{
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

    final rows = <Widget>[
      _detailRow('الحالة', task.statusLabel),
      _detailRow('نوع العرض', AppUtils.offerTypeText(type)),
      _detailRow('العملية', AppUtils.transactionText(transaction)),
      if (price > 0)
        _detailRow('السعر', AppUtils.formatPrice(price, currency: currency)),
      if (location.isNotEmpty) _detailRow('الموقع', location),
      if (text('descript').isNotEmpty)
        _detailRow('الوصف', text('descript')),
      if (task.requesterName.isNotEmpty)
        _detailRow('صاحب الطلب', task.requesterName),
      if (task.requesterPhone.isNotEmpty)
        _detailRow(
            'رقم التواصل', AppUtils.displayPhone(task.requesterPhone)),
      ...specs.entries.where((e) => e.value.toString().trim().isNotEmpty).map(
            (e) => _detailRow(labels[e.key] ?? 'تفصيل إضافي', e.value.toString()),
          ),
      if (task.tsScheduled != null)
        _detailRow('موعد التصوير', _fmtDate(task.tsScheduled!)),
      if (task.tsScheduled == null)
        _detailRow('موعد التصوير', 'لم تحدده الإدارة بعد'),
      if (task.notes.isNotEmpty) _detailRow('ملاحظات المكتب', task.notes),
    ];

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: Text(task.ttl.isEmpty ? 'تفاصيل مهمة التصوير' : task.ttl,
            style: const TextStyle(
                color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...rows,
                if (task.media.isNotEmpty) ...[
                  const Divider(color: Colors.white12),
                  const Text('الوسائط المرفوعة',
                      style: TextStyle(
                          color: AppTheme.primaryGold,
                          fontWeight: FontWeight.bold)),
                  AppTheme.gapHeightSmall,
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: task.media.map((url) => ClipRRect(
                      borderRadius: AppTheme.radiusSmall,
                      child: Image.network(
                        url,
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 88,
                          height: 88,
                          child: OfficeLogoPlaceholder(logoSize: 28),
                        ),
                      ),
                    )).toList(),
                  ),
                ],
              ],
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

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
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

  Widget _taskCard(PhotographyTaskModel task) {
    final taskHash = task.id;
    final isExpanded = _expandedTaskId == taskHash;
    final isUploading = _isUploading[taskHash] ?? false;
    final hasMedia = _tempMedia[taskHash]?.isNotEmpty ?? false;
    final color = _statusColor(task.sts);
    final offer = task.offerDetails;
    final offerLoc = offer['loc'] is Map
        ? Map<String, dynamic>.from(offer['loc'] as Map)
        : task.loc;
    final city = offerLoc['city']?.toString().trim() ?? '';
    final district = offerLoc['d']?.toString().trim() ?? '';
    final location = [city, district].where((v) => v.isNotEmpty).join(' — ');
    final description = offer['descript']?.toString().trim() ?? '';

    return Card(
      color: AppTheme.surfaceBlack,
      shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusLarge),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: AppTheme.paddingAllLarge,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // رأس البطاقة
          Row(children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.14),
              child: Icon(Icons.camera_alt, color: color),
            ),
            AppTheme.gapWidthSmall,
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(task.ttl.isEmpty ? 'مهمة تصوير' : task.ttl,
                  style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold)),
              Text(task.statusLabel, style: TextStyle(color: color, fontSize: AppTheme.fontSizeSmall)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: AppTheme.radiusXL,
              ),
              child: Text('${task.media.length} وسائط',
                  style: TextStyle(color: color, fontSize: AppTheme.fontSizeCaption)),
            ),
          ]),

          // معلومات
          if (task.notes.isNotEmpty) ...[
            AppTheme.gapHeightSmall,
            Container(
              width: double.infinity,
              padding: AppTheme.paddingAllSmall,
              decoration: BoxDecoration(
                color: AppTheme.primaryGold.withOpacity(0.08),
                borderRadius: AppTheme.radiusSmall,
                border: Border.all(color: AppTheme.primaryGold.withOpacity(0.2)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.description, size: 14, color: AppTheme.primaryGold),
                const SizedBox(width: 6),
                Expanded(child: Text(task.notes,
                    style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeSmall))),
              ]),
            ),
          ],
          if (task.requesterName.isNotEmpty || task.requesterPhone.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.person_outline,
                  color: AppTheme.infoBlue, size: 14),
              AppTheme.gapWidthXS,
              Expanded(
                child: Text(
                  'صاحب الطلب: ${task.requesterName}${task.requesterPhone.isNotEmpty ? ' — ${AppUtils.displayPhone(task.requesterPhone)}' : ''}',
                  style: const TextStyle(
                      color: AppTheme.infoBlue,
                      fontSize: AppTheme.fontSizeSmall,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ]),
          ],
          if (location.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.location_on_outlined,
                  color: AppTheme.textGrey, size: 14),
              AppTheme.gapWidthXS,
              Expanded(child: Text(location,
                  style: const TextStyle(
                      color: AppTheme.textGrey,
                      fontSize: AppTheme.fontSizeSmall))),
            ]),
          ],
          if (description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.home_work_outlined,
                  color: AppTheme.textGrey, size: 14),
              AppTheme.gapWidthXS,
              Expanded(child: Text(description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppTheme.textGrey,
                      fontSize: AppTheme.fontSizeSmall))),
            ]),
          ],
          if (task.tsScheduled != null) ...[
            AppTheme.gapHeightXS,
            Row(children: [
              const Icon(Icons.schedule, color: AppTheme.textGrey, size: 14),
              AppTheme.gapWidthXS,
              Text('الموعد: ${_fmtDate(task.tsScheduled!)}',
                  style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
            ]),
          ],
          // 💡 تحسين 2026-07-30: تنبيه المصوّر عند عدم تحديد موعد
          if (task.tsScheduled == null && (task.isPending || task.isInProgress)) ...[
            AppTheme.gapHeightXS,
            Row(children: [
              const Icon(Icons.schedule, color: Colors.amber, size: 14),
              AppTheme.gapWidthXS,
              const Text('بلا موعد محدد — نسّق مع المكتب',
                  style: TextStyle(color: Colors.amber, fontSize: AppTheme.fontSizeSmall)),
            ]),
          ],

          AppTheme.gapHeightSmall,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showTaskDetails(task),
                icon: const Icon(Icons.receipt_long_outlined,
                    color: AppTheme.primaryGold, size: 17),
                label: const Text('التفاصيل',
                    style: TextStyle(color: AppTheme.primaryGold)),
              ),
              if (task.requesterPhone.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _callRequester(task),
                  icon: const Icon(Icons.call_outlined,
                      color: AppTheme.successGreen, size: 17),
                  label: const Text('اتصال',
                      style: TextStyle(color: AppTheme.successGreen)),
                ),
              if (task.isPending || task.isInProgress || task.isRejected)
                OutlinedButton.icon(
                  onPressed: () => _editSchedule(task),
                  icon: const Icon(Icons.edit_calendar_outlined,
                      color: AppTheme.infoBlue, size: 17),
                  label: Text(task.tsScheduled == null ? 'تحديد الموعد' : 'تعديل الموعد',
                      style: const TextStyle(color: AppTheme.infoBlue)),
                ),
            ],
          ),

          // زر بدء المهمة أو واجهة الرفع
          if (!isExpanded && (task.isPending || task.isInProgress || task.isRejected)) ...[
            AppTheme.gapHeightSmall,
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () => _startTask(task),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('بدء المهمة'),
                  ),
                ),
                AppTheme.gapWidthSmall,
                // 🔄 مخرج للمصوّر عند التعذّر — ترجع المهمة للمكتب بدل ما تبقى
                // مسكّرة عليه بلا علم أحد (أُضيف 2026-07-30)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _declineTask(task),
                    icon: const Icon(Icons.event_busy,
                        color: AppTheme.errorRed, size: 18),
                    label: const Text('اعتذار',
                        style: TextStyle(color: AppTheme.errorRed)),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.errorRed)),
                  ),
                ),
              ],
            ),
          ],

          // واجهة رفع الصور (عند التوسيع)
          if (isExpanded) ...[
            const Divider(color: Colors.white12, height: 20),

            // 💡 تحسين 2026-07-30: عرض الصور الحقيقية بدلاً من أيقونة
            // كان Container بـ Icon(Icons.image) — المستخدم لا يرى ما اختار.
            // الآن Image.file(XFile.path) يعرض المحتوى الفعلي.
            if ((_tempMedia[taskHash]?.isNotEmpty ?? false))
              Wrap(
                spacing: 8, runSpacing: 8,
                children: _tempMedia[taskHash]!.asMap().entries.map((e) {
                  return Stack(clipBehavior: Clip.none, children: [
                    ClipRRect(
                      borderRadius: AppTheme.radiusSmall,
                      child: Image.file(
                        File(e.value.path),
                        width: 70, height: 70,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            borderRadius: AppTheme.radiusSmall,
                            border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3)),
                            color: AppTheme.inputBackground,
                          ),
                          child: const OfficeLogoPlaceholder(logoSize: 28),
                        ),
                      ),
                    ),
                    Positioned(
                      top: -6, right: -6,
                      child: GestureDetector(
                        onTap: () => _removeMedia(taskHash, e.key),
                        child: const CircleAvatar(
                          radius: 10,
                          backgroundColor: AppTheme.errorRed,
                          child: Icon(Icons.close, size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ]);
                }).toList(),
              ),
            AppTheme.gapHeightSmall,
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isUploading ? null : () => _takePhoto(taskHash),
                    icon: const Icon(Icons.photo_camera_outlined,
                        color: AppTheme.primaryGold),
                    label: const Text('الكاميرا',
                        style: TextStyle(color: AppTheme.primaryGold)),
                  ),
                ),
                AppTheme.gapWidthSmall,
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isUploading ? null : () => _pickMedia(taskHash),
                    icon: const Icon(Icons.photo_library_outlined,
                        color: AppTheme.primaryGold),
                    label: Text('المعرض (${_tempMedia[taskHash]?.length ?? 0})',
                        style: const TextStyle(color: AppTheme.primaryGold)),
                  ),
                ),
              ],
            ),
            AppTheme.gapHeightSmall,
            TextField(
              controller: _notesControllers.putIfAbsent(taskHash, () => TextEditingController(text: task.photographerNote)),
              maxLines: 2,
              style: const TextStyle(color: AppTheme.textWhite),
              decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
            ),
            AppTheme.gapHeightSmall,
            if (hasMedia && !isUploading)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _submitToOffice(task),
                  icon: const Icon(Icons.send),
                  label: const Text('إرسال إلى المكتب'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                ),
              ),
            if (isUploading)
              const Center(child: Padding(
                padding: AppTheme.paddingAllMedium,
                child: CircularProgressIndicator(color: AppTheme.primaryGold),
              )),
          ],

          // ملاحظة المكتب (للمرفوضة)
          if (task.officeNote.isNotEmpty) ...[
            AppTheme.gapHeightSmall,
            Text('ملاحظة المكتب: ${task.officeNote}',
                style: const TextStyle(color: AppTheme.warningOrange, fontSize: AppTheme.fontSizeSmall)),
          ],

          // إعادة الرفع (للمرفوضة)
          if (task.isRejected && !isExpanded) ...[
            AppTheme.gapHeightSmall,
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _startTask(task),
                icon: const Icon(Icons.replay),
                label: const Text('إعادة رفع التصوير'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warningOrange),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  // ─── بطاقة مهمة منفذة ───

  Widget _completedCard(PhotographyTaskModel task) {
    final color = _statusColor(task.sts);
    return Card(
      color: AppTheme.surfaceBlack,
      shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusLarge),
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => _showTaskDetails(task),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.14),
          child: Icon(
            task.isApproved ? Icons.check : (task.isRejected ? Icons.close : Icons.schedule),
            color: color,
          ),
        ),
        title: Text(task.ttl.isEmpty ? 'مهمة تصوير' : task.ttl,
            style: const TextStyle(color: AppTheme.textWhite)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(task.statusLabel, style: TextStyle(color: color, fontSize: AppTheme.fontSizeSmall)),
          Text('${task.media.length} وسائط',
              style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
          if (task.tsDone != null)
            Text('أُغلقت: ${_fmtDate(task.tsDone!)}',
                style: const TextStyle(
                    color: AppTheme.textGrey,
                    fontSize: AppTheme.fontSizeCaption)),
          if (task.isSubmitted)
            const Text('بانتظار معالجة المكتب',
                style: TextStyle(color: Colors.purple, fontSize: AppTheme.fontSizeCaption)),
        ]),
        trailing: const Icon(Icons.chevron_left,
            color: AppTheme.primaryGold),
      ),
    );
  }

  // ─── مساعدات ───

  Color _statusColor(int status) {
    switch (status) {
      case 0: return AppTheme.warningOrange;
      case 1: return AppTheme.infoBlue;
      case 2: return AppTheme.primaryGold;
      case 3: return AppTheme.successGreen;
      case 4: return AppTheme.errorRed;
      default: return AppTheme.textGrey;
    }
  }

  Widget _empty(String msg) {
    return Center(child: Text(msg, style: const TextStyle(color: AppTheme.textGrey)));
  }

  String _fmtDate(DateTime d) {
    final l = d.toLocal();
    return '${l.year}/${l.month.toString().padLeft(2, '0')}/${l.day.toString().padLeft(2, '0')} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  void _snack(String msg) {
    if (!mounted) return;
    AppTheme.showSnackBar(context, SnackBar(content: Text(msg)));
  }
}

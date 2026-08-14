import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/expediting_task_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/legal_provider.dart';
import '../../widgets/e2e.dart';
import 'expediter_task_detail_screen.dart';

class ExpediterTasksScreen extends StatefulWidget {
  const ExpediterTasksScreen({super.key});

  @override
  State<ExpediterTasksScreen> createState() => _ExpediterTasksScreenState();
}

class _ExpediterTasksScreenState extends State<ExpediterTasksScreen> {
  // 🔎 فلترة (2026-08-14): 14 مهمة مختلطة — معتمدة وجارية ومنتظرة معاً،
  // فيبحث المعقّب عن مهام اليوم وسط المنجزة.
  int _filter = -1; // -1 الكل · 0 جديدة · 1 جارية · 2 بانتظار المراجعة · 3 معتمدة

  List<ExpeditingTaskModel> _apply(List<ExpeditingTaskModel> all) =>
      _filter == -1 ? all : all.where((t) => t.status == _filter).toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final user = context.read<AuthProvider>().userModel;
    if (user != null) {
      final legal = context.read<LegalProvider>();
      // إلزامي: بقية نداءات المعقّب (تحديث بند/إتمام مهمة) تعتمد الهوية
      // المحفوظة، وبدونها ترتد USER_UID_REQUIRED بصمت.
      legal.setActor(user.uid);
      await legal.getExpeditingTasks(userUid: user.uid);
    }
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
        content: const Text('هل تريد تسجيل الخروج من حساب المعقب؟', style: TextStyle(color: AppTheme.textGrey)),
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

  Widget _filterBar(List<ExpeditingTaskModel> all) {
    int cnt(int st) => st == -1 ? all.length : all.where((t) => t.status == st).length;
    const chips = <(int, String)>[
      (-1, 'الكل'), (0, 'جديدة'), (1, 'جارية'), (2, 'بانتظار المراجعة'), (3, 'معتمدة'),
    ];
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        children: [
          for (final c in chips)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: ChoiceChip(
                selected: _filter == c.$1,
                onSelected: (_) => setState(() => _filter = c.$1),
                label: Text('${c.$2} (${cnt(c.$1)})',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _filter == c.$1 ? Colors.black : AppTheme.textGrey)),
                selectedColor: AppTheme.primaryGold,
                backgroundColor: AppTheme.surfaceBlack,
                shape: RoundedRectangleBorder(
                  borderRadius: AppTheme.radiusXL,
                  side: BorderSide(
                      color: _filter == c.$1 ? AppTheme.primaryGold : Colors.white12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = context.watch<LegalProvider>().expeditingTasks;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: Builder(builder: (_) {
          // 🔔 شارة المهام غير المنجزة — تلفت نظره فور الفتح
          final open = tasks.where((t) => t.status < 2).length;
          return E2E(
            id: 'e2e_screen_expediter_tasks',
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('مهام التعقيب 🏃'),
              if (open > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: AppTheme.errorRed, borderRadius: BorderRadius.circular(12)),
                  child: Text('$open',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ]),
          );
        }),
        backgroundColor: AppTheme.scaffoldBackground,
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined, color: AppTheme.primaryGold),
            tooltip: 'تفاصيل حسابي',
            onPressed: _openAccountDetails,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryGold),
            tooltip: 'تحديث المهام',
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'تسجيل خروج',
            onPressed: _logout,
          ),
        ],
      ),
      body: tasks.isEmpty && context.watch<LegalProvider>().error != null
          ? Center(
              child: Padding(
                padding: AppTheme.paddingAllXL,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off, size: 56, color: AppTheme.errorRed),
                  AppTheme.gapHeightMedium,
                  const Text('تعذّر جلب المهام',
                      style: TextStyle(color: AppTheme.errorRed, fontSize: AppTheme.fontSizeSubtitle, fontWeight: FontWeight.bold)),
                  AppTheme.gapHeightSmall,
                  Text(context.read<LegalProvider>().error ?? '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
                  AppTheme.gapHeightLarge,
                  ElevatedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh, color: Colors.black),
                    label: const Text('إعادة المحاولة',
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
                  ),
                ]),
              ),
            )
          : tasks.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.assignment_late, size: 64, color: AppTheme.textGrey.withOpacity(0.4)),
                  AppTheme.gapHeightLarge,
                  const Text(
                    'لا توجد مهام تعقيب حالياً',
                    style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSubtitle),
                  ),
                  AppTheme.gapHeightSmall,
                  const Text(
                    'عند إحالة المحامي مهمة لك، ستظهر هنا',
                    style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody),
                  ),
                ],
              ),
            )
          : Column(children: [
              _filterBar(tasks),
              Expanded(
                child: Builder(builder: (_) {
                  final shown = _apply(tasks);
                  if (shown.isEmpty) {
                    return ListView(children: const [
                      SizedBox(height: 60),
                      Center(
                        child: Text('لا مهام في هذا التصنيف',
                            style: TextStyle(color: AppTheme.textGrey, fontSize: 14)),
                      ),
                    ]);
                  }
                  return RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final task = shown[i];
                        return _TaskCard(
                          task: task,
                          onTap: () => context.push('/expediter/task-detail', extra: task),
                        );
                      },
                    ),
                  );
                }),
              ),
            ]),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final ExpeditingTaskModel task;
  final VoidCallback onTap;

  const _TaskCard({required this.task, required this.onTap});

  Color _statusColor(int sts) {
    switch (sts) {
      case 0: return AppTheme.warningOrange;
      case 1: return AppTheme.infoBlue;
      case 2: return AppTheme.successGreen;
      case 3: return AppTheme.successGreen;
      default: return AppTheme.textGrey;
    }
  }

  String _statusText(int sts) {
    switch (sts) {
      case 0: return 'قيد الانتظار';
      case 1: return 'قيد الاستخراج';
      case 2: return 'مكتملة';
      case 3: return 'معتمدة';
      default: return 'غير معروف';
    }
  }

  int _doneCount() {
    return task.checklist.where((c) => c.status == 2).length;
  }

  /// ⏰ عمر المهمة بالأيام — مهمة عمرها أسبوع كانت تبدو كمهمة اليوم
  int get _ageDays {
    final c = task.createdAt;
    if (c == null) return 0;
    return DateTime.now().difference(c).inDays;
  }

  /// متأخرة = لم تُنجز بعد ومضى عليها 3 أيام فأكثر
  bool get _isLate => task.status < 2 && _ageDays >= 3;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(task.status);
    final done = _doneCount();
    final total = task.checklist.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTheme.radiusLarge,
        child: Container(
          padding: AppTheme.paddingAllLarge,
          decoration: BoxDecoration(
            color: AppTheme.surfaceBlack,
            borderRadius: AppTheme.radiusLarge,
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.assignment, color: color, size: 20),
                  AppTheme.gapWidthSmall,
                  Expanded(
                    child: Text(
                      _statusText(task.status),
                      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeMedium),
                    ),
                  ),
                  if (_isLate) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.errorRed.withOpacity(0.15),
                        borderRadius: AppTheme.radiusXL,
                        border: Border.all(color: AppTheme.errorRed.withOpacity(0.5)),
                      ),
                      child: Text('⏰ متأخرة $_ageDays يوم',
                          style: const TextStyle(
                              color: AppTheme.errorRed, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    task.itemType == 0 ? '🏠 عقار' : '🚗 سيارة',
                    style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeSmall),
                  ),
                ],
              ),
              AppTheme.gapHeightSmall,
              if (task.targetPropertyNum.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'رقم العقار: ${task.targetPropertyNum} | المنطقة: ${task.targetZone}',
                    style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody),
                  ),
                ),
              Row(
                children: [
                  Icon(Icons.checklist, color: AppTheme.primaryGold, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '$done / $total وثائق مستخرجة',
                    style: TextStyle(
                      color: done == total ? AppTheme.successGreen : AppTheme.textGrey,
                      fontSize: AppTheme.fontSizeBody,
                    ),
                  ),
                  AppTheme.gapWidthSmall,
                  // شريط تقدّم مرئي — يقيس إنجازه بنظرة واحدة
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : done / total,
                        minHeight: 5,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation(
                            done == total ? AppTheme.successGreen : AppTheme.primaryGold),
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_left, color: AppTheme.textGrey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    final tasks = context.watch<LegalProvider>().expeditingTasks;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const E2E(id: 'e2e_screen_expediter_tasks', child: Text('مهام تعقيب المعاملات 🏃')),
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
      body: tasks.isEmpty
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
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: AppTheme.paddingAllLarge,
                itemCount: tasks.length,
                itemBuilder: (_, i) {
                  final task = tasks[i];
                  return _TaskCard(
                    task: task,
                    onTap: () => context.push('/expediter/task-detail', extra: task),
                  );
                },
              ),
            ),
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
                  const Spacer(),
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

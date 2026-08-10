import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/appointment_model.dart';
import '../../core/theme/app_theme.dart';

/// 📅 إدارة المواعيد — عرض الكل + فلترة بالحالة + فرض/إلغاء
class AppointmentsManagementScreen extends StatefulWidget {
  const AppointmentsManagementScreen({super.key});

  @override
  State<AppointmentsManagementScreen> createState() =>
      _AppointmentsManagementScreenState();
}

class _AppointmentsManagementScreenState
    extends State<AppointmentsManagementScreen> {
  List<AppointmentModel> _all = [];
  bool _loading = true;
  int _filter = -1; // -1=الكل

  static const _statusLabels = {
    0: 'معلّق',
    1: 'مؤكّد',
    2: 'مكتمل',
    3: 'ملغى',
    4: 'مرفوض',
    5: 'لم يحضر',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final adminUid = context.read<AuthProvider>().userModel?.uid ?? '';
    final list = await context.read<AdminProvider>().getAllAppointments(adminUid);
    if (mounted) {
      setState(() {
        _all = list;
        _loading = false;
      });
    }
  }

  List<AppointmentModel> get _filtered =>
      _filter == -1 ? _all : _all.where((a) => a.sts == _filter).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('إدارة المواعيد'),
        backgroundColor: AppTheme.scaffoldBackground,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryGold),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                _chip('الكل', -1),
                ..._statusLabels.entries
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _chip(e.value, e.key),
                        )),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryGold))
                : _filtered.isEmpty
                    ? const Center(
                        child: Text('لا توجد مواعيد',
                            style: TextStyle(color: AppTheme.textGrey)))
                    : RefreshIndicator(
                        color: AppTheme.primaryGold,
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: AppTheme.paddingAllMedium,
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) => _apptTile(_filtered[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, int value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label,
            style: TextStyle(
              color: selected ? AppTheme.deepBlack : AppTheme.textWhite,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            )),
        selected: selected,
        selectedColor: AppTheme.primaryGold,
        backgroundColor: AppTheme.surfaceBlack,
        checkmarkColor: AppTheme.deepBlack,
        side: BorderSide(color: AppTheme.primaryGold.withOpacity(0.3)),
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  Color _statusColor(int sts) {
    switch (sts) {
      case 1:
        return AppTheme.successGreen;
      case 2:
        return AppTheme.primaryGold;
      case 3:
        return AppTheme.textGrey;
      case 4:
        return AppTheme.errorRed;
      case 5:
        return Colors.deepOrange;
      default:
        return AppTheme.warningOrange;
    }
  }

  Widget _apptTile(AppointmentModel a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.event,
                      color: AppTheme.primaryGold, size: 18),
                  const SizedBox(width: 6),
                  Text(_fmtDate(a.dt),
                      style: const TextStyle(
                          color: AppTheme.textWhite,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor(a.sts).withOpacity(0.15),
                  borderRadius: AppTheme.radiusSmall,
                  border: Border.all(color: _statusColor(a.sts).withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (a.iForce == 1) ...[
                      const Icon(Icons.gavel, size: 11, color: AppTheme.primaryGold),
                      const SizedBox(width: 3),
                    ],
                    Text(_statusLabels[a.sts] ?? '—',
                        style: TextStyle(
                            color: _statusColor(a.sts), fontSize: AppTheme.fontSizeCaption)),
                  ],
                ),
              ),
            ],
          ),
          AppTheme.gapHeightSmall,
          Text('العرض: ${_short(a.offId)}',
              style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
          if (a.supervisorUid != null && a.supervisorUid!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(children: [
                const Icon(Icons.support_agent, color: AppTheme.primaryGold, size: 12),
                AppTheme.gapWidthXS,
                Text('المشرف: ${_short(a.supervisorUid!)}',
                    style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeCaption)),
              ]),
            ),
          if (a.neogRounds > 0)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('جولات التفاوض: ${a.neogRounds}/5',
                  style: const TextStyle(color: AppTheme.warningOrange, fontSize: AppTheme.fontSizeCaption)),
            ),
          if (a.cnlRsn != null && a.cnlRsn!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('سبب الإلغاء: ${a.cnlRsn}',
                  style: const TextStyle(color: AppTheme.errorRed, fontSize: AppTheme.fontSizeCaption)),
            ),
          const Divider(color: Colors.white12, height: 18),
          // ✅ Fix for Bug #16: استخدام Wrap بدلاً من Row لتجنب overflow
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              if (a.sts == 0 || a.sts == 1)
                TextButton.icon(
                  onPressed: () => _force(a),
                  icon: const Icon(Icons.gavel, size: 16),
                  label: const Text('فرض'),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.primaryGold),
                ),
              if (a.sts != 2)
                TextButton.icon(
                  onPressed: () => _setStatus(a, 2),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('إكمال'),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.successGreen),
                ),
              if (a.sts != 3)
                TextButton.icon(
                  onPressed: () => _setStatus(a, 3),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('إلغاء'),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.textGrey),
                ),
              if (a.sts != 5)
                TextButton.icon(
                  onPressed: () => _setStatus(a, 5),
                  icon: const Icon(Icons.person_off, size: 16),
                  label: const Text('عدم حضور'),
                  style: TextButton.styleFrom(foregroundColor: Colors.deepOrange),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _setStatus(AppointmentModel a, int status) async {
    final adminUid = context.read<AuthProvider>().userModel?.uid ?? '';
    if (await context
        .read<AdminProvider>()
        .updateAppointmentStatus(adminUid, a.id, status)) {
      _snack('تم تحديث حالة الموعد');
      _load();
    }
  }

  Future<void> _force(AppointmentModel a) async {
    final adminId = context.read<AuthProvider>().userModel?.uid ?? '';
    if (await context.read<AdminProvider>().forceAppointment(a.id, adminId)) {
      _snack('تم فرض الموعد');
      _load();
    }
  }

  String _short(String s) => s.length >= 8 ? s.substring(0, 8) : s;
  String _fmtDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  void _snack(String msg) {
    if (!mounted) return;
    AppTheme.showSnackBar(context, SnackBar(content: Text(msg)));
  }
}

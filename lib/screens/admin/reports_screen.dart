import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/report_model.dart';
import '../../core/theme/app_theme.dart';

/// 🚩 إدارة التبليغات — عرض البلاغات + اتخاذ إجراء
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List<ReportModel> _all = [];
  bool _loading = true;
  int _filter = 0; // 0=مفتوح(افتراضي), -1=الكل, 1=معالَج

  static const _tgtTypes = {
    0: 'مستخدم',
    1: 'عرض',
    2: 'طلب',
    3: 'موعد',
    4: 'استشارة قانونية',
  };
  static const _actions = {
    0: 'لا إجراء',
    1: 'تحذير',
    2: 'تجميد',
    3: 'حظر',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final adminUid = context.read<AuthProvider>().userModel?.uid ?? '';
    final list = await context.read<AdminProvider>().getAllReports(adminUid);
    if (mounted) {
      setState(() {
        _all = list;
        _loading = false;
      });
    }
  }

  List<ReportModel> get _filtered =>
      _filter == -1 ? _all : _all.where((r) => r.sts == _filter).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('التبليغات'),
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
                _chip('مفتوح', 0),
                _chip('الكل', -1),
                _chip('معالَج', 1),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryGold))
                : _filtered.isEmpty
                    ? const Center(
                        child: Text('لا توجد تبليغات',
                            style: TextStyle(color: AppTheme.textGrey)))
                    : RefreshIndicator(
                        color: AppTheme.primaryGold,
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: AppTheme.paddingAllMedium,
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) => _reportTile(_filtered[i]),
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

  Widget _reportTile(ReportModel r) {
    final handled = r.sts == 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(
            color: handled
                ? AppTheme.primaryGold.withOpacity(0.15)
                : AppTheme.errorRed.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(handled ? Icons.check_circle : Icons.flag,
                      color: handled ? AppTheme.successGreen : AppTheme.errorRed,
                      size: 18),
                  const SizedBox(width: 6),
                  Text('بلاغ على ${_tgtTypes[r.tgtTp] ?? '—'}',
                      style: const TextStyle(
                          color: AppTheme.textWhite,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              Text(r.tsCrt.toString().split(' ').first,
                  style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
            ],
          ),
          AppTheme.gapHeightSmall,
          _row('المُبلِّغ', _short(r.repUid)),
          _row('الهدف', _short(r.tgtId)),
          if (r.det.isNotEmpty) _row('التفاصيل', r.det),
          if (handled) ...[
            const Divider(color: Colors.white12, height: 18),
            _row('الإجراء المتخذ', _actions[r.act] ?? '—', highlight: true),
            if (r.note.isNotEmpty) _row('ملاحظة', r.note),
          ] else ...[
            const Divider(color: Colors.white12, height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: () => _actionDialog(r),
                icon: const Icon(Icons.gavel, size: 18),
                label: const Text('اتخاذ إجراء'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _actionDialog(ReportModel r) async {
    int selectedAction = 0;
    final noteCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: AppTheme.surfaceBlack,
          title: const Text('اتخاذ إجراء',
              style: TextStyle(color: AppTheme.primaryGold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ..._actions.entries.map((e) => RadioListTile<int>(
                    title: Text(e.value,
                        style: const TextStyle(color: AppTheme.textWhite)),
                    value: e.key,
                    groupValue: selectedAction,
                    onChanged: (value) => setSt(() {
                      selectedAction = value ?? 0;
                    }),
                    activeColor: AppTheme.primaryGold,
                    dense: true,
                  )),
              AppTheme.gapHeightSmall,
              TextField(
                controller: noteCtrl,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء',
                    style: TextStyle(color: AppTheme.textGrey))),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('تنفيذ')),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      final adminId = context.read<AuthProvider>().userModel?.uid ?? '';
      final admin = context.read<AdminProvider>();
      // 1) تسجيل القرار على البلاغ
      final ok = await admin.handleReport(r.id, selectedAction, adminId,
          note: noteCtrl.text.trim());
      // 2) تطبيق الإجراء على المستخدم المستهدف إن لزم
      if (ok && r.tgtUid.isNotEmpty) {
        if (selectedAction == 2) {
          await admin.freezeUser(adminId, r.tgtUid, 'إجراء على بلاغ');
        } else if (selectedAction == 3) {
          await admin.banUser(adminId, r.tgtUid, 'إجراء على بلاغ');
        }
      }
      if (ok) {
        _snack('تم تنفيذ الإجراء');
        _load();
      }
    }
  }

  Widget _row(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody)),
          AppTheme.gapWidthMedium,
          Flexible(
            child: Text(value,
                textAlign: TextAlign.left,
                style: TextStyle(
                    color: highlight ? AppTheme.primaryGold : AppTheme.textWhite,
                    fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
                    fontSize: AppTheme.fontSizeBody)),
          ),
        ],
      ),
    );
  }

  String _short(String s) => s.length >= 8 ? s.substring(0, 8) : s;

  void _snack(String msg) {
    if (!mounted) return;
    AppTheme.showSnackBar(context, SnackBar(content: Text(msg)));
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/legal_provider.dart';

/// ⚖️ إدارة الاستشارات القانونية — شاشة الإدارة (أُضيفت 2026-08-14)
///
/// الفجوة التي تسدّها: بعد اعتذار كل المحامين كانت الاستشارة تبقى **يتيمة
/// للأبد** — لا شاشة تعرضها ولا أداة لإسنادها، والعميل دفع ولم يحصل على شيء.
///
/// قرار المالك: الإدارة تتواصل مع المحامين خارج التطبيق ثم:
///   • تُسند الطلب يدوياً لمن يقبله، أو
///   • تمنح «رصيد استشارة» (المبلغ يبقى بالخزينة والعميل لا يدفع ثانيةً)، أو
///   • تتواصل مع العميل لإعادة المبلغ خارج التطبيق.
class LegalConsultationsAdminScreen extends StatefulWidget {
  const LegalConsultationsAdminScreen({super.key});

  @override
  State<LegalConsultationsAdminScreen> createState() =>
      _LegalConsultationsAdminScreenState();
}

class _LegalConsultationsAdminScreenState
    extends State<LegalConsultationsAdminScreen> {
  bool _loading = true;
  bool _onlyOrphan = false;
  int _filter = -1; // -1 الكل · 0 بانتظار · 1 مؤكدة · 5 بانتظار العميل · 2 مكتملة · 3 ملغاة

  static const _statusNames = {
    0: 'بانتظار المحامي',
    1: 'مؤكدة',
    2: 'مكتملة',
    3: 'ملغاة',
    4: 'مرفوضة',
    5: 'بانتظار بيانات العميل',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final legal = context.read<LegalProvider>();
    legal.setActor(context.read<AuthProvider>().userModel?.uid ?? '');
    await legal.fetchAdminConsultations(onlyOrphan: _onlyOrphan);
    if (mounted) setState(() => _loading = false);
  }

  Color _statusColor(int s) => switch (s) {
        0 => AppTheme.warningOrange,
        1 => AppTheme.successGreen,
        2 => Colors.teal,
        5 => AppTheme.infoBlue,
        _ => AppTheme.textGrey,
      };

  void _snack(String m, {Color? bg}) {
    if (!mounted) return;
    AppTheme.showSnackBar(
        context, SnackBar(content: Text(m), backgroundColor: bg ?? AppTheme.primaryGold));
  }

  Future<void> _showV2Details() async {
    final legal = context.read<LegalProvider>();
    final details = await legal.fetchAdminV2Details();
    if (!mounted) return;
    final intents = details['intents'] ?? const <Map<String, dynamic>>[];
    final holds = details['reservations'] ?? const <Map<String, dynamic>>[];
    final sessions = details['sessions'] ?? const <Map<String, dynamic>>[];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceBlack,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        maxChildSize: 0.95,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: AppTheme.paddingAllLarge,
          children: [
            const Text('تفاصيل نظام الاستشارة V2',
                style: TextStyle(color: AppTheme.primaryGold,
                    fontSize: 18, fontWeight: FontWeight.bold)),
            AppTheme.gapHeightLarge,
            Text('طلبات الدفع والحالات (${intents.length})',
                style: const TextStyle(color: AppTheme.infoBlue,
                    fontWeight: FontWeight.bold)),
            ...intents.map((i) => ListTile(
              dense: true,
              title: Text('${i['flow']} — ${i['status']}',
                  style: const TextStyle(color: AppTheme.textWhite)),
              subtitle: Text((i['failure_code'] ?? i['id']).toString(),
                  style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)),
            )),
            const Divider(color: Colors.white12),
            Text('الحجوزات الفعالة (${holds.length})',
                style: const TextStyle(color: AppTheme.warningOrange,
                    fontWeight: FontWeight.bold)),
            ...holds.map((h) => ListTile(
              dense: true,
              title: Text('${h['status']} — ${h['slot_start']}',
                  style: const TextStyle(color: AppTheme.textWhite)),
              subtitle: Text((h['id'] ?? '').toString(),
                  style: const TextStyle(color: AppTheme.textGrey, fontSize: 10)),
              trailing: h['status'] == 'held'
                  ? TextButton(
                      onPressed: () async {
                        final ok = await legal.adminReleaseReservation(h['id'].toString());
                        if (ctx.mounted && ok) Navigator.pop(ctx);
                        if (ok) {
                          _snack('تم تحرير الحجز، وسيختار المستخدم موعداً جديداً');
                          _load();
                        }
                      },
                      child: const Text('تحرير',
                          style: TextStyle(color: AppTheme.errorRed)),
                    )
                  : null,
            )),
            const Divider(color: Colors.white12),
            Text('الجلسات الحالية (${sessions.length})',
                style: const TextStyle(color: AppTheme.successGreen,
                    fontWeight: FontWeight.bold)),
            ...sessions.map((s) => ListTile(
              dense: true,
              title: Text('${s['kind']} — ${s['status']}',
                  style: const TextStyle(color: AppTheme.textWhite)),
              subtitle: Text('النهاية: ${s['ends_at'] ?? 'لم تبدأ'}',
                  style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)),
            )),
            if (intents.isEmpty && holds.isEmpty && sessions.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('لا توجد حالات V2 تحتاج متابعة',
                    style: TextStyle(color: AppTheme.textGrey))),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final legal = context.watch<LegalProvider>();
    final all = legal.adminConsultations;
    final overview = legal.adminV2Overview;
    final intents = overview['intents'] is Map
        ? Map<String, dynamic>.from(overview['intents'] as Map)
        : <String, dynamic>{};
    final sessions = overview['sessions'] is Map
        ? Map<String, dynamic>.from(overview['sessions'] as Map)
        : <String, dynamic>{};
    final reservations = overview['reservations'] is Map
        ? Map<String, dynamic>.from(overview['reservations'] as Map)
        : <String, dynamic>{};
    final orphanCount =
        all.where((c) => c['lawyer_uid'] == null && (c['status'] ?? 0) == 0).length;
    final shown = _filter == -1
        ? all
        : all.where((c) => (c['status'] ?? 0) == _filter).toList();

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('⚖️ الاستشارات القانونية'),
        backgroundColor: AppTheme.scaffoldBackground,
        actions: [
          IconButton(
            tooltip: 'تفاصيل V2',
            icon: const Icon(Icons.account_tree_outlined,
                color: AppTheme.infoBlue),
            onPressed: _showV2Details,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryGold),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(children: [
        // 🚨 تنبيه الطلبات اليتيمة — أهم ما تحتاجه الإدارة
        if (orphanCount > 0 && !_onlyOrphan)
          GestureDetector(
            onTap: () {
              setState(() => _onlyOrphan = true);
              _load();
            },
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: AppTheme.paddingAllMedium,
              decoration: BoxDecoration(
                color: AppTheme.errorRed.withOpacity(0.12),
                borderRadius: AppTheme.radiusMedium,
                border: Border.all(color: AppTheme.errorRed.withOpacity(0.5)),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber, color: AppTheme.errorRed),
                AppTheme.gapWidthSmall,
                Expanded(
                  child: Text(
                    '$orphanCount طلب بلا محامٍ — يحتاج تدخلك',
                    style: const TextStyle(
                        color: AppTheme.errorRed,
                        fontWeight: FontWeight.bold,
                        fontSize: AppTheme.fontSizeBody),
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: AppTheme.errorRed, size: 14),
              ]),
            ),
          ),

        if (overview.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            padding: AppTheme.paddingAllMedium,
            decoration: BoxDecoration(
              color: AppTheme.infoBlue.withOpacity(0.08),
              borderRadius: AppTheme.radiusMedium,
              border: Border.all(color: AppTheme.infoBlue.withOpacity(0.3)),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                Text('دفعات تنتظر: ${intents['payment_pending'] ?? 0}',
                    style: const TextStyle(color: AppTheme.textWhite, fontSize: 11)),
                Text('تحتاج موعداً: ${intents['payment_needs_slot'] ?? 0}',
                    style: const TextStyle(color: AppTheme.warningOrange, fontSize: 11)),
                Text('جلسات جاهزة: ${sessions['ready'] ?? 0}',
                    style: const TextStyle(color: AppTheme.infoBlue, fontSize: 11)),
                Text('انتظار انضمام: ${sessions['join_window'] ?? 0}',
                    style: const TextStyle(color: AppTheme.warningOrange, fontSize: 11)),
                Text('جلسات نشطة: ${sessions['active'] ?? 0}',
                    style: const TextStyle(color: AppTheme.successGreen, fontSize: 11)),
                Text('حجوزات مؤقتة: ${reservations['held'] ?? 0}',
                    style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)),
              ],
            ),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(children: [
            Expanded(
              child: SizedBox(
                height: 36,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final f in const [
                    (-1, 'الكل'), (0, 'بانتظار'), (1, 'مؤكدة'),
                    (5, 'بانتظار العميل'), (2, 'مكتملة'), (3, 'ملغاة'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ChoiceChip(
                        selected: _filter == f.$1,
                        onSelected: (_) => setState(() => _filter = f.$1),
                        label: Text(f.$2,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _filter == f.$1 ? Colors.black : AppTheme.textGrey)),
                        selectedColor: AppTheme.primaryGold,
                        backgroundColor: AppTheme.surfaceBlack,
                      ),
                    ),
                ]),
              ),
            ),
            FilterChip(
              selected: _onlyOrphan,
              onSelected: (v) {
                setState(() => _onlyOrphan = v);
                _load();
              },
              label: const Text('بلا محامٍ',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              selectedColor: AppTheme.errorRed.withOpacity(0.25),
              backgroundColor: AppTheme.surfaceBlack,
              checkmarkColor: AppTheme.errorRed,
              labelStyle: TextStyle(
                  color: _onlyOrphan ? AppTheme.errorRed : AppTheme.textGrey),
            ),
          ]),
        ),

        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGold))
              : shown.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(children: const [
                        SizedBox(height: 80),
                        Center(
                          child: Text('لا توجد استشارات',
                              style: TextStyle(color: AppTheme.textGrey, fontSize: 15)),
                        ),
                      ]),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        itemCount: shown.length,
                        itemBuilder: (_, i) => _card(shown[i]),
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> c) {
    final status = (c['status'] ?? 0) as int;
    final sType = (c['service_type'] ?? 0) as int;
    final orphan = c['lawyer_uid'] == null && status == 0;
    final client = (c['client'] as Map?) ?? {};
    final clientName = (client['nm'] ?? 'عميل').toString();
    final clientPhone = (client['ph'] ?? '').toString();
    final alias = (c['lawyer_alias'] ?? '').toString();
    final reassign = (c['reassign_count'] ?? 0) as int;
    final color = orphan ? AppTheme.errorRed : _statusColor(status);
    final dt = DateTime.tryParse(c['ts_crt']?.toString() ?? '')?.toLocal();
    final when = dt == null
        ? ''
        : '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: AppTheme.paddingAllMedium,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(sType == 1 ? Icons.business : Icons.phone_in_talk,
              color: AppTheme.primaryGold, size: 17),
          const SizedBox(width: 5),
          Expanded(
            child: Text(sType == 1 ? 'جلسة حضورية' : 'استشارة هاتفية',
                style: const TextStyle(
                    color: AppTheme.textWhite,
                    fontWeight: FontWeight.bold,
                    fontSize: AppTheme.fontSizeBody)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: color.withOpacity(0.15), borderRadius: AppTheme.radiusXL),
            child: Text(orphan ? '🚨 بلا محامٍ' : (_statusNames[status] ?? '—'),
                style: TextStyle(
                    color: color,
                    fontSize: AppTheme.fontSizeCaption,
                    fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 5),
        Text((c['subject'] ?? '').toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.textGrey, fontSize: 12)),
        const SizedBox(height: 5),
        Row(children: [
          const Icon(Icons.person_outline, color: AppTheme.textGrey, size: 13),
          const SizedBox(width: 3),
          Text(clientName,
              style: const TextStyle(color: AppTheme.primaryGold, fontSize: 12)),
          if (clientPhone.isNotEmpty) ...[
            const SizedBox(width: 8),
            const Icon(Icons.phone, color: AppTheme.textGrey, size: 12),
            const SizedBox(width: 3),
            // الإدارة تحتاج رقم العميل للتواصل (بخلاف المحامي المحجوب عنه)
            SelectableText(clientPhone,
                style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)),
          ],
          const Spacer(),
          Text(when,
              style: const TextStyle(color: AppTheme.textGrey, fontSize: 10)),
        ]),
        if (alias.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text('⚖️ $alias', style: const TextStyle(color: AppTheme.infoBlue, fontSize: 11)),
        ],
        if (reassign > 0) ...[
          const SizedBox(height: 3),
          Text('🔄 أُعيد إسناده $reassign مرة',
              style: const TextStyle(color: AppTheme.warningOrange, fontSize: 10)),
        ],
        if ((c['reject_note'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 3),
          Text('📝 ${c['reject_note']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textGrey, fontSize: 10)),
        ],

        if (c['chat_started_at'] != null) ...[
          const Divider(color: Colors.white12, height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/legal/chat/${c['id']}'),
              icon: const Icon(Icons.visibility_outlined,
                  color: AppTheme.infoBlue, size: 16),
              label: const Text('مشاهدة المحادثة — قراءة فقط',
                  style: TextStyle(color: AppTheme.infoBlue)),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.infoBlue)),
            ),
          ),
        ],

        // أدوات الإدارة: تظهر للطلبات القابلة للتدخل فقط
        if (status == 0 || status == 5) ...[
          const Divider(color: Colors.white12, height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _grantCreditDialog(c),
                icon: const Icon(Icons.card_giftcard, color: AppTheme.warningOrange, size: 15),
                label: const Text('منح رصيد',
                    style: TextStyle(color: AppTheme.warningOrange, fontSize: 11)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.warningOrange)),
              ),
            ),
            AppTheme.gapWidthSmall,
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _assignDialog(c),
                icon: const Icon(Icons.person_add_alt, color: Colors.black, size: 15),
                label: Text(orphan ? 'إسناد لمحامٍ' : 'تغيير المحامي',
                    style: const TextStyle(
                        color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
              ),
            ),
          ]),
        ],
      ]),
    );
  }

  /// إسناد يدوي — بعد تواصل الإدارة مع المحامي خارج التطبيق
  Future<void> _assignDialog(Map<String, dynamic> c) async {
    final legal = context.read<LegalProvider>();
    await legal.fetchActiveLawyers();
    if (!mounted) return;
    final lawyers = legal.activeLawyers;
    if (lawyers.isEmpty) {
      _snack('لا يوجد محامون نشطون', bg: AppTheme.errorRed);
      return;
    }
    final rejected = ((c['rejected_by'] as List?) ?? []).map((e) => e.toString()).toSet();

    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('اختر المحامي',
            style: TextStyle(
                color: AppTheme.primaryGold, fontSize: 16, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('تواصل معه أولاً خارج التطبيق للتأكد من قبوله.',
                style: TextStyle(color: AppTheme.textGrey, fontSize: 11)),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final l in lawyers)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.gavel, color: AppTheme.primaryGold, size: 18),
                    title: Text(l.fullName.isEmpty ? 'محامي' : l.fullName,
                        style: const TextStyle(color: AppTheme.textWhite, fontSize: 13)),
                    subtitle: Text(
                        'مهام نشطة: ${l.activeTasksCount}'
                        '${rejected.contains(l.uid) ? '  ·  ⚠️ اعتذر سابقاً' : ''}',
                        style: TextStyle(
                            color: rejected.contains(l.uid)
                                ? AppTheme.warningOrange
                                : AppTheme.textGrey,
                            fontSize: 11)),
                    onTap: () => Navigator.pop(ctx, l.uid),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(color: AppTheme.textGrey)),
          ),
        ],
      ),
    );
    if (picked == null) return;

    final ok = await legal.adminAssignConsultation(
        consultationId: c['id'].toString(), lawyerUid: picked);
    if (!mounted) return;
    _snack(ok ? '✅ أُسند الطلب وأُشعر الطرفان' : (legal.error ?? 'فشل الإسناد'),
        bg: ok ? null : AppTheme.errorRed);
  }

  /// منح رصيد استشارة — بديل الاسترداد النقدي
  Future<void> _grantCreditDialog(Map<String, dynamic> c) async {
    final ctrl = TextEditingController(
        text: 'تعذّر إسناد طلبك السابق — نعتذر عن التأخير');
    final sType = (c['service_type'] ?? 0) as int;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('منح رصيد استشارة',
            style: TextStyle(
                color: AppTheme.warningOrange, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'سيستطيع العميل طلب ${sType == 1 ? 'جلسة حضورية' : 'استشارة هاتفية'} '
            'جديدة **بلا دفع**. المبلغ المدفوع سابقاً يبقى في الخزينة.',
            style: const TextStyle(
                color: AppTheme.textWhite, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            maxLines: 3,
            maxLength: 300,
            style: const TextStyle(color: AppTheme.textWhite, fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'السبب (يصل للعميل)',
              filled: true,
              fillColor: AppTheme.scaffoldBackground,
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع', style: TextStyle(color: AppTheme.textGrey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warningOrange),
            child: const Text('منح الرصيد', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
    final reason = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true) return;
    if (reason.length < 5) {
      _snack('اكتب سبباً واضحاً للعميل', bg: AppTheme.errorRed);
      return;
    }

    final legal = context.read<LegalProvider>();
    final done = await legal.adminGrantCredit(
      userUid: c['user_uid'].toString(),
      serviceType: sType,
      reason: reason,
      sourceConsultationId: c['id'].toString(),
    );
    if (!mounted) return;
    _snack(done ? '🎁 مُنح الرصيد وأُشعر العميل' : (legal.error ?? 'فشل المنح'),
        bg: done ? null : AppTheme.errorRed);
  }
}

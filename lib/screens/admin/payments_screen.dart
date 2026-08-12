import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/supabase_service.dart';
import '../../core/constants/db_constants.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/payment_model.dart';
import '../../models/user_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_utils.dart';
import '../../providers/config_provider.dart';
import '../../services/storage_service.dart';

/// 💰 إدارة المدفوعات — موافقة/رفض + تفعيل الباقات
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  List<PaymentModel> _all = [];
  final Map<String, UserModel> _usersCache = {};
  bool _loading = true;
  int _filter = 0; // 0=معلّق(افتراضي), -1=الكل, 1=مقبول, 2=مرفوض

  static const _pkgNames = {0: 'مجاني', 1: 'فضي', 2: 'ذهبي'};

  String _typeLabel(p) {
    if (p.tp == 1) {
      final w = p.meta['weeks']?.toString() ?? '?';
      return '⭐ إعلان مميز — ' + w + ' أسبوع';
    }
    return 'باقة ' + (_pkgNames[p.pkg] ?? '—');
  }
  static const _stsNames = {0: 'معلّق', 1: 'مقبول', 2: 'مرفوض'};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final adminUid = context.read<AuthProvider>().userModel?.uid ?? '';
    final list = await context.read<AdminProvider>().getAllPayments(adminUid);

    // جلب أسماء المستخدمين دفعة واحدة
    final uids = list.map((p) => p.uid).where((id) => id.isNotEmpty).toSet().toList();
    if (uids.isNotEmpty) {
      try {
        final res = await SupabaseService().client
            .from(DbTables.users)
            .select('id, nm, ph')
            .inFilter('id', uids);
        for (final u in res as List) {
          final m = Map<String, dynamic>.from(u as Map);
          _usersCache[m['id'] as String] =
              UserModel.fromSupabase(m, m['id'] as String);
        }
      } catch (_) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }
    }

    if (mounted) {
      setState(() {
        _all = list;
        _loading = false;
      });
    }
  }

  List<PaymentModel> get _filtered =>
      _filter == -1 ? _all : _all.where((p) => p.sts == _filter).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('المدفوعات'),
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
                _chip('معلّق', 0),
                _chip('الكل', -1),
                _chip('مقبول', 1),
                _chip('مرفوض', 2),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryGold))
                : _filtered.isEmpty
                    ? const Center(
                        child: Text('لا توجد مدفوعات',
                            style: TextStyle(color: AppTheme.textGrey)))
                    : RefreshIndicator(
                        color: AppTheme.primaryGold,
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: AppTheme.paddingAllMedium,
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) => _payTile(_filtered[i]),
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

  Color _stsColor(int sts) {
    switch (sts) {
      case 1:
        return AppTheme.successGreen;
      case 2:
        return AppTheme.errorRed;
      default:
        return AppTheme.warningOrange;
    }
  }

  Widget _payTile(PaymentModel p) {
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
              Text('${p.amt.toStringAsFixed(0)} ${p.cur == 0 ? '\$' : 'ل.س'}',
                  style: const TextStyle(
                      color: AppTheme.primaryGold,
                      fontSize: AppTheme.fontSizeTitle,
                      fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _stsColor(p.sts).withOpacity(0.15),
                  borderRadius: AppTheme.radiusSmall,
                  border: Border.all(color: _stsColor(p.sts).withOpacity(0.5)),
                ),
                child: Text(_stsNames[p.sts] ?? '—',
                    style: TextStyle(color: _stsColor(p.sts), fontSize: AppTheme.fontSizeCaption)),
              ),
            ],
          ),
          AppTheme.gapHeightSmall,
          _row('المستخدم',
              _usersCache[p.uid]?.nm.isNotEmpty == true
                  ? _usersCache[p.uid]!.nm
                  : _short(p.uid)),
          if (_usersCache[p.uid]?.ph.isNotEmpty == true)
            _row('الهاتف', AppUtils.displayPhone(_usersCache[p.uid]!.ph)),
          _row('النوع', _typeLabel(p)),
          // السعر المدفوع مقابل المفترض
          Builder(builder: (ctx) {
            final config = ctx.read<ConfigProvider>().config;
            double expected = 0;
            try {
              final pkgMap = config?.packages ?? {};
              final pkgData = pkgMap['${p.pkg}'];
              if (pkgData is Map && pkgData['pr'] is num) {
                expected = (pkgData['pr'] as num).toDouble();
              }
            } catch (_) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }
            final paidLabel = '${p.amt.toStringAsFixed(0)} ${p.cur == 0 ? '\$' : 'ل.س'}';
            final expectedLabel = '\$${expected.toStringAsFixed(0)}';
            final mismatch = expected > 0 && p.cur == 0 && p.amt < expected;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('المبلغ المدفوع', paidLabel),
                if (expected > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Text('السعر المفترض: ',
                          style: const TextStyle(
                              color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
                      Text(expectedLabel,
                          style: TextStyle(
                              color: mismatch ? AppTheme.errorRed : AppTheme.successGreen,
                              fontSize: AppTheme.fontSizeBody,
                              fontWeight: FontWeight.bold)),
                      if (mismatch) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.warning_amber,
                            color: AppTheme.errorRed, size: 14),
                        const Text(' أقل من المطلوب',
                            style: TextStyle(
                                color: AppTheme.errorRed, fontSize: AppTheme.fontSizeCaption)),
                      ],
                    ]),
                  ),
              ],
            );
          }),
          _row('قناة الدفع', p.channelDisplayName()),
          if (p.ref.isNotEmpty) _row('المرجع', p.ref),
          // Bug #35: عرض رقم هاتف المُحوِّل إذا موجود
          if (p.meta['sender_phone'] != null && p.meta['sender_phone'].toString().isNotEmpty)
            _row('📱 هاتف المُحوِّل', p.meta['sender_phone'].toString()),
          _row('التاريخ', p.tsCrt.toString().split(' ').first),
          if (p.proof.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: GestureDetector(
                onTap: () => _showProof(p.proof),
                child: const Row(
                  children: [
                    Icon(Icons.receipt_long, color: AppTheme.primaryGold, size: 16),
                    AppTheme.gapWidthXS,
                    Text('عرض إثبات الدفع',
                        style: TextStyle(
                            color: AppTheme.primaryGold,
                            fontSize: AppTheme.fontSizeSmall,
                            decoration: TextDecoration.underline)),
                  ],
                ),
              ),
            ),
          if (p.sts == 0) ...[
            const Divider(color: Colors.white12, height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _approve(p),
                  icon: const Icon(Icons.check_circle, size: 18),
                  label: const Text('قبول وتفعيل'),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.successGreen),
                ),
                TextButton.icon(
                  onPressed: () => _reject(p),
                  icon: const Icon(Icons.cancel, size: 18),
                  label: const Text('رفض'),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.errorRed),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// عرض إثبات الدفع — يدعم الحالتين:
  ///   1. URL كامل (سجلات قديمة من offer_images bucket عام)
  ///   2. path داخل bucket payment_proofs (خاص) → نولّد signed URL
  Future<void> _showProof(String proof) async {
    String? finalUrl;
    if (proof.startsWith('http')) {
      finalUrl = proof;
    } else {
      // path داخل payment_proofs → نولّد signed URL (صالح لساعة)
      try {
        finalUrl = await SupabaseService()
            .storage
            .from(StorageService.paymentProofsBucket)
            .createSignedUrl(proof, 3600);
      } catch (e) {_snack('فشل تحميل الإيصال');
        return;
      }
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppTheme.surfaceBlack,
        insetPadding: AppTheme.paddingAllLarge,
        child: Stack(
          children: [
            InteractiveViewer(
              child: Padding(
                padding: AppTheme.paddingAllSmall,
                child: Image.network(
                  finalUrl!,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('تعذّر تحميل الصورة',
                        style: TextStyle(color: AppTheme.textGrey)),
                  ),
                  loadingBuilder: (_, child, p) => p == null
                      ? child
                      : const Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(
                              color: AppTheme.primaryGold),
                        ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                    backgroundColor: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(PaymentModel p) async {
    final adminId = context.read<AuthProvider>().userModel?.uid ?? '';
    if (await context
        .read<AdminProvider>()
        .approvePayment(p.id, adminId)) {
      _snack('تمت الموافقة والتفعيل بنجاح');
      // ✅ Fix for Bug #37: تحديث حالة المستخدم بعد الموافقة
      // هذا يضمن أن المستخدم يحصل على الباقة الجديدة فوراً
      await context.read<AuthProvider>().refreshUser();
      _load();
    }
  }

  Future<void> _reject(PaymentModel p) async {
    final adminId = context.read<AuthProvider>().userModel?.uid ?? '';
    final reason = await _askRejectReason();
    if (reason == null || reason.trim().isEmpty) return;
    if (await context.read<AdminProvider>().rejectPayment(p.id, adminId, reason.trim())) {
      _snack('تم رفض الدفعة وإشعار المستخدم بالسبب');
      _load();
    }
  }

  /// دايالوغ سبب الرفض — إلزامي، مع أسباب جاهزة + نص حر
  Future<String?> _askRejectReason() {
    final ctrl = TextEditingController();
    const presets = ['صورة الإيصال غير واضحة', 'المبلغ المدفوع ناقص', 'رقم المرجع غير صحيح'];
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('سبب الرفض (إلزامي)',
            style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeSubtitle)),
        content: StatefulBuilder(
          builder: (ctx2, setS) => Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final r in presets)
                ActionChip(
                  label: Text(r, style: const TextStyle(fontSize: AppTheme.fontSizeCaption)),
                  onPressed: () => setS(() => ctrl.text = r),
                ),
            ]),
            AppTheme.gapHeightSmall,
            TextField(
              controller: ctrl,
              maxLines: 2,
              style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeBody),
              decoration: const InputDecoration(
                hintText: 'اكتب السبب أو اختر من الأعلى…',
                hintStyle: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall),
                border: OutlineInputBorder(),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('رفض وإشعار المستخدم'),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody)),
          Flexible(
            child: Text(value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeBody)),
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

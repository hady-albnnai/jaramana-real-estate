import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_back_button.dart';

/// ════════════════════════════════════════════════════════════════════════
/// 🚫 GP-004 (2026-08-15) — شاشة المستخدمين المحظورين
/// ════════════════════════════════════════════════════════════════════════
/// سياسة Google Play «User Generated Content» تشترط وظيفة حظر المستخدمين
/// إلى جانب نظام التبليغ. الحظر يُنشأ من صفحة العرض، وهذه الشاشة هي مكان
/// **مراجعته ورفعه** — بلا مسار للتراجع يصير الحظر فخّاً لا أداة.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _blocks = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final rows = await context.read<AuthProvider>().listMyBlocks();
    if (!mounted) return;
    setState(() {
      _blocks = rows;
      _loading = false;
    });
  }

  Future<void> _unblock(Map<String, dynamic> row) async {
    final name = (row['nm'] ?? 'مستخدم').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('رفع الحظر',
            style: TextStyle(color: AppTheme.primaryGold)),
        content: Text(
          'سيعود محتوى «$name» للظهور لك، وسيرى محتواك من جديد.',
          style: const TextStyle(color: AppTheme.textWhite, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('إلغاء', style: TextStyle(color: AppTheme.textGrey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGold,
              foregroundColor: AppTheme.deepBlack,
            ),
            child: const Text('رفع الحظر'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok =
        await context.read<AuthProvider>().unblockUser(row['uid'].toString());
    if (!mounted) return;
    AppTheme.showSnackBar(
      context,
      SnackBar(
        content:
            Text(ok ? '✅ تم رفع الحظر' : 'تعذّر رفع الحظر، حاول مرة أخرى'),
      ),
    );
    if (ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground,
        leading: const AppBackButton(),
        title: const Text('المستخدمون المحظورون'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryGold))
          : RefreshIndicator(
              color: AppTheme.primaryGold,
              onRefresh: _load,
              child: _blocks.isEmpty ? _emptyState() : _list(),
            ),
    );
  }

  Widget _emptyState() {
    // ListView (لا Center) كي يبقى السحب للتحديث فعّالاً والقائمة فارغة.
    return ListView(
      padding: AppTheme.paddingAllLarge,
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.block, color: AppTheme.textGrey, size: 64),
        AppTheme.gapHeightLarge,
        const Text(
          'لا يوجد مستخدمون محظورون',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: AppTheme.textWhite,
              fontSize: AppTheme.fontSizeSubtitle,
              fontWeight: FontWeight.bold),
        ),
        AppTheme.gapHeightSmall,
        const Text(
          'يمكنك حظر أي مُعلِن من صفحة عرضه عبر زر الخيارات (⋮).\n'
          'عند الحظر لن تظهر لك عروضه ولن تظهر عروضك له.',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: AppTheme.textGrey,
              fontSize: AppTheme.fontSizeBody,
              height: 1.6),
        ),
      ],
    );
  }

  Widget _list() {
    return ListView.builder(
      padding: AppTheme.paddingAllLarge,
      itemCount: _blocks.length,
      itemBuilder: (context, i) {
        final row = _blocks[i];
        final name = (row['nm'] ?? 'مستخدم').toString();
        final reason = (row['reason'] ?? '').toString();
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppTheme.surfaceBlack,
            borderRadius: AppTheme.radiusLarge,
            border: Border.all(color: AppTheme.errorRed.withOpacity(0.25)),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.errorRed.withOpacity(0.12),
              child: const Icon(Icons.person_off_outlined,
                  color: AppTheme.errorRed),
            ),
            title: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppTheme.textWhite, fontWeight: FontWeight.w600)),
            subtitle: reason.isEmpty
                ? null
                : Text(reason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.textGrey,
                        fontSize: AppTheme.fontSizeSmall)),
            trailing: TextButton(
              onPressed: () => _unblock(row),
              child: const Text('رفع الحظر',
                  style: TextStyle(color: AppTheme.primaryGold)),
            ),
          ),
        );
      },
    );
  }
}

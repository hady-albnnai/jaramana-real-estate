import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/user_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_utils.dart';

/// 👥 إدارة المستخدمين — بحث + حظر/تجميد/تفعيل + تغيير الدور
class UsersManagementScreen extends StatefulWidget {
  const UsersManagementScreen({super.key});

  @override
  State<UsersManagementScreen> createState() => _UsersManagementScreenState();
}

class _UsersManagementScreenState extends State<UsersManagementScreen> {
  final _searchCtrl = TextEditingController();
  List<UserModel> _users = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final users = await context.read<AdminProvider>().getAllUsers(search: _search);
    if (mounted) {
      setState(() {
        _users = users;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('إدارة الحسابات والعملاء'),
        backgroundColor: AppTheme.scaffoldBackground,
      ),
      body: Column(
        children: [
          // شريط البحث
          Padding(
            padding: AppTheme.paddingAllMedium,
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: AppTheme.textWhite),
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو الهاتف...',
                prefixIcon: const Icon(Icons.search, color: AppTheme.primaryGold),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward, color: AppTheme.primaryGold),
                  onPressed: () {
                    _search = _searchCtrl.text.trim();
                    _load();
                  },
                ),
                filled: true,
                fillColor: AppTheme.surfaceBlack,
                border: OutlineInputBorder(
                  borderRadius: AppTheme.radiusMedium,
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (v) {
                _search = v.trim();
                _load();
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryGold))
                : _users.isEmpty
                    ? const Center(
                        child: Text('لا يوجد حسابات عملاء أو وسطاء',
                            style: TextStyle(color: AppTheme.textGrey)))
                    : RefreshIndicator(
                        color: AppTheme.primaryGold,
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: AppTheme.paddingAllMedium,
                          itemCount: _users.length,
                          itemBuilder: (_, i) => _userTile(_users[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _userTile(UserModel u) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.15)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        onTap: () => context.push('/admin/user/${u.uid}'),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryGold.withOpacity(0.15),
          child: Text(u.nm.isNotEmpty ? u.nm[0] : '؟',
              style: const TextStyle(color: AppTheme.primaryGold)),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(u.nm.isEmpty ? 'بدون اسم' : u.nm,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppTheme.textWhite, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 6),
            _statusDot(u.sts),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTheme.gapHeightXS,
            Text('${AppUtils.displayPhone(u.ph)}  •  ${u.roleName}',
                style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
            Text('${u.badgeName}  •  ⭐ ${u.pt}',
                style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppTheme.primaryGold),
          color: AppTheme.surfaceBlack,
          onSelected: (v) => _onAction(v, u),
          itemBuilder: (_) => [
            const PopupMenuItem(
                value: 'role', child: Text('تغيير الدور', style: TextStyle(color: AppTheme.textWhite))),
            if (u.sts != 0)
              const PopupMenuItem(
                  value: 'activate', child: Text('تفعيل', style: TextStyle(color: AppTheme.successGreen))),
            if (u.sts != 1)
              const PopupMenuItem(
                  value: 'freeze', child: Text('تجميد', style: TextStyle(color: AppTheme.warningOrange))),
            if (u.sts != 2)
              const PopupMenuItem(
                  value: 'ban', child: Text('حظر', style: TextStyle(color: AppTheme.errorRed))),
          ],
        ),
      ),
    );
  }

  Widget _statusDot(int sts) {
    Color c;
    String t;
    switch (sts) {
      case 1:
        c = AppTheme.warningOrange;
        t = 'مجمّد';
        break;
      case 2:
        c = AppTheme.errorRed;
        t = 'محظور';
        break;
      default:
        c = AppTheme.successGreen;
        t = 'نشط';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: c.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(t, style: TextStyle(color: c, fontSize: AppTheme.fontSizeXS)),
    );
  }

  Future<void> _onAction(String action, UserModel u) async {
    final admin = context.read<AdminProvider>();
    final adminId = context.read<AuthProvider>().userModel?.uid ?? '';

    switch (action) {
      case 'role':
        _showRoleDialog(u);
        break;
      case 'activate':
        if (await admin.activateUser(adminId, u.uid)) {
          _snack('تم تفعيل ${u.nm}');
          _load();
        }
        break;
      case 'freeze':
        final reason = await _askReason('سبب التجميد');
        if (reason != null) {
          if (await admin.freezeUser(adminId, u.uid, reason)) {
            _snack('تم تجميد ${u.nm}');
            _load();
          }
        }
        break;
      case 'ban':
        final reason = await _askReason('سبب الحظر');
        if (reason != null) {
          if (await admin.banUser(adminId, u.uid, reason)) {
            _snack('تم حظر ${u.nm}');
            _load();
          }
        }
        break;
    }
  }

  void _showRoleDialog(UserModel u) {
    final roles = <int, String>{
      UserRole.user: UserRole.nameOf(UserRole.user),
      UserRole.broker: UserRole.nameOf(UserRole.broker),
    };
    int? selectedRole = u.role;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            backgroundColor: AppTheme.surfaceBlack,
            title: const Text('تغيير الدور', style: TextStyle(color: AppTheme.primaryGold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: roles.entries.map((e) => RadioListTile<int>(
                    title: Text(e.value,
                        style: const TextStyle(color: AppTheme.textWhite)),
                    value: e.key,
                    groupValue: selectedRole,
                    onChanged: (val) {
                      setState(() => selectedRole = val);
                    },
                    activeColor: AppTheme.primaryGold,
                  )).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (selectedRole == null) return;
                  Navigator.pop(ctx);
                  final admin = context.read<AdminProvider>();
                  final adminId = context.read<AuthProvider>().userModel?.uid ?? '';
                  if (await admin.updateUserRole(adminId, u.uid, selectedRole!)) {
                    _snack('تم تغيير دور ${u.nm} إلى ${roles[selectedRole]}');
                    _load();
                  }
                },
                child: const Text('تأكيد'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<String?> _askReason(String title) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: Text(title, style: const TextStyle(color: AppTheme.primaryGold)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: AppTheme.textWhite),
          decoration: const InputDecoration(hintText: 'اكتب السبب...'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء', style: TextStyle(color: AppTheme.textGrey))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim().isEmpty ? '—' : ctrl.text.trim()),
              child: const Text('تأكيد')),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    AppTheme.showSnackBar(context, SnackBar(content: Text(msg)));
  }
}

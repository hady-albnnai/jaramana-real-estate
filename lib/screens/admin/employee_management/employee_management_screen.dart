import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../models/user_model.dart';
import '../../../services/storage_service.dart';
import 'add_employee_dialog.dart';
import 'change_role_dialog.dart';
import 'toggle_status_dialog.dart';
import 'password_result_dialog.dart';
import '../../../core/utils/error_utils.dart';

/// شاشة إدارة الموظفين (الأولوية الأولى)
/// مستوحاة من مشروع Final + ملتزمة بالدستور
class EmployeeManagementScreen extends StatefulWidget {
  const EmployeeManagementScreen({super.key});

  @override
  State<EmployeeManagementScreen> createState() => _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends State<EmployeeManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<UserModel> _allUsers = [];
  List<UserModel> _filteredUsers = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(_filterUsers);
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      final adminProvider = context.read<AdminProvider>();

      final currentUser = auth.userModel;
      if (currentUser == null) {
        throw Exception('لم يتم تسجيل الدخول');
      }

      // التحقق من الصلاحية (role >= 4)
      if (currentUser.role < 4) {
        throw Exception('ليس لديك صلاحية الوصول إلى هذه الشاشة');
      }

      final users = await adminProvider.getAllStaffUsers(currentUser.uid);

      if (mounted) {
        setState(() {
          _allUsers = users;
          _filteredUsers = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _filterUsers() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredUsers = _allUsers;
      } else {
        _filteredUsers = _allUsers.where((user) {
          return user.nm.toLowerCase().contains(query) ||
                 user.ph.toLowerCase().contains(query) ||
                 (user.eml?.toLowerCase().contains(query) ?? false);
        }).toList();
      }
    });
  }

  Future<void> _showAddEmployeeDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const AddEmployeeDialog(),
    );
    if (result != null && result['success'] == true) {
      await _loadUsers();
      final password = result['new_password']?.toString();
      if (mounted && password != null && password.isNotEmpty) {
        await PasswordResultDialog.show(
          context,
          title: 'تم إضافة الموظف - كلمة السر',
          password: password,
        );
      }
    }
  }

  bool _canModifyStaffTarget(UserModel user) {
    final currentRole = context.read<AuthProvider>().userModel?.role ?? 0;
    // لا يتم تعديل المدير الرئيسي من شاشة الموظفين.
    if (user.role == 6) return false;
    // المدير يستطيع إدارة النواب وما دونهم.
    if (currentRole >= 6) return true;
    // نائب المدير يستطيع إدارة الأدوار الأدنى فقط، ولا يدير نائباً آخر.
    return user.role < 5;
  }

  void _showSeniorRestrictionSnack() {
    AppTheme.showSnackBar(context,
      const SnackBar(content: Text('هذه العملية محصورة بالمدير الرئيسي للإدارة العليا')),
    );
  }

  Future<void> _changeRole(UserModel user) async {
    if (!_canModifyStaffTarget(user)) {
      _showSeniorRestrictionSnack();
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ChangeRoleDialog(user: user),
    );
    if (result == true) {
      _loadUsers();
    }
  }

  Future<void> _toggleStatus(UserModel user) async {
    if (!_canModifyStaffTarget(user)) {
      _showSeniorRestrictionSnack();
      return;
    }
    final isActive = user.sts == 0;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ToggleStatusDialog(user: user, currentStatus: isActive),
    );
    if (result == true) {
      _loadUsers();
    }
  }

  Future<void> _resetPassword(UserModel user) async {
    if (!_canModifyStaffTarget(user)) {
      _showSeniorRestrictionSnack();
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('إعادة تعيين كلمة السر', style: TextStyle(color: AppTheme.textWhite)),
        content: Text(
          'هل أنت متأكد من إعادة تعيين كلمة سر "${user.nm}"؟',
          style: const TextStyle(color: AppTheme.textWhite),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء', style: TextStyle(color: AppTheme.textGrey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final auth = context.read<AuthProvider>();
      final adminProvider = context.read<AdminProvider>();
      final adminUid = auth.userModel?.uid;
      if (adminUid == null) throw Exception('لم يتم العثور على جلسة المدير');

      final result = await adminProvider.resetStaffPassword(
        adminUid: adminUid,
        targetUid: user.uid,
      );

      if (!mounted) return;
      if (result['success'] == true) {
        await _loadUsers();
        if (!mounted) return;
        final password = result['new_password']?.toString();
        if (password != null && password.isNotEmpty) {
          await PasswordResultDialog.show(
            context,
            title: 'تمت إعادة تعيين كلمة السر',
            password: password,
          );
        }
      } else {
        AppTheme.showSnackBar(context,
          SnackBar(content: Text("فشل إعادة التعيين: ${result['error'] ?? 'خطأ غير معروف'}")),
        );
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showSnackBar(context,
          SnackBar(content: Text(ErrorUtils.arabicMessage(e))),
        );
      }
    }
  }

  Future<void> _deleteUser(UserModel user) async {
    if (!_canModifyStaffTarget(user)) {
      _showSeniorRestrictionSnack();
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('تأكيد الحذف', style: TextStyle(color: AppTheme.errorRed)),
        content: Text(
          'هل أنت متأكد من حذف "${user.nm}"؟\nهذا الإجراء لا يمكن التراجع عنه.',
          style: const TextStyle(color: AppTheme.textWhite),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء', style: TextStyle(color: AppTheme.textGrey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final auth = context.read<AuthProvider>();
      final adminProvider = context.read<AdminProvider>();
      final adminUid = auth.userModel?.uid;
      if (adminUid == null) throw Exception('لم يتم العثور على جلسة المدير');
      final success = await adminProvider.deleteStaffUser(adminUid, user.uid);

      if (mounted) {
        if (success) {
          AppTheme.showSnackBar(context,
            const SnackBar(content: Text('تم حذف المستخدم بنجاح')),
          );
          _loadUsers();
        } else {
          AppTheme.showSnackBar(context,
            const SnackBar(content: Text('فشل حذف المستخدم')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showSnackBar(context,
          SnackBar(content: Text(ErrorUtils.arabicMessage(e))),
        );
      }
    }
  }

  List<String> _parseIdImagePaths(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return const [];
    if (value.startsWith('[')) {
      try {
        final parsed = jsonDecode(value);
        if (parsed is List) {
          return parsed.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
        }
      } catch (_) {
        // fallback below
      }
    }
    return [value];
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryGold),
          AppTheme.gapWidthSmall,
          SizedBox(
            width: 95,
            child: Text(label, style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
          ),
          Expanded(
            child: SelectableText(
              value.isEmpty ? '—' : value,
              style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeBody),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateStaffIdImages(UserModel user) async {
    final currentRole = context.read<AuthProvider>().userModel?.role ?? 0;
    if (currentRole < 5) {
      AppTheme.showSnackBar(context,
        const SnackBar(content: Text('تحديث صور الهوية محصور بالمدير ونائب المدير')),
      );
      return;
    }
    if (currentRole < 6 && user.role >= 5 && user.uid != context.read<AuthProvider>().userModel?.uid) {
      AppTheme.showSnackBar(context,
        const SnackBar(content: Text('نائب المدير لا يستطيع تحديث صور هوية الإدارة العليا')),
      );
      return;
    }

    final imgs = await StorageService().pickMultiImages(limit: 2);
    if (!mounted) return;
    if (imgs.length < 2) {
      AppTheme.showSnackBar(context,
        const SnackBar(content: Text('يجب اختيار صورتين للهوية: الوجه والقفا')),
      );
      return;
    }

    try {
      final adminUid = context.read<AuthProvider>().userModel?.uid;
      if (adminUid == null) throw Exception('لم يتم العثور على جلسة المدير');

      final idImagesBase64 = <String>[];
      for (final image in imgs.take(2)) {
        idImagesBase64.add(base64Encode(await image.readAsBytes()));
      }

      final result = await context.read<AdminProvider>().updateStaffIdImages(
        adminUid: adminUid,
        targetUid: user.uid,
        idImagesBase64: idImagesBase64,
        idImageContentType: 'image/jpeg',
      );

      if (!mounted) return;
      if (result['success'] == true) {
        AppTheme.showSnackBar(context,
          const SnackBar(content: Text('تم تحديث صور الهوية وتوثيق الحساب وظيفياً ✅'), backgroundColor: AppTheme.successGreen),
        );
        await _loadUsers();
      } else {
        AppTheme.showSnackBar(context,
          SnackBar(content: Text("فشل تحديث الصور: ${result['error'] ?? 'خطأ غير معروف'}"), backgroundColor: AppTheme.errorRed),
        );
      }
    } catch (e) {
      if (!mounted) return;
      AppTheme.showSnackBar(context,
        SnackBar(content: Text('تعذّر تحديث صور الهوية: $e'), backgroundColor: AppTheme.errorRed),
      );
    }
  }

  Future<void> _showStaffIdImages(UserModel user) async {
    try {
      final adminUid = context.read<AuthProvider>().userModel?.uid;
      if (adminUid == null) throw Exception('لم يتم العثور على جلسة المدير');

      final urls = await context.read<AdminProvider>().getStaffIdImageUrls(adminUid, user.uid);
      if (!mounted) return;
      if (urls.isEmpty) {
        AppTheme.showSnackBar(context,
          const SnackBar(content: Text('لا توجد صور هوية محفوظة لهذا الموظف')),
        );
        return;
      }

      await showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: AppTheme.paddingAllMedium,
          child: _StaffIdImagesViewer(name: user.nm, urls: urls),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppTheme.showSnackBar(context,
        SnackBar(content: Text('تعذّر عرض صورة الهوية: $e')),
      );
    }
  }

  Future<void> _showEmployeeDetails(UserModel user) async {
    final currentRole = context.read<AuthProvider>().userModel?.role ?? 0;
    if (currentRole < 5) {
      AppTheme.showSnackBar(context,
        const SnackBar(content: Text('عرض تفاصيل الموظفين محصور بالمدير ونائب المدير')),
      );
      return;
    }
    if (currentRole < 6 && user.role >= 5 && user.uid != context.read<AuthProvider>().userModel?.uid) {
      AppTheme.showSnackBar(context,
        const SnackBar(content: Text('نائب المدير لا يستطيع عرض بيانات الإدارة العليا')),
      );
      return;
    }

    final idImageCount = _parseIdImagePaths(user.img).length;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: Text('بيانات ${user.nm}', style: const TextStyle(color: AppTheme.textWhite)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _detailRow(Icons.badge_outlined, 'الدور', _getRoleName(user.role)),
              _detailRow(Icons.phone, 'الهاتف', AppUtils.displayPhone(user.ph)),
              _detailRow(Icons.alternate_email, 'اسم المستخدم', user.usr ?? ''),
              _detailRow(Icons.email_outlined, 'الإيميل', user.eml ?? ''),
              _detailRow(Icons.credit_card, 'الرقم الوطني', user.sid),
              _detailRow(Icons.location_on_outlined, 'العنوان', user.ad),
              _detailRow(Icons.verified_user_outlined, 'التوثيق', user.vrf == 2 ? 'موثق' : 'غير موثق'),
              _detailRow(Icons.circle, 'الحالة', user.sts == 0 ? 'نشط' : 'معطّل/مجمّد'),
              AppTheme.gapHeightMedium,
              OutlinedButton.icon(
                onPressed: user.img.trim().isEmpty ? null : () => _showStaffIdImages(user),
                icon: const Icon(Icons.image_search, color: AppTheme.primaryGold),
                label: Text(
                  idImageCount <= 0 ? 'لا توجد صور هوية' : 'عرض صور الهوية ($idImageCount)',
                  style: const TextStyle(color: AppTheme.primaryGold),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.primaryGold),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              AppTheme.gapHeightSmall,
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _updateStaffIdImages(user);
                },
                icon: const Icon(Icons.upload_file, color: AppTheme.deepBlack),
                label: const Text(
                  'تحديث صور الهوية (وجه وقفا)',
                  style: TextStyle(color: AppTheme.deepBlack, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGold,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق', style: TextStyle(color: AppTheme.textGrey)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground,
        title: const Text('إدارة الموظفين', style: TextStyle(color: AppTheme.textWhite)),
        actions: [
          IconButton(
            icon: const Icon(Icons.dashboard_customize, color: AppTheme.primaryGold),
            onPressed: () => context.push('/admin/office-operations'),
            tooltip: 'لوحة المدير والأقسام',
          ),
          IconButton(
            icon: const Icon(Icons.add, color: AppTheme.primaryGold),
            onPressed: _showAddEmployeeDialog,
            tooltip: 'إضافة موظف جديد',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryGold),
            onPressed: _loadUsers,
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط البحث
          Padding(
            padding: AppTheme.paddingAllLarge,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: AppTheme.textWhite),
              decoration: InputDecoration(
                hintText: 'بحث بالاسم أو الهاتف أو البريد...',
                hintStyle: const TextStyle(color: AppTheme.textGrey),
                prefixIcon: const Icon(Icons.search, color: AppTheme.primaryGold),
                filled: true,
                fillColor: AppTheme.surfaceBlack,
                border: OutlineInputBorder(
                  borderRadius: AppTheme.radiusMedium,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // قائمة الموظفين
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGold))
                : _errorMessage != null
                    ? Center(child: Text(_errorMessage!, style: const TextStyle(color: AppTheme.errorRed)))
                    : _filteredUsers.isEmpty
                        ? const Center(
                            child: Text('لا يوجد موظفون', style: TextStyle(color: AppTheme.textGrey)),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _filteredUsers.length,
                            itemBuilder: (context, index) {
                              final user = _filteredUsers[index];
                              return _buildEmployeeCard(user);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard(UserModel user) {
    final roleName = _getRoleName(user.role);
    final roleColor = _getRoleColor(user.role);
    final isActive = user.sts == 0;
    final canModify = _canModifyStaffTarget(user);

    return Card(
      color: AppTheme.surfaceBlack,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusMedium),
      child: Padding(
        padding: AppTheme.paddingAllLarge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.primaryGold.withOpacity(0.2),
                  child: Text(
                    user.nm.isNotEmpty ? user.nm[0] : '?',
                    style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold),
                  ),
                ),
                AppTheme.gapWidthMedium,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.nm,
                        style: const TextStyle(
                          color: AppTheme.textWhite,
                          fontSize: AppTheme.fontSizeSubtitle,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      AppTheme.gapHeightXS,
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: roleColor.withOpacity(0.2),
                          borderRadius: AppTheme.radiusSmall,
                        ),
                        child: Text(
                          roleName,
                          style: TextStyle(color: roleColor, fontSize: AppTheme.fontSizeSmall),
                        ),
                      ),
                    ],
                  ),
                ),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, color: AppTheme.textGrey),
                                  onSelected: (value) {
                                    switch (value) {
                                      case 'details':
                                        _showEmployeeDetails(user);
                                        break;
                                      case 'update_id_images':
                                        _updateStaffIdImages(user);
                                        break;
                                      case 'change_role':
                                        _changeRole(user);
                                        break;
                                      case 'toggle_status':
                                        _toggleStatus(user);
                                        break;
                                      case 'reset_password':
                                        _resetPassword(user);
                                        break;
                                      case 'delete':
                                        _deleteUser(user);
                                        break;
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(value: 'details', child: Text('عرض التفاصيل')),
                                    if (canModify) ...[
                                      const PopupMenuItem(value: 'update_id_images', child: Text('تحديث صور الهوية')),
                                      const PopupMenuDivider(),
                                      const PopupMenuItem(value: 'change_role', child: Text('تغيير الدور')),
                                      PopupMenuItem(
                                        value: 'toggle_status',
                                        child: Text(isActive ? 'تعطيل' : 'تفعيل'),
                                      ),
                                      const PopupMenuItem(value: 'reset_password', child: Text('إعادة تعيين كلمة السر')),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text('حذف', style: TextStyle(color: AppTheme.errorRed)),
                                      ),
                                    ],
                                  ],
                                ),
              ],
            ),
            AppTheme.gapHeightMedium,
            Row(
              children: [
                const Icon(Icons.phone, size: 16, color: AppTheme.textGrey),
                const SizedBox(width: 6),
                Text(AppUtils.displayPhone(user.ph), style: const TextStyle(color: AppTheme.textGrey)),
              ],
            ),
            if (user.eml != null) ...[
              AppTheme.gapHeightXS,
              Row(
                children: [
                  const Icon(Icons.email, size: 16, color: AppTheme.textGrey),
                  const SizedBox(width: 6),
                  Text(user.eml!, style: const TextStyle(color: AppTheme.textGrey)),
                ],
              ),
            ],
            AppTheme.gapHeightSmall,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? AppTheme.successGreen.withOpacity(0.2)
                    : AppTheme.errorRed.withOpacity(0.2),
                borderRadius: AppTheme.radiusSmall,
              ),
              child: Text(
                isActive ? 'نشط' : 'معطل',
                style: TextStyle(
                  color: isActive ? AppTheme.successGreen : AppTheme.errorRed,
                  fontSize: AppTheme.fontSizeSmall,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getRoleName(int role) {
    switch (role) {
      case 2: return 'مصور';
      case 3: return 'مشرف';
      case 4: return 'موظف مكتب';
      case 5: return 'نائب مدير';
      case 6: return 'مدير';
      case 7: return 'محامي مختص';
      case 8: return 'معقب معاملات';
      default: return 'غير معروف';
    }
  }

  Color _getRoleColor(int role) {
    switch (role) {
      case 2: return Colors.teal;
      case 3: return AppTheme.warningOrange;
      case 4: return AppTheme.infoBlue;
      case 5: return Colors.purple;
      case 6: return AppTheme.primaryGold;
      case 7: return Colors.deepPurple;
      case 8: return Colors.brown;
      default: return AppTheme.textGrey;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
class _StaffIdImagesViewer extends StatefulWidget {
  final String name;
  final List<String> urls;

  const _StaffIdImagesViewer({required this.name, required this.urls});

  @override
  State<_StaffIdImagesViewer> createState() => _StaffIdImagesViewerState();
}

class _StaffIdImagesViewerState extends State<_StaffIdImagesViewer> {
  late final PageController _controller;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.82,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
                Expanded(
                  child: Text(
                    '${widget.name} - صورة ${_current + 1}/${widget.urls.length}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) => InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Center(
                  child: Image.network(
                    widget.urls[i],
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image,
                      color: AppTheme.textGrey,
                      size: 80,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.urls.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.urls.length, (i) {
                  final active = i == _current;
                  return Container(
                    width: active ? 18 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: active ? AppTheme.primaryGold : Colors.white54,
                      borderRadius: AppTheme.radiusSmall,
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

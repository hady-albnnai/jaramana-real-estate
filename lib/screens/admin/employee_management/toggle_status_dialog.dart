import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../models/user_model.dart';
import '../../../core/utils/error_utils.dart';

class ToggleStatusDialog extends StatefulWidget {
  final UserModel user;
  final bool currentStatus; // true = active (sts=0), false = inactive

  const ToggleStatusDialog({super.key, required this.user, required this.currentStatus});

  @override
  State<ToggleStatusDialog> createState() => _ToggleStatusDialogState();
}

class _ToggleStatusDialogState extends State<ToggleStatusDialog> {
  bool _isLoading = false;
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _isLoading = true);

    try {
      final auth = context.read<AuthProvider>();
      final adminProvider = context.read<AdminProvider>();
      final adminUid = auth.userModel?.uid ?? '';

      final newStatus = widget.currentStatus ? 1 : 0; // 1 = frozen, 0 = active

      final success = await adminProvider.toggleUserStatus(
        adminUid,
        widget.user.uid,
        newStatus,
        reason: _reasonController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context, success);
        if (success) {
          AppTheme.showSnackBar(context,
            SnackBar(content: Text(widget.currentStatus ? 'تم تعطيل المستخدم' : 'تم تفعيل المستخدم')),
          );
        } else {
          AppTheme.showSnackBar(context,
            const SnackBar(content: Text('فشل العملية')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context, false);
        AppTheme.showSnackBar(context,
          SnackBar(content: Text(ErrorUtils.arabicMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actionText = widget.currentStatus ? 'تعطيل' : 'تفعيل';
    final color = widget.currentStatus ? AppTheme.errorRed : AppTheme.successGreen;

    return AlertDialog(
      backgroundColor: AppTheme.surfaceBlack,
      title: Text('$actionText ${widget.user.nm}', style: TextStyle(color: color)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'هل أنت متأكد من $actionText هذا المستخدم؟',
            style: const TextStyle(color: AppTheme.textWhite),
          ),
          AppTheme.gapHeightLarge,
          if (widget.currentStatus) // سبب التعطيل/التجميد عند إيقاف حساب نشط
            TextField(
              controller: _reasonController,
              style: const TextStyle(color: AppTheme.textWhite),
              decoration: const InputDecoration(
                labelText: 'سبب التعطيل (اختياري)',
                labelStyle: TextStyle(color: AppTheme.textGrey),
              ),
              maxLines: 2,
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء', style: TextStyle(color: AppTheme.textGrey)),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: color),
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(actionText),
        ),
      ],
    );
  }
}
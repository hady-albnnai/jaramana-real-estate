import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/validation/input_validators.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/storage_service.dart';
import '../../../core/utils/error_utils.dart';

class AddEmployeeDialog extends StatefulWidget {
  const AddEmployeeDialog({super.key});

  @override
  State<AddEmployeeDialog> createState() => _AddEmployeeDialogState();
}

class _AddEmployeeDialogState extends State<AddEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _addressController = TextEditingController();
  final _sidController = TextEditingController();

  int _selectedRole = 4; // موظف مكتب افتراضي
  bool _isLoading = false;
  final List<XFile> _idImages = [];
  final StorageService _storage = StorageService();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _addressController.dispose();
    _sidController.dispose();
    super.dispose();
  }

  String? _validateUsername(String? value) => InputValidators.validateUsername(value);

  Future<void> _pickImages() async {
    final imgs = await _storage.pickMultiImages(limit: 2);
    if (imgs.isNotEmpty) {
      setState(() {
        _idImages
          ..clear()
          ..addAll(imgs.take(2));
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_idImages.length < 2) {
      AppTheme.showSnackBar(context,
        const SnackBar(content: Text('يجب رفع صورتين للهوية على الأقل: الوجه والقفا')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final auth = context.read<AuthProvider>();
      final adminProvider = context.read<AdminProvider>();
      final adminUid = auth.userModel?.uid;

      if (adminUid == null) {
        throw Exception('لم يتم العثور على جلسة المدير');
      }

      // صور الهوية تُرسل إلى Edge Function create-user كـ Base64.
      // السبب: حسابات الموظفين تستخدم staff_session_token داخلي، وليس بالضرورة Supabase Auth JWT،
      // لذلك الرفع المباشر إلى Storage من التطبيق قد يفشل بسبب RLS.
      final idImagesBase64 = <String>[];
      for (final image in _idImages.take(2)) {
        idImagesBase64.add(base64Encode(await image.readAsBytes()));
      }

      final result = await adminProvider.createStaffUser(
        adminUid: adminUid,
        fullName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        username: _usernameController.text.trim(),
        role: _selectedRole,
        address: _addressController.text.trim(),
        sid: _sidController.text.trim(),
        idImagesBase64: idImagesBase64,
        idImageContentType: 'image/jpeg',
      );

      if (!mounted) return;

      if (result['success'] == true) {
        Navigator.pop(context, result);
      } else {
        AppTheme.showSnackBar(context,
          SnackBar(content: Text("فشل إضافة الموظف: ${result['error'] ?? 'خطأ غير معروف'}")),
        );
      }
    } catch (e) {
      if (mounted) {
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
    final currentUser = context.read<AuthProvider>().userModel;
    final isManager = currentUser?.role == 6;
    final isSenior = currentUser?.isSenior ?? false;

    return AlertDialog(
      backgroundColor: AppTheme.surfaceBlack,
      title: const Text('إضافة موظف جديد', style: TextStyle(color: AppTheme.textWhite)),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: const InputDecoration(
                  labelText: 'الاسم الكامل *',
                  labelStyle: TextStyle(color: AppTheme.textGrey),
                ),
                validator: InputValidators.validateName,
              ),
              AppTheme.gapHeightMedium,
              TextFormField(
                controller: _phoneController,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف *',
                  labelStyle: TextStyle(color: AppTheme.textGrey),
                ),
                keyboardType: TextInputType.phone,
                validator: InputValidators.validateSyrianPhone,
              ),
              AppTheme.gapHeightMedium,
              TextFormField(
                controller: _sidController,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: const InputDecoration(
                  labelText: 'الرقم الوطني *',
                  labelStyle: TextStyle(color: AppTheme.textGrey),
                ),
                keyboardType: TextInputType.number,
                validator: (v) => (v == null || v.isEmpty) ? 'مطلوب' : null,
              ),
              AppTheme.gapHeightMedium,
              TextFormField(
                controller: _addressController,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: const InputDecoration(
                  labelText: 'العنوان التفصيلي *',
                  labelStyle: TextStyle(color: AppTheme.textGrey),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'مطلوب' : null,
              ),
              AppTheme.gapHeightMedium,
              // اختيار صورة الهوية
              InkWell(
                onTap: _pickImages,
                child: Container(
                  padding: AppTheme.paddingAllMedium,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceBlack,
                    borderRadius: AppTheme.radiusSmall,
                    border: Border.all(color: AppTheme.textGrey.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _idImages.isEmpty ? Icons.add_a_photo_outlined : Icons.check_circle,
                        color: _idImages.isEmpty ? AppTheme.primaryGold : AppTheme.successGreen,
                      ),
                      AppTheme.gapWidthMedium,
                      Expanded(
                        child: Text(
                          _idImages.length < 2 ? 'ارفع صورتين للهوية (وجه وقفا) *' : 'تم اختيار ${_idImages.length} صورة',
                          style: TextStyle(
                            color: _idImages.isEmpty ? AppTheme.textGrey : AppTheme.textWhite,
                            fontSize: AppTheme.fontSizeMedium,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AppTheme.gapHeightMedium,
              TextFormField(
                controller: _usernameController,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: const InputDecoration(
                  labelText: 'اسم المستخدم (اختياري)',
                  labelStyle: TextStyle(color: AppTheme.textGrey),
                  hintText: 'مثال: office_1',
                  hintStyle: TextStyle(color: AppTheme.textGrey),
                ),
                validator: _validateUsername,
              ),
              AppTheme.gapHeightMedium,
              TextFormField(
                controller: _emailController,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: const InputDecoration(
                  labelText: 'البريد الإلكتروني (اختياري)',
                  labelStyle: TextStyle(color: AppTheme.textGrey),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              AppTheme.gapHeightLarge,
              DropdownButtonFormField<int>(
                value: _selectedRole,
                dropdownColor: AppTheme.surfaceBlack,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: const InputDecoration(
                  labelText: 'الدور *',
                  labelStyle: TextStyle(color: AppTheme.textGrey),
                ),
                items: [
                  const DropdownMenuItem(value: 2, child: Text('مصور')),
                  const DropdownMenuItem(value: 3, child: Text('مشرف ميداني')),
                  const DropdownMenuItem(value: 8, child: Text('معقب معاملات ميداني')),
                  const DropdownMenuItem(value: 4, child: Text('موظف مكتب')),
                  if (isManager || isSenior) const DropdownMenuItem(value: 7, child: Text('محامي مختص (قسم الاستشارات)')),
                  if (isManager) const DropdownMenuItem(value: 5, child: Text('نائب مدير')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _selectedRole = value);
                },
              ),
              AppTheme.gapHeightLarge,
              Container(
                padding: AppTheme.paddingAllMedium,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGold.withOpacity(0.08),
                  borderRadius: AppTheme.radiusSmall,
                  border: Border.all(color: AppTheme.primaryGold.withOpacity(0.25)),
                ),
                child: const Text(
                  'سيتم توليد كلمة سر تلقائياً وعرضها مرة واحدة بعد الإضافة.',
                  style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeSmall),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('إلغاء', style: TextStyle(color: AppTheme.textGrey)),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Text('إضافة', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

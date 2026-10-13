import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/validation/input_validators.dart';
import '../../core/network/supabase_service.dart';

/// ════════════════════════════════════════════════════════════════════
/// شاشة إعداد الملف الشخصي (إلزامية بعد أول تسجيل).
/// تشمل: الاسم الكامل + رقم الهاتف + اسم المستخدم + كلمة المرور.
/// هذه البيانات تُميّز الحساب وتضمن عدم تكراره.
/// ════════════════════════════════════════════════════════════════════
class SetupProfileScreen extends StatefulWidget {
  const SetupProfileScreen({super.key});

  @override
  State<SetupProfileScreen> createState() => _SetupProfileScreenState();
}

class _SetupProfileScreenState extends State<SetupProfileScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _usernameAvailable = false;
  bool _checkingUsername = false;
  bool _checkFailed = false;
  String? _usernameInputError;
  Timer? _usernameDebounce;
  int _usernameCheckSerial = 0;

  @override
  void initState() {
    super.initState();
    // نعبّئ الهاتف إذا كان موجوداً (تسجيل SMS)
    final user = context.read<AuthProvider>().userModel;
    if (user != null && user.ph.isNotEmpty) {
      _phoneController.text = _normalizePhoneToLocalFormat(user.ph);
    }
  }

  /// ✅ Fix for Bug #4: تطبيع رقم الهاتف إلى الصيغة المحلية (09xxxxxxxx)
  /// يتعامل مع الصيغ المختلفة: +9639xxxxxxxx, 9639xxxxxxxx, 09xxxxxxxx, 9xxxxxxxx
  String _normalizePhoneToLocalFormat(String phone) {
    // إزالة جميع الأحرف غير الرقمية
    var cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');
    
    // إزالة كود الدولة إذا كان موجوداً
    if (cleaned.startsWith('963')) {
      cleaned = cleaned.substring(3);
    }
    
    // إضافة 0 في البداية إذا لم تكن موجودة
    if (!cleaned.startsWith('0')) {
      cleaned = '0$cleaned';
    }
    
    return cleaned;
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  /// تنظيف اسم المستخدم أثناء الكتابة.
  /// يمنع الفراغات عملياً حتى لو وصلت عبر لصق النص، ويحوّل الأحرف اللاتينية
  /// إلى lowercase حتى يكون الفحص والحفظ بنفس القيمة التي يراها المستخدم.
  void _onUsernameChanged(String value) {
    final hadWhitespace = RegExp(r'\s').hasMatch(value);
    final cleaned = value.replaceAll(RegExp(r'\s+'), '').toLowerCase();

    if (cleaned != value) {
      final oldOffset = _usernameController.selection.baseOffset;
      final safeOffset = oldOffset < 0 ? value.length : oldOffset.clamp(0, value.length).toInt();
      final removedBeforeCursor = RegExp(r'\s')
          .allMatches(value.substring(0, safeOffset))
          .length;
      final newOffset = (safeOffset - removedBeforeCursor).clamp(0, cleaned.length).toInt();
      _usernameController.value = TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: newOffset),
      );
    }

    final username = cleaned.trim();
    final localError = username.isEmpty ? null : InputValidators.validateUsername(username);

    _usernameDebounce?.cancel();
    _usernameCheckSerial++;

    setState(() {
      _usernameInputError = localError;
      _usernameAvailable = false;
      _checkFailed = false;
      _checkingUsername = false;
    });

    if (hadWhitespace) {
      _snack('لا يسمح بالفراغات داخل اسم المستخدم — تم حذفها تلقائياً');
    }

    if (username.length < 3 || localError != null) return;

    _usernameDebounce = Timer(
      const Duration(milliseconds: 450),
      () => _checkUsername(username),
    );
  }

  /// فحص توفر اسم المستخدم لحظياً بعد تحقق القواعد المحلية.
  Future<void> _checkUsername(String username) async {
    if (!mounted) return;
    final usr = username.trim().toLowerCase();
    final localError = InputValidators.validateRequiredUsername(usr);
    if (localError != null) {
      if (mounted) {
        setState(() {
          _usernameInputError = localError;
          _usernameAvailable = false;
          _checkFailed = false;
          _checkingUsername = false;
        });
      }
      return;
    }

    final requestSerial = ++_usernameCheckSerial;
    setState(() {
      _checkingUsername = true;
      _checkFailed = false;
    });
    try {
      final res = await SupabaseService().invokeFunction(
        'user-account',
        body: {'action': 'check_username', 'username': usr},
      );
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : null;
      final ok = data != null && data['success'] == true && data['available'] == true;
      if (mounted && requestSerial == _usernameCheckSerial) {
        setState(() {
          _usernameAvailable = ok;
          _checkFailed = false;
          _checkingUsername = false;
          _usernameInputError =
              ok ? null : 'اسم المستخدم مستخدم في حساب آخر';
        });
      }
    } catch (_) {
      if (mounted && requestSerial == _usernameCheckSerial) {
        setState(() {
          _usernameAvailable = false;
          _checkFailed = true;
          _checkingUsername = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    // 1) الاسم الكامل
    final name = _nameController.text.trim();
    if (name.length < 2) {
      _snack('يرجى إدخال الاسم الكامل (حرفين على الأقل)');
      return;
    }

    // 2) رقم الهاتف
    // 📞 PHONE-001: تطبيع موحّد قبل الفحص
    final phone = InputValidators.toLocalSyrianPhone(_phoneController.text.trim());
    if (!InputValidators.isValidSyrianMobile(phone)) {
      _snack('يرجى إدخال رقم هاتف سوري صحيح (09xxxxxxxx)');
      return;
    }

    final auth = context.read<AuthProvider>();
    final user = auth.userModel;
    if (user == null) {
      _snack('انتهت صلاحية الجلسة، أعد تسجيل الدخول');
      return;
    }

    // 3) اسم المستخدم
    final username = _usernameController.text.trim().toLowerCase();
    final usernameError = InputValidators.validateRequiredUsername(username);
    if (usernameError != null) {
      _snack(usernameError);
      return;
    }
    if (_usernameInputError != null) {
      _snack(_usernameInputError!);
      return;
    }
    if (_checkingUsername) {
      _snack('انتظر لحظة حتى يكتمل فحص اسم المستخدم');
      return;
    }
    if (!_usernameAvailable) {
      await _checkUsername(username);
      if (!mounted) return;
    }
    if (_checkFailed) {
      _snack('تعذر التحقق من توفر اسم المستخدم، يرجى فحص الاتصال بالإنترنت');
      return;
    }
    if (!_usernameAvailable) {
      _snack('اسم المستخدم محجوز أو غير صالح، اختر اسماً آخر');
      return;
    }

    // 4) كلمة المرور
    final password = _passwordController.text;
    final passwordError = InputValidators.validatePassword(password);
    if (passwordError != null) {
      _snack(passwordError);
      return;
    }
    if (password != _confirmPasswordController.text) {
      _snack('كلمتا المرور غير متطابقتين');
      return;
    }

    // 🛡️ تأكيد حفظ البيانات
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('تأكيد حفظ البيانات', style: TextStyle(color: AppTheme.textWhite)),
        content: const Text(
          'هل قمت بحفظ اسم المستخدم وكلمة المرور في مكان آمن؟\nستحتاج إليهما للدخول مستقبلاً.',
          style: TextStyle(color: AppTheme.textGrey),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انتظر')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نعم، حفظتها')),
        ],
      ),
    );

    if (save != true) return;

    setState(() => _loading = true);

    try {
      // فحص مبكر لمنع رسالة عامة عند استخدام رقم مسجل لحساب آخر.
      // 🔒 BUG-021 (2026-08-14): كان السيرفر يُرجع `user_id` صاحب الرقم لأي
      // طالب بلا مصادقة ⇒ حصاد UIDs بالجملة (أُكِّد حياً على حساب المدير
      // الرئيسي). صار يُرجع `owned_by_other` المنطقي — وهو كل ما تحتاجه هذه
      // الشاشة فعلاً — بلا كشف أي معرّف.
      final phoneCheckRes = await SupabaseService().invokeFunction(
        'user-account',
        body: {
          'action': 'check_phone_exists',
          'phone': phone,
          'self_uid': user.uid,
        },
      );
      final phoneCheck = phoneCheckRes.data is Map
          ? Map<String, dynamic>.from(phoneCheckRes.data)
          : null;
      if (phoneCheck?['owned_by_other'] == true) {
        throw Exception('PHONE_ALREADY_EXISTS');
      }

      // خطوة 1: حفظ الاسم والهاتف
      final profileRes = await SupabaseService().invokeFunction('user-account', body: {
        'action': 'update_profile',
        'user_uid': user.uid,
        'payload': {'nm': name, 'ph': phone},
      });
      final profileData = profileRes.data is Map ? Map<String, dynamic>.from(profileRes.data) : null;
      if (profileData == null || profileData['success'] == false) {
        final err = profileData?['error']?.toString() ?? 'UPDATE_FAILED';
        throw Exception(err);
      }

      // خطوة 2: حفظ اسم المستخدم وكلمة المرور
      final res = await SupabaseService().invokeFunction('user-account', body: {
        'action': 'register_password',
        'user_uid': user.uid,
        'username': username,
        'password': password,
      });

      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : null;
      if (data == null || data['success'] == false) {
        final err = data?['error']?.toString() ?? 'REGISTRATION_FAILED';
        throw Exception(err);
      }

      await auth.refreshUser();
      if (!mounted) return;
      setState(() => _loading = false);

      AppTheme.showSnackBar(context,
        const SnackBar(
          content: Text('✅ تم إنشاء وتأمين حسابك بنجاح'),
          backgroundColor: AppTheme.successGreen,
        ),
      );

      _navigateByRole(auth);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final msg = e.toString();
      if (msg.contains('USERNAME_TAKEN')) {
        _snack('اسم المستخدم محجوز، اختر اسماً آخر');
      } else if (msg.contains('PHONE_ALREADY_EXISTS') || msg.contains('users_unique_phone_active') || msg.contains('duplicate key')) {
        _snack('رقم الهاتف مستخدم في حساب آخر — استخدم رقمك غير المسجل أو سجّل دخولك بالحساب الموجود');
      } else if (msg.contains('PASSWORD_TOO_SHORT') || msg.contains('6') || msg.contains('8')) {
        _snack('كلمة المرور قصيرة، يجب أن تكون 8 أحرف على الأقل');
      } else if (msg.contains('USERNAME_INVALID_CHARS')) {
        _snack('اسم المستخدم يحتوي أحرفاً غير مسموحة');
      } else if (msg.contains('USERNAME_LENGTH')) {
        _snack('اسم المستخدم يجب أن يكون بين 3 و 30 حرفاً');
      } else if (msg.contains('PHONE_INVALID') || msg.contains('PHONE_REQUIRED')) {
        _snack('رقم الهاتف غير صالح');
      } else if (msg.contains('AUTH_UID_MISMATCH') || msg.contains('UNAUTHORIZED_ACCESS') || msg.contains('AUTH_TOKEN_REQUIRED') || msg.contains('AUTH_TOKEN_INVALID') || msg.contains('401') || msg.contains('403')) {
        _snack('انتهت صلاحية جلسة الرابط السحري، الرجاء إعادة إرسال الرابط وفتحه من نفس الجهاز');
      } else if (msg.contains('USER_NOT_FOUND')) {
        _snack('تعذر العثور على الحساب، أعد فتح رابط التفعيل أو سجّل من جديد');
      } else {
        _snack('حدث خطأ أثناء إعداد الحساب، حاول مرة أخرى');
      }
    }
  }

  void _navigateByRole(AuthProvider auth) {
    if (auth.isSenior) {
      context.go('/admin/dashboard');
    } else if (auth.isEmployee) {
      context.go('/employee/home');
    } else if (auth.isSupervisor) {
      context.go('/executor/tasks');
    } else if (auth.isPhotographer) {
      context.go('/photographer/tasks');
    } else if (auth.isBroker) {
      context.go('/broker/dashboard');
    } else {
      context.go('/user/home');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    AppTheme.showSnackBar(context, SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('إعداد الحساب'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── أيقونة + عنوان ───
              Center(
                child: Column(children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGold.withOpacity(0.15),
                      borderRadius: AppTheme.radiusXL,
                    ),
                    child: const Icon(Icons.lock_person_outlined,
                        color: AppTheme.primaryGold, size: 36),
                  ),
                  AppTheme.gapHeightLarge,
                  const Text(
                    'إعداد بيانات الحساب',
                    style: TextStyle(
                        color: AppTheme.textWhite,
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'جميع الحقول إلزامية — تُستخدم لتمييز حسابك وحمايته',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody),
                  ),
                ]),
              ),
              AppTheme.gapHeightXXL,

              // ─── الاسم الكامل ───
              const Text('الاسم الكامل *',
                  style: TextStyle(
                      color: AppTheme.primaryGold,
                      fontWeight: FontWeight.bold,
                      fontSize: AppTheme.fontSizeBody)),
              AppTheme.gapHeightSmall,
              TextField(
                controller: _nameController,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: InputDecoration(
                  hintText: 'مثلاً: أحمد محمد',
                  prefixIcon: const Icon(Icons.person_outline,
                      color: AppTheme.primaryGold),
                  filled: true,
                  fillColor: AppTheme.surfaceBlack,
                  border: OutlineInputBorder(
                      borderRadius: AppTheme.radiusMedium),
                ),
              ),
              AppTheme.gapHeightLarge,

              // ─── رقم الهاتف ───
              const Text('رقم الهاتف *',
                  style: TextStyle(
                      color: AppTheme.primaryGold,
                      fontWeight: FontWeight.bold,
                      fontSize: AppTheme.fontSizeBody)),
              AppTheme.gapHeightSmall,
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: InputDecoration(
                  hintText: '09xxxxxxxx',
                  prefixIcon: const Icon(Icons.phone_outlined,
                      color: AppTheme.primaryGold),
                  filled: true,
                  fillColor: AppTheme.surfaceBlack,
                  border: OutlineInputBorder(
                      borderRadius: AppTheme.radiusMedium),
                ),
              ),
              AppTheme.gapHeightLarge,

              // ─── اسم المستخدم ───
              const Text('اسم المستخدم *',
                  style: TextStyle(
                      color: AppTheme.primaryGold,
                      fontWeight: FontWeight.bold,
                      fontSize: AppTheme.fontSizeBody)),
              AppTheme.gapHeightXS,
              const Text(
                'بدون فراغات — أحرف عربية أو إنجليزية + أرقام + _ + . (3–30 حرف)',
                style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption),
              ),
              AppTheme.gapHeightSmall,
              TextField(
                controller: _usernameController,
                textAlign: TextAlign.left,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                    color: AppTheme.textWhite, letterSpacing: 1),
                decoration: InputDecoration(
                  hintText: 'مثلاً: ahmed_123',
                  errorText: _usernameInputError,
                  helperText: _usernameController.text.isEmpty
                      ? null
                      : (_usernameAvailable
                          ? 'اسم المستخدم متاح ✅'
                          : (_checkingUsername ? 'جاري فحص توفر الاسم...' : null)),
                  helperStyle: TextStyle(
                    color: _usernameAvailable ? AppTheme.successGreen : AppTheme.textGrey,
                    fontSize: AppTheme.fontSizeCaption,
                  ),
                  prefixIcon: const Icon(Icons.alternate_email,
                      color: AppTheme.primaryGold),
                  suffixIcon: _checkingUsername
                      ? const Padding(
                          padding: AppTheme.paddingAllMedium,
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.primaryGold)),
                        )
                      : _usernameController.text.trim().length >= 3
                          ? Icon(
                              _checkFailed
                                  ? Icons.error_outline
                                  : _usernameAvailable
                                      ? Icons.check_circle
                                      : Icons.cancel,
                              color: _checkFailed
                                  ? AppTheme.warningOrange
                                  : _usernameAvailable
                                      ? AppTheme.successGreen
                                      : AppTheme.errorRed,
                              size: 20)
                          : null,
                  filled: true,
                  fillColor: AppTheme.surfaceBlack,
                  border: OutlineInputBorder(
                      borderRadius: AppTheme.radiusMedium),
                ),
                onChanged: _onUsernameChanged,
              ),
              AppTheme.gapHeightLarge,

              // ─── كلمة المرور ───
              const Text('كلمة المرور *',
                  style: TextStyle(
                      color: AppTheme.primaryGold,
                      fontWeight: FontWeight.bold,
                      fontSize: AppTheme.fontSizeBody)),
              AppTheme.gapHeightSmall,
              TextField(
                controller: _passwordController,
                obscureText: _obscure,
                textAlign: TextAlign.left,
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: InputDecoration(
                  hintText: '8 أحرف على الأقل',
                  prefixIcon: const Icon(Icons.lock_outline,
                      color: AppTheme.primaryGold),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppTheme.textGrey,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  filled: true,
                  fillColor: AppTheme.surfaceBlack,
                  border: OutlineInputBorder(
                      borderRadius: AppTheme.radiusMedium),
                ),
              ),
              AppTheme.gapHeightLarge,

              // ─── تأكيد كلمة المرور ───
              const Text('تأكيد كلمة المرور *',
                  style: TextStyle(
                      color: AppTheme.primaryGold,
                      fontWeight: FontWeight.bold,
                      fontSize: AppTheme.fontSizeBody)),
              AppTheme.gapHeightSmall,
              TextField(
                controller: _confirmPasswordController,
                obscureText: _obscure,
                textAlign: TextAlign.left,
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: InputDecoration(
                  hintText: 'أعد إدخال كلمة المرور',
                  prefixIcon: const Icon(Icons.lock_rounded,
                      color: AppTheme.primaryGold),
                  filled: true,
                  fillColor: AppTheme.surfaceBlack,
                  border: OutlineInputBorder(
                      borderRadius: AppTheme.radiusMedium),
                ),
                onSubmitted: (_) => _submit(),
              ),
              AppTheme.gapHeightXXL,

              // ─── تنبيه حفظ البيانات ───
              Container(
                padding: AppTheme.paddingAllMedium,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGold.withOpacity(0.08),
                  borderRadius: AppTheme.radiusMedium,
                  border: Border.all(
                      color: AppTheme.primaryGold.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: AppTheme.primaryGold, size: 18),
                    AppTheme.gapWidthSmall,
                    Expanded(
                      child: Text(
                        'احفظ اسم المستخدم وكلمة المرور في مكان آمن — ستستخدمهما للدخول مستقبلاً',
                        style: TextStyle(
                            color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption),
                      ),
                    ),
                  ],
                ),
              ),
              AppTheme.gapHeightXL,

              // ─── زر الإرسال ───
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _submit,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.check_rounded, color: Colors.black),
                  label: const Text('حفظ ومتابعة',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              AppTheme.gapHeightMedium,
              const Center(
                child: Text(
                  '🔒 بياناتك مشفّرة ومحفوظة بأمان',
                  style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption),
                ),
              ),
              AppTheme.gapHeightXL,
            ],
          ),
        ),
      ),
    );
  }
}

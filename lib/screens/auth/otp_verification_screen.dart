import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:sms_autofill/sms_autofill.dart';

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({super.key});
  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> with CodeAutoFill {
  final _ctrls = List.generate(6, (_) => TextEditingController());
  final _nodes = List.generate(6, (_) => FocusNode());
  Timer? _timer;
  int _start = 60;
  bool _canResend = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    startTimer();
    listenForCode();
    SmsAutoFill().listenForCode;
  }

  @override
  void codeUpdated() {
    if (code != null) {
      _parseAndFillOtp(code!);
    }
  }

  void _parseAndFillOtp(String smsMessage) {
    // ✅ Fix for Bug #11: Parse numeric OTP instead of Arabic letters
    final regExp = RegExp(r'(\d{6})');
    final match = regExp.firstMatch(smsMessage);
    if (match != null) {
      final otpText = match.group(1)!;
      if (otpText.length == 6) {
        for (int i = 0; i < 6; i++) {
          _ctrls[i].text = otpText[i];
        }
        _verify();
      }
    }
  }

  void startTimer() {
    setState(() { _start = 60; _canResend = false; });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_start == 0) {
        setState(() { _timer?.cancel(); _canResend = true; });
      } else {
        setState(() => _start--);
      }
    });
  }

  @override
  void dispose() {
    cancel();
    unregisterListener();
    _timer?.cancel();
    for (var c in _ctrls) {
      c.dispose();
    }
    for (var n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _otp => _ctrls.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_otp.length != 6) {
      _toast('يرجى إكمال الرمز');
      return;
    }
    setState(() => _loading = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final ok = await authProvider.verifySMSOTP(_otp);

    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) {
      if (authProvider.isNewUser || authProvider.userModel?.usr == null) {
        context.go('/setup-profile');
      } else if (authProvider.isSenior) {
        context.go('/admin/dashboard');
      } else if (authProvider.isEmployee) {
        context.go('/employee/home');
      } else if (authProvider.isSupervisor) {
        context.go('/executor/tasks');
      } else if (authProvider.isPhotographer) {
        context.go('/photographer/tasks');
      } else if (authProvider.isBroker) {
        context.go('/broker/dashboard');
      } else {
        context.go('/user/home');
      }
    } else {
      _toast(authProvider.lastError ?? 'الرمز غير صحيح أو منتهي الصلاحية');
    }
  }

  void _toast(String m) => AppTheme.showSnackBar(context, SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back_ios), onPressed: () => context.pop())),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(children: [
            AppTheme.gapHeightXL,
            const Icon(Icons.sms_outlined, color: AppTheme.primaryGold, size: 56),
            AppTheme.gapHeightXXL,
            const Text('تحقق من الرمز', style: TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeXL, fontWeight: FontWeight.bold)),
            AppTheme.gapHeightMedium,
            Text(
              'أدخل الرمز المكون من 6 أرقام المرسل عبر رسالة نصية SMS إلى\n${auth.currentPhone ?? ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeMedium, height: 1.5),
            ),
            AppTheme.gapHeightXL,
            Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (i) => SizedBox(
                  width: 48,
                  child: TextField(
                    controller: _ctrls[i], focusNode: _nodes[i], textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,  // ✅ Fix for Bug #11: Use number keyboard
                    maxLength: 1,
                    style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeLarge, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(counterText: '', filled: true, fillColor: AppTheme.surfaceBlack, enabledBorder: OutlineInputBorder(borderRadius: AppTheme.radiusLarge, borderSide: const BorderSide(color: Colors.white10)), focusedBorder: OutlineInputBorder(borderRadius: AppTheme.radiusLarge, borderSide: const BorderSide(color: AppTheme.primaryGold, width: 2))),
                    onChanged: (v) {
                      if (v.isNotEmpty && i < 5) {
                        _nodes[i + 1].requestFocus();
                      } else if (v.isEmpty && i > 0) {
                        _nodes[i - 1].requestFocus();
                      }
                      if (i == 5 && v.isNotEmpty && _otp.length == 6) {
                        _verify();
                      }
                    },
                  ),
                )),
              ),
            ),
            AppTheme.gapHeightXL,
            SizedBox(width: double.infinity, height: 56, child: ElevatedButton(onPressed: _loading ? null : _verify, style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusLarge)), child: _loading ? const CircularProgressIndicator(color: Colors.black) : const Text('تحقق الآن', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeTitle)))),
            AppTheme.gapHeightXL,
            TextButton(
              onPressed: _canResend ? () {
                Provider.of<AuthProvider>(context, listen: false).sendSMSOTP(auth.currentPhone ?? '');
                startTimer();
              } : null,
              child: Text(_canResend ? 'إعادة إرسال رمز الـ SMS' : 'إعادة الإرسال خلال $_start ثانية', style: TextStyle(color: _canResend ? AppTheme.primaryGold : AppTheme.textGrey, fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
      ),
    );
  }
}

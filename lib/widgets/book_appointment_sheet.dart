import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/appointment_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/config_provider.dart';
import '../models/offer_model.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/app_utils.dart';

class BookAppointmentSheet extends StatefulWidget {
  final OfferModel offer;
  final String? requestId;
  /// If true, after successful booking we will auto-launch WhatsApp video request
  /// (with prefilled offer_number). Used only when opened from "Watch Video" path.
  final bool isVideoRequest;
  const BookAppointmentSheet({
    super.key,
    required this.offer,
    this.requestId,
    this.isVideoRequest = false,
  });

  @override
  State<BookAppointmentSheet> createState() => _BookAppointmentSheetState();
}

class _BookAppointmentSheetState extends State<BookAppointmentSheet> {
  String? _selectedDayKey;
  String? _selectedSlot; // "HH:MM-HH:MM"
  String? _selectedTime; // "HH:MM"
  List<String> _bookedSlots = [];
  bool _loadingSlots = false;
  bool _submitting = false;

  // ── Phone verification step (enforced for ALL bookings) ──
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _otpSent = false;
  bool _sendingOtp = false;
  bool _verifyingOtp = false;
  String? _phoneError;

  static const List<String> _weekKeys = [
    'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'
  ];

  String _dayName(String d) => {
        'mon': 'الاثنين',
        'tue': 'الثلاثاء',
        'wed': 'الأربعاء',
        'thu': 'الخميس',
        'fri': 'الجمعة',
        'sat': 'السبت',
        'sun': 'الأحد',
      }[d] ??
      d;

  /// هل صاحب العرض "جاهز للمعاينة في أي وقت"؟ (avl تحتوي المفتاح any)
  bool get _isAnytime => widget.offer.avl.containsKey('any');

  /// أيام الحجز المعروضة: كل أيام الأسبوع في حالة any،
  /// وإلا الأيام التي حددها صاحب العرض حصراً (القاعدة 1)
  List<String> get _availableDays {
    if (_isAnytime) return _weekKeys;
    return _weekKeys.where((k) => (widget.offer.avl[k] ?? []).isNotEmpty).toList();
  }

  /// فترات اليوم المختار: في حالة any يكون الدوام من إعدادات app_config
  /// (appt.any_from — appt.any_to، افتراضياً 09:00-21:00)
  List<String> _slotsForDay(String dayKey) {
    if (_isAnytime) {
      final cfg = context.read<ConfigProvider>().config;
      final from = cfg?.apptAnyFrom ?? '09:00';
      final to = cfg?.apptAnyTo ?? '21:00';
      return ['$from-$to'];
    }
    return widget.offer.avl[dayKey] ?? [];
  }

  /// الفارق الأدنى بين المواعيد بالدقائق (قاعدة الساعة) — من app_config
  int get _gapMins {
    final cfg = context.read<ConfigProvider>().config;
    return cfg?.apptGapMins ?? 60;
  }

  Future<void> _loadBookedSlots() async {
    if (_selectedDayKey == null) return;

    setState(() => _loadingSlots = true);

    final targetWeekday = _weekKeys.indexOf(_selectedDayKey!) + 1;
    final now = DateTime.now();
    var daysAhead = (targetWeekday - now.weekday) % 7;
    if (daysAhead < 0) daysAhead += 7;
    final date = DateTime(now.year, now.month, now.day + daysAhead);

    final slots = await context.read<AppointmentProvider>().fetchBookedSlots(
      widget.offer.id,
      date,
    );

    if (mounted) {
      setState(() {
        _bookedSlots = slots;
        _loadingSlots = false;
      });
    }
  }

  int? _timeToMins(String t) {
    final parts = t.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  /// هل هذا الوقت محظور بقاعدة عدم التعارض؟
  /// محظور إذا وقع ضمن أقل من gap_mins (ساعة) من أي موعد نشط على العرض
  /// — موعد 10:00 يحظر كل الأوقات قبل 11:00 وبعد 09:00 (القاعدة 3)
  bool _isBlocked(String time) {
    final mins = _timeToMins(time);
    if (mins == null) return false;
    for (final booked in _bookedSlots) {
      final bMins = _timeToMins(booked);
      if (bMins == null) continue;
      if ((mins - bMins).abs() < _gapMins) return true;
    }
    return false;
  }

  /// توليد أوقات (كل 30 دقيقة) بناءً على الفترة المختارة
  List<String> _generateTimeSlots(String slotStr) {
    final parts = slotStr.split('-');
    if (parts.length != 2) return [];

    final fromParts = parts[0].trim().split(':');
    final toParts = parts[1].trim().split(':');

    int startHour = int.tryParse(fromParts[0]) ?? 0;
    int startMin = int.tryParse(fromParts[1]) ?? 0;
    int endHour = int.tryParse(toParts[0]) ?? 0;
    int endMin = int.tryParse(toParts[1]) ?? 0;

    final startTotalMins = startHour * 60 + startMin;
    final endTotalMins = endHour * 60 + endMin;

    final List<String> slots = [];
    for (int total = startTotalMins; total < endTotalMins; total += 30) {
      final h = (total ~/ 60).toString().padLeft(2, '0');
      final m = (total % 60).toString().padLeft(2, '0');
      slots.add('$h:$m');
    }
    return slots;
  }

  String _errorMessage(BookingResult result) {
    switch (result.errorCode) {
      case 'NO_SUPERVISOR_AVAILABLE':
        if (result.suggestedDt != null) {
          final s = AppUtils.formatTimestamp(
            result.suggestedDt,
            pattern: 'yyyy/MM/dd — HH:mm',
          );
          return 'لا يوجد مشرف متاح للتوقيت الذي اخترته.\nأقرب موعد متاح: $s\nيمكنك اختياره أو اختيار وقت آخر.';
        }
        return 'لا يوجد مشرف متاح للتوقيت الذي اخترته حالياً. يرجى اختيار وقت آخر.';
      case 'TIME_CONFLICT_ON_OFFER':
        return 'يوجد موعد آخر على هذا العرض قريب من التوقيت المختار — يجب فارق ساعة على الأقل بين المواعيد. اختر وقتاً آخر.';
      case 'DUPLICATE_APPOINTMENT':
        return 'لديك موعد نشط مسبقاً على هذا العرض.';
      case 'DAY_NOT_AVAILABLE':
      case 'TIME_NOT_IN_AVAILABLE_SLOTS':
        return 'التوقيت المختار خارج المواعيد التي حددها صاحب العرض.';
      case 'NO_AVAILABILITY':
        return 'هذا العرض لا يحتوي مواعيد معاينة متاحة.';
      case 'OFFER_HAS_PENDING_COMPLETION':
        return 'يوجد طلب إتمام معلق على هذا العرض — لا يمكن الحجز حالياً.';
      case 'INVALID_APPOINTMENT_TIME':
        return 'التوقيت المختار أصبح في الماضي. اختر وقتاً لاحقاً.';
      case 'NETWORK':
        return 'تعذّر الاتصال بالخادم. تحقق من الشبكة وأعد المحاولة.';
      default:
        return 'تعذّر حجز الموعد. قد يكون الوقت محجوزاً أو يوجد طلب إتمام معلق.';
    }
  }

  Future<void> _confirm() async {
    if (_selectedDayKey == null || _selectedSlot == null || _selectedTime == null) {
      AppTheme.showSnackBar(context,
        const SnackBar(content: Text('يرجى اختيار اليوم والفترة والوقت')),
      );
      return;
    }
    if (_submitting) return;

    // ✅ فحص مسبق: هل لدى المستخدم موعد نشط (قيد الانتظار أو مؤكد) على هذا العرض؟
    {
      final existingAppts = context.read<AppointmentProvider>().myAppointments;
      final hasActive = existingAppts.any((a) =>
          a.offId == widget.offer.id && (a.sts == 0 || a.sts == 1));
      if (hasActive) {
        if (mounted) {
          AppTheme.showSnackBar(context,
            const SnackBar(
              content: Text('لديك موعد نشط مسبقاً على هذا العرض. لا يمكنك حجز موعد آخر إلا بعد إلغائه أو رفضه.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }
    }

    setState(() => _submitting = true);

    final auth = context.read<AuthProvider>();
    final provider = context.read<AppointmentProvider>();
    final userId = auth.userModel?.uid ?? '';

    final result = await provider.bookAppointment(
      userId: userId,
      offerId: widget.offer.id,
      selectedDayKey: _selectedDayKey!,
      selectedTime: _selectedTime!,
      brokerId: widget.offer.brkId.isNotEmpty ? widget.offer.brkId : null,
      requestId: widget.requestId,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (result.success) {
      final activeCount = result.activeCount;
      Navigator.pop(context);

      // 🚀 AUTO WHATSAPP FOR VIDEO REQUEST PATH (only if opened from video button)
      // 1. Preferred: videoRequestWhatsApp (private dedicated number set by مدير / نائب المدير)
      // 2. Fallback: videoRequestGroupLink (if provided as full wa.me or chat.whatsapp link)
      // 3. Old fallback: videoWhatsAppGroup
      // Message always contains offer_number automatically.
      if (widget.isVideoRequest && widget.offer.offerNumber != null) {
        final num = widget.offer.offerNumber!;
        final cfg = context.read<ConfigProvider>().config;

        String target = '';
        final dedicated = (cfg?.videoRequestWhatsApp ?? '').trim();
        final groupLink = (cfg?.videoRequestGroupLink ?? '').trim();

        if (dedicated.isNotEmpty) {
          // Clean phone number
          target = dedicated.replaceAll(RegExp(r'[^0-9]'), '');
          if (target.startsWith('0')) target = '963${target.substring(1)}';
          if (!target.startsWith('963')) target = '963$target';
          final prefilled = 'عرض #$num - طلب فيديو (حجز موعد تم بنجاح)';
          final msg = Uri.encodeComponent(prefilled);
          final waUrl = 'https://wa.me/$target?text=$msg';
          try {
            await launchUrl(Uri.parse(waUrl), mode: LaunchMode.externalApplication);
          } catch (_) {}
        } else if (groupLink.isNotEmpty) {
          // Launch group link (full link) or convert to wa.me if possible
          String url = groupLink;
          if (!url.startsWith('http')) {
            url = 'https://$url';
          }
          try {
            await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          } catch (_) {}
        } else {
          // Last resort old group
          String old = (cfg?.texts['videoWhatsAppGroup']?.toString() ?? '963993000000').replaceAll(RegExp(r'[^0-9]'), '');
          if (old.startsWith('0')) old = '963${old.substring(1)}';
          if (!old.startsWith('963')) old = '963$old';
          final prefilled = 'عرض #$num - طلب فيديو (حجز موعد تم بنجاح)';
          final msg = Uri.encodeComponent(prefilled);
          final waUrl = 'https://wa.me/$old?text=$msg';
          try {
            await launchUrl(Uri.parse(waUrl), mode: LaunchMode.externalApplication);
          } catch (_) {}
        }
      }

      AppTheme.showSnackBar(context,
        SnackBar(
          content: Text(
            activeCount > 1
                ? '✅ تم إرسال طلب الموعد ليوم ${_dayName(_selectedDayKey!)} — '
                  'يوجد $activeCount مواعيد نشطة على هذا العرض. سيتم التأكيد عبر المكتب.'
                : '✅ تم إرسال طلب الموعد ليوم ${_dayName(_selectedDayKey!)} — '
                  'سيتم التأكيد عبر المكتب',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      // تحديث الأوقات المحجوزة بعد الفشل (قد يكون سببه تعارضاً حديثاً)
      _loadBookedSlots();
      AppTheme.showSnackBar(context,
        SnackBar(
          content: Text(_errorMessage(result)),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  bool get _userHasVerifiedPhone {
    final u = context.read<AuthProvider>().userModel;
    if (u == null) return false;
    final ph = u.ph.trim();
    // المستخدم اللي سجل عبر الهاتف (ph مش فاضي) = هاتفو متحقق منه تلقائياً
    // لا حاجة لـ OTP إضافي — التسجيل نفسه كان عبر OTP
    // vrf هو للتوثيق الرسمي (هوية + سند) وليس لتأكيد رقم الهاتف
    return ph.isNotEmpty;
  }

  Future<void> _sendPhoneOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (!AppUtils.isValidPhone(phone)) {
      setState(() => _phoneError = 'أدخل رقم هاتف صحيح (09XXXXXXXX)');
      return;
    }
    setState(() {
      _sendingOtp = true;
      _phoneError = null;
    });
    final auth = context.read<AuthProvider>();
    final ok = await auth.sendSMSOTP(phone);
    if (!mounted) return;
    setState(() {
      _sendingOtp = false;
      if (ok) {
        _otpSent = true;
        _phoneError = null;
      } else {
        _phoneError = auth.lastError ?? 'فشل إرسال الرمز';
      }
    });
  }

  Future<void> _verifyPhoneOtp() async {
    final code = _otpCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _phoneError = 'أدخل الرمز كاملاً (6 أرقام)');
      return;
    }
    setState(() {
      _verifyingOtp = true;
      _phoneError = null;
    });
    final auth = context.read<AuthProvider>();
    final ok = await auth.verifySMSOTP(code);
    if (!mounted) return;
    if (ok) {
      // Refresh to get updated ph/vrf
      await auth.refreshUser();
      setState(() {
        _verifyingOtp = false;
        _otpSent = false;
        _otpCtrl.clear();
      });
      // After successful verify, the build will switch to booking UI automatically
      // because _userHasVerifiedPhone will now be true
    } else {
      setState(() {
        _verifyingOtp = false;
        _phoneError = auth.lastError ?? 'الرمز غير صحيح أو منتهي الصلاحية';
      });
    }
  }

  Widget _buildPhoneVerificationUI(AuthProvider auth) {
    final phone = auth.userModel?.ph ?? '';
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(AppTheme.paddingXXL),
        decoration: const BoxDecoration(
          // 🩹 (2026-08-20): فاتح بدل deepBlack — كان النص الداخلي أسود على أسود
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Icon(Icons.phone_android, color: AppTheme.primaryGold, size: 48),
              ),
              AppTheme.gapHeightLarge,
              const Text(
                'تأكيد رقم الهاتف مطلوب',
                style: TextStyle(
                    color: AppTheme.textWhite,
                    fontSize: AppTheme.fontSizeHeadline,
                    fontWeight: FontWeight.bold),
              ),
              AppTheme.gapHeightSmall,
              const Text(
                'لحجز موعد معاينة يجب أن يكون رقم هاتفك متحققاً منه عبر رمز SMS. هذا الإجراء يضمن الجدية ويمنع الاستغلال.',
                style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeMedium, height: 1.5),
              ),
              AppTheme.gapHeightXL,

              if (phone.isEmpty) ...[
                // Email-only user: enter phone
                const Text('رقم الهاتف (09XXXXXXXX):',
                    style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
                AppTheme.gapHeightSmall,
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSubtitle),
                  decoration: InputDecoration(
                    hintText: '09XXXXXXXX',
                    prefixIcon: const Icon(Icons.phone, color: AppTheme.primaryGold),
                    filled: true,
                    fillColor: AppTheme.surfaceBlack,
                    border: OutlineInputBorder(
                      borderRadius: AppTheme.radiusMedium,
                      borderSide: BorderSide(color: AppTheme.primaryGold.withOpacity(0.3)),
                    ),
                  ),
                ),
                AppTheme.gapHeightMedium,
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _sendingOtp ? null : _sendPhoneOtp,
                    child: _sendingOtp
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.deepBlack))
                        : const Text('إرسال رمز التحقق SMS'),
                  ),
                ),
              ] else ...[
                // Has phone but unverified? (rare)
                Text('رقمك المسجل: $phone', style: const TextStyle(color: AppTheme.textWhite)),
                AppTheme.gapHeightMedium,
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _sendingOtp ? null : () async {
                      final ok = await context.read<AuthProvider>().sendSMSOTP(phone);
                      if (mounted && ok) setState(() => _otpSent = true);
                    },
                    child: _sendingOtp
                        ? const CircularProgressIndicator(color: AppTheme.deepBlack)
                        : const Text('إعادة إرسال رمز التحقق'),
                  ),
                ),
              ],

              if (_otpSent) ...[
                AppTheme.gapHeightLarge,
                const Text('أدخل رمز التحقق المكون من 6 أرقام:',
                    style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
                AppTheme.gapHeightSmall,
                TextField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeHeadline, letterSpacing: 8),
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    hintText: '123456',
                    counterText: '',
                  ),
                ),
                AppTheme.gapHeightMedium,
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _verifyingOtp ? null : _verifyPhoneOtp,
                    child: _verifyingOtp
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.deepBlack))
                        : const Text('تحقق واستمر في الحجز'),
                  ),
                ),
              ],

              if (_phoneError != null) ...[
                AppTheme.gapHeightMedium,
                Text(_phoneError!, style: const TextStyle(color: AppTheme.errorRed)),
              ],

              AppTheme.gapHeightXL,
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء', style: TextStyle(color: AppTheme.textGrey)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isLoggedIn = auth.isLoggedIn;

    // 🔒 2026-08-20: حارس دفاعي بالمنبع — صاحب العرض لا يستطيع حجز موعد
    // على عرضه مهما كان مسار فتح الورقة (السيرفر يرفض بـ CANNOT_BOOK_OWN_OFFER
    // وهنا لا نظهر نموذج الحجز إطلاقاً).
    final myUid = auth.userModel?.uid ?? '';
    final isMyOwnOffer = myUid.isNotEmpty && myUid == widget.offer.usrId;
    if (isMyOwnOffer) {
      return SafeArea(
        child: Container(
          padding: const EdgeInsets.all(30),
          decoration: const BoxDecoration(
            // 🩹 (2026-08-20): فاتح بدل deepBlack — كان النص الداخلي أسود على أسود
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.block, color: AppTheme.warningOrange, size: 60),
            AppTheme.gapHeightLarge,
            const Text('لا يمكنك حجز موعد على العرض الخاص بك',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.textWhite,
                    fontSize: AppTheme.fontSizeHeadline,
                    fontWeight: FontWeight.bold)),
            AppTheme.gapHeightSmall,
            const Text(
              'مواعيد المعاينة مخصصة للعملاء الراغبين بمعاينة العرض — أنت صاحب العرض.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeMedium, height: 1.5),
            ),
            AppTheme.gapHeightXL,
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGold,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('إغلاق',
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      );
    }

    // الزائر غير المسجّل — نعرض رسالة تسجيل الدخول بدل الـ sheet
    if (!isLoggedIn) {
      return SafeArea(
        child: Container(
          padding: const EdgeInsets.all(30),
          decoration: const BoxDecoration(
            // 🩹 (2026-08-20): فاتح بدل deepBlack — كان النص الداخلي أسود على أسود
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_outline, color: AppTheme.primaryGold, size: 60),
              AppTheme.gapHeightLarge,
              const Text('يجب تسجيل الدخول',
                  style: TextStyle(
                      color: AppTheme.textWhite,
                      fontSize: AppTheme.fontSizeHeadline,
                      fontWeight: FontWeight.bold)),
              AppTheme.gapHeightSmall,
              const Text(
                'لحجز موعد معاينة يجب أن تكون مسجّلاً في التطبيق.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeMedium, height: 1.5),
              ),
              AppTheme.gapHeightXXL,
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    context.push('/login');
                  },
                  child: const Text('تسجيل الدخول',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              AppTheme.gapHeightSmall,
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('لاحقاً',
                    style: TextStyle(color: AppTheme.textGrey)),
              ),
            ]),
          ),
        ),
      );
    }

    // ✅ NEW: Enforce verified phone for ALL appointment bookings (independent + video path)
    // WhatsApp-registered users (ph present + vrf > 0) skip this.
    // Email users (no ph or vrf=0): show phone entry + OTP flow.
    if (!_userHasVerifiedPhone) {
      return _buildPhoneVerificationUI(auth);
    }

    final days = _availableDays;
    final hasAvailability = widget.offer.avl.isNotEmpty && days.isNotEmpty;
    final media = MediaQuery.of(context);

    // ارتفاع أقصى + تمرير داخلي لمنع الـ Overflow مهما بلغ عدد الأوقات
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
        decoration: const BoxDecoration(
          // 🩹 (2026-08-20): فاتح بدل deepBlack — كان النص الداخلي أسود على أسود
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + media.viewInsets.bottom),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 50, height: 5,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGold,
                  borderRadius: AppTheme.radiusMedium,
                ),
              ),
            ),
            AppTheme.gapHeightXL,
            const Text('حجز موعد معاينة',
                style: TextStyle(
                    color: AppTheme.textWhite,
                    fontSize: AppTheme.fontSizeHeadline,
                    fontWeight: FontWeight.bold)),
            AppTheme.gapHeightSmall,
            // تنبيه الدور والمكتب
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primaryGold.withOpacity(0.1),
                borderRadius: AppTheme.radiusSmall,
                border: Border.all(color: AppTheme.primaryGold.withOpacity(0.4)),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline, color: AppTheme.primaryGold, size: 18),
                AppTheme.gapWidthSmall,
                Expanded(
                  child: Text(
                    'الحجز يتم عبر إدارة المكتب لضمان الجدية. يرجى ملاحظة أنه قد يكون هناك طلبات أخرى تسبقك في الدور.',
                    style: TextStyle(
                        color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeSmall, height: 1.4),
                  ),
                ),
              ]),
            ),
            AppTheme.gapHeightSmall,
            // تنبيه التوثيق القانوني المأجور
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.successGreen.withOpacity(0.08),
                borderRadius: AppTheme.radiusSmall,
                border: Border.all(color: AppTheme.successGreen.withOpacity(0.3)),
              ),
              child: const Row(children: [
                Icon(Icons.verified_user_outlined, color: AppTheme.successGreen, size: 18),
                AppTheme.gapWidthSmall,
                Expanded(
                  child: Text(
                    'يتولى القسم القانوني في المكتب تدقيق ثبوتيات الملكية وتنظيم العقود المعتمدة عند طلب إتمام المعاملة.',
                    style: TextStyle(color: AppTheme.successGreen, fontSize: AppTheme.fontSizeCaption, height: 1.4, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
            AppTheme.gapHeightLarge,

            if (!hasAvailability)
              const Center(
                child: Text('لا توجد مواعيد متاحة حالياً للمعاينة.',
                    style: TextStyle(color: AppTheme.textGrey)),
              )
            else ...[
              if (_isAnytime) ...[
                Row(children: [
                  const Icon(Icons.event_available,
                      color: AppTheme.primaryGold, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'صاحب العرض جاهز للمعاينة في أي يوم — الدوام من '
                      '${context.read<ConfigProvider>().config?.apptAnyFrom ?? '09:00'}'
                      ' حتى '
                      '${context.read<ConfigProvider>().config?.apptAnyTo ?? '21:00'}',
                      style: const TextStyle(
                          color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall, height: 1.4),
                    ),
                  ),
                ]),
                AppTheme.gapHeightSmall,
              ],
              const Text('1. اختر اليوم:',
                  style: TextStyle(
                      color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
              AppTheme.gapHeightSmall,
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: days.map((key) {
                  final selected = _selectedDayKey == key;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedDayKey = key;
                          _selectedSlot = null;
                          _selectedTime = null;
                        });
                        _loadBookedSlots();
                      },
                      borderRadius: AppTheme.radiusXL,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.primaryGold
                              : AppTheme.surfaceBlack,
                          borderRadius: AppTheme.radiusXL,
                          border: Border.all(color: AppTheme.primaryGold),
                        ),
                        child: Text(
                          _dayName(key),
                          style: TextStyle(
                            color: selected ? AppTheme.deepBlack : AppTheme.primaryGold,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              AppTheme.gapHeightLarge,

              if (_selectedDayKey != null) ...[
                const Text('2. اختر الفترة:',
                    style: TextStyle(
                        color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
                AppTheme.gapHeightSmall,
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _slotsForDay(_selectedDayKey!).map((slot) {
                    final selected = _selectedSlot == slot;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _selectedSlot = slot;
                        _selectedTime = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.primaryGold.withOpacity(0.2)
                              : AppTheme.surfaceBlack,
                          borderRadius: AppTheme.radiusXL,
                          border: Border.all(
                            color: selected
                                ? AppTheme.primaryGold
                                : AppTheme.textGrey.withOpacity(0.4),
                          ),
                        ),
                        child: Text(
                          slot.replaceAll('-', ' — '),
                          style: TextStyle(
                            color: selected ? AppTheme.primaryGold : AppTheme.textGrey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                AppTheme.gapHeightLarge,
              ],

              if (_selectedSlot != null) ...[
                const Text('3. اختر الوقت المحدد:',
                    style: TextStyle(
                        color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
                AppTheme.gapHeightSmall,
                if (_loadingSlots)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: CircularProgressIndicator(color: AppTheme.primaryGold),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _generateTimeSlots(_selectedSlot!).map((time) {
                      // قاعدة عدم التعارض: يُحظر الوقت الواقع ضمن أقل من
                      // ساعة من أي موعد نشط على هذا العرض
                      final isBooked = _isBlocked(time);
                      final selected = _selectedTime == time;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: isBooked
                            ? null
                            : () => setState(() => _selectedTime = time),
                          borderRadius: AppTheme.radiusMedium,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isBooked
                                  ? AppTheme.textGrey.withOpacity(0.1)
                                  : (selected ? AppTheme.primaryGold : AppTheme.surfaceBlack),
                              borderRadius: AppTheme.radiusMedium,
                              border: Border.all(
                                color: isBooked
                                    ? AppTheme.textGrey.withOpacity(0.2)
                                    : (selected ? AppTheme.primaryGold : AppTheme.textGrey.withOpacity(0.3)),
                              ),
                            ),
                            child: Text(
                              time,
                              style: TextStyle(
                                color: isBooked
                                    ? AppTheme.textGrey
                                    : (selected ? AppTheme.deepBlack : AppTheme.textWhite),
                                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                if (_bookedSlots.isNotEmpty && !_loadingSlots) ...[
                  AppTheme.gapHeightSmall,
                  const Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: AppTheme.textGrey),
                      AppTheme.gapWidthXS,
                      Expanded(
                        child: Text(
                          'الأوقات المظللة محجوزة أو ضمن فارق الساعة من موعد آخر',
                          style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption),
                        ),
                      ),
                    ],
                  ),
                ],
                AppTheme.gapHeightXL,
              ],

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: (_selectedTime != null && !_submitting) ? _confirm : null,
                  child: _submitting
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.deepBlack),
                        )
                      : const Text('تأكيد طلب الموعد',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
            AppTheme.gapHeightXL,
          ],
        ),
      ),
    ),
    );
  }
}

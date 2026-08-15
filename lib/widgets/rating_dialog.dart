import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../core/network/supabase_service.dart';
import '../providers/auth_provider.dart';

/// ⭐ Dialog لتقييم طرف آخر بعد صفقة/موعد مكتمل.
///
/// يكتب في جدول `ratings` (reviewer_uid, target_uid, stars, comment).
/// Trigger في DB يمنح 200 نقطة للمستهدف إذا كانت 5 نجوم.
///
/// مرجع: docs/LOGIC_SPEC.md §3.3 + supabase/migrations/2026_06_06_points_refinement.sql
class RatingDialog extends StatefulWidget {
  final String targetUid;
  final String targetName; // اسم للعرض فقط (لا يُحفظ — الخصوصية)
  final String? refLabel; // مثلاً "بعد موعد المعاينة"

  const RatingDialog({
    super.key,
    required this.targetUid,
    required this.targetName,
    this.refLabel,
  });

  /// عرض الـ dialog مع التحقق من تسجيل الدخول. يُعيد true إذا تم الإرسال.
  static Future<bool> show({
    required BuildContext context,
    required String targetUid,
    required String targetName,
    String? refLabel,
  }) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      AppTheme.showSnackBar(context,
        const SnackBar(content: Text('سجّل دخولك أولاً لإرسال تقييم')),
      );
      return false;
    }
    if (auth.userModel!.uid == targetUid) {
      AppTheme.showSnackBar(context,
        const SnackBar(content: Text('لا يمكنك تقييم نفسك')),
      );
      return false;
    }
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RatingDialog(
        targetUid: targetUid,
        targetName: targetName,
        refLabel: refLabel,
      ),
    );
    return result == true;
  }

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  int _stars = 0;
  final _commentCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars == 0) {
      AppTheme.showSnackBar(context,
        const SnackBar(content: Text('اختر عدد النجوم من 1 إلى 5')),
      );
      return;
    }
    setState(() => _sending = true);
    final auth = context.read<AuthProvider>();
    try {
      // ⭐ RATE-001 (2026-08-15) — بلاغ المالك: «إرسال التقييم فشل».
      // كان هنا إدراج REST مباشر في جدول `ratings`، وسياسة الإدراج هي
      // `auth.uid() = reviewer_uid`. لكن التطبيق يسجّل الدخول **بجلسة
      // مخصّصة** (staff_session_token) لا بجلسة Supabase ⇒ auth.uid()
      // تساوي NULL ⇒ **كل تقييم كان يُرفض** مهما فعل المستخدم.
      // (التعليق القديم ادّعى أن التدقيق أكّد سلامته — وهو غير صحيح.)
      // الآن عبر Edge بمفتاح الخدمة الذي يتخطى RLS بعد التحقق من الجلسة.
      final res = await SupabaseService().invokeFunction('user-account', body: {
        'action': 'create_rating',
        'user_uid': auth.userModel!.uid,
        'target_uid': widget.targetUid,
        'stars': _stars,
        'comment': _commentCtrl.text.trim(),
      });
      final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : null;
      if (data == null || data['success'] != true) {
        // §13: نرمي بنصّ الخطأ الخادمي ليُترجَم في catch بدل ابتلاعه.
        throw Exception(data?['error']?.toString() ?? 'RATING_FAILED');
      }

      if (!mounted) return;

      // ✅ منحة الـ ٥ نجوم (+200) تُمنح سيرفرياً من trigger جدول ratings —
      // أُزيل استدعاء rating_bonus المكرر (كان يضاعف المنحة +200 ×2 ومسار سكب).

      Navigator.pop(context, true);
      AppTheme.showSnackBar(context,
        SnackBar(
          content: Text(_stars == 5
              ? '⭐ شكراً! تم منح الطرف الآخر 200 نقطة مكافأة'
              : '✅ تم إرسال تقييمك'),
          backgroundColor: AppTheme.successGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      final raw = e.toString();
      String userMsg = '❌ فشل الإرسال';
      if (raw.contains('completed a deal/appointment')) {
        userMsg = 'لا يمكن التقييم قبل إتمام موعد أو صفقة مع هذا الطرف.';
      } else if (raw.contains('ratings_unique_reviewer_target') ||
          raw.contains('duplicate key')) {
        userMsg = 'لقد قيّمت هذا الطرف مسبقاً (تقييم واحد فقط مسموح).';
      } else if (raw.contains('ratings_no_self')) {
        userMsg = 'لا يمكنك تقييم نفسك.';
      }
      AppTheme.showSnackBar(context,
        SnackBar(content: Text(userMsg)),
      );
    }
  }

  String _starLabel(int s) {
    switch (s) {
      case 1: return 'سيء جداً';
      case 2: return 'سيء';
      case 3: return 'متوسط';
      case 4: return 'جيد';
      case 5: return 'ممتاز';
      default: return 'اختر تقييماً';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceBlack,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🧱 UI-OVF-002 (2026-08-15): بلاغ المالك «أوفرفلو من اليمين».
          // العنوان صف بلا Expanded ⇒ اسم طويل يدفع النص خارج الحوار.
          const Row(children: [
            Icon(Icons.star_rate, color: AppTheme.primaryGold),
            AppTheme.gapWidthSmall,
            Expanded(
              child: Text('تقييم تجربتك',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppTheme.textWhite)),
            ),
          ]),
          AppTheme.gapHeightXS,
          Text(
            widget.refLabel != null
                ? '${widget.refLabel} • مع: ${widget.targetName}'
                : 'مع: ${widget.targetName}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // نجوم تفاعلية
          // 🧱 UI-OVF-002: 5 نجوم × (36px + هوامش) تتجاوز عرض الحوار على
          // الشاشات الضيقة أو مع تكبير الخط ⇒ فيضان أفقي.
          // FittedBox يُصغّر الصف بالتناسب بدل أن يفيض (نفس مبدأ FitTile).
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final filled = i < _stars;
                return IconButton(
                  onPressed: _sending ? null : () => setState(() => _stars = i + 1),
                  icon: Icon(
                    filled ? Icons.star : Icons.star_border,
                    color: filled ? AppTheme.primaryGold : AppTheme.textGrey,
                    size: 36,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  constraints: const BoxConstraints(),
                );
              }),
            ),
          ),
          AppTheme.gapHeightXS,
          Center(
            child: Text(
              _starLabel(_stars),
              style: TextStyle(
                  color: _stars > 0
                      ? AppTheme.primaryGold
                      : AppTheme.textGrey,
                  fontSize: AppTheme.fontSizeBody,
                  fontWeight: FontWeight.w500),
            ),
          ),
          AppTheme.gapHeightMedium,
          TextField(
            controller: _commentCtrl,
            maxLines: 3,
            maxLength: 200,
            enabled: !_sending,
            style: const TextStyle(color: AppTheme.textWhite),
            decoration: const InputDecoration(
              hintText: 'تعليقك (اختياري)',
              hintStyle: TextStyle(color: AppTheme.textGrey),
              border: OutlineInputBorder(),
              counterStyle: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context, false),
          child: const Text('لاحقاً',
              style: TextStyle(color: AppTheme.textGrey)),
        ),
        ElevatedButton.icon(
          onPressed: _sending ? null : _submit,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.deepBlack))
              : const Icon(Icons.send, color: AppTheme.deepBlack, size: 18),
          label: const Text('إرسال',
              style: TextStyle(
                  color: AppTheme.deepBlack, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGold),
        ),
      ],
    );
  }
}

import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/network/supabase_service.dart';
import '../../core/theme/app_theme.dart';

/// 📡 شاشة «إعدادات قنوات البوش» (2026-07-27 «الإشعار-بلس»)
///
/// * «**وش نوّر جرس التطبيق؟**» — تظهير «غير مقروء» يتبع قبول البوش الحقيقي
///   لهذا الجهاز أو أي جهاز ضمن نفس الفصيلة (أندرويد/iOS/ويب).
/// * مفتاح يدوي لكل قناة (فعلّل عائل).
/// * سياسة المفتاح: إطفاء قناة مفعّلة أصلاً يستلزم تفعيل واحدة أخرى —
///   «ما بخلّي حدا يبقى بلا قنوات».
class PushChannelsScreen extends StatefulWidget {
  const PushChannelsScreen({super.key});
  @override
  State<PushChannelsScreen> createState() => _PushChannelsScreenState();
}

class _PushChannelsScreenState extends State<PushChannelsScreen> {
  /// ميّز DCOL بالأرقام مباشرة حتى ما يصير تعارض مع الثوابت لو اتغيرت
  static const Map<int, (String, String)> _labels = {
    1: ('FCM', '📩 بوش التطبيق — أندرويد/iOS'),
    2: ('إيميل', '📮 البريد الإلكتروني'),
    3: ('واتساب', '💬 رسائل واتساب'),
    4: ('تلغرام', '✈️ بوت تلغرام'),
    5: ('سجل الإشعارات', '📋 خانة الإشعارات بالتطبيق'),
    6: ('طوارئ WebPush', '🆘 بوش عبر متصفح الموبايل (hybrid)'),
    7: ('سجل الموظفين الداخلي', '🗂 شاشة الحالات الداخلية'),
  };

  /// فصيلة المنصة لسؤال التظهير (أندرويد/iOS) أو جفة ويب
  static int _platformFam() {
    if (kIsWeb) return 0;
    try {
      final p = Platform.operatingSystem.toLowerCase();
      if (p == 'android') return 1;
      if (p == 'ios') return 2;
      return 0;
    } catch (_) {
      return 0;
    }
  }

  bool _loading = true;
  bool _pushAllowed = false;
  List<int> _allowedFam = [];
  /// chn → منع؟
  Map<int, bool> _blocked = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final res = await SupabaseService().invokeFunction('user-account',
          body: {'action': 'notification_settings', 'what': 'push'});
      final d = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      final fam = _platformFam();
      final allowed = <String>[];
      final pushAllowed = d['push_allowed'] == true;
      for (final a in (d['push_allowed_by'] as List? ?? const [])) {
        allowed.add(a.toString());
      }
      final famIds = <int>{};
      if (pushAllowed) famIds.add(fam);
      for (final a in allowed) {
        final m = RegExp(r'fam(\d+)').firstMatch(a);
        if (m != null) famIds.add(int.parse(m.group(1)!));
      }
      final blocked = <int, bool>{};
      final raw = d['channels'] as Map? ?? const {};
      raw.forEach((k, v) {
        final id = int.tryParse(k.toString());
        if (id != null) blocked[id] = v == true;
      });
      if (!mounted) return;
      setState(() {
        _pushAllowed = pushAllowed;
        _allowedFam = famIds.toList();
        _blocked = blocked;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── تفعيل/تعطيل قناة يدوياً (sign بلا نقط) — policy: ما يبقى كلها مطفية ──
  Future<void> _toggle(int chn, bool enable) async {
    final wasBlocked = _blocked[chn] == true;
    if (enable && !wasBlocked) return;
    if (!enable && wasBlocked) {
      final stillEnabled = _labels.keys.where((c) => c != chn && _blocked[c] != true).length;
      if (stillEnabled == 0) { AppTheme.showSnackBar(context, const SnackBar(content: Text('فعّل قناة ثانية قبل ما تطفي هاي — ما بخلّي حدا يبقى بلا قنوات'))); return; }
    }
    // 🔧 BUG-018 (أُصلح 2026-08-14): كان الحفظ يمرّ بمسارين **كلاهما معطّل**:
    //   1. كتابة مباشرة على `internal_config` بمفتاح anon ⇒ يرفضها RLS (42501)
    //   2. نداء إيدج باسم `user-devices` — **دالة غير موجودة إطلاقاً**
    // وكلا الخطأين مبتلَع بـ`catch(_){}` (مخالفة §13) ⇒ المستخدم يرى المفتاح
    // يتبدّل ثم يعود لحاله عند أول تحديث، بلا أي رسالة تشرح لماذا.
    // الآن: مسار واحد حقيقي عبر user-account، والفشل يُعلَن ويُعاد المفتاح.
    final prev = _blocked[chn] == true;
    setState(() { _blocked[chn] = !enable; });
    try {
      final res = await SupabaseService().invokeFunction('user-account', body: {
        'action': 'set_push_channel',
        'channel': chn,
        'blocked': !enable,
      });
      final d = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (d['success'] != true) {
        if (!mounted) return;
        setState(() { _blocked[chn] = prev; });
        AppTheme.showSnackBar(context, SnackBar(
          content: Text(d['detail']?.toString() ?? 'تعذّر حفظ التغيير — حاول مجدداً'),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _blocked[chn] = prev; });
      AppTheme.showSnackBar(context, const SnackBar(
        content: Text('تعذّر حفظ التغيير — تحقّق من اتصالك'),
      ));
    }
  }

  Widget _famChip(String fam, List<String> enabledBy) {
    final en = enabledBy.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: (en ? AppTheme.successGreen : Colors.white10).withOpacity(en ? 0.12 : 0.06),
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: (en ? AppTheme.successGreen : Colors.white24).withOpacity(0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(en ? Icons.check_circle : Icons.help_outline,
            color: en ? AppTheme.successGreen : AppTheme.textGrey, size: 18),
        AppTheme.gapWidthSmall,
        Expanded(
          child: Text(
            en ? '$fam ✓ مُنوّرة عبر: ${enabledBy.join('، ')}'
               : '$fam — ما في جهاز بهالفصيلة قابل البوش بعد',
            style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSmall, height: 1.5),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fam = _platformFam();
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('📡 إعدادات قنوات البوش'),
        backgroundColor: AppTheme.scaffoldBackground,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGold))
          : ListView(padding: AppTheme.paddingAllLarge, children: [
              const Text('وش نوّر جرس التطبيق؟', style: TextStyle(color: AppTheme.primaryGold, fontSize: 15, fontWeight: FontWeight.bold)),
              AppTheme.gapHeightXS,
              const Text(
                'سجل الجرس بيتحوّل «غير مقروء» بس لما يان البوش يقبل فعلياً بجهاز '
                'واحد عالأقل من أجهزتك المفعل عليها الحساب (ومن أوفلاط القنوات '
                'الموسومة «hybrid»). فشل/رفض ⇒ يبقى مقروءاً وتكمل دوريتك عليه.',
                style: TextStyle(color: AppTheme.textGrey, fontSize: 11.5, height: 1.6),
              ),
              AppTheme.gapHeightSmall,
              _famChip('🤖 أندرويد / 🍎 iOS', [
                if (_pushAllowed && fam != 0) 'هذا الجهاز',
                for (final f in _allowedFam) if (f != 0) 'جهاز آخر (فصيلة $f)',
                if (_allowedFam.contains(0)) 'ويب',
              ]),
              AppTheme.gapHeightLarge,
              const Text('مفاتيح القنوات (فعلّل عائل)', style: TextStyle(color: AppTheme.primaryGold, fontSize: 15, fontWeight: FontWeight.bold)),
              AppTheme.gapHeightSmall,
              for (final e in _labels.entries) Builder(builder: (_) {
                final chn = e.key;
                final (nm, desc) = e.value;
                final enabled = _blocked[chn] != true;
                return SwitchListTile(
                  value: enabled,
                  activeColor: AppTheme.primaryGold,
                  title: Text('$nm (chn $chn)', style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeBody)),
                  subtitle: Text(desc + (enabled ? '' : ' — مطفية'),
                      style: TextStyle(color: enabled ? AppTheme.textGrey : AppTheme.errorRed, fontSize: AppTheme.fontSizeCaption)),
                  onChanged: (v) => _toggle(chn, v),
                );
              }),
              AppTheme.gapHeightMedium,
              Container(
                padding: AppTheme.paddingAllMedium,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBlack,
                  borderRadius: AppTheme.radiusMedium,
                  border: Border.all(color: AppTheme.primaryGold.withOpacity(0.25)),
                ),
                child: const Text(
                  '💡 «إشعارات» القديمة بتضل موجودة — هاد البروفايل هو «قنوات البوش + التظهير» '
                  'وفق قرار المالك 2026-07-27: التظهير يتبع قبول البوش، والمفاتيح فعلّل عائل.',
                  style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption, height: 1.6),
                ),
              ),
            ]),
    );
  }
}

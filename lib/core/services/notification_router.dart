import '../../models/user_model.dart';

/// 🧭 الموجّه الموحّد للإشعارات (أُضيف 2026-08-14)
///
/// ## المشكلة التي يحلّها
/// كان في التطبيق **مساران متباينان** للتنقّل من الإشعار:
///   • `notifications_screen` يوجّه بـ`tp` (رقم عام) ⇒ يعرف حالتين فقط.
///   • `fcm_service` يوجّه بـ`type` (نص) ⇒ يعرف 6 حالات.
/// فنفس الحدث يوصل المستخدم لمكانين مختلفين حسب طريقة الفتح، و**38% من
/// الإشعارات لا تستجيب للضغط إطلاقاً** (171 من 445 عند القياس).
///
/// ## لماذا `act` لا `tp`؟
/// قياس حي أثبت أن `tp` غير موثوق: `photography_reminder_1h` مسجَّل بـ`tp=1`
/// **و**`tp=2` معاً — نفس الحدث بتصنيفين. بينما `act` دقيق (35+ قيمة) ومعبّأ
/// بانتظام لأن معظم الدوال تمر بـ`notify_user(..., p_action)`.
///
/// ## التصنيف الثلاثي
///   🎯 actionable  → ينتقل لوجهة محددة (المحادثة، العرض، المهمة...)
///   📄 contextual  → ينتقل للشاشة الأم (سجل الدفعات، طلباتي...)
///   ℹ️ informational → لا ينتقل **ولا يعرض سهماً** (وعد كاذب لو عرضه)
class NotificationRouter {
  const NotificationRouter._();

  /// إشعارات معلوماتية بحتة — لا وجهة لها (تنتهي القصة عندها)
  static const Set<String> _informational = {
    'probe_notify_user', // إشعار اختباري قديم
  };

  /// أفعال تخصّ أدواراً محددة — تُمنع عن غيرهم (الراوتر يرفضها أصلاً،
  /// لكن المنع المبكر يعطي رسالة مفهومة بدل شاشة رفض)
  static const Map<String, List<int>> _roleGuard = {
    'expediting_task_assigned': [UserRole.expediter],
    'expediting_item_updated': [UserRole.lawyer, UserRole.deputy, UserRole.manager],
    'expediting_item_revision_requested': [UserRole.expediter],
    'expediting_revision_requested': [UserRole.expediter],
    'expediting_task_completed': [UserRole.lawyer, UserRole.deputy, UserRole.manager],
    'expediting_task_approved': [UserRole.expediter],
    'photography_task_assigned': [UserRole.photographer],
    'photography_task_created': [UserRole.photographer],
    'photography_task_started': [UserRole.deputy, UserRole.manager, UserRole.employee],
    // ACT-001: طلب الإتمام يراجعه موظف المكتب فأعلى (الإيدج يشترط role>=3
    // ودالة القاعدة تمنع المنفّذ من اعتماد طلبه)
    'completion_request': [UserRole.employee, UserRole.deputy, UserRole.manager],
    'photography_task_submitted': [UserRole.deputy, UserRole.manager, UserRole.employee],
    'legal_consultation_new': [UserRole.lawyer],
    'legal_consultation_resubmitted': [UserRole.lawyer],
    'legal_consultation_nudge': [UserRole.lawyer],
    'legal_appointment_nudge': [UserRole.lawyer],
    'consultation_reactivated': [UserRole.lawyer],
    'legal_user_joined': [UserRole.lawyer],
    'legal_renewal_paid_ready': [UserRole.lawyer],
    'legal_consultation_admin': [UserRole.deputy, UserRole.manager],
    'legal_consultation_escalated': [UserRole.deputy, UserRole.manager],
  };

  /// نتيجة الحل: المسار أو سبب عدم التنقّل
  static NotificationTarget resolve({
    required String act,
    required String refId,
    int tp = -1,
    int role = UserRole.user,
  }) {
    final a = act.trim();

    // ① معلوماتي بحت
    if (a.isEmpty && refId.isEmpty) {
      return const NotificationTarget.none();
    }
    if (_informational.contains(a)) {
      return const NotificationTarget.none();
    }

    // ② حارس الدور
    final allowed = _roleGuard[a];
    if (allowed != null && !allowed.contains(role)) {
      // المدير له صلاحية شاملة
      if (role != UserRole.manager) {
        return const NotificationTarget.denied('هذا الإشعار يخصّ دوراً آخر');
      }
    }

    // ③ الخريطة الكاملة (8 أقسام · 35+ فعلاً)
    switch (a) {
      // ─────────── ⚖️ الاستشارة القانونية ───────────
      case 'chat_started':
      case 'chat_message':
      case 'chat_renewed':
      case 'chat_extended':
      case 'legal_lawyer_ready':
      case 'legal_user_joined':
      case 'legal_session_auto_started':
      case 'legal_session_started':
      case 'legal_session_ended':
      case 'legal_renewal_paid_ready':
        return refId.isEmpty
            ? const NotificationTarget('/legal/consultations')
            : NotificationTarget('/legal/chat/$refId');

      case 'legal_consultation_new':
      case 'legal_consultation_resubmitted':
      case 'legal_consultation_nudge':
      case 'consultation_reactivated':
        return const NotificationTarget('/lawyer/dashboard');

      case 'legal_consultation_admin':
      case 'legal_consultation_escalated':
        return const NotificationTarget('/admin/legal-consultations');

      case 'legal_consultation_update':
      case 'legal_consultation_reassigned':
      case 'legal_consultation_completed':
      case 'legal_consultation_rejected':
      case 'legal_consultation_need_info':
      case 'consultation_credit_granted':
        return const NotificationTarget('/legal/consultations');

      case 'legal_appointment_update':
      case 'legal_appointment_reminder':
      case 'legal_onsite_confirmed':
        return role == UserRole.lawyer
            ? const NotificationTarget('/lawyer/dashboard')
            : const NotificationTarget('/user/my-appointments');

      case 'legal_waitlist_available':
      case 'legal_payment_needs_new_slot':
        return const NotificationTarget('/legal/consultations');

      case 'legal_appointment_nudge':
        return const NotificationTarget('/lawyer/dashboard');

      // ─────────── 📸 التصوير العقاري (أكبر قسم: 155 إشعاراً) ───────────
      case 'photography_request_new':
      case 'photography_task_submitted':
      case 'photography_task_started':
        return const NotificationTarget('/admin/photography-management');

      case 'photography_task_assigned':
      case 'photography_task_created':
      case 'photography_reminder_1h':
        // المصوّر يذهب لمهامه · العميل لشاشة خدمته
        return role == UserRole.photographer
            ? const NotificationTarget('/photographer/tasks')
            : const NotificationTarget('/user/photography');

      case 'photography_request_result':
      case 'photography_request_cancelled':
      case 'photography_photographer_assigned':
      case 'photography_task_submitted_client':
        return const NotificationTarget('/user/photography');

      case 'photography_offer_published':
        return refId.isEmpty
            ? const NotificationTarget('/user/my-offers')
            : NotificationTarget('/offer/$refId');

      // ─────────── 🏃 التعقيب ───────────
      case 'expediting_task_assigned':
      case 'expediting_item_revision_requested':
      case 'expediting_revision_requested':
      case 'expediting_task_approved':
        return const NotificationTarget('/expediter/tasks');

      case 'expediting_item_updated':
      case 'expediting_task_completed':
        return const NotificationTarget('/lawyer/dashboard');

      // ─────────── 🏠 العروض ───────────
      case 'offer':
      case 'offer_approved':
      case 'offer_rejected':
      // ACT-001 (2026-08-14): trg_offer_status_changed كانت تكتب الإشعار بلا
      // `act` إطلاقاً ⇒ صاحب العرض يستلم «تغيّرت حالة عرضك» ولا يفتحه بالضغط.
      case 'offer_status':
      // IMG-001 (2026-08-15): عرض أُعيد للمراجعة لأنه بلا صور — الوجهة
      // صفحة العرض نفسه ليضيف صاحبه صورة مباشرةً.
      case 'offer_needs_image':
        return refId.isEmpty
            ? const NotificationTarget('/user/my-offers')
            : NotificationTarget('/offer/$refId');

      // ─────────── 📅 المواعيد ───────────
      case 'appointment':
        return const NotificationTarget('/user/my-appointments');

      // ─────────── ✅ طلبات الإتمام ───────────
      // ACT-001 (2026-08-14): request_completion_by_appointment كانت تكتب
      // الإشعار بلا `act` ⇒ الموظف يرى «طلب إتمام معاملة» ولا يستطيع فتحه
      // فيبحث عنه يدوياً. الوجهة شاشة المراجعة لا الموعد، لأن الإجراء
      // المطلوب هو الاعتماد أو الرفض.
      case 'completion_request':
        return const NotificationTarget('/admin/completion-requests');

      // ─────────── 📝 الطلبات ───────────
      case 'request':
        return refId.isEmpty
            ? const NotificationTarget('/user/my-requests')
            : NotificationTarget('/user/request/$refId');

      // ─────────── 💰 المالية ───────────
      case 'payment':
      case 'payment_approved':
        return const NotificationTarget('/user/my-payments');

      // ─────────── ✅ التوثيق والحساب ───────────
      case 'verification':
      case 'verification_approved':
      case 'verification_rejected':
        return const NotificationTarget('/user/profile');

      case 'deal':
      case 'deal_completed':
        return const NotificationTarget('/user/my-offers');

      case 'rating':
        return const NotificationTarget('/user/my-ratings');
    }

    // ④ سقوط آمن على `tp` للإشعارات القديمة التي سبقت `act`
    switch (tp) {
      case 0:
        return refId.isEmpty
            ? const NotificationTarget.none()
            : NotificationTarget('/offer/$refId');
      case 2:
        return const NotificationTarget('/user/my-appointments');
      case 3:
        return const NotificationTarget('/user/my-payments');
      default:
        return const NotificationTarget.none();
    }
  }

  /// هل هذا الإشعار قابل للضغط؟ (لإخفاء السهم عن المعلوماتي)
  static bool isTappable({
    required String act,
    required String refId,
    int tp = -1,
    int role = UserRole.user,
  }) =>
      resolve(act: act, refId: refId, tp: tp, role: role).hasRoute;

  /// خريطة الـPush: `data.act` هو المصدر، ويُدعم `type` القديم للتوافق
  static NotificationTarget fromPushData(
    Map<String, dynamic> data, {
    int role = UserRole.user,
  }) {
    final act = (data['act'] ?? data['action'] ?? '').toString();
    final refId = (data['ref_id'] ?? data['id'] ?? '').toString();
    if (act.isNotEmpty) {
      return resolve(act: act, refId: refId, role: role);
    }
    // توافق عكسي مع الحقل القديم `type`
    final legacy = (data['type'] ?? '').toString();
    return resolve(act: legacy, refId: refId, role: role);
  }
}

/// وجهة الإشعار: مسار · أو لا شيء · أو ممنوع بالدور
class NotificationTarget {
  final String? route;
  final String? deniedReason;

  const NotificationTarget(this.route) : deniedReason = null;
  const NotificationTarget.none()
      : route = null,
        deniedReason = null;
  const NotificationTarget.denied(String reason)
      : route = null,
        deniedReason = reason;

  bool get hasRoute => route != null && route!.isNotEmpty;
  bool get isDenied => deniedReason != null;
}

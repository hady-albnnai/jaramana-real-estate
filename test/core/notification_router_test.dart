import 'package:flutter_test/flutter_test.dart';
import 'package:sweeda_real_estate/core/services/notification_router.dart';
import 'package:sweeda_real_estate/models/user_model.dart';

/// اختبارات الموجّه الموحّد للإشعارات.
///
/// **لماذا هذا الملف؟** الموجّه هو نقطة الالتقاء الوحيدة بين مساري الفتح
/// (درج الإشعارات داخل التطبيق، وضغط إشعار FCM من خارجه). أي فعل `act`
/// يكتبه السيرفر ولا يعرفه الموجّه يعني إشعاراً **يظهر ولا يستجيب للضغط**،
/// وهذا عطل صامت لا يكشفه أي اختبار خلفي.
///
/// القائمة أدناه مأخوذة من **قيم `act` الحيّة في قاعدة الإنتاج** (2026-08-14)
/// لا من الكود — فلو أضاف السيرفر فعلاً جديداً بلا تحديث الموجّه، يسقط
/// الاختبار المقابل هنا.
void main() {
  group('التغطية: كل قيمة act حيّة لها وجهة', () {
    // القيم الـ23 المسجّلة فعلياً في جدول notifications بالإنتاج،
    // عدا probe_notify_user (إشعار اختباري مقصود أنه معلوماتي).
    const liveActs = <String>[
      'appointment',
      'expediting_item_revision_requested',
      'expediting_item_updated',
      'expediting_revision_requested',
      'expediting_task_approved',
      'expediting_task_assigned',
      'expediting_task_completed',
      'offer',
      'offer_approved',
      'payment_approved',
      'photography_offer_published',
      'photography_photographer_assigned',
      'photography_reminder_1h',
      'photography_request_cancelled',
      'photography_request_new',
      'photography_request_result',
      'photography_task_assigned',
      'photography_task_created',
      'photography_task_started',
      'photography_task_submitted',
      'photography_task_submitted_client',
      'request',
      // ACT-001 (2026-08-14): كانتا تُكتبان بلا act إطلاقاً
      'completion_request',
      'offer_status',
    ];

    for (final act in liveActs) {
      test('«$act» له وجهة أو سبب رفض واضح', () {
        // نستخدم دور المدير: صلاحية شاملة، فأي رفض هنا يعني نقص تغطية
        final target = NotificationRouter.resolve(
          act: act,
          refId: 'test-ref-id',
          role: UserRole.manager,
        );
        expect(
          target.route,
          isNotNull,
          reason: 'الفعل «$act» موجود في الإنتاج لكن الموجّه لا يعرف وجهته '
              '⇒ الإشعار يظهر ولا يستجيب للضغط',
        );
        expect(target.route, startsWith('/'));
      });
    }
  });

  group('ACT-001: الحالتان المُضافتان', () {
    test('completion_request يوجّه لشاشة مراجعة طلبات الإتمام', () {
      final t = NotificationRouter.resolve(
        act: 'completion_request',
        refId: 'appt-1',
        role: UserRole.employee,
      );
      expect(t.route, '/admin/completion-requests');
    });

    test('completion_request محجوب عن المستخدم العادي', () {
      final t = NotificationRouter.resolve(
        act: 'completion_request',
        refId: 'appt-1',
        role: UserRole.user,
      );
      expect(t.route, isNull);
      expect(t.deniedReason, isNotNull);
    });

    test('offer_status يفتح تفاصيل العرض عند وجود ref', () {
      final t = NotificationRouter.resolve(
        act: 'offer_status',
        refId: 'offer-9',
        role: UserRole.user,
      );
      expect(t.route, '/offer/offer-9');
    });

    test('offer_status يسقط إلى «عروضي» بلا ref', () {
      final t = NotificationRouter.resolve(
        act: 'offer_status',
        refId: '',
        role: UserRole.user,
      );
      expect(t.route, '/user/my-offers');
    });
  });

  group('السلوك الافتراضي', () {
    test('act فارغ وrefId فارغ ⇒ لا وجهة (لا سهم كاذب)', () {
      final t = NotificationRouter.resolve(act: '', refId: '');
      expect(t.route, isNull);
      expect(t.deniedReason, isNull);
    });

    test('probe_notify_user معلوماتي بلا وجهة', () {
      final t = NotificationRouter.resolve(
        act: 'probe_notify_user',
        refId: 'x',
        role: UserRole.manager,
      );
      expect(t.route, isNull);
    });

    test('فعل مجهول لا يُسقط التطبيق', () {
      final t = NotificationRouter.resolve(
        act: 'totally_unknown_act_xyz',
        refId: 'x',
        role: UserRole.user,
      );
      expect(t, isA<NotificationTarget>());
    });
  });

  group('حارس الدور', () {
    test('مهمة تعقيب تخصّ المعقّب لا المصوّر', () {
      final expediter = NotificationRouter.resolve(
        act: 'expediting_task_assigned',
        refId: 't1',
        role: UserRole.expediter,
      );
      expect(expediter.route, isNotNull);

      final photographer = NotificationRouter.resolve(
        act: 'expediting_task_assigned',
        refId: 't1',
        role: UserRole.photographer,
      );
      expect(photographer.route, isNull);
      expect(photographer.deniedReason, isNotNull);
    });

    test('المدير يتجاوز حارس الدور (صلاحية شاملة)', () {
      final t = NotificationRouter.resolve(
        act: 'expediting_task_assigned',
        refId: 't1',
        role: UserRole.manager,
      );
      expect(t.route, isNotNull);
    });
  });

  group('fromPushData — مسار FCM', () {
    test('يقرأ act وref_id من حمولة الدفع', () {
      final t = NotificationRouter.fromPushData(
        {'act': 'offer_approved', 'ref_id': 'o-5'},
        role: UserRole.user,
      );
      expect(t.route, '/offer/o-5');
    });

    test('يقبل المفتاح البديل action/id', () {
      final t = NotificationRouter.fromPushData(
        {'action': 'request', 'id': 'r-7'},
        role: UserRole.user,
      );
      expect(t.route, '/user/request/r-7');
    });

    test('حمولة فارغة لا تُسقط التطبيق', () {
      final t = NotificationRouter.fromPushData({}, role: UserRole.user);
      expect(t, isA<NotificationTarget>());
    });
  });
}

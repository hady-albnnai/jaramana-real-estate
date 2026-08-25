import 'guide_models.dart';

/// Single source for all approved guide copy.
/// The guide layer may render these strings, but must not duplicate or alter them.
abstract final class GuideCopy {
  static String roleLabel(GuideScope scope) => switch (scope) {
        GuideScope.visitor => 'جولة الزائر',
        GuideScope.user => 'جولة المستخدم',
        GuideScope.broker => 'جولة الوسيط',
      };

  static String question(GuideScope scope) => switch (scope) {
        GuideScope.visitor => 'هل ترغب في جولة تعريفية سريعة؟',
        GuideScope.user => 'هل ترغب في التعرّف إلى أهم وظائف حسابك؟',
        GuideScope.broker => 'هل ترغب في التعرّف إلى مزايا حساب الوسيط؟',
      };

  static const yes = 'نعم، ابدأ';
  static const no = 'لا، شكراً';
  static const rejectionHint = 'يمكنك إعادة الجولة خلال ٣٠ دقيقة';
  static const next = 'التالي';
  static const back = 'رجوع';
  static const close = 'إغلاق';
  static const skip = 'تخطي الجولة';
  static const continueTour = 'متابعة الجولة';
  static const confirmSkip = 'هل تريد تخطي الجولة؟';
  static const finish = 'إنهاء الجولة';
  static const understood = 'فهمت';
  static const retry = 'إعادة المحاولة';

  static const visitorOffersTitle = 'تصفّح العروض';
  static const visitorOffersBody =
      'من هنا يمكنك تصفّح العروض المنشورة والمتاحة حالياً، ومنها العروض المثبّتة والمميّزة والعروض العادية. اسحب الشاشة إلى الأعلى لمشاهدة المزيد.';
  static const visitorOffersAction = 'ابدأ التصفح';
  static const visitorFiltersTitle = 'ابحث بدقة أكبر';
  static const visitorFiltersBody =
      'استخدم «فلاتر» لتضييق نطاق البحث وتحديد نوع العرض وموقعه وسعره ومواصفاته.';
  static const visitorShareTitle = 'شارك العرض';
  static const visitorShareBody =
      'يمكنك مشاركة أي عرض مع الآخرين مباشرةً، حتى من دون إنشاء حساب. اضغط على أيقونة المشاركة لإرسال معلومات العرض.';

  static const userOffersTitle = 'إدارة العروض الخاصة بك';
  static const userOffersBody =
      'هنا تظهر العروض الخاصة بك، وتتابع حالاتها من «قيد المراجعة» إلى «منشور» أو غير ذلك. ومن زر «عرض جديد» تبدأ بإضافة عقار أو سيارة.';
  static const userRequestsTitle = 'طلباتك العقارية';
  static const userRequestsBody =
      'من «طلباتي» تنشئ طلب شراء أو استئجار، ثم تتمتّع بالمطابقة الآلية التي تساعدك على الوصول إلى العروض الأقرب إلى طلبك.';
  static const userAppointmentsTitle = 'متابعة المواعيد';
  static const userAppointmentsBody =
      'من «مواعيدي» تتابع المواعيد التي حجزتها، والطلبات الواردة على العروض الخاصة بك، والردود والأوقات البديلة.';
  static const userNewOfferTitle = 'عرض جديد';
  static const userNewOfferBody =
      'من «عرض جديد» تبدأ بإضافة عقار أو سيارة، ثم تعبّئ البيانات والصور ومواعيد المعاينة، وترسل العرض الخاص بك إلى مراجعة الإدارة.';

  static const brokerBenefitsTitle = 'مزايا الوسيط';
  static const brokerBenefitsBody =
      'بصفتك وسيطاً معتمداً، يمكنك إدراج حتى خمسة عروض وخمسة طلبات، وتتابع عروضك ومواعيد المعاينة وصفقاتك من لوحة واحدة. كما أن عروضك معفاة من عمولة المكتب.';

  static String titleFor(String stepId) => switch (stepId) {
        GuideStepIds.visitorOffers => visitorOffersTitle,
        GuideStepIds.visitorFilters => visitorFiltersTitle,
        GuideStepIds.visitorShare => visitorShareTitle,
        GuideStepIds.userOffers => userOffersTitle,
        GuideStepIds.userRequests => userRequestsTitle,
        GuideStepIds.userAppointments => userAppointmentsTitle,
        GuideStepIds.userNewOffer => userNewOfferTitle,
        GuideStepIds.brokerBenefits => brokerBenefitsTitle,
        _ => '',
      };

  static String bodyFor(String stepId) => switch (stepId) {
        GuideStepIds.visitorOffers => visitorOffersBody,
        GuideStepIds.visitorFilters => visitorFiltersBody,
        GuideStepIds.visitorShare => visitorShareBody,
        GuideStepIds.userOffers => userOffersBody,
        GuideStepIds.userRequests => userRequestsBody,
        GuideStepIds.userAppointments => userAppointmentsBody,
        GuideStepIds.userNewOffer => userNewOfferBody,
        GuideStepIds.brokerBenefits => brokerBenefitsBody,
        _ => '',
      };
}

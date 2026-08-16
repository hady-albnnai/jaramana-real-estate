import '../../models/user_model.dart';

class PermissionKeys {
  static const adminDashboard = 'admin_dashboard';
  static const manageStaff = 'manage_staff';
  static const officeOperations = 'office_operations';
  static const manageUsers = 'manage_users';
  static const managePermissions = 'manage_permissions';
  static const reviewOffers   = 'review_offers';
  static const addOfferAdmin  = 'add_offer_admin';
  static const manageRequests = 'manage_requests';
  static const reviewVerifications = 'review_verifications';
  static const mediaReview = 'media_review';
  static const photographyManagement = 'photography_management';
  static const photographerTasks = 'photographer_tasks';
  static const fraudSuspects = 'fraud_suspects';
  static const manageAppointments = 'manage_appointments';
  static const manageDeals = 'manage_deals';
  static const managePayments = 'manage_payments';
  static const manageReports = 'manage_reports';
  static const manageConfig = 'manage_config';
  static const viewAnalytics = 'view_analytics';
  static const resourceUsage = 'resource_usage';
  static const completionRequests = 'completion_requests';
  static const brokerDashboard = 'broker_dashboard';
  static const brokerOffers = 'broker_offers';
  static const brokerAppointments = 'broker_appointments';
  static const brokerDeals = 'broker_deals';
  static const brokerStats = 'broker_stats';
  static const userHome = 'user_home';
  static const userOffers = 'user_offers';
  static const userRequests = 'user_requests';
  static const userAppointments = 'user_appointments';
  static const userPhotography = 'user_photography';
  static const userProfile = 'user_profile';
}

class AppPermission {
  final String key;
  final String title;
  final String group;
  final int minimumRoleForDefault;

  const AppPermission({
    required this.key,
    required this.title,
    required this.group,
    required this.minimumRoleForDefault,
  });
}

class PermissionService {
  /// الصلاحيات المتاحة بالنظام.
  /// minimumRoleForDefault: أقل role يحصل على هذه الصلاحية تلقائياً.
  /// 99 = لا يحصل عليها أي role تلقائياً (تُمنح يدوياً فقط).
  ///
  /// الأدوار:
  /// 0=مستخدم، 1=وسيط، 2=مصور، 3=مشرف، 4=موظف مكتب، 5=نائب مدير، 6=مدير
  static const permissions = <AppPermission>[
    // — الإدارة —
    AppPermission(key: PermissionKeys.adminDashboard, title: 'مدخل الإدارة', group: 'الإدارة', minimumRoleForDefault: UserRole.deputy),
    AppPermission(key: PermissionKeys.manageStaff, title: 'إدارة الموظفين', group: 'الإدارة', minimumRoleForDefault: UserRole.deputy),
    AppPermission(key: PermissionKeys.officeOperations, title: 'عمليات المكتب', group: 'الإدارة', minimumRoleForDefault: UserRole.employee),
    AppPermission(key: PermissionKeys.manageUsers, title: 'إدارة المستخدمين', group: 'الإدارة', minimumRoleForDefault: UserRole.employee),
    AppPermission(key: PermissionKeys.managePermissions, title: 'إدارة الصلاحيات', group: 'الإدارة', minimumRoleForDefault: UserRole.deputy),
    AppPermission(key: PermissionKeys.reviewOffers, title: 'مراجعة العروض', group: 'الإدارة', minimumRoleForDefault: UserRole.employee),
    AppPermission(key: PermissionKeys.addOfferAdmin, title: 'إضافة عرض (إدارة)', group: 'الإدارة', minimumRoleForDefault: UserRole.employee),
    AppPermission(key: PermissionKeys.manageRequests, title: 'إدارة الطلبات', group: 'الإدارة', minimumRoleForDefault: UserRole.employee),
    AppPermission(key: PermissionKeys.reviewVerifications, title: 'طلبات التوثيق', group: 'الإدارة', minimumRoleForDefault: UserRole.employee),
    AppPermission(key: PermissionKeys.mediaReview, title: 'إدارة الوسائط والتصوير', group: 'الإدارة', minimumRoleForDefault: UserRole.employee),
    AppPermission(key: PermissionKeys.fraudSuspects, title: 'كشف الاحتيال', group: 'الإدارة', minimumRoleForDefault: UserRole.employee),
    AppPermission(key: PermissionKeys.viewAnalytics, title: 'التحليلات', group: 'المالية', minimumRoleForDefault: UserRole.deputy),
    AppPermission(key: PermissionKeys.resourceUsage, title: 'استهلاك السيرفر والتخزين', group: 'الرقابة التقنية', minimumRoleForDefault: UserRole.employee),
    AppPermission(key: PermissionKeys.completionRequests, title: 'طلبات إتمام المعاملات', group: 'التشغيل', minimumRoleForDefault: UserRole.employee),

    // — التصوير —
    AppPermission(key: PermissionKeys.photographyManagement, title: 'إدارة مهام التصوير', group: 'التصوير', minimumRoleForDefault: UserRole.employee),
    AppPermission(key: PermissionKeys.photographerTasks, title: 'مهام المصور', group: 'التصوير', minimumRoleForDefault: UserRole.photographer),

    // — التشغيل —
    AppPermission(key: PermissionKeys.manageAppointments, title: 'إدارة المواعيد', group: 'التشغيل', minimumRoleForDefault: UserRole.employee),
    AppPermission(key: PermissionKeys.manageDeals, title: 'إدارة الصفقات', group: 'المالية', minimumRoleForDefault: UserRole.deputy),
    AppPermission(key: PermissionKeys.managePayments, title: 'إدارة المدفوعات', group: 'المالية', minimumRoleForDefault: UserRole.deputy),
    AppPermission(key: PermissionKeys.manageReports,   title: 'التبليغات',       group: 'التشغيل', minimumRoleForDefault: UserRole.employee),

    // — الإعدادات —
    // مدير + نائب المدير يستطيعون تعديل إعدادات طلبات الفيديو (احتياطي ضد الحظر)
    AppPermission(key: PermissionKeys.manageConfig, title: 'إعدادات التطبيق', group: 'الإعدادات', minimumRoleForDefault: UserRole.deputy),

    // — الوسيط — (brk==1 فقط، ليس بالـ role number)
    // ملاحظة: هذه الصلاحيات تُمنح تلقائياً لـ role=1 فقط
    // الأدوار الأعلى (مصور/مشرف/موظف...) لا يرثونها تلقائياً
    // إلا إذا كان brk==1 (وسيط مفعّل)
    AppPermission(key: PermissionKeys.brokerDashboard, title: 'لوحة الوسيط', group: 'الوسيط', minimumRoleForDefault: 99),
    AppPermission(key: PermissionKeys.brokerOffers, title: 'عروض الوسيط', group: 'الوسيط', minimumRoleForDefault: 99),
    AppPermission(key: PermissionKeys.brokerAppointments, title: 'مواعيد الوسيط', group: 'الوسيط', minimumRoleForDefault: 99),
    AppPermission(key: PermissionKeys.brokerDeals, title: 'صفقات الوسيط', group: 'الوسيط', minimumRoleForDefault: 99),
    AppPermission(key: PermissionKeys.brokerStats, title: 'إحصائيات الوسيط', group: 'الوسيط', minimumRoleForDefault: 99),

    // — المستخدم —
    AppPermission(key: PermissionKeys.userHome, title: 'واجهة المستخدم', group: 'المستخدم', minimumRoleForDefault: UserRole.user),
    AppPermission(key: PermissionKeys.userOffers, title: 'عروضي', group: 'المستخدم', minimumRoleForDefault: UserRole.user),
    AppPermission(key: PermissionKeys.userRequests, title: 'طلباتي', group: 'المستخدم', minimumRoleForDefault: UserRole.user),
    AppPermission(key: PermissionKeys.userAppointments, title: 'مواعيدي', group: 'المستخدم', minimumRoleForDefault: UserRole.user),
    AppPermission(key: PermissionKeys.userPhotography, title: 'خدمة التصوير', group: 'المستخدم', minimumRoleForDefault: UserRole.user),
    AppPermission(key: PermissionKeys.userProfile, title: 'الملف الشخصي', group: 'المستخدم', minimumRoleForDefault: UserRole.user),
  ];

  /// 🔒 قيمة حارسة تعني «لا صلاحيات إطلاقاً».
  ///
  /// **المشكلة التي تحلّها (2026-08-14):** كان `effectivePermissions` يقرأ
  /// `if (user.perm.isNotEmpty) return user.perm;` — أي أن القائمة الفارغة
  /// تعني «استخدم الافتراضي». النتيجة: **كان يستحيل تجريد موظف من كل
  /// صلاحياته** — المدير يمسح كل الصلاحيات ظنّاً أنه جرّده، فيعيده النظام
  /// إلى الافتراضي الكامل لدوره. عكس المقصود تماماً وبصمت.
  ///
  /// الآن: `perm = ['none']` تعني الصفر الصريح، و`perm = []` تبقى تعني
  /// «الافتراضي» حفاظاً على التوافق مع كل الحسابات الحالية.
  static const String noneSentinel = 'none';

  /// 🔒 أعلى دور يُعدّ **رتبة إدارية**. ما فوقه تخصّصات جانبية.
  ///
  /// VULN-001: الدوران 7 (محامٍ) و8 (معقّب) أُضيفا فوق المدير رقمياً بينما
  /// هما تخصّصان لا رتبتان أعلى. الشرط `role >= minimumRoleForDefault` كان
  /// يمنحهما **كل صلاحيات المدير** تلقائياً لأن أعلى قيمة في الجدول هي 6.
  /// أُكِّد حياً: محامٍ عدّل إعدادات التطبيق، ومعقّب قرأ كل المدفوعات.
  static const int maxAdministrativeRole = UserRole.manager;

  /// هل هذا الدور تخصّص جانبي (محامٍ/معقّب) لا رتبة إدارية؟
  static bool isSideSpecialty(int role) => role > maxAdministrativeRole;

  static List<String> defaultsForRole(int role) {
    // 🔒 VULN-001: التخصّصات الجانبية لا ترث أي صلاحية إدارية افتراضية.
    // شاشاتها محروسة بالراوتر عبر isLawyer/isExpediter، لا عبر هذا الجدول.
    if (isSideSpecialty(role)) {
      // المحامي والمعقّب لا يرثان الإدارة، لكنهما يحتاجان صفحات حسابهما
      // وإشعاراتهما المشتركة تحت /user/*.
      return const [PermissionKeys.userProfile];
    }

    return permissions
        .where((permission) => role >= permission.minimumRoleForDefault)
        .map((permission) => permission.key)
        .toList(growable: false);
  }

  static List<String> effectivePermissions(UserModel? user) {
    if (user == null) return const [];

    // 🔒 الصفر الصريح — تجريد كامل مقصود من الإدارة.
    if (user.perm.contains(noneSentinel)) return const [];

    if (user.perm.isNotEmpty) {
      // 🔒 VULN-001: حتى التخصيص اليدوي لا يمنح رتبة إدارية لدور جانبي،
      // وإلا صار بالإمكان الالتفاف على السقف بمنح perm يدوياً لمحامٍ.
      if (isSideSpecialty(user.role)) return const [];
      return user.perm;
    }

    final perms = defaultsForRole(user.role);

    // الوسيط (brk==1) يحصل على صلاحيات الوسيط بغض النظر عن الـ role
    if (user.isBroker) {
      return [
        ...perms,
        PermissionKeys.brokerDashboard,
        PermissionKeys.brokerOffers,
        PermissionKeys.brokerAppointments,
        PermissionKeys.brokerDeals,
        PermissionKeys.brokerStats,
      ];
    }

    return perms;
  }

  static bool has(UserModel? user, String permission) {
    return effectivePermissions(user).contains(permission);
  }

  static Map<String, List<AppPermission>> grouped() {
    final map = <String, List<AppPermission>>{};
    for (final permission in permissions) {
      map.putIfAbsent(permission.group, () => <AppPermission>[]).add(permission);
    }
    return map;
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sweeda_real_estate/core/services/permission_service.dart';
import 'package:sweeda_real_estate/models/user_model.dart';

/// اختبارات RBAC لوحدة الإدارة — تثبيت ثوابت الدستور docs/LOGIC_SPEC.md §5.5.
///
/// العقد:
/// - مراجعة العروض والتوثيق للرتبة 4 فما فوق (موظف مكتب+).
/// - إدارة المدفوعات للرتبة 5 فما فوق (نائب المدير+).
/// - إدارة الموظفين والصلاحيات والإعدادات للرتبة 5 فما فوق.
/// - المشرف (3) محظور من كل قرارات الإدارة الحساسة (least-privilege / fail-closed).

UserModel userWithRole(int role, {int brk = 0, List<String>? perm}) {
  return UserModel(
    uid: '00000000-0000-0000-0000-0000000000$role',
    nm: 'test-$role',
    ph: '+96390000000$role',
    role: role,
    brk: brk,
    perm: perm,
    tsCrt: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  group('Admin RBAC (LOGIC_SPEC §5.5)', () {
    test('offer review requires role >= employee (4)', () {
      expect(PermissionService.has(userWithRole(UserRole.supervisor), PermissionKeys.reviewOffers), isFalse);
      expect(PermissionService.has(userWithRole(UserRole.employee), PermissionKeys.reviewOffers), isTrue);
      expect(PermissionService.has(userWithRole(UserRole.deputy), PermissionKeys.reviewOffers), isTrue);
      expect(PermissionService.has(userWithRole(UserRole.manager), PermissionKeys.reviewOffers), isTrue);
    });

    test('verification review requires role >= employee (4)', () {
      expect(PermissionService.has(userWithRole(UserRole.supervisor), PermissionKeys.reviewVerifications), isFalse);
      expect(PermissionService.has(userWithRole(UserRole.employee), PermissionKeys.reviewVerifications), isTrue);
    });

    test('admin add-offer requires role >= employee (4)', () {
      expect(PermissionService.has(userWithRole(UserRole.supervisor), PermissionKeys.addOfferAdmin), isFalse);
      expect(PermissionService.has(userWithRole(UserRole.employee), PermissionKeys.addOfferAdmin), isTrue);
    });

    test('payment management requires role >= deputy (5)', () {
      expect(PermissionService.has(userWithRole(UserRole.employee), PermissionKeys.managePayments), isFalse);
      expect(PermissionService.has(userWithRole(UserRole.deputy), PermissionKeys.managePayments), isTrue);
      expect(PermissionService.has(userWithRole(UserRole.manager), PermissionKeys.managePayments), isTrue);
    });

    test('deals and analytics require role >= deputy (5)', () {
      expect(PermissionService.has(userWithRole(UserRole.employee), PermissionKeys.manageDeals), isFalse);
      expect(PermissionService.has(userWithRole(UserRole.employee), PermissionKeys.viewAnalytics), isFalse);
      expect(PermissionService.has(userWithRole(UserRole.deputy), PermissionKeys.manageDeals), isTrue);
      expect(PermissionService.has(userWithRole(UserRole.deputy), PermissionKeys.viewAnalytics), isTrue);
    });

    test('staff and permissions management require role >= deputy (5)', () {
      expect(PermissionService.has(userWithRole(UserRole.employee), PermissionKeys.manageStaff), isFalse);
      expect(PermissionService.has(userWithRole(UserRole.employee), PermissionKeys.managePermissions), isFalse);
      expect(PermissionService.has(userWithRole(UserRole.deputy), PermissionKeys.manageStaff), isTrue);
      expect(PermissionService.has(userWithRole(UserRole.deputy), PermissionKeys.managePermissions), isTrue);
    });

    test('app config requires deputy (5) or manager (6) — LOGIC_SPEC §7.2', () {
      expect(PermissionService.has(userWithRole(UserRole.employee), PermissionKeys.manageConfig), isFalse);
      expect(PermissionService.has(userWithRole(UserRole.deputy), PermissionKeys.manageConfig), isTrue);
      expect(PermissionService.has(userWithRole(UserRole.manager), PermissionKeys.manageConfig), isTrue);
    });

    test('supervisor (3) is blocked from all sensitive admin decisions', () {
      final supervisor = userWithRole(UserRole.supervisor);
      const sensitive = [
        PermissionKeys.reviewOffers,
        PermissionKeys.reviewVerifications,
        PermissionKeys.addOfferAdmin,
        PermissionKeys.manageRequests,
        PermissionKeys.manageUsers,
        PermissionKeys.managePayments,
        PermissionKeys.manageDeals,
        PermissionKeys.manageConfig,
        PermissionKeys.manageStaff,
        PermissionKeys.managePermissions,
      ];
      for (final key in sensitive) {
        expect(PermissionService.has(supervisor, key), isFalse, reason: 'supervisor must not hold $key');
      }
    });

    test('explicit perms override role defaults', () {
      final custom = userWithRole(UserRole.user, perm: [PermissionKeys.reviewOffers]);
      expect(PermissionService.has(custom, PermissionKeys.reviewOffers), isTrue);
      expect(PermissionService.has(custom, PermissionKeys.managePayments), isFalse);
    });
  });
}

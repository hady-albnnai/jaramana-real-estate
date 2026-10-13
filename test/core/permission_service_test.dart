import 'package:flutter_test/flutter_test.dart';
import 'package:jaramana_real_estate/core/services/permission_service.dart';
import 'package:jaramana_real_estate/models/user_model.dart';

UserModel userWithRole(int role, {List<String>? perm, int brk = 0}) {
  return UserModel(
    uid: '00000000-0000-0000-0000-00000000000$role',
    nm: 'test',
    ph: '+96390000000$role',
    role: role,
    brk: brk,
    perm: perm,
    tsCrt: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  group('PermissionService', () {
    test('manager has staff/config permissions by default', () {
      final user = userWithRole(UserRole.manager);

      expect(PermissionService.has(user, PermissionKeys.manageStaff), isTrue);
      expect(PermissionService.has(user, PermissionKeys.manageConfig), isTrue);
    });

    test('employee has operational permissions but not staff management', () {
      final user = userWithRole(UserRole.employee);

      expect(PermissionService.has(user, PermissionKeys.reviewOffers), isTrue);
      expect(PermissionService.has(user, PermissionKeys.manageAppointments), isTrue);
      expect(PermissionService.has(user, PermissionKeys.manageStaff), isFalse);
    });

    test('photographer has photographer tasks permission', () {
      final user = userWithRole(UserRole.photographer);

      expect(PermissionService.has(user, PermissionKeys.photographerTasks), isTrue);
      expect(PermissionService.has(user, PermissionKeys.manageStaff), isFalse);
    });

    test('broker flag grants broker permissions without changing role permissions', () {
      final user = userWithRole(UserRole.user, brk: 1);

      expect(PermissionService.has(user, PermissionKeys.brokerDashboard), isTrue);
      expect(PermissionService.has(user, PermissionKeys.userHome), isTrue);
    });
  });
}

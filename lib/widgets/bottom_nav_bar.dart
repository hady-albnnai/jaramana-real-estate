import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../core/theme/app_theme.dart';
import 'e2e.dart';

/// شريط التنقل السفلي الرئيسي للتطبيق
/// للمستخدمين العاديين والوسطاء: الرئيسية، عروضي، طلباتي، مواعيدي، تصوير، حسابي
/// (المفضلة انتقلت لأيقونة قلب في أعلى الشاشة الرئيسية)
/// للإدارة والموظفين: مهامي، حسابي فقط
class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  const CustomBottomNavBar({super.key, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isInternal = auth.userModel?.isInternal ?? false;

    // 🧭 الزائر (غير مسجّل): شريط عام بالكامل — كل وجهاته مفتوحة فلا ارتداد ولا «علِق» (إصلاح 2026-07-26)
    if (!auth.isLoggedIn) {
      final loc = GoRouterState.of(context).uri.path;
      var gi = 3; // حسابي
      if (loc == '/home') {
        gi = 0;
      } else if (loc == '/search') {
        gi = 1;
      } else if (loc == '/user/favorites') {
        gi = 2;
      }
      return BottomNavigationBar(
        currentIndex: gi,
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppTheme.scaffoldBackground,
        selectedItemColor: AppTheme.primaryGold,
        unselectedItemColor: AppTheme.textGrey,
        selectedFontSize: 12,
        unselectedFontSize: 11,
        onTap: (index) {
          switch (index) {
            case 0: context.go('/home'); break;
            case 1: context.go('/search'); break;
            case 2: context.go('/user/favorites'); break;
            default: context.go('/user/profile');
          }
        },
        items: [
          BottomNavigationBarItem(icon: E2E(id: 'e2e_nav_home', button: true, child: Icon(Icons.home_outlined)), activeIcon: Icon(Icons.home), label: 'الرئيسية'),
          BottomNavigationBarItem(icon: E2E(id: 'e2e_nav_search', button: true, child: Icon(Icons.search)), activeIcon: Icon(Icons.search), label: 'بحث'),
          BottomNavigationBarItem(icon: E2E(id: 'e2e_nav_favorites', button: true, child: Icon(Icons.favorite_border)), activeIcon: Icon(Icons.favorite), label: 'المفضلة'),
          BottomNavigationBarItem(icon: E2E(id: 'e2e_nav_profile', button: true, child: Icon(Icons.person_outline)), activeIcon: Icon(Icons.person), label: 'حسابي'),
        ],
      );
    }

    // الإدارة والموظفين: شريط مختصر (مهامي + حسابي)
    if (isInternal) {
      return BottomNavigationBar(
        currentIndex: currentIndex > 0 ? 1 : 0,
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppTheme.scaffoldBackground,
        selectedItemColor: AppTheme.primaryGold,
        unselectedItemColor: AppTheme.textGrey,
        selectedFontSize: 12,
        unselectedFontSize: 11,
        onTap: (index) {
          if (index == 0) {
            // مهامي — حسب الدور
            if (auth.isLawyer) {
              context.go('/lawyer/dashboard');
            } else if (auth.isExpediter) {
              context.go('/expediter/tasks');
            } else if (auth.isSenior) {
              context.go('/admin/dashboard');
            } else if (auth.isPhotographer) {
              context.go('/photographer/tasks');
            } else if (auth.isSupervisor) {
              context.go('/executor/tasks');
            } else {
              context.go('/employee/home');
            }
          } else {
            context.go('/user/profile');
          }
        },
        items: [
          BottomNavigationBarItem(
            icon: E2E(id: 'e2e_nav_home', button: true, child: Icon(Icons.task_alt_outlined)),
            activeIcon: Icon(Icons.task_alt),
            label: 'مهامي',
          ),
          BottomNavigationBarItem(
            icon: E2E(id: 'e2e_nav_profile', button: true, child: Icon(Icons.person_outline)),
            activeIcon: Icon(Icons.person),
            label: 'حسابي',
          ),
        ],
      );
    }

    // المستخدمون العاديون والوسطاء: شريط كامل (6 تبويبات)
    return BottomNavigationBar(
      currentIndex: currentIndex,
      type: BottomNavigationBarType.fixed,
      backgroundColor: AppTheme.scaffoldBackground,
      selectedItemColor: AppTheme.primaryGold,
      unselectedItemColor: AppTheme.textGrey,
      selectedFontSize: 11,
      unselectedFontSize: 10,
      onTap: (index) {
        switch (index) {
          case 0:
            if (auth.isBroker) {
              context.go('/broker/dashboard');
            } else {
              context.go('/user/home');
            }
            break;
          case 1:
            context.go(auth.isBroker ? '/broker/offers' : '/user/my-offers');
            break;
          case 2:
            context.go(auth.isBroker ? '/broker/appointments' : '/user/my-requests');
            break;
          case 3:
            context.go(auth.isBroker ? '/broker/deals' : '/user/my-appointments');
            break;
          case 4: context.go('/user/photography'); break;
          case 5: context.go('/user/profile'); break;
        }
      },
      items: [
        const BottomNavigationBarItem(icon: E2E(id: 'e2e_nav_home', button: true, child: Icon(Icons.home_outlined)), activeIcon: Icon(Icons.home), label: 'الرئيسية'),
        const BottomNavigationBarItem(icon: E2E(id: 'e2e_nav_offers', button: true, child: Icon(Icons.home_work_outlined)), activeIcon: Icon(Icons.home_work), label: 'عروضي'),
        BottomNavigationBarItem(icon: const E2E(id: 'e2e_nav_requests', button: true, child: Icon(Icons.assignment_outlined)), activeIcon: const Icon(Icons.assignment), label: auth.isBroker ? 'طلبات المعاينة' : 'طلباتي'),
        BottomNavigationBarItem(icon: const E2E(id: 'e2e_nav_appointments', button: true, child: Icon(Icons.calendar_today_outlined)), activeIcon: const Icon(Icons.calendar_today), label: auth.isBroker ? 'الصفقات' : 'مواعيدي'),
        const BottomNavigationBarItem(icon: E2E(id: 'e2e_nav_photography', button: true, child: Icon(Icons.photo_camera_outlined)), activeIcon: Icon(Icons.photo_camera), label: 'تصوير'),
        const BottomNavigationBarItem(icon: E2E(id: 'e2e_nav_profile', button: true, child: Icon(Icons.person_outline)), activeIcon: Icon(Icons.person), label: 'حسابي'),
      ],
    );
  }
}

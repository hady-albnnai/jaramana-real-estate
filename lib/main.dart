import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app.dart';
import 'core/services/app_info_service.dart';
import 'core/services/local_cache_service.dart';
import 'services/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تهيئة بيانات التواريخ بالعربية (لـ DateFormat)
  await initializeDateFormatting('ar', null);

  // تهيئة التخزين المحلي (Hive) — للكاش ودعم العمل دون اتصال
  await LocalCacheService.initialize();

  // 📦 قراءة الإصدار الحقيقي من الـAPK (لا نص ثابت ولا قيمة من الإدارة).
  // الفشل هنا غير قاتل — الواجهة تُخفي بند الإصدار بدل عرض رقم مخترَع (§13).
  try {
    await AppInfoService.init();
  } catch (_) {
    // الإصدار غير متاح ⇒ AppInfoService.isReady == false ⇒ البند يُخفى.
  }

  // تهيئة Firebase (للـ FCM Push Notifications)
  try {
    await FCMService.initializeFirebase();
    // تسجيل معالج الإشعارات بالخلفية
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
  } catch (e) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }

  runApp(const MyApp());
}

# اختبارات واجهة التطبيق الواقعية (Maestro)

هذه الاختبارات تفتح التطبيق على جهاز Android/محاكي وتتفاعل معه كأن المستخدم يضغط يدوياً.

## لماذا أضفنا E2E IDs؟

النصوص العربية قد تظهر مشوهة في PowerShell/Maestro على Windows. لذلك أضفنا علامات Semantics ثابتة بالإنكليزية داخل التطبيق في وضع debug فقط، مثل:

- `e2e_nav_profile`
- `e2e_login_username`
- `e2e_login_password`
- `e2e_login_button`
- `e2e_screen_admin_dashboard`
- `e2e_screen_lawyer_dashboard`
- `e2e_screen_expediter_tasks`

## 1) المتطلبات

- التطبيق مثبت أو قابل للتشغيل على جهاز Android.
- تفعيل USB debugging إذا كان الاختبار على موبايل حقيقي.
- تثبيت Maestro CLI.
- تأكد أن الجهاز ظاهر:

```bash
adb devices
```

## 2) تشغيل اختبار فتح التطبيق فقط

```bash
maestro test maestro/flows/00_smoke_launch.yaml
```

هذا الاختبار يبدأ التطبيق كزائر ويتأكد من ظهور `e2e_nav_profile`.

## 3) تشغيل اختبار تسجيل الدخول

استبدل القيم ببيانات حساب اختبار:

```bash
maestro test maestro/flows/01_login_password.yaml \
  -e E2E_USERNAME="hady" \
  -e E2E_PASSWORD="PUT_PASSWORD" \
  -e E2E_EXPECT_ID="e2e_screen_admin_dashboard"
```

أمثلة `E2E_EXPECT_ID`:

| الدور | القيمة المتوقعة |
|---|---|
| مدير/نائب | `e2e_screen_admin_dashboard` |
| محامي | `e2e_screen_lawyer_dashboard` |
| معقب | `e2e_screen_expediter_tasks` |

## 4) اختبار إرسال مهمة من محامي إلى معقب

يفترض وجود حساب محامي وحساب معقب جاهزين، وأن المعقب يظهر باسمه/رقمه في قائمة الاختيار.
يفضل تمرير رقم هاتف المعقب ضمن `EXPEDITER_LABEL` لأنه أرقام ولا يتأثر بترميز العربية.

```bash
maestro test maestro/flows/02_lawyer_create_expediting_task.yaml \
  -e LAWYER_USERNAME="lawyer_test_01" \
  -e LAWYER_PASSWORD="PUT_PASSWORD" \
  -e EXPEDITER_LABEL="9639xxxxxxx" \
  -e TASK_NUMBER="12345" \
  -e TASK_ZONE="جرمانا"
```

## 5) اختبار دخول المعقب ورؤية المهمة

```bash
maestro test maestro/flows/03_expediter_open_task.yaml \
  -e EXPEDITER_USERNAME="expediter_test_01" \
  -e EXPEDITER_PASSWORD="PUT_PASSWORD" \
  -e TASK_NUMBER="12345"
```

## ملاحظات مهمة

- هذه الاختبارات لا تضع كلمات مرور داخل المستودع. مرّرها دائماً عبر `-e`.
- إذا تغير flow أو UI، نضيف E2E ID جديد بدلاً من الاعتماد على OCR العربي.
- رفع الصور من المعرض يحتاج flow منفصل حسب جهاز الاختبار ومعرض الصور، لذلك نبدأ أولاً بتسجيل الدخول والتنقل وإرسال المهمة.
- الهدف من هذه المرحلة تقليل الضغط اليدوي تدريجياً، وليس استبدال كل الاختبارات من أول يوم.

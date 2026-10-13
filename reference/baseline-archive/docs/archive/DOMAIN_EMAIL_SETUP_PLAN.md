# خطة شراء الدومين وربطه مع Resend وSupabase

**المشروع:** المكتب العقاري الإلكتروني  
**الدومين المقترح:** `erealtyoffice.com`  
**آخر تحديث:** 2026-06-17  
**الغرض:** مرجع تنفيذي تفصيلي عند شراء الدومين وربطه بالإيميل والموقع لاحقاً، مع مراعاة أن صاحب المشروع داخل سوريا والدفع سيتم من أصدقاء خارج سوريا.

---

## 1. القرار الموصى به

### الخيار الموصى به حالياً

```text
شراء الدومين من Namecheap
إدارة DNS مبدئياً من Namecheap
ربط Resend لإرسال إيميلات التطبيق
استخدام نفس الدومين لاحقاً للموقع الرسمي
```

### لماذا هذا هو الخيار الأفضل لحالتنا؟

لأن الحالة العملية للمشروع هي:

- صاحب المشروع داخل سوريا.
- الدفع سيتم من أصدقاء في نيجيريا أو خارج سوريا.
- المطلوب تقليل تدخل الأصدقاء إلى الحد الأدنى.
- نحتاج دومين لإخراج Resend من وضع الاختبار.
- نحتاج لاحقاً نفس الدومين للموقع الرسمي والتطبيق الويب.
- نحتاج طريقة تسمح لصاحب المشروع بإدارة DNS بدون مشاركة كلمة سر حساب الدومين.

لذلك Namecheap مناسب لأنه يدعم ميزة **Share Access**، وهي تسمح لصاحب الدومين بإعطاء شخص آخر صلاحيات محددة لإدارة الدومين، مثل Advanced DNS، بدون تسليم كلمة مرور الحساب.

---

## 2. لماذا لا نبدأ بـ Cloudflare Registrar مباشرة؟

Cloudflare Registrar ممتاز تقنياً وسعره غالباً قريب من التكلفة الفعلية، لكنه ليس الخيار الأسهل لهذه الحالة لأن:

- صديقك سيشتري ويدفع، وأنت تريد أقل تدخل منه.
- إعدادات الحساب والدفع في Cloudflare قد تكون أقل مرونة من Namecheap لبعض المستخدمين.
- Namecheap أسهل كخطوة أولى، وميزة Share Access واضحة ومباشرة.

لاحقاً يمكن نقل DNS إلى Cloudflare إذا احتجنا حماية أو أداء أو إدارة DNS أكثر تقدماً، بدون تغيير الدومين نفسه.

---

## 3. لماذا لا نستخدم GoDaddy؟

GoDaddy معروف، لكنه ليس الخيار الأول هنا بسبب:

- كثرة الخدمات الإضافية أثناء الشراء.
- احتمال ارتفاع أسعار التجديد مقارنة بالبدائل.
- واجهة وإدارة DNS قد تكون مزعجة أكثر.
- مناسب فقط إذا فشلت كل البدائل الأخرى.

---

## 4. لماذا لا نستخدم Porkbun؟

Porkbun جيد جداً من ناحية السعر، لكنه ليس الخيار الأول لهذه الحالة لأن:

- مشاركة صلاحيات DNS معك ليست بنفس وضوح وانتشار Namecheap.
- قد تضطر أن تطلب من صديقك تعديل DNS بنفسه أو مشاركة الحساب.
- هدفنا هنا تقليل تدخل الأصدقاء بعد الدفع.

---

## 5. الدومين المقترح

### الخيار الأساسي

```text
erealtyoffice.com
```

### سبب الاختيار

- قريب من معنى: المكتب العقاري الإلكتروني.
- لا يذكر سوريا أو السويداء، وهذا أفضل للتوسع وتقليل الحساسية الجغرافية.
- مناسب لكل سوريا ولاحقاً للخارج.
- مناسب للعقارات الآن، ولا يمنع إضافة قسم سيارات لاحقاً.
- مناسب للإيميلات الرسمية:

```text
noreply@erealtyoffice.com
info@erealtyoffice.com
support@erealtyoffice.com
sales@erealtyoffice.com
```

### بدائل إذا لم يكن متاحاً

بالترتيب:

```text
digitalrealtyoffice.com
smartrealtyoffice.com
estatehubonline.com
realtyofficeonline.com
realtylinker.com
```

لا نشتري أي بديل قبل تقييمه من جديد.

---

## 6. الاستخدام المستقبلي للدومين

نفس الدومين سيخدم:

```text
https://erealtyoffice.com             الموقع الرسمي
https://www.erealtyoffice.com         نسخة www
https://app.erealtyoffice.com         نسخة الويب من التطبيق لاحقاً
https://admin.erealtyoffice.com       لوحة الإدارة مستقبلاً إذا احتجنا
https://api.erealtyoffice.com         API مستقبلاً إذا احتجنا
```

والإيميلات:

```text
noreply@erealtyoffice.com             رسائل النظام وMagic Links
info@erealtyoffice.com                البريد الرسمي
support@erealtyoffice.com             الدعم
sales@erealtyoffice.com               المبيعات لاحقاً
```

---

## 7. ما الذي يجب شراؤه؟

يجب شراء **الدومين فقط**:

```text
erealtyoffice.com لمدة سنة واحدة
```

لا تشتري:

- Hosting.
- Email Hosting.
- SSL مدفوع.
- Website Builder.
- VPN.
- Logo maker.
- Premium DNS إذا كان مدفوعاً.
- أي خدمة إضافية غير واضحة.

إذا ظهرت WHOIS Privacy مجاناً، اتركها مفعلة.

---

## 8. الخطة التنفيذية المختصرة

### المرحلة A — قبل الشراء

1. إنشاء حساب Namecheap لصاحب المشروع.
2. حفظ البريد واسم المستخدم المستخدم في الحساب.
3. إرسال اسم المستخدم/الإيميل إلى الصديق الذي سيدفع.
4. التأكد من توفر الدومين قبل الدفع مباشرة.

### المرحلة B — صديقك يشتري الدومين

1. يدخل إلى Namecheap.
2. يبحث عن:

```text
erealtyoffice.com
```

3. يضيف الدومين فقط إلى السلة.
4. يتأكد أنه لا توجد إضافات مدفوعة.
5. يشتري الدومين لمدة سنة واحدة.
6. بعد الشراء، يفعّل Share Access لحسابك بصلاحية Advanced DNS.

### المرحلة C — أنت تضبط Resend

1. تدخل إلى Resend.
2. تضيف الدومين:

```text
erealtyoffice.com
```

3. تأخذ سجلات DNS التي يعطيها Resend.
4. تضيفها في Namecheap Advanced DNS.
5. تنتظر تحقق Resend.

### المرحلة D — ضبط Supabase SMTP

بعد تحقق Resend:

```text
Authentication → Settings → SMTP Settings
```

وتضبط:

```text
Enable custom SMTP: ON
Sender email address: noreply@erealtyoffice.com
Sender name: المكتب العقاري الإلكتروني
Host: smtp.resend.com
Port: 465 أو 587 حسب إعداد Resend المستخدم
Username: resend
Password: Resend SMTP/API key
Minimum interval per user: 60 seconds مبدئياً
```

### المرحلة E — اختبار الإيميل

1. التسجيل بإيميل غير Gmail الخاص بحساب Resend.
2. التأكد من وصول Magic Link.
3. الضغط على الرابط.
4. التأكد من إنشاء صف في `public.users`.
5. التأكد من أن `handle_email_auth_internal` تعمل كما يجب.

---

## 9. خطوات إنشاء حساب Namecheap لصاحب المشروع

1. افتح:

```text
https://www.namecheap.com
```

2. أنشئ حساباً بإيميل تستطيع الوصول إليه دائماً.
3. فعّل 2FA إن أمكن.
4. لا تضف بطاقة دفع إن لم ترغب.
5. احتفظ بهذه البيانات داخلياً:

```text
Namecheap username:
Namecheap email:
2FA enabled: yes/no
```

لا ترسل كلمة مرورك لأحد.

---

## 10. رسالة جاهزة للصديق الذي سيدفع

انسخ هذه الرسالة كما هي مع تعديل بيانات حسابك:

```text
Hi, I need you to buy one domain for my project.

Domain:
erealtyoffice.com

Registrar:
Namecheap.com

Please buy it for 1 year only.

Important:
- Do not buy hosting
- Do not buy email
- Do not buy SSL
- Do not buy website builder
- Do not buy any extra paid services
- Only the domain
- Keep WHOIS privacy enabled if it is free

After purchase, please share DNS access with my Namecheap account:
[PUT MY NAMECHEAP USERNAME OR EMAIL HERE]

Path:
Domain List → Manage → Sharing & Transfer → Share Access

Permission needed:
Advanced DNS

Thank you.
```

---

## 11. خطوات Share Access في Namecheap

ينفذها صاحب الحساب الذي اشترى الدومين:

1. تسجيل الدخول إلى Namecheap.
2. فتح:

```text
Domain List
```

3. الضغط على:

```text
Manage
```

بجانب الدومين.

4. فتح تبويب:

```text
Sharing & Transfer
```

5. الوصول إلى:

```text
Share Access
```

6. إدخال حسابك في Namecheap:

```text
[Namecheap username/email]
```

7. اختيار صلاحيات:

```text
Advanced DNS
```

8. تأكيد العملية.

بعدها يجب أن يظهر الدومين عندك بصلاحيات DNS، بدون أن تملك حساب صديقك.

---

## 12. إعداد Resend بالتفصيل

### 12.1 إضافة الدومين

1. افتح Resend.
2. انتقل إلى:

```text
Domains
```

3. اضغط:

```text
Add Domain
```

4. أدخل:

```text
erealtyoffice.com
```

5. سيعطيك Resend سجلات DNS.

### 12.2 أنواع السجلات المتوقعة

غالباً سيطلب Resend سجلات مثل:

```text
TXT     SPF
TXT     DMARC
CNAME   DKIM
MX      Bounce/Return-path إن وجد
```

لا نخترع هذه القيم. ننسخها من Resend كما هي.

---

## 13. إضافة سجلات Resend في Namecheap

من حسابك الذي لديه Share Access:

1. افتح الدومين في Namecheap.
2. اذهب إلى:

```text
Advanced DNS
```

3. أضف سجلات Resend واحداً واحداً.
4. انتبه لهذه القواعد:

### قاعدة Host

إذا أعطاك Resend host مثل:

```text
resend._domainkey.erealtyoffice.com
```

في Namecheap قد تحتاج إدخال الجزء فقط:

```text
resend._domainkey
```

وليس الدومين الكامل.

إذا لم تكن متأكداً، لا تنفذ قبل مراجعة القيم.

### قاعدة TTL

استخدم:

```text
Automatic
```

أو القيمة الافتراضية.

### قاعدة عدم حذف سجلات غير مفهومة

لا تحذف أي سجل موجود إلا إذا تأكدنا أنه يتعارض.

---

## 14. إعداد Supabase SMTP بعد تحقق Resend

داخل Supabase:

```text
Authentication → Settings → SMTP Settings
```

القيم:

```text
Enable custom SMTP: ON
Sender email address: noreply@erealtyoffice.com
Sender name: المكتب العقاري الإلكتروني
Host: smtp.resend.com
Port: 465 أو 587
Username: resend
Password: SMTP password/API key من Resend
Minimum interval per user: 60
```

ملاحظات:

- إذا استخدمنا Port 465 فهو SSL.
- إذا استخدمنا Port 587 فهو TLS/STARTTLS.
- إذا كان واحد لا يعمل، نجرب الآخر حسب توصية Resend الحالية.

---

## 15. اختبار Supabase Email Auth بعد الإعداد

بعد حفظ SMTP:

1. افتح التطبيق.
2. تسجيل خروج.
3. اختر تسجيل عبر الإيميل.
4. استخدم بريد اختبار خارجي ليس بالضرورة بريد حساب Resend.
5. أرسل الرابط.
6. تحقق من وصول الإيميل.
7. اضغط الرابط.
8. تحقق أن التطبيق فتح.
9. تحقق من إنشاء المستخدم.

استعلام التحقق:

```sql
SELECT
  id,
  nm,
  ph,
  eml,
  role,
  sts,
  i_del,
  ts_crt
FROM public.users
WHERE lower(eml) = lower('PUT_TEST_EMAIL_HERE')
ORDER BY ts_crt DESC;
```

---

## 16. استعلامات تحقق مهمة للسيرفر

### 16.1 دالة الإيميل الآمنة

```sql
SELECT
  to_regprocedure('public.handle_email_auth_internal()') IS NOT NULL AS function_exists,
  has_function_privilege('anon', 'public.handle_email_auth_internal()', 'EXECUTE') AS anon_can_execute,
  has_function_privilege('authenticated', 'public.handle_email_auth_internal()', 'EXECUTE') AS authenticated_can_execute,
  has_function_privilege('service_role', 'public.handle_email_auth_internal()', 'EXECUTE') AS service_role_can_execute;
```

المتوقع:

```text
function_exists = true
anon_can_execute = false
authenticated_can_execute = true
service_role_can_execute = true
```

### 16.2 فهارس منع تكرار الإيميل والهاتف

```sql
SELECT
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'users'
  AND indexname IN (
    'users_unique_email_active_lower',
    'users_unique_phone_active',
    'idx_users_eml_unique'
  )
ORDER BY indexname;
```

### 16.3 قفل دوال OTP المباشرة

```sql
SELECT
  'upsert_user_after_otp' AS function_name,
  has_function_privilege('anon', 'public.upsert_user_after_otp(text, text)', 'EXECUTE') AS anon_can_execute,
  has_function_privilege('authenticated', 'public.upsert_user_after_otp(text, text)', 'EXECUTE') AS authenticated_can_execute,
  has_function_privilege('service_role', 'public.upsert_user_after_otp(text, text)', 'EXECUTE') AS service_role_can_execute
UNION ALL
SELECT
  'verify_otp_v2',
  has_function_privilege('anon', 'public.verify_otp_v2(text, text)', 'EXECUTE'),
  has_function_privilege('authenticated', 'public.verify_otp_v2(text, text)', 'EXECUTE'),
  has_function_privilege('service_role', 'public.verify_otp_v2(text, text)', 'EXECUTE')
UNION ALL
SELECT
  'generate_otp_v2',
  has_function_privilege('anon', 'public.generate_otp_v2(text, text)', 'EXECUTE'),
  has_function_privilege('authenticated', 'public.generate_otp_v2(text, text)', 'EXECUTE'),
  has_function_privilege('service_role', 'public.generate_otp_v2(text, text)', 'EXECUTE');
```

المتوقع:

```text
anon = false
authenticated = false
service_role = true
```

---

## 17. اختبار Resend مباشرة من سجلات Supabase

إذا فشل إرسال الإيميل من التطبيق:

1. افتح Supabase Dashboard.
2. اذهب إلى:

```text
Logs → Auth
```

3. ابحث عن:

```text
Error sending confirmation email
```

4. إذا ظهرت رسالة مثل:

```text
You can only send testing emails to your own email address
```

فهذا يعني أن Resend ما زال في وضع الاختبار أو الدومين غير موثق أو Sender Email ليس من الدومين الموثق.

---

## 18. رسائل خطأ متوقعة وحلولها

### الخطأ 1

```text
You can only send testing emails to your own email address
```

الحل:

- توثيق دومين في Resend.
- تغيير Sender email في Supabase إلى بريد من نفس الدومين.

مثال:

```text
noreply@erealtyoffice.com
```

### الخطأ 2

```text
Error sending confirmation email
```

الحل:

- راجع Auth Logs.
- تحقق من SMTP host/port/username/password.
- تحقق من أن Resend domain verified.

### الخطأ 3

```text
Invalid redirect URL
```

الحل:

في Supabase Auth URL Configuration أضف redirect URL:

```text
io.supabase.sweeda://login-callback
```

وللموقع لاحقاً:

```text
https://app.erealtyoffice.com/login-callback
```

---

## 19. قيود سوريا ونصائح التشغيل

- لا تستخدم بيانات عنوان سورية عند إنشاء حساب الدومين إذا كان الحساب والدفع من خارج سوريا.
- لا تجعل الدومين يحتوي كلمة Syria أو Sweeda إذا كان الهدف التوسع وتخفيف الاحتكاك مع الخدمات الأجنبية.
- اجعل الحساب والدفع باسم الشخص الموجود خارج سوريا إذا هو من سيدفع.
- لا تشارك كلمات مرور الحسابات.
- استخدم Share Access أو أعضاء بصلاحيات محدودة عندما يكون ذلك ممكناً.
- احفظ الوصول إلى Resend وSupabase وNamecheap بشكل منظم.

---

## 20. قائمة تحقق قبل الشراء

| البند | تم؟ | ملاحظات |
|---|---|---|
| تأكدنا أن `erealtyoffice.com` متاح |  |  |
| أنشأنا حساب Namecheap لصاحب المشروع |  |  |
| فعّلنا 2FA على حساب Namecheap |  |  |
| جهزنا رسالة الصديق |  |  |
| اتفقنا أن الشراء دومين فقط بدون إضافات |  |  |
| تأكدنا من السعر والتجديد السنوي |  |  |
| الصديق يستطيع الدفع ببطاقة/PayPal/وسيلة مناسبة |  |  |

---

## 21. قائمة تحقق بعد الشراء

| البند | تم؟ | ملاحظات |
|---|---|---|
| الدومين ظهر في حساب الصديق |  |  |
| Share Access أُرسل لحساب صاحب المشروع |  |  |
| صلاحية Advanced DNS مفعلة |  |  |
| الدومين ظهر عند صاحب المشروع |  |  |
| Resend domain أُضيف |  |  |
| سجلات DNS أضيفت في Namecheap |  |  |
| Resend domain verified |  |  |
| Supabase SMTP تم تحديثه |  |  |
| Magic Link وصل لبريد خارجي |  |  |
| تسجيل الإيميل أنشأ مستخدم في `public.users` |  |  |

---

## 22. القرار النهائي

القرار الحالي المعتمد:

```text
الدومين: erealtyoffice.com
الشراء: Namecheap
DNS مبدئي: Namecheap Advanced DNS
Email sending: Resend
Supabase SMTP sender: noreply@erealtyoffice.com
الموقع لاحقاً: erealtyoffice.com / app.erealtyoffice.com
```

لا يتم الشراء قبل التأكد من:

- السعر الحالي.
- سعر التجديد.
- أن الدومين ليس Premium Domain بسعر مرتفع.
- أن صديقك لن يشتري إضافات غير لازمة.

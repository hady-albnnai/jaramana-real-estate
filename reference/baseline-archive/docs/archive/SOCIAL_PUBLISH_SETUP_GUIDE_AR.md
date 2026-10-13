# دليل ربط فيسبوك وإنستغرام للنشر التلقائي — خطوة بخطوة

> **الهدف:** جعل العروض تُنشر تلقائياً على صفحة فيسبوك وحساب إنستغرام بعد موافقة الإدارة، باستخدام Edge Functions الآمنة.

**تاريخ التحديث:** 2026-07-14 — الوضع التلقائي مفعّل افتراضياً `autoPublish = true`

---

## 1. المتطلبات الأساسية

1. صفحة فيسبوك رسمية للمكتب (Page) — أنت Admin عليها.
2. حساب إنستغرام Business/Professional مربوط بنفس صفحة فيسبوك (من إعدادات الصفحة → Linked Accounts → Instagram).
3. حساب Meta Developers `developers.facebook.com` (نفس حساب فيسبوك الذي يدير الصفحة).

---

## 2. إنشاء تطبيق Meta

1. ادخل `https://developers.facebook.com` → My Apps → Create App
2. اختر نوع التطبيق: **Business** أو **Other** → Business
3. اسم التطبيق: `Sweeda Real Estate` مثلاً
4. بعد الإنشاء، من لوحة التطبيق → **Use cases** أو **Products** أضف:
   - **Facebook Login for Business**
   - **Instagram Graph API** (إن لم يظهر، أضفه من Add Product)

---

## 3. ربط الأصول (Assets) بالتطبيق

1. في لوحة التطبيق → **App Settings → Business** → اربط الـ Business Manager الذي يملك الصفحة.
2. أو من **Business Settings (business.facebook.com)**:
   - Accounts → Pages → أضف صفحتك → اربطها بالتطبيق.
   - Accounts → Instagram Accounts → أضف حساب الإنستغرام.

هذه الخطوة مهمة لأن الصلاحيات `pages_manage_posts` و `instagram_content_publish` تتطلب أن يملك التطبيق الأصول.

---

## 4. الصلاحيات المطلوبة

في **App Review → Permissions and Features** أو **Use Cases → Permissions** ستحتاج:

| الصلاحية | الغرض |
|---|---|
| `pages_read_engagement` | قراءة معلومات الصفحة |
| `pages_manage_posts` | نشر صور + نص على صفحة فيسبوك |
| `instagram_basic` | قراءة حساب إنستغرام المرتبط |
| `instagram_content_publish` | نشر كاروسيل صور على إنستغرام |

- **للتطوير والاختبار:** إذا كنت Admin أو لديك Role في التطبيق (Admin/Developer/Tester) ويُستخدم التطبيق فقط لنشر على أصول تملكها نفس الـ Business، يمكنك استخدام التوكنات فوراً دون App Review (Development Mode يكفي).
- **للإنتاج الكامل (نشر لصفحات عملاء آخرين):** ستحتاج Advanced Access + App Review. ابدأ بالاختبار في Development أولاً.

---

## 5. توليد Page Access Token طويل العمر

الطريقة السريعة (Graph Explorer):

1. افتح **Graph API Explorer** `https://developers.facebook.com/tools/explorer/`
2. اختر تطبيقك، ثم الصفحة.
3. اطلب الصلاحيات الأربعة أعلاه.
4. انسخ User Access Token (قصير العمر) ثم حوله:

```bash
# 1) حوّل User Token قصير → طويل (60 يوم)
curl -i -X GET "https://graph.facebook.com/v25.0/oauth/access_token?grant_type=fb_exchange_token&client_id=APP_ID&client_secret=APP_SECRET&fb_exchange_token=SHORT_USER_TOKEN"

# الناتج: long-lived user token

# 2) احصل على Page Token طويل العمر
curl -i -X GET "https://graph.facebook.com/v25.0/me/accounts?access_token=LONG_USER_TOKEN"

# الناتج يحتوي لكل صفحة: id + access_token (هذا التوكن لا ينتهي طالما لم تغير كلمة المرور/الصلاحيات)
```

**احفظ الناتج:**
- `META_PAGE_ACCESS_TOKEN` = access_token الخاص بصفحتك من الخطوة 2
- `META_FACEBOOK_PAGE_ID` = id الصفحة
- `META_INSTAGRAM_ACCOUNT_ID` = id حساب إنستغرام المرتبط (تحصل عليه عبر `/{PAGE_ID}?fields=instagram_business_account`)

```bash
curl "https://graph.facebook.com/v25.0/{PAGE_ID}?fields=instagram_business_account&access_token={PAGE_TOKEN}"
# الناتج: {"instagram_business_account":{"id":"1784..."}}
```

---

## 6. ضبط الأسرار في Supabase

**لا تضع التوكن في الكود أو في app_config أو في Git أبداً.** فقط كـ Supabase Edge Secrets:

```bash
# من داخل مجلد المشروع المحلي حيث supabase CLI مثبت
supabase login
supabase link --project-ref vsgkgnjtebjxyqwpuopz

supabase secrets set \
  META_PAGE_ACCESS_TOKEN='EAA...' \
  META_FACEBOOK_PAGE_ID='123456789...' \
  META_INSTAGRAM_ACCOUNT_ID='178414...' \
  META_GRAPH_API_VERSION='v25.0'
```

> `META_GRAPH_API_VERSION` اختياري، الافتراضي في الكود `v25.0`. يمكنك تغييره دون تعديل الكود عبر Secrets.

تحقق:

```bash
supabase secrets list
```

---

## 7. تطبيق Migration ونشر Edge Functions

```bash
# 1) طبّق جداول النشر (إن لم تكن طبقتها سابقاً)
supabase db push
# سيطبق:
# - 2026_07_13_social_publishing_phase2.sql
# - 2026_07_14_social_auto_publish_enable.sql (يضبط autoPublish=true)

# 2) انشر الوظائف
supabase functions deploy publish-to-social
supabase functions deploy admin-offers
```

إذا كنت تستخدم Dashboard فقط (بدون CLI)، نفّذ ملفات الـ Migration يدوياً من SQL Editor ثم Deploy Functions من Dashboard → Edge Functions.

---

## 8. التفعيل والاختبار

1. ادخل `/admin/config` → تأكد أن مفتاح **النشر التلقائي فور قبول العرض** مفعّل (أخضر).
2. أضف عرض اختبار من حساب مستخدم عادي:
   - فعل تشيك بوكس "نشر العرض تلقائياً على صفحاتنا..."
   - أضف صورة واحدة على الأقل (مطلوبة لإنستغرام) — الصورة يجب أن تكون رابط عام https
   - أرسل للمراجعة
3. من حساب إداري → `/admin/offers` → اضغط **قبول**
   - يجب أن ترى رسالة: `✅ تم نشر العرض داخلياً • 📣 ✅ تم النشر تلقائياً على فيسبوك وإنستغرام`
   - وإلا سترى رسالة الفشل مع السبب (مثلاً META_SECRETS_NOT_CONFIGURED)
4. تحقق من صفحة فيسبوك وحساب إنستغرام: يجب أن يظهر منشور كاروسيل (حتى 10 صور) مع نفس نص `socTxt`.
5. في قاعدة البيانات:
```sql
SELECT soc_pub, i_soc FROM offers WHERE id = '...' ; -- يجب أن يكون soc_pub=2 بعد النجاح
SELECT platform, status, post_id, error_message, attempts FROM social_publications WHERE offer_id = '...';
```

---

## 9. معالجة الفشل وإعادة المحاولة

- الجدول `social_publications` يحفظ حالة كل منصة بشكل منفصل:
  - `facebook: published` + `instagram: failed` → عند إعادة المحاولة سينشر إنستغرام فقط.
- إذا نجح فيسبوك وفشل إنستغرام يبقى `offers.soc_pub = 1` ويبقى العرض في قائمة **جاهزة للنشر**.
- اضغط زر **نشر الآن** أو **نشر الكل** لإعادة المحاولة — لا ينشئ منشور مكرر للمنصة التي نجحت.

**الأخطاء الشائعة:**

| الخطأ | الحل |
|---|---|
| `META_SECRETS_NOT_CONFIGURED` | لم تضبط Secrets الثلاثة |
| `PUBLIC_IMAGE_REQUIRED` | لا توجد صور https عامة في العرض — تأكد أن الصور في `offer_images` bucket العام |
| `FACEBOOK_PHOTO_ID_MISSING` / `INSTAGRAM_...` | مشكلة مؤقتة في Graph API أو روابط الصور غير صالحة |
| `OAuthException ... permission` | الصلاحيات غير ممنوحة أو التوكن منتهي — أعد توليد Page Token |
| `PUBLISH_IN_PROGRESS` | شخص آخر ينشر نفس العرض الآن — انتظر 10 دقائق |

---

## 10. الوضع التلقائي (بعد نجاح الاختبار اليدوي)

- **منذ 2026-07-14:** `socialPublishing.autoPublish = true` افتراضياً في الكود وفي الـ Migration الجديد.
- عند قبول أي عرض جديد فيه `i_soc=1` و `socTxt` ولو صورة واحدة، سيُنشر فوراً.
- يمكنك تعطيله مؤقتاً من `/admin/config` إذا أردت المراجعة اليدوية فقط.
- زر **نشر الكل** يبقى متاحاً كاحتياط لإعادة نشر العروض التي فشلت سابقاً.

---

## 11. ملاحظات أمنية

- التوكنات لا تُحفظ أبداً في `app_config` أو في التطبيق أو في Git — فقط كـ Edge Secrets.
- Edge Functions تتحقق من جلسة الموظف (role>=3) قبل أي نشر.
- روابط الصور يجب أن تكون https عامة (Supabase `getPublicUrl` يحقق ذلك) — لا تستخدم روابط private أو signed قصيرة المدى لحظة النشر.
- نص إنستغرام يُقص إلى 2200 حرف.

---

## 12. أوامر سريعة للنسخ

```bash
# تطبيق DB
supabase db push

# ضبط أسرار Meta (استبدل القيم)
supabase secrets set META_PAGE_ACCESS_TOKEN='EAA...' META_FACEBOOK_PAGE_ID='123' META_INSTAGRAM_ACCOUNT_ID='1784...' META_GRAPH_API_VERSION='v25.0'

# نشر الوظائف
supabase functions deploy publish-to-social
supabase functions deploy admin-offers

# متابعة اللوجز
supabase functions logs --filter publish-to-social
supabase functions logs --filter admin-offers
```

بعد ذلك: جرب دورة كاملة (إضافة → موافقة → تحقق من فيسبوك/إنستغرام).

---

**جاهز!** الآن النشر يحدث تلقائياً بعد موافقة الإدارة، مع حماية من التكرار وإمكانية إعادة المحاولة اليدوية.

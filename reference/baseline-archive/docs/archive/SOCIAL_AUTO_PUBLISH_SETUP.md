# 📱 دليل إعداد النشر التلقائي على فيس بوك وانستغرام

> **لرفيقك بنيجيريا** — كل الخطوات يجب تنفذ من حسابه لأن سوريا عليها حظر من ميتا

---

## 📋 ملخص اللي رح نعمله

```
حساب فيس بوك شخصي (رفيقك)
    │
    ├──► صفحة فيس بوك تجارية (المكتب العقاري الالكتروني)
    │
    ├──► حساب انستغرام تجاري (مرتبط بالصفحة)
    │
    ├──► Meta Business Suite (إدارة مركزية)
    │
    └──► Meta Developer App (للحصول على التوكنز)
              │
              └──► Supabase Edge Function (نشر تلقائي من التطبيق)
```

---

# 🟢 المرحلة الأولى: إنشاء صفحة فيس بوك تجارية

> ⏱️ الوقت المقدر: 10 دقائق

### الخطوة 1.1 — فتح Meta Business Suite

1. رفيقك يفتح المتصفح على الكمبيوتر
2. يدخل على: **https://business.facebook.com**
3. يسجل دخول بحسابه الشخصي على فيس بوك
4. إذا سألو "Create a business portfolio" — يضغط **Create Account**

### الخطوة 1.2 — إنشاء Business Portfolio

1. **Business portfolio name**: `المكتب العقاري الالكتروني`
2. **Your full name**: اسم رفيقك الحقيقي
3. **Business email**: إيميل رفيقك (مو شروط يكون نفس إيميل فيس بوك)
4. يضغط **Submit**

### الخطوة 1.3 — إنشاء صفحة فيس بوك جديدة

1. من القائمة اليسار يضغط **Settings** ⚙️
2. يضغط **Business assets** → **Pages**
3. يضغط زر **Add assets** → **Facebook Page** → **Create a new Facebook Page**
4. يملأ البيانات:
   - **Page name**: `المكتب العقاري الالكتروني`
   - **Category**: اكتب `Real Estate` واختار `Real Estate Agent`
   - **Bio**: `منصتك العقارية الذكية — بيع، إيجار، وتصوير عقاري احترافي 🏠`
5. يضغط **Create Page**
6. **يضيف صورة شعار التطبيق** كصورة الملف (Profile picture)
7. **يضيف صورة غلاف** (Cover photo) — ممكن أي صورة عقارية مؤقتة

### الخطوة 1.4 — إعدادات الصفحة المهمة

1. يروح للصفحة الجديدة (يضغط عليها)
2. يضغط **Settings** → **Page Setup** → **Page Access**
3. يتأكد إنو هو **Admin** على الصفحة ✅
4. يضغط **Settings** → **Privacy**
5. يتأكد إنو الصفحة **Published** (منشورة) مش Unpublished

---

# 🟣 المرحلة الثانية: إنشاء حساب انستغرام تجاري

> ⏱️ الوقت المقدر: 15 دقيقة

### الخطوة 2.1 — إنشاء حساب انستغرام جديد

1. رفيقك يحمل تطبيق **Instagram** على موبايله
2. يضغط **Create new account**
3. **اسم المستخدم (Username)**: `sweeda.real_estate` أو `sweeda.realestate` أو `elc.real.estate`
4. **كلمة السر**: يختار كلمة سر قوية ويحفظها
5. **الاسم الكامل**: `المكتب العقاري الالكتروني`

### الخطوة 2.2 — التحويل لحساب تجاري (Business)

1. يفتح البروفايل → يضغط **≡** (القائمة) أعلى اليمين
2. يضغط **Settings and privacy** → **Account type and tools**
3. يضغط **Switch to professional account**
4. يختار **Business**
5. يختار التصنيف: **Real Estate**
6. **يربط الحساب بصفحة فيس بوك** اللي أنشأناها بالمرحلة الأولى
   - بيطلب منه يسجل دخول فيس بوك → يختار صفحة "المكتب العقاري الالكتروني"
7. يضغط **Done**

### الخطوة 2.3 — إكمال البروفايل

1. يضيف **صورة الملف** (نفس شعار التطبيق)
2. يضيف **Bio**: `🏠 منصتك العقارية الذكية | بيع • إيجار • تصوير`
3. يضيف **رابط**: رابط التطبيق أو الموقع

### ✅ نقطة فحص: التحقق من الربط

من الكمبيوتر، رفيقك يفتح:
**https://business.facebook.com** → **Settings** → **Business assets** → **Instagram accounts**

المفروض يشوف حساب الانستغرام مربوط ✅

---

# 🔵 المرحلة الثالثة: إنشاء Meta Developer App

> ⏱️ الوقت المقدر: 20 دقيقة
> 🎯 هذه أهم مرحلة — منها بنحصل على التوكنز

### الخطوة 3.1 — التسجيل كمطور

1. يفتح: **https://developers.facebook.com**
2. يسجل دخون بحساب فيس بوك الشخصي
3. إذا أول مرة — بيطلب منه يسجل كمطور:
   - يضغط **Get Started**
   - يوافق على الشروط
   - يأكد الإيميل
4. بعد التسجيل يضغط **Create App**

### الخطوة 3.2 — إنشاء التطبيق

1. يختار نوع التطبيق: **Business**
2. يضغط **Next**
3. يملأ البيانات:
   - **App name**: `Sweeda Real Estate Publisher`
   - **App contact email**: إيميل رفيقك
   - **Business portfolio**: يختار portfolio اللي أنشأناها
4. يضغط **Create app**
5. ممكن يطلب منه كلمة سر فيس بوك للتأكيد

### الخطوة 3.3 — إضافة منتجات (Use Cases)

1. بعد إنشاء التطبيق، بيكون في Dashboard
2. يضغط **Add use cases** أو **Customize**
3. يختار **Manage everything on your Page** ← هذا يضيف فيس بوك
4. يضغط **Add use case** مرة تانية
5. يختار **Manage messaging & content on Instagram** ← هذا يضيف انستغرام
6. لما يسأل عن API setup → يختار **API setup with Facebook Login**

### الخطوة 3.4 — إعداد الصلاحيات (Permissions)

من الـ Dashboard → **Permissions and features**:

الصلاحيات المطلوبة (يضغط **Add** بجانب كل وحدة):

| الصلاحية | الوصف | مطلوب لـ |
|----------|-------|----------|
| `pages_show_list` | عرض قائمة الصفحات | فيس بوك |
| `pages_read_engagement` | قراءة تفاعلات الصفحة | فيس بوك |
| `pages_manage_posts` | إنشاء/تعديل/حذف منشورات | فيس بوك ✅ مهم |
| `instagram_basic` | معلومات أساسية | انستغرام |
| `instagram_content_publish` | نشر محتوى على انستغرام | انستغرام ✅ مهم |

> ⚠️ بعض الصلاحيات تحتاج **App Review** (موافقة من ميتا) قبل الإنتاج.
> بس للـ testing + Admin حصري، منقدر نستخدمها بدون Review لأنو التطبيق في وضع **Development**.

### الخطوة 3.5 — إعداد Facebook Login

1. من Dashboard → يضغط **Facebook Login** → **Settings**
2. **Valid OAuth Redirect URIs**: يضيف:
   ```
   https://vsgkgnjtebjxyqwpuopz.supabase.co/functions/v1/social-auth-callback
   ```
3. يضغط **Save**

### الخطوة 3.6 — حفظ بيانات التطبيق المهمة 🔑

من **Settings** → **Basic**:

| البيانات | وين لقاها |
|----------|-----------|
| **App ID** | معروض فوق |
| **App Secret** | يضغط **Show** بجانبه |

⚠️ **يحفظ هادول بمكان آمن** — رح نحتاجهم للاستبدال بالتوكنز!

---

# 🟡 المرحلة الرابعة: الحصول على التوكنز

> ⏱️ الوقت المقدر: 30 دقيقة
> 🎯 هذه المرحلة الأكثر تعقيداً — اتبع خطوة بخطوة

## كيف تعمل التوكنز؟

```
Short-lived User Token (ساعة واحدة)
    │
    ▼ نستبدله بـ
Long-lived User Token (60 يوم)
    │
    ▼ نستبدله بـ
Long-lived Page Token (لا ينتهي أبدداً! ✅)
```

### الخطوة 4.1 — الحصول على Short-lived User Token

1. يفتح: **https://developers.facebook.com/tools/explorer/**
2. يختار التطبيق: **Sweeda Real Estate Publisher** (من القائمة يمين فوق)
3. يضغط **User or Page** → **User Token**
4. يضغط **Generate Access Token**
5. بيظهر قائمة الصلاحيات — يختار **كل** الصلاحيات المذكورة بالجدال فوق
6. يوافق على الأذونات
7. **ينسخ التوكن** اللي ظهر ✅ → هذا هو **Short-lived User Token**

### الخطوة 4.2 — استبداله بـ Long-lived User Token

يفتح Terminal أو متصفح وينفذ:

```bash
curl -X GET "https://graph.facebook.com/v21.0/oauth/access_token?grant_type=fb_exchange_token&client_id=APP_ID&client_secret=APP_SECRET&fb_exchange_token=SHORT_LIVED_TOKEN"
```

استبدل:
- `APP_ID` ← من الخطوة 3.6
- `APP_SECRET` ← من الخطوة 3.6
- `SHORT_LIVED_TOKEN` ← من الخطوة 4.1

**النتيجة** رح تكون JSON فيها `access_token` جديد — هذا هو **Long-lived User Token** (60 يوم)

✅ انسخه واحفظه!

### الخطوة 4.3 — الحصول على Page ID

```bash
curl -X GET "https://graph.facebook.com/v21.0/me/accounts?fields=id,name&access_token=LONG_LIVED_USER_TOKEN"
```

استبدل `LONG_LIVED_USER_TOKEN` ← من الخطوة 4.2

**النتيجة** رح تكون:
```json
{
  "data": [
    {
      "id": "123456789012345",
      "name": "المكتب العقاري الالكتروني"
    }
  ]
}
```

✅ انسخ الـ `id` — هذا هو **Facebook Page ID**

### الخطوة 4.4 — الحصول على Long-lived Page Token (لا ينتهي! 🎉)

```bash
curl -X GET "https://graph.facebook.com/v21.0/PAGE_ID?fields=access_token&access_token=LONG_LIVED_USER_TOKEN"
```

استبدل:
- `PAGE_ID` ← من الخطوة 4.3
- `LONG_LIVED_USER_TOKEN` ← من الخطوة 4.2

**النتيجة**:
```json
{
  "access_token": "EAAxxxxxxxxxxxxxxxxxxxxxx",
  "id": "123456789012345"
}
```

✅ هذا هو **Long-lived Page Token** — **لا ينتهي أبداً** طالما التطبيق فعال!

🔑 احفظه بمكان آمن جداً — هذا اللي رح نستخدمه للنشر على فيس بوك!

### الخطوة 4.5 — الحصول على Instagram Business Account ID

```bash
curl -X GET "https://graph.facebook.com/v21.0/PAGE_ID?fields=instagram_business_account&access_token=PAGE_TOKEN"
```

استبدل:
- `PAGE_ID` ← من الخطوة 4.3
- `PAGE_TOKEN` ← من الخطوة 4.4

**النتيجة**:
```json
{
  "instagram_business_account": {
    "id": "17841400000000000"
  },
  "id": "123456789012345"
}
```

✅ انسخ الـ `id` داخل `instagram_business_account` — هذا هو **Instagram Business Account ID**

---

# 🟠 المرحلة الخامسة: التحقق من التوكنز

> قبل ما نكمل، لازم نتأكد إنو التوكنز شغالة

### اختبار فيس بوك — إنشاء منشور تجريبي

```bash
curl -X POST "https://graph.facebook.com/v21.0/PAGE_ID/feed?message=🏠 تجربة النشر التلقائي من المكتب العقاري الالكتروني&access_token=PAGE_TOKEN"
```

إذا رجع:
```json
{"id": "123456789012345_987654321"}
```
✅ يعني فيس بوك شغال!

**بعدها احذف المنشور التجريبي** من الصفحة يدوياً.

### اختبار انستغرام — إنشاء منشور صورة تجريبي

> ⚠️ انستغرام لازم رابط صورة عامة (URL)، مش رفع مباشر

```bash
curl -X POST "https://graph.facebook.com/v21.0/IG_BUSINESS_ID/media?image_url=https://upload.wikimedia.org/wikipedia/commons/thumb/a/a7/Camponotus_flavomarginatus_ant.jpg/320px-Camponotus_flavomarginatus_ant.jpg&caption=🏠 تجربة النشر التلقائي #عقارات&access_token=PAGE_TOKEN"
```

إذا رجع:
```json
{"id": "178896xxxxxxx"}
```

انتظر 10 ثواني، بعدها انشر:

```bash
curl -X POST "https://graph.facebook.com/v21.0/IG_BUSINESS_ID/media_publish?creation_id=178896xxxxxxx&access_token=PAGE_TOKEN"
```

✅ إذا ظهر المنشور على الانستغرام — كل شيء شغال!

---

# 🔴 المرحلة السادسة: حفظ البيانات بالسيرفر

### البيانات اللي لازم تحفظها:

| المفتاح | القيمة | الوصف |
|---------|--------|-------|
| `FB_PAGE_ID` | `123456789012345` | معرف صفحة فيس بوك |
| `FB_PAGE_TOKEN` | `EAAxxxx...` | توكن صفحة فيس بوك (لا ينتهي) |
| `IG_BUSINESS_ID` | `17841400...` | معرف حساب انستغرام التجاري |
| `FB_APP_ID` | `987654321` | معرف تطبيق ميتا |
| `FB_APP_SECRET` | `abc123...` | سر تطبيق ميتا |

### طريقة الحفظ:

بنحفظهم بجدول `app_config` في Supabase، ضمن مفتاح `social`:

```sql
UPDATE app_config
SET value = jsonb_set(
  COALESCE(value, '{}'::jsonb),
  '{social}',
  '{
    "fb_page_id": "ضع_هنا",
    "fb_page_token": "ضع_هنا",
    "ig_business_id": "ضع_هنا",
    "fb_app_id": "ضع_هنا",
    "fb_app_secret": "ضع_هنا"
  }'::jsonb
)
WHERE key = 'main';
```

---

# 📊 مخطط التكامل مع التطبيق

```
المستخدم يضيف عرض جديد
    │
    ▼
يعرض زر "نشر على السوشال" ← generateSocialPost()
    │
    ▼
يضغط المستخدم "نشر"
    │
    ▼
Edge Function: social-publish
    │
    ├──► فيس بوك: POST /{PAGE_ID}/feed
    │    └── message + رابط العرض + صورة (link attachment)
    │
    └──► انستغرام: POST /{IG_ID}/media → media_publish
         └── image_url (أول صورة من العرض) + caption
    │
    ▼
تحديث العرض: soc_pub = 1 + soc_txt = النص
    │
    ▼
منح نقاط مشاركة (socialSharePoints)
```

---

# ⚠️ ملاحظات مهمة

1. **انستغرام لا ينشر نص فقط** — لازم صورة على الأقل. رح نستخدم أول صورة من العرض
2. **في.loaded بوك ممكن نشر نص + رابط + صورة** — أنسب للعروض
3. **التوكنز بالـ Development mode** بتشتغل فقط لحساب رفيقك كم Admin. للإنتاج لازم **App Review**
4. **App Review** بياخذ 3-10 أيام — بنتقدم عليه لاحقاً
5. **Long-lived Page Token لا ينتهي** بس لازم نعمله Refresh إذا صار بالـ Logs "token expired" (نادر)
6. **كل العمليات رح تمر عبر Edge Function** — ما في توكنز بالتطبيق (أمان)

---

# 📞 بعد ما رفيقك يخلص

أرسلي هاد البيانات:
1. ✅ Page ID
2. ✅ Page Token
3. ✅ Instagram Business Account ID
4. ✅ App ID
5. ✅ App Secret

ورح نبني الـ Edge Function للنشر التلقائي + زر النشر بالتطبيق 💪

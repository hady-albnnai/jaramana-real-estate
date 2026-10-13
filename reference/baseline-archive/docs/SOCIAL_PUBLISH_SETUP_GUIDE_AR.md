# 🔧 دليل ضبط توكنات النشر على فيسبوك وإنستغرام

> **التاريخ:** 2026-08-05  
> **الإصدار:** 2.0 (مفصّل)  
> **الهدف:** تفعيل النشر التلقائي للعروض على صفحات التواصل الاجتماعي  
> **المدة المتوقعة:** 45-60 دقيقة  
> **المستوى:** متوسط (يحتاج معرفة أساسية بفيسبوك وإنستغرام)

---

## 📖 مقدمة: كيف يعمل النشر التلقائي؟

قبل البدء، من المهم فهم العملية الكاملة:

```
┌─────────────────────────────────────────────────────────────┐
│ 1. المستخدم يضيف عرض + يفعّل "النشر على السوشيال"          │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. المدير يراجع العرض ويضغط "قبول"                         │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. النظام ينشر العرض داخلياً (sts=2, i_pub=1)              │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. Edge Function تستدعي publishOfferToSocial()              │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ├──────────────────┬──────────────────┐
                     ▼                  ▼                  ▼
              ┌────────────┐    ┌────────────┐    ┌────────────┐
              │ فيسبوك     │    │ إنستغرام   │    │ قاعدة      │
              │ Graph API  │    │ Graph API  │    │ البيانات   │
              └─────┬──────┘    └─────┬──────┘    └─────┬──────┘
                    │                 │                 │
                    ▼                 ▼                 ▼
              ┌─────────────────────────────────────────────┐
              │ 5. المنشور يظهر على الصفحات + soc_pub=2     │
              └─────────────────────────────────────────────┘
```

### لماذا نحتاج التوكنات؟

- **`META_PAGE_ACCESS_TOKEN`**: إذن من فيسبوك يسمح للتطبيق بالنشر على صفحتك
- **`META_FACEBOOK_PAGE_ID`**: رقم تعريف صفحتك (حتى يعرف النظام أين ينشر)
- **`META_INSTAGRAM_ACCOUNT_ID`**: رقم تعريف حساب الإنستغرام المهني

بدون هذه التوكنات، النظام لا يستطيع الوصول إلى Meta Graph API.

---

## 📋 المتطلبات التفصيلية

### 1. حساب فيسبوك
- ✅ **حساب شخصي** (ليس صفحة) مع صلاحيات **أدمن** على الصفحة المستهدفة
- ✅ **الصفحة** يجب أن تكون:
  - منشورة (ليست في وضع المسودة)
  - غير محظورة أو مقيدة
  - من نوع "Business" أو "Community"
- ✅ **الصلاحيات المطلوبة على الصفحة**:
  - Manage Page (إدارة الصفحة)
  - Create Content (إنشاء محتوى)
  - Moderate Community (إدارة المجتمع)

### 2. حساب إنستغرام
- ✅ **حساب مهني** (Professional Account) - ليس شخصي
- ✅ **نوع الحساب**: Business (ليس Creator)
- ✅ **مرتبط** بصفحة الفيسبوك المستهدفة
- ✅ **الصلاحيات المطلوبة**:
  - Content Publishing (نشر المحتوى)
  - Read Insights (قراءة الإحصائيات)

### 3. حساب Supabase
- ✅ **صلاحيات أدمن** على المشروع
- ✅ **القدرة على**:
  - إضافة/تعديل Secrets
  - نشر Edge Functions
  - قراءة Logs

### 4. المتطلبات التقنية
- ✅ **متصفح حديث** (Chrome/Firefox/Safari)
- ✅ **أداة سطر الأوامر** (Terminal/Command Prompt) - اختياري
- ✅ **curl** مثبت على الجهاز - اختياري (يمكن استخدام Postman بدلاً منه)

### 5. التحقق من المتطلبات

قبل البدء، تحقق من:

```bash
# 1. هل أنت أدمن على الصفحة؟
# افتح: https://facebook.com/[your-page]/settings
# يجب أن ترى "Page Access" مع صلاحيات كاملة

# 2. هل حساب الإنستغرام مهني؟
# افتح إنستغرام → Profile → Settings → Account
# يجب أن ترى "Switch to Personal Account" (وليس "Switch to Professional")

# 3. هل الحسابان مرتبطان؟
# افتح إنستغرام → Settings → Account → Linked Accounts
# يجب أن ترى "Facebook" مع اسم صفحتك
```

---

## 🎯 المرحلة 1: إنشاء Meta App

### ما هو Meta App؟

**Meta App** هو تطبيق تسجله عند Meta (الشركة المالكة لفيسبوك وإنستغرام) للحصول على إذن للوصول إلى APIs الخاصة بهم. بدون هذا التطبيق، لا يمكن للتطبيق الخاص بك النشر على صفحاتك.

### الخطوة 1.1: الدخول إلى Meta for Developers

1. **افتح المتصفح** واذهب إلى: https://developers.facebook.com/

2. **سجّل الدخول**:
   - اضغط **"Log In"** في الأعلى
   - استخدم **نفس حساب الفيسبوك** اللي عندك صلاحيات أدمن على الصفحة
   - ⚠️ **مهم جداً**: يجب أن يكون نفس الحساب اللي هو أدمن على الصفحة

3. **بعد تسجيل الدخول**:
   - سترى لوحة التحكم الرئيسية
   - في الأعلى، اضغط **"My Apps"**
   - ثم اضغط **"Create App"** (زر أخضر)

### الخطوة 1.2: إنشاء التطبيق

ستظهر نافذة بعنوان **"Create an App"**:

1. **اختر نوع التطبيق**:
   ```
   📋 ما نوع التطبيق اللي تريد بناءه؟
   
   ○ Consumer (للتطبيقات الاستهلاكية)
   ● Business (للتطبيقات التجارية) ← اختر هذا
   ○ Gaming (للألعاب)
   ○ Other (آخر)
   ```
   - اختر **"Business"**
   - اضغط **"Next"**

2. **املأ بيانات التطبيق**:
   ```
   App Information
   ─────────────────────────────────────
   App Display Name: عقارات السويداء
   App Contact Email: your-email@example.com
   Business Account: (اختياري - اتركه فارغ)
   ```
   - **App Display Name**: اسم التطبيق (يظهر للمستخدمين عند طلب الإذن)
   - **App Contact Email**: إيميلك (للتواصل من Meta)
   - **Business Account**: اتركه فارغ إذا لم يكن عندك Business Manager

3. **اضغط "Create App"**

4. **التحقق من الهوية** (قد يطلب):
   - إذا طلب Meta التحقق من هويتك، اتبع التعليمات
   - عادةً يطلب رقم هاتف أو تأكيد إيميل

### الخطوة 1.3: إضافة المنتجات (Products)

بعد إنشاء التطبيق، ستظهر **لوحة التحكم الخاصة بالتطبيق**:

```
┌─────────────────────────────────────────────────────────┐
│ عقارات السويداء                                         │
│ App ID: 123456789                                       │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ Add Product to Your App                                 │
│                                                         │
│ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐    │
│ │ Facebook     │ │ Instagram    │ │ WhatsApp     │    │
│ │ Login for    │ │ Basic        │ │ Business     │    │
│ │ Business     │ │ Display      │ │ Platform     │    │
│ │              │ │              │ │              │    │
│ │ [Set Up]     │ │ [Set Up]     │ │ [Set Up]     │    │
│ └──────────────┘ └──────────────┘ └──────────────┘    │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

1. **أضف "Facebook Login for Business"**:
   - اضغط **"Set Up"** تحت **"Facebook Login for Business"**
   - ستظهر صفحة الإعدادات
   - اتركها كما هي الآن (سنعود لها لاحقاً)

2. **أضف "Instagram Basic Display"**:
   - ارجع للصفحة الرئيسية (اضغط على اسم التطبيق في الأعلى)
   - اضغط **"Set Up"** تحت **"Instagram Basic Display"**
   - ستظهر صفحة الإعدادات
   - اتركها كما هي الآن

3. **التحقق**:
   - في القائمة اليسرى، يجب أن ترى:
     ```
     Products
     ├─ Facebook Login for Business
     └─ Instagram Basic Display
     ```

### الخطوة 1.4: ضبط إعدادات التطبيق

1. **من القائمة اليسرى**: اضغط **"Settings"** → **"Basic"**

2. **سترى معلومات التطبيق**:
   ```
   App ID: 123456789 (انسخه - ستحتاجه لاحقاً)
   App Secret: [Show] (اضغط "Show" وانسخه - ستحتاجه لاحقاً)
   ```

3. **أضف Privacy Policy URL** (مطلوب):
   ```
   Privacy Policy URL: https://your-app.com/privacy
   ```
   - إذا لم يكن عندك صفحة privacy، يمكنك استخدام:
     - https://www.freeprivacypolicy.com/ (مولد مجاني)
     - أو اتركه فارغ مؤقتاً (للتطوير فقط)

4. **اضغط "Save Changes"**

### الخطوة 1.5: جعل التطبيق "Live" (مهم!)

⚠️ **خطوة حرجة**: التطبيق يبدأ في وضع **"Development"** (تطوير) - يجب تحويله إلى **"Live"** (حي) حتى يعمل:

1. **في الأعلى**: ستجد مفتاح تبديل:
   ```
   App Mode: Development [🔴] → Live [🟢]
   ```

2. **اضغط على المفتاح** لتحويله إلى **"Live"**

3. **ستظهر نافذة تأكيد**:
   ```
   Are you sure you want to make this app live?
   
   [Cancel] [Confirm]
   ```

4. **اضغط "Confirm"**

5. **التحقق**: يجب أن يتحول المفتاح إلى الأخضر 🟢

### ✍️ ملاحظات المرحلة 1

- ⚠️ **App Secret حساس جداً**: لا تشاركه مع أحد، لا تضعه في الكود، لا ترفعه على GitHub
- 💡 **اسم التطبيق**: اختر اسم واضح ومعبر (يظهر للمستخدمين عند طلب الإذن)
- 🔒 **وضع Development**: في هذا الوضع، فقط المطورين والمسؤولين يمكنهم استخدام التطبيق
- 🌍 **وضع Live**: في هذا الوضع، أي مستخدم يمكنه استخدام التطبيق (بعد الموافقة على الصلاحيات)

---

## 📘 المرحلة 2: الحصول على Page Access Token

### فهم أنواع التوكنات (مهم جداً!)

قبل البدء، يجب أن تفهم الفرق بين أنواع التوكنات:

| النوع | الصلاحية | الاستخدام | كيف تحصل عليه |
|-------|----------|-----------|---------------|
| **Short-Lived User Token** | ساعة واحدة | اختبار سريع | Graph API Explorer |
| **Long-Lived User Token** | 60 يوم | تطبيقات ويب | تمديد Short-Lived |
| **Page Access Token** | **لا ينتهي** ✨ | **النشر على الصفحات** | **تحويل Long-Lived** |

⚠️ **مهم جداً**: يجب أن تحصل على **Page Access Token الدائم** (لا ينتهي). إذا استخدمت User Token، سيتوقف النشر بعد 60 يوم!

### الخطوة 2.1: إعداد Facebook Login

1. **من القائمة اليسرى**: اضغط **"Facebook Login for Business"** → **"Settings"**

2. **في قسم "Configuration"**:
   ```
   Configuration
   ─────────────────────────────────────
   Client OAuth Settings
   
   Valid OAuth Redirect URIs:
   [أضف URL التطبيق الخاص بك - اختياري للتطوير]
   
   ─────────────────────────────────────
   App ID: 123456789 (انسخه)
   App Secret: [Show] (انسخه)
   ```

3. **انسخ القيم التالية** (ستحتاجها لاحقاً):
   - **App ID** (رقم مثل: `123456789`)
   - **App Secret** (نص طويل مثل: `abc123def456...`)
   
   💡 **احفظهم في مكان آمن** (مثل Password Manager)

### الخطوة 2.2: الحصول على Short-Lived Token (مؤقت)

#### الطريقة 1: Graph API Explorer (الأسهل والأسرع)

1. **افتح Graph API Explorer**:
   - الرابط: https://developers.facebook.com/tools/explorer/
   - ستظهر واجهة مثل هذه:
   ```
   ┌─────────────────────────────────────────────────────────┐
   │ Graph API Explorer                                      │
   ├─────────────────────────────────────────────────────────┤
   │                                                         │
   │ Application: [عقارات السويداء ▼]                       │
   │ User or Page: [Page ▼]                                 │
   │ Page: [عقارات السويداء ▼]                              │
   │                                                         │
   │ GET /v25.0/ [                    ] [Submit]            │
   │                                                         │
   │ Permissions:                                            │
   │ [ ] email                                               │
   │ [ ] public_profile                                      │
   │ [+ Add a Permission]                                   │
   │                                                         │
   │ [Generate Access Token]                                │
   │                                                         │
   └─────────────────────────────────────────────────────────┘
   ```

2. **اضبط الإعدادات**:
   - **Application**: اختر `عقارات السويداء` (التطبيق اللي أنشأته)
   - **User or Page**: اختر `Page` (وليس User!)
   - **Page**: اختر صفحتك `عقارات السويداء`

3. **أضف الصلاحيات (Permissions)**:
   - اضغط **"+ Add a Permission"**
   - أضف الصلاحيات التالية (واحدة تلو الأخرى):
     ```
     ✅ pages_read_engagement     (قراءة التفاعل)
     ✅ pages_manage_posts        (إدارة المنشورات)
     ✅ pages_show_list           (عرض قائمة الصفحات)
     ✅ pages_read_user_content   (قراءة محتوى المستخدم)
     ✅ instagram_basic           (قراءة أساسيات إنستغرام)
     ✅ instagram_content_publish (نشر محتوى إنستغرام)
     ```

4. **اضغط "Generate Access Token"**:
   - ستظهر نافذة لتسجيل الدخول
   - **سجّل الدخول** بنفس حساب الفيسبوك
   - **وافق على الصلاحيات** المطلوبة
   - **اختر الصفحة** اللي تريد النشر عليها

5. **انسخ التوكن**:
   - ستظهر خانة **"Access Token"** في الأعلى
   - التوكن يبدأ بـ `EAAB...` وطويل جداً
   - **انسخه كاملاً** (لا تقطعه!)

6. **تحقق من التوكن**:
   - اضغط على أيقونة 🔍 بجانب التوكن
   - ستظهر معلومات التوكن:
   ```
   Access Token Info
   ─────────────────────────────────────
   App ID: 123456789
   Type: User
   Expires: 1 hour from now ⚠️
   Scopes: pages_read_engagement, pages_manage_posts, ...
   ```
   - ⚠️ **انتبه**: Type = **User** (ليس Page!) و Expires = **1 hour**
   - هذا توكن مؤقت فقط - سنحوله إلى Page Token دائم

### الخطوة 2.3: تحويله إلى Long-Lived Token (60 يوم)

1. **افتح Access Token Debugger**:
   - الرابط: https://developers.facebook.com/tools/debug/accesstoken/

2. **الصق التوكن القصير** (من الخطوة السابقة)

3. **اضغط "Debug"**:
   ```
   Access Token Info
   ─────────────────────────────────────
   App ID: 123456789
   Type: User
   Expires: 1 hour from now
   Scopes: pages_read_engagement, pages_manage_posts, ...
   
   [Extend Access Token] ← اضغط هنا
   ```

4. **اضغط "Extend Access Token"**:
   - ستظهر صفحة جديدة مع توكن جديد
   - **Expires**: `60 days from now` ✅

5. **انسخ التوكن الجديد** (Long-Lived Token)

### الخطوة 2.4: تحويله إلى Page Access Token دائم ✨

⚠️ **هذه الخطوة الأهم**: نحول Long-Lived User Token إلى **Page Access Token دائم** (لا ينتهي)

#### الطريقة 1: باستخدام curl (الأسرع)

```bash
# المتغيرات المطلوبة:
# - {long-lived-user-token}: التوكن من الخطوة 2.3
# - {page-id}: ID صفحتك (ستحصل عليه في المرحلة 3، أو استخدم "me")

curl -i -X GET "https://graph.facebook.com/v25.0/me/accounts?access_token={long-lived-user-token}"
```

**النتيجة**:
```json
{
  "data": [
    {
      "access_token": "EAABsbCS1iHgBA...(هذا هو Page Access Token الدائم!)",
      "category": "Real Estate",
      "category_list": [
        {
          "id": "192576880765924",
          "name": "Real Estate"
        }
      ],
      "name": "عقارات السويداء",
      "id": "123456789",
      "tasks": [
        "ANALYZE",
        "ADVERTISE",
        "MODERATE",
        "CREATE_CONTENT",
        "MANAGE"
      ]
    }
  ]
}
```

✅ **انسخ `access_token`** → هذا هو `META_PAGE_ACCESS_TOKEN` الدائم!

#### الطريقة 2: باستخدام Graph API Explorer (بدون curl)

1. **افتح Graph API Explorer**: https://developers.facebook.com/tools/explorer/

2. **اضبط الإعدادات**:
   - **Application**: `عقارات السويداء`
   - **User or Page**: `User` (هذه المرة User وليس Page!)
   - **Access Token**: الصق الـ Long-Lived Token من الخطوة 2.3

3. **في حقل الاستعلام**:
   ```
   me/accounts
   ```

4. **اضغط "Submit"**

5. **ستظهر النتيجة** (نفس النتيجة أعلاه)

6. **انسخ `access_token`** من النتيجة

### الخطوة 2.5: التحقق من أن التوكن دائم

1. **افتح Access Token Debugger** مرة أخرى:
   - https://developers.facebook.com/tools/debug/accesstoken/

2. **الصق Page Access Token** (من الخطوة 2.4)

3. **اضغط "Debug"**

4. **تحقق من المعلومات**:
   ```
   Access Token Info
   ─────────────────────────────────────
   App ID: 123456789
   Type: Page ✅ (وليس User!)
   Expires: Never ✅ (لا ينتهي!)
   Scopes: pages_read_engagement, pages_manage_posts, ...
   Profile ID: 123456789 (هذا هو Page ID)
   ```

✅ **إذا رأيت**:
- Type = **Page**
- Expires = **Never**

**مبروك!** عندك Page Access Token دائم! 🎉

### ✍️ ملاحظات المرحلة 2

- ⚠️ **لا تشارك التوكن مع أحد**: التوكن يعطي صلاحية كاملة للنشر على صفحتك
- 💾 **احفظ التوكن في مكان آمن**: Password Manager أو ملف مشفر
- 🔄 **إذا تغيرت كلمة سر الفيسبوك**: التوكن سيُلغى تلقائياً، يجب إنشاء توكن جديد
- 🚫 **إذا ألغيت التطبيق**: التوكن سيُلغى، يجب إعادة إنشاء التطبيق
- 📝 **سجل التوكن في مكان آمن**: إذا فقدته، يجب إعادة كل الخطوات

---

## 📗 المرحلة 3: الحصول على Page ID

### الطريقة 1: من الصفحة مباشرة

1. افتح صفحتك على فيسبوك: https://facebook.com/عقارات-السويداء
2. اضغط **"About"** (حول)
3. ابحث عن **"Page ID"**
4. انسخ الرقم (مثل: `123456789`)

### الطريقة 2: من Graph API Explorer

1. افتح: https://developers.facebook.com/tools/explorer/
2. في حقل الاستعلام، اكتب:
   ```
   me/accounts
   ```
3. اضغط **"Submit"**
4. ستظهر النتيجة:
   ```json
   {
     "data": [
       {
         "access_token": "EAAB...",
         "category": "Real Estate",
         "category_list": [...],
         "name": "عقارات السويداء",
         "id": "123456789"  // ← هذا هو Page ID
       }
     ]
   }
   ```

✅ **انسخ `id`** → هذا هو `META_FACEBOOK_PAGE_ID`

---

## 📸 المرحلة 4: الحصول على Instagram Account ID

### المتطلبات التفصيلية

قبل البدء، تأكد من:
- ✅ حساب إنستغرام **مهني** (Professional Account) - ليس شخصي
- ✅ نوع الحساب: **Business** (وليس Creator)
- ✅ الحساب **مرتبط** بصفحة الفيسبوك المستهدفة
- ✅ عندك صلاحيات **أدمن** على صفحة الفيسبوك المرتبطة

### الخطوة 4.1: تحويل حساب إنستغرام إلى مهني (إذا كان شخصي)

⚠️ **إذا كان حسابك شخصي**، يجب تحويله إلى مهني أولاً:

1. **افتح تطبيق إنستغرام** على هاتفك

2. **اذهب إلى الملف الشخصي**:
   - اضغط على أيقونة الشخص في الأسفل

3. **افتح الإعدادات**:
   - اضغط على ☰ (ثلاث خطوط) في الأعلى
   - اختر **"Settings"**

4. **اذهب إلى Account**:
   - اضغط **"Account"**

5. **حوّل إلى حساب مهني**:
   - اضغط **"Switch to Professional Account"**
   - ستظهر شاشة ترحيب → اضغط **"Continue"**

6. **اختر الفئة (Category)**:
   ```
   What best describes you?
   
   [Real Estate     ] ← اختر هذه
   [Entrepreneur    ]
   [Business        ]
   [...]
   ```
   - اختر **"Real Estate"** (عقارات)
   - اضغط **"Done"**

7. **اختر نوع الحساب**:
   ```
   You're creating a professional account
   
   ○ Creator (للمؤثرين والفنانين)
   ● Business (للشركات والمتاجر) ← اختر هذا
   ```
   - اختر **"Business"**
   - اضغط **"Next"**

8. **أضف معلومات الاتصال** (اختياري):
   ```
   Review your contact information
   
   Email: your-email@example.com
   Phone: +963 XXX XXX XXX
   Address: السويداء، سوريا
   ```
   - يمكنك تعديلها أو تركها كما هي
   - اضغط **"Next"**

9. **اربط بصفحة الفيسبوك**:
   ```
   Connect to Facebook
   
   Connect to [عقارات السويداء] ← صفحتك
   
   [Connect to Facebook] ← اضغط هنا
   ```
   - اضغط **"Connect to Facebook"**
   - سجّل الدخول بحساب الفيسبوك
   - اختر الصفحة المستهدفة
   - اضغط **"Done"**

10. **التحقق**:
    - ارجع إلى **Profile**
    - يجب أن ترى **"Professional Dashboard"** تحت البايو
    - اضغط عليها → يجب أن ترى **"Account Type: Business"**

### الخطوة 4.2: التحقق من الارتباط بصفحة الفيسبوك

1. **افتح إنستغرام** → **Settings** → **Account** → **Linked Accounts**

2. **تحقق من Facebook**:
   ```
   Linked Accounts
   ─────────────────────────────────────
   ✅ Facebook
      Connected to: عقارات السويداء
   
   ○ Twitter
   ○ Tumblr
   ```

3. **إذا لم يكن مرتبطاً**:
   - اضغط **"Facebook"**
   - سجّل الدخول بحساب الفيسبوك
   - اختر الصفحة المستهدفة
   - اضغط **"Link Account"**

### الخطوة 4.3: الحصول على Instagram Account ID

#### الطريقة 1: من Graph API Explorer (الأسهل)

1. **افتح Graph API Explorer**:
   - https://developers.facebook.com/tools/explorer/

2. **اضبط الإعدادات**:
   - **Application**: `عقارات السويداء`
   - **User or Page**: `User`
   - **Access Token**: الصق الـ Long-Lived Token من المرحلة 2

3. **في حقل الاستعلام**:
   ```
   {page-id}?fields=instagram_business_account
   ```
   - استبدل `{page-id}` بـ Page ID من المرحلة 3
   - مثال: `123456789?fields=instagram_business_account`

4. **اضغط "Submit"**

5. **ستظهر النتيجة**:
   ```json
   {
     "instagram_business_account": {
       "id": "17841405123456789"  // ← هذا هو Instagram Account ID!
     },
     "id": "123456789"
   }
   ```

✅ **انسخ `instagram_business_account.id`** → هذا هو `META_INSTAGRAM_ACCOUNT_ID`

#### الطريقة 2: من Instagram Professional Dashboard (بدون API)

1. **افتح إنستغرام** على هاتفك

2. **اذهب إلى الملف الشخصي**

3. **اضغط "Professional Dashboard"**

4. **اضغط "Business Tools"**

5. **اضغط "Facebook"**

6. **ستظهر صفحة الفيسبوك المرتبطة**

7. **اضغط على اسم الصفحة**

8. **في المتصفح، ستفتح صفحة الفيسبوك**

9. **انظر إلى URL**:
   ```
   https://www.facebook.com/عقارات-السويداء-123456789
                                            ^^^^^^^^^
                                            هذا هو Page ID
   ```

⚠️ **هذه الطريقة تعطي Page ID فقط، ليس Instagram Account ID**

للحصول على Instagram Account ID، استخدم الطريقة 1 أو:

#### الطريقة 3: من Instagram Graph API

1. **افتح Graph API Explorer**

2. **استخدم Page Access Token** (من المرحلة 2.4)

3. **في حقل الاستعلام**:
   ```
   {page-id}?fields=instagram_business_account{id,username}
   ```

4. **اضغط "Submit"**

5. **النتيجة**:
   ```json
   {
     "instagram_business_account": {
       "id": "17841405123456789",
       "username": "aqarat_alsuwayda"
     },
     "id": "123456789"
   }
   ```

### ✍️ ملاحظات المرحلة 4

- ⚠️ **حساب Creator لا يعمل**: يجب أن يكون **Business** وليس Creator
- 🔗 **الارتباط ضروري**: بدون ربط إنستغرام بفيسبوك، لن يعمل النشر
- 📱 **التطبيق المحمول أسهل**: تحويل الحساب إلى مهني أسهل من الهاتف
- 🔄 **يمكنك التراجع**: يمكنك العودة إلى حساب شخصي في أي وقت (لكن ستفقد الميزات)

---

## 🔐 المرحلة 5: ضبط التوكنات في Supabase

### الخطوة 5.1: الدخول إلى Supabase Dashboard

1. افتح: https://supabase.com/dashboard
2. اختر المشروع: `vsgkgnjtebjxyqwpuopz`

### الخطوة 5.2: إضافة Secrets

1. من القائمة اليسرى: **"Edge Functions"** → **"Secrets"**
2. اضغط **"Add Secret"** وأضف الثلاثة التاليين:

#### Secret 1: META_PAGE_ACCESS_TOKEN
```
Name: META_PAGE_ACCESS_TOKEN
Value: EAABsbCS1iHgBA...(التوكن من المرحلة 2)
```

#### Secret 2: META_FACEBOOK_PAGE_ID
```
Name: META_FACEBOOK_PAGE_ID
Value: 123456789 (من المرحلة 3)
```

#### Secret 3: META_INSTAGRAM_ACCOUNT_ID
```
Name: META_INSTAGRAM_ACCOUNT_ID
Value: 17841405...(من المرحلة 4)
```

### الخطوة 5.3: إعادة نشر Edge Functions

بعد إضافة الـ Secrets، يجب إعادة نشر الـ Edge Functions:

```bash
cd /path/to/sweeda-real-estate-office-elc

# إعادة نشر admin-offers
supabase functions deploy admin-offers \
  --no-verify-jwt \
  --project-ref vsgkgnjtebjxyqwpuopz

# إعادة نشر publish-to-social
supabase functions deploy publish-to-social \
  --no-verify-jwt \
  --project-ref vsgkgnjtebjxyqwpuopz
```

---

## 🧪 المرحلة 6: اختبار النشر

### الخطوة 6.1: إضافة عرض تجريبي

1. سجّل الدخول كمستخدم عادي (`مستخدم2عادي`)
2. أضف عرض جديد:
   - العنوان: `شقة تجريبية للنشر`
   - السعر: `100000`
   - الصور: ارفع صورة واحدة على الأقل
   - ✅ فعّل checkbox **"النشر على فيسبوك + إنستغرام"**
3. احفظ العرض

### الخطوة 6.2: مراجعة العرض

1. سجّل الدخول كمدير (`hady`)
2. اذهب إلى **مراجعة العروض**
3. ستجد العرض مع الشارة الزرقاء:
   ```
   📣 سيُنشر تلقائياً على فيسبوك + إنستغرام (بعد الموافقة)
   ```
4. اضغط **"قبول"**

### الخطوة 6.3: التحقق من النتيجة

#### ✅ إذا نجح:
```
✅ تم نشر العرض داخلياً • 📣 ✅ تم النشر تلقائياً على فيسبوك وإنستغرام
```

**تحقق من:**
- صفحة الفيسبوك: يجب أن يظهر المنشور
- حساب الإنستغرام: يجب أن يظهر المنشور

#### ❌ إذا فشل:

| الخطأ | السبب | الحل |
|-------|-------|------|
| `META_SECRETS_NOT_CONFIGURED` | التوكنات غير مضبوطة | راجع المرحلة 5 |
| `PUBLIC_IMAGE_REQUIRED` | العرض بدون صور | أضف صورة واحدة على الأقل |
| `OFFER_NOT_APPROVED` | العرض غير منشور | تأكد أن `sts=2` و `i_pub=1` |
| `Invalid OAuth access token` | التوكن منتهي أو خاطئ | أعد الحصول على توكن جديد |
| `Permission error` | صلاحيات ناقصة | راجع الخطوة 2.2 (Permissions) |

---

## 🔄 المرحلة 7: النشر اليدوي (للعروض القديمة)

إذا كان عندك عروض في قائمة "جاهزة للنشر":

1. اذهب إلى **مراجعة العروض**
2. ستجد القسم: **📣 جاهزة للنشر على فيسبوك + إنستغرام**
3. لكل عرض:
   - اضغط **"نشر الآن"** → ينشر عرض واحد
   - أو اضغط **"نشر الكل"** → ينشر كل العروض الجاهزة

---

## ⚙️ الإعدادات الإضافية (اختياري)

### تعطيل النشر التلقائي

إذا تريد أن يبقى النشر يدوي فقط:

1. اذهب إلى **الإعدادات** (`/admin/config`)
2. ابحث عن: **"النشر التلقائي فور قبول العرض"**
3. عطّل الخيار
4. احفظ

**النتيجة:**
- العروض تُنشر داخلياً فقط
- تبقى في قائمة "جاهزة للنشر"
- المدير ينشرها يدوياً عندما يريد

### تعديل قالب النص

القالب الافتراضي:
```
🏠 عرض جديد على عقارات السويداء

📍 [العنوان]
[عقار/سيارة] [للبيع/للإيجار]
💰 السعر: ...
📌 المنطقة: ...

[الوصف]

للتفاصيل والحجز:
📱 تطبيق عقارات السويداء
#عقارات_السويداء #عروض_عقارية
```

**لتعديله:**
- القالب يُولَّد تلقائياً في `add_offer_screen.dart` → `_generateSocialPostText()`
- يمكنك تعديل النص هناك

---

## 🎯 ملخص التوكنات المطلوبة

| التوكن | الوصف | مثال |
|--------|-------|------|
| `META_PAGE_ACCESS_TOKEN` | توكن الوصول لصفحة الفيسبوك | `EAABsbCS1iHgBA...` |
| `META_FACEBOOK_PAGE_ID` | ID صفحة الفيسبوك | `123456789` |
| `META_INSTAGRAM_ACCOUNT_ID` | ID حساب الإنستغرام المهني | `17841405...` |

---

## ⚠️ ملاحظات مهمة

### 1. صلاحية التوكنات
- **Page Access Token الدائم:** لا ينتهي (طالما لم تغير كلمة السر)
- **User Access Token:** ينتهي بعد 60 يوم
- **Short-lived Token:** ينتهي بعد ساعة

**الحل:** استخدم Page Access Token الدائم (المرحلة 2.3)

### 2. الصور
- فيسبوك: يقبل أي صورة (حتى لو واحدة)
- إنستغرام: **يجب** أن يكون عندك صورة واحدة على الأقل
- الحد الأقصى: 10 صور (Carousel)

### 3. الصلاحيات
- يجب أن تكون **أدمن** على صفحة الفيسبوك
- يجب أن يكون حساب الإنستغرام **مهني** (Professional)
- يجب أن يكون حساب الإنستغرام **مرتباً** بصفحة الفيسبوك

### 4. الحدود (Rate Limits)
- فيسبوك: 200 منشور/ساعة
- إنستغرام: 25 منشور/24 ساعة
- **لا تقلق:** التطبيق يحمي من التكرار عبر `social_publications`

---

## 🆘 حل المشاكل التفصيلي

### المشكلة 1: "Invalid OAuth access token"

**الأعراض**:
```
❌ فشل النشر التلقائي: Invalid OAuth access token
```

**الأسباب المحتملة**:

| السبب | الاحتمال | الحل |
|-------|----------|------|
| التوكن منتهي | عالي | أنشئ توكن جديد (المرحلة 2) |
| التوكن خاطئ (نسخ غير كامل) | متوسط | أعد نسخ التوكن كاملاً |
| استخدمت User Token بدل Page Token | عالي | تأكد من Type = Page في Debugger |
| تغيرت كلمة سر الفيسبوك | متوسط | أنشئ توكن جديد |
| التطبيق تم حذفه أو إيقافه | منخفض | تحقق من حالة التطبيق |

**الحل خطوة بخطوة**:

1. **تحقق من التوكن الحالي**:
   ```bash
   # في Supabase Dashboard → Edge Functions → Secrets
   # انسخ قيمة META_PAGE_ACCESS_TOKEN
   ```

2. **افحص التوكن في Debugger**:
   - افتح: https://developers.facebook.com/tools/debug/accesstoken/
   - الصق التوكن
   - اضغط "Debug"
   - تحقق من:
     ```
     Expires: [تاريخ] ⚠️ إذا منتهي → أنشئ جديد
     Type: User ⚠️ إذا User → حوّله إلى Page
     ```

3. **إذا التوكن منتهي**:
   - أعد المرحلة 2 كاملة (من البداية)
   - احصل على Page Access Token جديد
   - حدّث الـ Secret في Supabase

4. **إذا التوكن User وليس Page**:
   - أعد المرحلة 2.4 (تحويله إلى Page Token)
   - حدّث الـ Secret في Supabase

5. **بعد التحديث**:
   ```bash
   # أعد نشر Edge Functions
   supabase functions deploy admin-offers --no-verify-jwt --project-ref vsgkgnjtebjxyqwpuopz
   supabase functions deploy publish-to-social --no-verify-jwt --project-ref vsgkgnjtebjxyqwpuopz
   ```

---

### المشكلة 2: "Permission error" أو "Insufficient permission"

**الأعراض**:
```
❌ فشل النشر التلقائي: Permission error / Insufficient permission
```

**السبب**: التوكن لا يحتوي على الصلاحيات الكافية

**الحل**:

1. **تحقق من الصلاحيات الحالية**:
   - افتح Access Token Debugger
   - الصق التوكن
   - انظر إلى **"Scopes"** (الصلاحيات)

2. **الصلاحيات المطلوبة**:
   ```
   ✅ pages_read_engagement
   ✅ pages_manage_posts
   ✅ pages_show_list
   ✅ pages_read_user_content
   ✅ instagram_basic
   ✅ instagram_content_publish
   ```

3. **إذا الصلاحيات ناقصة**:
   - افتح Graph API Explorer
   - اضغط **"+ Add a Permission"**
   - أضف الصلاحيات الناقصة
   - اضغط **"Generate Access Token"**
   - وافق على الصلاحيات الجديدة
   - أعد المرحلة 2.3 و 2.4 (تمديد + تحويل إلى Page Token)

4. **تحقق مرة أخرى**:
   - افتح Debugger
   - تأكد أن كل الصلاحيات موجودة

---

### المشكلة 3: "Instagram account not linked"

**الأعراض**:
```
❌ فشل النشر التلقائي: Instagram account not linked to Facebook Page
```

**السبب**: حساب الإنستغرام غير مرتباً بصفحة الفيسبوك

**الحل**:

1. **تحقق من الارتباط**:
   - افتح إنستغرام → Settings → Account → Linked Accounts
   - يجب أن ترى Facebook مع اسم صفحتك

2. **إذا غير مرتبط**:
   - اضغط **"Facebook"**
   - سجّل الدخول بحساب الفيسبوك
   - اختر الصفحة المستهدفة
   - اضغط **"Link Account"**

3. **تحقق من نوع الصفحة**:
   - افتح صفحة الفيسبوك
   - Settings → Page Info
   - **Category**: يجب أن تكون **"Real Estate"** أو مشابه
   - إذا كانت **"Personal Blog"** أو **"Community"**، غيّرها إلى **"Real Estate"**

4. **تحقق من صلاحيات الصفحة**:
   - افتح صفحة الفيسبوك
   - Settings → Page Access
   - تأكد أن حسابك موجود مع صلاحيات **"Full Control"**

---

### المشكلة 4: "No Instagram Business Account found"

**الأعراض**:
```
❌ فشل النشر التلقائي: No Instagram Business Account found
```

**السبب**: حساب الإنستغرام شخصي (ليس مهني) أو من نوع Creator

**الحل**:

1. **تحقق من نوع الحساب**:
   - افتح إنستغرام → Profile → Professional Dashboard
   - إذا لم تجد "Professional Dashboard" → الحساب شخصي
   - إذا وجدت → تحقق من النوع (Business أو Creator)

2. **إذا الحساب شخصي**:
   - اتبع **المرحلة 4.1** (تحويل إلى مهني)
   - اختر **Business** (وليس Creator)

3. **إذا الحساب Creator**:
   - افتح Settings → Account
   - اضغط **"Switch Account Type"**
   - اختر **"Switch to Business Account"**

4. **تحقق من النتيجة**:
   ```bash
   # في Graph API Explorer
   {page-id}?fields=instagram_business_account
   
   # النتيجة يجب أن تكون:
   {
     "instagram_business_account": {
       "id": "17841405..."
     }
   }
   ```

---

### المشكلة 5: "META_SECRETS_NOT_CONFIGURED"

**الأعراض**:
```
⚠️ التوكنات غير مضبوطة، بقي في قائمة الجاهزة
```

**السبب**: الـ Secrets غير مضبوطة في Supabase

**الحل**:

1. **تحقق من وجود الـ Secrets**:
   - افتح Supabase Dashboard
   - Edge Functions → Secrets
   - يجب أن ترى:
     ```
     ✅ META_PAGE_ACCESS_TOKEN
     ✅ META_FACEBOOK_PAGE_ID
     ✅ META_INSTAGRAM_ACCOUNT_ID
     ```

2. **إذا غير موجودة**:
   - اتبع **المرحلة 5** (ضبط التوكنات في Supabase)

3. **إذا موجودة لكن فارغة**:
   - اضغط على كل Secret
   - اضغط **"Edit"**
   - الصق القيمة الصحيحة
   - اضغط **"Save"**

4. **أعد نشر Edge Functions**:
   ```bash
   supabase functions deploy admin-offers --no-verify-jwt --project-ref vsgkgnjtebjxyqwpuopz
   supabase functions deploy publish-to-social --no-verify-jwt --project-ref vsgkgnjtebjxyqwpuopz
   ```

---

### المشكلة 6: "PUBLIC_IMAGE_REQUIRED"

**الأعراض**:
```
⚠️ لا توجد صورة عامة للنشر، بقي في قائمة الجاهزة
```

**السبب**: العرض لا يحتوي على صور عامة (https://)

**الحل**:

1. **تحقق من صور العرض**:
   - افتح العرض في التطبيق
   - تأكد أن عندك صورة واحدة على الأقل

2. **تحقق من نوع الصور**:
   - الصور يجب أن تكون **عامة** (https://...)
   - ليست محلية (file://...) أو خاصة

3. **إذا الصور خاصة**:
   - افتح Supabase Dashboard → Storage
   - تحقق من صلاحيات Bucket
   - تأكد أن الصور **public** (وليس private)

4. **أضف صورة جديدة**:
   - افتح العرض في التطبيق
   - اضغط **"تعديل"**
   - أضف صورة جديدة
   - احفظ

---

### المشكلة 7: "OFFER_NOT_APPROVED"

**الأعراض**:
```
❌ فشل النشر التلقائي: OFFER_NOT_APPROVED
```

**السبب**: العرض غير منشور داخلياً

**الحل**:

1. **تحقق من حالة العرض**:
   ```sql
   SELECT id, sts, i_pub, i_soc, soc_pub 
   FROM offers 
   WHERE id = 'offer-id-here';
   ```

2. **القيم المطلوبة**:
   ```
   sts = 2    (منشور)
   i_pub = 1  (مرئي للزوار)
   i_soc = 1  (النشر الاجتماعي مفعّل)
   ```

3. **إذا القيم خاطئة**:
   - افتح التطبيق كمدير
   - اذهب إلى **مراجعة العروض**
   - اضغط **"قبول"** على العرض

---

## 🔄 تجديد التوكنات

### متى تحتاج تجديد التوكن؟

| النوع | الصلاحية | متى يجدد؟ |
|-------|----------|-----------|
| Short-Lived User Token | ساعة | لا يجدد (أنشئ جديد) |
| Long-Lived User Token | 60 يوم | قبل أسبوع من الانتهاء |
| **Page Access Token الدائم** | **لا ينتهي** | **فقط إذا تغيرت كلمة السر** |

### كيفية التحقق من صلاحية التوكن

1. **افتح Access Token Debugger**:
   - https://developers.facebook.com/tools/debug/accesstoken/

2. **الصق التوكن**

3. **اضغط "Debug"**

4. **انظر إلى "Expires"**:
   ```
   Expires: Never ← لا يحتاج تجديد ✅
   Expires: 2026-10-05 ← يحتاج تجديد قبل هذا التاريخ ⚠️
   Expires: 1 hour from now ← منتهي تقريباً ❌
   ```

### كيفية تجديد التوكن (إذا كان ينتهي)

1. **أعد المرحلة 2 كاملة**:
   - احصل على Short-Lived Token جديد
   - حوّله إلى Long-Lived Token
   - حوّله إلى Page Access Token دائم

2. **حدّث الـ Secret في Supabase**:
   - افتح Supabase Dashboard → Edge Functions → Secrets
   - اضغط على `META_PAGE_ACCESS_TOKEN`
   - اضغط **"Edit"**
   - الصق التوكن الجديد
   - اضغط **"Save"**

3. **أعد نشر Edge Functions**:
   ```bash
   supabase functions deploy admin-offers --no-verify-jwt --project-ref vsgkgnjtebjxyqwpuopz
   ```

---

## 🔐 الأمان وأفضل الممارسات

### 1. حماية التوكنات

⚠️ **التوكنات حساسة جداً** - تعامل معها مثل كلمات السر:

| ✅ افعل | ❌ لا تفعل |
|---------|-----------|
| احفظها في Password Manager | لا تشاركها مع أحد |
| استخدم Supabase Secrets | لا تضعها في الكود |
| حدّثها بانتظام | لا ترفعها على GitHub |
| استخدم Page Token دائم | لا تستخدم User Token |

### 2. أفضل الممارسات

#### عند إنشاء التوكنات

- ✅ **استخدم حساب مخصص** (ليس حسابك الشخصي) إذا أمكن
- ✅ **اطلب أقل صلاحيات ممكنة** (فقط اللي تحتاجها)
- ✅ **احفظ التوكن في مكان آمن** (Password Manager)
- ✅ **سجل تاريخ إنشاء التوكن** (لمتابعة الصلاحية)

#### عند حفظ التوكنات

- ✅ **استخدم Supabase Secrets** (مشفر وآمن)
- ✅ **لا تكتبها في ملفات نصية** (غير آمن)
- ✅ **لا تضعها في `.env`** (قد تُرفع بالخطأ)
- ✅ **لا تشاركها في Slack/Email** (غير آمن)

#### عند استخدام التوكنات

- ✅ **استخدم Page Token دائم** (لا ينتهي)
- ✅ **تحقق من الصلاحية بانتظام** (كل 3 أشهر)
- ✅ **راقب الاستخدام** (من Supabase Logs)
- ✅ **حدّث التوكن إذا تغيرت كلمة السر**

### 3. ماذا تفعل إذا تسرب التوكن؟

⚠️ **إذا شكيت أن التوكن تسرب** (مثلاً رفعته على GitHub بالخطأ):

1. **ألغِ التوكن فوراً**:
   - افتح Facebook → Settings → Apps and Websites
   - ابحث عن تطبيقك
   - اضغط **"Remove"**

2. **أنشئ توكن جديد**:
   - أعد المرحلة 2 كاملة

3. **حدّث الـ Secret في Supabase**:
   - استبدل التوكن القديم بالتوكن الجديد

4. **تحقق من السجلات**:
   - افتح Supabase Dashboard → Edge Functions → Logs
   - ابحث عن نشاط مشبوه

5. **راجع المنشورات**:
   - افتح صفحة الفيسبوك
   - تحقق من المنشورات الأخيرة
   - احذف أي منشور مشبوه

---

## 📊 مراقبة النشر (Logs)

### كيفية مراقبة عمليات النشر

#### 1. من Supabase Dashboard

1. **افتح Supabase Dashboard**

2. **اذهب إلى Edge Functions → Logs**

3. **فلتر حسب الدالة**:
   ```
   Function: publish-to-social
   Status: All
   Time Range: Last 24 hours
   ```

4. **ستظهر السجلات**:
   ```
   Timestamp              Status  Duration  Details
   ─────────────────────────────────────────────────
   2026-08-05 10:30:15   ✅ 200   1.2s     Published to Facebook + Instagram
   2026-08-05 10:25:10   ❌ 400   0.8s     META_SECRETS_NOT_CONFIGURED
   2026-08-05 10:20:05   ✅ 200   1.5s     Already published (skipped)
   ```

5. **اضغط على أي سجل** لرؤية التفاصيل:
   ```
   Request:
   {
     "action": "publish",
     "offer_id": "abc123"
   }
   
   Response:
   {
     "success": true,
     "facebook": { "success": true, "postId": "123_456" },
     "instagram": { "success": true, "postId": "789" }
   }
   ```

#### 2. من قاعدة البيانات

```sql
-- تحقق من حالة النشر لكل عرض
SELECT 
  id,
  ttl AS title,
  i_soc AS social_enabled,
  soc_pub AS publish_status,
  CASE 
    WHEN soc_pub = 0 THEN 'لم يُفعّل'
    WHEN soc_pub = 1 THEN 'جاهز للنشر'
    WHEN soc_pub = 2 THEN 'تم النشر'
  END AS status_text
FROM offers
WHERE i_soc = 1
ORDER BY ts_crt DESC;
```

**النتيجة**:
```
id       | title              | social_enabled | publish_status | status_text
─────────────────────────────────────────────────────────────────────────────
abc123   | شقة فاخرة للبيع    | 1              | 2              | تم النشر
def456   | سيارة رائعة        | 1              | 1              | جاهز للنشر
ghi789   | أرض زراعية         | 1              | 0              | لم يُفعّل
```

#### 3. من جدول social_publications

```sql
-- تحقق من تفاصيل النشر لكل منصة
SELECT 
  offer_id,
  platform,
  status,
  post_id,
  error,
  attempt_count,
  ts_crt,
  ts_upd
FROM social_publications
ORDER BY ts_crt DESC
LIMIT 10;
```

**النتيجة**:
```
offer_id | platform  | status    | post_id   | error | attempt_count | ts_crt
──────────────────────────────────────────────────────────────────────────────────
abc123   | facebook  | published | 123_456   | NULL  | 1             | 2026-08-05
abc123   | instagram | published | 789       | NULL  | 1             | 2026-08-05
def456   | facebook  | pending   | NULL      | NULL  | 0             | 2026-08-05
```

---

## 🚦 حدود API (Rate Limits)

### حدود فيسبوك

| العملية | الحد | الفترة |
|---------|------|--------|
| النشر على الصفحة | 200 منشور | في الساعة |
| قراءة التفاعل | 200 طلب | في الساعة |
| رفع الصور | 50 صورة | في الساعة |

### حدود إنستغرام

| العملية | الحد | الفترة |
|---------|------|--------|
| النشر (صور/فيديو) | 25 منشور | في 24 ساعة |
| Carousel (ألبوم) | 25 منشور | في 24 ساعة |
| قراءة الإحصائيات | 200 طلب | في الساعة |

### كيف يتعامل التطبيق مع الحدود؟

✅ **الحماية المدمجة**:
- يتحقق من عدم التكرار عبر `social_publications`
- ينتظر بين المنشورات (لا ينشر فوراً)
- يسجل المحاولات الفاشلة ويعيد المحاولة لاحقاً

✅ **ماذا يحدث إذا وصلت للحد؟**:
```
❌ فشل النشر: Rate limit exceeded
⏰ سيعاد المحاولة بعد: 1 ساعة
```

✅ **كيف تتجنب الوصول للحد؟**:
- لا تنشر أكثر من 20 عرض في الساعة (فيسبوك)
- لا تنشر أكثر من 20 عرض في اليوم (إنستغرام)
- استخدم **النشر اليدوي** للتحكم في التوقيت

---

## ❓ أسئلة شائعة (FAQ)

### س1: هل يمكنني استخدام حساب إنستغرام شخصي؟

**لا**، يجب أن يكون الحساب **مهني** (Professional) ومن نوع **Business**. الحسابات الشخصية لا تدعم Instagram Graph API.

---

### س2: هل يمكنني النشر على أكثر من صفحة؟

**نعم**، لكن تحتاج:
- Page Access Token لكل صفحة
- ضبط الـ Secrets لكل صفحة (أو استخدام متغيرات مختلفة)

**الحل الأسهل**: استخدم صفحة واحدة فقط.

---

### س3: ماذا يحدث إذا حذفت منشور من فيسبوك؟

**لا شيء**، المنشور سيُحذف من فيسبوك فقط. لكن:
- `soc_pub` سيبقى = 2 (تم النشر)
- إذا أردت إعادة النشر، يجب إعادة تعيين `soc_pub = 1`

```sql
UPDATE offers SET soc_pub = 1 WHERE id = 'offer-id-here';
```

---

### س4: هل يمكنني تعديل المنشور بعد النشر؟

**لا مباشرة**، لكن يمكنك:
1. حذف المنشور من فيسبوك/إنستغرام
2. إعادة تعيين `soc_pub = 1`
3. إعادة النشر يدوياً

---

### س5: ماذا يحدث إذا غيّرت كلمة سر الفيسبوك؟

**التوكن سيُلغى تلقائياً**، ويجب:
1. إنشاء توكن جديد (المرحلة 2)
2. تحديث الـ Secret في Supabase
3. إعادة نشر Edge Functions

---

### س6: هل يمكنني استخدام التطبيق بدون إنستغرام؟

**نعم**، يمكنك:
- ضبط `META_PAGE_ACCESS_TOKEN` و `META_FACEBOOK_PAGE_ID` فقط
- ترك `META_INSTAGRAM_ACCOUNT_ID` فارغ
- النظام سينشر على فيسبوك فقط

---

### س7: ماذا يحدث إذا لم يكن عندك صور؟

- **فيسبوك**: يمكن النشر بدون صور (نص فقط)
- **إنستغرام**: **يجب** أن يكون عندك صورة واحدة على الأقل

**الحل**: أضف صورة واحدة على الأقل لكل عرض.

---

### س8: هل يمكنني تعديل قالب النص؟

**نعم**، القالب يُولَّد في `add_offer_screen.dart` → `_generateSocialPostText()`

**لتعديله**:
1. افتح الملف
2. عدّل النص كما تريد
3. احفظ وادفع التغييرات

---

### س9: ماذا يحدث إذا فشل النشر على إنستغرام لكن نجح على فيسبوك؟

النظام يسجل النتيجة لكل منصة على حدة:
```json
{
  "success": false,
  "facebook": { "success": true, "postId": "123_456" },
  "instagram": { "success": false, "error": "Rate limit exceeded" }
}
```

**الحل**: أعد المحاولة لاحقاً (النشر اليدوي).

---

### س10: هل يمكنني جدولة النشر؟

**لا مباشرة**، لكن يمكنك:
- تعطيل النشر التلقائي (من الإعدادات)
- استخدام **النشر اليدوي** في الوقت المناسب

---

## 📞 الدعم

إذا واجهت مشكلة لم تُحل في هذا الدليل:

1. **راجع قسم "حل المشاكل"** أعلاه
2. **تحقق من السجلات** في Supabase Dashboard → Edge Functions → Logs
3. **افحص التوكن** في Access Token Debugger
4. **تواصل معي** وسأساعدك

---

**الحالة:** ✅ جاهز للتنفيذ  
**التاريخ:** 2026-08-05  
**الإصدار:** 2.0 (مفصّل)  
**المؤلف:** نظام المساعدة الذكي

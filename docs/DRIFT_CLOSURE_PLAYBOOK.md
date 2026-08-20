# 🔁 دليل إقفال انحراف الريبو ↔ السيرفر (الدَين 5) — 2026-08-20

> الهدف: صورة واحدة موثوقة عن السيرفر الحي تُقارن ضد ملفات الريبو —
> فتظهر كل الفروقات (دوال، جداول، أعمدة، بوالصي) وتُقفل وحدة وحدة.
> بدون هذه الصورة، أي نشر مستقبلي يبقى معرّضاً لأخطاء الانحراف
> (مثل فشل `get_lawyer_appointments` 42P13 الذي وقع اليوم).

## ١) أوامر المالك (على جهاز الويندوز — مرة واحدة)

يشترط: Supabase CLI + Docker (كلاهما مثبّت سابقاً وموثق).

```
cd sweeda-real-estate-office-elc
supabase login
supabase link --project-ref vsgkgnjtebjxyqwpuopz
supabase db dump -f db_dump_2026_08_20.sql
```

ملاحظات:
- `supabase link` يسأل كلمة سر قاعدة البيانات (موجودة بلوحة Supabase → Settings → Database).
- إن تعذّر Docker: البديل الموثق سابقاً هو `supabase db query --linked -f <ملف>`.
- أرسل الملف الناتج للوكيل (أو ضعه بجذر المشروع).

## ٢) فحص الفروقات (الوكيل — بعد استلام الملف)

```bash
python3 scripts/compare_db_dump.py db_dump_2026_08_20.sql
```

النص يفحص **علامات الانحراف المعروفة** (التي اكتشفتها الجولات الأخيرة)
ويطبع لكل منها: موجود/غائب بالـ dump + المراجع الريبوية المقابلة —
وأي فرق يُسجَّل بقائمة «فروقات للإقفال» وتُنشأ منها ملفات migration
تصحيحية (توقيعات دوال، أعمدة، بوالصي) بموافقة المالك.

## ٣) علامات الفحص الحالية

| العلامة | ماذا تثبت |
|---|---|
| `get_lawyer_appointments` بتوقيع `sts/cnl_by/cnl_rsn` | دالّة المواعيد منشورة بالتوقيع الجديد |
| `rebook_legal_appointment_v2` | إعادة الموعد بعد الاعتذار حية |
| `LAWYER_INACTIVE_FOR_RENEWAL` داخل v3 | الثغرة 2 حية |
| `OPEN_CONSULTATION_EXISTS` داخل prepare | الثغرة 3 حية |
| عمود `waveform` على consultation_chats | موجة الصوت منشورة |
| عمود `doc_img_admin` على offers + جدول `offer_documents` | **حالة سند الملكية الحي** (مشتبه بانحراف — الريبو لا يحوي offer_documents) |
| بوالصي INSERT على `payment_proofs` = صفر | دين 1 مقفول حياً |
| `enqueue_consultation_notification_push` يستدعي process فوراً | push الفوري حي |

## ٤) ماذا بعد

- كل فرق مثبت يُقفل بملف migration جديد (أو يُوثَّق كقرار مقصود).
- `functions_dump.sql` و`setup.sql` يُحدَّثان من الـ dump بعد المطابقة،
  و`FUNCTIONS_REFERENCE.md` يُصحَّح — وبها **يُقفل الدَين نهائياً**.

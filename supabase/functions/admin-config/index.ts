// Edge Function: admin-config — كتابة آمنة لإعدادات التطبيق (app_config)
// السبب: سياسة RLS على app_config تشترط auth.uid() (جلسة Supabase حقيقية مع role≥6)
//        بينما المدير/النائب يدخلان بالهاتف عبر staff sessions (auth.uid()=NULL)
//        فكان الحفظ من شاشة الإعدادات يفشل بصمت — هذه الدالة تكتب عبر service_role
//        بعد التحقق من الجلسة (JWT أو staff session) بحد أدنى role≥5 (مدير/نائب).
// الأمان: whitelist حصرية للمفاتيح النصية المسموح تعديلها في هذه المرحلة:
//         txts.videoRequestWhatsApp / txts.videoRequestGroupLink / txts.appDownloadLink
//         (تُوسَّع لاحقاً لباقي أقسام الإعدادات بمراحل منفصلة ومراجعة مستقلة)
// ترتيب النشر: functions deploy فقط — لا تغييرات قاعدة بيانات.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// المفاتيح النصية المسموح تعديلها داخل txts.* (قائمة بيضاء)
//
// ⚠️ 2026-08-14: كانت هذه القائمة تحرس مسار `update_texts` وحده، بينما مسار
// `update_sections` كان يمرّر `txts` عبر الدمج السطحي الافتراضي
// (`{...cur, ...v}`) **بلا أي قائمة بيضاء ولا تنظيف ولا تحقّق من الروابط** —
// وكان القسم الوحيد المكشوف هكذا بين كل الأقسام. النتيجة: أي حساب دوره ≥ 5
// يستطيع زرع أي مفتاح بأي نوع، وأي رابط بأي مخطط (بما فيه `javascript:`)
// داخل «تابعنا على» التي يفتحها المستخدم بثقة أنها صفحة المكتب الرسمية.
// الآن المساران يتشاركان نفس القائمة ونفس التحقق.
const ALLOWED_TEXT_KEYS = new Set([
  "videoRequestWhatsApp",
  "videoRequestGroupLink",
  "appDownloadLink",
  "appLatestVersion",
  // نصوص الحالة المعروضة للمستخدم
  "plg",
  "bnRsn",
  "frzRsn",
  "visBlk",
  "warnApp",
  // صفحات التواصل الاجتماعي
  "facebook",
  "instagram",
  "socialPages",
  // نافذة «عن التطبيق» (2026-08-14) — بديل developerPhone/developerPhone2
  "contactPhone1",
  "contactPhone2",
  "contactWhatsApp",
  "aboutUs",
  "appDescription",
  "privacyPolicyUrl",
  "termsUrl",
  "referralBaseUrl",
]);

// مفاتيح txts التي قيمتها رابط — يُشترط فيها https:// حصراً.
const TEXT_URL_KEYS = new Set([
  "facebook",
  "instagram",
  "privacyPolicyUrl",
  "termsUrl",
  "referralBaseUrl",
  "appDownloadLink",
  "videoRequestGroupLink",
]);

// مفاتيح txts التي قيمتها رقم هاتف سوري.
const TEXT_PHONE_KEYS = new Set([
  "contactPhone1",
  "contactPhone2",
  "contactWhatsApp",
  "videoRequestWhatsApp",
]);

// الحد الأقصى لطول كل مفتاح نصي (حماية من تضخيم صف app_config).
const TEXT_MAX_LEN: Record<string, number> = {
  aboutUs: 1500,
  appDescription: 300,
};
const TEXT_DEFAULT_MAX_LEN = 500;

/// ✅ رابط آمن: `https://` حصراً.
/// نرفض `http://` (غير مشفَّر) وكل المخططات الخطرة (`javascript:`, `data:`,
/// `file:`) لأن القيمة تُمرَّر مباشرة إلى `launchUrl` في التطبيق.
function isSafeHttpsUrl(raw: string): boolean {
  const s = raw.trim();
  if (s.length === 0 || s.length > 500) return false;
  if (!s.startsWith("https://")) return false;
  if (/[\s\u0000-\u001F\u007F]/.test(s)) return false;
  try {
    const u = new URL(s);
    return u.protocol === "https:" && u.hostname.trim().length > 0;
  } catch {
    return false;
  }
}

/// ✅ رقم هاتف سوري: `09xxxxxxxx` أو `+9639xxxxxxxx` أو `9639xxxxxxxx`.
function isSyrianPhone(raw: string): boolean {
  const s = raw.trim().replace(/[\s()-]/g, "");
  return /^(0\d{9}|\+?963\d{9})$/.test(s);
}

/// 🧹 تحقُّق وتنظيف مفتاح واحد داخل `txts`.
/// يُرجع القيمة النظيفة، أو رسالة خطأ عربية عند الرفض.
/// **النص الفارغ مقبول دائماً** ويعني «أخفِ هذا البند» (قرار المالك: لا قيم
/// افتراضية مطبوخة — الفارغ يجب أن يُخفي فعلاً).
function validateTextKey(
  key: string,
  raw: unknown,
): { ok: true; value: unknown } | { ok: false; error: string } {
  // socialPages خريطة {network: url} وليست نصاً
  if (key === "socialPages") {
    if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
      return { ok: false, error: "SOCIAL_PAGES_MUST_BE_OBJECT" };
    }
    const out: Record<string, string> = {};
    const entries = Object.entries(raw as Record<string, unknown>);
    if (entries.length > 20) {
      return { ok: false, error: "TOO_MANY_SOCIAL_PAGES" };
    }
    for (const [k, v] of entries) {
      const nk = String(k).trim().toLowerCase().replace(/[\s_-]+/g, "");
      if (nk.length === 0 || nk.length > 30) {
        return { ok: false, error: `INVALID_SOCIAL_KEY:${k}` };
      }
      if (!/^[a-z0-9]+$/.test(nk)) {
        return { ok: false, error: `SOCIAL_KEY_MUST_BE_LATIN:${k}` };
      }
      const url = cleanText(v, 501); // 501 ليرفض isSafeHttpsUrl ما تجاوز 500
      if (url.length === 0) continue; // فارغ = محذوف
      if (!isSafeHttpsUrl(url)) {
        return { ok: false, error: `SOCIAL_URL_MUST_BE_HTTPS:${nk}` };
      }
      out[nk] = url;
    }
    return { ok: true, value: out };
  }

  const max = TEXT_MAX_LEN[key] ?? TEXT_DEFAULT_MAX_LEN;
  // ننظّف بسقف أعلى من الحد ثم نرفض الزائد صراحةً — لا اقتطاع صامت.
  const s = cleanText(raw, max + 1);
  if (s.length === 0) return { ok: true, value: "" }; // فارغ = أخفِ البند
  if (s.length > max) {
    return { ok: false, error: `TEXT_TOO_LONG:${key}:${max}` };
  }
  if (TEXT_URL_KEYS.has(key) && !isSafeHttpsUrl(s)) {
    return { ok: false, error: `URL_MUST_BE_HTTPS:${key}` };
  }
  if (TEXT_PHONE_KEYS.has(key) && !isSyrianPhone(s)) {
    return { ok: false, error: `INVALID_PHONE:${key}` };
  }
  return { ok: true, value: s };
}

// كود سجل التدقيق لتغيير إعدادات txts (أكواد 101-107 مستخدمة للعروض/السوشيال)
const ACT_UPDATE_CONFIG_TEXTS = 120;

function env(name: string, fallback?: string): string {
  return Deno.env.get(name) ?? (fallback ? Deno.env.get(fallback) ?? "" : "");
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// نفس نمط validateActor المعتمد في admin-offers (JWT ثم staff session)
async function validateActor(
  req: Request,
  supabaseAdmin: ReturnType<typeof createClient>,
  body: Record<string, unknown>,
  minRole = 5, // مدير + نائب فقط — صاحب صلاحية "إعدادات التطبيق"
): Promise<{ ok: true; adminUid: string; role: number } | { ok: false; response: Response }> {
  const requestedAdminUid = (body.admin_uid ?? body.adminUid ?? body.user_uid ?? body.userUid ?? body.admin_id ?? body.adminId)?.toString() ?? "";
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";

  if (bearer && bearer !== "undefined" && bearer !== "null" && bearer !== "anon_key_here") {
    const { data: userData } = await supabaseAdmin.auth.getUser(bearer);
    const uid = userData?.user?.id;
    if (uid && (!requestedAdminUid || requestedAdminUid === uid)) {
      const { data: userRow, error } = await supabaseAdmin
        .from("users")
        .select("id, role, sts, i_del")
        .eq("id", uid)
        .eq("i_del", 0)
        .single();

      if (!error && userRow && userRow.sts === 0 && Number(userRow.role) >= minRole) {
        return { ok: true, adminUid: uid, role: Number(userRow.role) };
      }
    }
  }

  const sessionToken = (body.staff_session_token ?? body.staffSessionToken)?.toString()
    ?? (authHeader && !authHeader.startsWith("Bearer ") ? authHeader.trim() : "");
  if (!requestedAdminUid || !sessionToken) {
    return { ok: false, response: json({ success: false, error: "ADMIN_SESSION_REQUIRED" }, 401) };
  }

  const { data, error } = await supabaseAdmin.rpc("validate_staff_session", {
    p_user_uid: requestedAdminUid,
    p_token: sessionToken,
    p_min_role: minRole,
  });

  if (error || data?.success !== true) {
    return {
      ok: false,
      response: json({ success: false, error: data?.error ?? error?.message ?? "INVALID_ADMIN_SESSION" }, 401),
    };
  }

  return { ok: true, adminUid: requestedAdminUid, role: Number(data.role) };
}

// تنظيف نص إعداد: إزالة محارف التحكم (U+0000–U+001F وU+007F) + قص الطول (300 كحد أقصى)
/// 🧹 تنظيف نص: حذف محارف التحكّم + قصّ الأطراف + سقف طول.
///
/// ⚠️ 2026-08-14: كان السقف ثابتاً عند 300 محرف. فقرة «من نحن» تحتاج 1500،
/// وكانت ستُقتطع **بصمت** إلى 300 بلا أي رسالة للمدير — أي أن المدير يحفظ
/// ويرى «تم» بينما نصفُ نصه ضاع (§13 No-Silent-Probes). الآن السقف معامل،
/// و`validateTextKey` يرفض الزائد صراحةً بدل اقتطاعه.
function cleanText(v: unknown, maxLen = 300): string {
  return (v ?? "").toString().replace(/[\u0000-\u001F\u007F]/g, "").trim().slice(0, maxLen);
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ success: false, error: "METHOD_NOT_ALLOWED" }, 405);

  try {
    const supabaseAdmin = createClient(
      env("SUPABASE_URL", "PROJECT_URL"),
      env("SUPABASE_SERVICE_ROLE_KEY", "SERVICE_ROLE_KEY"),
      { auth: { autoRefreshToken: false, persistSession: false } },
    );

    const body = await req.json() as Record<string, unknown>;
    const action = (body.action ?? "").toString();
    const actor = await validateActor(req, supabaseAdmin, body, 5);
    if (!actor.ok) return actor.response;
    const adminUid = actor.adminUid;

    // ─── Action: update_sections — حفظ أقسام محرر الإعدادات ───
    // أُضيف 2026-07-29: ConfigProvider.updateConfig كان يكتب app_config بـ PATCH
    // مباشر بمفتاح anon والسيرفر يرفضه 42501 ⇒ زر «حفظ الإعدادات» معطّل بالكامل
    // (كل الأقسام: النقاط/العمولات/الحصص/النصوص/النشر التلقائي).
    // الحل: الحفظ عبر مفتاح الخدمة، بقائمة بيضاء للأقسام تمنع الكتابة العشوائية،
    // ودمج على مستوى القسم (لا استبدال كامل) فلا تُفقد مفاتيح لم يرسلها العميل.
    if (action === "update_sections") {
      const incoming = body.sections;
      if (!incoming || typeof incoming !== "object" || Array.isArray(incoming)) {
        return json({ success: false, error: "SECTIONS_OBJECT_REQUIRED" }, 400);
      }

      // 2026-08-14: أُضيف payChannels + office. السبب: محرّر قنوات الدفع كان
      // يحفظ عبر PATCH مباشر بمفتاح anon فيرفضه RLS (يشترط auth.uid + role>=6)
      // ⇒ «حفظ» يفشل بصمت لمدير الهاتف (بلا JWT) — نفس درس §18 الموثق.
      const ALLOWED_SECTIONS = new Set([
        "pts", "com", "qta", "txts", "socialPublishing", "photoPrice",
        "payChannels", "office", "legalPrice",
      ]);
      const entries = Object.entries(incoming as Record<string, unknown>);
      const rejected = entries.map(([k]) => k).filter((k) => !ALLOWED_SECTIONS.has(k));
      if (rejected.length > 0) {
        return json({ success: false, error: "SECTION_NOT_ALLOWED", keys: rejected }, 403);
      }
      if (entries.length === 0) {
        return json({ success: false, error: "NO_SECTIONS_PROVIDED" }, 400);
      }

      const { data: row, error: readErr } = await supabaseAdmin
        .from("app_config").select("value").eq("key", "main").maybeSingle();
      if (readErr) return json({ success: false, error: readErr.message }, 400);

      const value = (row?.value && typeof row.value === "object" && !Array.isArray(row.value))
        ? { ...(row.value as Record<string, unknown>) }
        : {};

      for (const [k, v] of entries) {
        if (k === "photoPrice") {
          const p = Number(v);
          if (!Number.isInteger(p) || p < 0 || p > 100000000) {
            return json({ success: false, error: "INVALID_PHOTO_PRICE" }, 400);
          }
          value[k] = p;
          continue;
        }
        // ── payChannels: دمج على مستوى القناة (لا مستوى القسم) ──
        // 2026-08-14: الدمج السطحي وحده يستبدل كائن القناة كاملاً فتضيع name/icon
        // إن لم يرسلها العميل. هنا كل قناة تُدمج مع الموجود، وتُرفض أي قناة أو
        // مفتاح خارج القوائم البيضاء، وتُنظَّف كل القيم النصية.
        if (k === "payChannels") {
          if (!v || typeof v !== "object" || Array.isArray(v)) {
            return json({ success: false, error: "SECTION_MUST_BE_OBJECT", key: k }, 400);
          }
          const ALLOWED_CHANNELS = new Set(["haram", "sham_cash", "syriatel_cash", "balance", "bank"]);
          const ALLOWED_CH_KEYS = new Set([
            "enabled", "name", "icon", "instructions",
            "recipient_name", "recipient_phone", "account_number", "qr_image_url",
            "number", "syriatel_number", "mtn_number",
            "bank_name", "account_holder", "iban", "branch",
          ]);
          const curAll = (value[k] && typeof value[k] === "object" && !Array.isArray(value[k]))
            ? { ...(value[k] as Record<string, unknown>) } : {};
          for (const [chKey, chVal] of Object.entries(v as Record<string, unknown>)) {
            if (!ALLOWED_CHANNELS.has(chKey)) {
              return json({ success: false, error: "CHANNEL_NOT_ALLOWED", key: chKey }, 403);
            }
            if (!chVal || typeof chVal !== "object" || Array.isArray(chVal)) {
              return json({ success: false, error: "CHANNEL_MUST_BE_OBJECT", key: chKey }, 400);
            }
            const badKeys = Object.keys(chVal as Record<string, unknown>)
              .filter((f) => !ALLOWED_CH_KEYS.has(f));
            if (badKeys.length > 0) {
              return json({ success: false, error: "CHANNEL_FIELD_NOT_ALLOWED", keys: badKeys }, 403);
            }
            const curCh = (curAll[chKey] && typeof curAll[chKey] === "object" && !Array.isArray(curAll[chKey]))
              ? { ...(curAll[chKey] as Record<string, unknown>) } : {};
            for (const [f, fv] of Object.entries(chVal as Record<string, unknown>)) {
              curCh[f] = (f === "enabled") ? (fv === true) : cleanText(fv);
            }
            curAll[chKey] = curCh;
          }

          // 🔒 BUG-009 (2026-08-14): حارس «آخر قناة دفع».
          // كان بالإمكان تعطيل القنوات الخمس كلها بطلب واحد ⇒ **لا يستطيع أي
          // مستخدم الدفع إطلاقاً**: الباقات والإعلان المميز والاستشارة القانونية
          // تتوقف كلها، والأسوأ أن العطل صامت — الإدارة ترى «تم الحفظ» ولا شيء
          // ينبّهها. أُكِّد حياً: الطلب نجح والنتيجة `القنوات المفعّلة: []`.
          const anyEnabled = Object.values(curAll).some((ch) => {
            const o = (ch && typeof ch === "object" && !Array.isArray(ch))
              ? ch as Record<string, unknown> : {};
            return o.enabled === true;
          });
          if (!anyEnabled) {
            return json({
              success: false,
              error: "AT_LEAST_ONE_CHANNEL_REQUIRED",
              detail: "يجب إبقاء قناة دفع واحدة مفعّلة على الأقل — وإلا يتعذّر الدفع في التطبيق كلياً.",
            }, 400);
          }

          value[k] = curAll;
          continue;
        }

        // ── legalPrice: أسعار الاستشارة القانونية ومدة المحادثة ──
        // 2026-08-14: كانت 500/2000/15 ثابتة بالكود (11 موضع واجهة + 3 إيدج + RPC)
        // ⇒ تعديلها مستحيل. القيم أعداد صحيحة موجبة فقط، والمدة ≥ 1 دقيقة.
        if (k === "legalPrice") {
          if (!v || typeof v !== "object" || Array.isArray(v)) {
            return json({ success: false, error: "SECTION_MUST_BE_OBJECT", key: k }, 400);
          }
          // 📍 2026-08-20: officeAddress — عنوان المكتب للجلسات الحضورية (نص
          // ≤ 200 حرف)، تبقى بقية الحقول أعداداً صحيحة موجبة.
          const ALLOWED_LEGAL = new Set(["phone", "onsite", "renew", "durationMins", "officeAddress"]);
          const badLegal = Object.keys(v as Record<string, unknown>)
            .filter((f) => !ALLOWED_LEGAL.has(f));
          if (badLegal.length > 0) {
            return json({ success: false, error: "LEGAL_FIELD_NOT_ALLOWED", keys: badLegal }, 403);
          }
          const curLegal = (value[k] && typeof value[k] === "object" && !Array.isArray(value[k]))
            ? { ...(value[k] as Record<string, unknown>) } : {};
          for (const [f, fv] of Object.entries(v as Record<string, unknown>)) {
            if (f === "officeAddress") {
              curLegal[f] = String(fv ?? "").trim().slice(0, 200);
              continue;
            }
            const n = Number(fv);
            if (!Number.isInteger(n) || n < 0 || n > 100000000) {
              return json({ success: false, error: "INVALID_LEGAL_PRICE", key: f }, 400);
            }
            if (f === "durationMins" && (n < 1 || n > 1440)) {
              return json({ success: false, error: "INVALID_DURATION_MINS" }, 400);
            }
            curLegal[f] = n;
          }
          value[k] = curLegal;
          continue;
        }

        // ── office: بيانات المكتب (الهاتف مصدرُ رقم تحويل الرصيد) ──
        if (k === "office") {
          if (!v || typeof v !== "object" || Array.isArray(v)) {
            return json({ success: false, error: "SECTION_MUST_BE_OBJECT", key: k }, 400);
          }
          const ALLOWED_OFFICE = new Set(["phone", "address", "working_hours", "working_days"]);
          const badOffice = Object.keys(v as Record<string, unknown>)
            .filter((f) => !ALLOWED_OFFICE.has(f));
          if (badOffice.length > 0) {
            return json({ success: false, error: "OFFICE_FIELD_NOT_ALLOWED", keys: badOffice }, 403);
          }
          const curOffice = (value[k] && typeof value[k] === "object" && !Array.isArray(value[k]))
            ? { ...(value[k] as Record<string, unknown>) } : {};
          for (const [f, fv] of Object.entries(v as Record<string, unknown>)) {
            if (f === "working_days") {
              if (!Array.isArray(fv) || fv.some((d) => !Number.isInteger(Number(d)))) {
                return json({ success: false, error: "INVALID_WORKING_DAYS" }, 400);
              }
              curOffice[f] = fv.map((d) => Number(d));
            } else {
              curOffice[f] = cleanText(fv);
            }
          }
          value[k] = curOffice;
          continue;
        }

        // ── txts: القائمة البيضاء + التنظيف + تحقّق الروابط والأرقام ──
        // 2026-08-14: كان هذا القسم يسقط في الدمج السطحي أدناه بلا أي حراسة.
        if (k === "txts") {
          if (!v || typeof v !== "object" || Array.isArray(v)) {
            return json({ success: false, error: "SECTION_MUST_BE_OBJECT", key: k }, 400);
          }
          const curTxts = (value[k] && typeof value[k] === "object" && !Array.isArray(value[k]))
            ? { ...(value[k] as Record<string, unknown>) } : {};
          const badTxts = Object.keys(v as Record<string, unknown>)
            .filter((f) => !ALLOWED_TEXT_KEYS.has(f));
          if (badTxts.length > 0) {
            return json({ success: false, error: "TEXT_KEY_NOT_ALLOWED", keys: badTxts }, 403);
          }
          for (const [f, fv] of Object.entries(v as Record<string, unknown>)) {
            const res = validateTextKey(f, fv);
            if (!res.ok) return json({ success: false, error: res.error }, 400);
            curTxts[f] = res.value;
          }
          // إزالة المفتاحين القديمين نهائياً بعد الترحيل إلى contactPhone1/2
          delete curTxts["developerPhone"];
          delete curTxts["developerPhone2"];
          value[k] = curTxts;
          continue;
        }

        // دمج القسم مع الموجود بدل استبداله (حماية من فقدان مفاتيح)
        if (v && typeof v === "object" && !Array.isArray(v)) {
          const cur = (value[k] && typeof value[k] === "object" && !Array.isArray(value[k]))
            ? (value[k] as Record<string, unknown>) : {};
          value[k] = { ...cur, ...(v as Record<string, unknown>) };
        } else {
          return json({ success: false, error: "SECTION_MUST_BE_OBJECT", key: k }, 400);
        }
      }

      const { error: upErr } = await supabaseAdmin
        .from("app_config").update({ value }).eq("key", "main");
      if (upErr) return json({ success: false, error: upErr.message }, 400);

      try {
        await supabaseAdmin.rpc("log_admin_action", {
          p_admin_uid: adminUid,
          p_act: ACT_UPDATE_CONFIG_TEXTS,
          p_det: `config sections: ${entries.map(([k]) => k).join(",")}`,
          p_ref_id: "main",
          p_ref_col: "app_config",
        });
      } catch { /* سجل التدقيق ثانوي */ }

      return json({ success: true, updated: entries.map(([k]) => k), value });
    }

    // ─── Action: update_photo_price — أجر خدمة التصوير العقاري (ل.س) ───
    // أُضيف 2026-07-29: العميل كان يكتب app_config بـ PATCH مباشر بمفتاح anon
    // والسيرفر يرفضه 42501 ⇒ زر الحفظ كان معطّلاً فعلياً. المسار الآن عبر الإيدج
    // بمفتاح الخدمة، بنطاق ضيّق (مفتاح واحد) ومع تحقق دور ≥5 وسجل تدقيق.
    if (action === "update_photo_price") {
      const raw = body.photo_price ?? body.photoPrice;
      const price = Number(raw);
      if (!Number.isFinite(price) || !Number.isInteger(price) || price < 0 || price > 100000000) {
        return json({ success: false, error: "INVALID_PHOTO_PRICE" }, 400);
      }

      const { data: row, error: readErr } = await supabaseAdmin
        .from("app_config").select("value").eq("key", "main").maybeSingle();
      if (readErr) return json({ success: false, error: readErr.message }, 400);

      const value = (row?.value && typeof row.value === "object" && !Array.isArray(row.value))
        ? { ...(row.value as Record<string, unknown>) }
        : {};
      const oldPrice = value.photoPrice ?? null;
      value.photoPrice = price;

      const { error: upErr } = await supabaseAdmin
        .from("app_config").update({ value }).eq("key", "main");
      if (upErr) return json({ success: false, error: upErr.message }, 400);

      try {
        await supabaseAdmin.rpc("log_admin_action", {
          p_admin_uid: adminUid,
          p_act: ACT_UPDATE_CONFIG_TEXTS,
          p_det: `photoPrice: ${oldPrice ?? "—"} → ${price}`,
          p_ref_id: "main",
          p_ref_col: "app_config",
        });
      } catch { /* سجل التدقيق ثانوي */ }

      return json({ success: true, photo_price: price });
    }

    // ─── Action: update_texts — تحديث مفاتيح نصية ضمن txts.* ───
    // ─── IMP-002: نسخ الإعدادات الاحتياطية (2026-08-14) ───
    // app_config كان فيه صفّان فقط بلا أي نسخة احتياطية: خطأ واحد في المحرّر
    // (سعر خاطئ · نص ممسوح · قناة معطّلة) = لا رجعة. وسجل التدقيق كان يسجّل
    // اسم القسم فقط بلا القيمة القديمة، فحتى معرفة ما تغيّر مستحيلة.
    // الآن trigger يلتقط كل تغيير (آخر 50 نسخة لكل مفتاح).
    if (action === "list_config_history") {
      const key = (body.config_key ?? body.key ?? "main").toString();
      const limit = Number(body.limit ?? 20);
      const { data, error } = await supabaseAdmin.rpc("admin_list_config_history", {
        p_admin_uid: adminUid,
        p_key: key,
        p_limit: Number.isFinite(limit) ? limit : 20,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, history: data ?? [] });
    }

    // الاسترجاع: مدير فقط (role=6) — أخطر من التعديل نفسه لأنه يعيد الحالة كلها
    if (action === "restore_config") {
      const historyId = Number(body.history_id ?? body.historyId);
      if (!Number.isFinite(historyId) || historyId <= 0) {
        return json({ success: false, error: "HISTORY_ID_REQUIRED" }, 400);
      }
      const { data, error } = await supabaseAdmin.rpc("admin_restore_config", {
        p_admin_uid: adminUid,
        p_history_id: historyId,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json(data && typeof data === "object" ? data as Record<string, unknown> : { success: true });
    }

    if (action === "update_texts") {
      const incoming = body.texts;
      if (!incoming || typeof incoming !== "object" || Array.isArray(incoming)) {
        return json({ success: false, error: "TEXTS_OBJECT_REQUIRED" }, 400);
      }

      // رفض أي مفتاح خارج القائمة البيضاء (منع الكتابة العشوائية بالإعدادات)
      const entries = Object.entries(incoming as Record<string, unknown>);
      const rejectedKeys = entries.map(([k]) => k).filter((k) => !ALLOWED_TEXT_KEYS.has(k));
      if (rejectedKeys.length > 0) {
        return json({ success: false, error: "KEY_NOT_ALLOWED", keys: rejectedKeys }, 403);
      }
      if (entries.length === 0) {
        return json({ success: false, error: "NO_KEYS_PROVIDED" }, 400);
      }

      // قراءة القيمة الحالية ودمج txts فقط (باقي أقسام الإعدادات لا تُمس)
      const { data: row, error: readErr } = await supabaseAdmin
        .from("app_config")
        .select("value")
        .eq("key", "main")
        .maybeSingle();
      if (readErr) return json({ success: false, error: readErr.message }, 400);

      const value = (row?.value && typeof row.value === "object" && !Array.isArray(row.value))
        ? { ...(row.value as Record<string, unknown>) }
        : {};
      const txts = { ...((value.txts && typeof value.txts === "object" && !Array.isArray(value.txts))
        ? (value.txts as Record<string, unknown>)
        : {}) };

      // نفس التحقق المستخدم في update_sections — مصدر واحد للقواعد حتى لا
      // ينحرف المساران (كان هذا المسار يكتفي بـ cleanText بلا تحقُّق روابط).
      for (const [k, v] of entries) {
        const res = validateTextKey(k, v);
        if (!res.ok) return json({ success: false, error: res.error }, 400);
        txts[k] = res.value;
      }
      delete txts["developerPhone"];
      delete txts["developerPhone2"];
      value.txts = txts;

      const { error: writeErr } = await supabaseAdmin
        .from("app_config")
        .upsert({ key: "main", value }, { onConflict: "key" });
      if (writeErr) return json({ success: false, error: writeErr.message }, 400);

      // تسجيل الحركة — بالأسماء الصحيحة للنسخة الحية المؤكدة 2026-07-26
      const changedKeys = entries.map(([k]) => k).join(", ");
      try {
        await supabaseAdmin.rpc("log_admin_action", {
          p_admin_uid: adminUid,
          p_act: ACT_UPDATE_CONFIG_TEXTS,
          p_det: `تحديث نصوص الإعدادات (${changedKeys})`,
          p_ref_id: "main",
          p_ref_col: "app_config",
        });
      } catch (_) { /* التسجيل أفضل-جهد ولا يسقط العملية */ }

      return json({ success: true, updated: entries.map(([k]) => k) });
    }

    return json({ success: false, error: "UNKNOWN_ACTION" }, 400);
  } catch (e) {
    return json({ success: false, error: (e as Error).message ?? "UNEXPECTED_ERROR" }, 500);
  }
});

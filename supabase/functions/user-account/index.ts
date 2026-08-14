// Edge Function: user-account
// الغرض: إدارة ملف المستخدم الشخصي، التحقق من اسم المستخدم، كلمات السر، الأجهزة، والتوثيق، باستخدام JWT أو آليات محددة.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function env(name: string, fallback?: string): string {
  return Deno.env.get(name) ?? (fallback ? Deno.env.get(fallback) ?? "" : "");
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isBlank(value: unknown): boolean {
  return value === null || value === undefined || value.toString().trim() === "";
}

// ─── نقاط من الكونفغ سيرفرياً (تحصين 2026-07-27): العميل لا يقرر قيمة النقاط ───
const POINTS_DEFAULTS: Record<string, number> = {
  like: 5, cmt: 20, shr: 10, soc: 100, strk: 50, ref: 1500,
  wkL: 100, addO: 500, sgn: 1000, att: 300, dlD: 2000,
};
const SELF_EVENTS = new Set(["like", "cmt", "shr", "soc"]);

async function loadPointsMap(
  supabaseAdmin: ReturnType<typeof createClient>,
): Promise<Record<string, number>> {
  const out: Record<string, number> = { ...POINTS_DEFAULTS };
  try {
    const { data } = await supabaseAdmin
      .from("app_config").select("value").eq("key", "main").maybeSingle();
    const raw = (data as Record<string, any> | null)?.value?.pts;
    if (raw && typeof raw === "object") {
      for (const [k, v] of Object.entries(raw)) {
        if (typeof v === "number") out[k] = v;
        else if (v && typeof (v as any).p === "number") out[k] = (v as any).p;
      }
    }
  } catch (_) { /* الاحتياطيات تكفي */ }
  return out;
}

function isIncompleteEmailSignup(row: Record<string, unknown> | null | undefined): boolean {
  if (!row) return false;
  const role = Number(row.role ?? 0);
  return role === 0 &&
    isBlank(row.nm) &&
    isBlank(row.ph) &&
    isBlank(row.usr) &&
    isBlank(row.pwd);
}

// دالة التحقق من الـ JWT
async function validateUser(
  req: Request,
  supabaseAdmin: ReturnType<typeof createClient>,
  requestedUid: string,
  body: Record<string, unknown> = {}
): Promise<{ ok: true; uid: string } | { ok: false; response: Response }> {
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";

  // 1. Try JWT validation first
  if (bearer && bearer !== "undefined" && bearer !== "null" && bearer !== "anon_key_here") {
    const { data: userData, error } = await supabaseAdmin.auth.getUser(bearer);
    const uid = userData?.user?.id;
    if (!error && uid) {
      if (requestedUid && requestedUid !== uid) {
        return { ok: false, response: json({ success: false, error: "UNAUTHORIZED_ACCESS" }, 403) };
      }
      return { ok: true, uid: uid };
    }
  }

  // 2. Try Custom Session Token validation (for custom password login)
  const sessionToken = (body?.staff_session_token ?? body?.staffSessionToken ?? body?.session_token ?? body?.sessionToken)?.toString() || bearer || authHeader.trim();
  if (sessionToken && sessionToken !== "anon_key_here" && sessionToken !== "undefined" && sessionToken !== "null") {
    const { data, error } = await supabaseAdmin.rpc("validate_staff_session", {
      p_token: sessionToken,
      p_user_uid: requestedUid, // Pass requestedUid to ensure the token belongs to the requested user
      p_min_role: 0,
    });

    if (!error && data && data.success === true) {
      return { ok: true, uid: data.user_id };
    }
  }

  // FALLBACK REMOVED: No longer accepting requestedUid blindly.
  return { ok: false, response: json({ success: false, error: "AUTH_TOKEN_REQUIRED" }, 401) };
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

    // ----------------------------------------------------
    // دوال لا تتطلب توثيق المستخدم (تُستخدم أثناء تسجيل الدخول/التسجيل)
    // ----------------------------------------------------

    if (action === "login_with_password") {
      const identifier = (body.identifier ?? "").toString();
      const password = (body.password ?? "").toString();
      if (!identifier || !password) return json({ success: false, error: "MISSING_CREDENTIALS" }, 400);

      // 🔒 SEC-005 (2026-08-14): حد محاولات الدخول — منع التخمين.
      // كانت 8 محاولات خاطئة متتالية تمرّ بلا أي إبطاء أو قفل (أُكِّد حياً).
      // خطير هنا تحديداً لأن كلمات السر تُنشأ إدارياً وكثير منها أرقام قصيرة،
      // وأرقام الهواتف كانت قابلة للحصاد (BUG-021) ⇒ مسار مباشر لحساب مدير.
      const throttle = await supabaseAdmin.rpc("check_login_throttle", {
        p_identifier: identifier,
      });
      const tData = (throttle.data ?? {}) as Record<string, unknown>;
      if (tData.allowed === false) {
        const retry = Number(tData.retry_after ?? 900);
        const mins = Math.max(1, Math.ceil(retry / 60));
        return json({
          success: false,
          error: "TOO_MANY_ATTEMPTS",
          retry_after: retry,
          detail: `محاولات كثيرة خاطئة — أعد المحاولة بعد ${mins} دقيقة.`,
        }, 429);
      }

      const { data, error } = await supabaseAdmin.rpc("login_with_password", {
        p_identifier: identifier,
        p_password: password,
      });

      if (error) {
        await supabaseAdmin.rpc("record_login_attempt", { p_identifier: identifier, p_ok: false });
        return json({ success: false, error: error.message }, 400);
      }

      // الدالة تُرجع كائناً فيه success — الفشل المنطقي (كلمة خاطئة) يُحتسب
      const res = (data ?? {}) as Record<string, unknown>;
      const loggedIn = res.success === true;
      await supabaseAdmin.rpc("record_login_attempt", {
        p_identifier: identifier,
        p_ok: loggedIn,
      });

      return json({ success: true, result: data });
    }

    if (action === "check_username") {
      const username = (body.username ?? "").toString();
      if (!username) return json({ success: false, error: "USERNAME_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("check_username_available", { p_username: username });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, available: data === true });
    }

    // ✅ فحص هل الإيميل مسجل عند حساب موجود (لمنع حساب مكرر)
    if (action === "check_email_exists") {
      const email = (body.email ?? "").toString().trim().toLowerCase();
      if (!email) return json({ success: false, error: "EMAIL_REQUIRED" }, 400);

      const { data: existing, error: findError } = await supabaseAdmin
        .from("users")
        .select("id, role, nm, ph, eml, usr, pwd")
        .eq("eml", email)
        .eq("i_del", 0)
        .maybeSingle();

      if (findError) return json({ success: false, error: findError.message }, 400);

      const incomplete = isIncompleteEmailSignup(existing as Record<string, unknown> | null);
      // الحساب الإيميلي الناقص (أنشئ بعد Magic Link ولم يكمل setup-profile)
      // يجب أن لا يمنع إعادة إرسال الرابط حتى يستطيع المستخدم إكمال التسجيل.
      // 🔒 BUG-021: نفس تسريب check_phone_exists — كان يكشف `user_id` صاحب
      // البريد لأي طالب بلا مصادقة. المستدعي يقارنه بمعرّفه هو ليعرف إن كان
      // البريد يخصّه، فتكفيه إجابة منطقية.
      const selfUidE = (body.self_uid ?? body.selfUid ?? "").toString().trim();
      const foundIdE = (existing as Record<string, unknown> | null)?.id?.toString() ?? null;
      return json({
        success: true,
        exists: !!existing && !incomplete,
        incomplete,
        owned_by_other: !!foundIdE && !incomplete && (!selfUidE || foundIdE !== selfUidE),
        is_self: !!foundIdE && !!selfUidE && foundIdE === selfUidE,
      });
    }

    // ✅ فحص هل الرقم مسجل عند حساب موجود (لمنع حساب مكرر)
    if (action === "check_phone_exists") {
      const phone = (body.phone ?? "").toString().trim();
      if (!phone) return json({ success: false, error: "PHONE_REQUIRED" }, 400);

      // تطبيع الرقم باستخدام SQL function
      const { data: normalized, error: normError } = await supabaseAdmin
        .rpc("normalize_sy_phone", { p_phone: phone });
      if (normError) return json({ success: false, error: normError.message }, 400);

      const { data: existing, error: findError } = await supabaseAdmin
        .from("users")
        .select("id")
        .eq("ph", normalized)
        .eq("i_del", 0)
        .maybeSingle();

      if (findError) return json({ success: false, error: findError.message }, 400);

      // 🔒 BUG-021 (2026-08-14): كان يُرجع `user_id` لأي طالب **بلا أي مصادقة**
      // ⇒ حصاد UIDs بالجملة: مكالمة واحدة برقم هاتف تعطي المعرّف الداخلي
      // لصاحبه. أُكِّد حياً — حُصد UID المدير الرئيسي وحساب محامٍ ومدير آخر
      // من أرقامهم وحدها. والـUID مفتاح يُمرَّر في كل نداءات الـAPI تقريباً.
      // المستدعي الوحيد (setup_profile_screen) يقارن الناتج بـ**معرّفه هو**
      // ليعرف إن كان الرقم يخصّه، فتكفيه إجابة منطقية بلا كشف المعرّف.
      const selfUid = (body.self_uid ?? body.selfUid ?? "").toString().trim();
      const foundId = (existing as Record<string, unknown> | null)?.id?.toString() ?? null;
      return json({
        success: true,
        exists: !!existing,
        // true فقط عندما يكون الرقم مملوكاً لشخص **آخر** غير مقدّم الطلب
        owned_by_other: !!foundId && (!selfUid || foundId !== selfUid),
        is_self: !!foundId && !!selfUid && foundId === selfUid,
      });
    }

    if (action === "register_device") {
      const deviceId = (body.device_id ?? body.deviceId)?.toString() ?? "";
      const ipHint = (body.ip_hint ?? body.ipHint)?.toString() ?? null;
      if (!deviceId) return json({ success: false, error: "DEVICE_ID_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("register_device", {
        p_device_id: deviceId,
        p_ip_hint: ipHint,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    // Email Magic Link: يجب أن يقرأ المستخدم من JWT مباشرة.
    // لا نستدعي handle_email_auth_internal هنا لأن Supabase client المستخدم service_role
    // ولا يمرر auth.uid()/auth.jwt() إلى داخل SQL.
    if (action === "handle_email_auth") {
      const authHeader = req.headers.get("Authorization") ?? "";
      const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
      if (!bearer || bearer === "undefined" || bearer === "null" || bearer === "anon_key_here") {
        return json({ success: false, error: "AUTH_TOKEN_REQUIRED" }, 401);
      }

      const { data: userData, error: userError } = await supabaseAdmin.auth.getUser(bearer);
      const authUser = userData?.user;
      const authUid = authUser?.id;
      const email = (authUser?.email ?? "").trim().toLowerCase();

      if (userError || !authUid) return json({ success: false, error: "AUTH_TOKEN_INVALID" }, 401);
      if (!email) return json({ success: false, error: "EMAIL_REQUIRED" }, 400);
      if (email.endsWith("@whatsapp.local")) return json({ success: false, error: "PSEUDO_EMAIL_NOT_ALLOWED" }, 400);

      const { data: existingById, error: byIdError } = await supabaseAdmin
        .from("users")
        .select("id, eml, usr, pwd, i_del")
        .eq("id", authUid)
        .eq("i_del", 0)
        .maybeSingle();

      if (byIdError) return json({ success: false, error: byIdError.message }, 400);

      if (existingById) {
        const existingEmail = (existingById.eml ?? "").toString().trim().toLowerCase();
        if (existingEmail && existingEmail !== email) {
          return json({ success: false, error: "AUTH_UID_EMAIL_CONFLICT" }, 409);
        }

        const { error: updateError } = await supabaseAdmin
          .from("users")
          .update({ eml: email, ts_upd: new Date().toISOString() })
          .eq("id", authUid);
        if (updateError) return json({ success: false, error: updateError.message }, 400);

        return json({
          success: true,
          user_id: authUid,
          is_new: false,
          email,
        });
      }

      const { data: existingByEmail, error: byEmailError } = await supabaseAdmin
        .from("users")
        .select("id, role, nm, ph, eml, usr, pwd")
        .eq("eml", email)
        .eq("i_del", 0)
        .maybeSingle();

      if (byEmailError) return json({ success: false, error: byEmailError.message }, 400);

      // إذا الإيميل مربوط بسجل مستخدم آخر فلا نعيد user_id مختلفاً عن JWT.
      // الاستثناء الوحيد: حساب إيميلي ناقص لم يكمل setup-profile؛ نؤرشفه
      // كي يستطيع المستخدم إعادة طلب الرابط والمتابعة بحساب Auth الجديد.
      if (existingByEmail && existingByEmail.id !== authUid) {
        const incomplete = isIncompleteEmailSignup(existingByEmail as Record<string, unknown> | null);
        if (!incomplete) {
          return json({
            success: false,
            error: "EMAIL_ALREADY_LINKED_TO_DIFFERENT_AUTH_USER",
          }, 409);
        }

        const archivedEmail = `orphaned_${existingByEmail.id}_${email}`;
        const { error: archiveError } = await supabaseAdmin
          .from("users")
          .update({
            i_del: 1,
            eml: archivedEmail,
            ts_upd: new Date().toISOString(),
          })
          .eq("id", existingByEmail.id)
          .eq("i_del", 0);

        if (archiveError) return json({ success: false, error: archiveError.message }, 400);
      }

      const { error: insertError } = await supabaseAdmin
        .from("users")
        .insert({
          id: authUid,
          nm: "",
          ph: "",
          eml: email,
          role: 0,
          sts: 0,
          i_del: 0,
          ts_crt: new Date().toISOString(),
          ts_upd: new Date().toISOString(),
        });
      if (insertError) return json({ success: false, error: insertError.message }, 400);

      return json({
        success: true,
        user_id: authUid,
        is_new: true,
        email,
      });
    }

    // ----------------------------------------------------
    // دوال تتطلب مستخدم مسجل الدخول (JWT)
    // ----------------------------------------------------

    const requestedUid = (body.user_uid ?? body.userUid)?.toString() ?? "";
    if (!requestedUid) return json({ success: false, error: "USER_UID_REQUIRED" }, 400);

    const actor = await validateUser(req, supabaseAdmin, requestedUid, body);
    if (!actor.ok) return actor.response;
    const uid = actor.uid;

    if (action === "revoke_staff_session") {
      const sessionToken = (body.session_token ?? body.sessionToken)?.toString() ?? "";
      if (!sessionToken) return json({ success: false, error: "SESSION_TOKEN_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("revoke_staff_session", {
        p_user_uid: uid,
        p_token: sessionToken,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    if (action === "register_weekly_login") {
      const ptsMap = await loadPointsMap(supabaseAdmin);
      const { data, error } = await supabaseAdmin.rpc("register_weekly_login", {
        p_uid: uid,
        p_pts: ptsMap["wkL"] ?? 100, // سيرفرياً من الكونفغ — لا قيمة من العميل
      });
      if (error) return json({ success: false, error: error.message }, 400);
      // 🔒 §13 No-Silent-Probes (2026-08-14): الدالة تُرجع FALSE مجرّداً حين
      // لم تمرّ 7 أيام على آخر تسجيل — وهو **سلوك صحيح** لا خطأ. لكن الإيدج
      // كان يمرّر `success:false` بلا سبب، فلا الواجهة ولا المستخدم يعرف
      // هل فشل النظام أم أن المكافأة ببساطة لم تستحق بعد.
      if (data !== true) {
        return json({
          success: false,
          error: "WEEKLY_BONUS_NOT_DUE",
          detail: "مكافأة الدخول الأسبوعي تُمنح مرة كل 7 أيام.",
        }, 200);
      }
      return json({ success: true });
    }

    if (action === "award_points") {
      const eventType = (body.event_type ?? "").toString();
      if (!eventType) return json({ success: false, error: "EVENT_TYPE_REQUIRED" }, 400);

      // تحصين 2026-07-27 (سد سكب النقاط):
      //  ١) الحدث معرّف بالكونفغ سيرفرياً (أو manual_add للإدارة فقط role≥5) — لا أحداث/قيم حرة
      //  ٢) قيمة النقاط من الكونفغ — نقاط body.points تُتجاهل لأي حدث معرّف
      let points: number;
      if (eventType === "manual_add") {
        const { data: me } = await supabaseAdmin
          .from("users").select("role").eq("id", uid).eq("i_del", 0).maybeSingle();
        if (Number((me as Record<string, unknown> | null)?.role ?? 0) < 5) {
          return json({ success: false, error: "ADMIN_ONLY_EVENT" }, 403);
        }
        points = Math.trunc(Number(body.points ?? 0));
        if (!points || Math.abs(points) > 10000) {
          return json({ success: false, error: "POINTS_INVALID" }, 400);
        }
      } else {
        const ptsMap = await loadPointsMap(supabaseAdmin);
        const cfgPts = ptsMap[eventType];
        if (cfgPts == null) {
          return json({ success: false, error: "EVENT_NOT_ALLOWED" }, 403);
        }
        if (!SELF_EVENTS.has(eventType)) {
          const { data: me } = await supabaseAdmin
            .from("users").select("role").eq("id", uid).eq("i_del", 0).maybeSingle();
          if (Number((me as Record<string, unknown> | null)?.role ?? 0) < 5) {
            return json({ success: false, error: "ADMIN_ONLY_EVENT" }, 403);
          }
        }
        points = cfgPts;
      }

      // 🚫 منع نقاط الإعجاب بالذات — السيرفر يستخرج مالك العرض بنفسه
      const awardOfferId = (body.offer_id ?? body.offerId ?? "").toString();
      if (eventType === "like" && !awardOfferId) {
        return json({ success: false, error: "OFFER_ID_REQUIRED" }, 400);
      }
      if (awardOfferId) {
        const { data: off } = await supabaseAdmin
          .from("offers")
          .select("usr_id")
          .eq("id", awardOfferId)
          .eq("i_del", 0)
          .maybeSingle();
        if (off && off.usr_id === uid) {
          return json({ success: false, error: "SELF_ACTION" }, 200);
        }
      }

      const { data, error } = await supabaseAdmin.rpc("award_points_safe", {
        p_uid: uid,
        p_event_type: eventType,
        p_points: points,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json(typeof data === "object" && data !== null ? data : { success: data === true });
    }

    if (action === "update_badge") {
      const { data, error } = await supabaseAdmin.rpc("update_user_badge", { p_uid: uid });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true });
    }

    if (action === "get_full_profile") {
      const { data, error } = await supabaseAdmin.rpc("get_user_full_by_id", { p_uid: uid });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, profile: data });
    }

    // ─── GP-001: حذف الحساب ذاتياً (شرط إلزامي في Google Play) ───
    // إقرار Data Safety المرفوع لجوجل ينصّ على «حذف الحساب من داخل التطبيق»
    // بينما الميزة لم تكن موجودة إطلاقاً — إقرار غير مطابق للواقع وسبب رفض
    // شائع. الحذف ناعم مع تعمية البيانات الشخصية: الصف يبقى لسلامة المراجع
    // (عروض · مواعيد · دفعات · صفقات تشير إليه) لكن هويته تُمحى.
    if (action === "delete_my_account") {
      // تأكيد صريح يمنع الحذف بنقرة خاطئة أو نداء عابر
      const confirm = (body.confirm ?? "").toString().trim();
      if (confirm !== "DELETE") {
        return json({
          success: false,
          error: "CONFIRMATION_REQUIRED",
          detail: "أرسل confirm=\"DELETE\" لتأكيد حذف الحساب نهائياً.",
        }, 400);
      }
      const reason = (body.reason ?? "").toString();
      const { data, error } = await supabaseAdmin.rpc("user_delete_own_account", {
        p_user_uid: uid,
        p_reason: reason,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      const res = (data ?? {}) as Record<string, unknown>;
      // الموانع تُعاد بحالة 409 لتميّزها الواجهة عن الأخطاء العامة
      if (res.success !== true) return json(res, 409);
      return json(res);
    }

    if (action === "update_profile") {
      const payload = (body.payload ?? body.p_payload) as Record<string, unknown>;
      if (!payload) return json({ success: false, error: "PAYLOAD_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("update_user_profile_internal", {
        p_user_uid: uid,
        p_payload: payload,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json(typeof data === "object" && data !== null ? data : { success: data === true });
    }

    // 🔒 رفع وثائق الهوية (رقم وطني + صورة أمامية/خلفية) عبر service_role —
    // الرفع المباشر من العميل لـ ids_private محظور بـ RLS لأن المستخدمين
    // يعملون بجلسات مخصصة (staff_session_token) لا بجلسة Supabase Auth.
    if (action === "upload_id_images") {
      const sid = (body.sid ?? "").toString().trim();
      const frontB64 = (body.front_b64 ?? body.frontBase64 ?? "").toString();
      const backB64 = (body.back_b64 ?? body.backBase64 ?? "").toString();

      if (!sid) return json({ success: false, error: "SID_REQUIRED" }, 400);
      if (sid.length > 30) return json({ success: false, error: "SID_TOO_LONG" }, 400);
      if (!frontB64 && !backB64) {
        return json({ success: false, error: "IMAGES_REQUIRED" }, 400);
      }

      // الصور الحالية — تُدمج مع الجديدة وتُحذف المستبدلة بعد النجاح
      const { data: currentUser, error: currentUserError } = await supabaseAdmin
        .from("users")
        .select("img")
        .eq("id", uid)
        .eq("i_del", 0)
        .maybeSingle();
      if (currentUserError) return json({ success: false, error: currentUserError.message }, 400);
      if (!currentUser) return json({ success: false, error: "USER_NOT_FOUND" }, 404);

      const parseImgPaths = (img: unknown): { front: string | null; back: string | null } => {
        const s = (img ?? "").toString().trim();
        if (!s) return { front: null, back: null };
        if (s.startsWith("[")) {
          try {
            const arr = JSON.parse(s);
            if (Array.isArray(arr)) {
              return {
                front: arr[0]?.toString() ?? null,
                back: arr[1]?.toString() ?? null,
              };
            }
          } catch { /* قيمة غير صالحة — نتعامل معها كمسار مفرد */ }
        }
        return { front: s, back: null };
      };
      const oldPaths = parseImgPaths(currentUser.img);

      // التأكد من وجود bucket خاص (يدرأ فشل "bucket not found" إن لم تُطبق الهجرة)
      const { error: bucketCheckError } = await supabaseAdmin.storage.getBucket("ids_private");
      if (bucketCheckError) {
        const { error: createBucketError } = await supabaseAdmin.storage.createBucket(
          "ids_private",
          { public: false },
        );
        if (createBucketError) {
          return json({ success: false, error: `BUCKET_UNAVAILABLE: ${createBucketError.message}` }, 400);
        }
      }

      const contentTypeFor = (ext: string): string =>
        ext === "png" ? "image/png" : ext === "webp" ? "image/webp" : "image/jpeg";
      const safeExt = (ext: string): string =>
        ext === "png" || ext === "webp" ? ext : "jpg";

      const uploads: Array<{ key: "front" | "back"; b64: string; ext: string }> = [];
      if (frontB64) uploads.push({ key: "front", b64: frontB64, ext: (body.front_ext ?? "jpg").toString().toLowerCase() });
      if (backB64) uploads.push({ key: "back", b64: backB64, ext: (body.back_ext ?? "jpg").toString().toLowerCase() });

      const newPaths: Record<string, string> = {};
      const ts = Date.now();
      for (const up of uploads) {
        if (up.b64.length > 14_000_000) {
          return json({ success: false, error: "IMAGE_TOO_LARGE" }, 400);
        }
        let bytes: Uint8Array;
        try {
          bytes = Uint8Array.from(atob(up.b64), (c) => c.charCodeAt(0));
        } catch {
          return json({ success: false, error: "INVALID_IMAGE_DATA" }, 400);
        }
        if (bytes.length === 0) {
          return json({ success: false, error: "EMPTY_IMAGE" }, 400);
        }
        const path = `${uid}/id_${up.key}_${ts}.${safeExt(up.ext)}`;
        const { error: uploadError } = await supabaseAdmin.storage
          .from("ids_private")
          .upload(path, bytes, {
            contentType: contentTypeFor(up.ext),
            cacheControl: "3600",
            upsert: true,
          });
        if (uploadError) {
          return json({ success: false, error: `ID_UPLOAD_FAILED: ${uploadError.message}` }, 400);
        }
        newPaths[up.key] = path;
      }

      // دمج مع المسارات القديمة — الوجه غير المُعاد رفعه يبقى كما هو
      const finalFront = newPaths.front ?? oldPaths.front;
      const finalBack = newPaths.back ?? oldPaths.back;
      const storedImg = finalFront && finalBack
        ? JSON.stringify([finalFront, finalBack])
        : (finalFront ?? finalBack ?? "");

      const { error: updateError } = await supabaseAdmin
        .from("users")
        .update({ sid, img: storedImg, ts_upd: new Date().toISOString() })
        .eq("id", uid)
        .eq("i_del", 0);
      if (updateError) {
        return json({ success: false, error: `SAVE_FAILED: ${updateError.message}` }, 400);
      }

      // حذف الصور القديمة المستبدلة بعد نجاح الحفظ
      const toDelete: string[] = [];
      if (newPaths.front && oldPaths.front && oldPaths.front !== newPaths.front) {
        toDelete.push(oldPaths.front);
      }
      if (newPaths.back && oldPaths.back && oldPaths.back !== newPaths.back) {
        toDelete.push(oldPaths.back);
      }
      if (toDelete.length > 0) {
        await supabaseAdmin.storage.from("ids_private").remove(toDelete);
      }

      return json({
        success: true,
        paths: [finalFront, finalBack].filter(Boolean),
      });
    }

    if (action === "get_device_tokens") {
      const { data, error } = await supabaseAdmin.rpc("get_user_device_tokens", { p_uid: uid });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, tokens: data ?? [] });
    }

    // تسجيل توكن FCM — استبدل الكتابة المباشرة المحظورة RLS في fcm_service (2026-07-27)
    if (action === "register_fcm_token") {
      const token = (body.device_token ?? body.deviceToken ?? body.fcm_token ?? body.fcmToken)?.toString() ?? "";
      const platform = (body.platform ?? "android").toString();
      if (!token) return json({ success: false, error: "DEVICE_TOKEN_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("register_fcm_token", {
        p_user_uid: uid,
        p_token: token,
        p_platform: platform,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    if (action === "unregister_fcm_token") {
      const token = (body.device_token ?? body.deviceToken ?? body.fcm_token ?? body.fcmToken)?.toString() ?? "";
      if (!token) return json({ success: false, error: "DEVICE_TOKEN_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("unregister_fcm_token", {
        p_user_uid: uid,
        p_token: token,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    if (action === "register_password") {
      const username = (body.username ?? "").toString();
      const password = (body.password ?? "").toString();
      if (!username || !password) return json({ success: false, error: "CREDENTIALS_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("register_password", {
        p_user_uid: uid,
        p_username: username,
        p_password: password,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json(typeof data === "object" && data !== null ? data : { success: data === true });
    }

    if (action === "change_password") {
      const oldPassword = (body.old_password ?? body.oldPassword ?? "").toString();
      const newPassword = (body.new_password ?? body.newPassword ?? "").toString();
      if (!oldPassword || !newPassword) return json({ success: false, error: "PASSWORDS_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("change_password_internal", {
        p_user_uid: uid,
        p_old_password: oldPassword,
        p_new_password: newPassword,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json(typeof data === "object" && data !== null ? data : { success: data === true });
    }

    if (action === "create_report") {
      const report = body.report as Record<string, unknown>;
      if (!report) return json({ success: false, error: "REPORT_DATA_REQUIRED" }, 400);
      const { data, error } = await supabaseAdmin.rpc("create_report_internal", {
        p_reporter_uid: uid,
        p_report: report,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, report_id: data });
    }

    if (action === "create_payment") {
      const paymentData = body.payment as Record<string, unknown>;
      if (!paymentData) return json({ success: false, error: "PAYMENT_DATA_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("create_payment_internal", {
        p_user_uid: uid,
        p_payment: paymentData,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, payment: Array.isArray(data) ? data[0] : data });
    }

    if (action === "user_payments") {
      const { data, error } = await supabaseAdmin.rpc("get_user_payments_internal", { p_user_uid: uid });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, payments: data ?? [] });
    }

    if (action === "handle_email_auth") {
      const { data, error } = await supabaseAdmin.rpc("handle_email_auth_internal");
      if (error) return json({ success: false, error: error.message }, 400);
      if (data && typeof data === "object") {
        const payload = data as Record<string, unknown>;
        return json({ ...payload, success: payload.success !== false });
      }
      return json({ success: false, error: "EMAIL_AUTH_FAILED" }, 400);
    }

    if (action === "request_verification") {
      const { data, error } = await supabaseAdmin.rpc("request_verification_by_uid", { p_user_uid: uid });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    if (action === "reset_password") {
      const newPassword = (body.new_password ?? body.newPassword ?? "").toString();
      if (!newPassword) return json({ success: false, error: "NEW_PASSWORD_REQUIRED" }, 400);

      // هذا الإجراء يفترض أن المستخدم قد تخطى للتو مرحلة الـ OTP وأثبت هويته
      const { data, error } = await supabaseAdmin.rpc("reset_password_with_otp", {
        p_user_uid: uid,
        p_new_password: newPassword,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json(typeof data === "object" && data !== null ? data : { success: data === true });
    }

    // 📡 notification_settings — بروفايل قنوات البوش + دليل التنقل «الإشعار-بلس» (2026-07-27)
    if (action === "notification_settings") {
      // دليل فقط (الدستور: لا شاشة تحتل navigate) — الزبون يحسم الURL النهائي
      const result: Record<string, unknown> = {
        success: true,
        navigate: "/user/push-channels",
        def_navigate: "/user/settings",
        push_allowed: false,
        push_allowed_by: [] as string[],
        channels: {} as Record<string, boolean>,
      };
      try {
        // «وش انوّر جرس التطبيق؟»: قبول-البوش الفعلي = جهاز نشط مسجّل عند FCM بفصيلة المنصة
        const { data: devs } = await supabaseAdmin
          .from("user_devices")
          .select("platform, is_active")
          .eq("uid", uid);
        const fams = new Set<string>();
        for (const d of (devs ?? []) as Array<Record<string, unknown>>) {
          if (d["is_active"] !== true) continue;
          const p = (d["platform"] ?? "").toString().toLowerCase();
          if (p === "android") fams.add("fam1");
          else if (p === "ios") fams.add("fam2");
          else if (p === "web") fams.add("fam0");
        }
        result.push_allowed_by = [...fams].map((f) => `${f}-device`);
        result.push_allowed = fams.size > 0;
      } catch (_) { /* تدهور رشيق — دليل التنقل يبقى صالحاً حتى لو تغيّر الجدول */ }

      // 🔧 BUG-018 (2026-08-14): قراءة القنوات المحفوظة فعلياً.
      // كان `channels` يُرجَع فارغاً **دائماً**، والشاشة تحفظ عبر
      // `internal_config` بمفتاح anon (يرفضه RLS بـ42501) وتنادي إيدج باسم
      // `user-devices` **غير موجودة أصلاً** — والخطآن مبتلعان بـcatch(_){}
      // ⇒ الشاشة تُظهر تبديل المفتاح ثم تُعيده عند أول تحديث، بلا أي رسالة.
      try {
        const { data: prefRow } = await supabaseAdmin
          .from("users").select("ntf").eq("id", uid).maybeSingle();
        const ntf = (prefRow?.ntf ?? {}) as Record<string, unknown>;
        const chans = (ntf["chn"] ?? {}) as Record<string, unknown>;
        const out: Record<string, boolean> = {};
        for (const [k, v] of Object.entries(chans)) out[k] = v === true;
        result.channels = out;
      } catch (_) { /* الافتراضي: لا قناة محجوبة */ }
      return json(result);
    }

    // ─── BUG-018: حفظ حجب/تفعيل قناة إشعارات ───
    // القناة المحجوبة تُخزَّن في users.ntf.chn.<id> = true.
    // القاعدة (كما بالواجهة): لا يجوز حجب كل القنوات — يبقى واحدة على الأقل.
    if (action === "set_push_channel") {
      const chn = Number(body.channel ?? body.chn);
      const blocked = body.blocked === true;
      if (!Number.isInteger(chn) || chn < 1 || chn > 9) {
        return json({ success: false, error: "INVALID_CHANNEL" }, 400);
      }

      const { data: row, error: readErr } = await supabaseAdmin
        .from("users").select("ntf").eq("id", uid).maybeSingle();
      if (readErr) return json({ success: false, error: readErr.message }, 400);

      const ntf = { ...((row?.ntf ?? {}) as Record<string, unknown>) };
      const chans = { ...((ntf["chn"] ?? {}) as Record<string, unknown>) };

      if (blocked) {
        // تحقّق خادمي: لا نسمح بحجب آخر قناة مفعّلة (الواجهة تفحص، والسيرفر يحسم)
        const ALL = [1, 2, 3, 4];
        const stillOn = ALL.filter((c) => c !== chn && chans[String(c)] !== true);
        if (stillOn.length === 0) {
          return json({
            success: false,
            error: "AT_LEAST_ONE_CHANNEL_REQUIRED",
            detail: "فعّل قناة أخرى قبل إيقاف هذه — لا يمكن إيقاف كل القنوات.",
          }, 400);
        }
        chans[String(chn)] = true;
      } else {
        delete chans[String(chn)];
      }
      ntf["chn"] = chans;

      const { error: upErr } = await supabaseAdmin
        .from("users").update({ ntf }).eq("id", uid);
      if (upErr) return json({ success: false, error: upErr.message }, 400);

      return json({ success: true, channels: chans });
    }

    return json({ success: false, error: "UNKNOWN_ACTION" }, 400);
  } catch (error) {
    return json({ success: false, error: error instanceof Error ? error.message : String(error) }, 500);
  }
});

// @ts-nocheck
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// ─── نقاط من الكونفغ سيرفرياً (تحصين 2026-07-27): العميل لا يقرر قيمة النقاط ───
// القيم الاحتياطية = نفس القيم الحية في app_config('main').pts وقت التحصين
const POINTS_DEFAULTS: Record<string, number> = {
  like: 5, cmt: 20, shr: 10, soc: 100, strk: 50, ref: 1500,
  wkL: 100, addO: 500, sgn: 1000, att: 300, dlD: 2000,
};
// أحداث يمنحها المستخدم لنفسه (بقية الأحداث إدارية/نظامية فقط)
const SELF_EVENTS = new Set(["like", "cmt", "shr", "soc"]);

async function loadPtsMap(
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

async function validateUser(
  req: Request,
  supabaseAdmin: ReturnType<typeof createClient>,
  requestedUid: string,
  body: Record<string, unknown> = {}
): Promise<{ ok: true; uid: string } | { ok: false; response: Response }> {
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";

  if (bearer && bearer !== "undefined" && bearer !== "null" && bearer !== "anon_key_here") {
    const { data: userData, error } = await supabaseAdmin.auth.getUser(bearer);
    const uid = userData?.user?.id;
    if (!error && uid) {
      if (requestedUid && requestedUid !== uid) {
        return {
          ok: false,
          response: new Response(
            JSON.stringify({ success: false, error: "UNAUTHORIZED_ACCESS" }),
            { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          ),
        };
      }
      return { ok: true, uid: uid };
    }
  }

  // 2. Try Custom Session Token validation (for custom password login)
  const sessionToken = (body?.staff_session_token ?? body?.staffSessionToken ?? body?.session_token ?? body?.sessionToken)?.toString()
    || (authHeader && !authHeader.startsWith("Bearer ") ? authHeader.trim() : "");
  if (sessionToken && sessionToken !== "undefined" && sessionToken !== "null" && sessionToken !== "anon_key_here") {
    const { data, error } = await supabaseAdmin.rpc("validate_staff_session", {
      p_token: sessionToken,
      p_user_uid: requestedUid,
      p_min_role: 0,
    });

    if (!error && data && data.success === true) {
      return { ok: true, uid: data.user_id };
    }
  }

  return {
    ok: false,
    response: new Response(
      JSON.stringify({ success: false, error: "AUTH_TOKEN_REQUIRED" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    ),
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const { action, user_uid, ...payload } = await req.json();

    if (!user_uid) {
      return new Response(
        JSON.stringify({ success: false, error: "MISSING_USER_UID" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const actor = await validateUser(req, supabase, user_uid, payload);
    if (!actor.ok) return actor.response;

    let result: any = { success: false };
    const offerId = (payload?.offer_id ?? payload?.offerId)?.toString() ?? "";
    let targetChecked = false;

    switch (action) {
      // ==================== DAILY STREAK ====================
      case "daily_streak": {
        const ptsMap = await loadPtsMap(supabase);
        const { data, error } = await supabase.rpc("register_daily_streak_internal", {
          p_user_uid: user_uid,
          p_points: ptsMap["strk"] ?? 50, // سيرفرياً من الكونفغ — لا قيمة من العميل
        });
        if (error) throw error;
        result = { success: true, data };
        break;
      }

      // ==================== ADD POINTS (safe) ====================
      case "award_points": {
        const event_key = (payload.event_key ?? "").toString();
        // تحصين 2026-07-27 (سد سكب النقاط):
        //  ١) الحدث لازم يكون معرّفاً بكونفغ النقاط — لا أحداث عشوائية (manual_add ومثيلاتها ممنوعة هنا)
        //  ٢) قيمة النقاط من الكونفغ سيرفرياً — قيمة العميل تُتجاهل كلياً
        //  ٣) الأحداث غير الذاتية (addO/sgn/…) للإدارة فقط (role≥5)
        const ptsMap = await loadPtsMap(supabase);
        const cfgPts = ptsMap[event_key];
        if (!event_key || cfgPts == null) {
          return new Response(
            JSON.stringify({ success: false, error: "EVENT_NOT_ALLOWED" }),
            { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
        if (!SELF_EVENTS.has(event_key)) {
          const { data: me } = await supabase
            .from("users").select("role").eq("id", user_uid).eq("i_del", 0).maybeSingle();
          if (Number((me as Record<string, any> | null)?.role ?? 0) < 5) {
            return new Response(
              JSON.stringify({ success: false, error: "ADMIN_ONLY_EVENT" }),
              { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
            );
          }
        }

        // تحصين 2026-07-26: نقاط الإعجاب بلا offer_id مرفوضة كلياً —
        // أي مسار كلاينت ناسي التمرير يُحسم هنا قبل أي منح
        if (event_key === "like" && !offerId) {
          return new Response(
            JSON.stringify({ success: false, error: "OFFER_ID_REQUIRED" }),
            { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }

        // 🚫 منع نقاط الإعجاب/المشاركة على عروضك الخاصة —
        // الكلاينت يمرر offer_id والسيرفر يقرر الملكية (لا يعتمد على بيانات العميل للملكية)
        if (!targetChecked && offerId) {
          targetChecked = true;
          const { data: off } = await supabase
            .from("offers")
            .select("usr_id")
            .eq("id", offerId)
            .eq("i_del", 0)
            .maybeSingle();
          if (off && (off as Record<string, unknown>).usr_id === user_uid) {
            return new Response(
              JSON.stringify({ success: false, error: "SELF_ACTION" }),
              { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
            );
          }
        }

        const { data, error } = await supabase.rpc("award_points_safe", {
          p_uid: user_uid,
          p_event_type: event_key,
          p_points: cfgPts, // سيرفرياً
        });
        if (error) throw error;
        // لا تغلّف بـ success:true — مرّر نتيجة الدالة كما هي (DAILY_LIMIT_REACHED وغيرها)
        // حتى لا تعرض الواجهة «+نقاط» كاذبة عند رفض السيرفر (2026-07-27)
        result = (data && typeof data === "object") ? data : { success: data === true };
        break;
      }

      // ==================== REFERRAL ====================
      case "referral": {
        const { referrer_code } = payload;
        const ptsMap = await loadPtsMap(supabase);
        const { data, error } = await supabase.rpc("apply_referral", {
          p_new_uid: user_uid,
          p_referrer_code: referrer_code,
          p_pts: ptsMap["ref"] ?? 1500, // سيرفرياً من الكونفغ
        });
        if (error) throw error;
        result = { success: true, data };
        break;
      }

      // ==================== RATING BONUS — أُزيل 2026-07-27 ====================
      // منحة الـ ٥ نجوم تُمنح من trigger جدول ratings (award_points_safe 'top_rating' +200)
      // إبقاء هذا الإجراء كان يتيح سكب +200 لأي target بلا تقييم حقيقي + يضاعف المنحة.

      default:
        return new Response(
          JSON.stringify({ success: false, error: "UNKNOWN_ACTION" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
    }

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
// Edge Function: user-offers
// الغرض: نقل عمليات إدارة العروض الخاصة بالمستخدم من RPC مباشر إلى Edge Function تتحقق من جلسة المستخدم (Auth JWT).

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

// دالة للتحقق من المستخدم الحالي عن طريق الـ JWT
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
        return { ok: false, response: json({ success: false, error: "UNAUTHORIZED_ACCESS" }, 403) };
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

    // دالة increment_offer_views قد لا تتطلب مستخدم مسجل الدخول، سنعالجها أولاً
    if (action === "increment_views") {
      const offerId = (body.offer_id ?? body.offerId)?.toString() ?? "";
      if (!offerId) return json({ success: false, error: "OFFER_ID_REQUIRED" }, 400);

      // قاعدة المالك 2026-07-26: مشاهدة المالك لعرضه لا تُحتسب.
      // لا توثيق هنا عمداً (الزوّار يُحتسبون): أسوأ استغلال ممكن هو تمرير viewer_uid
      // لشخص آخر لتخطّي عدّ مشاهدات عرضه — أي "تقليل" عداد لا نفع منه للمهاجم.
      const viewerUid = (body.viewer_uid ?? body.viewerUid)?.toString() ?? "";
      if (viewerUid) {
        const { data: offerRow } = await supabaseAdmin
          .from("offers")
          .select("usr_id")
          .eq("id", offerId)
          .eq("i_del", 0)
          .maybeSingle();
        if (offerRow && (offerRow as Record<string, unknown>).usr_id === viewerUid) {
          return json({ success: true, skipped: "OWNER_VIEW" });
        }
      }

      // 🔒 BUG-024 (2026-08-14): العدّاد كان قابلاً للتضخيم بلا أي حد —
      // عشرون نداءً متتالياً بلا مصادقة رفعوه من 9 إلى 29 (أُكِّد حياً).
      // التعليق أعلاه توقّع الاستغلال في اتجاه «التقليل» وأغفل التضخيم،
      // وهو الاتجاه المفيد فعلاً للمهاجم: صاحب عرض يجعله يبدو رائجاً،
      // والمشاهدات مؤشّر تعتمده الإدارة في التقارير.
      // الآن: نافذة تهدئة 30 دقيقة لكل (عرض + جهاز).
      const viewerKey = viewerUid ||
        (body.device_id ?? body.deviceId)?.toString() ||
        req.headers.get("x-client-info") ||
        req.headers.get("cf-connecting-ip") ||
        "anon";

      const { data, error } = await supabaseAdmin.rpc("increment_offer_view", {
        p_offer_id: offerId,
        p_viewer_key: viewerKey,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      // counted=false تعني «ضمن نافذة التهدئة» لا فشلاً — النداء ناجح.
      return json({ success: true, counted: data === true });
    }

    // الدالة check_offer_duplicate يمكن أن تكون للمستخدم أو للموظف (من شاشة الإضافة للموظف)، لكنها تحتاج توثيق
    if (action === "check_duplicate") {
      const duplicateCheckUid = (body.user_uid ?? body.userUid)?.toString() ?? "";
      const actor = await validateUser(req, supabaseAdmin, duplicateCheckUid, body);
      if (!actor.ok) return actor.response;

      const title = (body.title ?? "").toString();
      const price = Number(body.price ?? 0);
      const loc = body.loc as Record<string, unknown>;
      const usrId = (body.usr_id ?? body.usrId)?.toString() ?? actor.uid;

      const { data, error } = await supabaseAdmin.rpc("check_offer_duplicate", {
        p_ttl: title,
        p_prc: price,
        p_loc: loc,
        p_usr_id: usrId,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, is_duplicate: data === true });
    }

    // باقي الإجراءات تتطلب مستخدماً محدداً (p_user_uid)
    const requestedUid = (body.user_uid ?? body.userUid)?.toString() ?? "";
    if (!requestedUid) return json({ success: false, error: "USER_UID_REQUIRED" }, 400);

    const actor = await validateUser(req, supabaseAdmin, requestedUid, body);
    if (!actor.ok) return actor.response;
    const uid = actor.uid;

    if (action === "create_preflight") {
      const isPhotoRequest = body.photo_req === true || Number(body.photo_req ?? 0) === 1;
      if (isPhotoRequest) {
        return json({ success: true, allowed: true, used: 0, limit: 0 });
      }
      const { data: user, error: userError } = await supabaseAdmin.from("users")
        .select("role,b_pkg,pkg_end,pkg_grace,pkg_xoff,perm_boost_until")
        .eq("id", uid).eq("sts", 0).eq("i_del", 0).maybeSingle();
      if (userError || !user) return json({ success: false, error: "USER_NOT_ACTIVE_OR_NOT_FOUND" }, 404);
      if (Number(user.role) >= 4) return json({ success: true, allowed: true, used: 0, limit: 999999 });
      // 🔓 فتح السقف المؤقت (2026-09-02): طالما الفتح شغّال الحصة تتخطى
      const boostUntilMs = user.perm_boost_until
        ? new Date(String(user.perm_boost_until)).getTime() : 0;
      if (boostUntilMs > Date.now()) {
        return json({ success: true, allowed: true, used: 0, limit: 999999, boost_until: user.perm_boost_until });
      }
      const { data: cfgRow } = await supabaseAdmin.from("app_config")
        .select("value").eq("key", "main").maybeSingle();
      const cfg = cfgRow?.value as Record<string, unknown> | undefined;
      const pkg = cfg?.pkg as Record<string, Record<string, unknown>> | undefined;
      const now = Date.now();
      const activePkg = Number(user.b_pkg ?? 0) > 0 &&
        ((user.pkg_grace && new Date(String(user.pkg_grace)).getTime() > now) ||
         (user.pkg_end && new Date(String(user.pkg_end)).getTime() > now))
        ? Number(user.b_pkg) : 0;
      const baseLimit = Number(pkg?.[String(activePkg)]?.o ?? (Number(user.role) === 1 ? 5 : 1));
      const limit = baseLimit + (activePkg > 0 ? Number(user.pkg_xoff ?? 0) : 0);
      const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
      const [{ count: activeCount }, { count: deletedCount }] = await Promise.all([
        supabaseAdmin.from("offers").select("id", { count: "exact", head: true })
          .eq("usr_id", uid).eq("i_del", 0).eq("photo_req", 0).in("sts", [0, 1, 2, 5]),
        supabaseAdmin.from("offers").select("id", { count: "exact", head: true })
          .eq("usr_id", uid).eq("i_del", 1).eq("photo_req", 0).gte("ts_crt", since),
      ]);
      const used = (activeCount ?? 0) + (deletedCount ?? 0);
      if (used >= limit) return json({ success: false, allowed: false, error: "QUOTA_EXCEEDED", used, limit }, 409);
      const title = (body.title ?? "").toString().trim();
      const price = Number(body.price ?? 0);
      if (title && Number.isFinite(price)) {
        const { data: duplicate } = await supabaseAdmin.rpc("check_offer_duplicate", {
          p_ttl: title, p_prc: price, p_loc: body.loc ?? {}, p_usr_id: uid,
        });
        if (duplicate === true) return json({ success: false, allowed: false, error: "DUPLICATE_OFFER", used, limit }, 409);
      }
      return json({ success: true, allowed: true, used, limit });
    }

    if (action === "list") {
      const { data, error } = await supabaseAdmin.rpc("get_user_offers_internal", { p_user_uid: uid });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, offers: data ?? [] });
    }

    if (action === "get_by_id") {
      const offerId = (body.offer_id ?? body.offerId)?.toString() ?? "";
      if (!offerId) return json({ success: false, error: "OFFER_ID_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("get_offer_by_id_internal", {
        p_user_uid: uid,
        p_offer_id: offerId,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      if (!data || (Array.isArray(data) && data.length === 0)) {
        return json({ success: false, error: "OFFER_NOT_FOUND" }, 404);
      }
      return json({ success: true, offer: data });
    }

    if (action === "create") {
      const offer = body.offer as Record<string, unknown>;
      if (!offer) return json({ success: false, error: "OFFER_DATA_REQUIRED" }, 400);

      const isPhotoRequest = offer.photo_req === true || Number(offer.photo_req ?? 0) === 1;
      const { data, error } = await supabaseAdmin.rpc(
        isPhotoRequest ? "create_photography_request_internal" : "create_offer_internal",
        {
          p_user_uid: uid,
          p_offer: offer,
        },
      );
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, offer_id: data }); // قد يرجع ID العرض المنشأ أو true حسب تصميمك
    }

    if (action === "purchase_boost") {
      const offerId = (body.offer_id ?? body.offerId)?.toString() ?? "";
      const boostType = (body.boost_type ?? body.boostType)?.toString() ?? "";
      if (!offerId || !boostType) return json({ success: false, error: "MISSING_REQUIRED_FIELDS" }, 400);

      const { data, error } = await supabaseAdmin.rpc("purchase_offer_boost", {
        p_uid: uid,
        p_offer_id: offerId,
        p_boost_type: boostType,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      const result = (data ?? {}) as Record<string, unknown>;
      return json({ ...result, success: result.success === true });
    }

    if (action === "broker_offers") {
      const { data, error } = await supabaseAdmin.rpc("get_broker_offers_internal", { p_broker_uid: uid });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, offers: data ?? [] });
    }

    if (action === "broker_deals") {
      const { data, error } = await supabaseAdmin.rpc("get_broker_deals_internal", { p_broker_uid: uid });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, deals: data ?? [] });
    }

    if (action === "mark_social_published") {
      const offerId = (body.offer_id ?? body.offerId)?.toString() ?? "";
      const text = (body.text ?? "").toString();
      if (!offerId) return json({ success: false, error: "OFFER_ID_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("mark_social_published_internal", {
        p_user_uid: uid,
        p_offer_id: offerId,
        p_text: text,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    // ── 2026-07-27: تعديل/حذف العرض عبر الإيدج ──
    // القناة القديمة (PATCH مباشر من الكلاينت بصلاحية anon) مقفولة 42501 بعد سحب RLS،
    // فلا تعديل ولا حذف كان ينحفظ إطلاقاً — القناة الآن هنا: جلسة + ملكية + whitelist.
    if (action === "update_offer" || action === "delete_offer") {
      const offerId = (body.offer_id ?? body.offerId)?.toString() ?? "";
      if (!offerId) return json({ success: false, error: "OFFER_ID_REQUIRED" }, 400);

      const { data: offerRow, error: fErr } = await supabaseAdmin
        .from("offers")
        .select("id, usr_id, sts, i_del")
        .eq("id", offerId)
        .maybeSingle();
      if (fErr) return json({ success: false, error: fErr.message }, 400);
      if (!offerRow) return json({ success: false, error: "OFFER_NOT_FOUND" }, 404);
      const o = offerRow as Record<string, unknown>;
      if (o["i_del"] === 1) return json({ success: false, error: "OFFER_NOT_FOUND" }, 404);
      if (o["usr_id"] !== uid) return json({ success: false, error: "NOT_OFFER_OWNER" }, 403);
      const stsNow = Number(o["sts"] ?? 0);
      if (stsNow === 5 || stsNow === 6) {
        // محجوز (معاملة قيد الإتمام) أو مكتمل — نفس حارس الشاشة، مفروض سيرفرياً
        return json({ success: false, error: "OFFER_LOCKED" }, 409);
      }

      let patch: Record<string, unknown>;
      if (action === "delete_offer") {
        patch = { i_del: 1 };
      } else {
        // whitelist صارمة — لا sts/i_pub/ts_pub/i_del/usr_id/id/ts_ren من العميل إطلاقاً
        const ALLOWED = [
          "ttl", "prc", "loc", "descript", "contact_ph",
          "specs", "typ", "trx", "cur", "imgs", "avl",
        ];
        const incoming = (body.data ?? {}) as Record<string, unknown>;
        patch = {};
        for (const k of ALLOWED) {
          if (Object.prototype.hasOwnProperty.call(incoming, k)) patch[k] = incoming[k];
        }
        if (Object.keys(patch).length === 0) {
          return json({ success: false, error: "NO_VALID_FIELDS" }, 400);
        }
        // أي تعديل يعيد العرض لمسار المراجعة — يُفرض سيرفرياً (لا يقبل من العميل)
        patch["sts"] = 1;   // OfferStatus.review
        patch["i_pub"] = 0;
        patch["ts_pub"] = null;
      }

      const { error: uErr } = await supabaseAdmin
        .from("offers")
        .update(patch)
        .eq("id", offerId);
      if (uErr) return json({ success: false, error: uErr.message }, 400);
      return json({ success: true, deleted: action === "delete_offer" });
    }

    return json({ success: false, error: "UNKNOWN_ACTION" }, 400);
  } catch (error) {
    return json({ success: false, error: error instanceof Error ? error.message : String(error) }, 500);
  }
});

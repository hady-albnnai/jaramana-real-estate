// Edge Function: admin-offers — إدارة العروض + النشر التلقائي على السوشيال
// التحديث 2026-07-13: النشر التلقائي مفعّل افتراضياً (autoPublish != false).
// الترتيب الإلزامي: db push ثم secrets ثم functions deploy.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { publishOfferToSocial } from "../_shared/social_publisher.ts";

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

async function validateActor(
  req: Request,
  supabaseAdmin: ReturnType<typeof createClient>,
  body: Record<string, unknown>,
  minRole = 3,
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

  const sessionToken = (body.staff_session_token ?? body.staffSessionToken)?.toString() ?? (authHeader && !authHeader.startsWith("Bearer ") ? authHeader.trim() : "");
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
    const actor = await validateActor(req, supabaseAdmin, body, 3);
    if (!actor.ok) return actor.response;

    const adminUid = actor.adminUid;

    if (action === "create_for_user") {
      const userId = (body.user_id ?? body.userId)?.toString() ?? "";
      const offer = body.offer as Record<string, unknown>;
      if (!userId || !offer) return json({ success: false, error: "USER_ID_AND_OFFER_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("create_offer_internal", {
        p_user_uid: userId,
        p_offer: offer,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, offer_id: data });
    }

    if (action === "list_pending") {
      const { data, error } = await supabaseAdmin.rpc("get_admin_pending_offers_internal", {
        p_admin_uid: adminUid,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, offers: data ?? [] });
    }

    if (action === "list_social_queue") {
      const { data, error } = await supabaseAdmin
        .from("offers")
        .select("*")
        .eq("i_del", 0)
        .eq("sts", 2)
        .eq("i_pub", 1)
        .eq("i_soc", 1)
        .eq("soc_pub", 1)
        .order("ts_pub", { ascending: false })
        .limit(100);
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, offers: data ?? [] });
    }

    if (action === "list_media_review") {
      const limit = Number(body.limit ?? 100);
      const { data, error } = await supabaseAdmin.rpc("get_admin_offers_internal", {
        p_admin_uid: adminUid,
        p_limit: Number.isFinite(limit) ? Math.min(Math.max(limit, 1), 200) : 100,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, offers: data ?? [] });
    }

    if (action === "review") {
      const offerId = (body.offer_id ?? body.offerId)?.toString() ?? "";
      const approve = body.approve === true;
      const reason = (body.reason ?? "").toString();
      if (!offerId) return json({ success: false, error: "OFFER_ID_REQUIRED" }, 400);

      // 1. تنفيذ المراجعة العادية (sts=2 + i_pub=1)
      const { data, error } = await supabaseAdmin.rpc("admin_review_offer_internal", {
        p_admin_uid: adminUid,
        p_offer_id: offerId,
        p_approve: approve,
        p_reject_reason: reason,
      });
      if (error) return json({ success: false, error: error.message }, 400);

      // العرض الناتج عن طلب تصوير صار هنا عرضاً عادياً بالكامل. بعد قرار
      // المراجعة نغلق مهمة التصوير أيضاً؛ الصور رُبطت ذرياً وقت تسليم المصوّر.
      if (data === true) {
        await supabaseAdmin
          .from("photography_tasks")
          .update({
            sts: 3,
            office_note: approve ? "تمت مراجعة العرض ونشره" : `اكتمل التصوير ورُفض العرض: ${reason}`,
            ts_done: new Date().toISOString(),
            ts_upd: new Date().toISOString(),
          })
          .eq("off_id", offerId)
          .eq("sts", 2);
      }

      let socialPublishResult: Record<string, unknown> | null = null;
      if (approve && data === true) {
        try {
          const { data: offerRow } = await supabaseAdmin
            .from('offers')
            .select('i_soc, soc_txt, usr_id, imgs')
            .eq('id', offerId)
            .single();

          const iSoc = (offerRow?.i_soc ?? 0) as number;
          const socTxt = ((offerRow?.soc_txt as string) ?? '').trim();
          const ownerUid = (offerRow?.usr_id as string) ?? '';

          if (iSoc === 1 && socTxt.length > 10) {
            // علم أن العرض جاهز للنشر الاجتماعي (soc_pub = 1)
            await supabaseAdmin
              .from('offers')
              .update({ soc_pub: 1 })
              .eq('id', offerId);

            // منح نقاط النشر الاجتماعي
            if (ownerUid) {
              try {
                await supabaseAdmin.rpc('award_points_safe', {
                  p_user_uid: ownerUid,
                  p_event_type: 'soc',
                  p_points: 100,
                });
              } catch (_) {}
            }

            // سجل جدولة
            try {
              await supabaseAdmin.rpc('log_admin_action', {
                p_admin_uid: adminUid,
                p_act: 105,
                p_det: 'تم تفعيل النشر التلقائي على السوشيال (i_soc=1) - مجدول',
                p_ref_id: offerId,
                p_ref_col: 'offers',
              });
            } catch (_) {}

            // قراءة إعداد الوضع التلقائي — افتراضي true منذ 2026-07-13
            const { data: configRow } = await supabaseAdmin
              .from('app_config')
              .select('value')
              .eq('key', 'main')
              .single();
            const configValue = (configRow?.value ?? {}) as Record<string, unknown>;
            const socialConfig = (configValue.socialPublishing ?? {}) as Record<string, unknown>;
            const autoPublishEnabled = socialConfig.autoPublish !== false; // true افتراضياً

            if (autoPublishEnabled) {
              const result = await publishOfferToSocial(supabaseAdmin, offerId) as unknown as Record<string, unknown>;
              socialPublishResult = result;

              // سجل نتيجة النشر التلقائي
              try {
                const success = result.success === true;
                await supabaseAdmin.rpc('log_admin_action', {
                  p_admin_uid: adminUid,
                  p_act: success ? 106 : 107,
                  p_det: success
                    ? '✅ تم النشر التلقائي الفوري على فيسبوك وإنستغرام بعد الموافقة'
                    : `⚠️ فشل النشر التلقائي بعد الموافقة: ${(result.error as string) ?? 'UNKNOWN'} — سيبقى في قائمة الجاهزة`,
                  p_ref_id: offerId,
                  p_ref_col: 'offers',
                });
              } catch (_) {}
            } else {
              socialPublishResult = {
                success: false,
                queued: true,
                error: 'AUTO_PUBLISH_DISABLED',
                message: 'الوضع التلقائي معطل — تمت جدولة العرض فقط',
              };
            }
          }
        } catch (socialError) {
          socialPublishResult = {
            success: false,
            error: socialError instanceof Error ? socialError.message : String(socialError),
          };
        }
      }

      return json({ success: data === true, social_publish: socialPublishResult });
    }

    if (action === "set_priority") {
      const offerId = (body.offer_id ?? body.offerId)?.toString() ?? "";
      const priorityType = (body.priority_type ?? body.priorityType ?? "normal").toString();
      const durationDays = Number(body.duration_days ?? body.durationDays ?? 30);
      if (!offerId) return json({ success: false, error: "OFFER_ID_REQUIRED" }, 400);
      if (!["pin", "fms", "bst", "normal"].includes(priorityType)) {
        return json({ success: false, error: "INVALID_PRIORITY_TYPE" }, 400);
      }
      const { data, error } = await supabaseAdmin.rpc("admin_set_offer_priority_internal", {
        p_admin_uid: adminUid,
        p_offer_id: offerId,
        p_priority_type: priorityType,
        p_duration_days: Number.isFinite(durationDays) ? Math.min(Math.max(durationDays, 1), 365) : 30,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    if (action === "set_video_flag") {
      // 🎥 علامة «فيديو متوفر» (واتساب المكتب) — ميزة الفيديو 2026-07-27
      const offerId = (body.offer_id ?? body.offerId)?.toString() ?? "";
      const hasVideo = body.has_video === true || body.hasVideo === true;
      if (!offerId) return json({ success: false, error: "OFFER_ID_REQUIRED" }, 400);
      const { data, error } = await supabaseAdmin.rpc("admin_set_offer_video", {
        p_admin_uid: adminUid,
        p_offer_id: offerId,
        p_has_video: hasVideo,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    if (action === "delete") {
      const offerId = (body.offer_id ?? body.offerId)?.toString() ?? "";
      if (!offerId) return json({ success: false, error: "OFFER_ID_REQUIRED" }, 400);
      const { data, error } = await supabaseAdmin.rpc("admin_delete_offer_internal", {
        p_admin_uid: adminUid,
        p_offer_id: offerId,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    return json({ success: false, error: "UNKNOWN_ACTION" }, 400);
  } catch (error) {
    return json({ success: false, error: error instanceof Error ? error.message : String(error) }, 500);
  }
});

// Edge Function: photographer-tasks
// الغرض: نقل مهام المصور من RPC مباشر إلى Edge Function تتحقق من جلسة الموظف.

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

// إشعار داخلي + 🔔 بوش خارجي (ثانوي — فشله لا يكسر العملية)
// أُضيف 2026-07-28: مسار المصوّر كان صامتاً تماماً (بدء/تسليم بلا أي إشعار).
async function notifyUsers(
  supabaseAdmin: ReturnType<typeof createClient>,
  uids: string[],
  tp: number,
  ttl: string,
  bdy: string,
  refId: string,
  act: string,
): Promise<void> {
  const unique = [...new Set(uids.filter((u) => !!u))];
  if (unique.length === 0) return;
  try {
    const rows = unique.map((uid) => ({
      uid,
      tp,
      ttl,
      bdy,
      ref_id: refId,
      act,
      i_rd: 0,
      i_del: 0,
      ts_crt: new Date().toISOString(),
    }));
    await supabaseAdmin.from("notifications").insert(rows);
  } catch {
    // تجاهل — الإشعار إجراء ثانوي
  }
  for (const uid of unique) {
    try {
      await supabaseAdmin.rpc("send_push_notification", {
        p_uid: uid,
        p_title: ttl,
        p_body: bdy,
        p_data: { act, ref_id: refId },
      });
    } catch {
      // تجاهل — البوش إجراء ثانوي
    }
  }
}

async function validateActor(
  req: Request,
  supabaseAdmin: ReturnType<typeof createClient>,
  body: Record<string, unknown>,
  minRole = 2, // دور المصور أو أعلى
): Promise<{ ok: true; uid: string; role: number } | { ok: false; response: Response }> {
  const requestedUid = (body.user_uid ?? body.userUid ?? body.admin_uid ?? body.adminUid ?? body.user_id ?? body.userId)?.toString() ?? "";
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";

  if (bearer && bearer !== "undefined" && bearer !== "null" && bearer !== "anon_key_here") {
    const { data: userData } = await supabaseAdmin.auth.getUser(bearer);
    const uid = userData?.user?.id;
    if (uid && (!requestedUid || requestedUid === uid)) {
      const { data: userRow, error } = await supabaseAdmin
        .from("users")
        .select("id, role, sts, i_del")
        .eq("id", uid)
        .eq("i_del", 0)
        .single();

      if (!error && userRow && userRow.sts === 0 && Number(userRow.role) >= minRole) {
        return { ok: true, uid: uid, role: Number(userRow.role) };
      }
    }
  }

  const sessionToken = (body.staff_session_token ?? body.staffSessionToken)?.toString() ?? (authHeader && !authHeader.startsWith("Bearer ") ? authHeader.trim() : "");
  if (!requestedUid || !sessionToken) {
    return { ok: false, response: json({ success: false, error: "STAFF_SESSION_REQUIRED" }, 401) };
  }

  const { data, error } = await supabaseAdmin.rpc("validate_staff_session", {
    p_user_uid: requestedUid,
    p_token: sessionToken,
    p_min_role: minRole,
  });

  if (error || data?.success !== true) {
    return {
      ok: false,
      response: json({ success: false, error: data?.error ?? error?.message ?? "INVALID_STAFF_SESSION" }, 401),
    };
  }

  return { ok: true, uid: requestedUid, role: Number(data.role) };
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
    const actor = await validateActor(req, supabaseAdmin, body, 2);
    if (!actor.ok) return actor.response;

    const uid = actor.uid;

    if (action === "list") {
      const { data, error } = await supabaseAdmin.rpc("get_photographer_tasks_internal", { p_photographer_uid: uid });
      if (error) return json({ success: false, error: error.message }, 400);

      // المهمة الخام لا تحمل إلا عنواناً وموقعاً مختصراً؛ نضيف للمصور كل ما
      // يحتاجه للوصول والتنفيذ من العرض وصاحب الطلب، بعد حصر الصفوف به عبر RPC.
      const tasks = data ?? [];
      const offerIds = [...new Set(tasks.map((t) => t.off_id?.toString() ?? "").filter(Boolean))];
      const requesterIds = [...new Set(tasks.map((t) => t.requested_by?.toString() ?? "").filter(Boolean))];
      const offersById = new Map<string, Record<string, unknown>>();
      const requestersById = new Map<string, { name: string; phone: string }>();

      if (offerIds.length > 0) {
        const { data: offers } = await supabaseAdmin
          .from("offers")
          .select("id, ttl, typ, trx, cat, sub, prc, cur, loc, descript, specs, avl, contact_ph, doc_tp, sts, photo_req")
          .in("id", offerIds);
        for (const offer of offers ?? []) offersById.set(offer.id.toString(), offer);
      }
      if (requesterIds.length > 0) {
        const { data: requesters } = await supabaseAdmin
          .from("users")
          .select("id, nm, ph")
          .in("id", requesterIds)
          .eq("i_del", 0);
        for (const requester of requesters ?? []) {
          requestersById.set(requester.id.toString(), {
            name: requester.nm?.toString() ?? "",
            phone: requester.ph?.toString() ?? "",
          });
        }
      }

      const enriched = tasks.map((task) => {
        const offer = offersById.get(task.off_id?.toString() ?? "");
        const requester = requestersById.get(task.requested_by?.toString() ?? "");
        return {
          ...task,
          offer_details: offer ?? {},
          is_photo_request: Number(offer?.photo_req ?? 0) === 1,
          offer_sts: offer?.sts ?? null,
          requester_name: requester?.name ?? "",
          requester_phone: requester?.phone ?? "",
        };
      });
      return json({ success: true, tasks: enriched });
    }

    // ─── تعديل الموعد مباشرة من المصور — قرار المالك 2026-08-17 ───
    if (action === "reschedule") {
      const taskId = (body.task_id ?? body.taskId)?.toString() ?? "";
      const scheduledAt = (body.ts_scheduled ?? body.scheduled_at)?.toString() ?? "";
      if (!taskId || !scheduledAt) {
        return json({ success: false, error: "TASK_AND_SCHEDULE_REQUIRED" }, 400);
      }
      const when = new Date(scheduledAt);
      if (isNaN(when.getTime())) {
        return json({ success: false, error: "INVALID_SCHEDULE_DATE" }, 400);
      }
      if (when.getTime() < Date.now() - 5 * 60 * 1000) {
        return json({ success: false, error: "SCHEDULE_IN_THE_PAST" }, 400);
      }

      const { error: conflictError } = await supabaseAdmin.rpc("assert_photographer_free", {
        p_photographer_uid: uid,
        p_dt: scheduledAt,
        p_exclude_task: taskId,
      });
      if (conflictError) {
        const message = conflictError.message ?? "";
        if (message.includes("PHOTOGRAPHER_TIME_CONFLICT")) {
          return json({
            success: false,
            error: "PHOTOGRAPHER_TIME_CONFLICT",
            detail: "لديك مهمة أخرى قريبة من هذا الموعد — اختر وقتاً آخر.",
          }, 409);
        }
        return json({ success: false, error: message }, 400);
      }

      const { data: task, error } = await supabaseAdmin
        .from("photography_tasks")
        .update({ ts_scheduled: scheduledAt, rmnd_1h: 0, ts_upd: new Date().toISOString() })
        .eq("id", taskId)
        .eq("photographer_id", uid)
        .in("sts", [0, 1, 4])
        .select("id, ttl, requested_by, ts_scheduled")
        .maybeSingle();
      if (error) return json({ success: false, error: error.message }, 400);
      if (!task) return json({ success: false, error: "TASK_NOT_FOUND_OR_NOT_ALLOWED" }, 404);

      const whenText = new Intl.DateTimeFormat("ar-SY", {
        timeZone: "Asia/Damascus",
        year: "numeric", month: "2-digit", day: "2-digit",
        hour: "2-digit", minute: "2-digit", hour12: false,
      }).format(when);
      const requester = task.requested_by?.toString() ?? "";
      if (requester) {
        await notifyUsers(
          supabaseAdmin,
          [requester],
          1,
          "📅 تم تعديل موعد التصوير",
          `حدد المصوّر موعد تصوير «${task.ttl ?? ""}» بتاريخ ${whenText}.`,
          taskId,
          "photography_schedule_changed",
        );
      }
      const { data: staff } = await supabaseAdmin
        .from("users").select("id").gte("role", 3).lte("role", 6).eq("sts", 0).eq("i_del", 0);
      if (staff && staff.length > 0) {
        await notifyUsers(
          supabaseAdmin,
          staff.map((s) => s.id?.toString() ?? ""),
          1,
          "📅 المصوّر عدّل موعد مهمة",
          `موعد «${task.ttl ?? ""}» أصبح ${whenText}.`,
          taskId,
          "photography_schedule_changed_staff",
        );
      }
      return json({ success: true, task });
    }

    // ─── Action: decline — اعتذار المصوّر عن مهمة (2026-07-30) ───
    // كان المصوّر لا يملك أي مخرج: بس list/start/submit. لو مرض أو تعذّر وصوله
    // تبقى المهمة مسكّرة عليه والمكتب لا يعلم. الآن يعتذر بسبب، فترجع المهمة
    // لطابور المكتب (sts=0 بلا مصوّر) ويُشعَر المكتب فوراً لإعادة الإسناد.
    if (action === "decline") {
      const taskId = (body.task_id ?? body.taskId)?.toString() ?? "";
      const reason = (body.reason ?? body.decline_reason ?? "").toString().trim();
      if (!taskId) return json({ success: false, error: "TASK_ID_REQUIRED" }, 400);
      if (!reason) return json({ success: false, error: "DECLINE_REASON_REQUIRED" }, 400);

      // الملكية + الحالة يُفرضان بالاستعلام نفسه: مهامه هو فقط، وغير المسلّمة
      const { data: task, error } = await supabaseAdmin
        .from("photography_tasks")
        .update({
          photographer_id: null,
          sts: 0,
          ts_scheduled: null,
          office_note: `اعتذار المصوّر: ${reason}`,
          ts_upd: new Date().toISOString(),
        })
        .eq("id", taskId)
        .eq("photographer_id", uid)
        .in("sts", [0, 1, 4])
        .select("id, ttl, requested_by")
        .maybeSingle();
      if (error) return json({ success: false, error: error.message }, 400);
      if (!task) return json({ success: false, error: "TASK_NOT_FOUND_OR_NOT_ALLOWED" }, 400);

      const { data: me } = await supabaseAdmin
        .from("users").select("nm").eq("id", uid).maybeSingle();
      const { data: staff } = await supabaseAdmin
        .from("users").select("id").gte("role", 3).lte("role", 6).eq("sts", 0).eq("i_del", 0);
      if (staff && staff.length > 0) {
        await notifyUsers(
          supabaseAdmin,
          staff.map((s) => s.id?.toString() ?? ""),
          1,
          "🔄 اعتذار مصوّر عن مهمة",
          [
            `اعتذر ${me?.nm ?? "المصوّر"} عن مهمة: ${task.ttl ?? ""}`,
            `السبب: ${reason}`,
            "المهمة رجعت لقائمة الانتظار — يرجى إسناد مصوّر آخر.",
          ].join("\n"),
          taskId,
          "photography_task_declined",
        );
      }
      return json({ success: true });
    }

    if (action === "start") {
      const taskId = (body.task_id ?? body.taskId)?.toString() ?? "";
      if (!taskId) return json({ success: false, error: "TASK_ID_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("start_photography_task_internal", {
        p_photographer_uid: uid,
        p_task_id: taskId,
      });
      if (error) return json({ success: false, error: error.message }, 400);

      // 🔔 إشعار صاحب الطلب ببدء التنفيذ (كان معدوماً — فجوة 2026-07-28)
      if (data === true) {
        const { data: task } = await supabaseAdmin
          .from("photography_tasks")
          .select("id, ttl, requested_by")
          .eq("id", taskId)
          .maybeSingle();
        const reqUid = task?.requested_by?.toString() ?? "";
        if (reqUid) {
          const { data: ph } = await supabaseAdmin
            .from("users").select("nm, ph").eq("id", uid).maybeSingle();
          await notifyUsers(
            supabaseAdmin,
            [reqUid],
            1,
            "📸 المصوّر بدأ تنفيذ طلبك",
            [
              `بدأ العمل على طلب التصوير: ${task?.ttl ?? ""}`,
              `👤 المصوّر: ${ph?.nm ?? "—"}${ph?.ph ? ` — ${ph.ph}` : ""}`,
            ].join("\n"),
            taskId,
            "photography_task_started",
          );
        }
      }
      return json({ success: data === true });
    }

    if (action === "submit") {
      const taskId = (body.task_id ?? body.taskId)?.toString() ?? "";
      const media = body.media as string[];
      const note = (body.photographer_note ?? body.photographerNote ?? "").toString();
      
      if (!taskId || !Array.isArray(media)) {
        return json({ success: false, error: "INVALID_REQUEST_DATA" }, 400);
      }

      // 🔒 BUG-014 (2026-08-14): `Array.isArray([])` تنجح على المصفوفة الفارغة
      // ⇒ كان المصوّر يستطيع «تسليم» مهمة **بصفر صور**، فتنتقل إلى «بانتظار
      // المراجعة» ثم تُعتمد، ويُغلق الطلب بلا أي وسائط. أُكِّد حياً: تسليم
      // بـ`media:[]` أعاد success:true والحالة صارت 2 والوسائط [].
      // والأسوأ: بعدها يُرفض التسليم الصحيح بـTASK_NOT_FOUND_OR_NOT_ALLOWED
      // لأن الحالة لم تعد 1 ⇒ المصوّر يفقد مهمته بلا رجعة.
      const cleanMedia = media
        .map((m) => String(m ?? "").trim())
        .filter((m) => m.length > 0);
      if (cleanMedia.length === 0) {
        return json({
          success: false,
          error: "MEDIA_REQUIRED",
          detail: "لا يمكن تسليم مهمة تصوير بلا صور — أرفق صورة واحدة على الأقل.",
        }, 400);
      }

      const { data, error } = await supabaseAdmin.rpc("submit_photography_task_internal", {
        p_photographer_uid: uid,
        p_task_id: taskId,
        p_media: cleanMedia,
        p_photographer_note: note,
      });
      if (error) return json({ success: false, error: error.message }, 400);

      // 🔔 إشعار المكتب بوصول صور للمراجعة (كان معدوماً — صور تنتظر بلا علم أحد)
      if (data === true) {
        const { data: task } = await supabaseAdmin
          .from("photography_tasks")
          .select("id, off_id, ttl, requested_by")
          .eq("id", taskId)
          .maybeSingle();
        const offerId = task?.off_id?.toString() ?? "";
        let isUserPhotoOffer = false;
        if (offerId) {
          const { data: offer } = await supabaseAdmin
            .from("offers")
            .select("photo_req, sts")
            .eq("id", offerId)
            .maybeSingle();
          // الـ RPC الذرية تنقل مسودة طلب التصوير إلى المراجعة عند التسليم.
          isUserPhotoOffer = Number(offer?.photo_req ?? 0) === 1 && Number(offer?.sts ?? -1) === 1;
        }
        const { data: staff } = await supabaseAdmin
          .from("users").select("id").gte("role", 3).lte("role", 6).eq("sts", 0).eq("i_del", 0);
        if (staff && staff.length > 0) {
          await notifyUsers(
            supabaseAdmin,
            staff.map((s) => s.id?.toString() ?? ""),
            1,
            isUserPhotoOffer ? "🆕 عرض جديد بانتظار المراجعة" : "📥 صور جاهزة للمراجعة",
            isUserPhotoOffer
              ? `اكتمل تصوير العرض: ${task?.ttl ?? ""} — أُرفقت ${cleanMedia.length} وسائط وأصبح العرض جاهزاً للمراجعة.`
              : `سلّم المصوّر ${cleanMedia.length} وسائط للمهمة: ${task?.ttl ?? ""} — بانتظار اعتماد التصوير.`,
            isUserPhotoOffer ? offerId : taskId,
            isUserPhotoOffer ? "offer" : "photography_task_submitted",
          );
        }
        // وإعلام صاحب الطلب أن التصوير انتهى ودخل المراجعة
        const reqUid = task?.requested_by?.toString() ?? "";
        if (reqUid) {
          await notifyUsers(
            supabaseAdmin,
            [reqUid],
            1,
            "📸 انتهى التصوير",
            `تم رفع صور طلبك (${task?.ttl ?? ""}) وهي قيد مراجعة المكتب — سنعلمك فور اعتمادها.`,
            taskId,
            "photography_task_submitted_client",
          );
        }
      }
      return json({ success: data === true });
    }

    return json({ success: false, error: "UNKNOWN_ACTION" }, 400);
  } catch (error) {
    return json({ success: false, error: error instanceof Error ? error.message : String(error) }, 500);
  }
});

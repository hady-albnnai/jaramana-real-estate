// Edge Function: legal-actions
// الغرض: نقطة الوصول الآمنة لعمليات القسم القانوني وتعقيب المعاملات ومسارات المحامين والمعقبين.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type SupabaseAdmin = ReturnType<typeof createClient>;

function env(name: string, fallback?: string): string {
  return Deno.env.get(name) ?? (fallback ? Deno.env.get(fallback) ?? "" : "");
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function base64ToUint8Array(base64: string): Uint8Array {
  const clean = base64.includes(",") ? base64.split(",").pop() ?? "" : base64;
  const binary = atob(clean);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function safeImageContentType(value: unknown): string {
  const contentType = typeof value === "string" ? value.toLowerCase() : "image/jpeg";
  return ["image/jpeg", "image/jpg", "image/png", "image/webp"].includes(contentType)
    ? (contentType === "image/jpg" ? "image/jpeg" : contentType)
    : "image/jpeg";
}

function safeStorageName(value: string): string {
  return value.replace(/[^a-zA-Z0-9_.-]/g, "_").slice(0, 80) || "item";
}

async function signExpeditingTaskAttachments(
  supabaseAdmin: SupabaseAdmin,
  tasks: unknown,
): Promise<unknown[]> {
  const list = Array.isArray(tasks) ? tasks : [];
  const result: unknown[] = [];
  for (const rawTask of list) {
    const task = rawTask && typeof rawTask === "object" ? { ...(rawTask as Record<string, unknown>) } : rawTask;
    if (!task || typeof task !== "object") {
      result.push(task);
      continue;
    }
    const record = task as Record<string, unknown>;
    const checklist = Array.isArray(record.checklist) ? record.checklist : [];
    record.checklist = await Promise.all(checklist.map(async (rawItem) => {
      const item = rawItem && typeof rawItem === "object" ? { ...(rawItem as Record<string, unknown>) } : rawItem;
      if (!item || typeof item !== "object") return item;
      const itemRecord = item as Record<string, unknown>;
      const path = (itemRecord.attachment_url ?? "").toString();
      if (path && !path.startsWith("http")) {
        const { data } = await supabaseAdmin.storage
          .from("expediting_docs")
          .createSignedUrl(path, 3600);
        if (data?.signedUrl) itemRecord.attachment_signed_url = data.signedUrl;
      }
      return itemRecord;
    }));
    result.push(record);
  }
  return result;
}

async function getUserRole(
  supabaseAdmin: SupabaseAdmin,
  uid: string,
): Promise<number | null> {
  const { data, error } = await supabaseAdmin
    .from("users")
    .select("role, sts, i_del")
    .eq("id", uid)
    .eq("i_del", 0)
    .single();

  if (error || !data || Number(data.sts) !== 0) return null;
  return Number(data.role);
}

function canManageLawyerProfiles(role: number): boolean {
  // الإدارة العليا فقط: نائب مدير ومدير. لا يدخل lawyer=7 أو expediter=8 في صلاحيات الإدارة.
  return role === 5 || role === 6;
}

function isLawyer(role: number): boolean {
  return role === 7;
}

function isExpediter(role: number): boolean {
  return role === 8;
}

async function validateUser(
  req: Request,
  supabaseAdmin: SupabaseAdmin,
  requestedUid: string,
  body: Record<string, unknown> = {},
): Promise<{ ok: true; uid: string; role: number } | { ok: false; response: Response }> {
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";

  if (bearer && bearer !== "undefined" && bearer !== "null" && bearer !== "anon_key_here") {
    const { data: userData, error } = await supabaseAdmin.auth.getUser(bearer);
    const uid = userData?.user?.id;
    if (!error && uid) {
      if (requestedUid && requestedUid !== uid) {
        return { ok: false, response: json({ success: false, error: "UNAUTHORIZED_ACCESS" }, 403) };
      }
      const role = await getUserRole(supabaseAdmin, uid);
      if (role == null) {
        return { ok: false, response: json({ success: false, error: "USER_INACTIVE" }, 401) };
      }
      return { ok: true, uid, role };
    }
  }

  const sessionToken = (body?.staff_session_token ?? body?.staffSessionToken ?? body?.session_token ?? body?.sessionToken)?.toString()
    || (authHeader && !authHeader.startsWith("Bearer ") ? authHeader.trim() : "");

  if (sessionToken && sessionToken !== "anon_key_here" && sessionToken !== "undefined" && sessionToken !== "null") {
    const { data, error } = await supabaseAdmin.rpc("validate_staff_session", {
      p_token: sessionToken,
      p_user_uid: requestedUid,
      p_min_role: 0,
    });

    if (!error && data && data.success === true) {
      return { ok: true, uid: data.user_id, role: Number(data.role) };
    }
  }

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
    const requestedUid = (body.user_uid ?? body.userUid ?? body.admin_uid ?? body.adminUid)?.toString() ?? "";

    if (!requestedUid) return json({ success: false, error: "USER_UID_REQUIRED" }, 400);

    const actor = await validateUser(req, supabaseAdmin, requestedUid, body);
    if (!actor.ok) return actor.response;
    const uid = actor.uid;
    const role = actor.role;

    // ─── المحامين النشطين (إخفاء واتساب عن المستخدم العادي) ───
    if (action === "get_active_lawyers") {
      const { data, error } = await supabaseAdmin.rpc("get_active_lawyers");
      if (error) return json({ success: false, error: error.message }, 400);
      const lawyers = (data ?? []) as Record<string, unknown>[];
      // 🔒 إخفاء واتساب والعنوان عن المستخدم العادي (يظهر فقط للمحامي/الإدارة)
      const hidePrivate = !isLawyer(role) && !canManageLawyerProfiles(role);
      const safeLawyers = hidePrivate
        ? lawyers.map((l) => {
            const safe = { ...l };
            delete safe.whatsapp_phone;
            delete safe.office_address;
            return safe;
          })
        : lawyers;
      return json({ success: true, lawyers: safeLawyers });
    }

    if (action === "admin_upsert_lawyer") {
      const targetUid = (body.target_uid ?? body.targetUid)?.toString() ?? "";
      const whatsapp = (body.whatsapp_phone ?? body.whatsappPhone)?.toString() ?? "";
      const address = (body.office_address ?? body.officeAddress ?? "").toString();
      const spec = (body.specialization ?? "عقارات وسيارات").toString();
      const avl = body.avl ?? {};

      if (!targetUid || !whatsapp) return json({ success: false, error: "MISSING_REQUIRED_FIELDS" }, 400);
      if (targetUid !== uid && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }
      if (targetUid === uid && !isLawyer(role) && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }

      const { data, error } = await supabaseAdmin.rpc("admin_upsert_lawyer_profile", {
        p_admin_uid: uid,
        p_target_uid: targetUid,
        p_whatsapp: whatsapp,
        p_address: address,
        p_spec: spec,
        p_avl: avl,
      });

      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    if (action === "update_checklist_item") {
      if (!isLawyer(role) && !isExpediter(role) && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }

      const taskId = (body.task_id ?? body.taskId)?.toString() ?? "";
      const itemKey = (body.item_key ?? body.itemKey)?.toString() ?? "";
      const status = Number(body.status ?? 0);
      const inputValue = (body.input_value ?? body.inputValue ?? "").toString();
      let attachmentUrl = (body.attachment_url ?? body.attachmentUrl ?? "").toString();
      const attachmentBase64 = (body.attachment_base64 ?? body.attachmentBase64 ?? "").toString();
      const notes = (body.notes ?? "").toString();

      if (!taskId || !itemKey) return json({ success: false, error: "TASK_ID_AND_ITEM_KEY_REQUIRED" }, 400);

      const { data: taskRow, error: taskError } = await supabaseAdmin
        .from("expediting_tasks")
        .select("id, lawyer_uid, expediter_uid")
        .eq("id", taskId)
        .single();
      if (taskError || !taskRow) return json({ success: false, error: "TASK_NOT_FOUND" }, 404);
      if (taskRow.lawyer_uid !== uid && taskRow.expediter_uid !== uid && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }

      if (attachmentBase64) {
        const contentType = safeImageContentType(body.attachment_content_type ?? body.attachmentContentType);
        const ext = contentType === "image/png" ? "png" : contentType === "image/webp" ? "webp" : "jpg";
        const bytes = base64ToUint8Array(attachmentBase64);
        if (bytes.length > 8 * 1024 * 1024) return json({ success: false, error: "ATTACHMENT_TOO_LARGE" }, 413);
        const path = `${taskId}/${safeStorageName(itemKey)}_${Date.now()}.${ext}`;
        const { error: uploadError } = await supabaseAdmin.storage
          .from("expediting_docs")
          .upload(path, bytes, { contentType, cacheControl: "3600", upsert: true });
        if (uploadError) return json({ success: false, error: `ATTACHMENT_UPLOAD_FAILED: ${uploadError.message}` }, 400);
        attachmentUrl = path;
      }

      const { data: updateResult, error } = await supabaseAdmin.rpc("update_expediting_checklist_item", {
        p_actor_uid: uid,
        p_task_id: taskId,
        p_item_key: itemKey,
        p_status: status,
        p_input_value: inputValue,
        p_attachment_url: attachmentUrl,
        p_notes: notes,
      });

      if (error) return json({ success: false, error: error.message }, 400);

      // 🔔 إشعار المحامي عند تحديث بند (إذا المعقّب هو من حدّث)
      if (isExpediter(role)) {
        const { data: taskRow } = await supabaseAdmin
          .from("expediting_tasks")
          .select("lawyer_uid, target_property_num")
          .eq("id", taskId)
          .maybeSingle();
        const lawyerToNotify = taskRow?.lawyer_uid?.toString() ?? "";
        if (lawyerToNotify) {
          const statusLabels: Record<number, string> = { 0: "مطلوب", 1: "قيد الاستخراج", 2: "تم الاستخراج ✅", 3: "عائق إداري ⚠️" };
          const sLabel = statusLabels[status] ?? "تحديث";
          const ref = taskRow?.target_property_num ? ` (${taskRow.target_property_num})` : "";
          await supabaseAdmin.from("notifications").insert({
            uid: lawyerToNotify, tp: 2, ttl: "📋 تحديث على مهمة تعقيب",
            bdy: `المعقّب حدّث بند "${itemKey}" → ${sLabel}${ref}`,
            ref_id: taskId, act: "expediting_item_updated", i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
          });
          try {
            await supabaseAdmin.rpc("send_push_notification", {
              p_uid: lawyerToNotify, p_title: "📋 تحديث مهمة تعقيب",
              p_body: `${itemKey} → ${sLabel}`,
              p_data: { act: "expediting_item_updated", ref_id: taskId },
            });
          } catch { /* non-critical */ }
        }
      }

      return json(updateResult as Record<string, unknown>);
    }

    if (action === "get_lawyer_profile") {
      if (!isLawyer(role)) return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      const { data, error } = await supabaseAdmin.rpc("get_lawyer_profile", {
        p_lawyer_uid: uid,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, profile: data });
    }

    if (action === "get_available_expediters") {
      if (!isLawyer(role) && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }
      const { data, error } = await supabaseAdmin.rpc("get_available_expediters");
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, expediters: data ?? [] });
    }

    // ─── إنشاء مهمة تعقيب (محامي + إدارة + فحص تكرار) ───
    if (action === "create_expediting_task") {
      if (!isLawyer(role) && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }
      const expediterUid = (body.expediter_uid ?? body.expediterUid)?.toString() ?? "";
      const itemType = Number(body.item_type ?? body.itemType ?? 0);
      const propNum = (body.target_property_num ?? "").toString();
      const zone = (body.target_zone ?? "").toString();
      const notes = (body.lawyer_notes ?? body.notes ?? "").toString();
      const checklist = body.checklist ?? [];

      if (!expediterUid) return json({ success: false, error: "EXPEDITER_UID_REQUIRED" }, 400);

      // 🔒 فحص التكرار: نفس المعقّب + نفس رقم العقار + مهمة نشطة
      if (propNum) {
        const { data: dupes } = await supabaseAdmin
          .from("expediting_tasks")
          .select("id")
          .eq("expediter_uid", expediterUid)
          .eq("target_property_num", propNum)
          .in("status", [0, 1])
          .limit(1);
        if (dupes && dupes.length > 0) {
          return json({ success: false, error: "DUPLICATE_TASK_EXISTS", message: "يوجد مهمة نشطة لنفس المعقّب ونفس الرقم" }, 409);
        }
      }

      // المحامي = المستخدم الحالي (محامي) أو محامي مُحدد (إدارة) أو أول محامي متاح
      let lawyerUid = isLawyer(role) ? uid : ((body.lawyer_uid ?? body.lawyerUid)?.toString() ?? "");
      if (!lawyerUid && canManageLawyerProfiles(role)) {
        // الإدارة ما حددت محامي → أسند لأول محامي متاح (role=7 فقط)
        const { data: firstLawyer } = await supabaseAdmin
          .from("lawyer_profiles")
          .select("uid, users!inner(role)")
          .eq("is_active", true)
          .eq("users.role", 7)
          .limit(1);
        lawyerUid = firstLawyer?.[0]?.uid?.toString() ?? "";
        if (!lawyerUid) {
          return json({ success: false, error: "NO_ACTIVE_LAWYERS", message: "لا يوجد محامون نشطون" }, 400);
        }
      }
      if (!lawyerUid) lawyerUid = uid;

      const { data, error } = await supabaseAdmin.rpc("create_expediting_task_internal", {
        p_lawyer_uid: lawyerUid,
        p_expediter_uid: expediterUid,
        p_item_type: itemType,
        p_target_property_num: propNum,
        p_target_zone: zone,
        p_lawyer_notes: notes,
        p_checklist: checklist,
      });
      if (error) return json({ success: false, error: error.message }, 400);

      // 🔔 إشعار المعقّب بمهمة تعقيب جديدة
      const taskResult = data as Record<string, unknown>;
      const newTaskId = taskResult?.task_id?.toString() ?? "";
      if (newTaskId) {
        const itemLabel = itemType === 0 ? "عقار" : "سيارة";
        const refLabel = propNum ? ` — ${propNum}` : "";
        await supabaseAdmin.from("notifications").insert({
          uid: expediterUid, tp: 2, ttl: "🏃 مهمة تعقيب جديدة",
          bdy: `كلّفك المحامي بمهمة استخراج ثبوتيات ${itemLabel}${refLabel} — ${zone || ""} (${(checklist as unknown[]).length} وثائق)`,
          ref_id: newTaskId, act: "expediting_task_assigned", i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: expediterUid, p_title: "🏃 مهمة تعقيب جديدة",
            p_body: `${itemLabel}${refLabel} — ${(checklist as unknown[]).length} وثائق`,
            p_data: { act: "expediting_task_assigned", ref_id: newTaskId },
          });
        } catch { /* non-critical */ }
      }

      return json(data as Record<string, unknown>);
    }

    if (action === "complete_expediting_task") {
      if (!isExpediter(role)) return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      const taskId = (body.task_id ?? body.taskId)?.toString() ?? "";
      const notes = (body.expediter_notes ?? body.notes ?? "").toString();
      if (!taskId) return json({ success: false, error: "TASK_ID_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("complete_expediting_task_internal", {
        p_expediter_uid: uid,
        p_task_id: taskId,
        p_notes: notes,
      });
      if (error) return json({ success: false, error: error.message }, 400);

      // 🔔 إشعار المحامي بأن المهمة اكتملت وبانتظار المراجعة
      const { data: taskRow } = await supabaseAdmin
        .from("expediting_tasks")
        .select("lawyer_uid, target_property_num, target_zone")
        .eq("id", taskId)
        .maybeSingle();
      const lawyerToNotify = taskRow?.lawyer_uid?.toString() ?? "";
      if (lawyerToNotify) {
        const ref = taskRow?.target_property_num ? ` — ${taskRow.target_property_num}` : "";
        const zoneTxt = taskRow?.target_zone ? ` (${taskRow.target_zone})` : "";
        await supabaseAdmin.from("notifications").insert({
          uid: lawyerToNotify, tp: 2, ttl: "✅ مهمة تعقيب مكتملة — بانتظار المراجعة",
          bdy: `أنهى المعقّب مهمة الاستخراج${ref}${zoneTxt} — راجع الوثائق واعتمد المهمة أو اطلب إعادة.`,
          ref_id: taskId, act: "expediting_task_completed", i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: lawyerToNotify, p_title: "✅ مهمة تعقيب مكتملة",
            p_body: `بانتظار مراجعتك${ref}`,
            p_data: { act: "expediting_task_completed", ref_id: taskId },
          });
        } catch { /* non-critical */ }
      }

      return json(data as Record<string, unknown>);
    }

    if (action === "request_checklist_revision") {
      if (!isLawyer(role) && !canManageLawyerProfiles(role)) return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      const taskId = (body.task_id ?? body.taskId)?.toString() ?? "";
      const itemKey = (body.item_key ?? body.itemKey)?.toString() ?? "";
      const revisionNotes = (body.revision_notes ?? body.revisionNotes ?? body.notes ?? "").toString();
      if (!taskId || !itemKey) return json({ success: false, error: "TASK_ID_AND_ITEM_KEY_REQUIRED" }, 400);

      // الإدارة: نستخدم lawyer_uid الحقيقي للمهمة
      let effectiveLawyerUid = uid;
      if (canManageLawyerProfiles(role) && !isLawyer(role)) {
        const { data: taskRow } = await supabaseAdmin
          .from("expediting_tasks").select("lawyer_uid").eq("id", taskId).maybeSingle();
        effectiveLawyerUid = taskRow?.lawyer_uid?.toString() ?? uid;
      }

      const { data, error } = await supabaseAdmin.rpc("request_expediting_item_revision_internal", {
        p_lawyer_uid: effectiveLawyerUid,
        p_task_id: taskId,
        p_item_key: itemKey,
        p_revision_notes: revisionNotes,
      });
      if (error) return json({ success: false, error: error.message }, 400);

      // 🔔 إشعار المعقّب بطلب إعادة وثيقة
      const { data: taskRow } = await supabaseAdmin
        .from("expediting_tasks")
        .select("expediter_uid, target_property_num")
        .eq("id", taskId)
        .maybeSingle();
      const expediterToNotify = taskRow?.expediter_uid?.toString() ?? "";
      if (expediterToNotify) {
        const ref = taskRow?.target_property_num ? ` (${taskRow.target_property_num})` : "";
        await supabaseAdmin.from("notifications").insert({
          uid: expediterToNotify, tp: 2, ttl: "🔄 طلب إعادة وثيقة",
          bdy: `المحامي طلب إعادة "${itemKey}"${ref} — السبب: ${revisionNotes || "يرجى المراجعة"}`,
          ref_id: taskId, act: "expediting_revision_requested", i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: expediterToNotify, p_title: "🔄 طلب إعادة وثيقة",
            p_body: `${itemKey} — ${revisionNotes?.slice(0, 60) || "يرجى المراجعة"}`,
            p_data: { act: "expediting_revision_requested", ref_id: taskId },
          });
        } catch { /* non-critical */ }
      }

      return json(data as Record<string, unknown>);
    }

    if (action === "approve_expediting_task") {
      if (!isLawyer(role) && !canManageLawyerProfiles(role)) return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      const taskId = (body.task_id ?? body.taskId)?.toString() ?? "";
      if (!taskId) return json({ success: false, error: "TASK_ID_REQUIRED" }, 400);

      // الإدارة: نستخدم lawyer_uid الحقيقي للمهمة (مش uid الأدمن)
      let effectiveLawyerUid = uid;
      if (canManageLawyerProfiles(role) && !isLawyer(role)) {
        const { data: taskRow } = await supabaseAdmin
          .from("expediting_tasks").select("lawyer_uid").eq("id", taskId).maybeSingle();
        effectiveLawyerUid = taskRow?.lawyer_uid?.toString() ?? uid;
      }

      const { data, error } = await supabaseAdmin.rpc("approve_expediting_task_internal", {
        p_lawyer_uid: effectiveLawyerUid,
        p_task_id: taskId,
      });
      if (error) return json({ success: false, error: error.message }, 400);

      // 🔔 إشعار المعقّب باعتماد المهمة
      const { data: taskRow2 } = await supabaseAdmin
        .from("expediting_tasks")
        .select("expediter_uid, target_property_num, target_zone")
        .eq("id", taskId)
        .maybeSingle();
      const expediterToNotify2 = taskRow2?.expediter_uid?.toString() ?? "";
      if (expediterToNotify2) {
        const ref = taskRow2?.target_property_num ? ` — ${taskRow2.target_property_num}` : "";
        const zoneTxt = taskRow2?.target_zone ? ` (${taskRow2.target_zone})` : "";
        await supabaseAdmin.from("notifications").insert({
          uid: expediterToNotify2, tp: 2, ttl: "🎉 تم اعتماد مهمة التعقيب",
          bdy: `اعتمد المحامي مهمة الاستخراج${ref}${zoneTxt} — أحسنت!`,
          ref_id: taskId, act: "expediting_task_approved", i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: expediterToNotify2, p_title: "🎉 تم اعتماد مهمتك",
            p_body: `مهمة الاستخراج${ref} — معتمدة`,
            p_data: { act: "expediting_task_approved", ref_id: taskId },
          });
        } catch { /* non-critical */ }
      }

      return json(data as Record<string, unknown>);
    }

    // ─── مهام التعقيب (محامي + إدارة) ───
    if (action === "get_lawyer_expediting_tasks") {
      if (!isLawyer(role) && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }
      // الإدارة تشوف كل المهام، المحامي يشوف مهامه فقط
      const lawyerFilter = isLawyer(role) ? uid : ((body.lawyer_uid ?? body.lawyerUid)?.toString() ?? "");
      if (canManageLawyerProfiles(role) && !lawyerFilter) {
        // جلب كل المهام للإدارة
        const { data, error } = await supabaseAdmin
          .from("expediting_tasks")
          .select("*")
          .order("created_at", { ascending: false })
          .limit(100);
        if (error) return json({ success: false, error: error.message }, 400);
        const signedTasks = await signExpeditingTaskAttachments(supabaseAdmin, data ?? []);
        return json({ success: true, tasks: signedTasks });
      }
      const { data, error } = await supabaseAdmin.rpc("get_lawyer_expediting_tasks", {
        p_lawyer_uid: lawyerFilter || uid,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      const signedTasks = await signExpeditingTaskAttachments(supabaseAdmin, data ?? []);
      return json({ success: true, tasks: signedTasks });
    }

    if (action === "get_lawyer_appointments") {
      if (!isLawyer(role)) return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      const { data, error } = await supabaseAdmin.rpc("get_lawyer_appointments", {
        p_lawyer_uid: uid,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, appointments: data ?? [] });
    }

    if (action === "get_my_expediting_tasks") {
      if (!isExpediter(role)) return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      const { data, error } = await supabaseAdmin.rpc("get_my_expediting_tasks", {
        p_expediter_uid: uid,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      const signedTasks = await signExpeditingTaskAttachments(supabaseAdmin, data ?? []);
      return json({ success: true, tasks: signedTasks });
    }

    // ─── حجز استشارة قانونية (من المستخدم العادي) ───
    if (action === "book_consultation") {
      const serviceType = Number(body.service_type ?? 0);
      const subject = (body.subject ?? "").toString().trim();
      const price = Number(body.price ?? 0);
      const attachments = Array.isArray(body.attachments) ? body.attachments.map(String) : [];
      if (!subject) return json({ success: false, error: "SUBJECT_REQUIRED" }, 400);
      if (serviceType < 0 || serviceType > 1) return json({ success: false, error: "INVALID_SERVICE_TYPE" }, 400);

      // الأسعار الرسمية: 0=هاتفية 500, 1=حضورية 2000
      const officialPrices: Record<number, number> = { 0: 500, 1: 2000 };
      const expectedPrice = officialPrices[serviceType] ?? 0;
      if (price !== expectedPrice) return json({ success: false, error: "INVALID_PRICE", expected: expectedPrice }, 400);

      // لا حد أقصى للمحادثات — المستخدم يقدر يحجز استشارات جديدة بحرية

      const { data, error } = await supabaseAdmin.rpc("create_legal_consultation_internal", {
        p_user_uid: uid,
        p_service_type: serviceType,
        p_subject: subject,
        p_price: price,
      });
      if (error) return json({ success: false, error: error.message }, 400);

      const consultation = Array.isArray(data) ? data[0] : data;
      const consultId = consultation?.id?.toString() ?? "";

      // تحديد lawyer_alias (محامي المكتب الأول/الثاني/الثالث)
      const lawyerUid = consultation?.lawyer_uid?.toString() ?? "";
      let lawyerAlias = "محامي المكتب";
      if (lawyerUid) {
        const { count: lawyerOrder } = await supabaseAdmin
          .from("lawyer_profiles").select("*", { count: "exact", head: true })
          .eq("is_active", true)
          .lte("created_at", (consultation as Record<string, unknown>)?.created_at ?? new Date().toISOString());
        const orderNum = (lawyerOrder ?? 1);
        const arabicOrdinals = ["", "الأول", "الثاني", "الثالث", "الرابع", "الخامس"];
        lawyerAlias = `محامي المكتب ${arabicOrdinals[orderNum] ?? orderNum}`;
        // حفظ alias و attachments
        await supabaseAdmin.from("legal_consultations").update({
          lawyer_alias: lawyerAlias,
          attachments: attachments.length > 0 ? attachments : undefined,
        }).eq("id", consultId);
      } else if (attachments.length > 0) {
        await supabaseAdmin.from("legal_consultations").update({
          attachments,
        }).eq("id", consultId);
      }

      // 🔔 إشعار المحامي المُسند (إن وُجد)
      if (lawyerUid) {
        const serviceNames = ["استشارة هاتفية", "جلسة مكتبية"];
        const sName = serviceNames[serviceType] ?? "استشارة قانونية";
        const { data: userData } = await supabaseAdmin
          .from("users").select("nm").eq("id", uid).maybeSingle();
        const clientName = userData?.nm?.toString() ?? "عميل";
        await supabaseAdmin.from("notifications").insert({
          uid: lawyerUid, tp: 1, ttl: "⚖️ حجز استشارة قانونية جديد",
          bdy: `${clientName} حجز ${sName} — الموضوع: ${subject.slice(0, 100)}`,
          ref_id: consultId, act: "legal_consultation_new", i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: lawyerUid, p_title: "⚖️ استشارة قانونية جديدة",
            p_body: `${clientName} — ${sName}`,
            p_data: { act: "legal_consultation_new", ref_id: consultId },
          });
        } catch { /* push failure is non-critical */ }
      }

      // 🔔 إشعار الإدارة (role >= 5)
      const { data: admins } = await supabaseAdmin
        .from("users").select("id").gte("role", 5).eq("sts", 0).eq("i_del", 0);
      if (admins && admins.length > 0) {
        const { data: userData } = await supabaseAdmin
          .from("users").select("nm").eq("id", uid).maybeSingle();
        const clientName = userData?.nm?.toString() ?? "عميل";
        await supabaseAdmin.from("notifications").insert(
          admins.map((a: Record<string, unknown>) => ({
            uid: a.id, tp: 1, ttl: "⚖️ طلب استشارة قانونية",
            bdy: `${clientName} حجز استشارة قانونية — بانتظار التأكيد`,
            ref_id: consultId, act: "legal_consultation_admin", i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
          }))
        );
        // Push للإدارة
        for (const admin of admins) {
          try {
            await supabaseAdmin.rpc("send_push_notification", {
              p_uid: admin.id, p_title: "⚖️ طلب استشارة جديد",
              p_body: "بانتظار تأكيد المحامي",
              p_data: { act: "legal_consultation_admin", ref_id: consultId },
            });
          } catch {}
        }
      }

      // 📊 تحديث active_tasks_count للمحامي المُسند
      if (lawyerUid) {
        await supabaseAdmin.rpc("update_lawyer_active_tasks", { p_lawyer_uid: lawyerUid });
      }

      return json({ success: true, consultation_id: consultId, lawyer_assigned: !!lawyerUid });
    }

    // ─── قائمة استشاراتي (للمستخدم العادي) ───
    if (action === "list_my_consultations") {
      const { data, error } = await supabaseAdmin
        .from("legal_consultations")
        .select("*")
        .eq("user_uid", uid)
        .eq("i_del", 0)
        .order("ts_crt", { ascending: false });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, consultations: data ?? [] });
    }

    // ─── استشارات المحامي (محامي: خاصة به — إدارة: الكل) ───
    if (action === "get_lawyer_consultations") {
      if (!isLawyer(role) && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }
      let query = supabaseAdmin
        .from("legal_consultations")
        .select("*, client_nm:users!user_uid(nm)")
        .eq("i_del", 0)
        .order("ts_crt", { ascending: false });
      // المحامي يشوف استشاراته فقط، الإدارة تشوف الكل
      if (isLawyer(role) && !canManageLawyerProfiles(role)) {
        query = query.eq("lawyer_uid", uid);
      }
      const { data, error } = await query;
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, consultations: data ?? [] });
    }

    // ─── تحديث حالة الاستشارة (محامي/أدمن/المستخدم يلغي) ───
    if (action === "update_consultation_status") {
      const consultId = (body.consultation_id ?? body.consultationId)?.toString() ?? "";
      const newStatus = Number(body.status ?? 0);
      const updateNotes = (body.notes ?? "").toString();
      if (!consultId) return json({ success: false, error: "CONSULTATION_ID_REQUIRED" }, 400);

      const { data: row, error: fetchErr } = await supabaseAdmin
        .from("legal_consultations")
        .select("id, user_uid, lawyer_uid, service_type, subject, status")
        .eq("id", consultId)
        .eq("i_del", 0)
        .maybeSingle();
      if (fetchErr || !row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);

      const currentStatus = Number(row.status ?? 0);
      const isOwner = row.user_uid === uid;
      const isAssignedLawyer = isLawyer(role) && row.lawyer_uid === uid;
      const isAdmin = canManageLawyerProfiles(role);

      // 🔒 الصلاحيات:
      // - المستخدم: يقدر يلغي استشارته فقط (status=0 → 3)
      // - المحامي المُسند: يؤكد/يتمم/يرفض/يلغي
      // - الإدارة: كل شي
      if (isOwner && !isAssignedLawyer && !isAdmin) {
        // المستخدم العادي — يسمح فقط بالإلغاء (0 → 3)
        if (currentStatus !== 0 || newStatus !== 3) {
          return json({ success: false, error: "USER_CAN_ONLY_CANCEL_PENDING" }, 403);
        }
      } else if (!isAssignedLawyer && !isAdmin) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }

      // 🔒 حماية انتقالات الحالة — منع تغيير حالة مكتملة/ملغاة/مرفوضة
      const allowedTransitions: Record<number, number[]> = {
        0: [1, 3, 4], // بانتظار → مؤكد / ملغي / مرفوض
        1: [2, 3],    // مؤكد → مكتمل / ملغي
        2: [],         // مكتمل → لا شيء (نهائية)
        3: [],         // ملغي → لا شيء (نهائية)
        4: [],         // مرفوض → لا شيء (نهائية)
      };
      const allowed = allowedTransitions[currentStatus] ?? [];
      if (!allowed.includes(newStatus)) {
        const statusNames: Record<number, string> = { 0: "بانتظار", 1: "مؤكدة", 2: "مكتملة", 3: "ملغاة", 4: "مرفوضة" };
        return json({
          success: false,
          error: `INVALID_STATUS_TRANSITION`,
          message: `لا يمكن تغيير الاستشارة من "${statusNames[currentStatus] ?? currentStatus}" إلى "${statusNames[newStatus] ?? newStatus}"`,
        }, 409);
      }

      const { error: updErr } = await supabaseAdmin
        .from("legal_consultations")
        .update({ status: newStatus, notes: updateNotes || undefined, ts_upd: new Date().toISOString() })
        .eq("id", consultId);
      if (updErr) return json({ success: false, error: updErr.message }, 400);

      // 🔔 إشعار المستخدم بتحديث الحالة
      const statusLabels: Record<number, string> = { 1: "تم تأكيد", 2: "تم إتمام", 3: "تم إلغاء", 4: "تم رفض" };
      const label = statusLabels[newStatus] ?? "تم تحديث";
      const serviceNames = ["استشارة هاتفية", "جلسة مكتبية", "باقة توثيق شامل"];
      const sName = serviceNames[Number(row.service_type)] ?? "استشارة قانونية";
      const userUid = row.user_uid?.toString() ?? "";

      // 📊 تحديث active_tasks_count عند انتقال لحالة نهائية (2,3,4)
      if ([2, 3, 4].includes(newStatus) && [0, 1].includes(currentStatus)) {
        const lawyerToUpdate = row.lawyer_uid?.toString() ?? "";
        if (lawyerToUpdate) {
          await supabaseAdmin.rpc("update_lawyer_active_tasks", { p_lawyer_uid: lawyerToUpdate });
        }
      }

      if (userUid) {
        await supabaseAdmin.from("notifications").insert({
          uid: userUid, tp: 1, ttl: `⚖️ ${label} الاستشارة القانونية`,
          bdy: `${label} ${sName} — ${row.subject?.toString().slice(0, 80) ?? ""}${updateNotes ? " — " + updateNotes : ""}`,
          ref_id: consultId, act: "legal_consultation_update", i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: userUid, p_title: `⚖️ ${label} استشارتك القانونية`,
            p_body: sName,
            p_data: { act: "legal_consultation_update", ref_id: consultId },
          });
        } catch { /* push failure is non-critical */ }
      }

      return json({ success: true });
    }

    // ─── فتح المحادثة (المحامي يضغط "بدء المحادثة") ───
    if (action === "start_chat") {
      const consultId = (body.consultation_id ?? body.consultationId)?.toString() ?? "";
      if (!consultId) return json({ success: false, error: "CONSULTATION_ID_REQUIRED" }, 400);

      const { data: row } = await supabaseAdmin
        .from("legal_consultations")
        .select("id, user_uid, lawyer_uid, status, chat_started_at")
        .eq("id", consultId).eq("i_del", 0).maybeSingle();
      if (!row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);

      // فقط المحامي المُسند أو الإدارة يفتح المحادثة
      if (isLawyer(role) && row.lawyer_uid !== uid && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_ASSIGNED_LAWYER" }, 403);
      }
      if (Number(row.status) !== 1) return json({ success: false, error: "CONSULTATION_NOT_CONFIRMED" }, 400);
      if (row.chat_started_at) return json({ success: false, error: "CHAT_ALREADY_STARTED" }, 400);

      const now = new Date().toISOString();
      await supabaseAdmin.from("legal_consultations").update({
        chat_started_at: now, status: 1,
      }).eq("id", consultId);

      // رسالة system
      await supabaseAdmin.from("consultation_chats").insert({
        consultation_id: consultId, sender_id: uid,
        message_type: "system", content: "بدأت المحادثة — لديك 15 دقيقة للاستشارة",
      });

      // إشعار الطالب
      if (row.user_uid) {
        await supabaseAdmin.from("notifications").insert({
          uid: row.user_uid, tp: 1, ttl: "💬 المحامي فتح المحادثة",
          bdy: "يمكنك الآن بدء الاستشارة القانونية — لديك 15 دقيقة",
          ref_id: consultId, act: "chat_started", i_rd: 0, i_del: 0, ts_crt: now,
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: row.user_uid, p_title: "💬 المحادثة مفتوحة",
            p_body: "ابدأ استشارتك القانونية الآن",
            p_data: { act: "chat_started", ref_id: consultId },
          });
        } catch {}
      }

      return json({ success: true, chat_started_at: now });
    }

    // ─── إرسال رسالة في المحادثة ───
    if (action === "send_chat_message") {
      const consultId = (body.consultation_id ?? body.consultationId)?.toString() ?? "";
      const messageType = (body.message_type ?? "text").toString();
      const content = (body.content ?? "").toString().trim();
      const fileUrl = (body.file_url ?? "").toString();
      const fileName = (body.file_name ?? "").toString();
      const durationSeconds = body.duration_seconds ? Number(body.duration_seconds) : null;

      if (!consultId) return json({ success: false, error: "CONSULTATION_ID_REQUIRED" }, 400);
      if (messageType === "text" && !content) return json({ success: false, error: "CONTENT_REQUIRED" }, 400);

      const { data: row } = await supabaseAdmin
        .from("legal_consultations")
        .select("id, user_uid, lawyer_uid, chat_started_at, chat_duration_minutes, status")
        .eq("id", consultId).eq("i_del", 0).maybeSingle();
      if (!row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);

      // التحقق: المستخدم أو المحامي المُسند فقط
      const isStudent = row.user_uid === uid;
      const isAssignedLawyer = isLawyer(role) && row.lawyer_uid === uid;
      const isAdminUser = canManageLawyerProfiles(role);
      if (!isStudent && !isAssignedLawyer && !isAdminUser) {
        return json({ success: false, error: "NOT_PARTICIPANT" }, 403);
      }

      // التحقق: المحادثة مفتوحة (لا نقفل تلقائياً — المستخدم يجدد بالدفع)
      if (!row.chat_started_at) return json({ success: false, error: "CHAT_NOT_STARTED" }, 400);
      
      // التحقق: المحادثة لم تتجاوز 7 أيام
      const startedAt = new Date(row.chat_started_at).getTime();
      const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
      if (Date.now() > startedAt + sevenDaysMs) {
        return json({ success: false, error: "CHAT_EXPIRED_7DAYS", message: "انتهت صلاحية المحادثة (7 أيام)" }, 400);
      }

      // حفظ الرسالة
      const { data: msg, error: insertErr } = await supabaseAdmin
        .from("consultation_chats").insert({
          consultation_id: consultId, sender_id: uid,
          message_type: messageType, content,
          file_url: fileUrl || null, file_name: fileName || null,
          duration_seconds: durationSeconds,
        }).select().single();
      if (insertErr) return json({ success: false, error: insertErr.message }, 400);

      // إشعار الطرف الآخر
      const recipientUid = isStudent ? row.lawyer_uid : row.user_uid;
      if (recipientUid) {
        // 🔒 حماية الخصوصية: لا نعرض محتوى الرسالة في Push (يظهر على شاشة القفل)
        const inAppPreview = messageType === "text" ? content.slice(0, 50) : messageType === "voice" ? "🎤 رسالة صوتية" : "📎 صورة";
        await supabaseAdmin.from("notifications").insert({
          uid: recipientUid, tp: 1, ttl: "💬 رسالة جديدة",
          bdy: inAppPreview, ref_id: consultId, act: "chat_message", i_rd: 0, i_del: 0,
          ts_crt: new Date().toISOString(),
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: recipientUid, p_title: "💬 رسالة جديدة",
            p_body: "لديك رسالة جديدة في الاستشارة القانونية",
            p_data: { act: "chat_message", ref_id: consultId },
          });
        } catch {}
      }

      return json({ success: true, message: msg });
    }

    // ─── جلب رسائل المحادثة ───
    if (action === "get_chat_messages") {
      const consultId = (body.consultation_id ?? body.consultationId)?.toString() ?? "";
      if (!consultId) return json({ success: false, error: "CONSULTATION_ID_REQUIRED" }, 400);

      const { data: row } = await supabaseAdmin
        .from("legal_consultations")
        .select("id, user_uid, lawyer_uid, chat_started_at, chat_duration_minutes, extended, status, lawyer_alias")
        .eq("id", consultId).eq("i_del", 0).maybeSingle();
      if (!row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);

      // التحقق: المشارك فقط
      const isStudent = row.user_uid === uid;
      const isAssignedLawyer = isLawyer(role) && row.lawyer_uid === uid;
      const isAdminUser = canManageLawyerProfiles(role);
      if (!isStudent && !isAssignedLawyer && !isAdminUser) {
        return json({ success: false, error: "NOT_PARTICIPANT" }, 403);
      }

      const { data: messages, error: msgErr } = await supabaseAdmin
        .from("consultation_chats")
        .select("*")
        .eq("consultation_id", consultId)
        .eq("i_del", 0)
        .order("ts_crt", { ascending: true });
      if (msgErr) return json({ success: false, error: msgErr.message }, 400);

      // توقيع روابط الملفات
      const signedMessages = await Promise.all((messages ?? []).map(async (m: Record<string, unknown>) => {
        const msg = { ...m };
        const fileUrl = (msg.file_url ?? "").toString();
        if (fileUrl && !fileUrl.startsWith("http")) {
          const { data } = await supabaseAdmin.storage
            .from("consultation_files").createSignedUrl(fileUrl, 3600);
          if (data?.signedUrl) msg.file_signed_url = data.signedUrl;
        }
        return msg;
      }));

      // تحديد الرسائل غير المقروءة كمقروءة (للطرف الآخر)
      const otherUid = isStudent ? row.lawyer_uid : row.user_uid;
      if (otherUid) {
        await supabaseAdmin.from("consultation_chats")
          .update({ is_read: true })
          .eq("consultation_id", consultId)
          .eq("is_read", false)
          .neq("sender_id", uid);
      }

      // حساب الوقت المتبقي
      let remainingSeconds = 0;
      let chatExpired = false;
      if (row.chat_started_at) {
        const startedAt = new Date(row.chat_started_at).getTime();
        const durationMs = (Number(row.chat_duration_minutes) || 15) * 60 * 1000;
        const elapsed = Date.now() - startedAt;
        remainingSeconds = Math.max(0, Math.floor((durationMs - elapsed) / 1000));
        chatExpired = elapsed > durationMs;
      }

      return json({
        success: true,
        messages: signedMessages,
        chat_info: {
          chat_started_at: row.chat_started_at,
          chat_duration_minutes: row.chat_duration_minutes,
          extended: row.extended,
          remaining_seconds: remainingSeconds,
          chat_expired: chatExpired,
          lawyer_alias: row.lawyer_alias ?? "محامي المكتب",
          status: row.status,
        },
      });
    }

    // ─── تمديد المحادثة (5 دقائق — مرة واحدة فقط) ───
    if (action === "extend_chat") {
      const consultId = (body.consultation_id ?? body.consultationId)?.toString() ?? "";
      if (!consultId) return json({ success: false, error: "CONSULTATION_ID_REQUIRED" }, 400);

      const { data: row } = await supabaseAdmin
        .from("legal_consultations")
        .select("id, user_uid, lawyer_uid, extended, chat_duration_minutes, chat_started_at")
        .eq("id", consultId).eq("i_del", 0).maybeSingle();
      if (!row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);

      // فقط المحامي المُسند يمدد
      if (isLawyer(role) && row.lawyer_uid !== uid && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_ASSIGNED_LAWYER" }, 403);
      }
      if (row.extended) return json({ success: false, error: "ALREADY_EXTENDED" }, 400);
      if (!row.chat_started_at) return json({ success: false, error: "CHAT_NOT_STARTED" }, 400);

      const newDuration = (Number(row.chat_duration_minutes) || 15) + 5;
      await supabaseAdmin.from("legal_consultations").update({
        extended: true, extended_by: uid, chat_duration_minutes: newDuration,
      }).eq("id", consultId);

      // رسالة system
      await supabaseAdmin.from("consultation_chats").insert({
        consultation_id: consultId, sender_id: uid,
        message_type: "system", content: "⏱️ تم تمديد المحادثة 5 دقائق إضافية",
      });

      // إشعار الطالب
      if (row.user_uid) {
        await supabaseAdmin.from("notifications").insert({
          uid: row.user_uid, tp: 1, ttl: "⏱️ تم تمديد المحادثة",
          bdy: "المحامي مدّد المحادثة 5 دقائق إضافية",
          ref_id: consultId, act: "chat_extended", i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: row.user_uid, p_title: "⏱️ تمديد المحادثة",
            p_body: "5 دقائق إضافية",
            p_data: { act: "chat_extended", ref_id: consultId },
          });
        } catch {}
      }

      return json({ success: true, new_duration: newDuration });
    }

    // ─── تقييم الاستشارة ───
    if (action === "rate_consultation") {
      const consultId = (body.consultation_id ?? body.consultationId)?.toString() ?? "";
      const rating = Number(body.rating ?? 0);
      const comment = (body.comment ?? "").toString().trim();

      if (!consultId) return json({ success: false, error: "CONSULTATION_ID_REQUIRED" }, 400);
      if (rating < 1 || rating > 5) return json({ success: false, error: "INVALID_RATING" }, 400);

      const { data: row } = await supabaseAdmin
        .from("legal_consultations")
        .select("id, user_uid, rating")
        .eq("id", consultId).eq("i_del", 0).maybeSingle();
      if (!row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);

      // فقط صاحب الاستشارة يقيّم
      if (row.user_uid !== uid) return json({ success: false, error: "NOT_OWNER" }, 403);
      if (row.rating) return json({ success: false, error: "ALREADY_RATED" }, 400);

      await supabaseAdmin.from("legal_consultations").update({
        rating, rating_comment: comment || null,
      }).eq("id", consultId);

      return json({ success: true });
    }

    // ─── إعادة تفعيل الاستشارة (بعد عدم رد المحامي) ───
    if (action === "reactivate_consultation") {
      const consultId = (body.consultation_id ?? body.consultationId)?.toString() ?? "";
      if (!consultId) return json({ success: false, error: "CONSULTATION_ID_REQUIRED" }, 400);

      const { data: row } = await supabaseAdmin
        .from("legal_consultations")
        .select("id, user_uid, lawyer_uid, status, ts_crt, reactivate_count")
        .eq("id", consultId).eq("i_del", 0).maybeSingle();
      if (!row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);

      if (row.user_uid !== uid) return json({ success: false, error: "NOT_OWNER" }, 403);
      if (Number(row.status) !== 0) return json({ success: false, error: "NOT_PENDING" }, 400);

      // التحقق: مرّت ساعة على الأقل
      const createdAt = new Date(row.ts_crt).getTime();
      const hoursPassed = (Date.now() - createdAt) / (1000 * 60 * 60);
      if (hoursPassed < 1) return json({ success: false, error: "TOO_EARLY", hours_remaining: Math.ceil(1 - hoursPassed) }, 400);

      const now = new Date().toISOString();
      const newCount = (Number(row.reactivate_count) || 0) + 1;
      await supabaseAdmin.from("legal_consultations").update({
        reactivate_count: newCount, last_reactivate_at: now,
      }).eq("id", consultId);

      // إشعار المحامي
      if (row.lawyer_uid) {
        await supabaseAdmin.from("notifications").insert({
          uid: row.lawyer_uid, tp: 1, ttl: "🔔 إعادة تفعيل استشارة",
          bdy: `المستخدم أعاد تفعيل طلب الاستشارة (المرة ${newCount})`,
          ref_id: consultId, act: "consultation_reactivated", i_rd: 0, i_del: 0, ts_crt: now,
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: row.lawyer_uid, p_title: "🔔 استشارة معاد تفعيلها",
            p_body: `المرة ${newCount}`,
            p_data: { act: "consultation_reactivated", ref_id: consultId },
          });
        } catch {}
      }

      return json({ success: true, reactivate_count: newCount });
    }

    // ─── تجديد وقت المحادثة (دفع + إضافة 15 دقيقة) ───
    if (action === "renew_chat") {
      const consultId = (body.consultation_id ?? body.consultationId)?.toString() ?? "";
      if (!consultId) return json({ success: false, error: "CONSULTATION_ID_REQUIRED" }, 400);

      const { data: row } = await supabaseAdmin
        .from("legal_consultations")
        .select("id, user_uid, chat_started_at, chat_duration_minutes, renew_count, expires_at")
        .eq("id", consultId).eq("i_del", 0).maybeSingle();
      if (!row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);

      // فقط صاحب الاستشارة يجدد
      if (row.user_uid !== uid) return json({ success: false, error: "NOT_OWNER" }, 403);
      if (!row.chat_started_at) return json({ success: false, error: "CHAT_NOT_STARTED" }, 400);

      // التحقق: لم تتجاوز 7 أيام
      const startedAt = new Date(row.chat_started_at).getTime();
      const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
      if (Date.now() > startedAt + sevenDaysMs) {
        return json({ success: false, error: "CHAT_EXPIRED_7DAYS", message: "انتهت صلاحية المحادثة (7 أيام)" }, 400);
      }

      const newDuration = (Number(row.chat_duration_minutes) || 15) + 15;
      const newRenewCount = (Number(row.renew_count) || 0) + 1;
      await supabaseAdmin.from("legal_consultations").update({
        chat_duration_minutes: newDuration,
        renew_count: newRenewCount,
      }).eq("id", consultId);

      // رسالة system
      await supabaseAdmin.from("consultation_chats").insert({
        consultation_id: consultId, sender_id: uid,
        message_type: "system", content: `⏱️ تم تجديد المحادثة 15 دقيقة إضافية (التجديد رقم ${newRenewCount})`,
      });

      // إشعار المحامي
      const { data: consult } = await supabaseAdmin
        .from("legal_consultations").select("lawyer_uid").eq("id", consultId).maybeSingle();
      if (consult?.lawyer_uid) {
        await supabaseAdmin.from("notifications").insert({
          uid: consult.lawyer_uid, tp: 1, ttl: "⏱️ تم تجديد المحادثة",
          bdy: `العميل جدد المحادثة 15 دقيقة إضافية`,
          ref_id: consultId, act: "chat_renewed", i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: consult.lawyer_uid, p_title: "⏱️ تجديد المحادثة",
            p_body: "العميل جدد 15 دقيقة إضافية",
            p_data: { act: "chat_renewed", ref_id: consultId },
          });
        } catch {}
      }

      return json({ success: true, new_duration: newDuration, renew_count: newRenewCount });
    }

    // ─── جلب المحادثات السابقة (لخيار المتابعة) ───
    if (action === "list_previous_chats") {
      const { data, error } = await supabaseAdmin
        .from("legal_consultations")
        .select("id, subject, lawyer_alias, chat_started_at, chat_duration_minutes, renew_count, status, ts_crt")
        .eq("user_uid", uid)
        .eq("service_type", 0) // هاتفية فقط
        .in("status", [1, 2]) // مؤكدة أو منتهية
        .eq("i_del", 0)
        .order("ts_crt", { ascending: false })
        .limit(10);
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, consultations: data ?? [] });
    }

    // ─── تحويل لحضورية مع خصم ───
    if (action === "convert_to_onsite") {
      const consultId = (body.consultation_id ?? body.consultationId)?.toString() ?? "";
      if (!consultId) return json({ success: false, error: "CONSULTATION_ID_REQUIRED" }, 400);

      const { data: row } = await supabaseAdmin
        .from("legal_consultations")
        .select("id, user_uid, price, converted_to_onsite")
        .eq("id", consultId).eq("i_del", 0).maybeSingle();
      if (!row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);
      if (row.user_uid !== uid) return json({ success: false, error: "NOT_OWNER" }, 403);
      if (row.converted_to_onsite) return json({ success: false, error: "ALREADY_CONVERTED" }, 400);

      // الخصم = سعر الاستشارة الهاتفية المدفوع
      const discount = Number(row.price) || 500;
      const remainingAmount = 2000 - discount;

      await supabaseAdmin.from("legal_consultations").update({
        converted_to_onsite: true,
        onsite_discount: discount,
      }).eq("id", consultId);

      return json({ success: true, discount, remaining_amount: remainingAmount });
    }

    return json({ success: false, error: "UNKNOWN_ACTION" }, 400);
  } catch (error) {
    return json({ success: false, error: (error as Error).message }, 500);
  }
});

// Edge Function: admin-photography
// الغرض: نقل مهام إدارة التصوير الخاصة بالإدارة (إنشاء مهام، تحديث حالة، إرفاق صور) من RPC إلى Edge Function.

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

async function validateActor(
  req: Request,
  supabaseAdmin: ReturnType<typeof createClient>,
  body: Record<string, unknown>,
  minRole = 3,
): Promise<{ ok: true; uid: string; role: number } | { ok: false; response: Response }> {
  let requestedUid = (body.admin_uid ?? body.adminUid ?? body.user_uid ?? body.userUid ?? body.admin_id ?? body.adminId)?.toString() ?? "";
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
  if (!sessionToken) {
    return { ok: false, response: json({ success: false, error: "ADMIN_SESSION_REQUIRED" }, 401) };
  }

  // بعض نسخ APK ترسل رمز جلسة الموظف بلا admin_uid. نحل الممثل من الرمز
  // سيرفرياً بدلاً من رفض إسناد المصور رغم أن الجلسة صحيحة.
  if (!requestedUid) {
    const resolved = await supabaseAdmin.rpc("resolve_staff_session_actor", {
      p_token: sessionToken,
      p_min_role: minRole,
    });
    if (!resolved.error && resolved.data?.success === true) {
      requestedUid = resolved.data.user_id?.toString() ?? "";
      return { ok: true, uid: requestedUid, role: Number(resolved.data.role) };
    }
    return {
      ok: false,
      response: json({ success: false, error: resolved.data?.error ?? resolved.error?.message ?? "INVALID_ADMIN_SESSION" }, 401),
    };
  }

  const { data, error } = await supabaseAdmin.rpc("validate_staff_session", {
    p_user_uid: requestedUid,
    p_token: sessionToken,
    p_min_role: minRole,
  });

  if (error || data?.success !== true) {
    return {
      ok: false,
      response: json({ success: false, error: data?.error ?? error?.message ?? "INVALID_ADMIN_SESSION" }, 401),
    };
  }

  return { ok: true, uid: requestedUid, role: Number(data.role) };
}

// تحقق هوية المستخدم العادي (JWT أو staff_session_token) — لإجراءات المستخدم على طلباته
async function verifyUserUid(
  req: Request,
  supabaseAdmin: ReturnType<typeof createClient>,
  body: Record<string, unknown>,
  userUid: string,
): Promise<boolean> {
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (bearer && bearer !== "undefined" && bearer !== "null") {
    const { data: userData } = await supabaseAdmin.auth.getUser(bearer);
    const uid = userData?.user?.id;
    if (uid) return uid === userUid;
  }
  const sessionToken = (body.staff_session_token ?? body.staffSessionToken)?.toString() ?? "";
  if (sessionToken && userUid) {
    const { data, error } = await supabaseAdmin.rpc("validate_staff_session", {
      p_user_uid: userUid,
      p_token: sessionToken,
      p_min_role: 0,
    });
    if (!error && data?.success === true) return true;
  }
  return false;
}

// 🕐 تنسيق موعد بتوقيت دمشق — «2026/07/30 الساعة 11:00»
// السيرفر يخزّن UTC؛ العرض دائماً بتوقيت دمشق (دستور: التوقيت Asia/Damascus).
function fmtDamascus(iso: string | null | undefined): string {
  if (!iso) return "";
  try {
    const d = new Date(iso);
    if (isNaN(d.getTime())) return "";
    const p = new Intl.DateTimeFormat("en-CA", {
      timeZone: "Asia/Damascus",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    }).formatToParts(d);
    const g = (t: string) => p.find((x) => x.type === t)?.value ?? "";
    return `${g("year")}/${g("month")}/${g("day")} الساعة ${g("hour")}:${g("minute")}`;
  } catch {
    return "";
  }
}

// إشعار داخلي + 🔔 بوش خارجي (ثانوي — لا يكسر العملية الأساسية عند فشله)
// إصلاح 2026-07-28: كان يكتب صف notifications فقط بلا أي استدعاء للبوش،
// فلا يصل إشعار خارجي للجهاز إطلاقاً (بلاغ المالك). الآن يُستدعى
// send_push_notification لكل مستخدم بعد الإدراج — نفس قناة المواعيد/الدفعات المُثبتة.
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
  // 🔔 البوش الخارجي: مستقل عن نجاح الإدراج، وفشله لا يكسر العملية
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

    // ✅ طلب تصوير مرتبط بعرض موجود (من شاشة إضافة العرض بوضع التصوير)
    // المستخدم عبّى بيانات العرض الكاملة + حدد الموقع على الخريطة → العرض أُنشئ كـ review
    // هذا الأكشن ينشئ مهمة تصوير مرتبطة بالعرض (off_id) + يُشعر المكتب.
    if (action === "request_photography_for_offer") {
      const userUid = (body.user_uid ?? body.userUid)?.toString() ?? "";
      const offerId = (body.offer_id ?? body.offerId)?.toString() ?? "";
      if (!userUid || !offerId) {
        return json({ success: false, error: "MISSING_REQUIRED_FIELDS" }, 400);
      }

      // التحقق من هوية المستخدم
      const authHeader = req.headers.get("Authorization") ?? "";
      const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
      let verifiedUid = "";
      if (bearer && bearer !== "undefined" && bearer !== "null") {
        const { data: userData } = await supabaseAdmin.auth.getUser(bearer);
        verifiedUid = userData?.user?.id ?? "";
      }
      if (!verifiedUid) {
        const sessionToken = (body.staff_session_token ?? body.staffSessionToken)?.toString() ?? "";
        if (sessionToken && userUid) {
          const { data, error } = await supabaseAdmin.rpc("validate_staff_session", {
            p_user_uid: userUid,
            p_token: sessionToken,
            p_min_role: 0,
          });
          if (!error && data?.success === true) verifiedUid = userUid;
        }
      }
      if (!verifiedUid || verifiedUid !== userUid) {
        return json({ success: false, error: "AUTH_REQUIRED" }, 401);
      }

      // التحقق أن العرض موجود ومملوك للمستخدم
      const { data: offer, error: offerError } = await supabaseAdmin
        .from("offers")
        .select("id, ttl, loc, usr_id")
        .eq("id", offerId)
        .eq("usr_id", userUid)
        .eq("i_del", 0)
        .maybeSingle();
      if (offerError) return json({ success: false, error: offerError.message }, 400);
      if (!offer) return json({ success: false, error: "OFFER_NOT_FOUND_OR_NOT_OWNED" }, 404);

      // منع التكرار: مهمة تصوير نشطة لنفس العرض
      const { data: existing } = await supabaseAdmin
        .from("photography_tasks")
        .select("id")
        .eq("off_id", offerId)
        .in("sts", [0, 1, 2])
        .limit(1);
      if (existing && existing.length > 0) {
        return json({ success: false, error: "ACTIVE_PHOTOGRAPHY_REQUEST_EXISTS" }, 400);
      }

      // إنشاء مهمة تصوير مرتبطة بالعرض
      const { data: insertData, error: insertError } = await supabaseAdmin
        .from("photography_tasks")
        .insert({
          off_id: offerId,
          requested_by: userUid,
          ttl: offer.ttl ?? "طلب تصوير عقار",
          notes: "",
          loc: offer.loc ?? {},
          sts: 0,
        })
        .select("id")
        .single();
      if (insertError) return json({ success: false, error: insertError.message }, 400);

      // إشعار المكتب بطلب تصوير جديد مرتبط بعرض
      const { data: staff } = await supabaseAdmin
        .from("users")
        .select("id")
        .gte("role", 3)
        .lte("role", 6)
        .eq("sts", 0)
        .eq("i_del", 0);
      if (staff && staff.length > 0) {
        await notifyUsers(
          supabaseAdmin,
          staff.map((s) => s.id?.toString() ?? ""),
          1,
          "📸 طلب تصوير جديد لعرض",
          `طلب تصوير للعرض: ${offer.ttl ?? ""} — يرجى مراجعة العرض وإسناد مصوّر.`,
          insertData.id,
          "photography_request_new",
        );
      }

      return json({ success: true, task_id: insertData.id });
    }

    // ✅ طلب تصوير عقار من مستخدم عادي (لا يحتاج صلاحية إدارة)
    // الخدمة: طلب تصوير عقار قبل أو بعد النشر — مو مرتبطة بعرض موجود
    if (action === "request_photography") {
      const userUid = (body.user_uid ?? body.userUid)?.toString() ?? "";
      const fullName = (body.full_name ?? "").toString();
      const propertyDesc = (body.property_desc ?? "").toString();
      const propertyLocation = (body.property_location ?? "").toString();
      const contactPhone = (body.contact_phone ?? "").toString();
      const notes = (body.notes ?? "").toString();

      if (!userUid) {
        return json({ success: false, error: "USER_UID_REQUIRED" }, 400);
      }

      // التحقق من هوية المستخدم عبر JWT أو staff_session_token
      const authHeader = req.headers.get("Authorization") ?? "";
      const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
      let verifiedUid = "";

      if (bearer && bearer !== "undefined" && bearer !== "null") {
        const { data: userData } = await supabaseAdmin.auth.getUser(bearer);
        verifiedUid = userData?.user?.id ?? "";
      }

      // إذا ما في JWT صالح، نحاول staff_session_token
      if (!verifiedUid) {
        const sessionToken = (body.staff_session_token ?? body.staffSessionToken)?.toString() ?? "";
        if (sessionToken && userUid) {
          try {
            const { data, error } = await supabaseAdmin.rpc("validate_staff_session", {
              p_user_uid: userUid,
              p_token: sessionToken,
              p_min_role: 0,
            });
            
            // ✅ Bug #26: تحسين معالجة الأخطاء
            if (error) {
              console.error("validate_staff_session error:", error);
              return json({ 
                success: false, 
                error: "SESSION_VALIDATION_FAILED",
                message: "فشل التحقق من الجلسة. يرجى تسجيل الدخول مرة أخرى."
              }, 401);
            }
            
            if (data?.success === true) {
              verifiedUid = userUid;
            } else {
              // ✅ Bug #26: رسالة واضحة عندما تفشل المصادقة
              const errorMsg = data?.error ?? "UNKNOWN_ERROR";
              console.error("Session validation failed:", errorMsg);
              return json({ 
                success: false, 
                error: "AUTH_FAILED",
                message: `فشل المصادقة: ${errorMsg}. يرجى تسجيل الدخول مرة أخرى.`
              }, 401);
            }
          } catch (e) {
            // ✅ Bug #26: معالجة الأخطاء الاستثنائية
            console.error("Exception in validate_staff_session:", e);
            return json({ 
              success: false, 
              error: "VALIDATION_EXCEPTION",
              message: "حدث خطأ غير متوقع أثناء التحقق من الجلسة. يرجى المحاولة مرة أخرى."
            }, 500);
          }
        }
      }

      // ✅ Bug #26: رسالة واضحة عندما لا يتم التحقق من الهوية
      if (!verifiedUid || verifiedUid !== userUid) {
        console.error("Auth failed: verifiedUid=", verifiedUid, "userUid=", userUid);
        return json({ 
          success: false, 
          error: "AUTH_REQUIRED",
          message: "يجب تسجيل الدخول أولاً. يرجى تسجيل الدخول والمحاولة مرة أخرى."
        }, 401);
      }

      // التحقق من عدم وجود طلب تصوير نشط لنفس المستخدم
      const { data: existing, error: existError } = await supabaseAdmin
        .from("photography_tasks")
        .select("id")
        .eq("requested_by", userUid)
        .in("sts", [0, 1, 2]) // بانتظار / قيد التنفيذ / مرسلة للمكتب
        .limit(1);

      if (!existError && existing && existing.length > 0) {
        return json({ success: false, error: "ACTIVE_PHOTOGRAPHY_REQUEST_EXISTS" }, 400);
      }

      // إنشاء طلب تصوير (off_id فارغ لأن العقار ممكن يكون مو منشور بعد)
      const titleParts = [propertyDesc, fullName].filter(Boolean);
      const notesParts = [
        fullName ? `الاسم: ${fullName}` : "",
        propertyLocation ? `الموقع: ${propertyLocation}` : "",
        contactPhone ? `الهاتف: ${contactPhone}` : "",
        notes ? `ملاحظات: ${notes}` : "",
      ].filter(Boolean);

      const { data: insertData, error: insertError } = await supabaseAdmin
        .from("photography_tasks")
        .insert({
          off_id: null,
          requested_by: userUid,
          ttl: titleParts.join(" — ") || "طلب تصوير عقار",
          notes: notesParts.join(" | "),
          sts: 0,
        })
        .select("id")
        .single();

      if (insertError) {
        return json({ success: false, error: insertError.message }, 400);
      }

      // إشعار المكتب (مشرف/موظف/نائب/مدير نشط) بوصول طلب تصوير جديد
      const { data: staff } = await supabaseAdmin
        .from("users")
        .select("id")
        .gte("role", 3)
        .lte("role", 6)
        .eq("sts", 0)
        .eq("i_del", 0);
      if (staff && staff.length > 0) {
        await notifyUsers(
          supabaseAdmin,
          staff.map((s) => s.id?.toString() ?? ""),
          1,
          "طلب تصوير عقار جديد",
          `${fullName || "مستخدم"} يطلب تصوير: ${propertyDesc}${propertyLocation ? ` — ${propertyLocation}` : ""}`,
          insertData.id,
          "photography_request_new",
        );
      }

      return json({ success: true, task_id: insertData.id });
    }

    // إلغاء طلب تصوير من صاحبه (فقط المهام بانتظار sts=0)
    if (action === "cancel_photo_request") {
      const userUid = (body.user_uid ?? body.userUid)?.toString() ?? "";
      const taskId = (body.task_id ?? body.taskId)?.toString() ?? "";
      const cancelReason = (body.cancel_reason ?? body.cancelReason)?.toString() ?? "";
      if (!userUid || !taskId) {
        return json({ success: false, error: "MISSING_REQUIRED_FIELDS" }, 400);
      }
      if (!cancelReason) {
        return json({ success: false, error: "CANCEL_REASON_REQUIRED" }, 400);
      }
      if (!(await verifyUserUid(req, supabaseAdmin, body, userUid))) {
        return json({ success: false, error: "AUTH_REQUIRED" }, 401);
      }

      const { data: cancelled, error: cancelError } = await supabaseAdmin
        .from("photography_tasks")
        .update({
          sts: 5,
          office_note: "إلغاء من العميل: " + cancelReason,
          ts_done: new Date().toISOString(),
          ts_upd: new Date().toISOString(),
        })
        .eq("id", taskId)
        .eq("requested_by", userUid)
        .eq("sts", 0)
        .select("id, off_id, ttl, photographer_id")
        .maybeSingle();
      if (cancelError) return json({ success: false, error: cancelError.message }, 400);
      if (!cancelled) return json({ success: false, error: "TASK_NOT_PENDING" }, 400);

      // طلب المستخدم يحمل مسودة عرض تقنية؛ عند الإلغاء تُخفى نهائياً ولا
      // يجوز أن تصل لاحقاً إلى مراجعة العروض.
      const cancelledOfferId = cancelled.off_id?.toString() ?? "";
      if (cancelledOfferId) {
        await supabaseAdmin
          .from("offers")
          .update({ i_del: 1 })
          .eq("id", cancelledOfferId)
          .eq("photo_req", 1)
          .eq("sts", 0);
      }

      const pid = cancelled.photographer_id?.toString() ?? "";
      if (pid) {
        await notifyUsers(
          supabaseAdmin,
          [pid],
          2,
          "📸 إلغاء مهمة تصوير",
          "ألغى العميل طلب التصوير \"" + (cancelled.ttl ?? "") + "\" — السبب: " + cancelReason,
          cancelled.id,
          "photography_request_cancelled",
        );
      }

      return json({ success: true });
    }

    // جلب طلبات التصوير الخاصة بالمستخدم نفسه (لشاشة خدمة التصوير)
    if (action === "my_photo_requests") {
      const userUid = (body.user_uid ?? body.userUid)?.toString() ?? "";
      if (!userUid) {
        return json({ success: false, error: "USER_UID_REQUIRED" }, 400);
      }

      // نفس منطق التحقق المستخدم في request_photography (JWT أو staff_session_token)
      const authHeader2 = req.headers.get("Authorization") ?? "";
      const bearer2 = authHeader2.startsWith("Bearer ") ? authHeader2.slice(7) : "";
      let verifiedUid = "";

      if (bearer2 && bearer2 !== "undefined" && bearer2 !== "null") {
        const { data: userData } = await supabaseAdmin.auth.getUser(bearer2);
        verifiedUid = userData?.user?.id ?? "";
      }

      if (!verifiedUid) {
        const sessionToken = (body.staff_session_token ?? body.staffSessionToken)?.toString() ?? "";
        if (sessionToken && userUid) {
          const { data, error } = await supabaseAdmin.rpc("validate_staff_session", {
            p_user_uid: userUid,
            p_token: sessionToken,
            p_min_role: 0,
          });
          if (!error && data?.success === true) {
            verifiedUid = userUid;
          }
        }
      }

      if (!verifiedUid || verifiedUid !== userUid) {
        return json({ success: false, error: "AUTH_REQUIRED" }, 401);
      }

      const { data: tasks, error: tasksError } = await supabaseAdmin
        .from("photography_tasks")
        .select("*")
        .eq("requested_by", userUid)
        .order("ts_crt", { ascending: false })
        .limit(20);
      if (tasksError) {
        return json({ success: false, error: tasksError.message }, 400);
      }

      // صاحب الطلب يحتاج رؤية بياناته كاملة منذ لحظة الإرسال، ثم اسم المصور
      // وموعده بعد الإسناد. الإثراء يتم بعد التحقق من الملكية أعلاه حصراً.
      const rows = tasks ?? [];
      const offerIds = [...new Set(rows.map((t) => t.off_id?.toString() ?? "").filter(Boolean))];
      const photographerIds = [...new Set(rows.map((t) => t.photographer_id?.toString() ?? "").filter(Boolean))];
      const offersById = new Map<string, Record<string, unknown>>();
      const photographersById = new Map<string, { name: string; phone: string }>();

      if (offerIds.length > 0) {
        const { data: offers } = await supabaseAdmin
          .from("offers")
          .select("id, ttl, typ, trx, cat, sub, prc, cur, loc, descript, specs, avl, contact_ph, doc_tp, sts, photo_req")
          .in("id", offerIds)
          .eq("usr_id", userUid);
        for (const offer of offers ?? []) offersById.set(offer.id.toString(), offer);
      }
      if (photographerIds.length > 0) {
        const { data: photographers } = await supabaseAdmin
          .from("users")
          .select("id, nm, ph")
          .in("id", photographerIds)
          .eq("sts", 0)
          .eq("i_del", 0);
        for (const photographer of photographers ?? []) {
          photographersById.set(photographer.id.toString(), {
            name: photographer.nm?.toString() ?? "",
            phone: photographer.ph?.toString() ?? "",
          });
        }
      }

      const enriched = rows.map((task) => {
        const offer = offersById.get(task.off_id?.toString() ?? "");
        const photographer = photographersById.get(task.photographer_id?.toString() ?? "");
        return {
          ...task,
          offer_details: offer ?? {},
          is_photo_request: Number(offer?.photo_req ?? 0) === 1,
          offer_sts: offer?.sts ?? null,
          photographer_name: photographer?.name ?? "",
          photographer_phone: photographer?.phone ?? "",
        };
      });
      return json({ success: true, tasks: enriched });
    }

    const actor = await validateActor(req, supabaseAdmin, body, 3); // إدارة/موظف مكتبي
    if (!actor.ok) return actor.response;

    const adminUid = actor.uid;

    // عرض كل مهام التصوير للإدارة — الاستعلام المباشر من العميل محظور بـ RLS
    // (جلسات مخصصة لا تحمل auth.uid())، فكان المكتب يرى قائمة فارغة.
    if (action === "list_tasks") {
      const statusFilter = body.status ?? body.sts;
      let query = supabaseAdmin
        .from("photography_tasks")
        .select("*")
        .order("ts_crt", { ascending: false });
      if (statusFilter !== undefined && statusFilter !== null && statusFilter !== "") {
        query = query.eq("sts", Number(statusFilter));
      }
      const { data, error } = await query.limit(200);
      if (error) return json({ success: false, error: error.message }, 400);

      // تمييز مسودة طلب المستخدم عن مهمة تصوير عرض منشور؛ تحتاج الواجهة هذا
      // للفصل بين «فتح مراجعة العرض» و«اعتماد صور عرض موجود».
      const tasks = data ?? [];
      const offerIds = [...new Set(tasks.map((t) => t.off_id?.toString() ?? "").filter(Boolean))];
      const offerMeta = new Map<string, { photoReq: number; sts: number }>();
      if (offerIds.length > 0) {
        const { data: offers } = await supabaseAdmin
          .from("offers")
          .select("id, photo_req, sts")
          .in("id", offerIds);
        for (const offer of offers ?? []) {
          offerMeta.set(offer.id.toString(), {
            photoReq: Number(offer.photo_req ?? 0),
            sts: Number(offer.sts ?? 0),
          });
        }
      }
      const enriched = tasks.map((task) => {
        const meta = offerMeta.get(task.off_id?.toString() ?? "");
        return {
          ...task,
          is_photo_request: meta?.photoReq === 1,
          offer_sts: meta?.sts ?? null,
        };
      });
      return json({ success: true, tasks: enriched });
    }

    // ─── Action: stats — إحصاءات مهام التصوير (نظرة إدارية بأرقام مجمّعة) ───
    // أُضيف 2026-07-30: الشاشة فيها فلاتر تصفح فقط (قوائم)، بلا أي رقم مجمّع
    // يخبر المكتب بالتكدّس أو الإنتاجية أو نسبة التحويل لعروض.
    if (action === "stats") {
      const { data: rows, error } = await supabaseAdmin
        .from("photography_tasks")
        .select("sts, off_id, photographer_id, ts_crt, ts_done");
      if (error) return json({ success: false, error: error.message }, 400);

      const tasks = rows ?? [];
      const byStatus: Record<string, number> = {
        pending: 0, in_progress: 0, submitted: 0, approved: 0, rejected: 0, cancelled: 0,
      };
      const nameByStatus: Record<number, string> = {
        0: "pending", 1: "in_progress", 2: "submitted", 3: "approved", 4: "rejected", 5: "cancelled",
      };

      let becameOffers = 0;
      let doneCount = 0;
      let totalHours = 0;
      const perPhotographer: Record<string, number> = {};

      for (const t of tasks) {
        const key = nameByStatus[Number(t.sts)] ?? "pending";
        byStatus[key] = (byStatus[key] ?? 0) + 1;

        if (t.off_id) becameOffers++;

        // متوسط زمن الإنجاز: من إنشاء الطلب حتى إغلاقه (المعتمدة فقط)
        if (Number(t.sts) === 3 && t.ts_crt && t.ts_done) {
          const h = (new Date(String(t.ts_done)).getTime() -
                     new Date(String(t.ts_crt)).getTime()) / 3600000;
          if (h >= 0 && h < 24 * 365) { totalHours += h; doneCount++; }
        }

        const pid = t.photographer_id?.toString() ?? "";
        if (pid && Number(t.sts) === 3) {
          perPhotographer[pid] = (perPhotographer[pid] ?? 0) + 1;
        }
      }

      // أسماء المصوّرين الأكثر إنجازاً (أعلى 5)
      const topIds = Object.entries(perPhotographer)
        .sort((a, b) => b[1] - a[1]).slice(0, 5).map(([id]) => id);
      const topPhotographers: Array<Record<string, unknown>> = [];
      if (topIds.length > 0) {
        const { data: users } = await supabaseAdmin
          .from("users").select("id, nm").in("id", topIds);
        for (const id of topIds) {
          const u = users?.find((x) => x.id?.toString() === id);
          topPhotographers.push({
            uid: id,
            name: u?.nm?.toString() ?? "—",
            done: perPhotographer[id],
          });
        }
      }

      const total = tasks.length;
      return json({
        success: true,
        total,
        by_status: byStatus,
        became_offers: becameOffers,
        conversion_pct: total > 0 ? Math.round((becameOffers / total) * 100) : 0,
        avg_done_hours: doneCount > 0
          ? Math.round((totalHours / doneCount) * 10) / 10
          : null,
        top_photographers: topPhotographers,
      });
    }

    // إسناد مصور لمهمة تصوير بانتظار (يدعم طلبات المستخدم بلا عرض off_id=null)
    if (action === "assign_photographer") {
      const taskId = (body.task_id ?? body.taskId)?.toString() ?? "";
      const photographerId = (body.photographer_id ?? body.photographerId)?.toString() ?? "";
      const scheduledAt = body.ts_scheduled?.toString() ?? null;
      if (!taskId || !photographerId) {
        return json({ success: false, error: "MISSING_REQUIRED_FIELDS" }, 400);
      }

      // 🕐 رفض أي موعد بالماضي (2026-07-30): كان يُقبل بلا اعتراض — أُسندت مهمة
      // بموعد 2020 ونجحت ⇒ ضغطة غلط بالتقويم تُفسد الموعد والتذكير معاً.
      if (scheduledAt) {
        const when = new Date(scheduledAt);
        if (isNaN(when.getTime())) {
          return json({ success: false, error: "INVALID_SCHEDULE_DATE" }, 400);
        }
        // هامش 5 دقائق يستوعب فرق ساعة الجهاز
        if (when.getTime() < Date.now() - 5 * 60 * 1000) {
          return json({ success: false, error: "SCHEDULE_IN_THE_PAST" }, 400);
        }

        // 🚧 منع ازدواج المصوّر بنفس النافذة الزمنية (gap_mins من app_config).
        // مواعيد المعاينة محميّة بـ TIME_CONFLICT؛ التصوير كان بلا أي حماية
        // ⇒ مهمتان لنفس المصوّر بنفس الساعة = ازدواج ميداني حتمي (2026-07-30).
        const { error: conflictErr } = await supabaseAdmin.rpc(
          "assert_photographer_free",
          {
            p_photographer_uid: photographerId,
            p_dt: scheduledAt,
            p_exclude_task: taskId,
          },
        );
        if (conflictErr) {
          const msg = conflictErr.message ?? "";
          if (msg.includes("PHOTOGRAPHER_TIME_CONFLICT")) {
            return json({
              success: false,
              error: "PHOTOGRAPHER_TIME_CONFLICT",
              message: "المصوّر لديه مهمة أخرى بنفس التوقيت — اختر موعداً آخر أو مصوّراً آخر.",
            }, 409);
          }
          return json({ success: false, error: msg }, 400);
        }
      }

      // التحقق أن المُسند إليه مصوّر فعلياً (الدور 2 أو صلاحية صريحة).
      // لا نستخدم role>=2 لأن المحامي والمعقب أرقامهما أعلى وليسا مصورين.
      const { data: photographer, error: photographerError } = await supabaseAdmin
        .from("users")
        .select("id, role, perm, sts, i_del")
        .eq("id", photographerId)
        .eq("i_del", 0)
        .maybeSingle();
      if (photographerError) return json({ success: false, error: photographerError.message }, 400);
      if (!photographer || Number(photographer.sts) !== 0) {
        return json({ success: false, error: "PHOTOGRAPHER_NOT_FOUND" }, 400);
      }
      const permList = Array.isArray(photographer.perm) ? photographer.perm : [];
      const qualified = Number(photographer.role) === 2 || permList.includes("photographer_tasks");
      if (!qualified) {
        return json({ success: false, error: "USER_NOT_A_PHOTOGRAPHER" }, 400);
      }

      // 🔁 إعادة الإسناد/التأجيل مسموحان للمهام بانتظار (0) أو قيد التنفيذ (1)
      // — أُضيف 2026-07-30: كان الشرط sts=0 فقط، فإذا اعتذر المصوّر أو طلب
      // العميل تأجيلاً بعد بدء التنفيذ تصير المهمة مقفولة ولا حل إلا تعديل
      // مباشر بقاعدة البيانات. المهام المسلّمة/المعتمدة/الملغاة تبقى مقفلة.
      const { data: prevTask } = await supabaseAdmin
        .from("photography_tasks")
        .select("photographer_id, sts, ts_scheduled")
        .eq("id", taskId)
        .maybeSingle();
      const prevPhotographer = prevTask?.photographer_id?.toString() ?? "";
      const isReassign = prevPhotographer !== "" && prevPhotographer !== photographerId;

      const { data: task, error: taskError } = await supabaseAdmin
        .from("photography_tasks")
        .update({
          photographer_id: photographerId,
          ts_scheduled: scheduledAt,
          // إعادة الإسناد لمصوّر آخر تُرجع المهمة لنقطة البدء عنده
          sts: isReassign ? 0 : (prevTask?.sts ?? 0),
          ts_upd: new Date().toISOString(),
        })
        .eq("id", taskId)
        .in("sts", [0, 1])
        .select("id, ttl, notes, requested_by")
        .maybeSingle();
      if (taskError) return json({ success: false, error: taskError.message }, 400);
      if (!task) return json({ success: false, error: "TASK_NOT_ASSIGNABLE" }, 400);

      // إشعار المصوّر السابق أن المهمة سُحبت منه
      if (isReassign) {
        await notifyUsers(
          supabaseAdmin,
          [prevPhotographer],
          2,
          "🔄 أُعيد إسناد مهمة تصوير",
          `سُحبت منك مهمة «${task.ttl ?? ""}» وأُسندت لمصوّر آخر — لا حاجة لمتابعتها.`,
          task.id,
          "photography_task_reassigned",
        );
      }

      // ── إشعارات الإسناد الغنية للطرفين (2026-07-28 بطلب المالك) ──
      // الهدف: كل طرف يعرف الموعد بالساعة + الموقع + اسم ورقم الطرف الآخر
      // ليتمكنا من التواصل والتنسيق قبل الموعد.
      const whenTxt = fmtDamascus(scheduledAt);
      const reqUid = task.requested_by?.toString() ?? "";

      // بيانات المصور (للطالب) وبيانات الطالب (للمصور)
      const { data: parties } = await supabaseAdmin
        .from("users")
        .select("id, nm, ph")
        .in("id", [photographerId, reqUid].filter(Boolean));
      const photog = parties?.find((u) => u.id?.toString() === photographerId);
      const requesterRow = parties?.find((u) => u.id?.toString() === reqUid);

      // الموقع والهاتف مخزّنان داخل notes بصيغة «الاسم: … | الموقع: … | الهاتف: …»
      const notesStr = (task.notes ?? "").toString();
      const pick = (label: string): string => {
        const seg = notesStr.split("|").find((s) => s.includes(`${label}:`));
        return seg ? seg.split(`${label}:`)[1]?.trim() ?? "" : "";
      };
      const locTxt = pick("الموقع");
      const reqPhone = pick("الهاتف") || (requesterRow?.ph?.toString() ?? "");
      const reqName = (requesterRow?.nm?.toString() || pick("الاسم")) || "العميل";

      // ① للمصوّر: الموعد + الموقع + اسم وهاتف طالب التصوير
      const photogLines = [
        `📸 مهمة تصوير: ${task.ttl ?? ""}`,
        whenTxt ? `📅 ${whenTxt}` : "📅 الموعد غير محدد — نسّق مع المكتب",
        locTxt ? `📍 الموقع: ${locTxt}` : "",
        `📞 طالب التصوير: ${reqName}${reqPhone ? ` — ${reqPhone}` : ""}`,
        "يرجى التواصل معه قبل الموعد لتأكيد الوصول.",
      ].filter(Boolean);
      await notifyUsers(
        supabaseAdmin,
        [photographerId],
        2,
        "📸 مهمة تصوير مسندة لك",
        photogLines.join("\n"),
        task.id,
        "photography_task_assigned",
      );

      // ② لصاحب الطلب: الموعد + اسم وهاتف المصوّر (كان معدوماً تماماً قبل اليوم)
      if (reqUid) {
        const clientLines = [
          `تم تعيين مصوّر لطلبك: ${task.ttl ?? ""}`,
          whenTxt ? `📅 موعد التصوير: ${whenTxt}` : "📅 سيتم تحديد الموعد قريباً",
          `👤 المصوّر: ${photog?.nm ?? "—"}${photog?.ph ? ` — ${photog.ph}` : ""}`,
          "يرجى التواجد بالموقع قبل الموعد بعشر دقائق، وللتنسيق تواصل مع المصوّر مباشرة.",
        ].filter(Boolean);
        await notifyUsers(
          supabaseAdmin,
          [reqUid],
          1,
          "📸 تم تعيين مصوّر لطلبك",
          clientLines.join("\n"),
          task.id,
          "photography_photographer_assigned",
        );
      }

      return json({ success: true });
    }

    if (action === "create") {
      const offerId = (body.offer_id ?? body.offerId)?.toString() ?? "";
      const photographerId = (body.photographer_id ?? body.photographerId)?.toString() ?? "";
      const notes = (body.notes ?? "").toString();
      const scheduledAt = body.ts_scheduled?.toString() ?? null;

      if (!offerId || !photographerId) {
        return json({ success: false, error: "MISSING_REQUIRED_FIELDS" }, 400);
      }

      // 🕐 منع ازدواج المصوّر بنفس النافذة الزمنية (2026-07-30)
      // assign_photographer كان يفحص التعارض لكن create لا — فجوة منطقية
      // أُغلقت بنفس الدالة assert_photographer_free المستخدمة بالإسناد.
      if (scheduledAt) {
        const when = new Date(scheduledAt);
        if (isNaN(when.getTime())) {
          return json({ success: false, error: "INVALID_SCHEDULE_DATE" }, 400);
        }
        if (when.getTime() < Date.now() - 5 * 60 * 1000) {
          return json({ success: false, error: "SCHEDULE_IN_THE_PAST" }, 400);
        }
        const { error: conflictErr } = await supabaseAdmin.rpc(
          "assert_photographer_free",
          { p_photographer_uid: photographerId, p_dt: scheduledAt, p_exclude_task: null },
        );
        if (conflictErr) {
          const msg = conflictErr.message ?? "";
          if (msg.includes("PHOTOGRAPHER_TIME_CONFLICT")) {
            return json({
              success: false,
              error: "PHOTOGRAPHER_TIME_CONFLICT",
              message: "المصوّر لديه مهمة أخرى بنفس التوقيت — اختر موعداً آخر أو مصوّراً آخر.",
            }, 409);
          }
          return json({ success: false, error: msg }, 400);
        }
      }

      const { data, error } = await supabaseAdmin.rpc("create_photography_task_internal", {
        p_admin_uid: adminUid,
        p_offer_id: offerId,
        p_photographer_id: photographerId,
        p_notes: notes,
        p_ts_scheduled: scheduledAt,
      });

      if (error) return json({ success: false, error: error.message }, 400);

      // 🔔 إشعار المصوّر بالمهمة الجديدة (2026-07-30)
      // كان المصوّر لا يُشعَر عند الإنشاء — يكتشف المهمة فقط عند فتح الشاشة.
      // assign_photographer يُشعَر لكن create لا — فجوة إشعارات أُغلقت.
      if (data && Array.isArray(data) && data.length > 0) {
        const newTask = data[0];
        const whenTxt = fmtDamascus(scheduledAt);
        const { data: photog } = await supabaseAdmin
          .from("users").select("nm, ph").eq("id", photographerId).maybeSingle();
        const { data: offer } = await supabaseAdmin
          .from("offers").select("ttl").eq("id", offerId).maybeSingle();

        const lines = [
          `📸 مهمة تصوير جديدة: ${offer?.ttl ?? newTask.ttl ?? ""}`,
          whenTxt ? `📅 ${whenTxt}` : "📅 الموعد غير محدد — نسّق مع المكتب",
          notes ? `📝 ${notes}` : "",
          "يرجى فتح «مهام التصوير» للتفاصيل والبدء بالتنفيذ.",
        ].filter(Boolean);

        await notifyUsers(
          supabaseAdmin,
          [photographerId],
          2,
          "📸 مهمة تصوير جديدة مسندة لك",
          lines.join("\n"),
          newTask.id?.toString() ?? "",
          "photography_task_created",
        );
      }

      return json({ success: true });
    }

    if (action === "update_status") {
      const taskId = (body.task_id ?? body.taskId)?.toString() ?? "";
      const status = Number(body.status ?? 0);
      const officeNote = (body.office_note ?? body.officeNote ?? "").toString();

      if (!taskId) return json({ success: false, error: "TASK_ID_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("update_photography_task_status_internal", {
        p_admin_uid: adminUid,
        p_task_id: taskId,
        p_status: status,
        p_office_note: officeNote,
      });

      if (error) return json({ success: false, error: error.message }, 400);

      // إشعار صاحب الطلب بالنتيجة النهائية (اعتماد/رفض/إلغاء)
      if (data === true && (status === 3 || status === 4 || status === 5)) {
        const { data: task } = await supabaseAdmin
          .from("photography_tasks")
          .select("requested_by, ttl, office_note")
          .eq("id", taskId)
          .maybeSingle();
        const requester = task?.requested_by?.toString() ?? "";
        if (requester) {
          const msg = status === 3
            ? `تم اعتماد تصوير عقارك — الوسائط متاحة الآن في طلبك (${task?.ttl ?? ""})`
            : status === 4
              ? `تم رفض طلب التصوير (${task?.ttl ?? ""})${task?.office_note ? " — " + task.office_note : ""}`
              : `تم إلغاء طلب التصوير (${task?.ttl ?? ""})`;
          await notifyUsers(
            supabaseAdmin,
            [requester],
            1,
            "تحديث طلب تصوير العقار",
            msg,
            taskId,
            "photography_request_result",
          );
        }
      }

      return json({ success: data === true });
    }

    // ─── Action: offer_photo_info — هل هذا العرض مُصوَّر من المكتب؟ (للإدارة فقط) ───
    // أُضيف 2026-07-29: التنويه لا يُخزَّن داخل offers.specs لأن العمود مقروء anon
    // ⇒ أي وسم فيه يتسرّب للزائر. المصدر الموثوق هو photography_tasks.off_id،
    // ويُقرأ هنا خلف حارس الدور (validateActor ≥3) بمفتاح الخدمة.
    if (action === "offer_photo_info") {
      const offerId = (body.offer_id ?? body.offerId)?.toString() ?? "";
      if (!offerId) return json({ success: false, error: "OFFER_ID_REQUIRED" }, 400);

      const { data: task, error } = await supabaseAdmin
        .from("photography_tasks")
        .select("id, ttl, sts, photographer_id, ts_done, ts_scheduled")
        .eq("off_id", offerId)
        .order("ts_crt", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (error) return json({ success: false, error: error.message }, 400);
      if (!task) return json({ success: true, office_photographed: false });

      let photographerName = "";
      if (task.photographer_id) {
        const { data: ph } = await supabaseAdmin
          .from("users").select("nm").eq("id", task.photographer_id).maybeSingle();
        photographerName = ph?.nm?.toString() ?? "";
      }

      return json({
        success: true,
        office_photographed: true,
        task_id: task.id,
        photographer_name: photographerName,
        done_at: task.ts_done ?? task.ts_scheduled ?? null,
      });
    }

    // ─── Action: link_offer — ربط مهمة تصوير بالعرض المُنشأ منها وإغلاقها ───
    // أُضيف 2026-07-29: طلبات المستخدم تُنشأ بـ off_id=null (العقار غير منشور بعد)،
    // فكانت صور المصوّر تبقى حبيسة photography_tasks بلا أي طريق لتصير عرضاً.
    // الآن موظف المكتب ينشئ العرض من الصور، وهذا الأكشن يربط ويُغلق ويُشعر الطالب.
    if (action === "link_offer") {
      const taskId = (body.task_id ?? body.taskId)?.toString() ?? "";
      const offerId = (body.offer_id ?? body.offerId)?.toString() ?? "";
      if (!taskId || !offerId) {
        return json({ success: false, error: "TASK_AND_OFFER_REQUIRED" }, 400);
      }

      const { data: task, error: upErr } = await supabaseAdmin
        .from("photography_tasks")
        .update({
          off_id: offerId,
          sts: 3,
          ts_done: new Date().toISOString(),
          ts_upd: new Date().toISOString(),
        })
        .eq("id", taskId)
        .select("id, ttl, requested_by")
        .maybeSingle();
      if (upErr) return json({ success: false, error: upErr.message }, 400);
      if (!task) return json({ success: false, error: "TASK_NOT_FOUND" }, 404);

      const requester = task.requested_by?.toString() ?? "";
      if (requester) {
        await notifyUsers(
          supabaseAdmin,
          [requester],
          1,
          "🎉 العرض الخاص بك أصبح منشوراً",
          `تم إنشاء عرض من صور التصوير (${task.ttl ?? ""}) ونشره — يمكنك متابعته من «عروضي».`,
          offerId,
          "photography_offer_published",
        );
      }

      return json({ success: true, offer_id: offerId });
    }

    if (action === "attach_media") {
      const taskId = (body.task_id ?? body.taskId)?.toString() ?? "";
      if (!taskId) return json({ success: false, error: "TASK_ID_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("attach_photography_media_to_offer_internal", {
        p_admin_uid: adminUid,
        p_task_id: taskId,
      });

      if (error) return json({ success: false, error: error.message }, 400);

      // إشعار صاحب الطلب عند اعتماد التصوير وربط الوسائط بالعرض
      if (data === true) {
        const { data: task } = await supabaseAdmin
          .from("photography_tasks")
          .select("requested_by, ttl")
          .eq("id", taskId)
          .maybeSingle();
        const requester = task?.requested_by?.toString() ?? "";
        if (requester) {
          await notifyUsers(
            supabaseAdmin,
            [requester],
            1,
            "تم اعتماد تصوير عقارك",
            `اعتُمدت وسائط التصوير ورُبطت بالعرض الخاص بك (${task?.ttl ?? ""})`,
            taskId,
            "photography_request_result",
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

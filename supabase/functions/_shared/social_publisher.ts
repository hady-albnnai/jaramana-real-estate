// Shared Meta publisher used by publish-to-social and admin-offers.
//
// 🔄 2026-08-27 — تعدد الحسابات: مصدر الحسابات أصبح جدول social_accounts
// (يُدار من داخل التطبيق عبر Edge Function: social-accounts). الناشر يقرأ كل
// الحسابات المفعّلة وينشر عليها واحدة تلو الأخرى، مع سجل مستقل لكل حساب في
// social_publications (عبر claim_social_publication_v2).
//
// التوافق الخلفي: إن لم يوجد أي حساب في القاعدة، يُستخدم المسار القديم
// بمفاتيح البيئة (claim_social_publication) — أي أن النشر يبقى فاقداً فقط
// عند غياب الحسابين معاً.
//
// Secrets (المسار القديم فقط):
// META_PAGE_ACCESS_TOKEN, META_FACEBOOK_PAGE_ID, META_INSTAGRAM_ACCOUNT_ID
// Optional: META_GRAPH_API_VERSION (default: v25.0)

export type SocialPublishResult = {
  success: boolean;
  alreadyPublished?: boolean;
  facebook?: PlatformResult;
  instagram?: PlatformResult;
  accounts?: AccountPublishResult[];
  error?: string;
};

type Platform = "facebook" | "instagram";
type PlatformResult = {
  success: boolean;
  skipped?: boolean;
  postIds?: string[];
  error?: string;
};
type AccountPublishResult = {
  accountId: string;
  accountName: string;
  platform: Platform;
  success: boolean;
  skipped?: boolean;
  postId?: string;
  error?: string;
};

type SupabaseAdmin = any;

type AccountRow = {
  id: string;
  platform: string;
  name: string | null;
  account_external_id: string;
  access_token: string;
};

type Account = {
  /** UUID للسسجلات القاعدية، أو "env:<platform>" للمسار البيئي. */
  id: string;
  /** true = حساب قاعدي (claim v2)، false = مسار مفاتيح البيئة (claim قديم). */
  isDb: boolean;
  platform: Platform;
  name: string;
  externalId: string;
  accessToken: string;
};

type OfferRow = {
  id: string;
  i_soc: number;
  soc_pub: number;
  soc_txt: string | null;
  imgs: unknown;
  sts: number;
  i_pub: number;
  i_del: number;
};

function env(name: string): string {
  return (Deno.env.get(name) ?? "").trim();
}

function cleanImages(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  const unique = new Set<string>();
  for (const item of raw) {
    const url = String(item ?? "").trim();
    if (!url.startsWith("https://")) continue;
    try {
      const parsed = new URL(url);
      if (parsed.protocol === "https:") unique.add(parsed.toString());
    } catch (_) {
      // Ignore malformed/non-public URLs.
    }
    if (unique.size >= 10) break;
  }
  return [...unique];
}

function safeError(value: unknown): string {
  if (value instanceof Error) return value.message.slice(0, 1000);
  return String(value ?? "UNKNOWN_ERROR").slice(0, 1000);
}

async function graphPost(
  path: string,
  token: string,
  values: Record<string, string>,
): Promise<Record<string, unknown>> {
  const version = env("META_GRAPH_API_VERSION") || "v25.0";
  const body = new URLSearchParams(values);
  const response = await fetch(`https://graph.facebook.com/${version}/${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body,
  });
  const payload = await response.json().catch(() => ({})) as Record<string, unknown>;
  if (!response.ok || payload.error) {
    const graphError = payload.error as Record<string, unknown> | undefined;
    const message = String(graphError?.message ?? `META_HTTP_${response.status}`);
    const code = graphError?.code ? ` (${graphError.code})` : "";
    throw new Error(`${message}${code}`);
  }
  return payload;
}

// ─── تحميل الحسابات: القاعدة أولاً ثم fallback البيئة ───

async function loadAccounts(supabase: SupabaseAdmin): Promise<Account[]> {
  const { data, error } = await supabase
    .from("social_accounts")
    .select("id,platform,name,account_external_id,access_token")
    .eq("i_del", 0)
    .eq("is_active", true)
    .in("platform", ["facebook", "instagram"])
    .order("ts_crt", { ascending: true });
  // خطأ القراءة لا يُجهض النشر كلياً: نجرب المسار البيئي قبل الاستسلام.
  if (!error && Array.isArray(data) && data.length > 0) {
    const accounts = (data as AccountRow[])
      .map((row) => ({
        id: String(row.id ?? ""),
        isDb: true,
        platform: row.platform === "instagram" ? ("instagram" as Platform) : ("facebook" as Platform),
        name: String(row.name ?? row.platform).trim() || String(row.platform),
        externalId: String(row.account_external_id ?? "").trim(),
        accessToken: String(row.access_token ?? "").trim(),
      }))
      .filter((a) => a.id && a.externalId && a.accessToken);
    if (accounts.length > 0) return accounts;
  }

  // المسار القديم: مفاتيح البيئة (توافق خلفي كامل مع التوثيق السابق).
  const accounts: Account[] = [];
  const pageToken = env("META_PAGE_ACCESS_TOKEN");
  const pageId = env("META_FACEBOOK_PAGE_ID");
  const instagramId = env("META_INSTAGRAM_ACCOUNT_ID");
  if (pageId && pageToken) {
    accounts.push({
      id: "env:facebook",
      isDb: false,
      platform: "facebook",
      name: "فيسبوك (مفاتيح السيرفر)",
      externalId: pageId,
      accessToken: pageToken,
    });
  }
  if (instagramId && pageToken) {
    accounts.push({
      id: "env:instagram",
      isDb: false,
      platform: "instagram",
      name: "إنستغرام (مفاتيح السيرفر)",
      externalId: instagramId,
      accessToken: pageToken,
    });
  }
  return accounts;
}

// ─── الحجز الذرّي: v2 للحسابات القاعدية، القديمة للمسار البيئي ───

async function claimForAccount(
  supabase: SupabaseAdmin,
  offerId: string,
  account: Account,
  attemptToken: string,
): Promise<"claimed" | "published" | "busy"> {
  const rpcArgs = account.isDb
    ? {
      p_offer_id: offerId,
      p_account_id: account.id,
      p_platform: account.platform,
      p_attempt_token: attemptToken,
    }
    : {
      p_offer_id: offerId,
      p_platform: account.platform,
      p_attempt_token: attemptToken,
    };
  const rpcName = account.isDb ? "claim_social_publication_v2" : "claim_social_publication";
  const { data, error } = await supabase.rpc(rpcName, rpcArgs);
  if (error) throw new Error(`SOCIAL_CLAIM_FAILED: ${error.message}`);
  const state = String(data ?? "busy");
  if (state === "claimed" || state === "published") return state;
  return "busy";
}

async function markResult(
  supabase: SupabaseAdmin,
  offerId: string,
  account: Account,
  attemptToken: string,
  result: { status: "published"; postId: string } | { status: "failed"; errorMessage: string },
): Promise<void> {
  const values = result.status === "published"
    ? {
      status: "published",
      post_id: result.postId,
      error_message: "",
      published_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }
    : {
      status: "failed",
      error_message: result.errorMessage.slice(0, 1000),
      updated_at: new Date().toISOString(),
    };
  let query = supabase.from("social_publications").update(values).eq("offer_id", offerId);
  if (account.isDb) {
    query = query.eq("account_id", account.id);
  } else {
    query = query.is("account_id", null).eq("platform", account.platform);
  }
  query = query.eq("attempt_token", attemptToken);
  const { error } = await query;
  if (error && result.status === "published") {
    throw new Error(`SOCIAL_RESULT_SAVE_FAILED: ${error.message}`);
  }
}

// ─── النشر الفعلي لكل منصة ───

async function publishFacebook(
  pageId: string,
  token: string,
  message: string,
  images: string[],
): Promise<string> {
  // Upload photos as unpublished, then attach them to one feed post.
  // فيسبوك يقبل النشر النصي فقط (بلا صور) — الإنستغرام هو من يشترط الصور.
  const mediaIds: string[] = [];
  for (const image of images) {
    const uploaded = await graphPost(`${pageId}/photos`, token, {
      url: image,
      published: "false",
    });
    const id = String(uploaded.id ?? "");
    if (!id) throw new Error("FACEBOOK_PHOTO_ID_MISSING");
    mediaIds.push(id);
  }

  const values: Record<string, string> = { message };
  mediaIds.forEach((id, index) => {
    values[`attached_media[${index}]`] = JSON.stringify({ media_fbid: id });
  });
  const post = await graphPost(`${pageId}/feed`, token, values);
  const id = String(post.id ?? "");
  if (!id) throw new Error("FACEBOOK_POST_ID_MISSING");
  return id;
}

async function publishInstagram(
  instagramId: string,
  token: string,
  caption: string,
  images: string[],
): Promise<string> {
  let creationId = "";
  if (images.length === 1) {
    const container = await graphPost(`${instagramId}/media`, token, {
      image_url: images[0],
      caption,
    });
    creationId = String(container.id ?? "");
  } else {
    const childIds: string[] = [];
    for (const image of images) {
      const child = await graphPost(`${instagramId}/media`, token, {
        image_url: image,
        is_carousel_item: "true",
      });
      const id = String(child.id ?? "");
      if (!id) throw new Error("INSTAGRAM_CHILD_CONTAINER_ID_MISSING");
      childIds.push(id);
    }
    const carousel = await graphPost(`${instagramId}/media`, token, {
      media_type: "CAROUSEL",
      children: childIds.join(","),
      caption,
    });
    creationId = String(carousel.id ?? "");
  }

  if (!creationId) throw new Error("INSTAGRAM_CONTAINER_ID_MISSING");
  const published = await graphPost(`${instagramId}/media_publish`, token, {
    creation_id: creationId,
  });
  const id = String(published.id ?? "");
  if (!id) throw new Error("INSTAGRAM_MEDIA_ID_MISSING");
  return id;
}

// ─── تنفيذ حساب واحد مع الحجز والتسجيل (idempotent لكل حساب) ───

async function runAccount(
  supabase: SupabaseAdmin,
  offerId: string,
  account: Account,
  publish: () => Promise<string>,
): Promise<AccountPublishResult> {
  const base = {
    accountId: account.id,
    accountName: account.name,
    platform: account.platform,
  };
  const attemptToken = crypto.randomUUID();
  const claim = await claimForAccount(supabase, offerId, account, attemptToken);
  if (claim === "published") return { ...base, success: true, skipped: true };
  if (claim === "busy") {
    return { ...base, success: false, skipped: true, error: "PUBLISH_IN_PROGRESS" };
  }

  try {
    const postId = await publish();
    await markResult(supabase, offerId, account, attemptToken, { status: "published", postId });
    return { ...base, success: true, postId };
  } catch (error) {
    const message = safeError(error);
    await markResult(supabase, offerId, account, attemptToken, { status: "failed", errorMessage: message });
    return { ...base, success: false, error: message };
  }
}

// ─── نقطة الدخول الموحّدة ───

export async function publishOfferToSocial(
  supabase: SupabaseAdmin,
  offerId: string,
): Promise<SocialPublishResult> {
  const accounts = await loadAccounts(supabase);
  if (accounts.length === 0) {
    return { success: false, error: "NO_SOCIAL_ACCOUNTS_CONFIGURED" };
  }

  const { data, error } = await supabase
    .from("offers")
    .select("id,i_soc,soc_pub,soc_txt,imgs,sts,i_pub,i_del")
    .eq("id", offerId)
    .single();
  if (error || !data) return { success: false, error: "OFFER_NOT_FOUND" };

  const offer = data as OfferRow;
  if (offer.i_del !== 0 || offer.sts !== 2 || offer.i_pub !== 1) {
    return { success: false, error: "OFFER_NOT_APPROVED" };
  }
  if (offer.i_soc !== 1 || String(offer.soc_txt ?? "").trim().length <= 10) {
    return { success: false, error: "SOCIAL_PUBLISH_NOT_ENABLED" };
  }
  if (offer.soc_pub === 2) return { success: true, alreadyPublished: true };

  const images = cleanImages(offer.imgs);
  const caption = String(offer.soc_txt ?? "").trim().slice(0, 2200);

  // Run sequentially to reduce Meta throttling. Per-account records make retries idempotent.
  // فيسبوك: النشر النصي مسموح بدون صور. إنستغرام: يشترط صورة عامة واحدة على الأقل.
  const accountResults: AccountPublishResult[] = [];
  for (const account of accounts) {
    if (account.platform === "instagram" && images.length === 0) {
      accountResults.push({
        accountId: account.id,
        accountName: account.name,
        platform: "instagram",
        success: false,
        error: "INSTAGRAM_IMAGE_REQUIRED",
      });
      continue;
    }
    const publish = account.platform === "facebook"
      ? () => publishFacebook(account.externalId, account.accessToken, caption, images)
      : () => publishInstagram(account.externalId, account.accessToken, caption, images);
    accountResults.push(await runAccount(supabase, offerId, account, publish));
  }

  // ملخص لكل منصة (متوافق شكلاً مع الاستهلاك السابق في التطبيق).
  const platformResult = (platform: Platform): PlatformResult => {
    const rows = accountResults.filter((r) => r.platform === platform);
    if (rows.length === 0) return { success: true, skipped: true };
    const failures = rows.filter((r) => !r.success);
    return {
      success: failures.length === 0,
      postIds: rows.filter((r) => r.postId).map((r) => r.postId as string),
      error: failures.length === 0 ? undefined : failures.map((r) => r.error ?? "FAILED").join(" | "),
    };
  };
  const facebook = platformResult("facebook");
  const instagram = platformResult("instagram");

  const success = accountResults.every((r) => r.success);
  if (success) {
    await supabase.from("offers").update({ soc_pub: 2 }).eq("id", offerId);
  }
  const failures = accountResults
    .filter((r) => !r.success)
    .map((r) => `${r.accountName}: ${r.error ?? "FAILED"}`);
  return {
    success,
    facebook,
    instagram,
    accounts: accountResults,
    error: success ? undefined : failures.join(" | ") || "PARTIAL_OR_TOTAL_FAILURE",
  };
}

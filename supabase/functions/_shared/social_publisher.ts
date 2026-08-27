// Shared Meta publisher used by publish-to-social and admin-offers.
// Secrets (Supabase Edge Function secrets):
// META_PAGE_ACCESS_TOKEN, META_FACEBOOK_PAGE_ID, META_INSTAGRAM_ACCOUNT_ID
// Optional: META_GRAPH_API_VERSION (default: v25.0)

export type SocialPublishResult = {
  success: boolean;
  alreadyPublished?: boolean;
  facebook?: PlatformResult;
  instagram?: PlatformResult;
  error?: string;
};

type Platform = "facebook" | "instagram";
type PlatformResult = {
  success: boolean;
  skipped?: boolean;
  postId?: string;
  error?: string;
};

type SupabaseAdmin = any;

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

async function claimPlatform(
  supabase: SupabaseAdmin,
  offerId: string,
  platform: Platform,
  attemptToken: string,
): Promise<"claimed" | "published" | "busy"> {
  const { data, error } = await supabase.rpc("claim_social_publication", {
    p_offer_id: offerId,
    p_platform: platform,
    p_attempt_token: attemptToken,
  });
  if (error) throw new Error(`SOCIAL_CLAIM_FAILED: ${error.message}`);
  const state = String(data ?? "busy");
  if (state === "claimed" || state === "published") return state;
  return "busy";
}

async function markPublished(
  supabase: SupabaseAdmin,
  offerId: string,
  platform: Platform,
  attemptToken: string,
  postId: string,
): Promise<void> {
  const { error } = await supabase
    .from("social_publications")
    .update({
      status: "published",
      post_id: postId,
      error_message: "",
      published_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq("offer_id", offerId)
    .eq("platform", platform)
    .eq("attempt_token", attemptToken);
  if (error) throw new Error(`SOCIAL_RESULT_SAVE_FAILED: ${error.message}`);
}

async function markFailed(
  supabase: SupabaseAdmin,
  offerId: string,
  platform: Platform,
  attemptToken: string,
  errorMessage: string,
): Promise<void> {
  await supabase
    .from("social_publications")
    .update({
      status: "failed",
      error_message: errorMessage.slice(0, 1000),
      updated_at: new Date().toISOString(),
    })
    .eq("offer_id", offerId)
    .eq("platform", platform)
    .eq("attempt_token", attemptToken);
}

async function publishFacebook(
  pageId: string,
  token: string,
  message: string,
  images: string[],
): Promise<string> {
  // Upload photos as unpublished, then attach them to one feed post.
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

async function runPlatform(
  supabase: SupabaseAdmin,
  offerId: string,
  platform: Platform,
  publish: () => Promise<string>,
): Promise<PlatformResult> {
  const attemptToken = crypto.randomUUID();
  const claim = await claimPlatform(supabase, offerId, platform, attemptToken);
  if (claim === "published") return { success: true, skipped: true };
  if (claim === "busy") return { success: false, skipped: true, error: "PUBLISH_IN_PROGRESS" };

  try {
    const postId = await publish();
    await markPublished(supabase, offerId, platform, attemptToken, postId);
    return { success: true, postId };
  } catch (error) {
    const message = safeError(error);
    await markFailed(supabase, offerId, platform, attemptToken, message);
    return { success: false, error: message };
  }
}

export async function publishOfferToSocial(
  supabase: SupabaseAdmin,
  offerId: string,
): Promise<SocialPublishResult> {
  const pageToken = env("META_PAGE_ACCESS_TOKEN");
  const pageId = env("META_FACEBOOK_PAGE_ID");
  const instagramId = env("META_INSTAGRAM_ACCOUNT_ID");
  if (!pageToken || !pageId || !instagramId) {
    return { success: false, error: "META_SECRETS_NOT_CONFIGURED" };
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
  if (images.length === 0) return { success: false, error: "PUBLIC_IMAGE_REQUIRED" };
  const caption = String(offer.soc_txt ?? "").trim().slice(0, 2200);

  // Run sequentially to reduce Meta throttling. Per-platform records make retries idempotent.
  const facebook = await runPlatform(
    supabase,
    offerId,
    "facebook",
    () => publishFacebook(pageId, pageToken, caption, images),
  );
  const instagram = await runPlatform(
    supabase,
    offerId,
    "instagram",
    () => publishInstagram(instagramId, pageToken, caption, images),
  );

  const success = facebook.success && instagram.success;
  if (success) {
    await supabase.from("offers").update({ soc_pub: 2 }).eq("id", offerId);
  }
  const failures = [
    !facebook.success ? `Facebook: ${facebook.error ?? "FAILED"}` : "",
    !instagram.success ? `Instagram: ${instagram.error ?? "FAILED"}` : "",
  ].filter(Boolean).join(" | ");
  return { success, facebook, instagram, error: success ? undefined : failures || "PARTIAL_OR_TOTAL_FAILURE" };
}

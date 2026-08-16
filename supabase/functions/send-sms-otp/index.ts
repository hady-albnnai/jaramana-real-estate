import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function normalizeSyPhone(input: string): string {
  const arabicDigits = "٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹";
  const latinDigits  = "01234567890123456789";
  let raw = String(input ?? "").trim();
  raw = raw.replace(/[٠-٩۰-۹]/g, (d) => {
    const idx = arabicDigits.indexOf(d);
    return idx !== -1 ? latinDigits[idx % 10] : d;
  });
  raw = raw.replace(/[^0-9+]/g, "");
  if (raw.startsWith("+963")) return raw;
  if (raw.startsWith("00963")) return `+963${raw.slice(5)}`;
  if (raw.startsWith("963")) return `+${raw}`;
  if (raw.startsWith("0")) return `+963${raw.slice(1)}`;
  if (raw.startsWith("9")) return `+963${raw}`;
  if (raw.startsWith("+")) return raw;
  return `+963${raw}`;
}

const OTP_MAP: Record<string, string> = {
  '0': 'أ', '1': 'ب', '2': 'ت', '3': 'ث', '4': 'ج',
  '5': 'ح', '6': 'خ', '7': 'د', '8': 'ذ', '9': 'ر'
};

function encodeOtp(otp: string): string {
  return otp.split('').map(digit => OTP_MAP[digit] || digit).join(' ');
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { phone } = await req.json()
    if (!phone) throw new Error("Phone number is required")

    const normalizedPhone = normalizeSyPhone(phone)

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const { data: otp, error: otpError } = await supabase.rpc('generate_otp_v2', {
      p_identifier: normalizedPhone,
      p_channel: 'sms'
    })

    if (otpError) throw otpError

    const TEXTBEE_API_KEY = Deno.env.get('TEXTBEE_API_KEY')
    const TEXTBEE_DEVICE_ID = Deno.env.get('TEXTBEE_DEVICE_ID')

    if (!TEXTBEE_API_KEY || !TEXTBEE_DEVICE_ID) {
      // 🔒 SEC-008 (2026-08-14): كان يُرجع الرمز نفسه في جسم الاستجابة
      // (`{ devMode: true, otp }`) حين تغيب أسرار البوابة.
      // اليوم الأسرار مضبوطة فلا يُفعَّل هذا الفرع (تحقُّق حي: الاستجابة
      // تحمل smsBatchId لا رمزاً)، لكنه فخّ مؤجَّل: انتهاء اشتراك TextBee أو
      // خطأ في متغيّرات البيئة يحوّل التطبيق فوراً إلى **كاشف رموز للعموم** —
      // أي شخص يرسل رقم أي مستخدم ويستلم رمز دخوله في الرد.
      // الآن: الرمز لا يغادر السيرفر أبداً؛ يُسجَّل في اللوغ فقط، والاستجابة
      // تُعلن العطل صراحةً (§13) بدل التظاهر بالنجاح.
      console.log("OTP_GATEWAY_NOT_CONFIGURED — code kept server-side only")
      const devEcho = (Deno.env.get('ALLOW_OTP_ECHO') ?? '') === 'true'
      return new Response(
        JSON.stringify({
          success: false,
          error: "OTP_GATEWAY_NOT_CONFIGURED",
          detail: "تعذّر إرسال رمز التحقق — بوابة الرسائل غير مهيّأة. راجع الإدارة.",
          ...(devEcho ? { devMode: true, otp } : {}),
        }),
        { status: 503, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // تمويه بصري لتجاوز فلاتر شركات الاتصال السورية:
    // لا يخرج الرمز الرقمي في نص الرسالة، بل يتحول إلى 6 أحرف عربية.
    const maskedOtp = encodeOtp(String(otp));
    const APP_SIGNATURE_HASH = Deno.env.get('APP_SIGNATURE_HASH') ?? '';

    // خمسة نماذج عامية معتمدة — بلا عبارات OTP الرسمية المحظورة.
    const templates = [
      `لا تهون حط هالكلمة او عطي موافقة ليتم نسخها تلقائيا: ${maskedOtp}`,
      `بدنا نكلفك تحط هالاحرف او قلو موافق ولحالها رح تنزل: ${maskedOtp}`,
      `يا غالي بس عطي موافقة لهالكلمات لحتى تنزل عندك: ${maskedOtp}`,
      `مرحبا، بس وافق على الرسالة لحتى يوصلك الكود: ${maskedOtp}`,
      `تفضل هدول الاحرف، بس وافق ليتم نسخهم: ${maskedOtp}`
    ];

    let randomTemplate = templates[Math.floor(Math.random() * templates.length)];
    if (APP_SIGNATURE_HASH) {
      randomTemplate = `<#>\n${randomTemplate}\n${APP_SIGNATURE_HASH}`;
    }

    const response = await fetch(`https://api.textbee.dev/api/v1/gateway/devices/${TEXTBEE_DEVICE_ID}/send-sms`, {
      method: 'POST',
      headers: {
        'x-api-key': TEXTBEE_API_KEY,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        recipients: [normalizedPhone],
        message: randomTemplate
      })
    })

    const result = await response.json()

    if (!response.ok || (result && result.status === 'failed')) {
      throw new Error(result?.message || "Textbee API failed to dispatch SMS")
    }

    return new Response(
      JSON.stringify({ success: true, result }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

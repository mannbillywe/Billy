// One Gemini generateContent call per HTTP request — no retries, no fan-out.
// API key resolution (first match wins):
// 1) public.profiles.gemini_api_key for the authenticated user (you edit this in Table Editor)
// 2) Edge Function secret GEMINI_API_KEY (optional default for users with no profile key)

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const PROMPT = `You are an expert invoice and bill data extractor. Analyze this image which may contain an invoice, bill, or receipt.

Extract ALL data found. Return ONLY valid JSON (no markdown, no code blocks):

{
  "invoices": [
    {
      "invoice_number": "",
      "invoice_date": "YYYY-MM-DD",
      "due_date": "",
      "vendor_name": "",
      "vendor_address": "",
      "vendor_phone": "",
      "vendor_email": "",
      "vendor_gstin": "",
      "buyer_name": "",
      "buyer_address": "",
      "buyer_gstin": "",
      "line_items": [
        {"description": "", "quantity": 1, "unit_price": 0, "amount": 0, "hsn_code": "", "category": ""}
      ],
      "subtotal": 0,
      "discount": 0,
      "gst": 0,
      "cgst": 0,
      "cgst_rate": 0,
      "sgst": 0,
      "sgst_rate": 0,
      "igst": 0,
      "igst_rate": 0,
      "other_taxes": 0,
      "total_amount": 0,
      "currency": "INR",
      "category": "",
      "payment_method": "",
      "payment_status": "",
      "notes": ""
    }
  ],
  "total_invoices_found": 1,
  "extraction_confidence": "high"
}

Invoice-level category and each line_item.category must be one of: Food & Beverage, Laundry, Room Service, Housekeeping Supplies, Kitchen Supplies, Maintenance, Vendor Supplies, Utilities, Guest Amenities, Equipment, Stationery, Transportation, Groceries, Shopping, Dining, Other.

Rules:
- Extract ALL invoices if multiple are present (use first invoice if UI only needs one; still list all in invoices array).
- If a field is not found, use "" for text or 0 for numbers.
- Convert all amounts to numbers (remove ₹, Rs, commas).
- Extract CGST, SGST, IGST as separate numbers when printed on the document.
- Extract discount as its own number when present.
- For each line item, suggest the best category from the list.
- Return ONLY valid JSON.`;

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseAnon, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user }, error: authErr } = await supabase.auth.getUser();
    if (authErr || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json().catch(() => ({}));
    const image_base64 = body.image_base64 as string | undefined;
    const mime_type = (body.mime_type as string) || "image/jpeg";

    if (!image_base64 || typeof image_base64 !== "string") {
      return new Response(JSON.stringify({ error: "image_base64 required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Per-user key from profiles (RLS: user can read own row). No key sent from the Flutter app.
    const { data: profile, error: profileErr } = await supabase
      .from("profiles")
      .select("gemini_api_key")
      .eq("id", user.id)
      .maybeSingle();

    if (profileErr) {
      console.error("extract-invoice: profile read", profileErr.message);
    }

    const fromProfile = profile?.gemini_api_key?.trim() ?? "";
    const fromSecret = Deno.env.get("GEMINI_API_KEY")?.trim() ?? "";
    const geminiKey = fromProfile.length > 0 ? fromProfile : fromSecret;

    if (!geminiKey) {
      console.error(
        "extract-invoice: no API key — set profiles.gemini_api_key for this user and/or GEMINI_API_KEY secret",
      );
      return new Response(
        JSON.stringify({
          error:
            "No Gemini API key configured. Add gemini_api_key on your profile row in Supabase, or set GEMINI_API_KEY on the Edge Function.",
        }),
        {
          status: 503,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const keySource = fromProfile.length > 0 ? "profiles.gemini_api_key" : "GEMINI_API_KEY secret";
    console.log(
      `extract-invoice: start user=${user.id} key_source=${keySource} b64_len=${image_base64.length} mime=${mime_type}`,
    );

    const model = "gemini-2.0-flash";
    const url =
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${geminiKey}`;

    const geminiRes = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              { text: PROMPT },
              { inline_data: { mime_type, data: image_base64 } },
            ],
          },
        ],
        generationConfig: { temperature: 0.1, maxOutputTokens: 8192 },
      }),
    });

    if (!geminiRes.ok) {
      const errText = await geminiRes.text();
      console.error("extract-invoice: gemini http", geminiRes.status, errText.slice(0, 400));
      return new Response(
        JSON.stringify({
          error: `Gemini error ${geminiRes.status}`,
          detail: errText.slice(0, 500),
        }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const geminiJson = await geminiRes.json();
    const text = geminiJson?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!text || typeof text !== "string") {
      console.error("extract-invoice: empty model text", JSON.stringify(geminiJson).slice(0, 400));
      return new Response(JSON.stringify({ error: "Empty model response" }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    let jsonStr = text.trim();
    if (jsonStr.startsWith("```")) {
      jsonStr = jsonStr.replace(/^```\w*\n?/, "").replace(/\n?```$/, "");
    }
    if (!jsonStr.startsWith("{")) {
      const m = jsonStr.match(/\{[\s\S]*\}/);
      if (m) jsonStr = m[0];
    }

    const extraction = JSON.parse(jsonStr);
    console.log("extract-invoice: success");

    return new Response(JSON.stringify({ extraction }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("extract-invoice: failure", e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

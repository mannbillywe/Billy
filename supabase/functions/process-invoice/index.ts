// process-invoice: Storage → Gemini (one generateContent per file) → Postgres
// API key (first match): profiles.gemini_api_key for JWT user, else Edge secret GEMINI_API_KEY
// Model: gemini-2.0-flash — balanced latency + cost for invoice/receipt images & PDFs

import { encode as encodeBase64 } from "https://deno.land/std@0.224.0/encoding/base64.ts";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const GEMINI_MODEL = "gemini-2.0-flash";

type Json = Record<string, unknown>;

const EXTRACTION_PROMPT = `You are an expert invoice and bill data extractor. Analyze this document (image or PDF).

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
      "sgst": 0,
      "igst": 0,
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

Rules:
- Use first invoice if multiple; still list all in invoices if present.
- Missing text fields: "". Missing numbers: 0.
- Amounts as numbers (strip ₹, Rs, commas).
- extraction_confidence: "high", "medium", or "low".
- Return ONLY valid JSON.`;

function corsHeadersFor(req: Request): Record<string, string> {
  const requested = req.headers.get("access-control-request-headers");
  const allowHeaders =
    requested?.trim() ||
    "authorization, x-client-info, apikey, content-type, accept, accept-encoding";
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": allowHeaders,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
  };
}

function jsonResponse(body: Json, req: Request, status = 200): Response {
  const cors = corsHeadersFor(req);
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

interface NormalizedLine {
  description: string | null;
  quantity: number | null;
  unit_price: number | null;
  amount: number | null;
  tax_percent: number | null;
  tax_amount: number | null;
  item_code: string | null;
  category: string | null;
}

interface NormalizedInvoice {
  vendor_name: string | null;
  vendor_gstin: string | null;
  invoice_number: string | null;
  invoice_date: string | null;
  due_date: string | null;
  subtotal: number | null;
  cgst: number | null;
  sgst: number | null;
  igst: number | null;
  cess: number | null;
  discount: number | null;
  total_tax: number | null;
  total: number | null;
  currency: string | null;
  payment_status: string | null;
  raw_text: string | null;
  confidence: number | null;
  document_type: string | null;
  line_items: NormalizedLine[];
}

function num(v: unknown): number | null {
  if (v == null) return null;
  if (typeof v === "number" && Number.isFinite(v)) return v;
  const s = String(v).replace(/[₹Rs,\s]/gi, "").trim();
  const n = parseFloat(s);
  return Number.isFinite(n) ? n : null;
}

function str(v: unknown): string | null {
  if (v == null) return null;
  const t = String(v).trim();
  return t.length ? t : null;
}

function parseDateIso(s: string | null | undefined): string | null {
  if (!s) return null;
  const t = s.trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(t)) return t;
  return t.split("T")[0] ?? null;
}

function normalizeFromGeminiJson(
  parsed: Record<string, unknown>,
  rawSnippet: string,
): NormalizedInvoice {
  let inv: Record<string, unknown> = parsed;
  const invs = parsed.invoices;
  if (Array.isArray(invs) && invs.length > 0 && invs[0] && typeof invs[0] === "object") {
    inv = invs[0] as Record<string, unknown>;
  }

  const itemsRaw = inv.line_items;
  const line_items: NormalizedLine[] = [];
  if (Array.isArray(itemsRaw)) {
    for (const it of itemsRaw) {
      if (!it || typeof it !== "object") continue;
      const o = it as Record<string, unknown>;
      const qty = num(o.quantity) ?? 1;
      const unit = num(o.unit_price);
      const amt = num(o.amount) ?? num(o.total) ?? null;
      line_items.push({
        description: str(o.description),
        quantity: qty,
        unit_price: unit,
        amount: amt,
        tax_percent: num(o.tax_percent),
        tax_amount: num(o.tax_amount),
        item_code: str(o.hsn_code) ?? str(o.item_code),
        category: str(o.category),
      });
    }
  }

  const cgst = num(inv.cgst) ?? 0;
  const sgst = num(inv.sgst) ?? 0;
  const igst = num(inv.igst) ?? 0;
  const gst = num(inv.gst) ?? 0;
  const explicit = cgst + sgst + igst;
  const total_tax = explicit > 0 ? explicit : gst;

  const confStr = str(parsed.extraction_confidence) ?? str(inv.extraction_confidence);
  let confidence: number | null = null;
  if (confStr === "high") confidence = 0.9;
  else if (confStr === "medium") confidence = 0.65;
  else if (confStr === "low") confidence = 0.35;

  const total =
    num(inv.total_amount) ?? num(inv.total) ?? num(inv.amount_due);
  const subtotal = num(inv.subtotal);

  return {
    vendor_name: str(inv.vendor_name),
    vendor_gstin: str(inv.vendor_gstin),
    invoice_number: str(inv.invoice_number),
    invoice_date: parseDateIso(str(inv.invoice_date) ?? undefined),
    due_date: parseDateIso(str(inv.due_date) ?? undefined),
    subtotal,
    cgst: cgst || null,
    sgst: sgst || null,
    igst: igst || null,
    cess: num(inv.cess) ?? num(inv.other_taxes),
    discount: num(inv.discount),
    total_tax: total_tax || null,
    total,
    currency: str(inv.currency) ?? "INR",
    payment_status: str(inv.payment_status),
    raw_text: rawSnippet.length > 12000 ? rawSnippet.slice(0, 12000) : rawSnippet,
    confidence,
    document_type: str(inv.category) ?? "invoice",
    line_items,
  };
}

async function callGeminiOnce(
  apiKey: string,
  base64: string,
  mimeType: string,
): Promise<{ raw: unknown; replyText: string }> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${encodeURIComponent(apiKey)}`;

  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [
        {
          parts: [
            { text: EXTRACTION_PROMPT },
            { inline_data: { mime_type: mimeType, data: base64 } },
          ],
        },
      ],
      generationConfig: { temperature: 0.1, maxOutputTokens: 8192 },
    }),
  });

  const json = (await res.json()) as Record<string, unknown>;
  if (!res.ok) {
    throw new Error(`Gemini HTTP ${res.status}: ${JSON.stringify(json).slice(0, 500)}`);
  }

  const text = (json as { candidates?: { content?: { parts?: { text?: string }[] } }[] })
    .candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text || typeof text !== "string") {
    throw new Error("Empty Gemini response text");
  }
  return { raw: json, replyText: text };
}

function parseJsonFromModelText(text: string): Record<string, unknown> {
  let s = text.trim();
  if (s.startsWith("```")) {
    s = s.replace(/^```\w*\n?/, "").replace(/\n?```$/, "");
  }
  if (!s.startsWith("{")) {
    const m = s.match(/\{[\s\S]*\}/);
    if (m) s = m[0];
  }
  return JSON.parse(s) as Record<string, unknown>;
}

serve(async (req) => {
  const cors = corsHeadersFor(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  if (req.method !== "POST") {
    return jsonResponse(
      { success: false, error: { code: "METHOD_NOT_ALLOWED", message: "POST only" } },
      req,
      405,
    );
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse(
      { success: false, error: { code: "UNAUTHORIZED", message: "Missing authorization" } },
      req,
      401,
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseAnon, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) {
    return jsonResponse(
      { success: false, error: { code: "UNAUTHORIZED", message: "Invalid session" } },
      req,
      401,
    );
  }

  let body: Json;
  try {
    body = (await req.json()) as Json;
  } catch {
    return jsonResponse(
      { success: false, error: { code: "INVALID_INPUT", message: "Invalid JSON body" } },
      req,
      400,
    );
  }

  const invoiceId = typeof body.invoice_id === "string" ? body.invoice_id : null;
  const filePath = typeof body.file_path === "string" ? body.file_path : null;
  const forceReprocess = body.force_reprocess === true;

  if (!invoiceId || !filePath) {
    return jsonResponse(
      {
        success: false,
        error: { code: "INVALID_INPUT", message: "invoice_id and file_path required" },
      },
      req,
      400,
    );
  }

  if (!filePath.startsWith(`${user.id}/`)) {
    return jsonResponse(
      {
        success: false,
        error: { code: "INVALID_INPUT", message: "file_path must be under your user folder" },
      },
      req,
      403,
    );
  }

  const { data: invRow, error: invErr } = await supabase
    .from("invoices")
    .select("id,user_id,status,file_path,mime_type")
    .eq("id", invoiceId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (invErr || !invRow) {
    return jsonResponse(
      { success: false, error: { code: "NOT_FOUND", message: "Invoice not found" } },
      req,
      404,
    );
  }

  if (invRow.file_path !== filePath) {
    return jsonResponse(
      { success: false, error: { code: "INVALID_INPUT", message: "file_path does not match invoice" } },
      req,
      400,
    );
  }

  if (!forceReprocess && invRow.status === "completed") {
    const { data: full } = await supabase.from("invoices").select("*").eq("id", invoiceId).single();
    const { data: items } = await supabase.from("invoice_items").select("*").eq("invoice_id", invoiceId);
    return jsonResponse({
      success: true,
      invoice: full,
      items: items ?? [],
      cached: true,
    }, req);
  }

  const logInsert = async (
    status: string,
    err: string | null,
    reqPayload: Json | null,
    resPayload: unknown,
    norm: unknown,
  ) => {
    await supabase.from("invoice_ocr_logs").insert({
      invoice_id: invoiceId,
      user_id: user.id,
      request_payload: reqPayload,
      response_payload: resPayload as Json,
      normalized_payload: norm as Json,
      status,
      error_message: err,
    });
  };

  const event = async (step: string, detail?: Json) => {
    await supabase.from("invoice_processing_events").insert({
      invoice_id: invoiceId,
      user_id: user.id,
      step,
      detail: detail ?? null,
    });
  };

  const { data: profile, error: profErr } = await supabase
    .from("profiles")
    .select("gemini_api_key")
    .eq("id", user.id)
    .maybeSingle();

  if (profErr) {
    console.error("process-invoice: profile read", profErr.message);
  }

  const fromProfile = (profile?.gemini_api_key as string | null)?.trim() ?? "";
  const fromSecret = Deno.env.get("GEMINI_API_KEY")?.trim() ?? "";
  const geminiKey = fromProfile.length > 0 ? fromProfile : fromSecret;

  if (!geminiKey) {
    const msg =
      "No Gemini API key: set profiles.gemini_api_key for this user and/or GEMINI_API_KEY on the function.";
    await logInsert("failed", msg, body, null, null);
    await supabase.from("invoices").update({ status: "failed", processing_error: msg }).eq(
      "id",
      invoiceId,
    );
    return jsonResponse(
      {
        success: false,
        error: { code: "CONFIG_ERROR", message: msg },
      },
      req,
      503,
    );
  }

  const keySource = fromProfile.length > 0 ? "profiles.gemini_api_key" : "GEMINI_API_KEY secret";
  console.log(
    `process-invoice: user=${user.id} key_source=${keySource} model=${GEMINI_MODEL}`,
  );

  await event("processing_started", { file_path: filePath, model: GEMINI_MODEL });
  await supabase.from("invoices").update({ status: "processing", processing_error: null }).eq(
    "id",
    invoiceId,
  );

  const mimeType = (invRow.mime_type as string) || "application/octet-stream";
  const { data: fileData, error: dlErr } = await supabase.storage.from("invoice-files").download(
    filePath,
  );

  if (dlErr || !fileData) {
    const msg = dlErr?.message ?? "Download failed";
    await logInsert("failed", msg, body, null, null);
    await event("storage_failed", { error: msg });
    await supabase.from("invoices").update({ status: "failed", processing_error: msg }).eq(
      "id",
      invoiceId,
    );
    return jsonResponse(
      { success: false, error: { code: "STORAGE_ERROR", message: "Could not read file from storage" } },
      req,
      502,
    );
  }

  const buf = new Uint8Array(await fileData.arrayBuffer());
  if (buf.byteLength > 16 * 1024 * 1024) {
    const msg = "File too large (max 16MB)";
    await supabase.from("invoices").update({ status: "failed", processing_error: msg }).eq(
      "id",
      invoiceId,
    );
    return jsonResponse(
      { success: false, error: { code: "INVALID_INPUT", message: msg } },
      req,
      400,
    );
  }

  const b64 = encodeBase64(buf);

  let geminiRaw: unknown = null;
  let replyText = "";
  try {
    const out = await callGeminiOnce(geminiKey, b64, mimeType);
    geminiRaw = out.raw;
    replyText = out.replyText;
  } catch (e) {
    const msg = String(e);
    await logInsert("failed", msg, body, geminiRaw, null);
    await event("gemini_failed", { error: msg.slice(0, 300) });
    await supabase.from("invoices").update({ status: "failed", processing_error: msg }).eq(
      "id",
      invoiceId,
    );
    return jsonResponse(
      {
        success: false,
        error: { code: "OCR_PROCESSING_FAILED", message: "Gemini request failed" },
      },
      req,
      502,
    );
  }

  let parsed: Record<string, unknown>;
  try {
    parsed = parseJsonFromModelText(replyText);
  } catch (e) {
    const msg = `JSON parse: ${String(e)}`;
    await logInsert("failed", msg, body, geminiRaw, { text_preview: replyText.slice(0, 2000) });
    await supabase.from("invoices").update({ status: "failed", processing_error: msg }).eq(
      "id",
      invoiceId,
    );
    return jsonResponse(
      {
        success: false,
        error: { code: "OCR_PROCESSING_FAILED", message: "Could not parse model output" },
      },
      req,
      502,
    );
  }

  const norm = normalizeFromGeminiJson(parsed, replyText);
  await logInsert("success", null, body, geminiRaw, norm);

  await supabase.from("invoice_items").delete().eq("invoice_id", invoiceId);

  const itemRows = norm.line_items.map((li) => {
    let amt = li.amount;
    if (amt == null && li.unit_price != null && li.quantity != null) {
      amt = li.unit_price * li.quantity;
    }
    return {
      invoice_id: invoiceId,
      user_id: user.id,
      assigned_user_id: null,
      description: li.description,
      quantity: li.quantity,
      unit_price: li.unit_price,
      amount: amt,
      tax_percent: li.tax_percent,
      tax_amount: li.tax_amount,
      item_code: li.item_code,
      category: li.category,
    };
  });

  if (itemRows.length > 0) {
    await supabase.from("invoice_items").insert(itemRows);
  }

  const updateRow = {
    status: "completed",
    ocr_provider: `google_${GEMINI_MODEL.replace(/[.-]/g, "_")}`,
    vendor_name: norm.vendor_name,
    vendor_gstin: norm.vendor_gstin,
    invoice_number: norm.invoice_number,
    invoice_date: norm.invoice_date,
    due_date: norm.due_date,
    subtotal: norm.subtotal,
    cgst: norm.cgst,
    sgst: norm.sgst,
    igst: norm.igst,
    cess: norm.cess,
    discount: norm.discount,
    total_tax: norm.total_tax,
    total: norm.total,
    currency: norm.currency ?? "INR",
    payment_status: norm.payment_status,
    raw_text: norm.raw_text,
    confidence: norm.confidence,
    document_type: norm.document_type,
    review_required: true,
    processing_error: null,
  };

  await supabase.from("invoices").update(updateRow).eq("id", invoiceId);
  await event("processing_completed", { items: itemRows.length, model: GEMINI_MODEL });

  const { data: fullInv } = await supabase.from("invoices").select("*").eq("id", invoiceId).single();
  const { data: itemsOut } = await supabase.from("invoice_items").select("*").eq(
    "invoice_id",
    invoiceId,
  );

  return jsonResponse({
    success: true,
    invoice: fullInv,
    items: itemsOut ?? [],
  }, req);
});

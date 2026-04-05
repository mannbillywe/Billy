// analytics-insights: deterministic spend analytics + optional single Gemini call per manual refresh.
// API key: shared app_api_keys table ('gemini'), else GEMINI_API_KEY. User JWT required; all reads respect RLS.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const GEMINI_MODEL = "gemini-2.5-flash-lite";

type Json = Record<string, unknown>;

function corsHeadersFor(req: Request): Record<string, string> {
  const requested = req.headers.get("access-control-request-headers");
  const allowHeaders =
    requested?.trim() ||
    "authorization, x-client-info, apikey, content-type, accept, accept-encoding";
  const origin = req.headers.get("Origin");
  const allowOrigin =
    origin && (origin.startsWith("http://") || origin.startsWith("https://")) ? origin : "*";
  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Headers": allowHeaders,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
}

function jsonResponse(body: Json, req: Request, status = 200): Response {
  const cors = corsHeadersFor(req);
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function dayEnd(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);
}

function dayStart(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);
}

function toYmd(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

/** Same calendar logic as app `DocumentDateRange.forFilter`. */
function windowForPreset(preset: string, now = new Date()): {
  start: Date;
  end: Date;
  prevStart: Date;
  prevEnd: Date;
} {
  const end = dayEnd(now);
  let start: Date;
  switch (preset) {
    case "1W":
      start = dayStart(new Date(now.getFullYear(), now.getMonth(), now.getDate() - 7));
      break;
    case "3M":
      start = dayStart(new Date(now.getFullYear(), now.getMonth() - 3, now.getDate()));
      break;
    case "1M":
    default:
      start = dayStart(new Date(now.getFullYear(), now.getMonth() - 1, now.getDate()));
      break;
  }
  const lenMs = end.getTime() - start.getTime();
  const prevEnd = new Date(start.getTime() - 86400000);
  prevEnd.setHours(23, 59, 59, 999);
  const prevStart = new Date(prevEnd.getTime() - lenMs);
  prevStart.setHours(0, 0, 0, 0);
  return { start, end, prevStart, prevEnd: dayEnd(prevEnd) };
}

interface DocRow {
  id: string;
  amount: number | null;
  date: string | null;
  vendor_name: string | null;
  description: string | null;
  tax_amount: number | null;
  currency: string | null;
  extracted_data: unknown;
  category_id: string | null;
  status: string | null;
  updated_at: string | null;
}

function num(v: unknown): number {
  if (typeof v === "number" && !Number.isNaN(v)) return v;
  if (typeof v === "string") return parseFloat(v) || 0;
  return 0;
}

function isDraft(d: DocRow): boolean {
  return (d.status ?? "") === "draft";
}

function edMap(d: DocRow): Record<string, unknown> | null {
  const ed = d.extracted_data;
  if (ed && typeof ed === "object" && !Array.isArray(ed)) return ed as Record<string, unknown>;
  return null;
}

function isOcrDoc(d: DocRow): boolean {
  const ed = edMap(d);
  const id = ed?.invoice_id;
  return id != null && String(id).trim() !== "";
}

function extractionConfidence(d: DocRow): string {
  const ed = edMap(d);
  const c = ed?.extraction_confidence;
  return typeof c === "string" ? c.toLowerCase() : "medium";
}

function needsReviewDoc(d: DocRow): boolean {
  if (!isOcrDoc(d)) return false;
  if (extractionConfidence(d) === "low") return true;
  const ed = edMap(d);
  if (ed?.user_flagged_mismatch === true) return true;
  return false;
}

function categoryLabel(d: DocRow): string {
  if (d.category_id != null && String(d.category_id).length > 0) {
    const desc = (d.description ?? "").split(",").map((s) => s.trim()).filter(Boolean);
    if (desc.length > 0) return desc[0]!;
  }
  const ed = edMap(d);
  const c = ed?.category;
  if (typeof c === "string" && c.trim()) return c.trim();
  const first = (d.description ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  if (first.length > 0) return first[0];
  return "Uncategorized";
}

function isUncategorized(d: DocRow): boolean {
  const hasCatId = d.category_id != null && String(d.category_id).trim() !== "";
  if (hasCatId) return false;
  const lab = categoryLabel(d);
  return lab === "Uncategorized" || lab === "Other";
}

function fingerprintFor(docs: DocRow[]): string {
  let maxU = "";
  for (const d of docs) {
    const u = d.updated_at ?? "";
    if (u > maxU) maxU = u;
  }
  const total = docs.reduce((s, d) => s + num(d.amount), 0);
  return `${docs.length}:${maxU}:${Math.round(total * 100)}`;
}

function findDuplicateGroups(docs: DocRow[]): { document_ids: string[]; reason: string }[] {
  const map = new Map<string, string[]>();
  for (const d of docs) {
    if (isDraft(d)) continue;
    const amt = num(d.amount);
    const date = d.date ?? "";
    const v = (d.vendor_name ?? "").toLowerCase().replace(/\s+/g, " ").trim().slice(0, 48);
    const key = `${date}|${amt.toFixed(2)}|${v}`;
    if (!map.has(key)) map.set(key, []);
    map.get(key)!.push(d.id);
  }
  const out: { document_ids: string[]; reason: string }[] = [];
  for (const ids of map.values()) {
    if (ids.length >= 2) {
      out.push({
        document_ids: ids,
        reason: "Same date, amount, and merchant name.",
      });
    }
  }
  return out;
}

function rollup(
  docs: DocRow[],
  prevDocs: DocRow[],
  preset: string,
  rangeStart: string,
  rangeEnd: string,
): Json {
  const active = docs.filter((d) => !isDraft(d));
  const prevActive = prevDocs.filter((d) => !isDraft(d));

  const total = active.reduce((s, d) => s + num(d.amount), 0);
  const prevTotal = prevActive.reduce((s, d) => s + num(d.amount), 0);
  const changePct = prevTotal > 0 ? Math.round(((total - prevTotal) / prevTotal) * 100) : null;

  const merchantMap = new Map<string, { amount: number; count: number }>();
  for (const d of active) {
    const name = (d.vendor_name ?? "Unknown").trim() || "Unknown";
    const cur = merchantMap.get(name) ?? { amount: 0, count: 0 };
    cur.amount += num(d.amount);
    cur.count += 1;
    merchantMap.set(name, cur);
  }
  const topMerchants = [...merchantMap.entries()]
    .map(([name, v]) => ({ name, amount: v.amount, count: v.count }))
    .sort((a, b) => b.amount - a.amount)
    .slice(0, 8);

  const catMap = new Map<string, number>();
  for (const d of active) {
    const c = categoryLabel(d);
    catMap.set(c, (catMap.get(c) ?? 0) + num(d.amount));
  }
  const topCategories = [...catMap.entries()]
    .map(([name, amount]) => ({ name, amount }))
    .sort((a, b) => b.amount - a.amount)
    .slice(0, 8);

  let taxTotal = 0;
  let docsWithTax = 0;
  for (const d of active) {
    const t = num(d.tax_amount);
    if (t > 0) {
      taxTotal += t;
      docsWithTax += 1;
    }
  }

  const uncategorized = active.filter(isUncategorized);
  const lowConf = active.filter((d) => isOcrDoc(d) && extractionConfidence(d) === "low");
  const reviewQueue = active.filter(needsReviewDoc);
  const dups = findDuplicateGroups(active);

  return {
    period: { preset, start: rangeStart, end: rangeEnd },
    summary: {
      total_spend: total,
      document_count: active.length,
      previous_period_total: prevTotal,
      change_vs_previous_pct: changePct,
    },
    top_merchants: topMerchants,
    top_categories: topCategories,
    tax_summary: {
      total_tax: taxTotal,
      documents_with_tax: docsWithTax,
    },
    needs_attention: {
      uncategorized_count: uncategorized.length,
      uncategorized_document_ids: uncategorized.map((d) => d.id),
      low_confidence_ocr_count: lowConf.length,
      low_confidence_document_ids: lowConf.map((d) => d.id),
      review_recommended_count: reviewQueue.length,
      review_recommended_document_ids: reviewQueue.map((d) => d.id),
      duplicate_groups: dups,
    },
    fingerprint: fingerprintFor(active),
  };
}

async function resolveGeminiKey(
  supabase: ReturnType<typeof createClient>,
  _userId: string,
): Promise<{ key: string; source: string } | null> {
  // Use shared app_api_keys table, fall back to env secret
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceClient = createClient(supabaseUrl, supabaseAnon, {
    global: { headers: { Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? supabaseAnon}` } },
  });
  const { data: sharedRow } = await serviceClient
    .from("app_api_keys")
    .select("api_key")
    .eq("provider", "gemini")
    .eq("is_active", true)
    .maybeSingle();

  const fromShared = (sharedRow?.api_key as string | null)?.trim() ?? "";
  const fromSecret = Deno.env.get("GEMINI_API_KEY")?.trim() ?? "";
  const key = fromShared.length > 0 ? fromShared : fromSecret;
  if (!key) return null;
  const source = fromShared.length > 0 ? "app_api_keys" : "GEMINI_API_KEY";
  return { key, source };
}

async function callGeminiRangeInsights(apiKey: string, det: Json): Promise<Json | null> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${encodeURIComponent(apiKey)}`;

  const prompt =
    `You are a concise financial analyst for a personal receipt app. You ONLY use the JSON summary below (already computed from the user's documents). Do not invent merchants or amounts.

Rules:
- Output ONLY valid JSON, no markdown.
- Tone: calm, direct, practical. No motivational language. No generic money advice.
- Max 2 sentences for short_narrative.
- prioritized_insights: 0 to 5 items, each 1 line. Only include items that are useful and tied to the data.
- Each insight: type (duplicate|category|tax|trend|review|other), text (short), optional document_ids (string[]) when applicable.

Input summary:
${JSON.stringify(det)}

Return JSON shape:
{"short_narrative":"","prioritized_insights":[{"type":"","text":"","document_ids":[]}]}`;

  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { temperature: 0.2, maxOutputTokens: 1024 },
    }),
  });

  const json = (await res.json()) as Record<string, unknown>;
  if (!res.ok) {
    console.error("analytics-insights Gemini", res.status, JSON.stringify(json).slice(0, 400));
    return null;
  }
  const text = (json as { candidates?: { content?: { parts?: { text?: string }[] } }[] })
    .candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text || typeof text !== "string") return null;

  let s = text.trim();
  if (s.startsWith("```")) {
    s = s.replace(/^```\w*\n?/, "").replace(/\n?```$/, "");
  }
  if (!s.startsWith("{")) {
    const m = s.match(/\{[\s\S]*\}/);
    if (m) s = m[0];
  }
  try {
    return JSON.parse(s) as Json;
  } catch {
    return null;
  }
}

async function callGeminiDocumentReview(apiKey: string, docSummary: Json): Promise<Json | null> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${encodeURIComponent(apiKey)}`;

  const prompt =
    `You review one saved receipt/invoice record. Use ONLY the JSON below. Output ONLY valid JSON, no markdown.

{"review_summary":"1-2 sentences","checks":[{"label":"short","ok":true,"detail":"optional"}],"suggested_actions":["optional short bullets"]}

Input:
${JSON.stringify(docSummary)}`;

  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { temperature: 0.2, maxOutputTokens: 512 },
    }),
  });

  const json = (await res.json()) as Record<string, unknown>;
  if (!res.ok) return null;
  const text = (json as { candidates?: { content?: { parts?: { text?: string }[] } }[] })
    .candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text || typeof text !== "string") return null;
  let s = text.trim();
  if (s.startsWith("```")) {
    s = s.replace(/^```\w*\n?/, "").replace(/\n?```$/, "");
  }
  if (!s.startsWith("{")) {
    const m = s.match(/\{[\s\S]*\}/);
    if (m) s = m[0];
  }
  try {
    return JSON.parse(s) as Json;
  } catch {
    return null;
  }
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

  const documentId = typeof body.document_id === "string" ? body.document_id : null;
  const includeAi = body.include_ai === true;

  if (documentId) {
    const { data: doc, error: docErr } = await supabase
      .from("documents")
      .select(
        "id,amount,date,vendor_name,description,tax_amount,currency,extracted_data,category_id,status,updated_at",
      )
      .eq("id", documentId)
      .eq("user_id", user.id)
      .maybeSingle();

    if (docErr || !doc) {
      return jsonResponse(
        { success: false, error: { code: "NOT_FOUND", message: "Document not found" } },
        req,
        404,
      );
    }

    const row = doc as unknown as DocRow;
    const det: Json = {
      mode: "document",
      document: {
        id: row.id,
        vendor_name: row.vendor_name,
        amount: num(row.amount),
        date: row.date,
        tax_amount: num(row.tax_amount),
        currency: row.currency,
        category_label: categoryLabel(row),
        is_ocr: isOcrDoc(row),
        extraction_confidence: extractionConfidence(row),
        needs_review: needsReviewDoc(row),
      },
    };

    let ai_layer: Json | null = null;
    let gemini_used = false;
    if (includeAi) {
      const keyInfo = await resolveGeminiKey(supabase, user.id);
      if (keyInfo) {
        ai_layer = await callGeminiDocumentReview(keyInfo.key, det);
        gemini_used = ai_layer != null;
      }
    }

    return jsonResponse({
      success: true,
      mode: "document",
      deterministic: det,
      ai_layer,
      generated_at: new Date().toISOString(),
      data_fingerprint: fingerprintFor([row]),
      gemini_used,
    }, req);
  }

  const rangePreset = typeof body.range_preset === "string" ? body.range_preset : null;
  if (!rangePreset || !["1W", "1M", "3M"].includes(rangePreset)) {
    return jsonResponse(
      {
        success: false,
        error: { code: "INVALID_INPUT", message: "range_preset must be 1W, 1M, or 3M" },
      },
      req,
      400,
    );
  }

  const { start, end, prevStart, prevEnd } = windowForPreset(rangePreset);
  const startStr = toYmd(start);
  const endStr = toYmd(end);
  const pStartStr = toYmd(prevStart);
  const pEndStr = toYmd(prevEnd);

  const { data: docsRaw, error: qErr } = await supabase
    .from("documents")
    .select(
      "id,amount,date,vendor_name,description,tax_amount,currency,extracted_data,category_id,status,updated_at",
    )
    .eq("user_id", user.id)
    .gte("date", startStr)
    .lte("date", endStr);

  if (qErr) {
    console.error("analytics-insights query", qErr.message);
    return jsonResponse(
      { success: false, error: { code: "QUERY_ERROR", message: qErr.message } },
      req,
      500,
    );
  }

  const { data: prevRaw } = await supabase
    .from("documents")
    .select(
      "id,amount,date,vendor_name,description,tax_amount,currency,extracted_data,category_id,status,updated_at",
    )
    .eq("user_id", user.id)
    .gte("date", pStartStr)
    .lte("date", pEndStr);

  const docs = (docsRaw ?? []) as unknown as DocRow[];
  const prevDocs = (prevRaw ?? []) as unknown as DocRow[];

  const deterministic = rollup(docs, prevDocs, rangePreset, startStr, endStr);

  let ai_layer: Json | null = null;
  let gemini_used = false;
  if (includeAi) {
    const keyInfo = await resolveGeminiKey(supabase, user.id);
    if (keyInfo) {
      ai_layer = await callGeminiRangeInsights(keyInfo.key, deterministic);
      gemini_used = ai_layer != null;
    }
  }

  const fp = deterministic.fingerprint as string;
  const generatedAt = new Date().toISOString();

  const { error: upErr } = await supabase.from("analytics_insight_snapshots").upsert(
    {
      user_id: user.id,
      range_preset: rangePreset,
      range_start: startStr,
      range_end: endStr,
      data_fingerprint: fp,
      deterministic,
      ai_layer: includeAi ? ai_layer : null,
      generated_at: generatedAt,
    },
    { onConflict: "user_id,range_preset" },
  );

  if (upErr) {
    console.error("analytics-insights upsert", upErr.message);
  }

  return jsonResponse({
    success: true,
    mode: "range",
    deterministic,
    ai_layer,
    generated_at: generatedAt,
    data_fingerprint: fp,
    gemini_used,
  }, req);
});

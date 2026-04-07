// statement-classify: small Gemini pass-1 for document_family + hints from text excerpt only.
// Auth: caller JWT; updates own statement_imports row via RLS.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

import { corsHeadersFor } from "../_shared/cors.ts";
import { resolveGoatGeminiKey } from "../_shared/resolve_gemini_key.ts";

const GEMINI_MODEL = "gemini-2.5-flash-lite";

type Json = Record<string, unknown>;

function jsonResponse(body: Json, req: Request, status = 200): Response {
  const cors = corsHeadersFor(req);
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req) });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, req, 405);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!supabaseUrl || !anonKey) {
    return jsonResponse({ error: "server_misconfigured" }, req, 500);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) {
    return jsonResponse({ error: "unauthorized" }, req, 401);
  }
  const userId = userData.user.id;

  let body: { import_id?: string; text_excerpt?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, req, 400);
  }
  const importId = body.import_id?.trim();
  const excerpt = (body.text_excerpt ?? "").slice(0, 8000);
  if (!importId || excerpt.length < 50) {
    return jsonResponse({ error: "missing_import_or_excerpt" }, req, 400);
  }

  const { data: row, error: selErr } = await userClient
    .from("statement_imports")
    .select("id,user_id,metadata")
    .eq("id", importId)
    .maybeSingle();

  if (selErr || !row || (row as { user_id: string }).user_id !== userId) {
    return jsonResponse({ error: "forbidden" }, req, 403);
  }

  const keyPack = await resolveGoatGeminiKey();
  if (!keyPack) {
    return jsonResponse({ error: "no_ai_key" }, req, 503);
  }

  const safeExcerpt = excerpt.replace(/</g, " ");
  const prompt =
    `You classify bank/card/wallet statements and payment exports. Read ONLY the excerpt (may be truncated). Return ONLY valid JSON, no markdown.

Allowed document_type values (exact string):
bank_statement, credit_card_statement, wallet_statement, loan_statement, payment_receipt, upi_receipt, account_export_csv, passbook_scan, unknown_financial_document

Return shape:
{"document_type":"","institution_name":"","currency":"INR","statement_start_date":null,"statement_end_date":null,"has_transaction_table":true,"confidence":0,"warnings":[]}

Rules:
- If unclear, use unknown_financial_document and lower confidence.
- Dates as YYYY-MM-DD or null.
- institution_name: best guess or empty string.
- warnings: short strings only.
- confidence: 0-100 number.

Excerpt:
${safeExcerpt}`;

  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${encodeURIComponent(keyPack.key)}`;
  const controller = new AbortController();
  const tid = setTimeout(() => controller.abort(), 45_000);
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    signal: controller.signal,
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { temperature: 0.15, maxOutputTokens: 512 },
    }),
  }).finally(() => clearTimeout(tid));

  const gj = (await res.json()) as Record<string, unknown>;
  if (!res.ok) {
    console.error("statement-classify gemini", res.status, JSON.stringify(gj).slice(0, 400));
    return jsonResponse({ error: "gemini_failed" }, req, 502);
  }

  const text = (gj as { candidates?: { content?: { parts?: { text?: string }[] } }[] })
    .candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text || typeof text !== "string") {
    return jsonResponse({ error: "empty_model_output" }, req, 502);
  }

  let s = text.trim();
  if (s.startsWith("```")) {
    s = s.replace(/^```\w*\n?/, "").replace(/\n?```$/, "");
  }
  if (!s.startsWith("{")) {
    const m = s.match(/\{[\s\S]*\}/);
    if (m) s = m[0];
  }
  let parsed: Json;
  try {
    parsed = JSON.parse(s) as Json;
  } catch {
    return jsonResponse({ error: "invalid_model_json" }, req, 502);
  }

  const docType = typeof parsed.document_type === "string"
    ? parsed.document_type
    : "unknown_financial_document";
  const prevMeta = (row as { metadata: Json | null }).metadata;
  const meta: Json = { ...(prevMeta ?? {}) };
  meta["ai_classification"] = parsed;
  meta["ai_classification_at"] = new Date().toISOString();

  const { error: upErr } = await userClient
    .from("statement_imports")
    .update({
      document_family: docType,
      ai_model_last: GEMINI_MODEL,
      metadata: meta,
    })
    .eq("id", importId)
    .eq("user_id", userId);

  if (upErr) {
    console.error("statement-classify update", upErr);
    return jsonResponse({ error: "update_failed" }, req, 500);
  }

  return jsonResponse({ ok: true, document_family: docType }, req, 200);
});

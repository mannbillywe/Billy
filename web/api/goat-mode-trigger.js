// Vercel serverless proxy for Goat Mode trigger.
// Mirrors web/api/analytics-insights.js so the Flutter web client can POST
// same-origin to `/api/goat-mode-trigger` and we forward it to the Supabase
// Edge Function. The Edge Function in turn dispatches to the Billy AI backend
// (currently a Cloudflare Tunnel → local Docker container; swap
// `GOAT_BACKEND_URL` on Supabase when moving back to Cloud Run).
const SUPABASE_URL = "https://wpzopkigbbldcfpxuvcm.supabase.co";
const SUPABASE_ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Indwem9wa2lnYmJsZGNmcHh1dmNtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM4MTAxNzYsImV4cCI6MjA4OTM4NjE3Nn0.vps43fornSArjXvsiFQm4BSW6BuuXTMg_G11snC6OO8";

module.exports = async (req, res) => {
  if (req.method === "OPTIONS") {
    return res.status(200).end();
  }

  if (req.method !== "POST") {
    return res.status(405).json({
      success: false,
      error: { code: "METHOD_NOT_ALLOWED", message: "Method not allowed" },
    });
  }

  const authHeader = req.headers.authorization || req.headers["authorization"];
  if (!authHeader) {
    return res.status(401).json({
      success: false,
      error: {
        code: "NO_AUTH",
        message: "Missing Authorization header from client",
      },
    });
  }

  const target = `${SUPABASE_URL}/functions/v1/goat-mode-trigger`;

  const headers = {
    "Content-Type": "application/json",
    Authorization: authHeader,
    apikey: SUPABASE_ANON_KEY,
  };

  let bodyStr;
  if (typeof req.body === "string") {
    bodyStr = req.body;
  } else if (req.body && typeof req.body === "object") {
    bodyStr = JSON.stringify(req.body);
  } else {
    bodyStr = "{}";
  }

  const startedAt = Date.now();
  try {
    const upstream = await fetch(target, {
      method: "POST",
      headers,
      body: bodyStr,
    });

    const durationMs = Date.now() - startedAt;
    const responseText = await upstream.text();

    let data;
    try {
      data = JSON.parse(responseText);
    } catch {
      data = { _raw: responseText.slice(0, 2000) };
    }

    // Structured log so the Vercel Function logs are easy to grep.
    console.log(
      JSON.stringify({
        proxy: "goat-mode-trigger",
        upstream_status: upstream.status,
        duration_ms: durationMs,
        body_len: responseText.length,
      }),
    );

    if (upstream.status >= 200 && upstream.status < 300) {
      return res.status(upstream.status).json(data);
    }

    return res.status(upstream.status).json({
      success: false,
      _upstream_status: upstream.status,
      _upstream_body: data,
      error: {
        code: "UPSTREAM_ERROR",
        message:
          data?.msg ||
          data?.message ||
          data?.error?.message ||
          `Edge Function returned ${upstream.status}`,
      },
    });
  } catch (err) {
    console.error("goat-mode-trigger proxy error:", err);
    return res.status(502).json({
      success: false,
      error: { code: "PROXY_ERROR", message: `Proxy failed: ${err.message}` },
    });
  }
};

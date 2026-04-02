const SUPABASE_URL = "https://wpzopkigbbldcfpxuvcm.supabase.co";
const SUPABASE_ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Indwem9wa2lnYmJsZGNmcHh1dmNtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM4MTAxNzYsImV4cCI6MjA4OTM4NjE3Nn0.vps43fornSArjXvsiFQm4BSW6BuuXTMg_G11snC6OO8";

module.exports = async (req, res) => {
  if (req.method === "OPTIONS") {
    return res.status(200).end();
  }

  if (req.method !== "POST") {
    return res.status(405).json({ success: false, error: "Method not allowed" });
  }

  const authHeader = req.headers.authorization || req.headers["authorization"];
  if (!authHeader) {
    return res.status(401).json({
      success: false,
      error: { code: "NO_AUTH", message: "Missing Authorization header from client" },
    });
  }

  const target = `${SUPABASE_URL}/functions/v1/process-invoice`;

  const headers = {
    "Content-Type": "application/json",
    "Authorization": authHeader,
    "apikey": SUPABASE_ANON_KEY,
  };

  let bodyStr;
  if (typeof req.body === "string") {
    bodyStr = req.body;
  } else if (req.body && typeof req.body === "object") {
    bodyStr = JSON.stringify(req.body);
  } else {
    bodyStr = "{}";
  }

  try {
    const upstream = await fetch(target, {
      method: "POST",
      headers,
      body: bodyStr,
    });

    const responseText = await upstream.text();

    let data;
    try {
      data = JSON.parse(responseText);
    } catch {
      data = { _raw: responseText.slice(0, 2000) };
    }

    if (upstream.status >= 200 && upstream.status < 300) {
      return res.status(upstream.status).json(data);
    }

    return res.status(upstream.status).json({
      success: false,
      _upstream_status: upstream.status,
      _upstream_body: data,
      error: {
        code: "UPSTREAM_ERROR",
        message: data?.msg || data?.message || data?.error?.message || `Edge Function returned ${upstream.status}`,
      },
    });
  } catch (err) {
    console.error("process-invoice proxy error:", err);
    return res.status(502).json({
      success: false,
      error: { code: "PROXY_ERROR", message: `Proxy failed: ${err.message}` },
    });
  }
};

/**
 * Cloudflare Worker: Mailtrap CORS Bridge / Proxy
 * 
 * Free Tier Limits: 100,000 requests/day ($0.00 / No credit card required)
 * 
 * How to Deploy:
 * 1. Go to https://dash.cloudflare.com -> Compute (Workers & Pages) -> Create application -> Create Worker
 * 2. Give it a name (e.g., `mailtrap-cors-proxy` or `tranyx-mail-proxy`)
 * 3. Click "Deploy" -> "Edit code"
 * 4. Paste this entire file into `index.js` (replacing default code) and click "Deploy"
 * 5. Copy your worker URL (e.g. `https://tranyx-mail-proxy.yourname.workers.dev`)
 * 6. Put it in `.env` as `MAIL_TRAP_PROXY_URL=https://tranyx-mail-proxy.yourname.workers.dev`
 *    and in GitHub Secrets as `MAIL_TRAP_PROXY_URL`.
 */

export default {
  async fetch(request, env, ctx) {
    // 1. Standard CORS Response Headers
    const corsHeaders = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization, Api-Token, X-Mailtrap-Endpoint, X-Inbox-Id, X-Sandbox",
      "Access-Control-Max-Age": "86400",
    };

    // 2. Handle Browser CORS Preflight (OPTIONS)
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: corsHeaders,
      });
    }

    if (request.method === "GET") {
      return new Response(JSON.stringify({ status: "ok", message: "Mailtrap CORS Proxy is active." }), {
        status: 200,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
        },
      });
    }

    if (request.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed. Use POST." }), {
        status: 405,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
        },
      });
    }

    try {
      const url = new URL(request.url);
      const authHeader = request.headers.get("Authorization") || "";
      const apiTokenHeader = request.headers.get("Api-Token") || "";
      const token = authHeader.replace(/^Bearer\s+/i, "") || apiTokenHeader;

      const inboxId = request.headers.get("X-Inbox-Id") || url.searchParams.get("inbox_id") || "4886849";
      const isSandboxHeader = request.headers.get("X-Sandbox") === "true";
      const customEndpoint = request.headers.get("X-Mailtrap-Endpoint");

      const bodyText = await request.text();

      // Determine Target Mailtrap URL
      let targetUrl = "https://send.api.mailtrap.io/api/send";
      if (customEndpoint && customEndpoint.startsWith("https://")) {
        targetUrl = customEndpoint;
      } else if (isSandboxHeader || url.searchParams.get("sandbox") === "true") {
        targetUrl = `https://sandbox.api.mailtrap.io/api/send/${inboxId}`;
      }

      // Helper to dispatch request to Mailtrap
      async function callMailtrap(endpointUrl) {
        return await fetch(endpointUrl, {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${token}`,
            "Api-Token": token,
            "Content-Type": "application/json",
          },
          body: bodyText,
        });
      }

      let mailtrapResponse = await callMailtrap(targetUrl);

      // If Live endpoint returns 401 Unauthorized or Sandbox token is detected, auto-fallback to Sandbox endpoint
      if (mailtrapResponse.status === 401 && targetUrl.includes("send.api.mailtrap.io")) {
        const sandboxUrl = `https://sandbox.api.mailtrap.io/api/send/${inboxId}`;
        const fallbackResponse = await callMailtrap(sandboxUrl);
        if (fallbackResponse.ok || fallbackResponse.status !== 401) {
          mailtrapResponse = fallbackResponse;
        }
      }

      const responseBody = await mailtrapResponse.text();

      return new Response(responseBody, {
        status: mailtrapResponse.status,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
        },
      });
    } catch (error) {
      return new Response(
        JSON.stringify({ success: false, error: error.message || "Proxy request failed" }),
        {
          status: 500,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
          },
        }
      );
    }
  },
};

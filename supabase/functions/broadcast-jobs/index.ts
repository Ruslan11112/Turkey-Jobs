import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const escapeHtml = (value: string) => value.replace(/[&<>"']/g, c => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
}[c]!));

Deno.serve(async req => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return Response.json({ error: "Method not allowed" }, { status: 405, headers: cors });
  const authorization = req.headers.get("Authorization");
  if (!authorization) return Response.json({ error: "Sign in required" }, { status: 401, headers: cors });
  const url = Deno.env.get("SUPABASE_URL")!;
  const publishable = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  const anonKey = publishable ? JSON.parse(publishable).default : Deno.env.get("SUPABASE_ANON_KEY")!;
  const caller = createClient(url, anonKey, { global: { headers: { Authorization: authorization } } });
  const { data: { user }, error: authError } = await caller.auth.getUser();
  if (authError || !user) return Response.json({ error: "Invalid session" }, { status: 401, headers: cors });
  const { data: isAdmin } = await caller.rpc("is_admin");
  if (!isAdmin) return Response.json({ error: "Administrator AAL2 access required" }, { status: 403, headers: cors });

  let body: { job_id?: string; preview?: boolean };
  try { body = await req.json(); } catch { return Response.json({ error: "Invalid request body" }, { status: 400, headers: cors }); }
  if (!body.job_id) return Response.json({ error: "job_id is required" }, { status: 400, headers: cors });
  const secretKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
  const serviceKey = secretKeys ? JSON.parse(secretKeys).default : Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const service = createClient(url, serviceKey);
  const { data: job, error: jobError } = await service.from("jobs")
    .select("id,title,company,city,salary,description,source_url,is_published")
    .eq("id", body.job_id).single();
  if (jobError || !job) return Response.json({ error: "Vacancy not found" }, { status: 404, headers: cors });
  if (!job.is_published) return Response.json({ error: "Publish this vacancy before sending a notice" }, { status: 409, headers: cors });
  const { data: subscriptions, error: preferenceError } = await service.from("user_settings")
    .select("user_id").eq("vacancy_emails", true).limit(10000);
  if (preferenceError) return Response.json({ error: preferenceError.message }, { status: 500, headers: cors });
  const userIds = (subscriptions || []).map(row => row.user_id);
  if (!userIds.length) return Response.json({ recipients: 0, sent: 0 }, { headers: cors });
  const { data: profiles, error: profileError } = await service.from("profiles")
    .select("id,full_name,email").in("id", userIds).neq("email", "");
  if (profileError) return Response.json({ error: profileError.message }, { status: 500, headers: cors });
  const recipients = profiles || [];
  if (body.preview) return Response.json({ recipients: recipients.length }, { headers: cors });
  if (!recipients.length) return Response.json({ recipients: 0, sent: 0 }, { headers: cors });
  const resendKey = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("MAIL_FROM");
  if (!resendKey || !from) return Response.json({ error: "Email provider is not configured" }, { status: 503, headers: cors });
  const title = escapeHtml(job.title), company = escapeHtml(job.company), city = escapeHtml(job.city);
  const salary = escapeHtml(job.salary || "Условия уточняйте у работодателя");
  const description = escapeHtml(job.description || "");
  const href = /^https:\/\//i.test(job.source_url || "") ? job.source_url : "";
  const action = href ? `<p><a href="${escapeHtml(href)}">Открыть условия работодателя</a></p>` : "";
  const messages = recipients.map(profile => ({
    from, to: [profile.email], subject: `Новая вакансия в Турции: ${job.title}`,
    html: `<main style="font-family:Arial,sans-serif;max-width:620px;margin:auto;color:#15372a"><p>Здравствуйте${profile.full_name ? `, ${escapeHtml(profile.full_name)}` : ""}!</p><h1>${title}</h1><p><b>${company}</b> · ${city}</p><p>${salary}</p><p>${description}</p>${action}<p>Вы получаете это письмо, потому что включили уведомления о вакансиях в настройках аккаунта. Изменить выбор можно в личном кабинете.</p></main>`,
    text: `Здравствуйте${profile.full_name ? `, ${profile.full_name}` : ""}! Новая вакансия: ${job.title}. ${job.company} · ${job.city}. ${job.salary || "Условия уточняйте у работодателя"}. ${job.description || ""} ${href ? `Условия работодателя: ${href}` : ""} Отключить рассылку можно в настройках аккаунта.`,
  }));
  let sent = 0;
  for (let i = 0; i < messages.length; i += 100) {
    const response = await fetch("https://api.resend.com/emails/batch", {
      method: "POST", headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
      body: JSON.stringify(messages.slice(i, i + 100)),
    });
    if (!response.ok) return Response.json({ error: "Email provider rejected part of the broadcast", sent, recipients: recipients.length }, { status: 502, headers: cors });
    sent += Math.min(100, messages.length - i);
  }
  return Response.json({ sent, recipients: recipients.length }, { headers: cors });
});

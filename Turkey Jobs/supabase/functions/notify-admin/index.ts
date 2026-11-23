import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405, headers: cors });
  const auth = req.headers.get("Authorization");
  if (!auth) return new Response("Unauthorized", { status: 401, headers: cors });

  const url = Deno.env.get("SUPABASE_URL")!;
  const publishableKeys = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  const secretKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
  const anonKey = publishableKeys ? JSON.parse(publishableKeys).default : Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = secretKeys ? JSON.parse(secretKeys).default : Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: auth } },
  });
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) return new Response("Unauthorized", { status: 401, headers: cors });

  let payload: { application_id?: string; complaint_id?: string; resume_user_id?: string };
  try { payload = await req.json(); } catch { return new Response("Invalid request body", { status: 400, headers: cors }); }
  const eventIds = [payload.application_id, payload.complaint_id, payload.resume_user_id].filter(Boolean);
  if (eventIds.length !== 1) return new Response("Provide exactly one event id", { status: 400, headers: cors });
  const adminClient = createClient(url, serviceKey);
  const { data: isAdmin } = await userClient.rpc("is_admin");
  let ownerId = "";
  let subject = "";
  let text = "";
  if (payload.application_id) {
    const { data: app, error } = await adminClient.from("applications")
      .select("id,user_id,applicant_name,contact_email,contact_phone,created_at,jobs(title,company)")
      .eq("id", payload.application_id).single();
    if (error || !app) return new Response("Application not found", { status: 404, headers: cors });
    if (app.user_id !== user.id && !isAdmin) return new Response("Forbidden", { status: 403, headers: cors });
    const job = Array.isArray(app.jobs) ? app.jobs[0] : app.jobs;
    ownerId = app.user_id;
    subject = `Новая заявка: ${app.applicant_name}`;
    text = `Кандидат: ${app.applicant_name}\nВакансия: ${job?.title ?? ""} — ${job?.company ?? ""}\nEmail: ${app.contact_email}\nТелефон: ${app.contact_phone}\nДата: ${app.created_at}\nID заявки: ${app.id}`;
  } else if (payload.complaint_id) {
    const { data: complaint, error } = await adminClient.from("complaints")
      .select("id,user_id,subject,message,created_at").eq("id", payload.complaint_id).single();
    if (error || !complaint) return new Response("Complaint not found", { status: 404, headers: cors });
    if (complaint.user_id !== user.id && !isAdmin) return new Response("Forbidden", { status: 403, headers: cors });
    ownerId = complaint.user_id;
    subject = `Новое сообщение: ${complaint.subject}`;
    text = `Тема: ${complaint.subject}\nСообщение: ${complaint.message}\nДата: ${complaint.created_at}\nID обращения: ${complaint.id}`;
  } else {
    const resumeUserId = payload.resume_user_id!;
    const { data: resume, error } = await adminClient.from("candidate_resumes")
      .select("user_id,headline,summary,experience,education,skills,languages,updated_at").eq("user_id", resumeUserId).single();
    if (error || !resume) return new Response("Resume not found", { status: 404, headers: cors });
    if (resume.user_id !== user.id && !isAdmin) return new Response("Forbidden", { status: 403, headers: cors });
    const { data: profile } = await adminClient.from("profiles").select("full_name,email,phone").eq("id", resume.user_id).maybeSingle();
    ownerId = resume.user_id;
    subject = `Новое или обновлённое резюме: ${profile?.full_name || profile?.email || "кандидат"}`;
    text = `Кандидат: ${profile?.full_name || ""}\nEmail: ${profile?.email || ""}\nТелефон: ${profile?.phone || ""}\nДолжность: ${resume.headline}\nО себе: ${resume.summary}\nОпыт: ${resume.experience}\nОбразование: ${resume.education}\nНавыки: ${resume.skills}\nЯзыки: ${resume.languages}\nОбновлено: ${resume.updated_at}`;
  }

  const resendKey = Deno.env.get("RESEND_API_KEY");
  const ownerEmail = Deno.env.get("ADMIN_EMAIL");
  if (!resendKey || !ownerEmail) return new Response("Email notification is not configured", { status: 503, headers: cors });

  const emailResponse = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from: Deno.env.get("MAIL_FROM") ?? "Turkey Jobs <onboarding@resend.dev>",
      to: [ownerEmail],
      subject,
      text: `${text}\nID пользователя: ${ownerId}`,
    }),
  });
  if (!emailResponse.ok) return new Response("Email provider rejected the message", { status: 502, headers: cors });
  return Response.json({ sent: true }, { headers: cors });
});

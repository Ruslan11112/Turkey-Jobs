
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405, headers: cors });
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return Response.json({ error: "Нужно войти в аккаунт." }, { status: 401, headers: cors });
  const url = Deno.env.get("SUPABASE_URL")!;
  const publishableKeys = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  const anonKey = publishableKeys ? JSON.parse(publishableKeys).default : Deno.env.get("SUPABASE_ANON_KEY")!;
  const caller = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
  const { data: { user }, error: authError } = await caller.auth.getUser();
  if (authError || !user) return Response.json({ error: "Сессия недействительна." }, { status: 401, headers: cors });
  const { data: isAdmin, error: roleError } = await caller.rpc("is_admin");
  if (roleError || !isAdmin) return Response.json({ error: "Только администратор может приглашать администраторов." }, { status: 403, headers: cors });
  const body = await req.json().catch(() => ({}));
  const email = String(body.email || "").trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email === user.email?.toLowerCase()) return Response.json({ error: "Укажите корректную почту другого пользователя." }, { status: 400, headers: cors });
  const secretKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
  const serviceKey = secretKeys ? JSON.parse(secretKeys).default : Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(url, serviceKey);
  let invitedUserId: string | undefined;
  for (let page = 1; page <= 20 && !invitedUserId; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) return Response.json({ error: error.message }, { status: 400, headers: cors });
    invitedUserId = data.users.find((candidate) => candidate.email?.toLowerCase() === email)?.id;
    if (data.users.length < 1000) break;
  }
  if (!invitedUserId) {
    const { data, error } = await admin.auth.admin.inviteUserByEmail(email, { redirectTo: body.redirectTo });
    if (error) return Response.json({ error: error.message }, { status: 400, headers: cors });
    invitedUserId = data.user.id;
  }
  const { error: grantError } = await admin.from("admin_users").upsert({ user_id: invitedUserId });
  if (grantError) return Response.json({ error: `Приглашение создано, но роль не назначена: ${grantError.message}` }, { status: 500, headers: cors });
  return Response.json({ ok: true }, { headers: cors });
});

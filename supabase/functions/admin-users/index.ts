import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

function makePassword() {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$";
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, b => chars[b % chars.length]).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return reply({ error: "Sesi tidak ditemukan." }, 401);

  const callerClient = createClient(url, anon, { global: { headers: { Authorization: "Bearer " + token } } });
  const { data: authData, error: authError } = await callerClient.auth.getUser(token);
  if (authError || !authData.user) return reply({ error: "Sesi tidak valid. Login kembali." }, 401);

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: callerProfile, error: profileError } = await admin.from("profiles")
    .select("id,email,role").eq("id", authData.user.id).single();
  if (profileError || !callerProfile || !["admin", "superadmin"].includes(callerProfile.role)) {
    return reply({ error: "Akses ditolak. Hanya Admin dan Superadmin." }, 403);
  }

  let body: any;
  try { body = await req.json(); } catch { return reply({ error: "JSON tidak valid." }, 400); }
  const action = String(body.action || "");
  const isSuper = callerProfile.role === "superadmin";

  const getTarget = async (email: string) => {
    const { data, error } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
    if (error) throw error;
    return data.users.find(u => (u.email || "").toLowerCase() === email.toLowerCase()) || null;
  };

  try {
    if (action === "list") {
      const [{ data: authUsers, error: listError }, { data: profiles, error: profError }] = await Promise.all([
        admin.auth.admin.listUsers({ page: 1, perPage: 1000 }),
        admin.from("profiles").select("id,email,full_name,role,created_at"),
      ]);
      if (listError) throw listError;
      if (profError) throw profError;
      const pmap = new Map((profiles || []).map((p: any) => [p.id, p]));
      const users = (authUsers.users || []).map((u: any) => {
        const p: any = pmap.get(u.id) || {};
        return {
          email: u.email || p.email || "",
          full_name: p.full_name || u.user_metadata?.full_name || "",
          role: p.role || "user",
          on: !u.banned_until,
          c: u.created_at ? Date.parse(u.created_at) : 0,
          l: u.last_sign_in_at ? Date.parse(u.last_sign_in_at) : 0,
        };
      });
      return reply({ users });
    }

    const email = String(body.email || "").trim().toLowerCase();
    if (!email || !email.includes("@")) return reply({ error: "Email tidak valid." }, 400);
    const target = await getTarget(email);
    if (!target) return reply({ error: "Akun tidak ditemukan." }, 404);
    const { data: targetProfile } = await admin.from("profiles").select("id,email,role")
      .eq("id", target.id).single();
    const targetRole = targetProfile?.role || "user";
    if (!isSuper && targetRole !== "user") return reply({ error: "Admin hanya boleh mengelola akun User." }, 403);
    if (target.id === authData.user.id && action === "delete") return reply({ error: "Tidak dapat menghapus akun sendiri." }, 400);

    if (action === "create") {
      // handled below; target lookup is not applicable for a new account
      return reply({ error: "Email sudah terdaftar." }, 409);
    }

    if (action === "update") {
      if (body.role !== undefined && !isSuper) return reply({ error: "Hanya Superadmin yang dapat mengubah role." }, 403);
      const patch: any = {};
      if (body.password) {
        if (String(body.password).length < 8) return reply({ error: "Password minimal 8 karakter." }, 400);
        patch.password = String(body.password);
      }
      if (body.active !== undefined) {
        if (!isSuper) return reply({ error: "Hanya Superadmin yang dapat mengubah status akun." }, 403);
        patch.ban_duration = body.active ? "none" : "876000h";
      }
      if (Object.keys(patch).length) {
        const { error } = await admin.auth.admin.updateUserById(target.id, patch);
        if (error) throw error;
      }
      const profilePatch: any = {};
      if (body.role !== undefined) {
        if (!["user", "admin", "superadmin"].includes(body.role)) return reply({ error: "Role tidak valid." }, 400);
        profilePatch.role = body.role;
      }
      if (body.full_name !== undefined) profilePatch.full_name = String(body.full_name).slice(0, 120);
      if (Object.keys(profilePatch).length) {
        const { error } = await admin.from("profiles").update(profilePatch).eq("id", target.id);
        if (error) throw error;
      }
      return reply({ ok: true });
    }

    if (action === "reset") {
      const password = String(body.password || makePassword());
      if (password.length < 8) return reply({ error: "Password minimal 8 karakter." }, 400);
      const { error } = await admin.auth.admin.updateUserById(target.id, { password });
      if (error) throw error;
      return reply({ ok: true });
    }

    if (action === "delete") {
      if (targetRole === "superadmin") {
        const { count, error } = await admin.from("profiles").select("id", { count: "exact", head: true }).eq("role", "superadmin");
        if (error) throw error;
        if ((count || 0) <= 1) return reply({ error: "Superadmin terakhir tidak boleh dihapus." }, 400);
      }
      const { error } = await admin.auth.admin.deleteUser(target.id);
      if (error) throw error;
      return reply({ ok: true });
    }
    return reply({ error: "Aksi tidak dikenal." }, 400);
  } catch (e) {
    return reply({ error: e instanceof Error ? e.message : "Terjadi kesalahan server." }, 500);
  }
});

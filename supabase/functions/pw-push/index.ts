// Powerosso: manda el aviso push al coach cuando un alumno deja una observación nueva.
// La llama el trigger notes_push de la base (con la clave x-pw-hook); las claves VAPID están en pw_config.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import webpush from "npm:web-push@3.6.7";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

Deno.serve(async (req) => {
  const { data: cfg } = await db.from("pw_config").select("k,v");
  const c = Object.fromEntries((cfg || []).map((r) => [r.k, r.v]));
  if (!c.hook || req.headers.get("x-pw-hook") !== c.hook) return new Response("no", { status: 401 });
  const { id } = await req.json().catch(() => ({}));
  const { data: note } = await db.from("notes").select("aid,data").eq("id", id).maybeSingle();
  if (!note) return new Response("sin nota", { status: 404 });
  const { data: ath } = await db.from("athletes").select("data").eq("id", note.aid).maybeSingle();
  const n = note.data || {}, name = ath?.data?.name || "Un alumno";
  const where = [n.exName, n.w && n.d ? `S${n.w} D${n.d}` : ""].filter(Boolean).join(" · ");
  const body = [n.tag, n.text].filter(Boolean).join(": ") || "Dejó una observación";
  const payload = JSON.stringify({ title: `Observación de ${name}`, body: where ? `${where}\n${body}` : body, tag: "obs-" + id, url: "./" });
  webpush.setVapidDetails(c.vapid_subject || "mailto:coach@powerosso.app", c.vapid_pub, c.vapid_priv);
  const { data: subs } = await db.from("push_subs").select("endpoint,sub");
  let sent = 0;
  for (const s of subs || []) {
    try { await webpush.sendNotification(s.sub, payload, { TTL: 86400 }); sent++; }
    catch (e) { if (e?.statusCode === 404 || e?.statusCode === 410) await db.from("push_subs").delete().eq("endpoint", s.endpoint); }
  }
  return new Response(JSON.stringify({ sent }), { headers: { "Content-Type": "application/json" } });
});

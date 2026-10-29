-- Avisos push al coach cuando un alumno deja una observación nueva.
-- Las claves (VAPID y la del aviso interno) se guardan en pw_config, que no se ve desde la app.
create extension if not exists pg_net with schema extensions;

create table if not exists public.pw_config (k text primary key, v text not null);
create table if not exists public.push_subs (
  endpoint   text primary key,
  aid        text not null references public.athletes(id) on delete cascade,
  sub        jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.pw_config enable row level security;
alter table public.push_subs enable row level security;
revoke all on public.pw_config, public.push_subs from anon, authenticated;

-- el coach activa (p_on) o desactiva los avisos en este teléfono
create or replace function public.pw_push_sub(p_token text, p_sub jsonb, p_on boolean default true) returns void
language plpgsql security definer set search_path = public as $$
declare me athletes := pw_me(p_token); e text := p_sub->>'endpoint';
begin
  if not me.coach then raise exception 'sin permiso' using errcode = '42501'; end if;
  if coalesce(e,'') = '' then raise exception 'suscripción no válida'; end if;
  if p_on then insert into push_subs(endpoint, aid, sub) values (e, me.id, p_sub) on conflict (endpoint) do update set sub = excluded.sub, aid = excluded.aid;
  else delete from push_subs where endpoint = e; end if;
end $$;
grant execute on function public.pw_push_sub(text, jsonb, boolean) to anon, authenticated;

-- observación nueva de un alumno → llama a la función pw-push, que manda el aviso
create or replace function public.pw_note_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare u text := (select v from pw_config where k = 'fn_url'); h text := (select v from pw_config where k = 'hook');
begin
  if u is null or h is null or exists(select 1 from athletes where id = new.aid and coach) then return new; end if;
  perform net.http_post(url := u, body := jsonb_build_object('id', new.id), headers := jsonb_build_object('Content-Type','application/json','x-pw-hook',h));
  return new;
end $$;
drop trigger if exists notes_push on public.notes;
create trigger notes_push after insert on public.notes for each row execute function public.pw_note_push();

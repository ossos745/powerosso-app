-- Powerosso App: base de datos en Supabase (acceso por link personal, sin correo).
-- Pégalo completo en Supabase → SQL Editor → New query → Run. Se puede correr más de una vez.
--
-- Cada persona tiene un link con una clave secreta (#k=...). Las tablas quedan cerradas:
-- la app solo entra a través de las funciones pw_*, que revisan esa clave.
-- El coach ve y edita todo; cada alumno solo su planificación, sus registros y sus observaciones.

create table if not exists public.athletes (
  id         text primary key,
  token      text not null unique default replace(gen_random_uuid()::text,'-',''),
  coach      boolean not null default false,
  data       jsonb   not null,          -- nombre, mesociclo actual, planilla (file)
  updated_at timestamptz not null default now()
);
create table if not exists public.files (  -- planillas Excel tal cual (base64), subidas por el .bat o desde la app
  name       text primary key,
  mtime      timestamptz,
  b64        text not null,
  updated_at timestamptz not null default now()
);
create table if not exists public.logs (
  id         text primary key,          -- <alumno>~<mesociclo>~<semana>-<día>
  aid        text not null references public.athletes(id) on delete cascade,
  data       jsonb not null,
  updated_at timestamptz not null default now()
);
create table if not exists public.notes (
  id         text primary key,
  aid        text not null references public.athletes(id) on delete cascade,
  data       jsonb not null,
  updated_at timestamptz not null default now()
);
create index if not exists logs_aid  on public.logs(aid);
create index if not exists notes_aid on public.notes(aid);

alter table public.athletes enable row level security;
alter table public.files    enable row level security;
alter table public.logs     enable row level security;
alter table public.notes    enable row level security;
revoke all on public.athletes, public.files, public.logs, public.notes from anon, authenticated;

create or replace function public.pw_me(p_token text) returns public.athletes
language plpgsql stable security definer set search_path = public as $$
declare r athletes;
begin
  select * into r from athletes where token = p_token;
  if r.id is null or coalesce(p_token,'') = '' then raise exception 'link no válido' using errcode = '28000'; end if;
  return r;
end $$;

-- Todo lo que la persona puede ver. p_since: solo lo cambiado desde esa hora (para refrescar).
create or replace function public.pw_load(p_token text, p_since timestamptz default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me athletes := pw_me(p_token); s timestamptz := coalesce(p_since, '-infinity');
begin
  return jsonb_build_object(
    'now', now(),
    'me', jsonb_build_object('id', me.id, 'coach', me.coach),
    'athletes', coalesce((select jsonb_object_agg(a.id, a.data || jsonb_build_object('coach', a.coach) || case when me.coach then jsonb_build_object('token', a.token) else '{}'::jsonb end)
                 from athletes a where (me.coach or a.id = me.id) and a.updated_at > s), '{}'),
    'files', coalesce((select jsonb_object_agg(f.name, f.mtime) from files f
                 where (me.coach or f.name = me.data->>'file') and f.updated_at > s), '{}'),
    'logs', coalesce((select jsonb_object_agg(l.id, l.data) from logs l where (me.coach or l.aid = me.id) and l.updated_at > s), '{}'),
    'notes', coalesce((select jsonb_object_agg(n.id, n.data) from notes n where (me.coach or n.aid = me.id) and n.updated_at > s), '{}'));
end $$;

create or replace function public.pw_file(p_token text, p_name text) returns text
language plpgsql stable security definer set search_path = public as $$
declare me athletes := pw_me(p_token);
begin
  if not me.coach and p_name is distinct from me.data->>'file' then raise exception 'sin permiso' using errcode = '42501'; end if;
  return (select b64 from files where name = p_name);
end $$;

create or replace function public.pw_put(p_token text, p_coll text, p_id text, p_data jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare me athletes := pw_me(p_token); a text := p_data->>'aid';
begin
  if p_coll = 'athletes' then
    if not me.coach then raise exception 'sin permiso' using errcode = '42501'; end if;
    insert into athletes(id, coach, data) values (p_id, coalesce((p_data->>'coach')::boolean, false), p_data - 'token' - 'coach')
      on conflict (id) do update set coach = excluded.coach, data = excluded.data, updated_at = now();
  elsif p_coll in ('logs','notes') then
    if a is null or (not me.coach and a <> me.id) or position(a || '~' in p_id) <> 1 then raise exception 'sin permiso' using errcode = '42501'; end if;
    if p_coll = 'logs' then
      insert into logs(id, aid, data) values (p_id, a, p_data) on conflict (id) do update set data = excluded.data, updated_at = now() where logs.aid = a;
    else
      insert into notes(id, aid, data) values (p_id, a, p_data) on conflict (id) do update set data = excluded.data, updated_at = now() where notes.aid = a;
    end if;
  else raise exception 'colección desconocida'; end if;
end $$;

create or replace function public.pw_del(p_token text, p_coll text, p_id text) returns void
language plpgsql security definer set search_path = public as $$
declare me athletes := pw_me(p_token);
begin
  if not me.coach then raise exception 'sin permiso' using errcode = '42501'; end if;
  if p_coll = 'athletes' then if p_id = me.id then raise exception 'no puedes borrarte a ti mismo'; end if; delete from athletes where id = p_id;
  elsif p_coll = 'logs' then delete from logs where id = p_id;
  elsif p_coll = 'notes' then delete from notes where id = p_id;
  elsif p_coll = 'files' then delete from files where name = p_id; end if;
end $$;

-- Texto simplificado para comparar nombres: minúsculas, sin tildes, solo letras y números.
create or replace function public.pw_norm(t text) returns text language sql immutable as $$
  select regexp_replace(lower(translate(coalesce(t,''), 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')), '[^a-z0-9]+', '', 'g');
$$;

-- Sube una planilla (la usa el .bat y la app). Si nadie la tiene asignada, se la asigna al alumno
-- cuyo nombre aparece en el nombre del archivo; si no hay ninguno, crea un alumno nuevo.
-- Con p_aid (desde la app) se asigna directo a ese alumno.
drop function if exists public.pw_upload(text, text, timestamptz, text);
create or replace function public.pw_upload(p_token text, p_name text, p_mtime timestamptz, p_b64 text, p_aid text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me athletes := pw_me(p_token); aid text; nm text; isnew boolean := false;
begin
  if not me.coach then raise exception 'sin permiso' using errcode = '42501'; end if;
  insert into files(name, mtime, b64) values (p_name, p_mtime, p_b64)
    on conflict (name) do update set mtime = excluded.mtime, b64 = excluded.b64, updated_at = now()
    where files.b64 is distinct from excluded.b64 or files.mtime is distinct from excluded.mtime;
  if p_aid is not null then
    update athletes set data = data || jsonb_build_object('file', p_name), updated_at = now() where id = p_aid returning id into aid;
    if aid is null then raise exception 'alumno no encontrado'; end if;
  end if;
  if aid is null then select id into aid from athletes where data->>'file' = p_name limit 1; end if;
  if aid is null then
    select id into aid from athletes a
      where length(pw_norm(split_part(a.data->>'name', ' ', 1))) >= 3
        and position(pw_norm(split_part(a.data->>'name', ' ', 1)) in pw_norm(p_name)) > 0
      order by (position(pw_norm(a.data->>'name') in pw_norm(p_name)) > 0) desc, a.coach desc limit 1;
    if aid is null then
      nm := initcap(trim(regexp_replace(regexp_replace(regexp_replace(p_name, '\.[a-z]+$', '', 'i'), '[_\-]+', ' ', 'g'),
              '\m(rutina|planificaci[oó]n|plan|versi[oó]n|v\d+|copia|final)\M', '', 'gi')));
      if nm = '' then nm := 'Alumno nuevo'; end if;
      aid := left(coalesce(nullif(regexp_replace(lower(translate(split_part(nm,' ',1),'ÁÉÍÓÚÜÑáéíóúüñ','AEIOUUNaeiouun')),'[^a-z0-9]+','','g'),''),'alumno'),20)
             || '-' || substr(md5(random()::text), 1, 4);
      insert into athletes(id, coach, data) values (aid, false, jsonb_build_object('name', nm, 'file', p_name, 'createdAt', (extract(epoch from now())*1000)::bigint));
      isnew := true;
    else
      update athletes set data = data || jsonb_build_object('file', p_name), updated_at = now() where id = aid;
    end if;
  end if;
  return jsonb_build_object('athlete', aid, 'new', isnew);
end $$;

-- Respaldo completo (incluye planillas y links) y restauración.
create or replace function public.pw_export(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me athletes := pw_me(p_token);
begin
  if not me.coach then raise exception 'sin permiso' using errcode = '42501'; end if;
  return jsonb_build_object('app', 'powerosso', 'version', 1, 'exportedAt', now(),
    'athletes', coalesce((select jsonb_object_agg(id, data || jsonb_build_object('coach', coach, 'token', token)) from athletes), '{}'),
    'files', coalesce((select jsonb_object_agg(name, jsonb_build_object('mtime', mtime, 'b64', b64)) from files), '{}'),
    'logs', coalesce((select jsonb_object_agg(id, data) from logs), '{}'),
    'notes', coalesce((select jsonb_object_agg(id, data) from notes), '{}'));
end $$;

create or replace function public.pw_import(p_token text, p_bundle jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me athletes := pw_me(p_token); k text; v jsonb; n int := 0;
begin
  if not me.coach then raise exception 'sin permiso' using errcode = '42501'; end if;
  for k, v in select * from jsonb_each(coalesce(p_bundle->'athletes', '{}')) loop
    insert into athletes(id, coach, data, token) values (k, coalesce((v->>'coach')::boolean, false), v - 'token' - 'coach',
        coalesce(nullif(v->>'token',''), replace(gen_random_uuid()::text,'-','')))
      on conflict (id) do update set data = excluded.data, updated_at = now(),
        coach = case when athletes.id = me.id then true else excluded.coach end,
        token = case when athletes.id = me.id then athletes.token else excluded.token end;
    n := n + 1;
  end loop;
  for k, v in select * from jsonb_each(coalesce(p_bundle->'files', '{}')) loop
    insert into files(name, mtime, b64) values (k, (v->>'mtime')::timestamptz, v->>'b64')
      on conflict (name) do update set mtime = excluded.mtime, b64 = excluded.b64, updated_at = now();
  end loop;
  for k, v in select * from jsonb_each(coalesce(p_bundle->'logs', '{}')) loop
    if exists(select 1 from athletes where id = v->>'aid') then
      insert into logs(id, aid, data) values (k, v->>'aid', v) on conflict (id) do update set data = excluded.data, updated_at = now(); end if;
  end loop;
  for k, v in select * from jsonb_each(coalesce(p_bundle->'notes', '{}')) loop
    if exists(select 1 from athletes where id = v->>'aid') then
      insert into notes(id, aid, data) values (k, v->>'aid', v) on conflict (id) do update set data = excluded.data, updated_at = now(); end if;
  end loop;
  return jsonb_build_object('athletes', n);
end $$;

revoke all on function public.pw_me(text) from public, anon, authenticated;
grant execute on function public.pw_load(text, timestamptz), public.pw_file(text, text), public.pw_put(text, text, text, jsonb),
  public.pw_del(text, text, text), public.pw_upload(text, text, timestamptz, text, text), public.pw_export(text), public.pw_import(text, jsonb)
  to anon, authenticated;

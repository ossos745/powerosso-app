-- Powerosso App: base de datos en Supabase.
-- Pégalo completo en Supabase → SQL Editor → New query → Run. Se puede correr más de una vez.

create table if not exists public.athletes (
  id         text primary key,
  email      text unique,               -- email con el que el alumno entra a la app
  coach      boolean not null default false,
  data       jsonb   not null,          -- nombre, plan (semanas/días/ejercicios), fechas
  updated_at timestamptz not null default now()
);
create table if not exists public.logs (
  id         text primary key,          -- <alumno>~<semana>-<día>
  aid        text not null references public.athletes(id) on delete cascade,
  data       jsonb not null,            -- series registradas, sesión terminada
  updated_at timestamptz not null default now()
);
create table if not exists public.notes (
  id         text primary key,
  aid        text not null references public.athletes(id) on delete cascade,
  data       jsonb not null,            -- observación del alumno y respuesta del coach
  updated_at timestamptz not null default now()
);
create index if not exists logs_aid on public.logs(aid);
create index if not exists notes_aid on public.notes(aid);

-- ¿Quién es el usuario conectado? (security definer para no chocar con las reglas de acceso)
create or replace function public.is_coach() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from athletes where coach and lower(email) = lower(auth.jwt()->>'email'));
$$;
create or replace function public.my_aid() returns text
language sql stable security definer set search_path = public as $$
  select id from athletes where lower(email) = lower(auth.jwt()->>'email') limit 1;
$$;

alter table public.athletes enable row level security;
alter table public.logs     enable row level security;
alter table public.notes    enable row level security;

-- El coach ve y edita todo. Cada alumno ve su ficha y solo lee/escribe sus propios registros y observaciones.
drop policy if exists athletes_read  on public.athletes;
drop policy if exists athletes_coach on public.athletes;
create policy athletes_read  on public.athletes for select to authenticated using (is_coach() or id = my_aid());
create policy athletes_coach on public.athletes for all    to authenticated using (is_coach()) with check (is_coach());

drop policy if exists logs_coach on public.logs;
drop policy if exists logs_own   on public.logs;
create policy logs_coach on public.logs for all to authenticated using (is_coach()) with check (is_coach());
create policy logs_own   on public.logs for all to authenticated using (aid = my_aid()) with check (aid = my_aid());

drop policy if exists notes_coach on public.notes;
drop policy if exists notes_own   on public.notes;
create policy notes_coach on public.notes for all to authenticated using (is_coach()) with check (is_coach());
create policy notes_own   on public.notes for all to authenticated using (aid = my_aid()) with check (aid = my_aid());

-- Cambios en vivo (el coach ve las observaciones apenas el alumno las deja)
do $$ begin
  begin alter publication supabase_realtime add table public.athletes; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.logs;     exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.notes;    exception when duplicate_object then null; end;
end $$;

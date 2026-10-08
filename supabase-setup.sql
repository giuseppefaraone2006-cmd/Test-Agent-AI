-- Configurazione iniziale per un nuovo progetto Supabase.
-- Per un progetto che ha già la vecchia tabella per-utente, eseguire invece
-- supabase-migration-global-tasks.sql per conservare e migrare le righe presenti.
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  text text not null check (char_length(btrim(text)) between 1 and 120),
  done boolean not null default false,
  due_date date,
  assigned_operator text check (
    assigned_operator is null or assigned_operator in ('DAVIDE', 'MARCO', 'PASQUALE', 'PEPPE S.', 'PEPPE F.', 'ALE')
  ),
  created_at timestamptz not null default now()
);

alter table public.tasks enable row level security;

do $$
declare
  existing_policy text;
begin
  for existing_policy in
    select policyname from pg_policies where schemaname = 'public' and tablename = 'tasks'
  loop
    execute format('drop policy if exists %I on public.tasks', existing_policy);
  end loop;
end $$;

create policy "Authenticated users can read shared tasks"
  on public.tasks for select to authenticated using (true);
create policy "Authenticated users can create shared tasks"
  on public.tasks for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "Authenticated users can update shared tasks"
  on public.tasks for update to authenticated using (true) with check (true);
create policy "Authenticated users can delete shared tasks"
  on public.tasks for delete to authenticated using (true);

revoke all on table public.tasks from public, anon;
grant select, insert, update, delete on table public.tasks to authenticated;

create index if not exists tasks_created_at_idx
  on public.tasks (created_at desc);

-- Migrazione dalla lista privata per utente alla lista globale condivisa.
-- Conserva tutte le attività già presenti e le lascia senza operatore (NULL).
-- Eseguire una sola volta nel SQL Editor del progetto esistente.
alter table public.tasks
  add column if not exists assigned_operator text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tasks'::regclass
      and conname = 'tasks_assigned_operator_allowed'
  ) then
    alter table public.tasks
      add constraint tasks_assigned_operator_allowed
      check (
        assigned_operator is null or assigned_operator in ('DAVIDE', 'MARCO', 'PASQUALE', 'PEPPE S.', 'PEPPE F.', 'ALE')
      );
  end if;
end $$;

-- Rimuove tutte le policy esistenti, incluse quelle che filtravano per user_id.
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

alter table public.tasks enable row level security;

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

-- Aggiorna la cache dello schema usata dall'API REST.
notify pgrst, 'reload schema';


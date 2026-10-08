-- Migrazione dalla lista privata per utente alla lista globale condivisa.
-- Conserva tutte le attività già presenti e le lascia senza operatore (NULL).
-- Script ripetibile per aggiornare lo schema e le policy nel progetto esistente.
alter table public.tasks
  add column if not exists assigned_operator text;

alter table public.tasks
  drop constraint if exists tasks_assigned_operator_allowed;

alter table public.tasks
  add constraint tasks_assigned_operator_allowed
  check (
    assigned_operator is null or assigned_operator in ('DAVIDE', 'MARCO', 'PASQUALE', 'PEPPE S.', 'PEPPE F.', 'ALE', 'DANIELE S.')
  );

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
  on public.tasks for update to authenticated
  using ((select auth.uid()) is not null)
  with check ((select auth.uid()) is not null);
create policy "Authenticated users can delete shared tasks"
  on public.tasks for delete to authenticated
  using ((select auth.uid()) is not null);

create table if not exists public.task_comments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);

alter table public.task_comments enable row level security;

do $$
declare
  existing_policy text;
begin
  for existing_policy in
    select policyname from pg_policies where schemaname = 'public' and tablename = 'task_comments'
  loop
    execute format('drop policy if exists %I on public.task_comments', existing_policy);
  end loop;
end $$;

create policy "Authenticated users can read comments on visible tasks"
  on public.task_comments for select to authenticated
  using (exists (select 1 from public.tasks t where t.id = task_comments.task_id));
create policy "Authenticated users can add comments to visible tasks"
  on public.task_comments for insert to authenticated
  with check (
    (select auth.uid()) = task_comments.user_id
    and exists (select 1 from public.tasks t where t.id = task_comments.task_id)
  );

revoke all on table public.tasks from public, anon;
grant select, insert, update, delete on table public.tasks to authenticated;
revoke all on table public.task_comments from public, anon;
grant select, insert on table public.task_comments to authenticated;

create index if not exists tasks_created_at_idx
  on public.tasks (created_at desc);
create index if not exists task_comments_task_created_idx
  on public.task_comments (task_id, created_at asc);

-- L'operatore scelto non si può cambiare; permette solo la prima assegnazione
-- alle attività storiche che sono ancora senza operatore.
create or replace function public.prevent_task_operator_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.assigned_operator is not null
     and new.assigned_operator is distinct from old.assigned_operator then
    raise exception 'Operatore non modificabile dopo la creazione.';
  end if;
  return new;
end;
$$;

drop trigger if exists tasks_operator_immutable on public.tasks;
create trigger tasks_operator_immutable
  before update of assigned_operator on public.tasks
  for each row execute function public.prevent_task_operator_change();

-- Aggiorna la cache dello schema usata dall'API REST.
notify pgrst, 'reload schema';

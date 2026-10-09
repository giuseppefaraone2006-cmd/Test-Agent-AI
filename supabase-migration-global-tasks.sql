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

alter table public.tasks enable row level security;

drop policy if exists "Authenticated users can read shared tasks" on public.tasks;
drop policy if exists "Authenticated users can create shared tasks" on public.tasks;
drop policy if exists "Authenticated users can update shared tasks" on public.tasks;
drop policy if exists "Authenticated users can delete shared tasks" on public.tasks;
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
  mentioned_operators text[] not null default '{}',
  created_at timestamptz not null default now()
);

alter table public.task_comments
  add column if not exists mentioned_operators text[] not null default '{}';
update public.task_comments set mentioned_operators = '{}' where mentioned_operators is null;
alter table public.task_comments alter column mentioned_operators set default '{}';
alter table public.task_comments alter column mentioned_operators set not null;

create or replace function public.task_comment_mentions_are_valid(mentioned text[])
returns boolean
language sql
immutable
set search_path = ''
as $$
  select mentioned is not null
    and array_position(mentioned, null) is null
    and mentioned <@ array['DAVIDE', 'MARCO', 'PASQUALE', 'PEPPE S.', 'PEPPE F.', 'ALE', 'DANIELE S.']::text[]
    and cardinality(mentioned) = (
      select count(distinct operator_name)::integer
      from unnest(mentioned) as operators(operator_name)
    );
$$;

alter table public.task_comments
  drop constraint if exists task_comments_mentioned_operators_allowed;
alter table public.task_comments
  add constraint task_comments_mentioned_operators_allowed
  check (public.task_comment_mentions_are_valid(mentioned_operators));

alter table public.task_comments enable row level security;

drop policy if exists "Authenticated users can read comments on visible tasks" on public.task_comments;
drop policy if exists "Authenticated users can add comments to visible tasks" on public.task_comments;
create policy "Authenticated users can read comments on visible tasks"
  on public.task_comments for select to authenticated
  using (exists (select 1 from public.tasks t where t.id = task_comments.task_id));
create policy "Authenticated users can add comments to visible tasks"
  on public.task_comments for insert to authenticated
  with check (
    (select auth.uid()) = task_comments.user_id
    and exists (select 1 from public.tasks t where t.id = task_comments.task_id)
  );

create table if not exists public.operator_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  operator text not null check (
    operator in ('DAVIDE', 'MARCO', 'PASQUALE', 'PEPPE S.', 'PEPPE F.', 'ALE', 'DANIELE S.')
  ),
  updated_at timestamptz not null default now()
);

do $$
declare
  duplicate_profiles text;
begin
  select string_agg(
    format('%s (%s account)', operator, profile_count),
    ', ' order by operator
  )
  into duplicate_profiles
  from (
    select operator, count(*) as profile_count
    from public.operator_profiles
    group by operator
    having count(*) > 1
  ) duplicates;

  if duplicate_profiles is not null then
    raise exception 'Cannot make operator_profiles.operator unique: existing duplicates: %. Resolve these profiles before rerunning this script; no profiles were changed.', duplicate_profiles;
  end if;
end $$;

create unique index if not exists operator_profiles_operator_unique_idx
  on public.operator_profiles (operator);

alter table public.operator_profiles enable row level security;
do $$
declare
  existing_policy text;
begin
  for existing_policy in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'operator_profiles'
  loop
    execute format('drop policy if exists %I on public.operator_profiles', existing_policy);
  end loop;
end $$;

create policy "Users can read their own operator profile"
  on public.operator_profiles for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Users can create their own operator profile"
  on public.operator_profiles for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "Users can update their own operator profile"
  on public.operator_profiles for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

revoke all on table public.tasks from public, anon;
grant select, insert, update, delete on table public.tasks to authenticated;
revoke all on table public.task_comments from public, anon, authenticated;
grant select, insert on table public.task_comments to authenticated;
revoke all on table public.operator_profiles from public, anon, authenticated;
grant select, insert, update on table public.operator_profiles to authenticated;

create or replace function public.available_operators()
returns table (operator text)
language sql
stable
security definer
set search_path = ''
as $$
  select candidate.operator
  from unnest(array['DAVIDE', 'MARCO', 'PASQUALE', 'PEPPE S.', 'PEPPE F.', 'ALE', 'DANIELE S.']::text[])
    as candidate(operator)
  where auth.uid() is not null
    and not exists (
      select 1
      from public.operator_profiles profile
      where profile.operator = candidate.operator
        and profile.user_id <> (select auth.uid())
    )
  order by array_position(
    array['DAVIDE', 'MARCO', 'PASQUALE', 'PEPPE S.', 'PEPPE F.', 'ALE', 'DANIELE S.']::text[],
    candidate.operator
  );
$$;

revoke all on function public.available_operators() from public, anon;
grant execute on function public.available_operators() to authenticated;

create index if not exists tasks_created_at_idx
  on public.tasks (created_at desc);
create index if not exists task_comments_task_created_idx
  on public.task_comments (task_id, created_at asc);
create index if not exists task_comments_mentioned_operators_idx
  on public.task_comments using gin (mentioned_operators);
create index if not exists tasks_todo_operator_idx
  on public.tasks (assigned_operator) where done = false;

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

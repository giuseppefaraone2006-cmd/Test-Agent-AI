# Supabase per Tasks Lega

L’app usa Supabase Auth con email e password. Tutti gli utenti autenticati condividono la stessa lista; gli utenti non autenticati non possono leggere o modificare le attività. La colonna `user_id` resta come autore della creazione, ma non limita la visibilità o la modifica delle righe.

## Progetto nuovo

1. Crea un progetto Supabase.
2. Abilita l’accesso e la registrazione via email in Authentication.
3. In Authentication → URL Configuration imposta Site URL e Redirect URLs sull’URL effettivo dell’app GitHub Pages.
4. In SQL Editor esegui `supabase-setup.sql`.
5. In `index.html` inserisci Project URL e publishable key del tuo progetto. Non usare una secret o service role key nel-- Migrazione dalla lista privata per utente alla lista globale condivisa.
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

 browser.
6. Pubblica i file aggiornati su GitHub Pages.

## Progetto che ha già la vecchia tabella per utente

Esegui `supabase-migration-global-tasks.sql` nel SQL Editor del progetto già esistente. La migrazione:

- mantiene tutte le righe e i valori `user_id` esistenti come autore;
- aggiunge `assigned_operator`, lasciandolo NULL per le attività storiche;
- installa le policy condivise per le task e i commenti senza rimuovere le altre policy già presenti;
- concede lettura, inserimento, modifica ed eliminazione a tutti gli utenti autenticati. Le policy di modifica ed eliminazione verificano che `auth.uid()` sia presente; la lettura condivisa usa intenzionalmente `using (true)` ma è limitata al ruolo `authenticated`;
- crea `task_comments`, collegata alle task con cancellazione a cascata, e consente a ogni utente autenticato di leggere i commenti delle task visibili e aggiungerne firmandoli con il proprio account;
- aggiunge `mentioned_operators text[] not null default '{}'`, aggiorna le righe esistenti senza menzioni e applica un vincolo che accetta solo operatori configurati e impedisce duplicati;
- crea `operator_profiles`, che conserva l’associazione account-operatore, con policy RLS che permettono a ogni account autenticato di leggere/inserire/modificare solo il proprio profilo;
- crea gli indici per task da fare e menzioni strutturate;
- nega l’accesso al ruolo anonimo.

La migrazione è ripetibile e conserva i dati; sostituisce solo le policy applicative con gli stessi nomi e, per la nuova tabella profili, ricrea le policy per garantirne l’accesso esclusivamente al proprietario. Rieseguila dopo aver aggiornato lo script per installare le regole più recenti. Le attività storiche senza operatore appariranno come Non assegnato e potranno ricevere un operatore una sola volta. Le attività nuove richiedono una selezione nel modulo e non potranno cambiare operatore dopo il salvataggio.

## Profilo operatore e dashboard

Dopo l’accesso, se manca `operator_profiles` per l’account, l’app mostra la scelta obbligatoria tra gli operatori configurati (incluso `DANIELE S.`). La scelta viene salvata su Supabase, non nel browser, quindi lo stesso account mantiene il profilo su altri dispositivi. Dalla barra utente è possibile vedere e cambiare l’operatore associato. La dashboard mostra le attività aperte totali, quelle assegnate all’operatore del profilo, il conteggio dei commenti che lo menzionano e le menzioni più recenti. La lista completa delle attività è in una vista separata, raggiungibile dalla navigazione principale.

Le menzioni vengono salvate nell’array `task_comments.mentioned_operators`, non ricavate cercando `@` nel testo. Nel compositore dei commenti digita `@` e scegli un operatore dal menu. Le vecchie righe ricevono l’array vuoto e continuano a essere visualizzate.

## Commenti

Per un progetto nuovo, esegui `supabase-setup.sql`; per un progetto esistente, esegui `supabase-migration-global-tasks.sql` nel SQL Editor. Entrambi gli script creano la tabella `public.task_comments` e le policy RLS. Solo gli utenti autenticati possono leggere o inserire commenti; in inserimento il `user_id` deve corrispondere all’account attivo. I commenti sono associati alla task e vengono eliminati dal database se la task viene eliminata. L’autore viene mostrato come “Tu” sul proprio dispositivo e come identificativo abbreviato per gli altri account, senza rendere pubbliche le email degli utenti.

Nell’app apri “Commenti” su una task per caricare la conversazione; i messaggi sono ordinati dal più vecchio al più recente e mostrano autore e data/ora. Se hai già eseguito in precedenza la migrazione, riesegui la versione aggiornata di `supabase-migration-global-tasks.sql`, poi pubblica `index.html` su GitHub Pages.

## Verifica

Dopo aver eseguito lo script SQL aggiornato e pubblicato `index.html`:

1. Accedi con un account senza profilo: la scelta dell’operatore deve essere richiesta prima di mostrare la dashboard. Selezionalo e ricarica la pagina.
2. Accedi con lo stesso account da un secondo browser/dispositivo: il profilo deve risultare già associato. Cambialo nelle impostazioni e verifica che la scelta si rifletta anche sul primo dispositivo dopo il ricaricamento.
3. Crea una task da fare, poi aggiungi un commento scegliendo un operatore con il menu `@`. Verifica che il contatore dashboard aumenti di uno, che il commento appaia tra le menzioni recenti e che il collegamento apra la task.
4. Controlla in Table Editor → `public.task_comments` che `mentioned_operators` contenga il nome scelto. Le righe precedenti devono avere `{}` e continuare a essere leggibili. Prova a menzionare due volte lo stesso operatore nel commento: il conteggio deve restare uno.
5. Con un secondo account autenticato, apri la stessa task e verifica testo, autore, data/ora e ordinamento condivisi. Una sessione non autenticata non deve poter leggere/inserire commenti né leggere/modificare `operator_profiles`.
6. Verifica che la lista completa sia ancora accessibile e che creazione, assegnazione iniziale, completamento e cancellazione delle task continuino a funzionare. I filtri e l’immutabilità degli operatori assegnati devono restare invariati.

La publishable key è visibile nel frontend; RLS e i privilegi SQL sono quindi essenziali per proteggere i dati. Il codice non deve contenere chiavi secret o service role.

## Immutabilità operatore

Per un progetto già esistente, esegui nuovamente `supabase-migration-global-tasks.sql`: installa il trigger che impedisce di cambiare un operatore già assegnato. Le attività storiche senza operatore possono ricevere un’assegnazione iniziale; dopo quella scelta, l’operatore non è più modificabile.

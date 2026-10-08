# Supabase per Tasks Lega

L’app usa Supabase Auth con email e password. Tutti gli utenti autenticati condividono la stessa lista; gli utenti non autenticati non possono leggere o modificare le attività. La colonna `user_id` resta come autore della creazione, ma non limita la visibilità o la modifica delle righe.

## Progetto nuovo

1. Crea un progetto Supabase.
2. Abilita l’accesso e la registrazione via email in Authentication.
3. In Authentication → URL Configuration imposta Site URL e Redirect URLs sull’URL effettivo dell’app GitHub Pages.
4. In SQL Editor esegui `supabase-setup.sql`.
5. In `index.html` inserisci Project URL e publishable key del tuo progetto. Non usare una secret o service role key nel browser.
6. Pubblica i file aggiornati su GitHub Pages.

## Progetto che ha già la vecchia tabella per utente

Esegui `supabase-migration-global-tasks.sql` nel SQL Editor del progetto già esistente. La migrazione:

- mantiene tutte le righe e i valori `user_id` esistenti come autore;
- aggiunge `assigned_operator`, lasciandolo NULL per le attività storiche;
- sostituisce tutte le policy presenti con policy per la lista condivisa;
- concede lettura, inserimento, modifica ed eliminazione a tutti gli utenti autenticati. Le policy di modifica ed eliminazione verificano che `auth.uid()` sia presente; la lettura condivisa usa intenzionalmente `using (true)` ma è limitata al ruolo `authenticated`;
- crea `task_comments`, collegata alle task con cancellazione a cascata, e consente a ogni utente autenticato di leggere i commenti delle task visibili e aggiungerne firmandoli con il proprio account;
- nega l’accesso al ruolo anonimo.

La migrazione è ripetibile. Rieseguila dopo aver aggiornato lo script per installare le regole più recenti. Le attività storiche senza operatore appariranno come Non assegnato e potranno ricevere un operatore una sola volta. Le attività nuove richiedono una selezione nel modulo e non potranno cambiare operatore dopo il salvataggio.

## Commenti

Per un progetto nuovo, esegui `supabase-setup.sql`; per un progetto esistente, esegui `supabase-migration-global-tasks.sql` nel SQL Editor. Entrambi gli script creano la tabella `public.task_comments` e le policy RLS. Solo gli utenti autenticati possono leggere o inserire commenti; in inserimento il `user_id` deve corrispondere all’account attivo. I commenti sono associati alla task e vengono eliminati dal database se la task viene eliminata. L’autore viene mostrato come “Tu” sul proprio dispositivo e come identificativo abbreviato per gli altri account, senza rendere pubbliche le email degli utenti.

Nell’app apri “Commenti” su una task per caricare la conversazione; i messaggi sono ordinati dal più vecchio al più recente. Se hai già eseguito in precedenza la migrazione, riesegui la versione aggiornata di `supabase-migration-global-tasks.sql`, poi pubblica `index.html` su GitHub Pages.

## Verifica

Dopo aver pubblicato `index.html`, accedi con un account, crea un’attività scegliendo un operatore e controlla che appaia in Table Editor → `public.tasks`. Poi accedi da un altro browser o dispositivo con un secondo account autenticato: vedrai la stessa riga e potrai modificarne lo stato o eliminarla. Prova anche da disconnesso: il modulo attività non deve essere accessibile.

Per verificare i commenti, accedi con due account autenticati: aggiungi un commento sulla stessa task dal primo dispositivo e apri “Commenti” dal secondo. Controlla che autore, data/ora e testo siano visibili e prova a inviare un testo vuoto. Da Table Editor puoi controllare le righe in `public.task_comments`; da una sessione non autenticata la lettura deve essere negata.

La publishable key è visibile nel frontend; RLS e i privilegi SQL sono quindi essenziali per proteggere i dati. Il codice non deve contenere chiavi secret o service role.

## Immutabilità operatore e logo

Per un progetto già esistente, esegui nuovamente la versione aggiornata di supabase-migration-global-tasks.sql: installa il trigger che impedisce di cambiare un operatore già assegnato. Le attività storiche senza operatore possono ricevere un’assegnazione iniziale; dopo quella scelta, l’operatore non è più modificabile.

Nel riquadro in alto di index.html sostituisci il valore PERCORSO-LOGO-DA-SOSTITUIRE.png con il percorso del logo che aggiungerai al repository. Per esempio, se lo metti in una cartella assets, usa un percorso relativo come assets/logo.png.

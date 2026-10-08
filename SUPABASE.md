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

Esegui una sola volta `supabase-migration-global-tasks.sql` nel SQL Editor del progetto già esistente. La migrazione:

- mantiene tutte le righe e i valori `user_id` esistenti come autore;
- aggiunge `assigned_operator`, lasciandolo NULL per le attività storiche;
- sostituisce tutte le policy presenti con policy per la lista condivisa;
- concede lettura, inserimento, modifica ed eliminazione a tutti gli utenti autenticati;
- nega l’accesso al ruolo anonimo.

Non rieseguire la migrazione dopo che è terminata correttamente. Le attività storiche senza operatore appariranno come “Non assegnato” e potranno ricevere uno dei sei operatori dal menu sulla riga. Le attività nuove richiedono una selezione nel modulo.

## Verifica

Dopo aver pubblicato `index.html`, accedi con un account, crea un’attività scegliendo un operatore e controlla che appaia in Table Editor → `public.tasks`. Poi accedi da un altro browser o dispositivo con un secondo account autenticato: vedrai la stessa riga e potrai modificarne lo stato o eliminarla. Prova anche da disconnesso: il modulo attività non deve essere accessibile.

La publishable key è visibile nel frontend; RLS e i privilegi SQL sono quindi essenziali per proteggere i dati. Il codice non deve contenere chiavi secret o service role.

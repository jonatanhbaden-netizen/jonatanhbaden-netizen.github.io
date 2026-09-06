-- pg_net lar cron kalle Edge Functions. Anon-nøkkelen er offentlig (den ligger
-- i web/shared/config.js); funksjonene gjør bare noe hvis hemmelighetene
-- deres er satt, og alt de gjør er idempotent.
create extension if not exists pg_net;

select cron.schedule('jobbo_varsler', '*/5 * * * *', $$
  select net.http_post(
    url := 'https://ndvefswyfriivcqntpxu.supabase.co/functions/v1/send-notifications',
    headers := '{"Content-Type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5kdmVmc3d5ZnJpaXZjcW50cHh1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg0OTkzMzAsImV4cCI6MjEwNDA3NTMzMH0.U_17N21nB9DsaCEG2Z-MrU18mRnAbFKzrw5LUzdnYOI"}'::jsonb,
    body := '{}'::jsonb)
$$);

-- Import før nattkjøringen kl. 04, så nye stillinger er med i fordelingen.
select cron.schedule('jobbo_import_nav', '30 3 * * *', $$
  select net.http_post(
    url := 'https://ndvefswyfriivcqntpxu.supabase.co/functions/v1/import-nav',
    headers := '{"Content-Type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5kdmVmc3d5ZnJpaXZjcW50cHh1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg0OTkzMzAsImV4cCI6MjEwNDA3NTMzMH0.U_17N21nB9DsaCEG2Z-MrU18mRnAbFKzrw5LUzdnYOI"}'::jsonb,
    body := '{}'::jsonb)
$$);

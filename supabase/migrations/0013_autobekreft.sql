-- Nye kontoer bekreftes idet de opprettes, så registrering virker uten
-- e-post. Fjern denne triggeren når egen SMTP er satt opp og du vil kreve
-- bekreftet e-post igjen.
create or replace function public.auto_confirm_user()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  if new.email_confirmed_at is null then
    new.email_confirmed_at := now();
  end if;
  return new;
end
$fn$;
revoke execute on function public.auto_confirm_user() from public, anon, authenticated;

create trigger on_auth_user_autoconfirm
  before insert on auth.users
  for each row execute function public.auto_confirm_user();

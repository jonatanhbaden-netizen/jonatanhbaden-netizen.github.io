-- Resolves the company of the signed-in employer. security definer so that
-- reading employer_users does not itself require a policy that reads
-- employer_users (infinite recursion).
create or replace function public.current_company_id()
returns uuid language sql stable security definer set search_path = public as $fn$
  select company_id from public.employer_users where id = auth.uid()
$fn$;

alter table public.companies      enable row level security;
alter table public.employer_users enable row level security;
alter table public.jobs           enable row level security;
alter table public.profiles       enable row level security;
alter table public.match_scores   enable row level security;
alter table public.applications   enable row level security;
alter table public.interviews     enable row level security;

create policy companies_select on public.companies
  for select to authenticated using (true);
create policy companies_update on public.companies
  for update to authenticated using (id = public.current_company_id());

create policy employer_users_select on public.employer_users
  for select to authenticated using (id = auth.uid());

create policy jobs_select on public.jobs
  for select to authenticated
  using (status = 'published' or company_id = public.current_company_id());
create policy jobs_insert on public.jobs
  for insert to authenticated with check (company_id = public.current_company_id());
create policy jobs_update on public.jobs
  for update to authenticated
  using (company_id = public.current_company_id())
  with check (company_id = public.current_company_id());
create policy jobs_delete on public.jobs
  for delete to authenticated using (company_id = public.current_company_id());

-- This is the policy that stops anyone browsing the candidate pool.
create policy profiles_select_own on public.profiles
  for select to authenticated using (id = auth.uid());
create policy profiles_select_applicant on public.profiles
  for select to authenticated
  using (exists (
    select 1 from public.applications a
    join public.jobs j on j.id = a.job_id
    where a.profile_id = public.profiles.id
      and j.company_id = public.current_company_id()
  ));
create policy profiles_insert_own on public.profiles
  for insert to authenticated with check (id = auth.uid());
create policy profiles_update_own on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Employers use match_scores only for the "47 kvalifiserte matchet" count.
-- Profile details still require an application.
create policy match_scores_select_own on public.match_scores
  for select to authenticated using (profile_id = auth.uid());
create policy match_scores_select_employer on public.match_scores
  for select to authenticated
  using (exists (
    select 1 from public.jobs j
    where j.id = public.match_scores.job_id
      and j.company_id = public.current_company_id()
  ));

create policy applications_select_own on public.applications
  for select to authenticated using (profile_id = auth.uid());
create policy applications_insert_own on public.applications
  for insert to authenticated with check (profile_id = auth.uid());
create policy applications_select_employer on public.applications
  for select to authenticated
  using (exists (
    select 1 from public.jobs j
    where j.id = public.applications.job_id
      and j.company_id = public.current_company_id()
  ));
create policy applications_update_employer on public.applications
  for update to authenticated
  using (exists (
    select 1 from public.jobs j
    where j.id = public.applications.job_id
      and j.company_id = public.current_company_id()
  ));

create policy interviews_select_own on public.interviews
  for select to authenticated
  using (exists (
    select 1 from public.applications a
    where a.id = public.interviews.application_id and a.profile_id = auth.uid()
  ));
create policy interviews_all_employer on public.interviews
  for all to authenticated
  using (exists (
    select 1 from public.applications a
    join public.jobs j on j.id = a.job_id
    where a.id = public.interviews.application_id
      and j.company_id = public.current_company_id()
  ))
  with check (exists (
    select 1 from public.applications a
    join public.jobs j on j.id = a.job_id
    where a.id = public.interviews.application_id
      and j.company_id = public.current_company_id()
  ));

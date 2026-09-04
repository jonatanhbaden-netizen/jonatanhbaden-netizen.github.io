-- Canonical skill vocabulary. Lowercase, no synonyms (spec section 7).
-- The employer wizard and the candidate CV builder both pick from this list —
-- that shared vocabulary is what makes set intersection a valid match signal.
create table public.skills (
  name     text primary key,
  category text not null,
  label    text not null
);

alter table public.skills enable row level security;
create policy skills_select on public.skills for select to authenticated using (true);
create policy skills_select_anon on public.skills for select to anon using (true);

create index skills_category_idx on public.skills (category);

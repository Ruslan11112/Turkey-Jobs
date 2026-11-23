-- Temporarily allow applicants to submit without creating an account.
-- Anonymous visitors can insert applications only for published jobs and cannot read them.
alter table public.applications alter column user_id drop not null;

drop policy if exists "public submit applications without account" on public.applications;
create policy "public submit applications without account"
  on public.applications
  for insert
  to anon
  with check (
    user_id is null
    and status = 'new'
    and char_length(btrim(applicant_name)) between 2 and 120
    and char_length(btrim(contact_email)) between 5 and 254
    and btrim(contact_email) ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    and char_length(contact_phone) between 7 and 24
    and exists (
      select 1
      from public.jobs j
      where j.id = applications.job_id
        and j.is_published
    )
  );

revoke insert on public.applications from anon;
grant insert (job_id, applicant_name, contact_email, contact_phone)
  on public.applications to anon;

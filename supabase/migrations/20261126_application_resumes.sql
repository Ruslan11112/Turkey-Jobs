-- Store optional applicant resumes in a private bucket and keep access admin-only.
drop policy if exists "public submit applications without account" on public.applications;
create policy "public submit applications without account"
  on public.applications for insert to anon
  with check (
    user_id is null
    and status = 'new'
    and char_length(btrim(applicant_name)) between 2 and 120
    and char_length(btrim(contact_email)) between 5 and 254
    and btrim(contact_email) ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    and char_length(contact_phone) between 7 and 24
    and (resume_path is null or (split_part(resume_path, '/', 1) = id::text and resume_path ~ '\.(pdf|doc|docx)$'))
    and exists (select 1 from public.jobs j where j.id = applications.job_id and j.is_published)
  );

revoke insert on public.applications from anon;
grant insert (id, job_id, applicant_name, contact_email, contact_phone, resume_path)
  on public.applications to anon;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'application-resumes', 'application-resumes', false, 10485760,
  array['application/pdf','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

grant insert on storage.objects to anon;

drop policy if exists "public upload application resumes" on storage.objects;
create policy "public upload application resumes"
  on storage.objects for insert to anon
  with check (
    bucket_id = 'application-resumes'
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|doc|docx)$'
  );

drop policy if exists "admins read application resumes" on storage.objects;
create policy "admins read application resumes"
  on storage.objects for select to authenticated
  using (bucket_id = 'application-resumes' and public.is_admin());

-- Upgrade an existing Turkey Jobs database with candidate accounts and an admin inbox.
-- Run this once if the original schema.sql has already been applied.
alter table public.profiles add column if not exists email text not null default '';
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,full_name,phone,email)
  values(new.id,coalesce(new.raw_user_meta_data->>'full_name',''),coalesce(new.raw_user_meta_data->>'phone',''),coalesce(new.email,''))
  on conflict(id) do update set email=excluded.email;
  return new;
end $$;
update public.profiles p set email=coalesce(u.email,'') from auth.users u where u.id=p.id and p.email='';
create or replace function public.sync_user_email() returns trigger language plpgsql security definer set search_path=public as $$ begin update public.profiles set email=coalesce(new.email,'') where id=new.id; return new; end $$;
drop trigger if exists auth_user_email_updated on auth.users;
create trigger auth_user_email_updated after update of email on auth.users for each row execute function public.sync_user_email();
revoke update on public.profiles from authenticated;
grant update(full_name,phone) on public.profiles to authenticated;
insert into public.jobs(id,title,company,city,salary,description,image_url,is_published) values
('10000000-0000-4000-8000-000000000004','Activities Host','TUI','Fethiye, Antalya, Izmir and other resorts','From TRY 43,530 net/month; accommodation provided if relocation needed','Summer 2027, local-resident position; Turkish citizenship or right-to-work documents required.','',true),
('10000000-0000-4000-8000-000000000005','Fitness Instructor','TUI','Sarigerme, Izmir, Fethiye','From TRY 43,087 net/month; TRY 47,880 for qualified applicants','Summer 2027, multilingual, local-resident position; Turkish citizenship or right-to-work documents required.','',true),
('10000000-0000-4000-8000-000000000006','Revenue Analyst - Leased Hotels Türkiye','Accor','Istanbul','Full time; salary not disclosed','Permanent role at Novotel Istanbul Bosphorus.','',true),
('10000000-0000-4000-8000-000000000007','Restaurant Manager','Swissôtel Büyük Efes','Izmir','Full time; salary not disclosed','Permanent role. Review the official employer listing for requirements.','',true),
('10000000-0000-4000-8000-000000000008','Restaurant Hostess','Raffles Istanbul','Istanbul','Full time; salary not disclosed','Permanent, entry-level role. Review the official employer listing for requirements.','',true),
('10000000-0000-4000-8000-000000000009','Waiter - In Room Dining','Raffles Istanbul','Istanbul','Full time; salary not disclosed','Permanent role. Review the official employer listing for requirements.','',true),
('10000000-0000-4000-8000-000000000010','Front Office Supervisor','The Grand Tarabya Managed by Accor','Istanbul','Full time; salary not disclosed','Permanent, mid-senior role. Review the official employer listing for requirements.','',true)
on conflict(id) do update set title=excluded.title,company=excluded.company,city=excluded.city,salary=excluded.salary,description=excluded.description,is_published=excluded.is_published;

-- Candidate resume, private portfolio files, complaints, and admin notifications.
create table public.candidate_resumes (
  user_id uuid primary key references auth.users(id) on delete cascade,
  headline text not null default '', summary text not null default '', experience text not null default '',
  education text not null default '', skills text not null default '', languages text not null default '',
  updated_at timestamptz not null default now()
);
create table public.portfolio_files (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  storage_path text not null unique, file_name text not null, content_type text not null default '',
  size_bytes bigint not null check (size_bytes > 0 and size_bytes <= 15728640), created_at timestamptz not null default now()
);
create table public.complaints (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  subject text not null check (char_length(subject) between 3 and 160),
  message text not null check (char_length(message) between 10 and 5000),
  status text not null default 'new' check (status in ('new','reviewing','resolved')),
  admin_reply text not null default '', created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.admin_notifications (
  id uuid primary key default gen_random_uuid(), kind text not null check (kind in ('application','resume','complaint')),
  user_id uuid references auth.users(id) on delete set null,
  application_id uuid references public.applications(id) on delete cascade,
  resume_user_id uuid references public.candidate_resumes(user_id) on delete cascade,
  complaint_id uuid references public.complaints(id) on delete cascade,
  summary text not null, is_read boolean not null default false, created_at timestamptz not null default now()
);
create index admin_notifications_created_at_idx on public.admin_notifications(created_at desc);
create index complaints_user_id_idx on public.complaints(user_id);
create index portfolio_files_user_id_idx on public.portfolio_files(user_id);

create or replace function public.notify_admin_application() returns trigger language plpgsql security definer set search_path=public as $$
declare candidate_name text; vacancy_name text;
begin
  select full_name into candidate_name from public.profiles where id=new.user_id;
  select title into vacancy_name from public.jobs where id=new.job_id;
  insert into public.admin_notifications(kind,user_id,application_id,summary)
  values('application',new.user_id,new.id,'Новая заявка: '||coalesce(candidate_name,new.applicant_name)||' — '||coalesce(vacancy_name,'вакансия'));
  return new;
end $$;
create trigger application_admin_notification after insert on public.applications for each row execute function public.notify_admin_application();

create or replace function public.notify_admin_resume() returns trigger language plpgsql security definer set search_path=public as $$
declare candidate_name text;
begin
  if tg_op='UPDATE' and row(old.headline,old.summary,old.experience,old.education,old.skills,old.languages) is not distinct from row(new.headline,new.summary,new.experience,new.education,new.skills,new.languages) then return new; end if;
  select full_name into candidate_name from public.profiles where id=new.user_id;
  insert into public.admin_notifications(kind,user_id,resume_user_id,summary)
  values('resume',new.user_id,new.user_id,'Новое или обновлённое резюме: '||coalesce(candidate_name,'кандидат')||case when new.headline='' then '' else ' — '||new.headline end);
  return new;
end $$;
create trigger resume_admin_notification after insert or update on public.candidate_resumes for each row execute function public.notify_admin_resume();

create or replace function public.notify_admin_complaint() returns trigger language plpgsql security definer set search_path=public as $$
declare candidate_name text;
begin
  select full_name into candidate_name from public.profiles where id=new.user_id;
  insert into public.admin_notifications(kind,user_id,complaint_id,summary)
  values('complaint',new.user_id,new.id,'Жалоба от '||coalesce(candidate_name,'пользователя')||': '||new.subject);
  return new;
end $$;
create trigger complaint_admin_notification after insert on public.complaints for each row execute function public.notify_admin_complaint();
create or replace function public.notify_admin_portfolio_file() returns trigger language plpgsql security definer set search_path=public as $$
declare candidate_name text;
begin
  select full_name into candidate_name from public.profiles where id=new.user_id;
  insert into public.admin_notifications(kind,user_id,summary)
  values('resume',new.user_id,'Кандидат '||coalesce(candidate_name,'')||' прикрепил файл портфолио: '||new.file_name);
  return new;
end $$;
create trigger portfolio_admin_notification after insert on public.portfolio_files for each row execute function public.notify_admin_portfolio_file();
create trigger complaints_touch_updated before update on public.complaints for each row execute function public.touch_updated_at();

alter table public.candidate_resumes enable row level security;
alter table public.portfolio_files enable row level security;
alter table public.complaints enable row level security;
alter table public.admin_notifications enable row level security;
create policy "candidate resumes own or admin read" on public.candidate_resumes for select to authenticated using (user_id=auth.uid() or public.is_admin());
create policy "candidates save own resume" on public.candidate_resumes for insert to authenticated with check (user_id=auth.uid());
create policy "candidates update own resume" on public.candidate_resumes for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy "portfolio files own or admin read" on public.portfolio_files for select to authenticated using (user_id=auth.uid() or public.is_admin());
create policy "candidates add own portfolio files" on public.portfolio_files for insert to authenticated with check (user_id=auth.uid());
create policy "candidates remove own portfolio files" on public.portfolio_files for delete to authenticated using (user_id=auth.uid());
create policy "complaints own or admin read" on public.complaints for select to authenticated using (user_id=auth.uid() or public.is_admin());
create policy "users send own complaints" on public.complaints for insert to authenticated with check (user_id=auth.uid() and status='new');
create policy "admins handle complaints" on public.complaints for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admins read notifications" on public.admin_notifications for select to authenticated using (public.is_admin());
create policy "admins mark notifications read" on public.admin_notifications for update to authenticated using (public.is_admin()) with check (public.is_admin());
grant select,insert,update on public.candidate_resumes to authenticated;
grant select,insert,delete on public.portfolio_files to authenticated;
grant select,insert on public.complaints to authenticated;
grant update on public.complaints to authenticated;
grant select,update on public.admin_notifications to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('candidate-files','candidate-files',false,15728640,array['application/pdf','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.ms-powerpoint','application/vnd.openxmlformats-officedocument.presentationml.presentation','application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create policy "candidate files own or admin read" on storage.objects for select to authenticated
  using (bucket_id='candidate-files' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));
create policy "candidates upload own files" on storage.objects for insert to authenticated
  with check (bucket_id='candidate-files' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "candidates update own files" on storage.objects for update to authenticated
  using (bucket_id='candidate-files' and (storage.foldername(name))[1]=auth.uid()::text)
  with check (bucket_id='candidate-files' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "candidates delete own files" on storage.objects for delete to authenticated
  using (bucket_id='candidate-files' and (storage.foldername(name))[1]=auth.uid()::text);

-- After your owner account is registered, grant the administrator role in SQL Editor:
-- insert into public.admin_users(user_id) select id from auth.users where email='you@example.com' on conflict do nothing;


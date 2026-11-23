-- Run in Supabase SQL Editor. Admins are provisioned by the project owner using SQL.
create extension if not exists pgcrypto;
create type public.application_status as enum ('new','reviewing','sent_to_employer','approved','rejected');
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '', phone text not null default '', email text not null default '', created_at timestamptz not null default now()
);
alter table public.profiles add column if not exists email text not null default '';
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,full_name,phone,email) values(new.id,coalesce(new.raw_user_meta_data->>'full_name',''),coalesce(new.raw_user_meta_data->>'phone',''),coalesce(new.email,'')) on conflict(id) do update set email=excluded.email;
  return new;
end $$;
create trigger auth_user_created_profile after insert on auth.users for each row execute function public.handle_new_user();
create or replace function public.sync_user_email() returns trigger language plpgsql security definer set search_path=public as $$ begin update public.profiles set email=coalesce(new.email,'') where id=new.id; return new; end $$;
create trigger auth_user_email_updated after update of email on auth.users for each row execute function public.sync_user_email();
update public.profiles p set email=coalesce(u.email,'') from auth.users u where u.id=p.id and p.email='';
create table public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create or replace function public.promote_turkey_jobs_owner() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if lower(coalesce(new.email,''))='ruskhamrakulov@gmail.com' and new.email_confirmed_at is not null then
    insert into public.admin_users(user_id) values(new.id) on conflict(user_id) do nothing;
    update public.profiles set phone='+77073186480' where id=new.id;
  end if;
  return new;
end $$;
create trigger promote_turkey_jobs_owner after insert or update of email_confirmed_at on auth.users for each row execute function public.promote_turkey_jobs_owner();
create table public.jobs (
  id uuid primary key default gen_random_uuid(), title text not null, company text not null default '', city text not null default '',
  salary text not null default '', description text not null default '', image_url text not null default '', source_url text not null default '',
  is_published boolean not null default false, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.applications (
  id uuid primary key default gen_random_uuid(), user_id uuid references auth.users(id) on delete cascade,
  job_id uuid not null references public.jobs(id) on delete restrict, applicant_name text not null,
  contact_email text not null, contact_phone text not null default '', resume_path text,
  status public.application_status not null default 'new', employer_name text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
-- Starter vacancies verified on the employers' official career pages (20 Nov 2026).
insert into public.jobs(id,title,company,city,salary,description,image_url,is_published) values
('10000000-0000-4000-8000-000000000001','Hotel Representative','TUI','Antalya','From TRY 38,800 net/month plus average commission stated by employer','Season 2027, local-resident position; existing right to work in Türkiye required. Confirm language and eligibility on the employer page.','',true),
('10000000-0000-4000-8000-000000000002','Service Support Representative','TUI','Antalya','TRY 44,400 net/month','Season 2027, local-resident position; German and English; existing right to work in Türkiye required. Confirm eligibility on the employer page.','',true),
('10000000-0000-4000-8000-000000000003','Room Attendant','Hampton by Hilton Antalya Airport','Antalya','Full time; salary not disclosed','Official Hilton listing posted 20 October 2026. Confirm current status and eligibility on the employer page.','',true),
('10000000-0000-4000-8000-000000000004','Activities Host','TUI','Fethiye, Antalya, Izmir and other resorts','From TRY 43,530 net/month; accommodation provided if relocation needed','Summer 2027, local-resident position; Turkish citizenship or right-to-work documents required.','',true),
('10000000-0000-4000-8000-000000000005','Fitness Instructor','TUI','Sarigerme, Izmir, Fethiye','From TRY 43,087 net/month; TRY 47,880 for qualified applicants','Summer 2027, multilingual, local-resident position; Turkish citizenship or right-to-work documents required.','',true),
('10000000-0000-4000-8000-000000000006','Revenue Analyst - Leased Hotels Türkiye','Accor','Istanbul','Full time; salary not disclosed','Permanent role at Novotel Istanbul Bosphorus.','',true),
('10000000-0000-4000-8000-000000000007','Restaurant Manager','Swissôtel Büyük Efes','Izmir','Full time; salary not disclosed','Permanent role. Review the official employer listing for requirements.','',true),
('10000000-0000-4000-8000-000000000008','Restaurant Hostess','Raffles Istanbul','Istanbul','Full time; salary not disclosed','Permanent, entry-level role. Review the official employer listing for requirements.','',true),
('10000000-0000-4000-8000-000000000009','Waiter - In Room Dining','Raffles Istanbul','Istanbul','Full time; salary not disclosed','Permanent role. Review the official employer listing for requirements.','',true),
('10000000-0000-4000-8000-000000000010','Front Office Supervisor','The Grand Tarabya Managed by Accor','Istanbul','Full time; salary not disclosed','Permanent, mid-senior role. Review the official employer listing for requirements.','',true)
on conflict(id) do nothing;
-- Additional employer-listed openings reviewed 21 Nov 2026.
insert into public.jobs(id,title,company,city,salary,description,image_url,source_url,is_published) values
('10000000-0000-4000-8000-000000000011','Football Coach | Multilingual | Local Residents | Türkiye | S27','TUI','Sarigerme','From TRY 47,880 net/month; full time; right to work in Türkiye required','Current employer listing; check the official page for eligibility, requirements and closing date.','','https://careers.tuigroup.com/en/job/sarigerme/football-coach-multilingual-local-residents-turkiye-s27/2937/46590169664',true),
('10000000-0000-4000-8000-000000000012','Childcare Host | Multilingual | Local Residents | S27','TUI','Fethiye, Antalya, Izmir','From TRY 43,530 net/month; accommodation if relocating; right to work in Türkiye required','Current employer listing; check the official page for eligibility, requirements and closing date.','','https://careers.tuigroup.com/en/job/fethiye/childcare-host-multilingual-local-residents-s27/2937/46564367680',true),
('10000000-0000-4000-8000-000000000013','Purchasing Specialist (Engineering)','Accor · Rixos Tersane Istanbul','Istanbul','Full time; salary not disclosed','Current employer listing; check the official page for eligibility, requirements and closing date.','','https://careers.accor.com/global/en/job/purchasing-specialist-engineering-in-rixos-tersane-istanbul-istanbul-turkey-jid-110212',true),
('10000000-0000-4000-8000-000000000014','Teknik Servis Takım Lideri','Accor · ibis Ankara Airport','Ankara','Full time; salary not disclosed','Current employer listing; check the official page for eligibility, requirements and closing date.','','https://careers.accor.com/global/en/job/teknik-servis-tak-m-lideri-ibis-ankara-airport-in-ibis-ankara-airport-ankara-turkey-jid-117959',true),
('10000000-0000-4000-8000-000000000015','Director of Revenue','Accor · Swissôtel Büyük Efes','Izmir','Full time; salary not disclosed','Current employer listing; check the official page for eligibility, requirements and closing date.','','https://careers.accor.com/global/en/job/director-of-revenue-in-swissotel-buyuk-efes-izmir-izmir-turkey-jid-89678',true),
('10000000-0000-4000-8000-000000000016','F&B Guest Experience Manager','Accor · Raffles Istanbul','Istanbul','Full time; salary not disclosed','Current employer listing; check the official page for eligibility, requirements and closing date.','','https://careers.accor.com/global/en/job/f-and-b-guest-experience-manager-in-raffles-istanbul-istanbul-turkey-jid-117570',true),
('10000000-0000-4000-8000-000000000017','Spa Therapist','Accor · Swissôtel The Bosphorus','Istanbul','Full time; salary not disclosed','Current employer listing; check the official page for eligibility, requirements and closing date.','','https://careers.accor.com/global/en/job/spa-therapist-in-swissotel-the-bosphorus-istanbul-istanbul-turkey-jid-117186',true),
('10000000-0000-4000-8000-000000000018','Head Chef (Italian Restaurant)','Accor · Swissôtel Büyük Efes','Izmir','Full time; salary not disclosed','Current employer listing; check the official page for eligibility, requirements and closing date.','','https://careers.accor.com/global/en/job/head-chef-italian-chef-in-an-italian-restaurant-in-izmir-turkey-jid-82950',true),
('10000000-0000-4000-8000-000000000019','Rooms Division Manager','Accor · ibis Istanbul Tuzla','Istanbul · Tuzla','Full time; salary not disclosed','Current employer listing; check the official page for eligibility, requirements and closing date.','','https://careers.accor.com/global/en/job/rooms-division-manager-ibis-istanbul-tuzla-in-ibis-istanbul-tuzla-hotel-istanbul-tuzla-turkey-jid-117089',true),
('10000000-0000-4000-8000-000000000020','Director of Sales','Accor · Swissôtel Büyük Efes','Izmir','Full time; salary not disclosed','Current employer listing; check the official page for eligibility, requirements and closing date.','','https://careers.accor.com/global/en/job/director-of-sales-in-swissotel-buyuk-efes-izmir-izmir-turkey-jid-85533',true),
('10000000-0000-4000-8000-000000000021','Guest Relations Manager','Accor · Fairmont Quasar Istanbul','Istanbul','Full time; salary not disclosed','Current employer listing; check the official page for eligibility, requirements and closing date.','','https://careers.accor.com/global/en/job/guest-relations-manager-in-fairmont-quasar-istanbul-istanbul-turkey-jid-114274',true),
('10000000-0000-4000-8000-000000000022','Sales Executive, Corporate','Accor · Fairmont Quasar Istanbul','Istanbul','Full time; salary not disclosed','Current employer listing; check the official page for eligibility, requirements and closing date.','','https://careers.accor.com/global/en/job/sales-executive-corporate-in-fairmont-quasar-istanbul-istanbul-turkey-jid-106547',true),
('10000000-0000-4000-8000-000000000023','Hostess','Accor · Swissôtel Büyük Efes','Izmir','Full time; salary not disclosed','Current employer listing; check the official page for eligibility, requirements and closing date.','','https://careers.accor.com/global/en/job/hostess-in-izmir-turkey-jid-63053',true),
('10000000-0000-4000-8000-000000000024','Reservations Supervisor','Accor · Sofitel Istanbul Taksim','Istanbul','Full time; salary not disclosed','Current employer listing; check the official page for eligibility, requirements and closing date.','','https://careers.accor.com/global/en/job/reservations-supervisor-in-sofitel-istanbul-taksim-istanbul-turkey-jid-111709',true),
('10000000-0000-4000-8000-000000000025','Vice President Operations · Türkiye','Accor · Türkiye Office','Istanbul','Senior leadership role; see employer page for terms','Current employer listing; check the official page for eligibility, requirements and closing date.','','https://careers.accor.com/tr/tr/job/vice-president-operations-premium-economy-and-midscale-brands-tuerkiye-in-istanbul-turkey-jid-110274',true),
('10000000-0000-4000-8000-000000000026','Digital Marketing Manager','Accor · Fairmont Quasar Istanbul','Istanbul','Full time; salary not disclosed','Current employer listing; check the official page for eligibility, requirements and closing date.','','https://careers.accor.com/global/en/job/digital-marketing-manager-in-fairmont-quasar-istanbul-istanbul-turkey-jid-111542',true),
('10000000-0000-4000-8000-000000000027','Cost Controller','Accor · Fairmont Quasar Istanbul','Istanbul','Full time; salary not disclosed','Current employer listing; check the official page for eligibility, requirements and closing date.','','https://careers.accor.com/global/en/job/cost-controller-in-fairmont-quasar-istanbul-istanbul-turkey-jid-106239',true),
('10000000-0000-4000-8000-000000000028','Reception Agent','Accor · Fairmont Quasar Istanbul','Istanbul','Full time; salary not disclosed','Current employer listing; check the official page for eligibility, requirements and closing date.','','https://careers.accor.com/job/reception-agent-in-fairmont-quasar-istanbul-istanbul-turkey-jid-112704',true),
('10000000-0000-4000-8000-000000000029','Guest Services Agent','Accor · Swissôtel Büyük Efes','Izmir','Full time; salary not disclosed','Current employer listing; check the official page for eligibility, requirements and closing date.','','https://careers.accor.com/job/guest-services-agent-in-izmir-turkey-jid-51440',true),
('10000000-0000-4000-8000-000000000030','Guest Relations Executive','Accor · Swissôtel Büyük Efes','Izmir','Full time; salary not disclosed','Current employer listing; check the official page for eligibility, requirements and closing date.','','https://careers.accor.com/tr/tr/job/guest-relations-executive-in-izmir-turkey-jid-67587',true)
on conflict(id) do update set title=excluded.title,company=excluded.company,city=excluded.city,salary=excluded.salary,description=excluded.description,source_url=excluded.source_url,is_published=true;
create index applications_user_id_idx on public.applications(user_id);
create index applications_job_id_idx on public.applications(job_id);
create index applications_status_idx on public.applications(status);
create or replace function public.is_admin_role() returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.admin_users where user_id=auth.uid()); $$;
revoke all on function public.is_admin_role() from public;
grant execute on function public.is_admin_role() to anon,authenticated;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$ select coalesce(auth.jwt()->>'aal','')='aal2' and public.is_admin_role(); $$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;
create or replace function public.touch_updated_at() returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end $$;
create trigger jobs_touch_updated before update on public.jobs for each row execute function public.touch_updated_at();
create trigger applications_touch_updated before update on public.applications for each row execute function public.touch_updated_at();
alter table public.profiles enable row level security;
alter table public.admin_users enable row level security;
alter table public.jobs enable row level security;
alter table public.applications enable row level security;
create policy "profiles read own or admin" on public.profiles for select to authenticated using (id=auth.uid() or public.is_admin());
create policy "profiles insert self" on public.profiles for insert to authenticated with check (id=auth.uid());
create policy "profiles update self" on public.profiles for update to authenticated using (id=auth.uid()) with check (id=auth.uid());
create policy "admins read admin list" on public.admin_users for select to authenticated using (public.is_admin());
create policy "published jobs are public; admins read all" on public.jobs for select to anon,authenticated using (is_published or public.is_admin());
create policy "admins insert jobs" on public.jobs for insert to authenticated with check (public.is_admin());
create policy "admins update jobs" on public.jobs for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admins delete jobs" on public.jobs for delete to authenticated using (public.is_admin());
create policy "applicants read own; admins read all" on public.applications for select to authenticated using (user_id=auth.uid() or public.is_admin());
create policy "users submit own applications" on public.applications for insert to authenticated with check (user_id=auth.uid() and status='new');
create policy "public submit applications without account" on public.applications for insert to anon with check (user_id is null and status='new' and char_length(btrim(applicant_name)) between 2 and 120 and char_length(btrim(contact_email)) between 5 and 254 and btrim(contact_email) ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' and char_length(contact_phone) between 7 and 24 and exists(select 1 from public.jobs j where j.id=applications.job_id and j.is_published));
create policy "admins update applications" on public.applications for update to authenticated using (public.is_admin()) with check (public.is_admin());
-- Grant only the table operations needed by the frontend. RLS applies in addition to these grants.
grant select,insert on public.profiles to authenticated;
grant update(full_name,phone) on public.profiles to authenticated;
grant select on public.admin_users to authenticated;
grant select on public.jobs to anon,authenticated;
grant insert,update,delete on public.jobs to authenticated;
grant select,insert,update on public.applications to authenticated;
revoke insert on public.applications from anon;
grant insert(job_id,applicant_name,contact_email,contact_phone) on public.applications to anon;

-- Candidate resume, private portfolio files, complaints, and admin notifications.
create table public.candidate_resumes (
  user_id uuid primary key references auth.users(id) on delete cascade,
  headline text not null default '', summary text not null default '', experience text not null default '',
  education text not null default '', skills text not null default '', languages text not null default '',
  review_status text not null default 'new' check (review_status in ('new','reviewing','approved','rejected')),
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
create policy "admins update resume review" on public.candidate_resumes for update to authenticated using (public.is_admin()) with check (public.is_admin());
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

-- Private, consent-based candidate introduction video (maximum 30 seconds, 50 MB).
create table public.candidate_videos (user_id uuid primary key references auth.users(id) on delete cascade, storage_path text not null unique, file_name text not null, content_type text not null check (content_type in ('video/mp4','video/webm')), size_bytes bigint not null check (size_bytes > 0 and size_bytes <= 52428800), consented_at timestamptz not null default now(), created_at timestamptz not null default now());
alter table public.candidate_videos enable row level security;
create policy "candidate video own or admin read" on public.candidate_videos for select to authenticated using (user_id=auth.uid() or public.is_admin());
create policy "candidates add own video" on public.candidate_videos for insert to authenticated with check (user_id=auth.uid());
create policy "candidates replace own video" on public.candidate_videos for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy "candidates remove own video" on public.candidate_videos for delete to authenticated using (user_id=auth.uid());
grant select,insert,update,delete on public.candidate_videos to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('candidate-videos','candidate-videos',false,52428800,array['video/mp4','video/webm']) on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create policy "candidate videos own or admin read" on storage.objects for select to authenticated using (bucket_id='candidate-videos' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));
create policy "candidates upload own videos" on storage.objects for insert to authenticated with check (bucket_id='candidate-videos' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "candidates replace own videos" on storage.objects for update to authenticated using (bucket_id='candidate-videos' and (storage.foldername(name))[1]=auth.uid()::text) with check (bucket_id='candidate-videos' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "candidates delete own videos" on storage.objects for delete to authenticated using (bucket_id='candidate-videos' and (storage.foldername(name))[1]=auth.uid()::text);
create or replace function public.protect_resume_review_status() returns trigger language plpgsql security definer set search_path=public as $$ begin if auth.uid()=new.user_id and (new.headline is distinct from old.headline or new.summary is distinct from old.summary or new.experience is distinct from old.experience or new.education is distinct from old.education or new.skills is distinct from old.skills or new.languages is distinct from old.languages) then new.review_status='new'; end if; if new.review_status is distinct from old.review_status and not public.is_admin() and not (auth.uid()=new.user_id and new.review_status='new') then raise exception 'Only administrators can set resume review status'; end if; return new; end $$;
create trigger candidate_resume_status_protection before update on public.candidate_resumes for each row execute function public.protect_resume_review_status();
create or replace function public.notify_admin_candidate_video() returns trigger language plpgsql security definer set search_path=public as $$ declare candidate_name text; begin select full_name into candidate_name from public.profiles where id=new.user_id; insert into public.admin_notifications(kind,user_id,resume_user_id,summary) values('resume',new.user_id,new.user_id,'Кандидат '||coalesce(candidate_name,'')||' загрузил видео-представление'); return new; end $$;
create trigger candidate_video_admin_notification after insert or update on public.candidate_videos for each row execute function public.notify_admin_candidate_video();

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

-- Per-account email and appearance preferences. Vacancy email notifications are opt-in.
create table public.user_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  vacancy_emails boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.user_settings enable row level security;
create policy "users manage own settings" on public.user_settings for all to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
grant select,insert,update on public.user_settings to authenticated;

-- Public applications can attach optional résumés; only MFA-protected admins can read them.
drop policy if exists "public submit applications without account" on public.applications;
create policy "public submit applications without account" on public.applications for insert to anon with check (
  user_id is null and status='new'
  and char_length(btrim(applicant_name)) between 2 and 120
  and char_length(btrim(contact_email)) between 5 and 254
  and btrim(contact_email) ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  and char_length(btrim(contact_phone)) between 7 and 24
  and (resume_path is null or (split_part(resume_path,'/',1)=id::text and resume_path ~ '\.(pdf|doc|docx)$'))
  and exists(select 1 from public.jobs j where j.id=applications.job_id and j.is_published)
);
revoke insert on public.applications from anon;
grant insert(id,job_id,applicant_name,contact_email,contact_phone,resume_path) on public.applications to anon;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('application-resumes','application-resumes',false,10485760,array['application/pdf','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
grant insert on storage.objects to anon;
drop policy if exists "public upload application resumes" on storage.objects;
create policy "public upload application resumes" on storage.objects for insert to anon with check (
  bucket_id='application-resumes'
  and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|doc|docx)$'
);
drop policy if exists "admins read application resumes" on storage.objects;
create policy "admins read application resumes" on storage.objects for select to authenticated using (bucket_id='application-resumes' and public.is_admin());


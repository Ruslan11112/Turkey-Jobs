-- Upgrade existing Turkey Jobs projects: private candidate introduction video.
create or replace function public.is_admin_role() returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.admin_users where user_id=auth.uid()); $$;
revoke all on function public.is_admin_role() from public;
grant execute on function public.is_admin_role() to anon,authenticated;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$ select coalesce(auth.jwt()->>'aal','')='aal2' and public.is_admin_role(); $$;
alter table public.candidate_resumes add column if not exists review_status text not null default 'new' check (review_status in ('new','reviewing','approved','rejected'));
drop policy if exists "admins update resume review" on public.candidate_resumes;
create policy "admins update resume review" on public.candidate_resumes for update to authenticated using (public.is_admin()) with check (public.is_admin());
create or replace function public.protect_resume_review_status() returns trigger language plpgsql security definer set search_path=public as $$ begin if new.review_status is distinct from old.review_status and not public.is_admin() then raise exception 'Only administrators can change resume review status'; end if; return new; end $$;
drop trigger if exists candidate_resume_status_protection on public.candidate_resumes;
create trigger candidate_resume_status_protection before update on public.candidate_resumes for each row execute function public.protect_resume_review_status();
create table if not exists public.candidate_videos (
  user_id uuid primary key references auth.users(id) on delete cascade,
  storage_path text not null unique,
  file_name text not null,
  content_type text not null check (content_type in ('video/mp4','video/webm')),
  size_bytes bigint not null check (size_bytes > 0 and size_bytes <= 52428800),
  consented_at timestamptz not null default now(), created_at timestamptz not null default now()
);
alter table public.candidate_videos enable row level security;
drop policy if exists "candidate video own or admin read" on public.candidate_videos;
drop policy if exists "candidates add own video" on public.candidate_videos;
drop policy if exists "candidates replace own video" on public.candidate_videos;
drop policy if exists "candidates remove own video" on public.candidate_videos;
create policy "candidate video own or admin read" on public.candidate_videos for select to authenticated using (user_id=auth.uid() or public.is_admin());
create policy "candidates add own video" on public.candidate_videos for insert to authenticated with check (user_id=auth.uid());
create policy "candidates replace own video" on public.candidate_videos for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy "candidates remove own video" on public.candidate_videos for delete to authenticated using (user_id=auth.uid());
grant select,insert,update,delete on public.candidate_videos to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('candidate-videos','candidate-videos',false,52428800,array['video/mp4','video/webm']) on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists "candidate videos own or admin read" on storage.objects;
drop policy if exists "candidates upload own videos" on storage.objects;
drop policy if exists "candidates replace own videos" on storage.objects;
drop policy if exists "candidates delete own videos" on storage.objects;
create policy "candidate videos own or admin read" on storage.objects for select to authenticated using (bucket_id='candidate-videos' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));
create policy "candidates upload own videos" on storage.objects for insert to authenticated with check (bucket_id='candidate-videos' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "candidates replace own videos" on storage.objects for update to authenticated using (bucket_id='candidate-videos' and (storage.foldername(name))[1]=auth.uid()::text) with check (bucket_id='candidate-videos' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "candidates delete own videos" on storage.objects for delete to authenticated using (bucket_id='candidate-videos' and (storage.foldername(name))[1]=auth.uid()::text);
create or replace function public.notify_admin_candidate_video() returns trigger language plpgsql security definer set search_path=public as $$ declare candidate_name text; begin select full_name into candidate_name from public.profiles where id=new.user_id; insert into public.admin_notifications(kind,user_id,resume_user_id,summary) values('resume',new.user_id,new.user_id,'Кандидат '||coalesce(candidate_name,'')||' загрузил видео-представление'); return new; end $$;
drop trigger if exists candidate_video_admin_notification on public.candidate_videos;
create trigger candidate_video_admin_notification after insert or update on public.candidate_videos for each row execute function public.notify_admin_candidate_video();

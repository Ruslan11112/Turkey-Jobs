-- Admin workspace, account preferences, published job notifications and the site owner's account.
alter table public.jobs add column if not exists source_url text not null default '';
create table if not exists public.user_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  vacancy_emails boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.user_settings enable row level security;
drop policy if exists "users manage own settings" on public.user_settings;
create policy "users manage own settings" on public.user_settings for all to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
grant select,insert,update on public.user_settings to authenticated;

create or replace function public.promote_turkey_jobs_owner() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if lower(coalesce(new.email,''))='rukhamrakulov@gmail.com' and new.email_confirmed_at is not null then
    insert into public.admin_users(user_id) values(new.id) on conflict(user_id) do nothing;
    update public.profiles set phone='+77073186480' where id=new.id;
  end if;
  return new;
end $$;
drop trigger if exists promote_turkey_jobs_owner on auth.users;
create trigger promote_turkey_jobs_owner after insert or update of email_confirmed_at on auth.users for each row execute function public.promote_turkey_jobs_owner();
insert into public.admin_users(user_id) select id from auth.users where lower(email)='rukhamrakulov@gmail.com' and email_confirmed_at is not null on conflict do nothing;
update public.profiles set phone='+77073186480' where lower(email)='rukhamrakulov@gmail.com';

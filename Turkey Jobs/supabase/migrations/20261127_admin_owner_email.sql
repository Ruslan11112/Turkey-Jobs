-- Use the new administrator email for future account provisioning.
-- Existing admin access is bound to auth.users.id and remains with the same account.
create or replace function public.promote_turkey_jobs_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if lower(coalesce(new.email, '')) = 'ruskhamrakulov@gmail.com'
     and new.email_confirmed_at is not null then
    insert into public.admin_users(user_id)
    values (new.id)
    on conflict (user_id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists promote_turkey_jobs_owner on auth.users;
create trigger promote_turkey_jobs_owner
  after insert or update of email, email_confirmed_at on auth.users
  for each row execute function public.promote_turkey_jobs_owner();

insert into public.admin_users(user_id)
select id
from auth.users
where lower(email) = 'ruskhamrakulov@gmail.com'
  and email_confirmed_at is not null
on conflict (user_id) do nothing;

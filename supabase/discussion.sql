-- ITNSA LAB: shared Discussion tab
-- Run once in Supabase Dashboard > SQL Editor.
create extension if not exists pgcrypto;

create or replace function public.itnsa_is_discussion_moderator()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role in ('admin', 'superadmin')
  );
$$;

create table if not exists public.discussion_topics (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  author_name text not null default 'Anggota',
  category text not null,
  title text not null check (char_length(trim(title)) between 5 and 150),
  body text not null check (char_length(trim(body)) between 1 and 10000),
  code text not null default '' check (char_length(code) <= 20000),
  status text not null default 'open' check (status in ('open','solved','locked','hidden')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.discussion_replies (
  id uuid primary key default gen_random_uuid(),
  topic_id uuid not null references public.discussion_topics(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  author_name text not null default 'Anggota',
  body text not null check (char_length(trim(body)) between 1 and 10000),
  code text not null default '' check (char_length(code) <= 20000),
  parent_id uuid references public.discussion_replies(id) on delete set null,
  is_solution boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.discussion_likes (
  topic_id uuid not null references public.discussion_topics(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (topic_id, user_id)
);

create table if not exists public.discussion_reports (
  id uuid primary key default gen_random_uuid(),
  topic_id uuid not null references public.discussion_topics(id) on delete cascade,
  reply_id uuid references public.discussion_replies(id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reporter_name text not null default 'Anggota',
  reason text not null check (char_length(trim(reason)) between 1 and 500),
  status text not null default 'baru' check (status in ('baru','selesai')),
  created_at timestamptz not null default now()
);

create index if not exists discussion_topics_created_idx on public.discussion_topics(created_at desc);
create index if not exists discussion_replies_topic_created_idx on public.discussion_replies(topic_id, created_at);
create index if not exists discussion_reports_status_created_idx on public.discussion_reports(status, created_at desc);

-- Author labels are assigned by the database, not trusted from browser input.
create or replace function public.itnsa_set_discussion_author()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  display_name text;
  target_user_id uuid;
begin
  if tg_table_name = 'discussion_reports' then
    target_user_id := new.reporter_id;
  else
    target_user_id := new.user_id;
  end if;

  select coalesce(nullif(trim(p.full_name), ''), split_part(coalesce(p.email, u.email, 'anggota'), '@', 1), 'Anggota')
    into display_name
  from auth.users u
  left join public.profiles p on p.id = u.id
  where u.id = target_user_id;

  if tg_table_name = 'discussion_reports' then
    new.reporter_name := coalesce(display_name, 'Anggota');
  else
    new.author_name := coalesce(display_name, 'Anggota');
  end if;
  return new;
end;
$$;

drop trigger if exists discussion_topics_author on public.discussion_topics;
create trigger discussion_topics_author before insert on public.discussion_topics
for each row execute function public.itnsa_set_discussion_author();

drop trigger if exists discussion_replies_author on public.discussion_replies;
create trigger discussion_replies_author before insert on public.discussion_replies
for each row execute function public.itnsa_set_discussion_author();

drop trigger if exists discussion_reports_author on public.discussion_reports;
create trigger discussion_reports_author before insert on public.discussion_reports
for each row execute function public.itnsa_set_discussion_author();


-- Protect moderation/solution fields even if a client bypasses the UI.
create or replace function public.itnsa_guard_discussion_topic()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.user_id <> auth.uid() or new.status <> 'open' then
      raise exception 'New topics must belong to the signed-in user and start open';
    end if;
  else
    if new.user_id is distinct from old.user_id or new.created_at is distinct from old.created_at then
      raise exception 'Topic ownership and creation time are immutable';
    end if;
    if new.status is distinct from old.status
       and not public.itnsa_is_discussion_moderator()
       and not (old.user_id = auth.uid() and new.status in ('open','solved')) then
      raise exception 'Only moderators can lock or hide topics';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists discussion_topics_guard on public.discussion_topics;
create trigger discussion_topics_guard before insert or update on public.discussion_topics
for each row execute function public.itnsa_guard_discussion_topic();

create or replace function public.itnsa_guard_discussion_reply()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.user_id <> auth.uid() or new.is_solution then
      raise exception 'Replies must belong to the signed-in user and cannot self-mark as solution';
    end if;
  else
    if new.user_id is distinct from old.user_id
       or new.topic_id is distinct from old.topic_id
       or new.created_at is distinct from old.created_at then
      raise exception 'Reply ownership, topic, and creation time are immutable';
    end if;
    if new.is_solution is distinct from old.is_solution
       and not public.itnsa_is_discussion_moderator()
       and not exists (select 1 from public.discussion_topics t where t.id = old.topic_id and t.user_id = auth.uid()) then
      raise exception 'Only the topic owner or a moderator can mark a solution';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists discussion_replies_guard on public.discussion_replies;
create trigger discussion_replies_guard before insert or update on public.discussion_replies
for each row execute function public.itnsa_guard_discussion_reply();

alter table public.discussion_topics enable row level security;
alter table public.discussion_replies enable row level security;
alter table public.discussion_likes enable row level security;
alter table public.discussion_reports enable row level security;

grant select, insert, update, delete on public.discussion_topics to authenticated;
grant select, insert, update, delete on public.discussion_replies to authenticated;
grant select, insert, delete on public.discussion_likes to authenticated;
grant select, insert, update on public.discussion_reports to authenticated;

drop policy if exists "Signed-in users read visible discussion topics" on public.discussion_topics;
create policy "Signed-in users read visible discussion topics"
on public.discussion_topics for select to authenticated
using (status <> 'hidden' or user_id = auth.uid() or public.itnsa_is_discussion_moderator());

drop policy if exists "Signed-in users create own discussion topics" on public.discussion_topics;
create policy "Signed-in users create own discussion topics"
on public.discussion_topics for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists "Owners and moderators update discussion topics" on public.discussion_topics;
create policy "Owners and moderators update discussion topics"
on public.discussion_topics for update to authenticated
using (user_id = auth.uid() or public.itnsa_is_discussion_moderator())
with check (user_id = auth.uid() or public.itnsa_is_discussion_moderator());

drop policy if exists "Owners and moderators delete discussion topics" on public.discussion_topics;
create policy "Owners and moderators delete discussion topics"
on public.discussion_topics for delete to authenticated
using (user_id = auth.uid() or public.itnsa_is_discussion_moderator());

drop policy if exists "Signed-in users read replies on visible topics" on public.discussion_replies;
create policy "Signed-in users read replies on visible topics"
on public.discussion_replies for select to authenticated
using (exists (select 1 from public.discussion_topics t where t.id = topic_id and (t.status <> 'hidden' or t.user_id = auth.uid() or public.itnsa_is_discussion_moderator())));

drop policy if exists "Signed-in users reply to open topics" on public.discussion_replies;
create policy "Signed-in users reply to open topics"
on public.discussion_replies for insert to authenticated
with check (
  user_id = auth.uid()
  and exists (select 1 from public.discussion_topics t where t.id = topic_id and t.status in ('open','solved'))
);

drop policy if exists "Owners and moderators update replies" on public.discussion_replies;
create policy "Owners and moderators update replies"
on public.discussion_replies for update to authenticated
using (user_id = auth.uid() or public.itnsa_is_discussion_moderator() or exists (select 1 from public.discussion_topics t where t.id = topic_id and t.user_id = auth.uid()))
with check (user_id = auth.uid() or public.itnsa_is_discussion_moderator() or exists (select 1 from public.discussion_topics t where t.id = topic_id and t.user_id = auth.uid()));

drop policy if exists "Owners and moderators delete replies" on public.discussion_replies;
create policy "Owners and moderators delete replies"
on public.discussion_replies for delete to authenticated
using (user_id = auth.uid() or public.itnsa_is_discussion_moderator() or exists (select 1 from public.discussion_topics t where t.id = topic_id and t.user_id = auth.uid()));

drop policy if exists "Signed-in users read likes" on public.discussion_likes;
create policy "Signed-in users read likes"
on public.discussion_likes for select to authenticated using (true);

drop policy if exists "Users manage own likes" on public.discussion_likes;
create policy "Users manage own likes"
on public.discussion_likes for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "Users remove own likes" on public.discussion_likes;
create policy "Users remove own likes"
on public.discussion_likes for delete to authenticated using (user_id = auth.uid());

drop policy if exists "Users create own reports" on public.discussion_reports;
create policy "Users create own reports"
on public.discussion_reports for insert to authenticated
with check (reporter_id = auth.uid());

drop policy if exists "Moderators read reports" on public.discussion_reports;
create policy "Moderators read reports"
on public.discussion_reports for select to authenticated
using (public.itnsa_is_discussion_moderator());

drop policy if exists "Moderators update reports" on public.discussion_reports;
create policy "Moderators update reports"
on public.discussion_reports for update to authenticated
using (public.itnsa_is_discussion_moderator())
with check (public.itnsa_is_discussion_moderator());

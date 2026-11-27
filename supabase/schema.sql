-- بيتنا — قاعدة البيانات (Supabase / Postgres)
-- الصقه كاملاً في: Supabase Dashboard → SQL Editor → New query → Run
-- آمن لإعادة التشغيل: كل الأوامر تستخدم if not exists / or replace.

-- ───────────── الجداول ─────────────
-- "household" هي المجموعة المخفية التي تجمع من دعوا بعضهم؛ لا تظهر في الواجهة.
create table if not exists public.households (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  name         text not null,
  email        text,
  color        text not null default 'blue',
  household_id uuid not null references public.households (id),
  created_at   timestamptz not null default now()
);
create index if not exists profiles_household_idx on public.profiles (household_id);

create table if not exists public.tags (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  name         text not null check (char_length(name) between 1 and 40),
  color        text not null default 'slate',
  icon         text not null default 'tag',
  created_at   timestamptz not null default now()
);
create index if not exists tags_household_idx on public.tags (household_id);

create table if not exists public.items (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  title        text not null check (char_length(title) between 1 and 200),
  tag_id       uuid references public.tags (id) on delete set null,
  prio         text not null default 'soon' check (prio in ('urgent', 'soon', 'later')),
  due          timestamptz,
  done         boolean not null default false,
  done_at      timestamptz,
  done_by      uuid references public.profiles (id) on delete set null,
  created_by   uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now()
);
create index if not exists items_household_idx on public.items (household_id, done);

-- المواعيد: نفس جدول الأغراض بنوع مختلف (kind = 'appt')، مع موقع اختياري ووقت تذكير قبل الموعد بالدقائق.
alter table public.items add column if not exists kind text not null default 'item';
alter table public.items add column if not exists location text;
alter table public.items add column if not exists remind_min integer;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'items_kind_check') then
    alter table public.items add constraint items_kind_check check (kind in ('item', 'appt'));
  end if;
end $$;

-- ───────────── دوال مساعدة ─────────────
-- مجموعة المستخدم الحالي. security definer حتى لا تدور سياسات RLS على نفسها.
create or replace function public.my_household()
returns uuid language sql stable security definer set search_path = public as $$
  select household_id from public.profiles where id = auth.uid()
$$;

-- رمز دعوة مثل BYT-7K4M2Q (بدون الحروف والأرقام المتشابهة) — نحو مليار احتمال.
create or replace function public.gen_invite_code()
returns text language plpgsql volatile security definer set search_path = public as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  c text;
begin
  loop
    c := 'BYT-';
    for i in 1..6 loop
      c := c || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.households where code = c);
  end loop;
  return c;
end $$;

-- عند إنشاء حساب: مجموعة خاصة + ملف شخصي + التاقات الافتراضية.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare h uuid;
begin
  insert into public.households (code) values (public.gen_invite_code()) returning id into h;
  insert into public.profiles (id, name, email, household_id)
  values (new.id,
          coalesce(nullif(trim(new.raw_user_meta_data ->> 'name'), ''), split_part(new.email, '@', 1)),
          new.email, h);
  insert into public.tags (household_id, name, color, icon) values
    (h, 'البقالة', 'green', 'cart'),
    (h, 'صيانة البيت', 'blue', 'wrench'),
    (h, 'صيانة السيارة', 'amber', 'car');
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- الانضمام برمز دعوة: ينقل أغراضك وتاقاتك إلى مجموعة صاحب الرمز (التاقات المتطابقة بالاسم تُدمج).
create or replace function public.join_household(p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me     uuid := auth.uid();
  old    uuid;
  target uuid;
begin
  if me is null then raise exception 'not_authenticated'; end if;
  select id into target from public.households where code = upper(trim(p_code));
  if target is null then raise exception 'invalid_code'; end if;
  select household_id into old from public.profiles where id = me;
  if old = target then return target; end if;

  update public.items i set tag_id = t2.id
    from public.tags t1
    join public.tags t2 on t2.household_id = target and t2.name = t1.name
   where i.tag_id = t1.id and t1.household_id = old;
  delete from public.tags t1
   where t1.household_id = old
     and exists (select 1 from public.tags t2 where t2.household_id = target and t2.name = t1.name);
  update public.tags  set household_id = target where household_id = old;
  update public.items set household_id = target where household_id = old;
  update public.profiles set household_id = target where id = me;
  delete from public.households h
   where h.id = old and not exists (select 1 from public.profiles p where p.household_id = old);
  return target;
end $$;

-- الخروج من المشاركة: مجموعة جديدة فارغة لك، وأغراض المجموعة تبقى عند الباقين.
create or replace function public.leave_household()
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  h  uuid;
begin
  if me is null then raise exception 'not_authenticated'; end if;
  insert into public.households (code) values (public.gen_invite_code()) returning id into h;
  update public.profiles set household_id = h where id = me;
  insert into public.tags (household_id, name, color, icon) values
    (h, 'البقالة', 'green', 'cart'),
    (h, 'صيانة البيت', 'blue', 'wrench'),
    (h, 'صيانة السيارة', 'amber', 'car');
  return h;
end $$;

revoke all on function public.gen_invite_code() from public, anon, authenticated;
revoke all on function public.join_household(text) from public, anon;
revoke all on function public.leave_household() from public, anon;
grant execute on function public.my_household() to authenticated;
grant execute on function public.join_household(text) to authenticated;
grant execute on function public.leave_household() to authenticated;

-- صلاحيات الوصول عبر الـ Data API للمستخدم المسجّل فقط (لا شيء للزائر anon).
revoke all on public.households, public.profiles, public.tags, public.items from anon;
grant select on public.households to authenticated;
grant select, update (name, color) on public.profiles to authenticated;
grant select, insert, update, delete on public.tags, public.items to authenticated;

-- ───────────── الصلاحيات (RLS) ─────────────
-- كل شخص يرى ويعدّل بيانات مجموعته فقط.
alter table public.households enable row level security;
alter table public.profiles   enable row level security;
alter table public.tags       enable row level security;
alter table public.items      enable row level security;

drop policy if exists households_select on public.households;
create policy households_select on public.households
  for select to authenticated using (id = public.my_household());

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated using (household_id = public.my_household());

-- تعديل الاسم واللون فقط؛ تغيير المجموعة يمر عبر join_household / leave_household.
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid() and household_id = public.my_household());

drop policy if exists tags_all on public.tags;
create policy tags_all on public.tags
  for all to authenticated
  using (household_id = public.my_household())
  with check (household_id = public.my_household());

drop policy if exists items_all on public.items;
create policy items_all on public.items
  for all to authenticated
  using (household_id = public.my_household())
  with check (household_id = public.my_household());

-- ───────────── المزامنة اللحظية ─────────────
do $$
declare t text;
begin
  foreach t in array array['items', 'tags', 'profiles'] loop
    if not exists (select 1 from pg_publication_tables
                    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- Keep-awake: free projects pause after a quiet week. One tiny request a day through the project's own API.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
create or replace function public.keep_awake() returns int language sql stable set search_path = '' as $f$ select 1 $f$;
grant execute on function public.keep_awake() to anon, authenticated;
select cron.schedule('baytna-keep-awake', '17 6 * * *', $job$ select net.http_get(url := 'https://xejnfjagypsjpucgccpq.supabase.co/rest/v1/rpc/keep_awake', headers := '{"apikey":"sb_publishable_68Jic6MZaKlgMsVfnzK-3w_5pNMte8G"}'::jsonb) $job$);
-- Redesign release: monthly bills, and an icon and colour per category. Safe to run more than once.

create table if not exists public.bills (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  title        text not null check (char_length(title) between 1 and 120),
  amount       numeric(12, 2) check (amount is null or amount >= 0),
  icon         text not null default 'receipt',
  color        text not null default 'teal',
  paid         boolean not null default false,
  paid_by      uuid references public.profiles (id) on delete set null,
  paid_at      timestamptz,
  created_at   timestamptz not null default now()
);
create index if not exists bills_household_idx on public.bills (household_id);

revoke all on public.bills from anon;
grant select, insert, update, delete on public.bills to authenticated;
alter table public.bills enable row level security;
drop policy if exists bills_all on public.bills;
create policy bills_all on public.bills
  for all to authenticated
  using (household_id = public.my_household())
  with check (household_id = public.my_household());

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'bills') then
    alter publication supabase_realtime add table public.bills;
  end if;
end $$;

-- Joining someone's household now brings your bills along with your items.
create or replace function public.join_household(p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me     uuid := auth.uid();
  old    uuid;
  target uuid;
begin
  if me is null then raise exception 'not_authenticated'; end if;
  select id into target from public.households where code = upper(trim(p_code));
  if target is null then raise exception 'invalid_code'; end if;
  select household_id into old from public.profiles where id = me;
  if old = target then return target; end if;

  update public.items i set tag_id = t2.id
    from public.tags t1
    join public.tags t2 on t2.household_id = target and t2.name = t1.name
   where i.tag_id = t1.id and t1.household_id = old;
  delete from public.tags t1
   where t1.household_id = old
     and exists (select 1 from public.tags t2 where t2.household_id = target and t2.name = t1.name);
  update public.tags  set household_id = target where household_id = old;
  update public.items set household_id = target where household_id = old;
  update public.bills set household_id = target where household_id = old;
  update public.profiles set household_id = target where id = me;
  delete from public.households h
   where h.id = old and not exists (select 1 from public.profiles p where p.household_id = old);
  return target;
end $$;
revoke all on function public.join_household(text) from public, anon;
grant execute on function public.join_household(text) to authenticated;

-- The paid marks clear on the 20th of every month, at 00:05 Riyadh time (21:05 UTC on the 19th).
select cron.schedule('baytna-bills-reset', '5 21 19 * *',
  $job$ update public.bills set paid = false, paid_by = null, paid_at = null where paid $job$);

-- Categories: a fitting icon and colour for the ones that already exist.
update public.tags set icon = 'house', color = 'amber' where icon = 'wrench';
update public.tags set color = 'blue' where icon = 'car';
update public.tags set icon = 'flower', color = 'rose' where icon = 'tag' and name = 'البنات';

-- The remaining two categories get an icon too.
update public.tags set icon = 'pill', color = 'red' where icon = 'tag' and name = 'الصحة';
update public.tags set icon = 'drop', color = 'teal' where icon = 'tag' and name = 'منظفات وعناية';

-- Leaving a shared household. You get a household of your own again; the people you leave keep everything as it was.
-- p_keep = 'all'  : you take a copy of every item, appointment and bill.
-- p_keep = 'mine' : you take a copy of only what you added yourself (and the bills, which belong to nobody in particular).
create or replace function public.leave_household(p_keep text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me   uuid := auth.uid();
  old  uuid;
  h    uuid;
  t    record;
  nid  uuid;
  everything boolean := coalesce(p_keep, 'all') <> 'mine';
begin
  if me is null then raise exception 'not_authenticated'; end if;
  select household_id into old from public.profiles where id = me;
  if (select count(*) from public.profiles where household_id = old) < 2 then raise exception 'alone'; end if;

  insert into public.households (code) values (public.gen_invite_code()) returning id into h;

  -- Categories come along, and each copied item points at its copied category.
  for t in select * from public.tags where household_id = old order by created_at loop
    insert into public.tags (household_id, name, color, icon, created_at) values (h, t.name, t.color, t.icon, t.created_at) returning id into nid;
    insert into public.items (household_id, title, tag_id, prio, due, done, done_at, done_by, created_by, created_at, kind, location, remind_min)
      select h, i.title, nid, i.prio, i.due, i.done, i.done_at,
             case when i.done_by = me then me end, case when i.created_by = me then me end, i.created_at, i.kind, i.location, i.remind_min
        from public.items i
       where i.household_id = old and i.tag_id = t.id and (everything or i.created_by = me);
  end loop;
  insert into public.items (household_id, title, tag_id, prio, due, done, done_at, done_by, created_by, created_at, kind, location, remind_min)
    select h, i.title, null, i.prio, i.due, i.done, i.done_at,
           case when i.done_by = me then me end, case when i.created_by = me then me end, i.created_at, i.kind, i.location, i.remind_min
      from public.items i
     where i.household_id = old and i.tag_id is null and (everything or i.created_by = me);
  insert into public.bills (household_id, title, amount, icon, color, paid, paid_by, paid_at, created_at)
    select h, b.title, b.amount, b.icon, b.color, b.paid, case when b.paid_by = me then me end, b.paid_at, b.created_at
      from public.bills b where b.household_id = old;

  update public.profiles set household_id = h where id = me;
  return h;
end $$;
revoke all on function public.leave_household(text) from public, anon;
grant execute on function public.leave_household(text) to authenticated;

-- ───────────── Places (1.1.3): spots to visit, added from a Google Maps link. Safe to run more than once. ─────────────
create table if not exists public.places (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  name         text not null check (char_length(name) between 1 and 200),
  kind         text,
  area         text,
  city         text,
  photo        text,
  url          text,
  lat          double precision,
  lng          double precision,
  place_id     text,
  fid          text,
  rating       real,
  reviews      integer,
  visited      boolean not null default false,
  note         text check (char_length(note) <= 500),
  created_by   uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now()
);
-- 1.1.5: a short note on a place (long-press the card).
alter table public.places add column if not exists note text check (char_length(note) <= 500);
create index if not exists places_household_idx on public.places (household_id);

revoke all on public.places from anon;
grant select, insert, update, delete on public.places to authenticated;
alter table public.places enable row level security;
drop policy if exists places_all on public.places;
create policy places_all on public.places
  for all to authenticated
  using (household_id = public.my_household())
  with check (household_id = public.my_household());

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'places') then
    alter publication supabase_realtime add table public.places;
  end if;
end $$;

-- Joining someone's household brings your bills and places along with your items.
create or replace function public.join_household(p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me     uuid := auth.uid();
  old    uuid;
  target uuid;
begin
  if me is null then raise exception 'not_authenticated'; end if;
  select id into target from public.households where code = upper(trim(p_code));
  if target is null then raise exception 'invalid_code'; end if;
  select household_id into old from public.profiles where id = me;
  if old = target then return target; end if;

  update public.items i set tag_id = t2.id
    from public.tags t1
    join public.tags t2 on t2.household_id = target and t2.name = t1.name
   where i.tag_id = t1.id and t1.household_id = old;
  delete from public.tags t1
   where t1.household_id = old
     and exists (select 1 from public.tags t2 where t2.household_id = target and t2.name = t1.name);
  update public.tags  set household_id = target where household_id = old;
  update public.items set household_id = target where household_id = old;
  update public.bills set household_id = target where household_id = old;
  update public.places set household_id = target where household_id = old;
  update public.profiles set household_id = target where id = me;
  delete from public.households h
   where h.id = old and not exists (select 1 from public.profiles p where p.household_id = old);
  return target;
end $$;
revoke all on function public.join_household(text) from public, anon;
grant execute on function public.join_household(text) to authenticated;

-- Leaving a shared household (now with places: all of them, or only the ones you added). You get a household of your own again; the people you leave keep everything as it was.
-- p_keep = 'all'  : you take a copy of every item, appointment and bill.
-- p_keep = 'mine' : you take a copy of only what you added yourself (and the bills, which belong to nobody in particular).
create or replace function public.leave_household(p_keep text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me   uuid := auth.uid();
  old  uuid;
  h    uuid;
  t    record;
  nid  uuid;
  everything boolean := coalesce(p_keep, 'all') <> 'mine';
begin
  if me is null then raise exception 'not_authenticated'; end if;
  select household_id into old from public.profiles where id = me;
  if (select count(*) from public.profiles where household_id = old) < 2 then raise exception 'alone'; end if;

  insert into public.households (code) values (public.gen_invite_code()) returning id into h;

  -- Categories come along, and each copied item points at its copied category.
  for t in select * from public.tags where household_id = old order by created_at loop
    insert into public.tags (household_id, name, color, icon, created_at) values (h, t.name, t.color, t.icon, t.created_at) returning id into nid;
    insert into public.items (household_id, title, tag_id, prio, due, done, done_at, done_by, created_by, created_at, kind, location, remind_min)
      select h, i.title, nid, i.prio, i.due, i.done, i.done_at,
             case when i.done_by = me then me end, case when i.created_by = me then me end, i.created_at, i.kind, i.location, i.remind_min
        from public.items i
       where i.household_id = old and i.tag_id = t.id and (everything or i.created_by = me);
  end loop;
  insert into public.items (household_id, title, tag_id, prio, due, done, done_at, done_by, created_by, created_at, kind, location, remind_min)
    select h, i.title, null, i.prio, i.due, i.done, i.done_at,
           case when i.done_by = me then me end, case when i.created_by = me then me end, i.created_at, i.kind, i.location, i.remind_min
      from public.items i
     where i.household_id = old and i.tag_id is null and (everything or i.created_by = me);
  insert into public.bills (household_id, title, amount, icon, color, paid, paid_by, paid_at, created_at)
    select h, b.title, b.amount, b.icon, b.color, b.paid, case when b.paid_by = me then me end, b.paid_at, b.created_at
      from public.bills b where b.household_id = old;
  insert into public.places (household_id, name, kind, area, city, photo, url, lat, lng, place_id, fid, rating, reviews, visited, note, created_by, created_at)
    select h, p.name, p.kind, p.area, p.city, p.photo, p.url, p.lat, p.lng, p.place_id, p.fid, p.rating, p.reviews, p.visited, p.note,
           case when p.created_by = me then me end, p.created_at
      from public.places p where p.household_id = old and (everything or p.created_by = me);

  update public.profiles set household_id = h where id = me;
  return h;
end $$;
revoke all on function public.leave_household(text) from public, anon;
grant execute on function public.leave_household(text) to authenticated;

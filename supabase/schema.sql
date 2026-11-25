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

-- Contacts by email, groups, shared lend/borrow visibility
-- Run after existing migrations

-- Preferred currency on profile (no hardcoded symbols in app)
alter table public.profiles
  add column if not exists preferred_currency text not null default 'USD';

comment on column public.profiles.preferred_currency is 'ISO 4217 code for formatting amounts in the app.';

-- Invitations: user A invites by email; recipient sees when JWT email matches or after sync
create table if not exists public.contact_invitations (
  id uuid primary key default gen_random_uuid(),
  from_user_id uuid not null references public.profiles(id) on delete cascade,
  to_email text not null,
  to_user_id uuid references public.profiles(id) on delete set null,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected', 'cancelled')),
  created_at timestamptz not null default now()
);

create index if not exists contact_invitations_from_idx on public.contact_invitations (from_user_id);
create index if not exists contact_invitations_to_email_idx on public.contact_invitations (lower(trim(to_email)));
create index if not exists contact_invitations_to_user_idx on public.contact_invitations (to_user_id);

create unique index if not exists contact_inv_one_pending_per_pair
  on public.contact_invitations (from_user_id, lower(trim(to_email)))
  where status = 'pending';

-- Mutual connection after acceptance
create table if not exists public.user_connections (
  id uuid primary key default gen_random_uuid(),
  user_low uuid not null references public.profiles(id) on delete cascade,
  user_high uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_low, user_high),
  check (user_low < user_high)
);

create index if not exists user_connections_low_idx on public.user_connections (user_low);
create index if not exists user_connections_high_idx on public.user_connections (user_high);

-- Groups for shared expenses / splits
create table if not exists public.expense_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.expense_group_members (
  group_id uuid not null references public.expense_groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create index if not exists expense_group_members_user_idx on public.expense_group_members (user_id);

-- Lend/borrow: optional linked user + group
alter table public.lend_borrow_entries
  add column if not exists counterparty_user_id uuid references public.profiles(id) on delete set null,
  add column if not exists group_id uuid references public.expense_groups(id) on delete set null;

create index if not exists lend_borrow_counterparty_idx on public.lend_borrow_entries (counterparty_user_id);
create index if not exists lend_borrow_group_idx on public.lend_borrow_entries (group_id);

-- RLS
alter table public.contact_invitations enable row level security;
alter table public.user_connections enable row level security;
alter table public.expense_groups enable row level security;
alter table public.expense_group_members enable row level security;

drop policy if exists "inv_select" on public.contact_invitations;
create policy "inv_select" on public.contact_invitations for select using (
  from_user_id = auth.uid()
  or to_user_id = auth.uid()
  or lower(trim(to_email)) = lower(trim(coalesce(auth.jwt() ->> 'email', '')))
);

drop policy if exists "inv_insert" on public.contact_invitations;
create policy "inv_insert" on public.contact_invitations for insert with check (from_user_id = auth.uid());

drop policy if exists "inv_update" on public.contact_invitations;
create policy "inv_update" on public.contact_invitations for update using (
  from_user_id = auth.uid() or to_user_id = auth.uid()
);

drop policy if exists "inv_delete" on public.contact_invitations;
create policy "inv_delete" on public.contact_invitations for delete using (from_user_id = auth.uid());

drop policy if exists "uc_select" on public.user_connections;
create policy "uc_select" on public.user_connections for select using (
  auth.uid() = user_low or auth.uid() = user_high
);

-- Clients cannot insert connections directly; only accept_contact_invitation (security definer) does
drop policy if exists "uc_insert" on public.user_connections;
create policy "uc_insert" on public.user_connections for insert with check (false);

drop policy if exists "eg_select" on public.expense_groups;
create policy "eg_select" on public.expense_groups for select using (
  exists (
    select 1 from public.expense_group_members m
    where m.group_id = expense_groups.id and m.user_id = auth.uid()
  )
);

drop policy if exists "eg_insert" on public.expense_groups;
create policy "eg_insert" on public.expense_groups for insert with check (created_by = auth.uid());

drop policy if exists "eg_update" on public.expense_groups;
create policy "eg_update" on public.expense_groups for update using (created_by = auth.uid());

drop policy if exists "eg_delete" on public.expense_groups;
create policy "eg_delete" on public.expense_groups for delete using (created_by = auth.uid());

drop policy if exists "egm_select" on public.expense_group_members;
create policy "egm_select" on public.expense_group_members for select using (
  exists (
    select 1 from public.expense_group_members m
    where m.group_id = expense_group_members.group_id and m.user_id = auth.uid()
  )
);

drop policy if exists "egm_insert" on public.expense_group_members;
create policy "egm_insert" on public.expense_group_members for insert with check (
  exists (
    select 1 from public.expense_groups g
    where g.id = group_id and g.created_by = auth.uid()
  )
);

drop policy if exists "egm_delete" on public.expense_group_members;
create policy "egm_delete" on public.expense_group_members for delete using (
  exists (
    select 1 from public.expense_groups g
    where g.id = group_id and g.created_by = auth.uid()
  )
);

-- Replace lend/borrow policies for shared visibility
drop policy if exists "Users can manage own lend_borrow" on public.lend_borrow_entries;

drop policy if exists "lb_select" on public.lend_borrow_entries;
create policy "lb_select" on public.lend_borrow_entries for select using (
  auth.uid() = user_id or auth.uid() = counterparty_user_id
);

drop policy if exists "lb_insert" on public.lend_borrow_entries;
create policy "lb_insert" on public.lend_borrow_entries for insert with check (auth.uid() = user_id);

drop policy if exists "lb_update" on public.lend_borrow_entries;
create policy "lb_update" on public.lend_borrow_entries for update using (
  auth.uid() = user_id or auth.uid() = counterparty_user_id
);

drop policy if exists "lb_delete" on public.lend_borrow_entries;
create policy "lb_delete" on public.lend_borrow_entries for delete using (auth.uid() = user_id);

-- Link pending invitations to recipient user id when they log in (email match)
create or replace function public.sync_invitation_recipient()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  em text;
begin
  select lower(trim(email::text)) into em from auth.users where id = auth.uid();
  if em is null or em = '' then
    return;
  end if;
  update public.contact_invitations
  set to_user_id = auth.uid()
  where lower(trim(to_email)) = em
    and to_user_id is null
    and status = 'pending';
end;
$$;

grant execute on function public.sync_invitation_recipient() to authenticated;

-- Invite by email (sets to_user_id if that email already has an account)
create or replace function public.invite_contact_by_email(p_email text)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  norm text;
  target uuid;
  new_id uuid;
begin
  norm := lower(trim(p_email));
  if norm = '' then
    raise exception 'Invalid email';
  end if;
  if exists (
    select 1 from auth.users u
    where u.id = auth.uid() and lower(trim(u.email::text)) = norm
  ) then
    raise exception 'Cannot invite yourself';
  end if;

  select id into target from auth.users where lower(trim(email::text)) = norm limit 1;

  insert into public.contact_invitations (from_user_id, to_email, to_user_id, status)
  values (auth.uid(), norm, target, 'pending')
  returning id into new_id;

  return new_id;
exception
  when unique_violation then
    select ci.id into new_id
    from public.contact_invitations ci
    where ci.from_user_id = auth.uid()
      and lower(trim(ci.to_email)) = norm
      and ci.status = 'pending'
    limit 1;
    if new_id is null then
      raise;
    end if;
    return new_id;
end;
$$;

grant execute on function public.invite_contact_by_email(text) to authenticated;

-- Accept invitation and create mutual connection
create or replace function public.accept_contact_invitation(p_invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  inv record;
  low_id uuid;
  high_id uuid;
begin
  select * into inv from public.contact_invitations where id = p_invitation_id for update;
  if not found then
    raise exception 'Invitation not found';
  end if;
  if inv.to_user_id is distinct from auth.uid() then
    raise exception 'Not authorized to accept this invitation';
  end if;
  if inv.status <> 'pending' then
    raise exception 'Invitation is not pending';
  end if;

  low_id := least(inv.from_user_id, inv.to_user_id);
  high_id := greatest(inv.from_user_id, inv.to_user_id);

  insert into public.user_connections (user_low, user_high)
  values (low_id, high_id)
  on conflict (user_low, user_high) do nothing;

  update public.contact_invitations
  set status = 'accepted'
  where id = p_invitation_id;
end;
$$;

grant execute on function public.accept_contact_invitation(uuid) to authenticated;

create or replace function public.reject_contact_invitation(p_invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  inv record;
begin
  select * into inv from public.contact_invitations where id = p_invitation_id for update;
  if not found then
    raise exception 'Invitation not found';
  end if;
  if inv.to_user_id is distinct from auth.uid() and inv.from_user_id is distinct from auth.uid() then
    raise exception 'Not authorized';
  end if;
  if inv.status <> 'pending' then
    return;
  end if;
  update public.contact_invitations set status = 'rejected' where id = p_invitation_id;
end;
$$;

grant execute on function public.reject_contact_invitation(uuid) to authenticated;

-- Insert connection row (only via accept); allow service to skip - we use accept function only

comment on table public.contact_invitations is 'Email-based contact invites; both users see shared lend/borrow after accept.';
comment on table public.user_connections is 'Accepted mutual contacts.';
comment on table public.expense_groups is 'User-created groups; members share group-scoped context.';
comment on column public.lend_borrow_entries.counterparty_user_id is 'When set, the other party can see and settle this entry.';

-- Let users read display names of connected contacts (for picker UI)
drop policy if exists "profiles_select_connections" on public.profiles;
create policy "profiles_select_connections" on public.profiles for select using (
  exists (
    select 1 from public.user_connections c
    where (c.user_low = auth.uid() and c.user_high = profiles.id)
       or (c.user_high = auth.uid() and c.user_low = profiles.id)
  )
);

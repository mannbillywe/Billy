-- Financial accounts for balance tracking and future net worth.

create table if not exists public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  type text not null check (type in ('checking','savings','credit_card','cash','investment','loan','other')),
  institution text,
  currency text not null default 'INR',
  current_balance numeric(14,2) not null default 0,
  is_asset boolean not null default true,
  is_active boolean not null default true,
  is_linked boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index accounts_user_idx on public.accounts(user_id);

alter table public.accounts enable row level security;
create policy "accounts_select" on public.accounts for select using (auth.uid() = user_id);
create policy "accounts_insert" on public.accounts for insert with check (auth.uid() = user_id);
create policy "accounts_update" on public.accounts for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "accounts_delete" on public.accounts for delete using (auth.uid() = user_id);

create trigger accounts_touch_updated_at
  before update on public.accounts
  for each row execute function set_invoice_updated_at();

-- Row Level Security (RLS) - Billy
-- Run after initial_schema.sql

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.documents enable row level security;
alter table public.lend_borrow_entries enable row level security;
alter table public.splits enable row level security;
alter table public.split_participants enable row level security;
alter table public.connected_apps enable row level security;
alter table public.export_history enable row level security;

-- Profiles
create policy "Users can view own profile" on public.profiles for select using (auth.uid() = id);
create policy "Users can update own profile" on public.profiles for update using (auth.uid() = id);

-- Categories (own + default categories with user_id null)
create policy "Users can select categories" on public.categories for select using (auth.uid() = user_id or user_id is null);
create policy "Users can insert own categories" on public.categories for insert with check (auth.uid() = user_id);
create policy "Users can update own categories" on public.categories for update using (auth.uid() = user_id);
create policy "Users can delete own categories" on public.categories for delete using (auth.uid() = user_id);

-- Documents
create policy "Users can manage own documents" on public.documents for all using (auth.uid() = user_id);

-- Lend/Borrow
create policy "Users can manage own lend_borrow" on public.lend_borrow_entries for all using (auth.uid() = user_id);

-- Splits
create policy "Users can manage own splits" on public.splits for all using (auth.uid() = user_id);
create policy "Users can manage own split participants" on public.split_participants for all using (
  exists (select 1 from public.splits s where s.id = split_id and s.user_id = auth.uid())
);

-- Connected apps
create policy "Users can manage own connected apps" on public.connected_apps for all using (auth.uid() = user_id);

-- Export history
create policy "Users can manage own export history" on public.export_history for all using (auth.uid() = user_id);

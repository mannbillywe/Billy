-- Billy AI Financial OS - Initial Schema
-- Run this in Supabase SQL Editor: Dashboard > SQL Editor > New Query

-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- Profiles (extends auth.users)
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  trust_score decimal(3,2) default 5.0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Categories (user-specific or default)
create table public.categories (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references public.profiles(id) on delete cascade,
  name text not null,
  icon text,
  color text,
  is_default boolean default false,
  created_at timestamptz default now()
);

-- Documents (invoices + receipts)
create table public.documents (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null check (type in ('invoice', 'receipt')),
  vendor_name text,
  amount decimal(12,2) not null default 0,
  currency text default 'INR',
  tax_amount decimal(12,2) default 0,
  date date not null,
  category_id uuid references public.categories(id) on delete set null,
  description text,
  payment_method text,
  status text default 'saved',
  image_url text,
  extracted_data jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index documents_user_id_idx on public.documents(user_id);
create index documents_date_idx on public.documents(date desc);
create index documents_user_date_idx on public.documents(user_id, date desc);

-- Lend/Borrow entries
create table public.lend_borrow_entries (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  counterparty_name text not null,
  amount decimal(12,2) not null,
  type text not null check (type in ('lent', 'borrowed')),
  status text default 'pending' check (status in ('pending', 'settled')),
  due_date date,
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index lend_borrow_user_id_idx on public.lend_borrow_entries(user_id);

-- Splits
create table public.splits (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text,
  total_amount decimal(12,2) not null,
  image_url text,
  created_at timestamptz default now()
);

create table public.split_participants (
  id uuid primary key default uuid_generate_v4(),
  split_id uuid not null references public.splits(id) on delete cascade,
  name text not null,
  amount_owed decimal(12,2) not null,
  status text default 'pending' check (status in ('pending', 'paid')),
  created_at timestamptz default now()
);

create index split_participants_split_id_idx on public.split_participants(split_id);

-- Connected apps
create table public.connected_apps (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  app_name text not null,
  status text default 'disconnected' check (status in ('connected', 'disconnected')),
  metadata jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(user_id, app_name)
);

create index connected_apps_user_id_idx on public.connected_apps(user_id);

-- Export history
create table public.export_history (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  format text not null check (format in ('pdf', 'csv')),
  date_range_start date not null,
  date_range_end date not null,
  filters jsonb,
  file_url text,
  created_at timestamptz default now()
);

create index export_history_user_id_idx on public.export_history(user_id);

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    new.raw_user_meta_data->>'avatar_url'
  );
  return new;
end;
$$ language plpgsql security definer;

create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

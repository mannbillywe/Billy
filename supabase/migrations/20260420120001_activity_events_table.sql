-- Chronological audit trail / activity feed for all financial actions.

create table if not exists public.activity_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  event_type text not null check (event_type in (
    'transaction_created','transaction_updated','transaction_voided','transaction_disputed',
    'group_expense_created','group_expense_updated','group_expense_deleted',
    'settlement_created','settlement_confirmed','settlement_rejected',
    'lend_created','borrow_created','lend_settled','borrow_settled',
    'group_member_added','group_member_removed',
    'budget_created','budget_exceeded',
    'recurring_detected','recurring_due',
    'dispute_opened','dispute_resolved',
    'document_scanned','statement_imported'
  )),
  actor_user_id uuid not null references public.profiles(id),
  target_user_id uuid references public.profiles(id),
  group_id uuid references public.expense_groups(id),
  transaction_id uuid references public.transactions(id) on delete set null,
  entity_type text,
  entity_id uuid,
  summary text not null,
  details jsonb,
  previous_state jsonb,
  visibility text not null default 'private' check (visibility in ('private','group','public')),
  created_at timestamptz not null default now()
);

create index activity_events_user_idx on public.activity_events(user_id, created_at desc);
create index activity_events_group_idx on public.activity_events(group_id, created_at desc) where group_id is not null;
create index activity_events_entity_idx on public.activity_events(entity_type, entity_id);

alter table public.activity_events enable row level security;
create policy "ae_select" on public.activity_events for select
  using (auth.uid() = user_id or auth.uid() = actor_user_id or auth.uid() = target_user_id);
create policy "ae_insert" on public.activity_events for insert with check (auth.uid() = actor_user_id);

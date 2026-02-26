create table if not exists gateway_events (
  id bigserial primary key,
  session_id uuid,
  agent_id text,
  event_type text not null,
  payload jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_gateway_events_session on gateway_events(session_id);
create index if not exists idx_gateway_events_agent on gateway_events(agent_id);
create index if not exists idx_gateway_events_type on gateway_events(event_type);
create index if not exists idx_gateway_events_created on gateway_events(created_at);

-- 36WAYS Gestão · instalação da base de dados
-- Corre este ficheiro UMA vez no Supabase: SQL Editor → New query → colar → Run.

-- 1) Tabela única: cada registo (produto, venda, despesa, evento, configuração) é um JSON.
create table if not exists public.docs (
  col        text        not null,          -- produtos | vendas | despesas | eventos | config
  id         text        not null,
  data       jsonb       not null,
  updated_at timestamptz not null default now(),
  updated_by text,
  primary key (col, id)
);

create or replace function public.docs_touch() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists docs_touch on public.docs;
create trigger docs_touch before insert or update on public.docs
  for each row execute function public.docs_touch();

-- 2) Lista de sócios: só estes emails conseguem ler e gravar.
create table if not exists public.membros (email text primary key);

-- >>> MUDA AQUI para os emails das contas que vão criar no Supabase (minúsculas) <<<
insert into public.membros (email) values
  ('silva.goncalo915@gmail.com'),
  ('rafa.andre.a.silva@gmail.com'),
  ('system.faliure16@gmail.com')
on conflict do nothing;

-- 3) Regras de acesso (Row Level Security)
alter table public.docs    enable row level security;
alter table public.membros enable row level security;

create or replace function public.e_membro() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.membros where email = lower(auth.jwt() ->> 'email'));
$$;

drop policy if exists "socios leem"     on public.docs;
drop policy if exists "socios criam"    on public.docs;
drop policy if exists "socios alteram"  on public.docs;
drop policy if exists "socios apagam"   on public.docs;
drop policy if exists "ver o proprio"   on public.membros;

create policy "socios leem"    on public.docs for select to authenticated using (public.e_membro());
create policy "socios criam"   on public.docs for insert to authenticated with check (public.e_membro());
create policy "socios alteram" on public.docs for update to authenticated using (public.e_membro()) with check (public.e_membro());
create policy "socios apagam"  on public.docs for delete to authenticated using (public.e_membro());
create policy "ver o proprio"  on public.membros for select to authenticated using (email = lower(auth.jwt() ->> 'email'));

-- 4) Tempo real: quando um sócio grava, os outros veem logo.
alter table public.docs replica identity full;
do $$
begin
  alter publication supabase_realtime add table public.docs;
exception when duplicate_object then null;
end $$;

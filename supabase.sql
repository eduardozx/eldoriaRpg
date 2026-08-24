-- Eldoria · Contas persistentes (Supabase)
-- Cole e execute este script no SQL Editor do seu projeto Supabase.

create table if not exists public.accounts (
  name text primary key,
  password_hash text not null,
  salt text not null,
  level integer not null default 1,
  experience integer not null default 0,
  max_hp integer not null default 100,
  base_damage integer not null default 8,
  gold integer not null default 0,
  equipped_weapon_id text not null default '',
  inventory jsonb not null default '[]'::jsonb,
  character_created boolean not null default false,
  appearance jsonb,
  pos_x double precision,
  pos_y double precision
);

-- Bloqueia acesso público: apenas a service_role key do servidor do jogo
-- consegue ler/gravar (service role ignora RLS).
alter table public.accounts enable row level security;

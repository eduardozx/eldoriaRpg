-- Eldoria · Migração v2: personagem por conta + posição salva
-- Execute no SQL Editor do Supabase (tabela accounts já existente).

alter table public.accounts add column if not exists character_created boolean not null default false;
alter table public.accounts add column if not exists appearance jsonb;
alter table public.accounts add column if not exists pos_x double precision;
alter table public.accounts add column if not exists pos_y double precision;

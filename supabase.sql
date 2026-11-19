-- =========================================================
-- IPIRANGA CRM · estrutura do banco (rodar 1x no SQL Editor)
-- =========================================================

-- ---------- PERFIS ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null default '',
  email text,
  papel text not null default 'corretor' check (papel in ('diretor','corretor')),
  ativo boolean not null default false,
  criado timestamptz not null default now()
);

-- Primeiro usuário cadastrado vira Diretor ativo; os demais entram como Corretor aguardando aprovação
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare primeiro boolean;
begin
  select not exists(select 1 from public.profiles) into primeiro;
  insert into public.profiles(id, nome, email, papel, ativo)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'nome', split_part(new.email,'@',1)),
          new.email,
          case when primeiro then 'diretor' else 'corretor' end,
          primeiro);
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.is_ativo() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select ativo from public.profiles where id = auth.uid()), false)
$$;
create or replace function public.is_diretor() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select ativo and papel = 'diretor' from public.profiles where id = auth.uid()), false)
$$;

-- ---------- IMÓVEIS (compartilhado) ----------
create table if not exists public.imoveis (
  id uuid primary key default gen_random_uuid(),
  codigo text,
  titulo text not null,
  tipo text,
  finalidade text default 'Venda',
  bairro text,
  endereco text,
  valor numeric,
  quartos int, suites int, vagas int, area numeric,
  status text not null default 'Disponível',
  proprietario text,
  tel_proprietario text,
  obs text,
  criado_por uuid references public.profiles(id) default auth.uid(),
  criado timestamptz not null default now(),
  atualizado timestamptz not null default now()
);

-- ---------- LEADS ----------
create table if not exists public.leads (
  id uuid primary key default gen_random_uuid(),
  corretor_id uuid not null references public.profiles(id) default auth.uid(),
  nome text not null,
  tel text,
  etapa text not null default 'novo',
  origem text,
  data date,
  hora text,
  busca text,
  notas jsonb not null default '[]'::jsonb,
  imovel_id uuid references public.imoveis(id) on delete set null,
  criado timestamptz not null default now(),
  atualizado timestamptz not null default now()
);
create index if not exists leads_corretor_idx on public.leads(corretor_id);

-- ---------- FINANCEIRO ----------
create table if not exists public.financeiro (
  id uuid primary key default gen_random_uuid(),
  tipo text not null check (tipo in ('pagar','receber')),
  descricao text not null,
  categoria text,
  valor numeric not null default 0,
  vencimento date,
  pago boolean not null default false,
  pago_em date,
  corretor_id uuid references public.profiles(id) on delete set null,
  imovel_id uuid references public.imoveis(id) on delete set null,
  obs text,
  criado_por uuid references public.profiles(id) default auth.uid(),
  criado timestamptz not null default now()
);

-- ---------- SEGURANÇA (RLS) ----------
alter table public.profiles   enable row level security;
alter table public.imoveis    enable row level security;
alter table public.leads      enable row level security;
alter table public.financeiro enable row level security;

-- perfis: cada um vê o próprio; ativos veem a equipe; só diretor altera
drop policy if exists p_sel on public.profiles;
create policy p_sel on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_ativo());
drop policy if exists p_upd on public.profiles;
create policy p_upd on public.profiles for update to authenticated
  using (public.is_diretor()) with check (public.is_diretor());
drop policy if exists p_del on public.profiles;
create policy p_del on public.profiles for delete to authenticated
  using (public.is_diretor() and id <> auth.uid());

-- imóveis: todos ativos veem, cadastram e editam; só diretor exclui
drop policy if exists i_sel on public.imoveis;
create policy i_sel on public.imoveis for select to authenticated using (public.is_ativo());
drop policy if exists i_ins on public.imoveis;
create policy i_ins on public.imoveis for insert to authenticated with check (public.is_ativo());
drop policy if exists i_upd on public.imoveis;
create policy i_upd on public.imoveis for update to authenticated using (public.is_ativo()) with check (public.is_ativo());
drop policy if exists i_del on public.imoveis;
create policy i_del on public.imoveis for delete to authenticated using (public.is_diretor());

-- leads: corretor só os dele; diretor todos
drop policy if exists l_sel on public.leads;
create policy l_sel on public.leads for select to authenticated
  using (public.is_diretor() or (public.is_ativo() and corretor_id = auth.uid()));
drop policy if exists l_ins on public.leads;
create policy l_ins on public.leads for insert to authenticated
  with check (public.is_diretor() or (public.is_ativo() and corretor_id = auth.uid()));
drop policy if exists l_upd on public.leads;
create policy l_upd on public.leads for update to authenticated
  using (public.is_diretor() or (public.is_ativo() and corretor_id = auth.uid()))
  with check (public.is_diretor() or (public.is_ativo() and corretor_id = auth.uid()));
drop policy if exists l_del on public.leads;
create policy l_del on public.leads for delete to authenticated
  using (public.is_diretor() or (public.is_ativo() and corretor_id = auth.uid()));

-- financeiro: diretor tudo; corretor só vê os lançamentos marcados com o nome dele (comissões)
drop policy if exists f_sel on public.financeiro;
create policy f_sel on public.financeiro for select to authenticated
  using (public.is_diretor() or (public.is_ativo() and corretor_id = auth.uid()));
drop policy if exists f_ins on public.financeiro;
create policy f_ins on public.financeiro for insert to authenticated with check (public.is_diretor());
drop policy if exists f_upd on public.financeiro;
create policy f_upd on public.financeiro for update to authenticated using (public.is_diretor()) with check (public.is_diretor());
drop policy if exists f_del on public.financeiro;
create policy f_del on public.financeiro for delete to authenticated using (public.is_diretor());

-- ---------- TEMPO REAL (TV atualiza sozinha) ----------
do $$ begin
  begin alter publication supabase_realtime add table public.leads;      exception when others then null; end;
  begin alter publication supabase_realtime add table public.imoveis;    exception when others then null; end;
  begin alter publication supabase_realtime add table public.financeiro; exception when others then null; end;
end $$;

-- ---------- PERMISSÕES (Supabase novo vem trancado) ----------
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.profiles, public.leads, public.imoveis, public.financeiro to authenticated;
grant execute on function public.is_ativo(), public.is_diretor() to authenticated;

-- ---------- CAMPOS DA IMPORTAÇÃO DO SISTEMA ANTIGO ----------
alter table public.imoveis add column if not exists origem_id text;
alter table public.imoveis add column if not exists descricao text;
alter table public.imoveis add column if not exists fotos jsonb not null default '[]'::jsonb;
alter table public.leads   add column if not exists origem_id text;
alter table public.leads   add column if not exists responsavel_origem text;
create unique index if not exists imoveis_origem_uk on public.imoveis(origem_id);
create unique index if not exists leads_origem_uk   on public.leads(origem_id);
-- Papel GERENTE: vê e gerencia os leads dos corretores (e os próprios); não vê financeiro nem leads de diretores
alter table public.profiles drop constraint if exists profiles_papel_check;
alter table public.profiles add constraint profiles_papel_check check (papel in ('diretor','gerente','corretor'));

create or replace function public.is_gerente() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select ativo and papel = 'gerente' from public.profiles where id = auth.uid()), false)
$$;
create or replace function public.papel_de(uid uuid) returns text
language sql stable security definer set search_path = public as $$
  select papel from public.profiles where id = uid
$$;
grant execute on function public.is_gerente(), public.papel_de(uuid) to authenticated;

-- leads: diretor tudo · dono vê os seus · gerente vê os dos corretores
drop policy if exists l_sel on public.leads;
create policy l_sel on public.leads for select to authenticated using (
  public.is_diretor() or (public.is_ativo() and corretor_id = auth.uid())
  or (public.is_gerente() and public.papel_de(corretor_id) = 'corretor'));
drop policy if exists l_ins on public.leads;
create policy l_ins on public.leads for insert to authenticated with check (
  public.is_diretor() or (public.is_ativo() and corretor_id = auth.uid())
  or (public.is_gerente() and public.papel_de(corretor_id) = 'corretor'));
drop policy if exists l_upd on public.leads;
create policy l_upd on public.leads for update to authenticated
  using (public.is_diretor() or (public.is_ativo() and corretor_id = auth.uid())
         or (public.is_gerente() and public.papel_de(corretor_id) = 'corretor'))
  with check (public.is_diretor() or (public.is_ativo() and corretor_id = auth.uid())
         or (public.is_gerente() and public.papel_de(corretor_id) = 'corretor'));
drop policy if exists l_del on public.leads;
create policy l_del on public.leads for delete to authenticated using (
  public.is_diretor() or (public.is_ativo() and corretor_id = auth.uid())
  or (public.is_gerente() and public.papel_de(corretor_id) = 'corretor'));

-- financeiro: gerente não vê nada
drop policy if exists f_sel on public.financeiro;
create policy f_sel on public.financeiro for select to authenticated using (
  public.is_diretor() or (public.is_ativo() and corretor_id = auth.uid() and not public.is_gerente()));

-- ---------- WHATSAPP DOS USUÁRIOS ----------
alter table public.profiles add column if not exists whatsapp text;
create or replace function public.set_meu_whatsapp(numero text) returns void
language sql security definer set search_path = public as $$
  update public.profiles set whatsapp = numero where id = auth.uid()
$$;
grant execute on function public.set_meu_whatsapp(text) to authenticated;

-- ---------- LOCALIZAÇÃO DOS IMÓVEIS ----------
alter table public.imoveis add column if not exists cep text;
alter table public.imoveis add column if not exists condominio text;
alter table public.imoveis add column if not exists regiao text;
alter table public.imoveis add column if not exists lat double precision;
alter table public.imoveis add column if not exists lng double precision;
-- Privacidade entre diretores: cada diretor vê só os próprios leads e o próprio financeiro
create or replace function public.pode_ver_lead(dono uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select (public.is_ativo() and dono = auth.uid())
      or (public.is_diretor() and coalesce(public.papel_de(dono),'') <> 'diretor')
      or (public.is_gerente() and public.papel_de(dono) = 'corretor')
$$;
grant execute on function public.pode_ver_lead(uuid) to authenticated;

drop policy if exists l_sel on public.leads;
create policy l_sel on public.leads for select to authenticated using (public.pode_ver_lead(corretor_id));
drop policy if exists l_ins on public.leads;
create policy l_ins on public.leads for insert to authenticated with check (public.pode_ver_lead(corretor_id));
drop policy if exists l_upd on public.leads;
create policy l_upd on public.leads for update to authenticated
  using (public.pode_ver_lead(corretor_id)) with check (public.pode_ver_lead(corretor_id));
drop policy if exists l_del on public.leads;
create policy l_del on public.leads for delete to authenticated using (public.pode_ver_lead(corretor_id));

-- financeiro: cada diretor só vê e mexe no que ele lançou; corretor vê as comissões dele
drop policy if exists f_sel on public.financeiro;
create policy f_sel on public.financeiro for select to authenticated using (
  (public.is_diretor() and (criado_por = auth.uid() or corretor_id = auth.uid()))
  or (public.is_ativo() and corretor_id = auth.uid() and not public.is_gerente()));
drop policy if exists f_ins on public.financeiro;
create policy f_ins on public.financeiro for insert to authenticated with check (public.is_diretor() and criado_por = auth.uid());
drop policy if exists f_upd on public.financeiro;
create policy f_upd on public.financeiro for update to authenticated
  using (public.is_diretor() and criado_por = auth.uid()) with check (public.is_diretor() and criado_por = auth.uid());
drop policy if exists f_del on public.financeiro;
create policy f_del on public.financeiro for delete to authenticated using (public.is_diretor() and criado_por = auth.uid());

-- um diretor não pode alterar nem bloquear outro diretor
drop policy if exists p_upd on public.profiles;
create policy p_upd on public.profiles for update to authenticated
  using (public.is_diretor() and (id = auth.uid() or public.papel_de(id) <> 'diretor'))
  with check (public.is_diretor());
-- Diretor geral (João): vê tudo. Outros diretores: veem tudo, menos leads e financeiro do diretor geral
alter table public.profiles add column if not exists master boolean not null default false;
update public.profiles set master = true
 where id = (select id from public.profiles where papel = 'diretor' order by criado limit 1);

create or replace function public.is_master(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select master and ativo from public.profiles where id = uid), false)
$$;
grant execute on function public.is_master(uuid) to authenticated;

create or replace function public.pode_ver_lead(dono uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_master()
      or (public.is_ativo() and dono = auth.uid())
      or (public.is_diretor() and not public.is_master(dono))
      or (public.is_gerente() and public.papel_de(dono) = 'corretor')
$$;

drop policy if exists f_sel on public.financeiro;
create policy f_sel on public.financeiro for select to authenticated using (
  public.is_master()
  or (public.is_diretor() and not public.is_master(criado_por))
  or (public.is_ativo() and corretor_id = auth.uid() and not public.is_gerente()));
drop policy if exists f_ins on public.financeiro;
create policy f_ins on public.financeiro for insert to authenticated with check (public.is_diretor() and criado_por = auth.uid());
drop policy if exists f_upd on public.financeiro;
create policy f_upd on public.financeiro for update to authenticated
  using (public.is_master() or (public.is_diretor() and not public.is_master(criado_por)))
  with check (public.is_master() or (public.is_diretor() and not public.is_master(criado_por)));
drop policy if exists f_del on public.financeiro;
create policy f_del on public.financeiro for delete to authenticated
  using (public.is_master() or (public.is_diretor() and not public.is_master(criado_por)));

drop policy if exists p_upd on public.profiles;
create policy p_upd on public.profiles for update to authenticated
  using (public.is_master() or (public.is_diretor() and (id = auth.uid() or public.papel_de(id) <> 'diretor')))
  with check (public.is_master() or (public.is_diretor() and not master));

select nome, email, papel, master from public.profiles where papel = 'diretor';
-- MÓDULO DE VENDAS
create table if not exists public.vendas (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid references public.leads(id) on delete set null,
  imovel_id uuid references public.imoveis(id) on delete set null,
  imovel_desc text,
  corretor_id uuid not null references public.profiles(id),
  cliente text,
  tipo text not null default 'Venda',
  valor numeric not null default 0,
  data date not null default current_date,
  comissao_pct numeric,
  comissao numeric,
  obs text,
  criado_por uuid references public.profiles(id) default auth.uid(),
  criado timestamptz not null default now()
);
alter table public.vendas enable row level security;
grant select, insert, update, delete on public.vendas to authenticated;

-- mesma regra dos leads: quem vê o corretor vê a venda; corretor registra as dele; só diretor/gerente edita ou cancela
drop policy if exists v_sel on public.vendas;
create policy v_sel on public.vendas for select to authenticated using (public.pode_ver_lead(corretor_id));
drop policy if exists v_ins on public.vendas;
create policy v_ins on public.vendas for insert to authenticated with check (public.pode_ver_lead(corretor_id));
drop policy if exists v_upd on public.vendas;
create policy v_upd on public.vendas for update to authenticated
  using ((public.is_diretor() or public.is_gerente()) and public.pode_ver_lead(corretor_id))
  with check ((public.is_diretor() or public.is_gerente()) and public.pode_ver_lead(corretor_id));
drop policy if exists v_del on public.vendas;
create policy v_del on public.vendas for delete to authenticated
  using (public.is_diretor() and public.pode_ver_lead(corretor_id));

do $$ begin
  begin alter publication supabase_realtime add table public.vendas; exception when others then null; end;
end $$;
-- REGRAS DE COMISSÃO
alter table public.profiles add column if not exists creci_definitivo boolean not null default false;
alter table public.profiles add column if not exists split_pct numeric;  -- opcional: % especial de um corretor
alter table public.vendas add column if not exists comissao_corretor numeric;
alter table public.vendas add column if not exists pct_corretor numeric;
alter table public.vendas add column if not exists comissao_gerente numeric;
alter table public.vendas add column if not exists gerente_id uuid references public.profiles(id);
alter table public.vendas add column if not exists comissao_ipiranga numeric;
alter table public.vendas add column if not exists comissao_diretor boolean not null default false;

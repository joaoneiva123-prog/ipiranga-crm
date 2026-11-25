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

-- ---------- LIGA LANÇAMENTOS À VENDA ----------
alter table public.financeiro add column if not exists venda_id uuid references public.vendas(id) on delete set null;
-- Financeiro: diretor geral tudo · diretor (menos o do geral) · gerente vê repasses dele e dos corretores · corretor só os dele
drop policy if exists f_sel on public.financeiro;
create policy f_sel on public.financeiro for select to authenticated using (
  public.is_master()
  or (public.is_diretor() and not public.is_master(criado_por))
  or (public.is_ativo() and corretor_id = auth.uid())
  or (public.is_gerente() and public.papel_de(corretor_id) = 'corretor'));
-- PERFIL SECRETÁRIA + MÓDULO CAPTAÇÃO
alter table public.profiles drop constraint if exists profiles_papel_check;
alter table public.profiles add constraint profiles_papel_check check (papel in ('diretor','gerente','secretaria','corretor'));

create or replace function public.is_secretaria() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select ativo and papel = 'secretaria' from public.profiles where id = auth.uid()), false)
$$;
grant execute on function public.is_secretaria() to authenticated;

-- secretária vê/cadastra leads dos corretores e do gerente (como o gerente)
create or replace function public.pode_ver_lead(dono uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_master()
      or (public.is_ativo() and dono = auth.uid())
      or (public.is_diretor() and not public.is_master(dono))
      or (public.is_gerente() and public.papel_de(dono) = 'corretor')
      or (public.is_secretaria() and public.papel_de(dono) in ('corretor','gerente'))
$$;

create table if not exists public.captacoes (
  id uuid primary key default gen_random_uuid(),
  link text, titulo text, tipo text, valor numeric, bairro text, quartos int, area numeric,
  proprietario text, tel text, texto text,
  status text not null default 'novo',
  data date,
  notas jsonb not null default '[]'::jsonb,
  imovel_id uuid references public.imoveis(id) on delete set null,
  responsavel_id uuid references public.profiles(id) default auth.uid(),
  criado timestamptz not null default now(),
  atualizado timestamptz not null default now()
);
alter table public.captacoes enable row level security;
grant select, insert, update, delete on public.captacoes to authenticated;
drop policy if exists c_all on public.captacoes;
drop policy if exists c_sel on public.captacoes;
create policy c_sel on public.captacoes for select to authenticated using (public.is_diretor() or public.is_gerente() or public.is_secretaria());
drop policy if exists c_ins on public.captacoes;
create policy c_ins on public.captacoes for insert to authenticated with check (public.is_diretor() or public.is_gerente() or public.is_secretaria());
drop policy if exists c_upd on public.captacoes;
create policy c_upd on public.captacoes for update to authenticated
  using (public.is_diretor() or public.is_gerente() or public.is_secretaria())
  with check (public.is_diretor() or public.is_gerente() or public.is_secretaria());
drop policy if exists c_del on public.captacoes;
create policy c_del on public.captacoes for delete to authenticated using (public.is_diretor() or responsavel_id = auth.uid());
do $$ begin
  begin alter publication supabase_realtime add table public.captacoes; exception when others then null; end;
end $$;
-- FOTOS: pasta pública "fotos" no Storage
insert into storage.buckets (id, name, public) values ('fotos', 'fotos', true) on conflict (id) do update set public = true;
drop policy if exists "fotos_envio" on storage.objects;
create policy "fotos_envio" on storage.objects for insert to authenticated with check (bucket_id = 'fotos' and public.is_ativo());
drop policy if exists "fotos_apagar" on storage.objects;
create policy "fotos_apagar" on storage.objects for delete to authenticated using (bucket_id = 'fotos' and (owner = auth.uid() or public.is_diretor()));
-- ROLETA DE LEADS
create table if not exists public.campanhas (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  origem text,
  ativa boolean not null default true,
  participantes uuid[] not null default '{}',
  pausados uuid[] not null default '{}',
  ponteiro int not null default 0,
  criado_por uuid references public.profiles(id) default auth.uid(),
  criado timestamptz not null default now()
);
alter table public.campanhas enable row level security;
grant select, insert, update, delete on public.campanhas to authenticated;
drop policy if exists cp_sel on public.campanhas;
create policy cp_sel on public.campanhas for select to authenticated using (public.is_diretor() or public.is_gerente() or public.is_secretaria());
drop policy if exists cp_ins on public.campanhas;
create policy cp_ins on public.campanhas for insert to authenticated with check (public.is_diretor() or public.is_gerente() or public.is_secretaria());
drop policy if exists cp_upd on public.campanhas;
create policy cp_upd on public.campanhas for update to authenticated
  using (public.is_diretor() or public.is_gerente() or public.is_secretaria())
  with check (public.is_diretor() or public.is_gerente() or public.is_secretaria());
drop policy if exists cp_del on public.campanhas;
create policy cp_del on public.campanhas for delete to authenticated using (public.is_diretor());

alter table public.leads add column if not exists campanha_id uuid references public.campanhas(id) on delete set null;

-- Sorteia o próximo da fila (em rodízio, pulando pausados e bloqueados) e já cria o lead para ele
create or replace function public.distribuir_lead(cid uuid, p_nome text, p_tel text default null, p_busca text default null, p_obs text default null)
returns json language plpgsql security definer set search_path = public as $$
declare c public.campanhas; lista uuid[]; n int; escolhido uuid; novo uuid;
begin
  if not (public.is_diretor() or public.is_gerente() or public.is_secretaria()) then raise exception 'Sem permissão para distribuir leads'; end if;
  select * into c from public.campanhas where id = cid for update;
  if not found then raise exception 'Campanha não encontrada'; end if;
  if not c.ativa then raise exception 'Campanha pausada'; end if;
  select array_agg(x order by ord) into lista
    from unnest(c.participantes) with ordinality as t(x, ord)
    join public.profiles p on p.id = t.x
   where p.ativo and not (t.x = any(c.pausados));
  n := coalesce(array_length(lista, 1), 0);
  if n = 0 then raise exception 'Nenhum corretor ativo na fila desta campanha'; end if;
  escolhido := lista[(c.ponteiro % n) + 1];
  update public.campanhas set ponteiro = ponteiro + 1 where id = cid;
  insert into public.leads (corretor_id, nome, tel, etapa, origem, busca, data, campanha_id, notas)
  values (escolhido, coalesce(nullif(trim(p_nome), ''), 'Lead sem nome'), p_tel, 'novo', coalesce(c.origem, c.nome), p_busca, current_date, cid,
          jsonb_build_array(jsonb_build_object('t', '🎯 Recebido pela roleta: ' || c.nome || coalesce(E'\n' || nullif(p_obs, ''), ''),
                                               'em', floor(extract(epoch from now()) * 1000), 'por', 'Roleta')))
  returning id into novo;
  return json_build_object('lead_id', novo, 'corretor_id', escolhido);
end $$;
grant execute on function public.distribuir_lead(uuid, text, text, text, text) to authenticated;

do $$ begin
  begin alter publication supabase_realtime add table public.campanhas; exception when others then null; end;
end $$;

-- ---------- CAPTADOR DO IMÓVEL ----------
alter table public.imoveis add column if not exists captador_id uuid references public.profiles(id) on delete set null;
alter table public.imoveis add column if not exists captador_nome text;
-- SITE PÚBLICO: vitrine de imóveis disponíveis (sem dados do proprietário) + formulário que vira lead
create or replace view public.site_imoveis as
  select id, codigo, titulo, tipo, finalidade, bairro, condominio, regiao, valor, quartos, suites, vagas, area,
         descricao, fotos, round(lat::numeric, 3)::float8 as lat, round(lng::numeric, 3)::float8 as lng, criado
    from public.imoveis
   where status = 'Disponível';
grant select on public.site_imoveis to anon, authenticated;

create or replace function public.site_lead(p_nome text, p_tel text, p_email text default null, p_msg text default null, p_codigo text default null)
returns json language plpgsql security definer set search_path = public as $$
declare v_imo public.imoveis; v_camp public.campanhas; lista uuid[]; n int; v_cor uuid; v_id uuid; v_txt text;
begin
  if length(coalesce(trim(p_nome), '')) < 2 or length(regexp_replace(coalesce(p_tel, ''), '\D', '', 'g')) < 10 then raise exception 'dados inválidos'; end if;
  if length(coalesce(p_msg, '')) > 2000 or length(p_nome) > 120 then raise exception 'texto muito longo'; end if;
  -- evita duplicado/robô: mesmo telefone nos últimos 10 minutos
  if exists (select 1 from public.leads where regexp_replace(coalesce(tel, ''), '\D', '', 'g') = regexp_replace(p_tel, '\D', '', 'g') and criado > now() - interval '10 minutes')
    then return json_build_object('ok', true, 'repetido', true); end if;
  if p_codigo is not null then select * into v_imo from public.imoveis where codigo = p_codigo or id::text = p_codigo limit 1; end if;
  -- roleta da campanha de origem "Site" (se existir e estiver ativa); senão vai para o diretor geral
  select * into v_camp from public.campanhas where ativa and (origem = 'Site' or nome ilike 'site%') order by criado limit 1 for update;
  if found then
    select array_agg(x order by ord) into lista from unnest(v_camp.participantes) with ordinality as t(x, ord)
      join public.profiles p on p.id = t.x where p.ativo and not (t.x = any(v_camp.pausados));
    n := coalesce(array_length(lista, 1), 0);
    if n > 0 then v_cor := lista[(v_camp.ponteiro % n) + 1]; update public.campanhas set ponteiro = ponteiro + 1 where id = v_camp.id; end if;
  end if;
  if v_cor is null then select id into v_cor from public.profiles where master and ativo order by criado limit 1; end if;
  if v_cor is null then select id into v_cor from public.profiles where papel = 'diretor' and ativo order by criado limit 1; end if;
  v_txt := '🌐 Contato pelo site' || coalesce(E'\nImóvel: ' || v_imo.codigo || ' – ' || v_imo.titulo, '') || coalesce(E'\nE-mail: ' || nullif(p_email, ''), '') || coalesce(E'\n' || nullif(p_msg, ''), '');
  insert into public.leads (corretor_id, nome, tel, etapa, origem, busca, data, imovel_id, campanha_id, notas)
  values (v_cor, trim(p_nome), trim(p_tel), 'novo', 'Site', v_imo.titulo, current_date, v_imo.id, v_camp.id,
          jsonb_build_array(jsonb_build_object('t', v_txt, 'em', floor(extract(epoch from now()) * 1000), 'por', 'Site')))
  returning id into v_id;
  return json_build_object('ok', true);
end $$;
revoke all on function public.site_lead(text, text, text, text, text) from public;
grant execute on function public.site_lead(text, text, text, text, text) to anon, authenticated;

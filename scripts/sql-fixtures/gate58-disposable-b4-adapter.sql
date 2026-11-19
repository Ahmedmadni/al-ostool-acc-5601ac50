-- SYNTHETIC DISPOSABLE POSTGRESQL ONLY. NEVER APPLY TO ANY HOSTED DB.
-- Installed AFTER native-g42-real-posting-parent.sql in its OWN isolated CI job.
-- Only a stand-in for actual B4; the separate "Actual B4 SQL" CI job compiles
-- observed real B4 source definitions. This adapter models a reversal receipt
-- so that Gate58's fail-closed historical replay checks can be exercised.
do $disposable$
begin
  if current_database()<>'onexa_gate_test'
     or to_regclass('public.fixture_module_grants') is null then
    raise exception 'SYNTHETIC_B4_ADAPTER_DISPOSABLE_ONLY';
  end if;
end $disposable$;

alter table public.chart_of_accounts
  add column id uuid not null default gen_random_uuid();
alter table public.onexa_journal_headers
  add column journal_number text not null default 'SYNTHETIC-B4',
  add column fiscal_period_id uuid,
  add column source_snapshot jsonb not null default '{}'::jsonb,
  add column memo text;

create table public.onexa_fiscal_periods (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null,
  legal_entity_id uuid not null,
  period_code text not null,
  starts_on date not null,
  ends_on date not null,
  status text not null default 'open',
  unique(tenant_id,legal_entity_id,period_code)
);
insert into public.onexa_fiscal_periods(
 tenant_id,legal_entity_id,period_code,starts_on,ends_on,status
) values
 ('tenant-smoke-A','a0000000-0000-4000-8000-000000000001',
   '2026-11',date '2026-11-01',date '2026-11-30','open'),
 ('tenant-smoke-A','a0000000-0000-4000-8000-000000000001',
   '2026-12',date '2026-12-01',date '2026-12-31','open'),
 ('tenant-smoke-B','b0000000-0000-4000-8000-000000000001',
   '2026-11',date '2026-11-01',date '2026-11-30','open');

create table public.onexa_journal_lines (
  tenant_id text not null,
  journal_id uuid not null references public.onexa_journal_headers(id),
  line_number integer not null,
  account_code text not null,
  debit numeric(20,4) not null,
  credit numeric(20,4) not null,
  description text,
  dimensions jsonb not null default '{}'::jsonb,
  primary key (journal_id, line_number)
);

insert into public.fixture_module_grants(tenant_id,user_id,module_key,action)
select m.tenant_id,m.user_id,'finance',a.action
from public.onexa_workspace_memberships m
cross join (values ('create'),('submit'),('approve'),('post'),('reverse')) a(action)
on conflict do nothing;

create or replace function public.onexa_post_journal(
 _legal_entity_id uuid,_source_document_type text,_source_document_id text,
 _source_revision integer,_source_status text,_source_snapshot jsonb,
 _accounting_date date,_period_code text,_currency text,_memo text,_lines jsonb
) returns uuid
language plpgsql security definer set search_path=pg_catalog,public as $fixture$
declare
 _id uuid:=gen_random_uuid();
 _tenant text:=onexa_private.claim_tenant_id();
 _debit numeric:=(select coalesce(sum((v->>'debit')::numeric),0)
                    from jsonb_array_elements(_lines) v);
 _credit numeric:=(select coalesce(sum((v->>'credit')::numeric),0)
                    from jsonb_array_elements(_lines) v);
 _period_id uuid;
begin
 if auth.uid() is null or _tenant is null or _source_status <> 'approved'
    or _source_document_type <> 'manual_journal'
    or _source_revision < 1 or _debit <> _credit or _debit <= 0
    or jsonb_array_length(_lines) < 2
    or not exists (select 1 from public.onexa_legal_entities e
       where e.id=_legal_entity_id and e.tenant_id=_tenant and e.is_active) then
   raise exception 'SYNTHETIC_B4_MANUAL_JOURNAL_INVALID';
 end if;
 select id into _period_id from public.onexa_fiscal_periods
 where tenant_id=_tenant and legal_entity_id=_legal_entity_id
   and period_code=_period_code and _accounting_date between starts_on and ends_on;
 if _period_id is null then
   raise exception 'SYNTHETIC_B4_FISCAL_PERIOD_INVALID';
 end if;
 insert into public.onexa_journal_headers(
   id,tenant_id,legal_entity_id,state,source_document_type,source_document_id,
   source_revision,currency,total_debit,total_credit,accounting_date,
   journal_number,fiscal_period_id,source_snapshot,memo
 ) values(_id,_tenant,_legal_entity_id,'posted',_source_document_type,
    _source_document_id,_source_revision,_currency,_debit,_credit,_accounting_date,
    'FAKE-MJ-'||left(_id::text,8),_period_id,
    coalesce(_source_snapshot,'{}'::jsonb),_memo);
 insert into public.onexa_journal_lines(
   tenant_id,journal_id,line_number,account_code,debit,credit,description,dimensions
 )
 select _tenant,_id,ordinality::integer,
        x->>'account_code',(x->>'debit')::numeric,(x->>'credit')::numeric,
        nullif(x->>'description',''),coalesce(x->'dimensions','{}'::jsonb)
 from jsonb_array_elements(_lines) with ordinality as t(x,ordinality);
 return _id;
end;
$fixture$;

create or replace function public.onexa_reverse_journal(
 _journal_id uuid,_accounting_date date,_period_code text,_reason text
) returns uuid
language plpgsql security definer set search_path=pg_catalog,public as $fixture$
declare
 _origin public.onexa_journal_headers%rowtype;
 _new uuid:=gen_random_uuid();
 _period_id uuid;
begin
 if auth.uid() is null or onexa_private.claim_tenant_id() is null
    or nullif(btrim(_reason),'') is null then
   raise exception 'SYNTHETIC_B4_REVERSAL_INVALID';
 end if;
 select * into _origin from public.onexa_journal_headers
 where id=_journal_id and tenant_id=onexa_private.claim_tenant_id() and state='posted'
 for update;
 if not found or _origin.reversal_journal_id is not null then
    raise exception 'SYNTHETIC_B4_ORIGINAL_NOT_REVERSIBLE';
 end if;
 select id into _period_id from public.onexa_fiscal_periods
 where tenant_id=_origin.tenant_id and legal_entity_id=_origin.legal_entity_id
   and period_code=_period_code and _accounting_date between starts_on and ends_on;
 if _period_id is null then raise exception 'SYNTHETIC_B4_REVERSAL_PERIOD_INVALID'; end if;

 insert into public.onexa_journal_headers(
   id,tenant_id,legal_entity_id,state,reversal_of_id,
   source_document_type,source_document_id,source_revision,currency,
   total_debit,total_credit,accounting_date,journal_number,fiscal_period_id,
   source_snapshot,memo
 ) values(
   _new,_origin.tenant_id,_origin.legal_entity_id,'posted',_origin.id,
   'journal_reversal',_origin.id::text,1,
   _origin.currency,_origin.total_credit,_origin.total_debit,_accounting_date,
   'FAKE-REV-'||left(_new::text,8),_period_id,
   jsonb_build_object('reversal_of',_origin.id,'reason',_reason),
   concat('Reversal of ',_origin.journal_number,' — ',_reason)
 );

 insert into public.onexa_journal_lines(
   tenant_id,journal_id,line_number,account_code,debit,credit,description,dimensions
 )
 select _origin.tenant_id,_new,l.line_number,
        l.account_code,l.credit,l.debit,
        concat('عكس القيد ',_origin.journal_number,' — ',_reason),
        l.dimensions
 from public.onexa_journal_lines l
 where l.journal_id=_origin.id
 order by l.line_number;

 update public.onexa_journal_headers
 set state='reversed',reversal_journal_id=_new where id=_origin.id;
 return _new;
end;
$fixture$;

grant execute on function public.onexa_reverse_journal(uuid,date,text,text) to authenticated;

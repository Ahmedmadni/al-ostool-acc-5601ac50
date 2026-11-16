-- SYNTHETIC DISPOSABLE POSTGRESQL ONLY. NEVER APPLY TO ANY HOSTED DB.
-- Installed AFTER native-g42-real-posting-parent.sql in its OWN isolated CI job.
-- Replace only the simplified B4 test double. Does not exercise real B4.
alter table public.chart_of_accounts add column id uuid not null default gen_random_uuid();
alter table public.onexa_journal_headers add column journal_number text not null default 'SYNTHETIC-B4';

insert into public.fixture_module_grants(tenant_id,user_id,module_key,action)
select m.tenant_id,m.user_id,'finance',action.action
from public.onexa_workspace_memberships m
cross join (values ('create'),('submit'),('approve'),('post'),('reverse')) action(action)
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
begin
 if auth.uid() is null or _tenant is null or _source_status <> 'approved'
    or _source_document_type <> 'manual_journal'
    or _source_revision < 1 or _debit <> _credit or _debit <= 0
    or jsonb_array_length(_lines) < 2
    or not exists (select 1 from public.onexa_legal_entities e
       where e.id=_legal_entity_id and e.tenant_id=_tenant and e.is_active) then
   raise exception 'SYNTHETIC_B4_MANUAL_JOURNAL_INVALID';
 end if;
 insert into public.onexa_journal_headers(
   id,tenant_id,legal_entity_id,state,source_document_type,source_document_id,
   source_revision,currency,total_debit,total_credit,accounting_date,journal_number
 ) values(_id,_tenant,_legal_entity_id,'posted',_source_document_type,
    _source_document_id,_source_revision,_currency,_debit,_credit,_accounting_date,
    'FAKE-MJ-'||left(_id::text,8));
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
 insert into public.onexa_journal_headers(
   id,tenant_id,legal_entity_id,state,reversal_of_id,
   source_document_type,source_document_id,source_revision,currency,
   total_debit,total_credit,accounting_date,journal_number
 ) values(
   _new,_origin.tenant_id,_origin.legal_entity_id,'posted',_origin.id,
   'manual_journal_reversal',_origin.source_document_id,_origin.source_revision,
   _origin.currency,_origin.total_credit,_origin.total_debit,_accounting_date,
   'FAKE-REV-'||left(_new::text,8)
 );
 update public.onexa_journal_headers set state='reversed',reversal_journal_id=_new
 where id=_origin.id;
 return _new;
end;
$fixture$;

grant execute on function public.onexa_reverse_journal(uuid,date,text,text) to authenticated;

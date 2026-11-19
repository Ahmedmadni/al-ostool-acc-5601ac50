-- ONEXA B4 GL / source registry / reversal integrity.
-- STRICTLY SELECT ONLY. No customer journal data is returned; count per issue.
-- Intended for independently restored STAGING, not ad-hoc live production runs.
-- Prefer a repeatable-read, read-only transaction during finance-approved
-- staging acceptance. For large ledgers, approve a bounded maintenance window.
-- Zero findings means only THESE invariants passed at this snapshot, not that
-- all financial workflow, tax, permission or source accuracy is certified.

with
checks(issue_code, severity) as (
  values
    ('REGISTRY_TARGET_MISSING', 'BLOCK'),
    ('REGISTRY_SOURCE_MISMATCH', 'BLOCK'),
    ('REGISTRY_KEY_MISMATCH', 'BLOCK'),
    ('HEADER_WITHOUT_REGISTRY', 'REVIEW'),
    ('DUPLICATE_SOURCE_RECEIPT', 'BLOCK'),
    ('HEADER_IMBALANCED', 'BLOCK'),
    ('LINE_COUNT_LT_TWO', 'BLOCK'),
    ('LINE_SUM_MISMATCH', 'BLOCK'),
    ('LINE_SIDE_INVALID', 'BLOCK'),
    ('LINE_TENANT_MISMATCH', 'BLOCK'),
    ('PERIOD_ENTITY_DATE_MISMATCH', 'BLOCK'),
    ('REVERSED_ORIGINAL_LINK_MISMATCH', 'BLOCK'),
    ('POSTED_WITH_REVERSAL_POINTER', 'BLOCK'),
    ('REVERSAL_SOURCE_LINK_MISMATCH', 'BLOCK'),
    ('REVERSAL_TOTALS_MISMATCH', 'BLOCK'),
    ('REVERSAL_REASON_RECEIPT_MISMATCH', 'BLOCK'),
    ('REVERSAL_ORDERED_LINES_MISMATCH', 'BLOCK')
),
line_facts as (
  select l.journal_id,
    count(*)::bigint as line_count,
    coalesce(sum(l.debit),0)::numeric as sum_debit,
    coalesce(sum(l.credit),0)::numeric as sum_credit,
    count(*) filter (
      where l.line_number<1
         or not ((l.debit>0 and l.credit=0) or (l.credit>0 and l.debit=0))
    )::bigint as invalid_sides,
    jsonb_agg(
      jsonb_build_object(
        'line_number',l.line_number,
        'account_code',l.account_code,
        'debit',l.debit,
        'credit',l.credit,
        'description',l.description,
        'dimensions',l.dimensions
      ) order by l.line_number
    ) as ordered_receipt
  from public.onexa_journal_lines l
  group by l.journal_id
),
findings as (
  select 'REGISTRY_TARGET_MISSING'::text issue_code
  from public.onexa_posting_registry r
  left join public.onexa_journal_headers h on h.id=r.journal_id
  where h.id is null

  union all
  select 'REGISTRY_SOURCE_MISMATCH'
  from public.onexa_posting_registry r
  join public.onexa_journal_headers h on h.id=r.journal_id
  where (r.tenant_id,r.legal_entity_id,r.source_document_type,
         r.source_document_id,r.source_revision)
    is distinct from
        (h.tenant_id,h.legal_entity_id,h.source_document_type,
         h.source_document_id,h.source_revision)

  union all
  select 'REGISTRY_KEY_MISMATCH'
  from public.onexa_posting_registry r
  where r.idempotency_key is distinct from concat_ws(
    ':','onexa-posting-v1',r.tenant_id,r.legal_entity_id::text,
    r.source_document_type,r.source_document_id,r.source_revision::text
  )

  union all
  select 'HEADER_WITHOUT_REGISTRY'
  from public.onexa_journal_headers h
  left join public.onexa_posting_registry r on r.journal_id=h.id
  where r.journal_id is null

  union all
  select 'DUPLICATE_SOURCE_RECEIPT'
  from public.onexa_journal_headers h
  group by h.tenant_id,h.legal_entity_id,h.source_document_type,
           h.source_document_id,h.source_revision
  having count(*)>1

  union all
  select 'HEADER_IMBALANCED'
  from public.onexa_journal_headers h
  where h.total_debit is distinct from h.total_credit
     or h.total_debit<=0 or h.total_credit<=0

  union all
  select 'LINE_COUNT_LT_TWO'
  from public.onexa_journal_headers h
  left join line_facts l on l.journal_id=h.id
  where coalesce(l.line_count,0)<2

  union all
  select 'LINE_SUM_MISMATCH'
  from public.onexa_journal_headers h
  left join line_facts l on l.journal_id=h.id
  where coalesce(l.sum_debit,0) is distinct from h.total_debit
     or coalesce(l.sum_credit,0) is distinct from h.total_credit

  union all
  select 'LINE_SIDE_INVALID'
  from line_facts l
  where l.invalid_sides>0

  union all
  select 'LINE_TENANT_MISMATCH'
  from public.onexa_journal_lines l
  left join public.onexa_journal_headers h on h.id=l.journal_id
  where h.id is null or l.tenant_id is distinct from h.tenant_id

  union all
  select 'PERIOD_ENTITY_DATE_MISMATCH'
  from public.onexa_journal_headers h
  left join public.onexa_fiscal_periods p on p.id=h.fiscal_period_id
  where p.id is null
     or p.tenant_id is distinct from h.tenant_id
     or p.legal_entity_id is distinct from h.legal_entity_id
     or h.accounting_date not between p.starts_on and p.ends_on

  union all
  select 'REVERSED_ORIGINAL_LINK_MISMATCH'
  from public.onexa_journal_headers h
  left join public.onexa_journal_headers rev on rev.id=h.reversal_journal_id
  where h.state='reversed'
    and (h.reversal_journal_id is null or rev.id is null
      or rev.reversal_of_id is distinct from h.id
      or rev.source_document_type is distinct from 'journal_reversal'
      or rev.source_document_id is distinct from h.id::text
      or rev.source_revision is distinct from 1
      or rev.tenant_id is distinct from h.tenant_id
      or rev.legal_entity_id is distinct from h.legal_entity_id
      or rev.state is distinct from 'posted')

  union all
  select 'POSTED_WITH_REVERSAL_POINTER'
  from public.onexa_journal_headers h
  where h.state='posted' and h.reversal_journal_id is not null

  union all
  select 'REVERSAL_SOURCE_LINK_MISMATCH'
  from public.onexa_journal_headers rev
  left join public.onexa_journal_headers orig on orig.id=rev.reversal_of_id
  where rev.source_document_type='journal_reversal'
    and (orig.id is null
      or orig.source_document_type='journal_reversal'
      or orig.tenant_id is distinct from rev.tenant_id
      or orig.legal_entity_id is distinct from rev.legal_entity_id
      or orig.state is distinct from 'reversed'
      or orig.reversal_journal_id is distinct from rev.id
      or rev.source_document_id is distinct from orig.id::text
      or rev.source_revision is distinct from 1
      or rev.state is distinct from 'posted')

  union all
  select 'REVERSAL_TOTALS_MISMATCH'
  from public.onexa_journal_headers orig
  join public.onexa_journal_headers rev on rev.id=orig.reversal_journal_id
  where orig.state='reversed'
    and (rev.total_debit is distinct from orig.total_credit
      or rev.total_credit is distinct from orig.total_debit
      or rev.currency is distinct from orig.currency)

  union all
  select 'REVERSAL_REASON_RECEIPT_MISMATCH'
  from public.onexa_journal_headers rev
  join public.onexa_journal_headers orig on orig.id=rev.reversal_of_id
  where rev.source_document_type='journal_reversal'
    and (nullif(btrim(rev.source_snapshot->>'reason'),'') is null
      or rev.source_snapshot->>'reversal_of' is distinct from orig.id::text
      or rev.memo is distinct from concat(
        'Reversal of ',orig.journal_number,' — ',rev.source_snapshot->>'reason'
      ))

  union all
  select 'REVERSAL_ORDERED_LINES_MISMATCH'
  from public.onexa_journal_headers orig
  join public.onexa_journal_headers rev on rev.id=orig.reversal_journal_id
  left join line_facts ol on ol.journal_id=orig.id
  left join line_facts rl on rl.journal_id=rev.id
  where orig.state='reversed'
    and (
      coalesce(ol.line_count,0)<2
      or coalesce(rl.line_count,0)<2
      or rl.ordered_receipt is distinct from (
        select coalesce(jsonb_agg(jsonb_build_object(
          'line_number',(x->>'line_number')::integer,
          'account_code',x->>'account_code',
          'debit',(x->>'credit')::numeric,
          'credit',(x->>'debit')::numeric,
          'description',concat(
            'عكس القيد ',orig.journal_number,' — ',
            rev.source_snapshot->>'reason'
          ),
          'dimensions',x->'dimensions'
        ) order by (x->>'line_number')::integer),'[]'::jsonb)
        from jsonb_array_elements(coalesce(ol.ordered_receipt,'[]'::jsonb)) x
      )
    )
)
select c.issue_code,c.severity,
  count(f.issue_code)::bigint as affected_count
from checks c
left join findings f on f.issue_code=c.issue_code
group by c.issue_code,c.severity
order by c.issue_code;

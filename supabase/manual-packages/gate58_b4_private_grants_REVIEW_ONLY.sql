-- ONEXA B4 LEAST-PRIVILEGE REMEDIATION — REVIEW ONLY.
-- NEVER auto-deploy. Test in isolated, restored Staging with all posting
-- sources and authorized user roles before a production change window.
-- This ONLY revokes direct authenticated execution of internal B4 functions.
-- It does not remove service_role, owner, or public checked RPC permissions.
begin;
do $preflight$
declare
  _post regprocedure :=
    to_regprocedure('onexa_private.post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)');
  _reverse regprocedure :=
    to_regprocedure('onexa_private.reverse_journal(uuid,date,text,text)');
  _checked_post regprocedure :=
    to_regprocedure('public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)');
  _checked_reverse regprocedure :=
    to_regprocedure('public.onexa_reverse_journal(uuid,date,text,text)');
begin
  if _post is null or _reverse is null or
     _checked_post is null or _checked_reverse is null then
    raise exception 'ONEXA_B4_PRIVATE_GRANT_REQUIRED_FUNCTION_MISSING';
  end if;
  if md5(pg_get_functiondef(_post::oid))
       <> '5ac58a780bbed49e8ba31b6f46c39f48'
     or md5(pg_get_functiondef(_reverse::oid))
       <> 'f51a890027057a0e838c13cbfd6ddb61' then
    raise exception 'ONEXA_B4_PRIVATE_GRANT_DEFINITION_DRIFT_STOP';
  end if;
  if not has_function_privilege('authenticated', _post::oid, 'EXECUTE')
     or not has_function_privilege('authenticated', _reverse::oid, 'EXECUTE')
     or not has_function_privilege('authenticated', _checked_post::oid, 'EXECUTE')
     or not has_function_privilege('authenticated', _checked_reverse::oid, 'EXECUTE') then
    raise exception 'ONEXA_B4_PRIVATE_GRANT_EXPECTED_MATRIX_CHANGED_STOP';
  end if;
  if exists (
    select 1 from pg_proc p
    where p.oid in (_checked_post::oid, _checked_reverse::oid)
      and p.prosecdef is not true
  ) then
    raise exception 'ONEXA_B4_CHECKED_SECURITY_DEFINER_REQUIRED';
  end if;
  if has_function_privilege('authenticated',
       'public.onexa_post_journal_unchecked(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)',
       'EXECUTE')
     or has_function_privilege('authenticated',
       'public.onexa_reverse_journal_unchecked(uuid,date,text,text)',
       'EXECUTE') then
    raise exception 'ONEXA_B4_UNCHECKED_RPC_PERMISSION_DRIFT_STOP';
  end if;
end;
$preflight$;

revoke execute on function
 onexa_private.post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)
 from authenticated;
revoke execute on function
 onexa_private.reverse_journal(uuid,date,text,text)
 from authenticated;

do $postcheck$
begin
 if has_function_privilege('authenticated',
      'onexa_private.post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)',
      'EXECUTE')
    or has_function_privilege('authenticated',
      'onexa_private.reverse_journal(uuid,date,text,text)','EXECUTE')
    or not has_function_privilege('authenticated',
      'public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)',
      'EXECUTE')
    or not has_function_privilege('authenticated',
      'public.onexa_reverse_journal(uuid,date,text,text)','EXECUTE') then
   raise exception 'ONEXA_B4_PRIVATE_GRANT_POSTCHECK_FAILED';
 end if;
end;
$postcheck$;
commit;

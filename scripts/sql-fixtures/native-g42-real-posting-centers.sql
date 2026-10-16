-- After the REAL Gate42 SQL creates the project cost center table.
insert into public.onexa_project_cost_centers
 (id,tenant_id,legal_entity_id,branch_id,project_code,project_name,cost_center_code)
values
 ('a0000000-0000-4000-8000-000000000005','tenant-smoke-A',
  'a0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000002',
  'PROJ_A','Test Project A','OM_A'),
 ('b0000000-0000-4000-8000-000000000005','tenant-smoke-B',
  'b0000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000002',
  'PROJ_B','Test Project B','OM_B');

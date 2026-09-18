INSERT INTO public.user_permissions (user_id, module_key, action_key, granted, source, granted_at)
SELECT p.id, m.key, a.key, true, 'manual', now()
FROM public.profiles p
CROSS JOIN public.permission_modules m
CROSS JOIN public.permission_actions a
WHERE p.employee_id = '650'
ON CONFLICT DO NOTHING;

UPDATE public.user_permissions up
SET granted = true
FROM public.profiles p
WHERE p.id = up.user_id AND p.employee_id = '650';

INSERT INTO public.user_roles (user_id, role)
SELECT p.id, 'admin'::app_role FROM public.profiles p WHERE p.employee_id = '650'
ON CONFLICT DO NOTHING;
import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { supabaseAdmin } from "@/integrations/supabase/client.server";

const Input = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  full_name: z.string().min(1),
  employee_id: z.string().min(1),
  phone: z.string().optional().nullable(),
  department_id: z.string().uuid().optional().nullable(),
  job_title_id: z.string().uuid().optional().nullable(),
});

function authCreateErrorMessage(message?: string) {
  const value = (message ?? "").toLowerCase();
  if (
    value.includes("already") &&
    (value.includes("email") || value.includes("registered"))
  ) {
    return "البريد الإلكتروني مستخدم بالفعل";
  }
  if (value.includes("database error creating new user")) {
    return "تعذر إنشاء ملف المستخدم في قاعدة البيانات. تأكد من تطبيق حزمة Gate 60 ومن عدم تكرار الرقم الوظيفي";
  }
  return message || "ONEXA_ACCOUNTANT_AUTH_CREATE_FAILED";
}

/**
 * Creates the Auth identity with trusted tenant app_metadata from the first
 * write, then activates one accountant membership through the owner-only RPC.
 * A failed activation compensates by deleting the new Auth identity.
 */
export const createWorkspaceAccountantByOwner = createServerFn({
  method: "POST",
})
  .middleware([requireSupabaseAuth])
  .inputValidator((value) => Input.parse(value))
  .handler(async ({ data, context }) => {
    const db = supabaseAdmin as any;
    const { data: owner, error: ownerError } = await db
      .from("onexa_workspace_memberships")
      .select("tenant_id")
      .eq("user_id", context.userId)
      .eq("role_key", "workspace_owner")
      .eq("status", "active")
      .maybeSingle();

    if (ownerError || !owner) {
      throw new Error("ONEXA_WORKSPACE_OWNER_REQUIRED");
    }

    const { data: workspace, error: workspaceError } = await db
      .from("onexa_workspace")
      .select(
        "tenant_id,slug,name_ar,plan_key,status,enabled_modules",
      )
      .eq("tenant_id", owner.tenant_id)
      .eq("status", "active")
      .single();

    if (workspaceError || !workspace) {
      throw new Error("ONEXA_ACTIVE_WORKSPACE_REQUIRED");
    }

    const email = data.email.trim().toLowerCase();
    const employeeId = data.employee_id.trim();

    const [employeeLookup, emailLookup] = await Promise.all([
      db
        .from("profiles")
        .select("id")
        .eq("employee_id", employeeId)
        .maybeSingle(),
      db
        .from("profiles")
        .select("id")
        .eq("email", email)
        .maybeSingle(),
    ]);

    if (employeeLookup.error) {
      throw new Error(employeeLookup.error.message);
    }
    if (emailLookup.error) {
      throw new Error(emailLookup.error.message);
    }
    if (employeeLookup.data) {
      throw new Error("الرقم الوظيفي مستخدم بالفعل");
    }
    if (emailLookup.data) {
      throw new Error("البريد الإلكتروني مستخدم بالفعل");
    }

    let newUserId: string | null = null;

    try {
      const { data: created, error: createError } =
        await supabaseAdmin.auth.admin.createUser({
          email,
          password: data.password,
          email_confirm: true,
          app_metadata: {
            onexa_tenant_id: workspace.tenant_id,
            onexa_tenant_slug: workspace.slug,
            onexa_tenant_name: workspace.name_ar,
            onexa_plan: workspace.plan_key,
            onexa_tenant_status: workspace.status,
            onexa_modules: workspace.enabled_modules,
          },
          user_metadata: {
            full_name: data.full_name.trim(),
            employee_id: employeeId,
            phone: data.phone ?? null,
            department_id: data.department_id ?? null,
            job_title_id: data.job_title_id ?? null,
          },
        });

      if (createError || !created.user) {
        throw new Error(
          authCreateErrorMessage(createError?.message),
        );
      }

      newUserId = created.user.id;

      const { error: membershipError } = await (
        context.supabase as any
      ).rpc("onexa_activate_accountant_user", {
        _target_user_id: newUserId,
      });

      if (membershipError) {
        throw new Error(membershipError.message);
      }

      return {
        id: newUserId,
        tenantId: workspace.tenant_id,
        role: "accountant" as const,
      };
    } catch (error) {
      if (newUserId) {
        await supabaseAdmin.auth.admin.deleteUser(newUserId);
      }
      throw error;
    }
  });

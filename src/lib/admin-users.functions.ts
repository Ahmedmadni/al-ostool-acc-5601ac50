import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { supabaseAdmin } from "@/integrations/supabase/client.server";
import { z } from "zod";

const CreateUserInput = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  full_name: z.string().min(1),
  employee_id: z.string().min(1),
  phone: z.string().optional().nullable(),
  department_id: z.string().uuid().optional().nullable(),
  job_title_id: z.string().uuid().optional().nullable(),
  role: z.string().min(1),
});

function authCreateErrorMessage(message?: string) {
  const value = (message ?? "").toLowerCase();
  if (value.includes("already") && (value.includes("email") || value.includes("registered"))) {
    return "البريد الإلكتروني مستخدم بالفعل";
  }
  if (value.includes("database error creating new user")) {
    return "تعذر إنشاء ملف المستخدم في قاعدة البيانات. تحقق من عدم تكرار الرقم الوظيفي وصحة الإدارة والوظيفة";
  }
  return message || "تعذر إنشاء المستخدم";
}

export const createUserByAdmin = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d) => CreateUserInput.parse(d))
  .handler(async ({ data, context }) => {
    const { userId } = context;
    // Verify caller is admin
    const { data: roleRow } = await supabaseAdmin
      .from("user_roles")
      .select("role")
      .eq("user_id", userId)
      .eq("role", "admin")
      .maybeSingle();
    if (!roleRow) throw new Error("صلاحيات غير كافية");

    const db = supabaseAdmin as any;
    const email = data.email.trim().toLowerCase();
    const employeeId = data.employee_id.trim();
    const [employeeLookup, emailLookup] = await Promise.all([
      db.from("profiles").select("id").eq("employee_id", employeeId).maybeSingle(),
      db.from("profiles").select("id").eq("email", email).maybeSingle(),
    ]);
    if (employeeLookup.error) throw new Error(employeeLookup.error.message);
    if (emailLookup.error) throw new Error(emailLookup.error.message);
    if (employeeLookup.data) throw new Error("الرقم الوظيفي مستخدم بالفعل");
    if (emailLookup.data) throw new Error("البريد الإلكتروني مستخدم بالفعل");

    const { data: created, error } = await supabaseAdmin.auth.admin.createUser({
      email,
      password: data.password,
      email_confirm: true,
      user_metadata: {
        full_name: data.full_name,
        employee_id: data.employee_id,
        phone: data.phone ?? null,
        department_id: data.department_id ?? null,
        job_title_id: data.job_title_id ?? null,
      },
    });
    if (error || !created.user) throw new Error(authCreateErrorMessage(error?.message));

    const newId = created.user.id;
    try {
      const { error: profileError } = await db
        .from("profiles")
        .update({
          full_name: data.full_name.trim(),
          employee_id: employeeId,
          phone: data.phone ?? null,
          department_id: data.department_id ?? null,
          job_title_id: data.job_title_id ?? null,
          status: "active",
          approved_by: userId,
          approved_at: new Date().toISOString(),
        })
        .eq("id", newId);
      if (profileError) throw new Error(profileError.message);

      const { error: deleteRoleError } = await supabaseAdmin.from("user_roles").delete().eq("user_id", newId);
      if (deleteRoleError) throw new Error(deleteRoleError.message);
      const { error: roleError } = await supabaseAdmin
        .from("user_roles")
        .insert({ user_id: newId, role: data.role as any });
      if (roleError) throw new Error(roleError.message);
      return { id: newId };
    } catch (provisionError) {
      await supabaseAdmin.auth.admin.deleteUser(newId);
      throw provisionError;
    }
  });

export const deleteUserByAdmin = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d) => z.object({ user_id: z.string().uuid() }).parse(d))
  .handler(async ({ data, context }) => {
    const { userId } = context;
    const { data: roleRow } = await supabaseAdmin
      .from("user_roles").select("role").eq("user_id", userId).eq("role", "admin").maybeSingle();
    if (!roleRow) throw new Error("صلاحيات غير كافية");
    if (data.user_id === userId) throw new Error("لا يمكنك حذف حسابك");
    const { error } = await supabaseAdmin.auth.admin.deleteUser(data.user_id);
    if (error) throw new Error(error.message);
    return { ok: true };
  });

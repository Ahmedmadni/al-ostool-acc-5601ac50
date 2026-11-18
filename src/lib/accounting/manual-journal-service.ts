import { supabase } from "@/integrations/supabase/client";

export type ManualJournalLineInput = {
  accountCode: string;
  debit: number;
  credit: number;
  description?: string;
  dimensions?: Record<string, string>;
};

export type ManualJournalRow = {
  id: string;
  revision: number;
  legal_entity_id: string;
  branch_id: string;
  external_reference: string | null;
  journal_number: string;
  accounting_date: string;
  period_code: string;
  currency: string;
  memo: string;
  status: string;
  total_debit: number;
  total_credit: number;
  posted_journal_id: string | null;
  created_by: string;
};

export async function createManualJournal(input: {
  legalEntityId: string;
  branchId: string;
  accountingDate: string;
  periodCode: string;
  currency: string;
  memo: string;
  externalReference?: string;
  lines: ManualJournalLineInput[];
}) {
  const db = supabase as any;
  const { data, error } = await db.rpc("onexa_create_manual_journal", {
    _legal_entity_id: input.legalEntityId,
    _branch_id: input.branchId,
    _accounting_date: input.accountingDate,
    _period_code: input.periodCode,
    _currency: input.currency,
    _memo: input.memo,
    _external_reference: input.externalReference || null,
    _lines: input.lines.map((line, index) => ({
      line_number: index + 1,
      account_code: line.accountCode,
      debit: line.debit,
      credit: line.credit,
      description: line.description || null,
      dimensions: line.dimensions ?? {},
    })),
  });
  if (error) throw new Error(error.message || "ONEXA_MANUAL_JOURNAL_CREATE_FAILED");
  if (typeof data !== "string" || !data) throw new Error("ONEXA_MANUAL_JOURNAL_INVALID_RESPONSE");
  return data;
}

/**
 * Read the existing draft through tenant-scoped RLS. The amendment RPC
 * re-checks identity, creator, revision, status, amounts and accounts.
 */
export async function loadEditableManualJournal(id: string): Promise<{
  journal: ManualJournalRow;
  lines: {
    line_number: number;
    account_code: string;
    debit: number;
    credit: number;
    description: string | null;
    dimensions: Record<string, string>;
  }[];
  latestRejectionReason: string | null;
}> {
  const db = supabase as any;
  const { data: journal, error: headerError } = await db.from("onexa_manual_journals")
    .select("id,revision,legal_entity_id,branch_id,external_reference,journal_number,accounting_date,period_code,currency,memo,status,total_debit,total_credit,posted_journal_id,created_by")
    .eq("id", id).single();
  if (headerError || !journal) throw new Error(headerError?.message || "ONEXA_MANUAL_JOURNAL_NOT_FOUND");
  if (!["draft", "rejected"].includes(journal.status)) {
    throw new Error("لا يمكن تعديل قيد بعد إرساله للاعتماد أو ترحيله");
  }
  const [lines, rejection] = await Promise.all([
    db.from("onexa_manual_journal_lines")
      .select("line_number,account_code,debit,credit,description,dimensions")
      .eq("manual_journal_id", id).order("line_number", { ascending: true }),
    db.from("onexa_manual_journal_events")
      .select("reason").eq("manual_journal_id", id)
      .eq("to_status", "rejected").order("id", { ascending: false }).limit(1),
  ]);
  if (lines.error || rejection.error) {
    throw new Error(lines.error?.message || rejection.error?.message || "ONEXA_MANUAL_JOURNAL_EDIT_READ_FAILED");
  }
  if (!lines.data || lines.data.length < 2) {
    throw new Error("ONEXA_MANUAL_JOURNAL_REQUIRES_TWO_LINES");
  }
  return {
    journal: journal as ManualJournalRow,
    lines: lines.data,
    latestRejectionReason: rejection.data?.[0]?.reason ?? null,
  };
}

/**
 * Save one atomic revision, after optimistic concurrency and maker checks.
 * Original journal ID and date/period/entity/branch/currency never change.
 */
export async function amendManualJournal(input: {
  journalId: string;
  expectedRevision: number;
  memo: string;
  externalReference?: string;
  lines: ManualJournalLineInput[];
}): Promise<number> {
  const db = supabase as any;
  const { data, error } = await db.rpc("onexa_amend_manual_journal", {
    _journal_id: input.journalId,
    _expected_revision: input.expectedRevision,
    _memo: input.memo,
    _external_reference: input.externalReference || null,
    _lines: input.lines.map((line, index) => ({
      line_number: index + 1,
      account_code: line.accountCode,
      debit: line.debit,
      credit: line.credit,
      description: line.description || null,
      dimensions: line.dimensions ?? {},
    })),
  });
  if (error) throw new Error(error.message || "ONEXA_MANUAL_JOURNAL_AMEND_FAILED");
  if (!Number.isSafeInteger(data) || data !== input.expectedRevision + 1) {
    throw new Error("ONEXA_MANUAL_JOURNAL_AMEND_INVALID_RESPONSE");
  }
  return data;
}

export async function transitionManualJournal(id: string, status: "submitted" | "approved" | "rejected" | "cancelled" | "draft", reason?: string) {
  const db = supabase as any;
  const { data, error } = await db.rpc("onexa_transition_manual_journal", {
    _journal_id: id,
    _to_status: status,
    _reason: reason || null,
  });
  if (error) throw new Error(error.message || "ONEXA_MANUAL_JOURNAL_TRANSITION_FAILED");
  return data as string;
}

export async function postManualJournal(id: string) {
  const db = supabase as any;
  const { data, error } = await db.rpc("onexa_post_manual_journal", { _journal_id: id });
  if (error) throw new Error(error.message || "ONEXA_MANUAL_JOURNAL_POST_FAILED");
  if (typeof data !== "string" || !data) throw new Error("ONEXA_MANUAL_JOURNAL_POST_INVALID_RESPONSE");
  return data;
}

export async function listManualJournals(limit = 100): Promise<ManualJournalRow[]> {
  const db = supabase as any;
  const { data, error } = await db.from("onexa_manual_journals")
    .select("id,revision,legal_entity_id,branch_id,external_reference,journal_number,accounting_date,period_code,currency,memo,status,total_debit,total_credit,posted_journal_id,created_by")
    .order("accounting_date", { ascending: false })
    .limit(Math.min(Math.max(limit, 1), 500));
  if (error) throw new Error(error.message || "ONEXA_MANUAL_JOURNAL_LIST_FAILED");
  return (data ?? []) as ManualJournalRow[];
}

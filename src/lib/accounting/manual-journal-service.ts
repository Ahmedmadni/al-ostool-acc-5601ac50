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
    .select("id,journal_number,accounting_date,period_code,currency,memo,status,total_debit,total_credit,posted_journal_id,created_by")
    .order("accounting_date", { ascending: false })
    .limit(Math.min(Math.max(limit, 1), 500));
  if (error) throw new Error(error.message || "ONEXA_MANUAL_JOURNAL_LIST_FAILED");
  return (data ?? []) as ManualJournalRow[];
}

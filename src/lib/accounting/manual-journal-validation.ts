/**
 * Browser-side journal preflight; the Gate 58 PostgreSQL RPC remains authoritative.
 * Monetary totals are evaluated in exact 1/10,000 units to avoid IEEE 754 drift.
 */
export type ManualJournalDraftLine = {
  accountCode: string;
  debit: string;
  credit: string;
  description: string;
};

export type ManualJournalDraft = {
  legalEntityId: string;
  branchId: string;
  entityIds: string[];
  branchIdsForEntity: string[];
  accountCodes: string[];
  accountingDate: string;
  currency: string;
  memo: string;
  lines: ManualJournalDraftLine[];
};

export type ValidatedManualJournalLine = {
  accountCode: string;
  debit: number;
  credit: number;
  description: string;
};

export type ManualJournalValidation = {
  valid: boolean;
  errors: string[];
  totalDebit: string;
  totalCredit: string;
  difference: string;
  normalizedLines: ValidatedManualJournalLine[];
};

const UNITS_PER_CURRENCY = 10_000n;
const MAX_SAFE_UNITS = BigInt(Number.MAX_SAFE_INTEGER);

function currencyPrecision(currency: string): number {
  try {
    const precision = new Intl.NumberFormat("en-US", {
      style: "currency",
      currency,
    }).resolvedOptions().maximumFractionDigits ?? 2;
    return Math.min(Math.max(precision, 0), 4);
  } catch {
    return 2;
  }
}

function parseDecimalUnits(raw: string, precision: number): bigint | null {
  const text = raw.trim();
  if (!text) return 0n;
  if (!/^\d+(?:\.\d+)?$/.test(text)) return null;
  const [whole, decimal = ""] = text.split(".");
  if (decimal.length > precision) return null;
  const units = BigInt(whole) * UNITS_PER_CURRENCY + BigInt((decimal + "0000").slice(0, 4));
  return units <= MAX_SAFE_UNITS ? units : null;
}

function formatUnits(units: bigint, precision: number): string {
  const absolute = units < 0n ? -units : units;
  const whole = (absolute / UNITS_PER_CURRENCY).toString();
  const fractional = (absolute % UNITS_PER_CURRENCY).toString().padStart(4, "0").slice(0, precision);
  return (units < 0n ? "-" : "") + whole + (precision ? "." + fractional : "");
}

function validDate(date: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return false;
  const parsed = new Date(date + "T00:00:00.000Z");
  return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === date;
}

/**
 * For UI feedback only. Never grant permission or write ledger records based
 * on this result; the tenant-scoped database functions repeat all checks.
 */
export function evaluateManualJournalDraft(draft: ManualJournalDraft): ManualJournalValidation {
  const errors: string[] = [];
  const precision = currencyPrecision(draft.currency);
  const entitySet = new Set(draft.entityIds);
  const branchSet = new Set(draft.branchIdsForEntity);
  const accountSet = new Set(draft.accountCodes);
  if (!draft.legalEntityId || !entitySet.has(draft.legalEntityId)) errors.push("اختر كيانًا قانونيًا متاحًا");
  if (!draft.branchId || !branchSet.has(draft.branchId)) errors.push("اختر فرعًا يتبع الكيان المحدد");
  if (!validDate(draft.accountingDate)) errors.push("أدخل تاريخ قيد صحيحًا");
  if (!/^[A-Z]{3}$/.test(draft.currency)) errors.push("عملة القيد غير صحيحة");
  if (!draft.memo.trim()) errors.push("بيان القيد مطلوب");
  if (draft.lines.length < 2) errors.push("القيد يتطلب سطرين على الأقل");

  let debitTotal = 0n;
  let creditTotal = 0n;
  const normalized: ValidatedManualJournalLine[] = [];
  draft.lines.forEach((line, index) => {
    const debit = parseDecimalUnits(line.debit, precision);
    const credit = parseDecimalUnits(line.credit, precision);
    if (!line.accountCode.trim() || !accountSet.has(line.accountCode)) {
      errors.push("اختر حسابًا تفصيليًا متاحًا للسطر " + (index + 1));
    }
    if (debit === null || credit === null) {
      errors.push("مبلغ غير صالح في السطر " + (index + 1) + "؛ الحد الأقصى " + precision + " منازل عشرية");
      return;
    }
    if ((debit > 0n) === (credit > 0n)) {
      errors.push("حدد مبلغًا موجبًا في جانب واحد فقط بالسطر " + (index + 1));
    }
    debitTotal += debit;
    creditTotal += credit;
    normalized.push({
      accountCode: line.accountCode.trim(),
      debit: Number(debit) / Number(UNITS_PER_CURRENCY),
      credit: Number(credit) / Number(UNITS_PER_CURRENCY),
      description: line.description.trim(),
    });
  });
  if (debitTotal === 0n || creditTotal === 0n) errors.push("يجب أن يكون إجمالي القيد أكبر من صفر");
  if (debitTotal !== creditTotal) errors.push("إجمالي المدين والدائن غير متساويين");
  if (debitTotal > MAX_SAFE_UNITS || creditTotal > MAX_SAFE_UNITS) {
    errors.push("قيمة القيد تتجاوز نطاق الدقة الآمنة");
  }
  const valid = errors.length === 0;
  const diff = debitTotal >= creditTotal ? debitTotal - creditTotal : creditTotal - debitTotal;
  return {
    valid,
    errors,
    totalDebit: formatUnits(debitTotal, precision),
    totalCredit: formatUnits(creditTotal, precision),
    difference: formatUnits(diff, precision),
    normalizedLines: valid ? normalized : [],
  };
}

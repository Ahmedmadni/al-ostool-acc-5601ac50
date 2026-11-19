/**
 * Client-side fail-closed preview of the shared B4 monetary contract.
 * Numeric UI inputs are NOT authoritative: PostgreSQL must re-validate
 * approved sources, line-level amounts, tenant, role and fiscal period.
 *
 * Never round a draft amount silently. If a caller combines floats into a
 * sub-halalah remainder, it must resolve the source precision explicitly.
 */
export function inspectPostingMoneyTotals(
  debit: number,
  credit: number,
  currency: string,
): string[] {
  if (!Number.isFinite(debit) || !Number.isFinite(credit)) {
    return ["finite_totals_required"];
  }
  if (debit <= 0 || credit <= 0) {
    return ["positive_totals_required"];
  }

  const parse = (value: number): { units: bigint | null; error: string | null } => {
    if (!Number.isSafeInteger(Math.trunc(value))) {
      return { units: null, error: "unsafe_money_number" };
    }
    const raw = String(value);
    const match = /^(0|[1-9]\d*)(?:\.(\d+))?$/.exec(raw);
    if (!match) return { units: null, error: "money_decimal_format_invalid" };

    const fraction = match[2] ?? "";
    if (fraction.length > 4) {
      return { units: null, error: "money_storage_precision_invalid" };
    }
    if (currency === "SAR" && fraction.length > 2) {
      return { units: null, error: "sar_halalah_precision_invalid" };
    }
    return {
      units: BigInt(match[1]) * 10000n + BigInt(fraction.padEnd(4, "0")),
      error: null,
    };
  };

  const d = parse(debit);
  const c = parse(credit);
  const errors = [...new Set([d.error, c.error].filter(
    (error): error is string => Boolean(error),
  ))];

  if (!errors.length && d.units !== c.units) {
    errors.push("journal_must_balance");
  }
  return errors;
}

# Accounting workspace experience

Gate 46 turns the financial-analysis landing page into a working accounting workspace.

## Live snapshot

The page reads existing accounting sources to present:

- latest balance for each bank account and the combined cash position
- receivables from the latest aging period
- supplier payables from the latest supplier-balance period
- chart-of-accounts size
- trial-balance debit, credit, difference, and balance status

## Interaction model

A persistent accounting navigation card keeps the main financial tasks visible. The workspace presents one primary action per empty state and uses the shared ONEXA line-icon, spacing, card, and selection rules introduced in Gate 44.

No new database object or production migration is required.

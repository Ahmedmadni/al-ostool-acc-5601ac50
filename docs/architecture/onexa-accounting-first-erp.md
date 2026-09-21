# ONEXA Accounting-First ERP

## Target operating model

ONEXA is a transaction system first and an import tool second. Every enabled module can create native business documents, approve them through a controlled workflow, expose its own operational reports, and send only an approved financial effect to General Ledger. Excel remains a governed `origin = import` channel with batch lineage; it is never the accounting source of truth.

The shared lifecycle is:

`draft → submitted → approved → posted → reversed`

- The operating module owns entry, quantities, prices, party, warehouse, project, employee, asset, and evidence.
- A different user approves the document; the creator cannot approve their own document.
- Approval makes the document available for accounting review.
- The accountant posts a balanced journal through `onexa_post_journal`; posted documents and journals are immutable.
- Correction is a linked reversal and a new revision, never an edit or delete.

## Module integration map

| Owning module | Native source documents | Operational effect | General Ledger control accounts | Reports remain in |
|---|---|---|---|---|
| Sales & Customers | Sales invoice, customer receipt | Customer balance; item issue for stocked sales | Accounts receivable, revenue, output VAT, cash/bank | Sales & Customers |
| Procurement & Suppliers | Purchase invoice, supplier payment | Supplier balance; item receipt or asset/cost acquisition | Accounts payable, input VAT, inventory/expense/asset, cash/bank | Procurement & Suppliers |
| Inventory | Receipt, issue | Quantity and value by item/warehouse | Inventory, GRNI, COGS/project/expense | Inventory & Warehouses |
| People & Payroll | Payroll run | Employee payable, deductions, department/project cost | Payroll expense, employee payable, payroll liabilities | People & Payroll |
| Fixed Assets | Acquisition, depreciation run | Asset cost, useful life, accumulated depreciation | Asset cost, depreciation expense, accumulated depreciation | Fixed Assets |
| Projects & Operations | Project cost, work-order cost | Cost by project/contract/work order | WIP or expense, clearing/source accounts | Projects & Operations |
| Facilities & Real Estate | Lease invoice, lease receipt | Tenant/property/contract balance | Accounts receivable, rental revenue, VAT, cash/bank | Facilities & Real Estate |
| Fleet & Logistics | Trip cost, fuel issue | Vehicle/trip/fuel quantity and cost | Fleet/project expense, inventory/payable/cash | Fleet & Logistics |
| Finance & Treasury | Bank transfer | Bank and cash position | Source and destination bank accounts | Finance & Treasury |

## Reports ownership

Each report has one owning module and explicit source-document lineage. The module presents its detailed reports inside its own navigation. Executive Management contains the consolidated Reports Center, which reads the same governed catalogue across enabled modules; it does not create a second reporting source.

This preserves both requirements:

1. A module can operate and report independently.
2. Executive Management can retrieve consolidated reports without opening every module.

## Gate 34 foundation

The Gate 34 migration adds a tenant-scoped business-document registry, document lines, atomic numbering, workflow transitions, immutable state guards, audit events, import lineage, and a security-invoker module summary view. RLS derives tenant identity only from server-controlled `app_metadata.onexa_tenant_id`.

The public creation RPC validates entity, branch, subscription entitlement, document-to-module ownership, totals, and line totals in one database transaction. Direct document creation is not granted to authenticated clients. Status transitions must use the workflow RPC, and creator/approver separation is enforced in the database.

Approved documents that have no journal appear in `onexa_accounting_inbox`. This is the accountant's governed work queue across all modules; it does not permit bypassing posting validation or writing directly to journal tables.

The existing B4 journal foundation remains the only posting path. Gate 34 deliberately does not recreate ledger tables or bypass `onexa_post_journal`.

## Deployment dependencies

- B2: complete tenant-isolation acceptance against every referenced legacy table.
- B3: connect workflow transitions and posting actions to production permission helpers/approval limits.
- B9: run final security, idempotency, concurrency, reversal, close-period, and reconciliation acceptance.

The next vertical slice should implement sales invoice → stock issue/valuation → customer control account → journal posting → AR/inventory/GL reconciliation before repeating the pattern for procurement, payroll, and assets.

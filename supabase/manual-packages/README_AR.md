# تشغيل Gate 34 إلى Gate 38 يدويًا

## قبل البدء

1. تأكد أنك داخل مشروع Supabase الصحيح الخاص بـ ONEXA.
2. خذ نسخة احتياطية أو Export حديثًا قبل أي تعديل.
3. افتح **SQL Editor** وأنشئ Query جديدة لكل ملف؛ لا تجمع الملفات كلها في تشغيل واحد.
4. اترك مفاتيح التشغيل `VITE_ENABLE_ONEXA_POSTING` و`VITE_ENABLE_ONEXA_SALES_POSTING` مغلقة.
5. اترك `VITE_ENABLE_ONEXA_PROCUREMENT_POSTING` مغلقًا حتى اكتمال فحص Gate 36.
6. اترك `VITE_ENABLE_ONEXA_PAYROLL_POSTING` و`VITE_ENABLE_ONEXA_ASSET_POSTING` مغلقين حتى نجاح فحوص Gate 37 وGate 38.

## الترتيب الإلزامي

### 0 — الفحص التمهيدي

نفّذ `00_onexa_gate34_35_preflight.sql`.

يجب أن تكون الجداول الأساسية الثلاثة `ready`، ويجب أن يظهر فحص `onexa_post_journal` بحالة `ready`. يجب أيضًا أن تكون كل الأعمدة المطلوبة `ready`.

إذا ظهر `signature_mismatch_or_missing` أو أي `missing`، توقف ولا تنفذ الملفات التالية. انسخ كامل النتائج لإعادة تكييف الحزمة مع مخطط الإنتاج الفعلي.

### 1 — Gate 34

نفّذ الملف:

`../migrations/202609200001_onexa_business_document_foundation.sql`

النتيجة المتوقعة: `Success. No rows returned`، لأن الملف ينشئ أساس مستندات الأعمال وسير الاعتماد والتدقيق وصندوق المحاسب داخل معاملة واحدة.

### 2 — Gate 35

قبل Gate 35 نفّذ `02_onexa_b2_b3_discovery.sql`. هذا فحص قراءة فقط لاكتشاف مخطط العضويات والأدوار وسياسات عزل المستأجرين الفعلية، ومن نتيجته تُبنى حزمتا B2 وB3 دون افتراض أسماء جداول أو أعمدة الإنتاج.

نفّذ الملف:

`gate35_sales_inventory_posting.sql`

النتيجة المتوقعة: `Success. No rows returned`. ستُنشأ جداول المخزون وحركاته وتقارير المطابقة ودالة ترحيل فاتورة البيع، مع إعادة استخدام جدول خرائط الحسابات الحالي `onexa_account_role_mappings`.

يتطلب الملف اكتمال B3 أولًا. بعده تكون دالة `onexa_post_sales_invoice` متاحة للمستخدم المسجل، لكنها ترفض التنفيذ داخل قاعدة البيانات ما لم يكن دوره مخولًا بترحيل المبيعات.

### 3 — فحص ما بعد التنفيذ

نفّذ `03_onexa_gate34_35_postcheck.sql`.

المتوقع:

- جميع الكائنات `ready`.
- RLS لجميع الجداول `enabled`.
- جميع الـ Views بحالة `security_invoker`.
- `anon_can_execute = false` لكل الدوال الحساسة.
- `authenticated_can_execute = true` و`anon_can_execute = false` لدالة `onexa_post_sales_invoice` بعد B3.
- ظهور خمسة حسابات ناقصة لكل كيان قانوني داخل `onexa_sales_posting_configuration_gaps` إلى أن نربط دليل الحسابات الفعلي.

## ما ترسله بعد التنفيذ

أرسل نتيجة ملف `00` أولًا. وبعد نجاح Gate 34 وGate 35 أرسل نتائج ملف `03`، خصوصًا:

1. توقيع `onexa_post_journal`.
2. جدول حالة الكائنات وRLS.
3. صلاحيات الدوال.
4. قائمة `onexa_sales_posting_configuration_gaps`.

بعدها يتم تجهيز كود ربط أرقام الحسابات الحقيقية، ثم B3، ثم اختبار فاتورة بيع تجريبية وترحيلها وعكسها.

## Gate 36 — المشتريات والموردون

بعد نجاح Gate 35 وربط حسابات المبيعات، نفّذ بالترتيب في Queries منفصلة:

1. `gate36_procurement_inventory_posting.sql`
2. `gate36_postcheck.sql`
3. `gate36_aoa_account_mapping.sql`
4. أعد تنفيذ `gate36_postcheck.sql` وتأكد من عدم وجود فجوات حسابية.
5. `gate36_purchase_posting_smoke_test_rollback.sql`

النتيجة النهائية المتوقعة من اختبار الدخان:

`gate36_purchase_posting_smoke_test | passed`

الاختبار ينشئ فاتورة مورد مؤقتة تشمل مخزونًا ومصروفًا وأصلًا ثابتًا، ويتحقق من القيد والاستلام والتصنيف ثم ينفذ `ROLLBACK`؛ لا تبقى أي بيانات تجريبية. لا تفعّل `VITE_ENABLE_ONEXA_PROCUREMENT_POSTING=true` قبل نجاحه.

## Gate 37 — الرواتب والحسابات العامة

نفّذ كل ملف في Query مستقلة وبالترتيب:

1. `gate37_payroll_gl_posting.sql`
2. `gate37_postcheck.sql`
3. `gate37_aoa_account_mapping.sql`
4. أعد تنفيذ `gate37_postcheck.sql` وتأكد من عدم وجود فجوات حسابية.
5. تأكد أن لديك مسيرًا معتمدًا تمت مزامنته مع دفتر التكاليف ومستخدمًا ماليًا مختلفًا عن منشئ المسير.
6. `gate37_payroll_posting_smoke_test_rollback.sql`

النتيجة المتوقعة: `gate37_payroll_posting_smoke_test | passed` ثم `ROLLBACK`.
لا تفعّل `VITE_ENABLE_ONEXA_PAYROLL_POSTING=true` قبل نجاح الفحص والاختبار.


## Gate 38 — الأصول الثابتة والإهلاك

Gate 36 يرحّل تكلفة اقتناء الأصل المصنّفة داخل فاتورة المورد، لذلك لا تعِد ترحيل
تكلفة الاقتناء في Gate 38. هذه الحزمة تضبط سجل الأصل وترحّل الإهلاك اللاحق فقط.

نفّذ كل ملف في Query مستقلة وبالترتيب:

1. `gate38_fixed_assets_gl_posting.sql`
2. `gate38_postcheck.sql`
3. حدّد `legal_entity_id` و`branch_id` لكل أصل، وأكمل `salvage_value` و`useful_life_years` و`depreciation_start_date`.
4. راجع نتائج المطابقة؛ يجب ألا توجد حالات `register_mismatch`.
5. `gate38_aoa_account_mapping.sql`
6. أعد تنفيذ `gate38_postcheck.sql` وتأكد من عدم وجود فجوات حسابية.
7. تأكد من وجود أصل واحد على الأقل بحالة `ready` ومستخدم مالي مختلف عن مستورد الأصل.
8. `gate38_asset_depreciation_smoke_test_rollback.sql`

النتيجة المتوقعة:

`gate38_asset_depreciation_smoke_test | passed`

ثم ينفذ الاختبار `ROLLBACK` ولا يترك قيدًا أو إهلاكًا تجريبيًا. لا تفعّل
`VITE_ENABLE_ONEXA_ASSET_POSTING=true` قبل نجاح الفحص والاختبار.

## Gate 39 — تحصيلات ONEXA والذمم المدينة

لا تُرحّل سجلات التحصيلات القديمة من جدول `payments` مرة ثانية. أنشئ مستند `customer_receipt` من شاشة ONEXA بعد ترحيل فاتورة المبيعات واعتمده بمستخدم مختلف.

بعد السماح بتغييرات قاعدة الإنتاج والفحص التمهيدي والنسخة الاحتياطية، شغّل الملفات كلًا على حدة:

1. `gate39_customer_receipts.sql`
2. `gate39_postcheck.sql`
3. افتح `gate39_aoa_account_mapping.sql`، راجع كشف حسابات الأصول، واختر حساب النقد أو البنك التفصيلي الحقيقي بدل القيمة `REPLACE_WITH_CONFIRMED_CASH_OR_BANK_DETAIL_CODE` ثم شغّل الملف.
4. أعد `gate39_postcheck.sql` وتأكد من خلو فجوات الحسابات وعدم وجود أرصدة سالبة.
5. أنشئ سند تحصيل ONEXA معتمدًا مرتبطًا بفاتورة مرحلة، ثم شغّل `gate39_receipt_smoke_test_rollback.sql`. المتوقع `gate39_customer_receipt_smoke_test | passed` ويُنفذ ROLLBACK.

اترك `VITE_ENABLE_ONEXA_CUSTOMER_RECEIPT_POSTING` مغلقًا حتى نجاح كل الفحوص. لا تطبّق SQL تلقائيًا على الإنتاج.

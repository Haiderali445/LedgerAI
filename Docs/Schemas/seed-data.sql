BEGIN;

-- 1. Master Tenant & Transaction-Scoped RLS Context
INSERT INTO public.tenants (
    id, tenant_code, business_name, domain_slug, whats_app_phone_number_id,
    ntn_no, strn_no, currency_code, is_active, created_at
)
VALUES (
    '11111111-1111-4111-8111-111111111111',
    'MASTER-PKR',
    'LedgerAI Master Wholesale',
    'master-pkr',
    NULL,
    NULL,
    NULL,
    'PKR',
    TRUE,
    TIMESTAMPTZ '2026-11-01 09:00:00+00'
)
ON CONFLICT (id) DO NOTHING;

SELECT set_config('app.current_tenant', '11111111-1111-4111-8111-111111111111', true);

-- 2. Master Users (Owner, Admin, Operator)
INSERT INTO public.users (
    id, tenant_id, user_code, full_name, email, password_hash, role, is_active, created_at
)
VALUES
    (
        md5('user:owner')::uuid,
        '11111111-1111-4111-8111-111111111111',
        'OWNER-001',
        'Master Owner',
        'owner@ledgerai.local',
        'AQAAAAEAACcQAAAAEPlaceholderSeedHashOwner2026==',
        'Owner',
        TRUE,
        TIMESTAMPTZ '2026-11-01 09:00:00+00'
    ),
    (
        md5('user:ADMIN-001')::uuid,
        '11111111-1111-4111-8111-111111111111',
        'ADMIN-001',
        'Master Admin',
        'admin@ledgerai.local',
        'AQAAAAEAACcQAAAAEPlaceholderSeedHashAdmin2026==',
        'Admin',
        TRUE,
        TIMESTAMPTZ '2026-11-01 09:00:00+00'
    ),
    (
        md5('user:OPERATOR-001')::uuid,
        '11111111-1111-4111-8111-111111111111',
        'OPERATOR-001',
        'Warehouse Operator',
        'operator@ledgerai.local',
        'AQAAAAEAACcQAAAAEPlaceholderSeedHashOperator2026==',
        'Operator',
        TRUE,
        TIMESTAMPTZ '2026-11-01 09:00:00+00'
    )
ON CONFLICT (id) DO NOTHING;

-- 3. Categories & Units of Measure
INSERT INTO public.categories (
    id, tenant_id, name, description, is_active, created_at
)
VALUES (
    md5('category:BAGS')::uuid,
    '11111111-1111-4111-8111-111111111111',
    'BAGS',
    'Wholesale Bags',
    TRUE,
    TIMESTAMPTZ '2026-11-01 09:00:00+00'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.units_of_measure (
    id, tenant_id, unit_code, name, allow_fractional, aliases, is_active, created_at
)
VALUES
    (
        md5('uom:BORI')::uuid,
        '11111111-1111-4111-8111-111111111111',
        'BORI',
        'Bori',
        TRUE,
        '["bori","ٹھھیلی"]'::jsonb,
        TRUE,
        TIMESTAMPTZ '2026-11-01 09:00:00+00'
    ),
    (
        md5('uom:KG')::uuid,
        '11111111-1111-4111-8111-111111111111',
        'KG',
        'Kilogram',
        TRUE,
        '["kg","کلو"]'::jsonb,
        TRUE,
        TIMESTAMPTZ '2026-11-01 09:00:00+00'
    )
ON CONFLICT (id) DO NOTHING;

-- 4. Warehouse, Product & Stock Batch
INSERT INTO public.warehouses (
    id, tenant_id, warehouse_code, name, address, is_active, created_at
)
VALUES (
    md5('warehouse:main')::uuid,
    '11111111-1111-4111-8111-111111111111',
    'WH-MAIN',
    'Main Faisalabad Warehouse',
    'Faisalabad Wholesale Market',
    TRUE,
    TIMESTAMPTZ '2026-11-01 09:00:00+00'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.products (
    id, tenant_id, product_code, name, category_id, base_unit_id, secondary_unit_id,
    pack_size, barcode, default_purchase_price, weighted_avg_cost, default_sales_price,
    minimum_stock, is_service, is_active, is_deleted, attributes, created_at, updated_at
)
VALUES (
    md5('product:rice-super')::uuid,
    '11111111-1111-4111-8111-111111111111',
    'RICE-SUPER',
    'Super Basmati Rice',
    md5('category:BAGS')::uuid,
    md5('uom:KG')::uuid,
    md5('uom:BORI')::uuid,
    50.0000,
    'PK-RICE-001',
    15500.0000,
    15500.0000,
    17000.0000,
    100.0000,
    FALSE,
    TRUE,
    FALSE,
    '{"aliases":["super basmati","rice","چاول"]}'::jsonb,
    TIMESTAMPTZ '2026-11-01 09:00:00+00',
    TIMESTAMPTZ '2026-11-01 09:00:00+00'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.stock_batches (
    id, tenant_id, warehouse_id, product_id, batch_code, unit_cost,
    quantity_on_hand, quantity_reserved, manufactured_at, expires_at, created_at
)
VALUES (
    md5('batch:rice-2026-a')::uuid,
    '11111111-1111-4111-8111-111111111111',
    md5('warehouse:main')::uuid,
    md5('product:rice-super')::uuid,
    'RICE-2026-A',
    15500.0000,
    500.0000,
    0.0000,
    DATE '2026-10-15',
    DATE '2027-12-31',
    TIMESTAMPTZ '2026-11-01 09:00:00+00'
)
ON CONFLICT (id) DO NOTHING;

-- 5. Accounts (Customer, Supplier, Transporter)
INSERT INTO public.accounts (
    id, tenant_id, account_code, account_type, name, mobile_no, address,
    opening_balance, opening_balance_type, current_balance, credit_limit,
    reserved_credit, risk_tier, is_active, is_deleted, metadata, created_by, created_at
)
VALUES
    (
        md5('account:customer')::uuid,
        '11111111-1111-4111-8111-111111111111',
        'CUST-001',
        'CUSTOMER',
        'Al-Rehman Traders',
        '03001234567',
        'Karkhana Bazaar, Faisalabad',
        10000.0000,
        'DR',
        90000.0000,
        250000.0000,
        0.0000,
        'MEDIUM',
        TRUE,
        FALSE,
        '{"seed":true}'::jsonb,
        md5('user:owner')::uuid,
        TIMESTAMPTZ '2026-11-01 09:00:00+00'
    ),
    (
        md5('account:supplier')::uuid,
        '11111111-1111-4111-8111-111111111111',
        'SUP-001',
        'SUPPLIER',
        'Punjab Rice Mills',
        '03007654321',
        NULL,
        0.0000,
        'CR',
        0.0000,
        500000.0000,
        0.0000,
        'LOW',
        TRUE,
        FALSE,
        '{"seed":true}'::jsonb,
        md5('user:owner')::uuid,
        TIMESTAMPTZ '2026-11-01 09:00:00+00'
    ),
    (
        md5('account:transporter')::uuid,
        '11111111-1111-4111-8111-111111111111',
        'TRANS-001',
        'TRANSPORTER',
        'FastLine Transport',
        '03111111111',
        NULL,
        0.0000,
        NULL,
        0.0000,
        100000.0000,
        0.0000,
        'LOW',
        TRUE,
        FALSE,
        '{"seed":true}'::jsonb,
        md5('user:owner')::uuid,
        TIMESTAMPTZ '2026-11-01 09:00:00+00'
    )
ON CONFLICT (id) DO NOTHING;

-- 6. Order, Order Item & Stock Reservation
INSERT INTO public.orders (
    id, tenant_id, order_code, account_id, order_status, payment_terms,
    total_amount, upfront_paid_amount, ai_confidence_score, requires_approval,
    approval_reason, approved_by, approved_at, idempotency_key,
    raw_intent_summary, execution_metadata, created_by, committed_at, created_at
)
VALUES (
    md5('order:seed-001')::uuid,
    '11111111-1111-4111-8111-111111111111',
    'ORD-2026-001',
    md5('account:customer')::uuid,
    'COMMITTED',
    'CREDIT',
    85000.0000,
    10000.0000,
    0.9500,
    FALSE,
    NULL,
    NULL,
    NULL,
    'seed-order-001',
    '10 bori super basmati rice',
    '{"seed":true}'::jsonb,
    md5('user:owner')::uuid,
    TIMESTAMPTZ '2026-11-01 09:00:00+00',
    TIMESTAMPTZ '2026-11-01 09:00:00+00'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.order_items (
    id, tenant_id, order_id, product_id, warehouse_id, batch_id,
    ordered_unit_id, ordered_quantity, ordered_unit_price, conversion_factor,
    base_quantity, unit_cost_at_sale, created_at
)
VALUES (
    md5('order-item:seed-001')::uuid,
    '11111111-1111-4111-8111-111111111111',
    md5('order:seed-001')::uuid,
    md5('product:rice-super')::uuid,
    md5('warehouse:main')::uuid,
    md5('batch:rice-2026-a')::uuid,
    md5('uom:BORI')::uuid,
    10.0000,
    8500.0000,
    50.000000,
    500.0000,
    15500.0000,
    TIMESTAMPTZ '2026-11-01 09:00:00+00'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.stock_reservations (
    id, tenant_id, order_id, order_item_id, warehouse_id, product_id, batch_id,
    reserved_quantity, released_quantity, committed_quantity, status, created_at, updated_at
)
VALUES (
    md5('reservation:seed-001')::uuid,
    '11111111-1111-4111-8111-111111111111',
    md5('order:seed-001')::uuid,
    md5('order-item:seed-001')::uuid,
    md5('warehouse:main')::uuid,
    md5('product:rice-super')::uuid,
    md5('batch:rice-2026-a')::uuid,
    500.0000,
    0.0000,
    500.0000,
    'COMMITTED',
    TIMESTAMPTZ '2026-11-01 09:00:00+00',
    TIMESTAMPTZ '2026-11-01 09:00:00+00'
)
ON CONFLICT (id) DO NOTHING;

-- 7. Invoice, Invoice Item, Invoice Charge & Stock Movements
INSERT INTO public.invoices (
    id, tenant_id, invoice_type, invoice_number, order_id, account_id,
    warehouse_id, transporter_account_id, bilty_number, invoice_status,
    subtotal_amount, discount_amount, tax_amount, grand_total, amount_paid,
    due_date, idempotency_key, notes, issued_by, issued_at, created_at
)
VALUES (
    md5('invoice:sale-001')::uuid,
    '11111111-1111-4111-8111-111111111111',
    'SALE',
    '01-2026-001',
    md5('order:seed-001')::uuid,
    md5('account:customer')::uuid,
    md5('warehouse:main')::uuid,
    md5('account:transporter')::uuid,
    'BLT-2026-001',
    'ISSUED',
    85000.0000,
    0.0000,
    0.0000,
    90000.0000,
    10000.0000,
    DATE '2026-12-01',
    'seed-invoice-001',
    'Initial seeded sale invoice',
    md5('user:owner')::uuid,
    TIMESTAMPTZ '2026-11-01 09:00:00+00',
    TIMESTAMPTZ '2026-11-01 09:00:00+00'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.invoice_items (
    id, tenant_id, invoice_id, order_item_id, warehouse_id, product_id, batch_id,
    unit_id, quantity, unit_price, discount_amount, tax_rate, tax_amount,
    conversion_factor, base_quantity, base_unit_cost, created_at
)
VALUES (
    md5('invoice-item:sale-001')::uuid,
    '11111111-1111-4111-8111-111111111111',
    md5('invoice:sale-001')::uuid,
    md5('order-item:seed-001')::uuid,
    md5('warehouse:main')::uuid,
    md5('product:rice-super')::uuid,
    md5('batch:rice-2026-a')::uuid,
    md5('uom:BORI')::uuid,
    10.0000,
    8500.0000,
    0.0000,
    0.0000,
    0.0000,
    50.000000,
    500.0000,
    15500.0000,
    TIMESTAMPTZ '2026-11-01 09:00:00+00'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.invoice_charges (
    id, tenant_id, invoice_id, charge_type, charge_direction, accounting_treatment,
    payable_account_id, amount, notes, created_at
)
VALUES (
    md5('invoice-charge:freight-001')::uuid,
    '11111111-1111-4111-8111-111111111111',
    md5('invoice:sale-001')::uuid,
    'FREIGHT_BILTY',
    'ADD_TO_BILL',
    'FULFILLMENT_EXPENSE',
    md5('account:transporter')::uuid,
    5000.0000,
    'Seed freight charge on sale invoice',
    TIMESTAMPTZ '2026-11-01 09:00:00+00'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.stock_movements (
    id, tenant_id, warehouse_id, product_id, batch_id, movement_type,
    quantity_delta, unit_cost, reference_type, reference_id, notes, created_by, created_at
)
VALUES
    (
        md5('movement:rice-opening-purchase')::uuid,
        '11111111-1111-4111-8111-111111111111',
        md5('warehouse:main')::uuid,
        md5('product:rice-super')::uuid,
        md5('batch:rice-2026-a')::uuid,
        'PURCHASE',
        1000.0000,
        15500.0000,
        'SEED_PURCHASE',
        md5('batch:rice-2026-a')::uuid,
        'Idempotent opening stock purchase (1000 kg)',
        md5('user:owner')::uuid,
        TIMESTAMPTZ '2026-11-01 09:00:00+00'
    ),
    (
        md5('movement:rice-sale-001')::uuid,
        '11111111-1111-4111-8111-111111111111',
        md5('warehouse:main')::uuid,
        md5('product:rice-super')::uuid,
        md5('batch:rice-2026-a')::uuid,
        'SALE',
        -500.0000,
        15500.0000,
        'SEED_SALE_INVOICE',
        md5('invoice:sale-001')::uuid,
        'Committed sale stock movement for 01-2026-001 (-500 kg)',
        md5('user:owner')::uuid,
        TIMESTAMPTZ '2026-11-01 09:00:00+00'
    )
ON CONFLICT (id) DO NOTHING;

-- 8. Ledger Entries & Allocation
INSERT INTO public.ledger_entries (
    id, tenant_id, account_id, order_id, invoice_id, entry_type,
    amount, running_balance, notes, idempotency_key, reverses_entry_id, created_by, created_at
)
VALUES
    (
        md5('ledger:debit-001')::uuid,
        '11111111-1111-4111-8111-111111111111',
        md5('account:customer')::uuid,
        md5('order:seed-001')::uuid,
        md5('invoice:sale-001')::uuid,
        'DEBIT',
        90000.0000,
        100000.0000,
        'Seed invoice debit',
        'seed-ledger-debit-001',
        NULL,
        md5('user:owner')::uuid,
        TIMESTAMPTZ '2026-11-01 09:00:00+00'
    ),
    (
        md5('ledger:credit-001')::uuid,
        '11111111-1111-4111-8111-111111111111',
        md5('account:customer')::uuid,
        md5('order:seed-001')::uuid,
        md5('invoice:sale-001')::uuid,
        'CREDIT',
        10000.0000,
        90000.0000,
        'Seed upfront payment',
        'seed-ledger-credit-001',
        NULL,
        md5('user:owner')::uuid,
        TIMESTAMPTZ '2026-11-01 09:01:00+00'
    )
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.ledger_allocations (
    id, tenant_id, account_id, debit_entry_id, credit_entry_id, amount, created_by, created_at
)
VALUES (
    md5('allocation:seed-001')::uuid,
    '11111111-1111-4111-8111-111111111111',
    md5('account:customer')::uuid,
    md5('ledger:debit-001')::uuid,
    md5('ledger:credit-001')::uuid,
    10000.0000,
    md5('user:owner')::uuid,
    TIMESTAMPTZ '2026-11-01 09:01:00+00'
)
ON CONFLICT (id) DO NOTHING;

-- 9. Inbound Message, Outbox Event & Audit Log
INSERT INTO public.inbound_messages (
    id, tenant_id, wamid, sender_phone, channel, raw_payload,
    audio_media_id, transcription_text, processing_status, matched_order_id,
    ai_confidence_score, error_log, received_at, processed_at, created_at
)
VALUES (
    md5('inbound:seed-001')::uuid,
    '11111111-1111-4111-8111-111111111111',
    'wamid-seed-001',
    '923001234567',
    'WhatsApp',
    '{"type":"text","body":"10 bori super basmati rice"}'::jsonb,
    NULL,
    '10 bori super basmati rice',
    'PROCESSED',
    md5('order:seed-001')::uuid,
    0.9500,
    NULL,
    TIMESTAMPTZ '2026-11-01 08:55:00+00',
    TIMESTAMPTZ '2026-11-01 08:56:00+00',
    TIMESTAMPTZ '2026-11-01 08:55:00+00'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.outbox_events (
    id, tenant_id, event_type, dedupe_key, payload, attempt_count,
    available_at, locked_at, processed_at, last_error, created_at
)
VALUES (
    md5('outbox:seed-001')::uuid,
    '11111111-1111-4111-8111-111111111111',
    'INVOICE_CREATED',
    'seed-invoice-created-001',
    ('{"invoiceId":"' || md5('invoice:sale-001')::uuid::text || '","tenantId":"11111111-1111-4111-8111-111111111111"}')::jsonb,
    0,
    TIMESTAMPTZ '2026-11-01 09:00:00+00',
    NULL,
    TIMESTAMPTZ '2026-11-01 09:00:00+00',
    NULL,
    TIMESTAMPTZ '2026-11-01 09:00:00+00'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.audit_logs (
    id, tenant_id, user_id, actor_snapshot, action_taken, entity_name,
    entity_id, old_values, new_values, correlation_id, created_at
)
VALUES (
    md5('audit:seed-invoice-001')::uuid,
    '11111111-1111-4111-8111-111111111111',
    md5('user:owner')::uuid,
    'MASTER_OWNER',
    'SEED_INVOICE_CREATED',
    'Invoice',
    md5('invoice:sale-001')::uuid,
    NULL,
    '{"seed":true}'::jsonb,
    NULL,
    TIMESTAMPTZ '2026-11-01 09:00:00+00'
)
ON CONFLICT (id) DO NOTHING;

COMMIT;
-- ============================================================================
-- LedgerAI Post-EF-Migration Hardening Patch (v2.0.1)
-- Applies: Extensions, Tenant Helpers, Unique & Check Constraints,
--          Composite Tenant & Batch-Tuple FKs, Triggers, Views,
--          Partial/Expression Indexes, Force RLS Policies & Atomic Lock Helpers
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- 1. GLOBAL TENANT CONTEXT & SECURITY HELPERS
-- ============================================================================

CREATE OR REPLACE FUNCTION ledgerai_current_tenant_id()
RETURNS UUID
LANGUAGE sql STABLE
AS $$
    SELECT NULLIF(current_setting('app.current_tenant', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION ledgerai_assert_tenant(p_tenant_id UUID)
RETURNS VOID
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    IF p_tenant_id IS NULL OR ledgerai_current_tenant_id() IS DISTINCT FROM p_tenant_id THEN
        RAISE EXCEPTION 'Tenant context is missing or does not match the requested tenant.'
            USING ERRCODE = '42501';
    END IF;
END;
$$;

-- ============================================================================
-- 2. UNIQUE CONSTRAINTS (REQUIRED FOR COMPOSITE TENANT FKs & IDEMPOTENCY)
-- ============================================================================

ALTER TABLE tenants
    ADD CONSTRAINT uq_tenants_tenant_code UNIQUE (tenant_code),
    ADD CONSTRAINT uq_tenants_domain_slug UNIQUE (domain_slug),
    ADD CONSTRAINT uq_tenants_whatsapp_phone_number_id UNIQUE (whats_app_phone_number_id);

ALTER TABLE users
    ADD CONSTRAINT uq_users_tenant_id UNIQUE (tenant_id, id),
    ADD CONSTRAINT uq_users_tenant_email UNIQUE (tenant_id, email);
-- Note: (tenant_id, user_code) already has unique index ix_users_tenant_id_user_code from EF

ALTER TABLE categories
    ADD CONSTRAINT uq_categories_tenant_id UNIQUE (tenant_id, id),
    ADD CONSTRAINT uq_categories_tenant_name UNIQUE (tenant_id, name);

ALTER TABLE units_of_measure
    ADD CONSTRAINT uq_uom_tenant_id UNIQUE (tenant_id, id),
    ADD CONSTRAINT uq_uom_tenant_code UNIQUE (tenant_id, unit_code),
    ADD CONSTRAINT uq_uom_tenant_name UNIQUE (tenant_id, name);

ALTER TABLE products
    ADD CONSTRAINT uq_products_tenant_id UNIQUE (tenant_id, id),
    ADD CONSTRAINT uq_products_tenant_code UNIQUE (tenant_id, product_code);

ALTER TABLE warehouses
    ADD CONSTRAINT uq_warehouses_tenant_id UNIQUE (tenant_id, id),
    ADD CONSTRAINT uq_warehouses_tenant_code UNIQUE (tenant_id, warehouse_code);

ALTER TABLE accounts
    ADD CONSTRAINT uq_accounts_tenant_id UNIQUE (tenant_id, id),
    ADD CONSTRAINT uq_accounts_tenant_code UNIQUE (tenant_id, account_code);

ALTER TABLE stock_batches
    ADD CONSTRAINT uq_stock_batches_tenant_id UNIQUE (tenant_id, id),
    ADD CONSTRAINT uq_stock_batches_code UNIQUE (tenant_id, warehouse_id, product_id, batch_code);
-- Note: (tenant_id, id, warehouse_id, product_id) already has unique index ix_stock_batches_tenant_id_id_warehouse_id_product_id from EF

ALTER TABLE orders
    ADD CONSTRAINT uq_orders_tenant_id UNIQUE (tenant_id, id),
    ADD CONSTRAINT uq_orders_tenant_code UNIQUE (tenant_id, order_code),
    ADD CONSTRAINT uq_orders_tenant_idempotency UNIQUE (tenant_id, idempotency_key);

ALTER TABLE order_items
    ADD CONSTRAINT uq_order_items_tenant_id UNIQUE (tenant_id, id),
    ADD CONSTRAINT uq_order_items_tenant_order_item UNIQUE (tenant_id, order_id, id);

ALTER TABLE stock_reservations
    ADD CONSTRAINT uq_stock_reservations_item_batch UNIQUE (tenant_id, order_item_id, batch_id);

ALTER TABLE invoices
    ADD CONSTRAINT uq_invoices_tenant_id UNIQUE (tenant_id, id),
    ADD CONSTRAINT uq_invoices_tenant_type_number UNIQUE (tenant_id, invoice_type, invoice_number),
    ADD CONSTRAINT uq_invoices_tenant_idempotency UNIQUE (tenant_id, idempotency_key);

ALTER TABLE ledger_entries
    ADD CONSTRAINT uq_ledger_entries_tenant_id UNIQUE (tenant_id, id),
    ADD CONSTRAINT uq_ledger_entries_tenant_account_id UNIQUE (tenant_id, account_id, id),
    ADD CONSTRAINT uq_ledger_entries_tenant_idempotency UNIQUE (tenant_id, idempotency_key),
    ADD CONSTRAINT uq_ledger_entries_invoice_entry UNIQUE (tenant_id, invoice_id, entry_type),
    ADD CONSTRAINT uq_ledger_entries_single_reversal UNIQUE (tenant_id, reverses_entry_id);

ALTER TABLE ledger_allocations
    ADD CONSTRAINT uq_alloc_pair UNIQUE (tenant_id, debit_entry_id, credit_entry_id);

ALTER TABLE inbound_messages
    ADD CONSTRAINT uq_inbound_messages_wamid UNIQUE (wamid);

ALTER TABLE outbox_events
    ADD CONSTRAINT uq_outbox_tenant_dedupe UNIQUE (tenant_id, dedupe_key);

-- ============================================================================
-- 3. COMPOSITE TENANT & BATCH-TUPLE FOREIGN KEYS
-- ============================================================================

ALTER TABLE products
    ADD CONSTRAINT fk_products_tenant_category
        FOREIGN KEY (tenant_id, category_id) REFERENCES categories(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_products_tenant_base_unit
        FOREIGN KEY (tenant_id, base_unit_id) REFERENCES units_of_measure(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_products_tenant_sec_unit
        FOREIGN KEY (tenant_id, secondary_unit_id) REFERENCES units_of_measure(tenant_id, id) ON DELETE RESTRICT;

ALTER TABLE accounts
    ADD CONSTRAINT fk_accounts_created_by
        FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_accounts_modified_by
        FOREIGN KEY (modified_by) REFERENCES users(id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_accounts_tenant_created_by
        FOREIGN KEY (tenant_id, created_by) REFERENCES users(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_accounts_tenant_modified_by
        FOREIGN KEY (tenant_id, modified_by) REFERENCES users(tenant_id, id) ON DELETE RESTRICT;

ALTER TABLE stock_items
    ADD CONSTRAINT fk_stock_items_tenant_warehouse
        FOREIGN KEY (tenant_id, warehouse_id) REFERENCES warehouses(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_stock_items_tenant_product
        FOREIGN KEY (tenant_id, product_id) REFERENCES products(tenant_id, id) ON DELETE RESTRICT;

ALTER TABLE stock_batches
    ADD CONSTRAINT fk_stock_batches_tenant_warehouse
        FOREIGN KEY (tenant_id, warehouse_id) REFERENCES warehouses(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_stock_batches_tenant_product
        FOREIGN KEY (tenant_id, product_id) REFERENCES products(tenant_id, id) ON DELETE RESTRICT;

ALTER TABLE stock_movements
    ADD CONSTRAINT fk_stock_movements_created_by
        FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_stock_movements_tenant_warehouse
        FOREIGN KEY (tenant_id, warehouse_id) REFERENCES warehouses(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_stock_movements_tenant_product
        FOREIGN KEY (tenant_id, product_id) REFERENCES products(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_stock_movements_batch_tuple
        FOREIGN KEY (tenant_id, batch_id, warehouse_id, product_id)
        REFERENCES stock_batches(tenant_id, id, warehouse_id, product_id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_stock_movements_tenant_created_by
        FOREIGN KEY (tenant_id, created_by) REFERENCES users(tenant_id, id) ON DELETE RESTRICT;

ALTER TABLE orders
    ADD CONSTRAINT fk_orders_approved_by
        FOREIGN KEY (approved_by) REFERENCES users(id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_orders_created_by
        FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_orders_tenant_account
        FOREIGN KEY (tenant_id, account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_orders_tenant_approved_by
        FOREIGN KEY (tenant_id, approved_by) REFERENCES users(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_orders_tenant_created_by
        FOREIGN KEY (tenant_id, created_by) REFERENCES users(tenant_id, id) ON DELETE RESTRICT;

ALTER TABLE order_items
    ADD CONSTRAINT fk_order_items_tenant_order
        FOREIGN KEY (tenant_id, order_id) REFERENCES orders(tenant_id, id) ON DELETE CASCADE,
    ADD CONSTRAINT fk_order_items_tenant_product
        FOREIGN KEY (tenant_id, product_id) REFERENCES products(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_order_items_tenant_warehouse
        FOREIGN KEY (tenant_id, warehouse_id) REFERENCES warehouses(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_order_items_batch_tuple
        FOREIGN KEY (tenant_id, batch_id, warehouse_id, product_id)
        REFERENCES stock_batches(tenant_id, id, warehouse_id, product_id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_order_items_tenant_unit
        FOREIGN KEY (tenant_id, ordered_unit_id) REFERENCES units_of_measure(tenant_id, id) ON DELETE RESTRICT;

ALTER TABLE stock_reservations
    ADD CONSTRAINT fk_reservations_tenant_order_item
        FOREIGN KEY (tenant_id, order_id, order_item_id) REFERENCES order_items(tenant_id, order_id, id) ON DELETE CASCADE,
    ADD CONSTRAINT fk_reservations_batch_tuple
        FOREIGN KEY (tenant_id, batch_id, warehouse_id, product_id)
        REFERENCES stock_batches(tenant_id, id, warehouse_id, product_id) ON DELETE RESTRICT;

ALTER TABLE invoices
    ADD CONSTRAINT fk_invoices_warehouse
        FOREIGN KEY (warehouse_id) REFERENCES warehouses(id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_invoices_issued_by
        FOREIGN KEY (issued_by) REFERENCES users(id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_invoices_tenant_order
        FOREIGN KEY (tenant_id, order_id) REFERENCES orders(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_invoices_tenant_account
        FOREIGN KEY (tenant_id, account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_invoices_tenant_warehouse
        FOREIGN KEY (tenant_id, warehouse_id) REFERENCES warehouses(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_invoices_tenant_transporter
        FOREIGN KEY (tenant_id, transporter_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_invoices_tenant_issued_by
        FOREIGN KEY (tenant_id, issued_by) REFERENCES users(tenant_id, id) ON DELETE RESTRICT;

ALTER TABLE invoice_items
    ADD CONSTRAINT fk_invoice_items_tenant_invoice
        FOREIGN KEY (tenant_id, invoice_id) REFERENCES invoices(tenant_id, id) ON DELETE CASCADE,
    ADD CONSTRAINT fk_invoice_items_tenant_order_item
        FOREIGN KEY (tenant_id, order_item_id) REFERENCES order_items(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_invoice_items_tenant_warehouse
        FOREIGN KEY (tenant_id, warehouse_id) REFERENCES warehouses(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_invoice_items_tenant_product
        FOREIGN KEY (tenant_id, product_id) REFERENCES products(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_invoice_items_batch_tuple
        FOREIGN KEY (tenant_id, batch_id, warehouse_id, product_id)
        REFERENCES stock_batches(tenant_id, id, warehouse_id, product_id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_invoice_items_tenant_unit
        FOREIGN KEY (tenant_id, unit_id) REFERENCES units_of_measure(tenant_id, id) ON DELETE RESTRICT;

ALTER TABLE invoice_charges
    ADD CONSTRAINT fk_invoice_charges_tenant_invoice
        FOREIGN KEY (tenant_id, invoice_id) REFERENCES invoices(tenant_id, id) ON DELETE CASCADE,
    ADD CONSTRAINT fk_invoice_charges_tenant_payable
        FOREIGN KEY (tenant_id, payable_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT;

ALTER TABLE ledger_entries
    ADD CONSTRAINT fk_ledger_entries_order
        FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_ledger_entries_invoice
        FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_ledger_entries_created_by
        FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_ledger_entries_tenant_account
        FOREIGN KEY (tenant_id, account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_ledger_entries_tenant_order
        FOREIGN KEY (tenant_id, order_id) REFERENCES orders(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_ledger_entries_tenant_invoice
        FOREIGN KEY (tenant_id, invoice_id) REFERENCES invoices(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_ledger_entries_same_account_reversal
        FOREIGN KEY (tenant_id, account_id, reverses_entry_id) REFERENCES ledger_entries(tenant_id, account_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_ledger_entries_tenant_created_by
        FOREIGN KEY (tenant_id, created_by) REFERENCES users(tenant_id, id) ON DELETE RESTRICT;

ALTER TABLE ledger_allocations
    ADD CONSTRAINT fk_allocations_created_by
        FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_allocations_tenant_account
        FOREIGN KEY (tenant_id, account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_allocations_tenant_debit
        FOREIGN KEY (tenant_id, account_id, debit_entry_id) REFERENCES ledger_entries(tenant_id, account_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_allocations_tenant_credit
        FOREIGN KEY (tenant_id, account_id, credit_entry_id) REFERENCES ledger_entries(tenant_id, account_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_allocations_tenant_created_by
        FOREIGN KEY (tenant_id, created_by) REFERENCES users(tenant_id, id) ON DELETE RESTRICT;

ALTER TABLE inbound_messages
    ADD CONSTRAINT fk_inbound_matched_order
        FOREIGN KEY (matched_order_id) REFERENCES orders(id) ON DELETE SET NULL,
    ADD CONSTRAINT fk_inbound_tenant_order
        FOREIGN KEY (tenant_id, matched_order_id) REFERENCES orders(tenant_id, id) ON DELETE RESTRICT;

ALTER TABLE audit_logs
    ADD CONSTRAINT fk_audit_logs_user
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_audit_logs_tenant_user
        FOREIGN KEY (tenant_id, user_id) REFERENCES users(tenant_id, id) ON DELETE RESTRICT;

-- ============================================================================
-- 4. DOMAIN & FINANCIAL INTEGRITY CHECK CONSTRAINTS
-- ============================================================================

ALTER TABLE tenants
    ADD CONSTRAINT ck_tenants_business_name CHECK (btrim(business_name) <> '');

ALTER TABLE users
    ADD CONSTRAINT ck_users_full_name CHECK (btrim(full_name) <> ''),
    ADD CONSTRAINT ck_users_role CHECK (role IN ('Owner','Admin','Manager','Operator','Viewer'));

ALTER TABLE categories
    ADD CONSTRAINT ck_categories_name CHECK (btrim(name) <> '');

ALTER TABLE units_of_measure
    ADD CONSTRAINT ck_uom_unit_code CHECK (btrim(unit_code) <> ''),
    ADD CONSTRAINT ck_uom_name CHECK (btrim(name) <> ''),
    ADD CONSTRAINT ck_uom_aliases_array CHECK (jsonb_typeof(aliases) = 'array');

ALTER TABLE products
    ADD CONSTRAINT ck_products_name CHECK (btrim(name) <> ''),
    ADD CONSTRAINT ck_products_pack_size CHECK (pack_size > 0),
    ADD CONSTRAINT ck_products_purchase_price CHECK (default_purchase_price >= 0),
    ADD CONSTRAINT ck_products_wac CHECK (weighted_avg_cost >= 0),
    ADD CONSTRAINT ck_products_sales_price CHECK (default_sales_price >= 0),
    ADD CONSTRAINT ck_products_min_stock CHECK (minimum_stock >= 0),
    ADD CONSTRAINT ck_products_attributes_obj CHECK (jsonb_typeof(attributes) = 'object'),
    ADD CONSTRAINT ck_products_aliases_array CHECK (
        NOT (attributes ? 'aliases') OR jsonb_typeof(attributes->'aliases') = 'array'
    );

ALTER TABLE warehouses
    ADD CONSTRAINT ck_warehouses_name CHECK (btrim(name) <> '');

ALTER TABLE accounts
    ADD CONSTRAINT ck_accounts_account_type CHECK (account_type IN (
        'CUSTOMER','SUPPLIER','BANK','CASH','EXPENSE','TRANSPORTER','INVESTOR'
    )),
    ADD CONSTRAINT ck_accounts_name CHECK (btrim(name) <> ''),
    ADD CONSTRAINT ck_accounts_opening_balance CHECK (opening_balance >= 0),
    ADD CONSTRAINT ck_accounts_opening_balance_type CHECK (opening_balance_type IN ('DR','CR')),
    ADD CONSTRAINT ck_accounts_credit_limit CHECK (credit_limit >= 0),
    ADD CONSTRAINT ck_accounts_reserved_credit CHECK (reserved_credit >= 0),
    ADD CONSTRAINT ck_accounts_risk_tier CHECK (risk_tier IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    ADD CONSTRAINT ck_accounts_metadata_obj CHECK (jsonb_typeof(metadata) = 'object');

ALTER TABLE stock_items
    ADD CONSTRAINT ck_stock_items_on_hand CHECK (quantity_on_hand >= 0),
    ADD CONSTRAINT ck_stock_items_reserved CHECK (quantity_reserved >= 0),
    ADD CONSTRAINT ck_stock_reserved_not_above_on_hand CHECK (quantity_reserved <= quantity_on_hand);

ALTER TABLE stock_batches
    ADD CONSTRAINT ck_batches_code CHECK (btrim(batch_code) <> ''),
    ADD CONSTRAINT ck_batches_unit_cost CHECK (unit_cost >= 0),
    ADD CONSTRAINT ck_batches_on_hand CHECK (quantity_on_hand >= 0),
    ADD CONSTRAINT ck_batches_reserved CHECK (quantity_reserved >= 0),
    ADD CONSTRAINT ck_batches_reserved_le_on_hand CHECK (quantity_reserved <= quantity_on_hand);

ALTER TABLE stock_movements
    ADD CONSTRAINT ck_movements_type CHECK (movement_type IN (
        'PURCHASE','SALE','SALES_RETURN','PURCHASE_RETURN',
        'TRANSFER_IN','TRANSFER_OUT','DAMAGE_EXPIRY','ADJUSTMENT'
    )),
    ADD CONSTRAINT ck_movements_qty_nonzero CHECK (quantity_delta <> 0),
    ADD CONSTRAINT ck_movements_unit_cost CHECK (unit_cost >= 0);

ALTER TABLE orders
    ADD CONSTRAINT ck_orders_status CHECK (order_status IN ('PENDING_APPROVAL','VALIDATED','COMMITTED','REJECTED','CANCELLED')),
    ADD CONSTRAINT ck_orders_payment_terms CHECK (payment_terms IN ('CASH','CREDIT','PARTIAL')),
    ADD CONSTRAINT ck_orders_total_amount CHECK (total_amount >= 0),
    ADD CONSTRAINT ck_orders_upfront_amount CHECK (upfront_paid_amount >= 0),
    ADD CONSTRAINT ck_orders_ai_confidence CHECK (ai_confidence_score BETWEEN 0 AND 1),
    ADD CONSTRAINT ck_orders_upfront_le_total CHECK (upfront_paid_amount <= total_amount),
    ADD CONSTRAINT ck_orders_approval_fields CHECK (
        (approved_by IS NULL AND approved_at IS NULL) OR
        (approved_by IS NOT NULL AND approved_at IS NOT NULL)
    );

ALTER TABLE order_items
    ADD CONSTRAINT ck_order_items_ordered_qty CHECK (ordered_quantity > 0),
    ADD CONSTRAINT ck_order_items_unit_price CHECK (ordered_unit_price >= 0),
    ADD CONSTRAINT ck_order_items_conv_factor CHECK (conversion_factor > 0),
    ADD CONSTRAINT ck_order_items_base_qty CHECK (base_quantity > 0),
    ADD CONSTRAINT ck_order_items_unit_cost CHECK (unit_cost_at_sale >= 0);

ALTER TABLE stock_reservations
    ADD CONSTRAINT ck_reservations_reserved_qty CHECK (reserved_quantity > 0),
    ADD CONSTRAINT ck_reservations_released_qty CHECK (released_quantity >= 0),
    ADD CONSTRAINT ck_reservations_committed_qty CHECK (committed_quantity >= 0),
    ADD CONSTRAINT ck_reservations_status CHECK (status IN ('ACTIVE','PARTIALLY_RELEASED','RELEASED','COMMITTED')),
    ADD CONSTRAINT ck_reservations_qty_balance CHECK (released_quantity + committed_quantity <= reserved_quantity);

ALTER TABLE invoices
    ADD CONSTRAINT ck_invoices_type CHECK (invoice_type IN ('PURCHASE','SALE')),
    ADD CONSTRAINT ck_invoices_status CHECK (invoice_status IN ('DRAFT','ISSUED','PARTIALLY_PAID','PAID','VOID')),
    ADD CONSTRAINT ck_invoices_subtotal CHECK (subtotal_amount >= 0),
    ADD CONSTRAINT ck_invoices_discount CHECK (discount_amount >= 0),
    ADD CONSTRAINT ck_invoices_tax CHECK (tax_amount >= 0),
    ADD CONSTRAINT ck_invoices_grand_total CHECK (grand_total >= 0),
    ADD CONSTRAINT ck_invoices_amount_paid CHECK (amount_paid >= 0),
    ADD CONSTRAINT ck_invoices_paid_le_grand_total CHECK (amount_paid <= grand_total),
    ADD CONSTRAINT ck_invoices_discount_le_subtotal CHECK (discount_amount <= subtotal_amount),
    ADD CONSTRAINT ck_invoices_status_paid_consistency CHECK (
        (invoice_status = 'PAID' AND amount_paid = grand_total) OR
        (invoice_status <> 'PAID')
    );

ALTER TABLE invoice_items
    ADD CONSTRAINT ck_invoice_items_qty CHECK (quantity > 0),
    ADD CONSTRAINT ck_invoice_items_unit_price CHECK (unit_price >= 0),
    ADD CONSTRAINT ck_invoice_items_discount CHECK (discount_amount >= 0),
    ADD CONSTRAINT ck_invoice_items_tax_rate CHECK (tax_rate BETWEEN 0 AND 100),
    ADD CONSTRAINT ck_invoice_items_tax_amount CHECK (tax_amount >= 0),
    ADD CONSTRAINT ck_invoice_items_conv_factor CHECK (conversion_factor > 0),
    ADD CONSTRAINT ck_invoice_items_base_qty CHECK (base_quantity > 0),
    ADD CONSTRAINT ck_invoice_items_base_cost CHECK (base_unit_cost >= 0),
    ADD CONSTRAINT ck_invoice_items_discount_le_gross CHECK (discount_amount <= round(quantity * unit_price, 4));

ALTER TABLE invoice_charges
    ADD CONSTRAINT ck_invoice_charges_type CHECK (charge_type IN (
        'FREIGHT_BILTY','LABOR_MAZDOORI','DELIVERY_OUTBOUND',
        'WHT_236G','WHT_236H','WEIGHING_KANTA','KASAR_WAIVER','OTHER'
    )),
    ADD CONSTRAINT ck_invoice_charges_direction CHECK (charge_direction IN ('ADD_TO_BILL','DEDUCT_FROM_BILL','MEMO_ONLY')),
    ADD CONSTRAINT ck_invoice_charges_treatment CHECK (accounting_treatment IN (
        'CAPITALIZE_LANDED_COST','FULFILLMENT_EXPENSE','TAX_PASS_THROUGH','DISCOUNT_WAIVER'
    )),
    ADD CONSTRAINT ck_invoice_charges_amount CHECK (amount > 0);

ALTER TABLE ledger_entries
    ADD CONSTRAINT ck_ledger_entries_type CHECK (entry_type IN ('DEBIT','CREDIT')),
    ADD CONSTRAINT ck_ledger_entries_amount CHECK (amount > 0),
    ADD CONSTRAINT ck_ledger_no_self_reversal CHECK (reverses_entry_id IS NULL OR reverses_entry_id <> id);

ALTER TABLE ledger_allocations
    ADD CONSTRAINT ck_allocations_amount CHECK (amount > 0),
    ADD CONSTRAINT ck_alloc_distinct_entries CHECK (debit_entry_id <> credit_entry_id);

ALTER TABLE inbound_messages
    ADD CONSTRAINT ck_inbound_channel CHECK (channel IN ('WhatsApp','Web','Voice','Other')),
    ADD CONSTRAINT ck_inbound_status CHECK (processing_status IN ('RECEIVED','PROCESSING','PROCESSED','FAILED','IGNORED')),
    ADD CONSTRAINT ck_inbound_confidence CHECK (ai_confidence_score BETWEEN 0 AND 1);

ALTER TABLE outbox_events
    ADD CONSTRAINT ck_outbox_attempt_count CHECK (attempt_count >= 0);

-- ============================================================================
-- 5. TRIGGERS (STOCK_ITEMS GUARD & SYNC, LEDGER ALLOCATIONS, IMMUTABLE AUDIT)
-- ============================================================================

CREATE OR REPLACE FUNCTION ledgerai_guard_stock_items_direct_write()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF pg_trigger_depth() < 2 THEN
        RAISE EXCEPTION 'Direct writes to stock_items are forbidden; aggregate stock is maintained exclusively by stock_batches triggers.'
            USING ERRCODE = '42501';
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_stock_items_direct_write ON stock_items;
CREATE TRIGGER trg_guard_stock_items_direct_write
BEFORE INSERT OR UPDATE OR DELETE ON stock_items
FOR EACH ROW EXECUTE FUNCTION ledgerai_guard_stock_items_direct_write();

CREATE OR REPLACE FUNCTION ledgerai_recalc_stock_item(
    p_tenant_id UUID,
    p_warehouse_id UUID,
    p_product_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_on_hand NUMERIC(18,4);
    v_reserved NUMERIC(18,4);
BEGIN
    PERFORM pg_advisory_xact_lock(
        hashtextextended(p_tenant_id::text || ':' || p_warehouse_id::text || ':' || p_product_id::text, 0)
    );

    SELECT COALESCE(SUM(quantity_on_hand), 0), COALESCE(SUM(quantity_reserved), 0)
    INTO v_on_hand, v_reserved
    FROM stock_batches
    WHERE tenant_id = p_tenant_id
      AND warehouse_id = p_warehouse_id
      AND product_id = p_product_id;

    INSERT INTO stock_items (id, tenant_id, warehouse_id, product_id, quantity_on_hand, quantity_reserved, created_at, updated_at)
    VALUES (gen_random_uuid(), p_tenant_id, p_warehouse_id, p_product_id, v_on_hand, v_reserved, now(), now())
    ON CONFLICT (tenant_id, warehouse_id, product_id) DO UPDATE
    SET quantity_on_hand = EXCLUDED.quantity_on_hand,
        quantity_reserved = EXCLUDED.quantity_reserved,
        updated_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION ledgerai_sync_stock_items()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.warehouse_id IS DISTINCT FROM NEW.warehouse_id OR
        OLD.product_id IS DISTINCT FROM NEW.product_id
    ) THEN
        PERFORM ledgerai_recalc_stock_item(OLD.tenant_id, OLD.warehouse_id, OLD.product_id);
    END IF;

    IF TG_OP = 'DELETE' THEN
        PERFORM ledgerai_recalc_stock_item(OLD.tenant_id, OLD.warehouse_id, OLD.product_id);
    ELSE
        PERFORM ledgerai_recalc_stock_item(NEW.tenant_id, NEW.warehouse_id, NEW.product_id);
    END IF;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_stock_items_from_batches ON stock_batches;
CREATE TRIGGER trg_sync_stock_items_from_batches
AFTER INSERT OR UPDATE OF quantity_on_hand, quantity_reserved, warehouse_id, product_id OR DELETE ON stock_batches
FOR EACH ROW EXECUTE FUNCTION ledgerai_sync_stock_items();

CREATE OR REPLACE FUNCTION ledgerai_validate_allocation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_debit ledger_entries%ROWTYPE;
    v_credit ledger_entries%ROWTYPE;
    v_debit_allocated NUMERIC(18,4);
    v_credit_allocated NUMERIC(18,4);
BEGIN
    SELECT * INTO v_debit FROM ledger_entries
    WHERE tenant_id = NEW.tenant_id AND account_id = NEW.account_id AND id = NEW.debit_entry_id FOR UPDATE;

    SELECT * INTO v_credit FROM ledger_entries
    WHERE tenant_id = NEW.tenant_id AND account_id = NEW.account_id AND id = NEW.credit_entry_id FOR UPDATE;

    IF NOT FOUND OR v_debit.id IS NULL OR v_credit.id IS NULL
       OR v_debit.entry_type <> 'DEBIT' OR v_credit.entry_type <> 'CREDIT'
       OR v_debit.reverses_entry_id IS NOT NULL OR v_credit.reverses_entry_id IS NOT NULL THEN
        RAISE EXCEPTION 'Allocation must link an unreversed DEBIT and an unreversed CREDIT for the same tenant and account.';
    END IF;

    SELECT COALESCE(SUM(amount),0) INTO v_debit_allocated FROM ledger_allocations
    WHERE tenant_id = NEW.tenant_id AND debit_entry_id = NEW.debit_entry_id AND id <> NEW.id;

    SELECT COALESCE(SUM(amount),0) INTO v_credit_allocated FROM ledger_allocations
    WHERE tenant_id = NEW.tenant_id AND credit_entry_id = NEW.credit_entry_id AND id <> NEW.id;

    IF v_debit_allocated + NEW.amount > v_debit.amount OR v_credit_allocated + NEW.amount > v_credit.amount THEN
        RAISE EXCEPTION 'Allocation exceeds remaining debit or credit balance.';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_ledger_allocation ON ledger_allocations;
CREATE TRIGGER trg_validate_ledger_allocation
BEFORE INSERT OR UPDATE ON ledger_allocations
FOR EACH ROW EXECUTE FUNCTION ledgerai_validate_allocation();

CREATE OR REPLACE FUNCTION ledgerai_prevent_audit_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'audit_logs is append-only and cannot be updated or deleted.'
        USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_logs_immutable ON audit_logs;
CREATE TRIGGER trg_audit_logs_immutable
BEFORE UPDATE OR DELETE ON audit_logs
FOR EACH ROW EXECUTE FUNCTION ledgerai_prevent_audit_mutation();

-- ============================================================================
-- 6. SECURITY-INVOKER VIEWS
-- ============================================================================

CREATE OR REPLACE VIEW v_product_stock_totals WITH (security_invoker = true) AS
SELECT
    tenant_id,
    product_id,
    SUM(quantity_on_hand) AS total_current_stock,
    SUM(quantity_reserved) AS total_reserved_stock,
    SUM(quantity_on_hand - quantity_reserved) AS total_available_stock
FROM stock_items
GROUP BY tenant_id, product_id;

CREATE OR REPLACE VIEW v_invoice_profit_summary WITH (security_invoker = true) AS
SELECT
    i.tenant_id,
    i.id AS invoice_id,
    i.voucher_series,
    i.invoice_number,
    i.order_id,
    i.account_id,
    i.invoice_status,
    i.issued_at,
    i.subtotal_amount,
    i.discount_amount,
    i.tax_amount,
    i.grand_total,
    COALESCE(SUM(ii.line_cogs), 0) AS total_cogs,
    COALESCE((SELECT SUM(ic.amount) FROM invoice_charges ic
              WHERE ic.tenant_id = i.tenant_id
                AND ic.invoice_id = i.id
                AND ic.accounting_treatment IN ('FULFILLMENT_EXPENSE','DISCOUNT_WAIVER')), 0) AS fulfillment_and_waiver_costs,
    (i.subtotal_amount - i.discount_amount)
        - COALESCE(SUM(ii.line_cogs), 0)
        - COALESCE((SELECT SUM(ic.amount) FROM invoice_charges ic
                    WHERE ic.tenant_id = i.tenant_id
                      AND ic.invoice_id = i.id
                      AND ic.accounting_treatment IN ('FULFILLMENT_EXPENSE','DISCOUNT_WAIVER')), 0) AS gross_profit
FROM invoices i
LEFT JOIN invoice_items ii ON ii.tenant_id = i.tenant_id AND ii.invoice_id = i.id
WHERE i.invoice_type = 'SALE' AND i.invoice_status <> 'VOID'
GROUP BY i.tenant_id, i.id, i.voucher_series, i.invoice_number, i.order_id, i.account_id,
         i.invoice_status, i.issued_at, i.subtotal_amount, i.discount_amount, i.tax_amount, i.grand_total;

-- ============================================================================
-- 7. PARTIAL, EXPRESSION & GIN PATH_OPS INDEX UPGRADES
-- ============================================================================

DROP INDEX IF EXISTS idx_accounts_tenant_type_active;
CREATE INDEX idx_accounts_tenant_type_active
    ON accounts(tenant_id, account_type, is_active) WHERE is_deleted = FALSE;

DROP INDEX IF EXISTS idx_accounts_tenant_phone;
CREATE INDEX idx_accounts_tenant_phone
    ON accounts(tenant_id, phone_no) WHERE phone_no IS NOT NULL;

DROP INDEX IF EXISTS idx_accounts_tenant_mobile;
CREATE INDEX idx_accounts_tenant_mobile
    ON accounts(tenant_id, mobile_no) WHERE mobile_no IS NOT NULL;

DROP INDEX IF EXISTS idx_uom_aliases_gin;
CREATE INDEX idx_uom_aliases_gin
    ON units_of_measure USING gin(aliases jsonb_path_ops);

DROP INDEX IF EXISTS idx_products_attributes_gin;
CREATE INDEX idx_products_attributes_gin
    ON products USING gin(attributes jsonb_path_ops);

CREATE INDEX IF NOT EXISTS idx_products_tenant_name
    ON products(tenant_id, lower(name)) WHERE is_deleted = FALSE;

DROP INDEX IF EXISTS idx_stock_batches_fefo;
CREATE INDEX idx_stock_batches_fefo
    ON stock_batches(tenant_id, warehouse_id, product_id, expires_at ASC NULLS LAST, created_at ASC);

DROP INDEX IF EXISTS idx_invoices_order;
CREATE INDEX idx_invoices_order
    ON invoices(tenant_id, order_id) WHERE order_id IS NOT NULL;

DROP INDEX IF EXISTS idx_ledger_order;
CREATE INDEX idx_ledger_order
    ON ledger_entries(tenant_id, order_id) WHERE order_id IS NOT NULL;

DROP INDEX IF EXISTS idx_ledger_invoice;
CREATE INDEX idx_ledger_invoice
    ON ledger_entries(tenant_id, invoice_id) WHERE invoice_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_inbound_pending
    ON inbound_messages(received_at) WHERE processing_status IN ('RECEIVED','PROCESSING');

DROP INDEX IF EXISTS idx_outbox_ready;
CREATE INDEX idx_outbox_ready
    ON outbox_events(available_at, created_at) WHERE processed_at IS NULL;

-- ============================================================================
-- 8. ROW-LEVEL SECURITY (FORCE RLS POLICIES ON ALL 21 TABLES)
-- ============================================================================

ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE units_of_measure ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE warehouses ENABLE ROW LEVEL SECURITY;
ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoice_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoice_charges ENABLE ROW LEVEL SECURITY;
ALTER TABLE ledger_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE ledger_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE inbound_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE outbox_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

ALTER TABLE tenants FORCE ROW LEVEL SECURITY;
ALTER TABLE users FORCE ROW LEVEL SECURITY;
ALTER TABLE categories FORCE ROW LEVEL SECURITY;
ALTER TABLE units_of_measure FORCE ROW LEVEL SECURITY;
ALTER TABLE products FORCE ROW LEVEL SECURITY;
ALTER TABLE warehouses FORCE ROW LEVEL SECURITY;
ALTER TABLE accounts FORCE ROW LEVEL SECURITY;
ALTER TABLE stock_items FORCE ROW LEVEL SECURITY;
ALTER TABLE stock_batches FORCE ROW LEVEL SECURITY;
ALTER TABLE stock_movements FORCE ROW LEVEL SECURITY;
ALTER TABLE orders FORCE ROW LEVEL SECURITY;
ALTER TABLE order_items FORCE ROW LEVEL SECURITY;
ALTER TABLE stock_reservations FORCE ROW LEVEL SECURITY;
ALTER TABLE invoices FORCE ROW LEVEL SECURITY;
ALTER TABLE invoice_items FORCE ROW LEVEL SECURITY;
ALTER TABLE invoice_charges FORCE ROW LEVEL SECURITY;
ALTER TABLE ledger_entries FORCE ROW LEVEL SECURITY;
ALTER TABLE ledger_allocations FORCE ROW LEVEL SECURITY;
ALTER TABLE inbound_messages FORCE ROW LEVEL SECURITY;
ALTER TABLE outbox_events FORCE ROW LEVEL SECURITY;
ALTER TABLE audit_logs FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_tenants ON tenants
    USING (id = ledgerai_current_tenant_id()) WITH CHECK (id = ledgerai_current_tenant_id());
CREATE POLICY tenant_isolation_users ON users
    USING (tenant_id = ledgerai_current_tenant_id()) WITH CHECK (tenant_id = ledgerai_current_tenant_id());
CREATE POLICY tenant_isolation_categories ON categories
    USING (tenant_id = ledgerai_current_tenant_id()) WITH CHECK (tenant_id = ledgerai_current_tenant_id());
CREATE POLICY tenant_isolation_uom ON units_of_measure
    USING (tenant_id = ledgerai_current_tenant_id()) WITH CHECK (tenant_id = ledgerai_current_tenant_id());
CREATE POLICY tenant_isolation_products ON products
    USING (tenant_id = ledgerai_current_tenant_id()) WITH CHECK (tenant_id = ledgerai_current_tenant_id());
CREATE POLICY tenant_isolation_warehouses ON warehouses
    USING (tenant_id = ledgerai_current_tenant_id()) WITH CHECK (tenant_id = ledgerai_current_tenant_id());
CREATE POLICY tenant_isolation_accounts ON accounts
    USING (tenant_id = ledgerai_current_tenant_id()) WITH CHECK (tenant_id = ledgerai_current_tenant_id());
CREATE POLICY tenant_isolation_stock_items ON stock_items
    USING (tenant_id = ledgerai_current_tenant_id()) WITH CHECK (tenant_id = ledgerai_current_tenant_id());
CREATE POLICY tenant_isolation_stock_batches ON stock_batches
    USING (tenant_id = ledgerai_current_tenant_id()) WITH CHECK (tenant_id = ledgerai_current_tenant_id());
CREATE POLICY tenant_isolation_stock_movements ON stock_movements
    USING (tenant_id = ledgerai_current_tenant_id()) WITH CHECK (tenant_id = ledgerai_current_tenant_id());
CREATE POLICY tenant_isolation_orders ON orders
    USING (tenant_id = ledgerai_current_tenant_id()) WITH CHECK (tenant_id = ledgerai_current_tenant_id());
CREATE POLICY tenant_isolation_order_items ON order_items
    USING (tenant_id = ledgerai_current_tenant_id()) WITH CHECK (tenant_id = ledgerai_current_tenant_id());
CREATE POLICY tenant_isolation_stock_reservations ON stock_reservations
    USING (tenant_id = ledgerai_current_tenant_id()) WITH CHECK (tenant_id = ledgerai_current_tenant_id());
CREATE POLICY tenant_isolation_invoices ON invoices
    USING (tenant_id = ledgerai_current_tenant_id()) WITH CHECK (tenant_id = ledgerai_current_tenant_id());
CREATE POLICY tenant_isolation_invoice_items ON invoice_items
    USING (tenant_id = ledgerai_current_tenant_id()) WITH CHECK (tenant_id = ledgerai_current_tenant_id());
CREATE POLICY tenant_isolation_invoice_charges ON invoice_charges
    USING (tenant_id = ledgerai_current_tenant_id()) WITH CHECK (tenant_id = ledgerai_current_tenant_id());
CREATE POLICY tenant_isolation_ledger_entries ON ledger_entries
    USING (tenant_id = ledgerai_current_tenant_id()) WITH CHECK (tenant_id = ledgerai_current_tenant_id());
CREATE POLICY tenant_isolation_ledger_allocations ON ledger_allocations
    USING (tenant_id = ledgerai_current_tenant_id()) WITH CHECK (tenant_id = ledgerai_current_tenant_id());
CREATE POLICY tenant_isolation_inbound_messages ON inbound_messages
    USING (tenant_id = ledgerai_current_tenant_id()) WITH CHECK (tenant_id = ledgerai_current_tenant_id());
CREATE POLICY tenant_isolation_outbox_events ON outbox_events
    USING (tenant_id = ledgerai_current_tenant_id()) WITH CHECK (tenant_id = ledgerai_current_tenant_id());
CREATE POLICY tenant_isolation_audit_logs ON audit_logs
    USING (tenant_id = ledgerai_current_tenant_id()) WITH CHECK (tenant_id = ledgerai_current_tenant_id());

-- ============================================================================
-- 9. OWNERSHIP-AWARE ATOMIC LOCK HELPERS
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_reserve_batch_stock(
    p_tenant_id UUID,
    p_order_id UUID,
    p_order_item_id UUID,
    p_batch_id UUID,
    p_base_qty NUMERIC
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_warehouse_id UUID;
    v_product_id UUID;
    v_reservation_id UUID;
BEGIN
    PERFORM ledgerai_assert_tenant(p_tenant_id);
    IF p_base_qty IS NULL OR p_base_qty <= 0 THEN
        RAISE EXCEPTION 'Reservation quantity must be positive.';
    END IF;

    UPDATE stock_batches
    SET quantity_reserved = quantity_reserved + p_base_qty
    WHERE tenant_id = p_tenant_id
      AND id = p_batch_id
      AND (quantity_on_hand - quantity_reserved) >= p_base_qty
    RETURNING warehouse_id, product_id INTO v_warehouse_id, v_product_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Insufficient available stock in batch %.', p_batch_id;
    END IF;

    INSERT INTO stock_reservations (
        id, tenant_id, order_id, order_item_id, warehouse_id, product_id, batch_id,
        reserved_quantity, released_quantity, committed_quantity, status, created_at, updated_at
    )
    VALUES (
        gen_random_uuid(), p_tenant_id, p_order_id, p_order_item_id, v_warehouse_id, v_product_id, p_batch_id,
        p_base_qty, 0, 0, 'ACTIVE', now(), now()
    )
    RETURNING id INTO v_reservation_id;

    RETURN v_reservation_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_release_stock_reservation(
    p_tenant_id UUID,
    p_reservation_id UUID,
    p_release_qty NUMERIC DEFAULT NULL
)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
    v_res stock_reservations%ROWTYPE;
    v_open_qty NUMERIC(18,4);
    v_qty_to_release NUMERIC(18,4);
    v_new_released NUMERIC(18,4);
BEGIN
    PERFORM ledgerai_assert_tenant(p_tenant_id);

    SELECT * INTO v_res FROM stock_reservations
    WHERE tenant_id = p_tenant_id AND id = p_reservation_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Stock reservation % not found.', p_reservation_id;
    END IF;

    v_open_qty := v_res.reserved_quantity - v_res.released_quantity - v_res.committed_quantity;
    v_qty_to_release := COALESCE(p_release_qty, v_open_qty);

    IF v_qty_to_release <= 0 OR v_qty_to_release > v_open_qty THEN
        RAISE EXCEPTION 'Invalid release quantity % for reservation % (open: %).',
            v_qty_to_release, p_reservation_id, v_open_qty;
    END IF;

    UPDATE stock_batches
    SET quantity_reserved = quantity_reserved - v_qty_to_release
    WHERE tenant_id = p_tenant_id
      AND id = v_res.batch_id
      AND quantity_reserved >= v_qty_to_release;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Batch % reserved quantity underflow.', v_res.batch_id;
    END IF;

    v_new_released := v_res.released_quantity + v_qty_to_release;

    UPDATE stock_reservations
    SET released_quantity = v_new_released,
        status = CASE
            WHEN v_new_released + committed_quantity = reserved_quantity THEN 'RELEASED'
            ELSE 'PARTIALLY_RELEASED'
        END,
        updated_at = now()
    WHERE id = p_reservation_id;

    RETURN v_new_released;
END;
$$;

CREATE OR REPLACE FUNCTION fn_commit_batch_stock(
    p_tenant_id UUID,
    p_batch_id UUID,
    p_base_qty NUMERIC,
    p_reservation_id UUID DEFAULT NULL
)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
    v_res stock_reservations%ROWTYPE;
    v_open_qty NUMERIC(18,4);
    v_remaining_on_hand NUMERIC(18,4);
BEGIN
    PERFORM ledgerai_assert_tenant(p_tenant_id);
    IF p_base_qty IS NULL OR p_base_qty <= 0 THEN
        RAISE EXCEPTION 'Commit quantity must be positive.';
    END IF;

    IF p_reservation_id IS NOT NULL THEN
        SELECT * INTO v_res FROM stock_reservations
        WHERE tenant_id = p_tenant_id AND id = p_reservation_id AND batch_id = p_batch_id
        FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Stock reservation % does not match batch %.', p_reservation_id, p_batch_id;
        END IF;

        v_open_qty := v_res.reserved_quantity - v_res.released_quantity - v_res.committed_quantity;
        IF p_base_qty > v_open_qty THEN
            RAISE EXCEPTION 'Commit quantity % exceeds open reservation % (open: %).',
                p_base_qty, p_reservation_id, v_open_qty;
        END IF;

        UPDATE stock_batches
        SET quantity_on_hand = quantity_on_hand - p_base_qty,
            quantity_reserved = quantity_reserved - p_base_qty
        WHERE tenant_id = p_tenant_id
          AND id = p_batch_id
          AND quantity_on_hand >= p_base_qty
          AND quantity_reserved >= p_base_qty
        RETURNING quantity_on_hand INTO v_remaining_on_hand;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Insufficient physical or reserved stock on batch %.', p_batch_id;
        END IF;

        UPDATE stock_reservations
        SET committed_quantity = committed_quantity + p_base_qty,
            status = CASE
                WHEN released_quantity + committed_quantity + p_base_qty = reserved_quantity THEN 'COMMITTED'
                ELSE status
            END,
            updated_at = now()
        WHERE id = p_reservation_id;
    ELSE
        UPDATE stock_batches
        SET quantity_on_hand = quantity_on_hand - p_base_qty
        WHERE tenant_id = p_tenant_id
          AND id = p_batch_id
          AND (quantity_on_hand - quantity_reserved) >= p_base_qty
        RETURNING quantity_on_hand INTO v_remaining_on_hand;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Insufficient unreserved stock on batch %.', p_batch_id;
        END IF;
    END IF;

    RETURN v_remaining_on_hand;
END;
$$;

CREATE OR REPLACE FUNCTION fn_apply_account_balance_delta(
    p_tenant_id UUID,
    p_account_id UUID,
    p_balance_delta NUMERIC DEFAULT 0,
    p_reserved_credit_delta NUMERIC DEFAULT 0,
    p_enforce_credit_limit BOOLEAN DEFAULT FALSE
)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
    v_acc accounts%ROWTYPE;
    v_new_balance NUMERIC(18,4);
    v_new_reserved NUMERIC(18,4);
BEGIN
    PERFORM ledgerai_assert_tenant(p_tenant_id);

    SELECT * INTO v_acc FROM accounts
    WHERE tenant_id = p_tenant_id AND id = p_account_id AND is_active AND NOT is_deleted
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active account % not found in tenant.', p_account_id;
    END IF;

    v_new_balance := v_acc.current_balance + COALESCE(p_balance_delta, 0);
    v_new_reserved := v_acc.reserved_credit + COALESCE(p_reserved_credit_delta, 0);

    IF v_new_reserved < 0 THEN
        RAISE EXCEPTION 'Credit reservation release exceeds currently reserved credit (%) for account %.',
            v_acc.reserved_credit, p_account_id;
    END IF;

    IF p_enforce_credit_limit AND (v_new_balance + v_new_reserved > v_acc.credit_limit) THEN
        RAISE EXCEPTION 'Credit limit (%) exceeded for account % (projected exposure: %).',
            v_acc.credit_limit, p_account_id, (v_new_balance + v_new_reserved);
    END IF;

    UPDATE accounts
    SET current_balance = v_new_balance,
        reserved_credit = v_new_reserved,
        modified_at = now()
    WHERE id = p_account_id;

    RETURN v_new_balance;
END;
$$;

COMMIT;
-- ============================================================================
-- LedgerAI Production Database Architecture (v2.0.1 - Hardened EF Core 9 Master)
-- Database Engine: PostgreSQL 16+ (Npgsql / EF Core 9 Scaffold-Ready)
-- 21 Tables | 100% Composite Tenant FKs | Batch-Tuple Integrity | Force RLS
-- Explicit Stock Reservations | Accounting-Rule Charges | Atomic Lock Helpers
-- ============================================================================

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
-- 2. DOMAIN 1: METADATA (TENANTS, USERS, CATEGORIES, UNITS, PRODUCTS, WAREHOUSES)
-- ============================================================================

CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_code VARCHAR(50) NOT NULL UNIQUE,
    business_name VARCHAR(200) NOT NULL CHECK (btrim(business_name) <> ''),
    domain_slug VARCHAR(100) UNIQUE,
    whatsapp_phone_number_id VARCHAR(100) UNIQUE,
    ntn_no VARCHAR(50),
    strn_no VARCHAR(50),
    currency_code CHAR(3) NOT NULL DEFAULT 'PKR',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    user_code VARCHAR(50) NOT NULL,
    full_name VARCHAR(150) NOT NULL CHECK (btrim(full_name) <> ''),
    email VARCHAR(254) NOT NULL,
    password_hash VARCHAR(255),
    role VARCHAR(30) NOT NULL DEFAULT 'Operator'
        CHECK (role IN ('Owner','Admin','Manager','Operator','Viewer')),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_users_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT uq_users_tenant_code UNIQUE (tenant_id, user_code),
    CONSTRAINT uq_users_tenant_email UNIQUE (tenant_id, email)
);

CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    name VARCHAR(150) NOT NULL CHECK (btrim(name) <> ''),
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_categories_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT uq_categories_tenant_name UNIQUE (tenant_id, name)
);

CREATE TABLE units_of_measure (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    unit_code VARCHAR(30) NOT NULL CHECK (btrim(unit_code) <> ''),
    name VARCHAR(80) NOT NULL CHECK (btrim(name) <> ''),
    allow_fractional BOOLEAN NOT NULL DEFAULT FALSE,
    aliases JSONB NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(aliases) = 'array'),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_uom_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT uq_uom_tenant_code UNIQUE (tenant_id, unit_code),
    CONSTRAINT uq_uom_tenant_name UNIQUE (tenant_id, name)
);

CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    product_code VARCHAR(50) NOT NULL,
    name VARCHAR(250) NOT NULL CHECK (btrim(name) <> ''),
    category_id UUID REFERENCES categories(id) ON DELETE SET NULL,
    base_unit_id UUID NOT NULL REFERENCES units_of_measure(id) ON DELETE RESTRICT,
    secondary_unit_id UUID REFERENCES units_of_measure(id) ON DELETE SET NULL,
    pack_size NUMERIC(18,4) NOT NULL DEFAULT 1 CHECK (pack_size > 0),
    barcode VARCHAR(150),
    default_purchase_price NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (default_purchase_price >= 0),
    weighted_avg_cost NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (weighted_avg_cost >= 0),
    default_sales_price NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (default_sales_price >= 0),
    minimum_stock NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (minimum_stock >= 0),
    is_service BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    attributes JSONB NOT NULL DEFAULT '{"aliases": []}'::jsonb
        CHECK (jsonb_typeof(attributes) = 'object'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_products_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT uq_products_tenant_code UNIQUE (tenant_id, product_code),
    CONSTRAINT fk_products_tenant_category FOREIGN KEY (tenant_id, category_id) REFERENCES categories(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_products_tenant_base_unit FOREIGN KEY (tenant_id, base_unit_id) REFERENCES units_of_measure(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_products_tenant_sec_unit FOREIGN KEY (tenant_id, secondary_unit_id) REFERENCES units_of_measure(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_products_aliases_array CHECK (
        NOT (attributes ? 'aliases') OR jsonb_typeof(attributes->'aliases') = 'array'
    )
);

CREATE TABLE warehouses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    warehouse_code VARCHAR(50) NOT NULL,
    name VARCHAR(150) NOT NULL CHECK (btrim(name) <> ''),
    address TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_warehouses_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT uq_warehouses_tenant_code UNIQUE (tenant_id, warehouse_code)
);

-- ============================================================================
-- 3. DOMAIN 2: ACCOUNTING (PARTY REGISTER, UDHAAR KHATA & FIFO ALLOCATIONS)
-- ============================================================================

CREATE TABLE accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    account_code VARCHAR(50) NOT NULL,
    account_type VARCHAR(30) NOT NULL CHECK (account_type IN (
        'CUSTOMER','SUPPLIER','BANK','CASH','EXPENSE','TRANSPORTER','INVESTOR'
    )),
    sub_category VARCHAR(100),
    name VARCHAR(200) NOT NULL CHECK (btrim(name) <> ''),
    cnic_no VARCHAR(50),
    phone_no VARCHAR(50),
    mobile_no VARCHAR(50),
    whatsapp_wamid_ref VARCHAR(100),
    email VARCHAR(254),
    ntn_no VARCHAR(50),
    strn_no VARCHAR(50),
    iban_no VARCHAR(100),
    bank_account_no VARCHAR(100),
    contact_person VARCHAR(250),
    cp_contact_no VARCHAR(100),
    address TEXT,
    business_address TEXT,
    remarks TEXT,
    opening_balance NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (opening_balance >= 0),
    opening_balance_type VARCHAR(2) CHECK (opening_balance_type IN ('DR','CR')),
    current_balance NUMERIC(18,4) NOT NULL DEFAULT 0,
    credit_limit NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (credit_limit >= 0),
    reserved_credit NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (reserved_credit >= 0),
    risk_tier VARCHAR(20) NOT NULL DEFAULT 'LOW'
        CHECK (risk_tier IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata) = 'object'),
    created_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    modified_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    modified_at TIMESTAMPTZ,
    CONSTRAINT uq_accounts_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT uq_accounts_tenant_code UNIQUE (tenant_id, account_code),
    CONSTRAINT fk_accounts_tenant_created_by FOREIGN KEY (tenant_id, created_by) REFERENCES users(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_accounts_tenant_modified_by FOREIGN KEY (tenant_id, modified_by) REFERENCES users(tenant_id, id) ON DELETE RESTRICT
);

-- ============================================================================
-- 4. DOMAIN 3: INVENTORY (HARDENED STOCK ITEMS, BATCHES, RESERVATIONS & MOVEMENTS)
-- ============================================================================

CREATE TABLE stock_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    warehouse_id UUID NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    quantity_on_hand NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (quantity_on_hand >= 0),
    quantity_reserved NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_stock_items_warehouse_product UNIQUE (tenant_id, warehouse_id, product_id),
    CONSTRAINT fk_stock_items_tenant_warehouse FOREIGN KEY (tenant_id, warehouse_id) REFERENCES warehouses(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_stock_items_tenant_product FOREIGN KEY (tenant_id, product_id) REFERENCES products(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_stock_reserved_not_above_on_hand CHECK (quantity_reserved <= quantity_on_hand)
);

CREATE TABLE stock_batches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    warehouse_id UUID NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    batch_code VARCHAR(100) NOT NULL CHECK (btrim(batch_code) <> ''),
    unit_cost NUMERIC(18,4) NOT NULL CHECK (unit_cost >= 0),
    quantity_on_hand NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (quantity_on_hand >= 0),
    quantity_reserved NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
    manufactured_at DATE,
    expires_at DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_stock_batches_tenant_id UNIQUE (tenant_id, id),
    -- Issue 3 Fix: Composite tuple key ensures any FK referencing a batch matches its exact warehouse & product
    CONSTRAINT uq_stock_batches_tuple UNIQUE (tenant_id, id, warehouse_id, product_id),
    CONSTRAINT uq_stock_batches_code UNIQUE (tenant_id, warehouse_id, product_id, batch_code),
    CONSTRAINT fk_stock_batches_tenant_warehouse FOREIGN KEY (tenant_id, warehouse_id) REFERENCES warehouses(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_stock_batches_tenant_product FOREIGN KEY (tenant_id, product_id) REFERENCES products(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_batches_reserved_le_on_hand CHECK (quantity_reserved <= quantity_on_hand)
);

-- Issue 5 Fix: Trigger-depth guard blocks ANY direct SQL statement on stock_items, even inside the same transaction
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

CREATE TRIGGER trg_guard_stock_items_direct_write
BEFORE INSERT OR UPDATE OR DELETE ON stock_items
FOR EACH ROW EXECUTE FUNCTION ledgerai_guard_stock_items_direct_write();

-- Concurrency-safe SECURITY DEFINER recalculation with fixed search_path
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

    INSERT INTO stock_items (tenant_id, warehouse_id, product_id, quantity_on_hand, quantity_reserved, updated_at)
    VALUES (p_tenant_id, p_warehouse_id, p_product_id, v_on_hand, v_reserved, now())
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

CREATE TRIGGER trg_sync_stock_items_from_batches
AFTER INSERT OR UPDATE OF quantity_on_hand, quantity_reserved, warehouse_id, product_id OR DELETE ON stock_batches
FOR EACH ROW EXECUTE FUNCTION ledgerai_sync_stock_items();

CREATE VIEW v_product_stock_totals WITH (security_invoker = true) AS
SELECT
    tenant_id,
    product_id,
    SUM(quantity_on_hand) AS total_current_stock,
    SUM(quantity_reserved) AS total_reserved_stock,
    SUM(quantity_on_hand - quantity_reserved) AS total_available_stock
FROM stock_items
GROUP BY tenant_id, product_id;

CREATE TABLE stock_movements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    warehouse_id UUID NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    batch_id UUID NOT NULL REFERENCES stock_batches(id) ON DELETE RESTRICT,
    movement_type VARCHAR(30) NOT NULL CHECK (movement_type IN (
        'PURCHASE','SALE','SALES_RETURN','PURCHASE_RETURN',
        'TRANSFER_IN','TRANSFER_OUT','DAMAGE_EXPIRY','ADJUSTMENT'
    )),
    quantity_delta NUMERIC(18,4) NOT NULL CHECK (quantity_delta <> 0),
    unit_cost NUMERIC(18,4) NOT NULL CHECK (unit_cost >= 0),
    reference_type VARCHAR(30) NOT NULL,
    reference_id UUID NOT NULL,
    notes TEXT,
    created_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_stock_movements_tenant_warehouse FOREIGN KEY (tenant_id, warehouse_id) REFERENCES warehouses(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_stock_movements_tenant_product FOREIGN KEY (tenant_id, product_id) REFERENCES products(tenant_id, id) ON DELETE RESTRICT,
    -- Issue 3 Fix: Enforces batch belongs to exact (tenant, warehouse, product)
    CONSTRAINT fk_stock_movements_batch_tuple FOREIGN KEY (tenant_id, batch_id, warehouse_id, product_id) REFERENCES stock_batches(tenant_id, id, warehouse_id, product_id) ON DELETE RESTRICT,
    CONSTRAINT fk_stock_movements_tenant_created_by FOREIGN KEY (tenant_id, created_by) REFERENCES users(tenant_id, id) ON DELETE RESTRICT
);

-- ============================================================================
-- 5. DOMAIN 4: INVOICING & FINANCE (ORDERS, RESERVATIONS, 00/01 INVOICES & CHARGES)
-- ============================================================================

CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    order_code VARCHAR(100) NOT NULL,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
    order_status VARCHAR(30) NOT NULL DEFAULT 'PENDING_APPROVAL'
        CHECK (order_status IN ('PENDING_APPROVAL','VALIDATED','COMMITTED','REJECTED','CANCELLED')),
    payment_terms VARCHAR(20) NOT NULL DEFAULT 'CREDIT'
        CHECK (payment_terms IN ('CASH','CREDIT','PARTIAL')),
    total_amount NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    upfront_paid_amount NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (upfront_paid_amount >= 0),
    ai_confidence_score NUMERIC(5,4) CHECK (ai_confidence_score BETWEEN 0 AND 1),
    requires_approval BOOLEAN NOT NULL DEFAULT FALSE,
    approval_reason VARCHAR(100),
    approved_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    approved_at TIMESTAMPTZ,
    idempotency_key VARCHAR(150) NOT NULL,
    raw_intent_summary TEXT,
    execution_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    committed_at TIMESTAMPTZ,
    CONSTRAINT uq_orders_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT uq_orders_tenant_code UNIQUE (tenant_id, order_code),
    CONSTRAINT uq_orders_tenant_idempotency UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT fk_orders_tenant_account FOREIGN KEY (tenant_id, account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_orders_tenant_approved_by FOREIGN KEY (tenant_id, approved_by) REFERENCES users(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_orders_tenant_created_by FOREIGN KEY (tenant_id, created_by) REFERENCES users(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_orders_upfront_le_total CHECK (upfront_paid_amount <= total_amount),
    CONSTRAINT ck_orders_approval_fields CHECK (
        (approved_by IS NULL AND approved_at IS NULL) OR
        (approved_by IS NOT NULL AND approved_at IS NOT NULL)
    )
);

CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    warehouse_id UUID NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,
    batch_id UUID REFERENCES stock_batches(id) ON DELETE RESTRICT,
    ordered_unit_id UUID NOT NULL REFERENCES units_of_measure(id) ON DELETE RESTRICT,
    ordered_quantity NUMERIC(18,4) NOT NULL CHECK (ordered_quantity > 0),
    ordered_unit_price NUMERIC(18,4) NOT NULL CHECK (ordered_unit_price >= 0),
    conversion_factor NUMERIC(18,6) NOT NULL DEFAULT 1 CHECK (conversion_factor > 0),
    base_quantity NUMERIC(18,4) NOT NULL CHECK (base_quantity > 0),
    unit_cost_at_sale NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (unit_cost_at_sale >= 0),
    total_price NUMERIC(18,4) GENERATED ALWAYS AS (round(ordered_quantity * ordered_unit_price, 4)) STORED,
    total_cost NUMERIC(18,4) GENERATED ALWAYS AS (round(base_quantity * unit_cost_at_sale, 4)) STORED,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_order_items_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT uq_order_items_tenant_order_item UNIQUE (tenant_id, order_id, id),
    CONSTRAINT fk_order_items_tenant_order FOREIGN KEY (tenant_id, order_id) REFERENCES orders(tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT fk_order_items_tenant_product FOREIGN KEY (tenant_id, product_id) REFERENCES products(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_order_items_tenant_warehouse FOREIGN KEY (tenant_id, warehouse_id) REFERENCES warehouses(tenant_id, id) ON DELETE RESTRICT,
    -- Issue 3 Fix: Enforces batch belongs to exact (tenant, warehouse, product) when batch_id is set
    CONSTRAINT fk_order_items_batch_tuple FOREIGN KEY (tenant_id, batch_id, warehouse_id, product_id) REFERENCES stock_batches(tenant_id, id, warehouse_id, product_id) ON DELETE RESTRICT,
    CONSTRAINT fk_order_items_tenant_unit FOREIGN KEY (tenant_id, ordered_unit_id) REFERENCES units_of_measure(tenant_id, id) ON DELETE RESTRICT
);

-- Issue 1 Fix: Explicit Order-to-Batch Stock Reservation Ownership Table (#21)
CREATE TABLE stock_reservations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    order_item_id UUID NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
    warehouse_id UUID NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    batch_id UUID NOT NULL REFERENCES stock_batches(id) ON DELETE RESTRICT,
    reserved_quantity NUMERIC(18,4) NOT NULL CHECK (reserved_quantity > 0),
    released_quantity NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (released_quantity >= 0),
    committed_quantity NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (committed_quantity >= 0),
    status VARCHAR(25) NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE','PARTIALLY_RELEASED','RELEASED','COMMITTED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_stock_reservations_item_batch UNIQUE (tenant_id, order_item_id, batch_id),
    CONSTRAINT fk_reservations_tenant_order_item FOREIGN KEY (tenant_id, order_id, order_item_id) REFERENCES order_items(tenant_id, order_id, id) ON DELETE CASCADE,
    CONSTRAINT fk_reservations_batch_tuple FOREIGN KEY (tenant_id, batch_id, warehouse_id, product_id) REFERENCES stock_batches(tenant_id, id, warehouse_id, product_id) ON DELETE RESTRICT,
    CONSTRAINT ck_reservations_qty_balance CHECK (released_quantity + committed_quantity <= reserved_quantity)
);

-- Unified 00 (PURCHASE) & 01 (SALE) Invoicing Table
CREATE TABLE invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    invoice_type VARCHAR(20) NOT NULL CHECK (invoice_type IN ('PURCHASE','SALE')),
    voucher_series CHAR(2) GENERATED ALWAYS AS (
        CASE WHEN invoice_type = 'PURCHASE' THEN '00' ELSE '01' END
    ) STORED,
    invoice_number VARCHAR(100) NOT NULL,
    order_id UUID REFERENCES orders(id) ON DELETE RESTRICT,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
    warehouse_id UUID REFERENCES warehouses(id) ON DELETE RESTRICT,
    transporter_account_id UUID REFERENCES accounts(id) ON DELETE RESTRICT,
    bilty_number VARCHAR(100),
    invoice_status VARCHAR(20) NOT NULL DEFAULT 'ISSUED'
        CHECK (invoice_status IN ('DRAFT','ISSUED','PARTIALLY_PAID','PAID','VOID')),
    subtotal_amount NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (subtotal_amount >= 0),
    discount_amount NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    tax_amount NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    grand_total NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (grand_total >= 0),
    amount_paid NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (amount_paid >= 0),
    balance_due NUMERIC(18,4) GENERATED ALWAYS AS (GREATEST(grand_total - amount_paid, 0)) STORED,
    due_date DATE,
    idempotency_key VARCHAR(150) NOT NULL,
    notes TEXT,
    issued_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    issued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_invoices_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT uq_invoices_tenant_type_number UNIQUE (tenant_id, invoice_type, invoice_number),
    CONSTRAINT uq_invoices_tenant_idempotency UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT fk_invoices_tenant_order FOREIGN KEY (tenant_id, order_id) REFERENCES orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_invoices_tenant_account FOREIGN KEY (tenant_id, account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_invoices_tenant_warehouse FOREIGN KEY (tenant_id, warehouse_id) REFERENCES warehouses(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_invoices_tenant_transporter FOREIGN KEY (tenant_id, transporter_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_invoices_tenant_issued_by FOREIGN KEY (tenant_id, issued_by) REFERENCES users(tenant_id, id) ON DELETE RESTRICT,
    -- Issue 7 Fix: Financial reconciliation constraints
    CONSTRAINT ck_invoices_paid_le_grand_total CHECK (amount_paid <= grand_total),
    CONSTRAINT ck_invoices_discount_le_subtotal CHECK (discount_amount <= subtotal_amount),
    CONSTRAINT ck_invoices_status_paid_consistency CHECK (
        (invoice_status = 'PAID' AND amount_paid = grand_total) OR
        (invoice_status <> 'PAID')
    )
);

CREATE TABLE invoice_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    invoice_id UUID NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    order_item_id UUID REFERENCES order_items(id) ON DELETE RESTRICT,
    warehouse_id UUID NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    batch_id UUID NOT NULL REFERENCES stock_batches(id) ON DELETE RESTRICT,
    unit_id UUID NOT NULL REFERENCES units_of_measure(id) ON DELETE RESTRICT,
    quantity NUMERIC(18,4) NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(18,4) NOT NULL CHECK (unit_price >= 0),
    discount_amount NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    tax_rate NUMERIC(6,4) NOT NULL DEFAULT 0 CHECK (tax_rate BETWEEN 0 AND 100),
    tax_amount NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    conversion_factor NUMERIC(18,6) NOT NULL DEFAULT 1 CHECK (conversion_factor > 0),
    base_quantity NUMERIC(18,4) NOT NULL CHECK (base_quantity > 0),
    base_unit_cost NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (base_unit_cost >= 0),
    line_total NUMERIC(18,4) GENERATED ALWAYS AS (round((quantity * unit_price) - discount_amount + tax_amount, 4)) STORED,
    line_cogs NUMERIC(18,4) GENERATED ALWAYS AS (round(base_quantity * base_unit_cost, 4)) STORED,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_invoice_items_tenant_invoice FOREIGN KEY (tenant_id, invoice_id) REFERENCES invoices(tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT fk_invoice_items_tenant_order_item FOREIGN KEY (tenant_id, order_item_id) REFERENCES order_items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_invoice_items_tenant_warehouse FOREIGN KEY (tenant_id, warehouse_id) REFERENCES warehouses(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_invoice_items_tenant_product FOREIGN KEY (tenant_id, product_id) REFERENCES products(tenant_id, id) ON DELETE RESTRICT,
    -- Issue 3 Fix: Enforces batch belongs to exact (tenant, warehouse, product)
    CONSTRAINT fk_invoice_items_batch_tuple FOREIGN KEY (tenant_id, batch_id, warehouse_id, product_id) REFERENCES stock_batches(tenant_id, id, warehouse_id, product_id) ON DELETE RESTRICT,
    CONSTRAINT fk_invoice_items_tenant_unit FOREIGN KEY (tenant_id, unit_id) REFERENCES units_of_measure(tenant_id, id) ON DELETE RESTRICT,
    -- Issue 7 Fix: Line discount cannot exceed gross line amount
    CONSTRAINT ck_invoice_items_discount_le_gross CHECK (discount_amount <= round(quantity * unit_price, 4))
);

-- Issue 7 Fix: Explicit Accounting Rules & Direction on Invoice Charges
CREATE TABLE invoice_charges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    invoice_id UUID NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    charge_type VARCHAR(40) NOT NULL CHECK (charge_type IN (
        'FREIGHT_BILTY','LABOR_MAZDOORI','DELIVERY_OUTBOUND',
        'WHT_236G','WHT_236H','WEIGHING_KANTA','KASAR_WAIVER','OTHER'
    )),
    charge_direction VARCHAR(20) NOT NULL DEFAULT 'ADD_TO_BILL'
        CHECK (charge_direction IN ('ADD_TO_BILL','DEDUCT_FROM_BILL','MEMO_ONLY')),
    accounting_treatment VARCHAR(30) NOT NULL
        CHECK (accounting_treatment IN (
            'CAPITALIZE_LANDED_COST', -- Added into product WAC on 00 Purchase
            'FULFILLMENT_EXPENSE',    -- Deducted from Gross Profit on 01 Sale
            'TAX_PASS_THROUGH',       -- FBR WHT 236G/236H (does not distort product margin)
            'DISCOUNT_WAIVER'         -- Kasar / settlement concession
        )),
    payable_account_id UUID REFERENCES accounts(id) ON DELETE RESTRICT,
    amount NUMERIC(18,4) NOT NULL CHECK (amount > 0),
    notes VARCHAR(250),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_invoice_charges_tenant_invoice FOREIGN KEY (tenant_id, invoice_id) REFERENCES invoices(tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT fk_invoice_charges_tenant_payable FOREIGN KEY (tenant_id, payable_account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT
);

CREATE VIEW v_invoice_profit_summary WITH (security_invoker = true) AS
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
-- 6. DOMAIN 2B: ACCOUNTING LEDGER & FIFO PAYMENT ALLOCATIONS
-- ============================================================================

CREATE TABLE ledger_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
    order_id UUID REFERENCES orders(id) ON DELETE RESTRICT,
    invoice_id UUID REFERENCES invoices(id) ON DELETE RESTRICT,
    entry_type VARCHAR(20) NOT NULL CHECK (entry_type IN ('DEBIT','CREDIT')),
    amount NUMERIC(18,4) NOT NULL CHECK (amount > 0),
    running_balance NUMERIC(18,4) NOT NULL,
    notes TEXT,
    idempotency_key VARCHAR(150),
    reverses_entry_id UUID REFERENCES ledger_entries(id) ON DELETE RESTRICT,
    created_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_ledger_entries_tenant_id UNIQUE (tenant_id, id),
    -- Issue 8 Fix: Enables composite FK ensuring reversals belong to same tenant AND account
    CONSTRAINT uq_ledger_entries_tenant_account_id UNIQUE (tenant_id, account_id, id),
    CONSTRAINT uq_ledger_entries_tenant_idempotency UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT uq_ledger_entries_invoice_entry UNIQUE (tenant_id, invoice_id, entry_type),
    -- Issue 8 Fix: Prevent reversing the same ledger entry more than once
    CONSTRAINT uq_ledger_entries_single_reversal UNIQUE (tenant_id, reverses_entry_id),
    CONSTRAINT ck_ledger_no_self_reversal CHECK (reverses_entry_id IS NULL OR reverses_entry_id <> id),
    CONSTRAINT fk_ledger_entries_tenant_account FOREIGN KEY (tenant_id, account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_ledger_entries_tenant_order FOREIGN KEY (tenant_id, order_id) REFERENCES orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_ledger_entries_tenant_invoice FOREIGN KEY (tenant_id, invoice_id) REFERENCES invoices(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_ledger_entries_same_account_reversal FOREIGN KEY (tenant_id, account_id, reverses_entry_id) REFERENCES ledger_entries(tenant_id, account_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_ledger_entries_tenant_created_by FOREIGN KEY (tenant_id, created_by) REFERENCES users(tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE ledger_allocations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
    debit_entry_id UUID NOT NULL REFERENCES ledger_entries(id) ON DELETE RESTRICT,
    credit_entry_id UUID NOT NULL REFERENCES ledger_entries(id) ON DELETE RESTRICT,
    amount NUMERIC(18,4) NOT NULL CHECK (amount > 0),
    created_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_alloc_pair UNIQUE (tenant_id, debit_entry_id, credit_entry_id),
    CONSTRAINT fk_allocations_tenant_account FOREIGN KEY (tenant_id, account_id) REFERENCES accounts(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_allocations_tenant_debit FOREIGN KEY (tenant_id, account_id, debit_entry_id) REFERENCES ledger_entries(tenant_id, account_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_allocations_tenant_credit FOREIGN KEY (tenant_id, account_id, credit_entry_id) REFERENCES ledger_entries(tenant_id, account_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_allocations_tenant_created_by FOREIGN KEY (tenant_id, created_by) REFERENCES users(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_alloc_distinct_entries CHECK (debit_entry_id <> credit_entry_id)
);

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

CREATE TRIGGER trg_validate_ledger_allocation
BEFORE INSERT OR UPDATE ON ledger_allocations
FOR EACH ROW EXECUTE FUNCTION ledgerai_validate_allocation();

-- ============================================================================
-- 7. DOMAIN 5: AI & OPERATIONS (WHATSAPP INGRESS, OUTBOX & IMMUTABLE AUDIT LOGS)
-- ============================================================================

CREATE TABLE inbound_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    wamid VARCHAR(150) NOT NULL UNIQUE,
    sender_phone VARCHAR(50) NOT NULL,
    channel VARCHAR(30) NOT NULL DEFAULT 'WhatsApp'
        CHECK (channel IN ('WhatsApp','Web','Voice','Other')),
    raw_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    audio_media_id VARCHAR(255),
    transcription_text TEXT,
    processing_status VARCHAR(30) NOT NULL DEFAULT 'RECEIVED'
        CHECK (processing_status IN ('RECEIVED','PROCESSING','PROCESSED','FAILED','IGNORED')),
    matched_order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
    ai_confidence_score NUMERIC(5,4) CHECK (ai_confidence_score BETWEEN 0 AND 1),
    error_log TEXT,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at TIMESTAMPTZ,
    CONSTRAINT fk_inbound_tenant_order FOREIGN KEY (tenant_id, matched_order_id) REFERENCES orders(tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE outbox_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    event_type VARCHAR(100) NOT NULL,
    dedupe_key VARCHAR(180) NOT NULL,
    payload JSONB NOT NULL,
    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    available_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    locked_at TIMESTAMPTZ,
    processed_at TIMESTAMPTZ,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_outbox_tenant_dedupe UNIQUE (tenant_id, dedupe_key)
);

-- Issue 4 Fix: ON DELETE RESTRICT + actor_snapshot prevents user deletion from colliding with immutability
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    user_id UUID REFERENCES users(id) ON DELETE RESTRICT,
    actor_snapshot VARCHAR(200) NOT NULL DEFAULT 'SYSTEM',
    action_taken VARCHAR(100) NOT NULL,
    entity_name VARCHAR(80) NOT NULL,
    entity_id UUID,
    old_values JSONB,
    new_values JSONB,
    correlation_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_audit_logs_tenant_user FOREIGN KEY (tenant_id, user_id) REFERENCES users(tenant_id, id) ON DELETE RESTRICT
);

CREATE OR REPLACE FUNCTION ledgerai_prevent_audit_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'audit_logs is append-only and cannot be updated or deleted.'
        USING ERRCODE = '42501';
END;
$$;

CREATE TRIGGER trg_audit_logs_immutable
BEFORE UPDATE OR DELETE ON audit_logs
FOR EACH ROW EXECUTE FUNCTION ledgerai_prevent_audit_mutation();

-- ============================================================================
-- 8. INDEXES & PERFORMANCE OPTIMIZATIONS
-- ============================================================================

CREATE INDEX idx_users_tenant_active ON users(tenant_id, is_active);
CREATE INDEX idx_accounts_tenant_type_active ON accounts(tenant_id, account_type, is_active) WHERE is_deleted = FALSE;
CREATE INDEX idx_accounts_tenant_phone ON accounts(tenant_id, phone_no) WHERE phone_no IS NOT NULL;
CREATE INDEX idx_accounts_tenant_mobile ON accounts(tenant_id, mobile_no) WHERE mobile_no IS NOT NULL;
CREATE INDEX idx_uom_aliases_gin ON units_of_measure USING gin(aliases jsonb_path_ops);
CREATE INDEX idx_products_attributes_gin ON products USING gin(attributes jsonb_path_ops);
CREATE INDEX idx_products_tenant_name ON products(tenant_id, lower(name)) WHERE is_deleted = FALSE;
CREATE INDEX idx_products_category ON products(tenant_id, category_id);
CREATE INDEX idx_stock_items_product ON stock_items(tenant_id, product_id);
CREATE INDEX idx_stock_batches_fefo ON stock_batches(tenant_id, warehouse_id, product_id, expires_at ASC NULLS LAST, created_at ASC);
CREATE INDEX idx_stock_movements_product ON stock_movements(tenant_id, product_id, created_at DESC);
CREATE INDEX idx_stock_movements_ref ON stock_movements(tenant_id, reference_type, reference_id);
CREATE INDEX idx_orders_tenant_status_created ON orders(tenant_id, order_status, created_at DESC);
CREATE INDEX idx_orders_account_created ON orders(tenant_id, account_id, created_at DESC);
CREATE INDEX idx_order_items_order ON order_items(tenant_id, order_id);
CREATE INDEX idx_order_items_product ON order_items(tenant_id, product_id);
CREATE INDEX idx_stock_reservations_order ON stock_reservations(tenant_id, order_id, status);
CREATE INDEX idx_stock_reservations_batch ON stock_reservations(tenant_id, batch_id, status);
CREATE INDEX idx_invoices_type_account_status ON invoices(tenant_id, invoice_type, account_id, invoice_status, issued_at DESC);
CREATE INDEX idx_invoices_order ON invoices(tenant_id, order_id) WHERE order_id IS NOT NULL;
CREATE INDEX idx_invoice_items_invoice ON invoice_items(tenant_id, invoice_id);
CREATE INDEX idx_invoice_charges_invoice ON invoice_charges(tenant_id, invoice_id);
CREATE INDEX idx_ledger_account_created ON ledger_entries(tenant_id, account_id, created_at DESC);
CREATE INDEX idx_ledger_order ON ledger_entries(tenant_id, order_id) WHERE order_id IS NOT NULL;
CREATE INDEX idx_ledger_invoice ON ledger_entries(tenant_id, invoice_id) WHERE invoice_id IS NOT NULL;
CREATE INDEX idx_allocations_credit ON ledger_allocations(tenant_id, credit_entry_id);
CREATE INDEX idx_allocations_debit ON ledger_allocations(tenant_id, debit_entry_id);
CREATE INDEX idx_inbound_tenant_received ON inbound_messages(tenant_id, received_at DESC);
CREATE INDEX idx_inbound_pending ON inbound_messages(received_at) WHERE processing_status IN ('RECEIVED','PROCESSING');
CREATE INDEX idx_outbox_ready ON outbox_events(available_at, created_at) WHERE processed_at IS NULL;
CREATE INDEX idx_audit_entity ON audit_logs(tenant_id, entity_name, entity_id, created_at DESC);

-- ============================================================================
-- 9. ROW-LEVEL SECURITY (RLS) POLICIES (ALL 21 TABLES)
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
-- 10. OWNERSHIP-AWARE ATOMIC LOCK HELPERS (ISSUES 1 & 6 FIXED)
-- ============================================================================

-- Helper 1: Reserve batch stock AND record explicit order_item -> batch ownership
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
        tenant_id, order_id, order_item_id, warehouse_id, product_id, batch_id,
        reserved_quantity, status
    )
    VALUES (
        p_tenant_id, p_order_id, p_order_item_id, v_warehouse_id, v_product_id, p_batch_id,
        p_base_qty, 'ACTIVE'
    )
    RETURNING id INTO v_reservation_id;

    RETURN v_reservation_id;
END;
$$;

-- Helper 2: Release stock by reservation_id (fails on over-release; never hides bugs)
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

-- Helper 3: Commit reserved stock (or direct walk-in deduction when p_reservation_id IS NULL)
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

-- Helper 4: Atomically lock account row, enforce credit limit & reservation bounds, and return new balance
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

-- ============================================================================
-- 11. RECOMMENDED ROLE GRANTS (RUN FOR YOUR .NET APPLICATION DB ROLE)
-- ============================================================================
-- Replace `ledgerai_app_user` with your actual PostgreSQL connection user:
-- REVOKE INSERT, UPDATE, DELETE ON stock_items FROM ledgerai_app_user;
-- REVOKE UPDATE, DELETE ON audit_logs FROM ledgerai_app_user;
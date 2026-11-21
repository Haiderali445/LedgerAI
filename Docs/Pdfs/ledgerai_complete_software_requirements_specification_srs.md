# Software Requirements Specification (SRS)
## LedgerAI: An Event-Driven B2B Multi-Tenant ERP and Wholesale Credit Ledger with Integrated AI Agentic Workflows

**Document ID:** `SRS-LEDGERAI-2026-V1.0`  
**Standard Compliance:** IEEE Std 830-1998 / ISO/IEC/IEEE 29148:2018  
**Version:** 1.0 (Complete Production & Academic Baseline)  
**Date:** November 2026  
**Prepared By:**  
* **Haider Ali** (`23014198-097`) — Project Manager, Backend Architect & Database Engineer  
* **Ibtisam Kashif** (`23014198-083`) — AI Orchestration, NLP Pipeline & QA Engineer  
* **Fazina Mukhtar** (`23014198-088`) — Frontend Lead (React PWA) & UX Engineer  

**Supervised By:** Prof. Muhammad Tauqeer ul Amin  
**Institution:** Department of Software Engineering, Faculty of Computing & Information Technology, University of Gujrat, Punjab, Pakistan  

---

## Table of Contents
1. [Introduction](#1-introduction)
2. [Overall Description](#2-overall-description)
3. [External Interface Requirements](#3-external-interface-requirements)
4. [System Features & Functional Requirements](#4-system-features--functional-requirements)
5. [Domain Mathematical, Accounting & Risk Specifications](#5-domain-mathematical--accounting--risk-specifications)
6. [Data Requirements & Database Constraints](#6-data-requirements--database-constraints)
7. [Non-Functional Requirements (NFRs)](#7-non-functional-requirements-nfrs)
8. [Assumptions, Constraints, Dependencies & Exclusions](#8-assumptions-constraints-dependencies--exclusions)
9. [Requirements Traceability Matrix (RTM)](#9-requirements-traceability-matrix-rtm)

---

## 1. Introduction

### 1.1 Purpose
This Software Requirements Specification (SRS) defines the complete functional, non-functional, mathematical, data, security, and external interface requirements for **LedgerAI**. It serves as the authoritative engineering contract for backend implementation (`LedgerAI.Api` in `.NET 9`), database administration (`PostgreSQL 16+` / Supabase), AI pipeline development (`Microsoft Semantic Kernel`), frontend development (`React TypeScript PWA`), and academic evaluation at the University of Gujrat.

### 1.2 Document Conventions
* **Requirement Identifiers:**
  * `FR-MOD-###`: Functional Requirement grouped by module (`AUTH`, `CAT`, `INV`, `ACC`, `ORD`, `BIL`, `AI`, `COM`, `OPS`).
  * `NFR-CAT-###`: Non-Functional Requirement (`PERF`, `SEC`, `REL`, `SCAL`, `MAINT`, `OBS`).
  * `EIR-###`: External Interface Requirement (`UI`, `API`, `HW`, `SW`, `COM`).
  * `BR-###`: Business & Mathematical Rule.
* **Priority Levels (MoSCoW):**
  * **MUST (M):** Mandatory for core system operation and FYP completion.
  * **SHOULD (S):** High-value operational capability expected in production baseline.
  * **COULD (C):** Desirable enhancement if schedule permits.
* **Precision Standard:** All monetary and inventory quantity specifications adhere to exact `decimal` arithmetic rounded to 4 decimal places (`NUMERIC(18,4)`) using `MidpointRounding.AwayFromZero`.

### 1.3 Intended Audience
* **Development Team:** Backend engineers, AI/NLP developers, and frontend PWA engineers implementing system modules and API contracts.
* **Academic Evaluators & Supervisor:** Faculty reviewers assessing architectural rigor, requirement completeness, and alignment with the approved FYP proposal.
* **QA & Testing Engineers:** Testers designing unit tests, integration tests, RLS isolation audits, and load benchmarks.

### 1.4 Product Scope
**LedgerAI** is a cloud-ready, multi-tenant B2B wholesale Enterprise Resource Planning (ERP), Inventory Management System (IMS), and digitized credit ledger (*Udhaar Khata*) tailored for Pakistani wholesale distribution networks. 

The system solves two core operational challenges:
1. **Deterministic Wholesale Operations:** Provides multi-warehouse inventory management with First-Expired-First-Out (FEFO) batch tracking, Weighted Average Cost (WAC) landed valuation, unified party registers (*Customers*, *Suppliers*, *Transporters*), *Udhaar Khata* double-entry style accounting with First-In-First-Out (FIFO) payment settlement, and `00` Purchase / `01` Sale invoicing with localized Pakistani wholesale charges (*Freight/Bilty*, *Labor/Mazdoori*, *Weighing/Kanta*, *FBR WHT 236G/236H*, and *Kasar* settlement waivers).
2. **Constraint-Driven Agentic AI Automation:** Integrates an isolated multi-agent AI orchestration pipeline capable of ingesting informal Roman Urdu and English text or voice notes via WhatsApp Cloud API or PWA chat, transcribing audio via Whisper STT, normalizing intents into strictly typed JSON DTOs, enforcing confidence and credit-limit gates, and routing low-confidence or over-limit orders to human supervisors for approval.

**Critical Scope Boundary:** All core ERP/IMS modules operate **100% independently** of external AI providers. Outages or rate limits on Groq, HuggingFace, or OpenAI Whisper never block manual order creation, invoicing, stock adjustments, or ledger postings.

### 1.5 Definitions, Acronyms, and Abbreviations
| Term / Acronym | Definition |
| :--- | :--- |
| **B2B** | Business-to-Business wholesale distribution between distributors/stockists and retail shopkeepers (*Dukandars*). |
| **Bilty** | Goods transport receipt / freight charge issued by a regional goods transport agency (*Goods Adda*). |
| **DR / CR** | Debit (`DR`: increases receivable / reduces payable) and Credit (`CR`: reduces receivable / increases payable). |
| **FEFO** | First-Expired, First-Out inventory allocation policy prioritizing batches with the earliest `expires_at` date. |
| **FIFO** | First-In, First-Out payment settlement algorithm allocating incoming customer receipts against oldest unpaid debit entries. |
| **Kanta** | Commercial weighbridge weighing charge applied to bulk commodities (grains, sugar, pulses). |
| **Kasar** | Minor rounding or settlement concession waived during final bill clearance. |
| **Mazdoori** | Manual loading/unloading labor charges at wholesale warehouses/godowns. |
| **PWA** | Progressive Web App — installable web application supporting offline caching and native HTML5 `MediaRecorder`. |
| **RLS** | PostgreSQL Row-Level Security enforcing multi-tenant row isolation at the database engine layer. |
| **Udhaar Khata** | Traditional wholesale credit ledger tracking running party receivables, payables, and credit limits. |
| **UOM** | Unit of Measure (two-tier: Base Unit such as `Kg`/`Piece` and Secondary Pack Unit such as `Bora`/`Carton`). |
| **WAC** | Weighted Average Cost inventory valuation recalculated upon posting `00` Purchase invoices. |
| **WAMID** | WhatsApp Message ID used as a unique idempotency key for inbound Meta Cloud API webhooks. |
| **WHT 236G/236H** | Withholding Tax under Sections 236G and 236H of Pakistan's Income Tax Ordinance for distributors and retailers. |

### 1.6 References
1. *LedgerAI Final Year Project Proposal (Version 1.0)*, Department of Software Engineering, University of Gujrat, September 2026.
2. *LedgerAI Domain Calculation & Accounting Specification (`Mathematics Calculations and Categories.pdf`)*, November 2026.
3. *LedgerAI Production Database Architecture (`LedgerAI_Schema_v2.sql` v2.0.1)*, PostgreSQL 16+ DDL Specification.
4. *IEEE Std 830-1998 / ISO/IEC/IEEE 29148:2018*, Systems and Software Engineering — Life Cycle Processes — Requirements Engineering.

---

## 2. Overall Description

### 2.1 Product Perspective
LedgerAI is a greenfield, self-contained **Five-Tier Distributed Application** built around a **Single-Project `.NET 9` Modular Monolith (`LedgerAI.Api`)**:
* **Tier 1 — Presentation Layer:** Installable React + Vite + TypeScript + Tailwind CSS Progressive Web App (PWA) communicating over HTTPS REST and SignalR WebSockets.
* **Tier 2 — Communication & Ingress Gateway:** Meta WhatsApp Cloud API webhook receiver (HMAC-SHA256 verified), Whisper Speech-to-Text (STT) transcription client, and asynchronous Transactional Outbox dispatcher (`BackgroundService`).
* **Tier 3 — Agentic AI Orchestration Layer:** Microsoft Semantic Kernel `.NET 9` pipeline with deterministic sanitization, Groq LPU structured JSON extraction, HuggingFace failover routing (Polly v8), validation gates, and real-time SignalR telemetry logging.
* **Tier 4 — Application Core Layer:** Deterministic C# business modules (`Catalog`, `Inventory`, `Accounts`, `Orders`, `Invoicing`, `Operations`) separated strictly into Domain Entities (`Modules/*/Entities`) and Data Transfer Objects (`Data/Dtos/`), coordinated by a Unit of Work (`IUnitOfWork`).
* **Tier 5 — Persistence Layer:** PostgreSQL 16+ (local or Supabase-hosted) enforcing composite-tenant foreign keys, `FORCE ROW LEVEL SECURITY`, trigger-driven stock aggregation, immutable audit logs, and atomic `FOR UPDATE` concurrency functions.

### 2.2 Product Functions Summary
1. **Multi-Tenant Identity & RBAC:** Tenant onboarding, JWT authentication, and 5-tier role enforcement (`Owner`, `Admin`, `Manager`, `Operator`, `Viewer`).
2. **Bilingual Wholesale Catalog:** Hierarchical categories, two-tier UOMs (`Base` + `Secondary` pack conversions), fractional rules, and JSONB Roman Urdu aliases.
3. **Multi-Warehouse FEFO Inventory:** Batch-level stock tracking, automatic FEFO picking, explicit order-to-batch reservations, transfer/adjustment movements, and trigger-guarded warehouse totals.
4. **Party Register & Udhaar Khata:** Customer, Supplier, Transporter, Bank, Cash, Expense, and Investor accounts with credit limits, reserved credit exposure, aging buckets, risk tiers, and FIFO payment allocations.
5. **Order Lifecycle & Approval Routing:** Manual and AI-drafted orders with automated routing to `PENDING_APPROVAL` when `ai_confidence_score < 0.85` or `credit_exposure` breaches `credit_limit`.
6. **Dual-Series Voucher Invoicing (`00` & `01`):** Purchase (`00`) vouchers capitalizing landed freight/labor into batch cost and WAC; Sale (`01`) vouchers committing stock reservations, calculating COGS/gross profit, and applying localized charges.
7. **Conversational AI & Real-Time Telemetry:** Roman Urdu voice/text parsing into validated JSON order proposals with live step-by-step agent decision streaming to the frontend.

### 2.3 User Classes and Characteristics
| User Class | Role Code | Technical Proficiency | Primary Responsibilities & Access Scope |
| :--- | :--- | :--- | :--- |
| **Business Owner / Tenant Admin** | `Owner` / `Admin` | Moderate | Full tenant configuration, user provisioning, credit limit overrides, high-risk order approvals, profit analytics, and audit review. |
| **Warehouse / Godown Manager** | `Manager` | Basic–Moderate | Stock batch intake (`00` Purchase), inter-warehouse transfers, stock adjustments, expiry monitoring, and dispatch verification. |
| **Accountant / Munshi** | `Manager` / `Operator` | Moderate | *Udhaar Khata* ledger reconciliation, customer payment receipts (FIFO allocation), supplier settlements, WHT/Bilty charge entries. |
| **Sales / Billing Operator** | `Operator` | Basic | Fast manual order entry, `01` Sale invoice generation, reviewing AI-drafted WhatsApp orders, and printing/sharing vouchers. |
| **Read-Only Auditor** | `Viewer` | Moderate | Read-only access to ledger statements, stock reports, and immutable audit trails. |
| **Retail Buyer (External Actor)** | *External (WhatsApp/PWA)* | Basic (Smartphone) | Places orders in Roman Urdu/English text or voice notes via WhatsApp or PWA chat and receives order/invoice confirmations. |

### 2.4 Operating Environment
* **Backend Server Runtime:** `.NET 9.0 SDK / Runtime (C# 13)` running on Kestrel (Windows 11 development on ports `7274`/`5284`; Ubuntu 22.04/24.04 LTS Linux VPS in production, optionally containerized via Docker).
* **Database Engine:** `PostgreSQL 16+` (supporting both local native/Docker instances and managed **Supabase PostgreSQL** via Supavisor session/transaction pooling over SSL/TLS).
* **Client Environment:** Modern evergreen browsers (Google Chrome, Microsoft Edge, Safari, Firefox) on Android, iOS, Windows, and macOS supporting Service Workers (PWA) and HTML5 `MediaRecorder` API.
* **External Cloud APIs:** Meta WhatsApp Cloud API (`v20.0+`), Groq Cloud LPU API (`OpenAI-compatible`), HuggingFace Inference API, and OpenAI Whisper STT API.

### 2.5 Design and Implementation Constraints
1. **Single-Project Modular Monolith Structure:** All backend code must reside inside `LedgerAI.Api/src/` partitioned into `Core/`, `Data/`, `Modules/`, `AI/`, `Communication/`, and `Api/`.
2. **Strict Entity-to-DTO Separation:** EF Core database entities (`Modules/*/Entities`) shall never be serialized directly in HTTP responses; all API endpoints must accept and return dedicated DTOs (`Data/Dtos/`).
3. **Database Trigger & Immutability Compliance:** Application code must never execute direct `INSERT`, `UPDATE`, or `DELETE` against `stock_items` (maintained exclusively by `trg_sync_stock_items_from_batches`) or `UPDATE`/`DELETE` against `audit_logs` (protected by `trg_audit_logs_immutable`).
4. **Supabase Connection Pool Compatibility:** Every database operation requiring tenant isolation must execute inside an explicit transaction block so `SET LOCAL app.current_tenant` remains valid across pooled connections.

---

## 3. External Interface Requirements

### 3.1 User Interfaces (`EIR-UI`)
* **EIR-UI-001 (Responsive PWA Shell):** The React frontend shall be installable as a Progressive Web App supporting desktop (`1920x1080` to `1280x720`) and mobile (`360x800`) viewports.
* **EIR-UI-002 (Real-Time AI Telemetry Console):** The UI shall render a live decision timeline subscribed to SignalR (`LedgerHub`) displaying step-by-step AI pipeline execution (`Sanitized` $\rightarrow$ `Transcribed` $\rightarrow$ `JSON Extracted` $\rightarrow$ `Credit/Confidence Evaluated` $\rightarrow$ `Order Created`).
* **EIR-UI-003 (Human-in-the-Loop Approval Queue):** Orders flagged with `requires_approval = true` shall display confidence score badges, credit utilization bars, and one-click Approve/Reject controls.

### 3.2 Hardware Interfaces (`EIR-HW`)
* **EIR-HW-001 (Client Microphone):** Browser clients shall interface with device microphones via the HTML5 `MediaRecorder` API to capture `.webm`/`.ogg`/`.wav` voice notes for AI order parsing.
* **EIR-HW-002 (Voucher Printing):** Invoice views shall support standard A4 PDF generation and 80mm thermal receipt browser print layouts.

### 3.3 Software & API Interfaces (`EIR-API`)
* **EIR-API-001 (RESTful JSON API):** All synchronous client-server operations shall use JSON over HTTPS (`application/json`) following REST conventions under `/api/v1/{module}`, documented via OpenAPI 3.x (Swagger/Scalar).
* **EIR-API-002 (SignalR Real-Time WebSocket Hub):** Endpoint `/hubs/ledger` shall authenticate via JWT access token query/header and multiplex tenant-scoped groups (`tenant_{tenantId}`) for live stock updates, order alerts, and AI decision logs.
* **EIR-API-003 (Meta WhatsApp Cloud API):**
  * Inbound Webhook: `GET /api/webhooks/whatsapp` (hub challenge verification) and `POST /api/webhooks/whatsapp` (verified via `X-Hub-Signature-256` HMAC-SHA256 header).
  * Outbound Messaging: HTTPS POST to `https://graph.facebook.com/v20.0/{phone_number_id}/messages` using Bearer token authentication.
* **EIR-API-004 (LLM & STT Inference Interfaces):**
  * Primary LLM: Groq LPU OpenAI-compatible chat completions endpoint with JSON Schema structured output enforcement.
  * Secondary Fallback LLM: HuggingFace Inference API managed via Polly v8 circuit breaker and retry policies.
  * Audio Transcription: Whisper STT endpoint accepting `.ogg`, `.wav`, and `.mp3` payloads up to 16 MB.

### 3.4 Communications Interfaces (`EIR-COM`)
* **EIR-COM-001:** All external HTTP traffic shall enforce TLS 1.2/1.3.
* **EIR-COM-002:** PostgreSQL database connections (including Supabase poolers) shall enforce SSL (`SSL Mode=Require`) and attach `X-Correlation-ID` headers across HTTP logs and audit trails.

---

## 4. System Features & Functional Requirements

### 4.1 Feature 1: Multi-Tenant Identity, Security & Administration (`FR-AUTH`)
* **FR-AUTH-001 [M]:** The system shall authenticate users via email/password (`POST /api/auth/login`) using salted cryptographic password hashes and issue a signed JWT containing `sub` (`user_id`), `tenant_id`, `role`, and `jti`.
* **FR-AUTH-002 [M]:** Upon receiving an authenticated HTTP request, `TenantResolutionMiddleware` shall extract `tenant_id` from the validated JWT claims and populate `ITenantContext`.
* **FR-AUTH-003 [M]:** Before executing any database command, `TenantRlsInterceptor` shall execute `SET LOCAL app.current_tenant = '{tenant_id}';` inside the active PostgreSQL transaction.
* **FR-AUTH-004 [M]:** The system shall enforce Role-Based Access Control (RBAC):
  * `Owner`/`Admin`: Full access including credit limit changes, user management, and invoice voiding.
  * `Manager`: Order approval, purchase posting, stock adjustments, and ledger entries.
  * `Operator`: Order creation, sale invoicing, payment recording, and read access.
  * `Viewer`: Strictly HTTP `GET` read-only endpoints.
* **FR-AUTH-005 [S]:** Administrators shall be able to create, update, deactivate, and assign roles to operators within their own tenant (`GET/POST/PATCH /api/users`).

### 4.2 Feature 2: Product Catalog & Two-Tier Units of Measure (`FR-CAT`)
* **FR-CAT-001 [M]:** Users shall create and manage product categories (`categories`) unique by `(tenant_id, name)`.
* **FR-CAT-002 [M]:** Users shall define Units of Measure (`units_of_measure`) with `unit_code`, `name`, `allow_fractional` boolean flag, and a JSONB `aliases` array (e.g., `["bori", "boriyan", "bag", "sack"]`).
* **FR-CAT-003 [M]:** Users shall create and manage products (`products`) specifying `product_code`, `name`, `category_id`, mandatory `base_unit_id`, optional `secondary_unit_id`, `pack_size > 0`, `default_purchase_price`, `default_sales_price`, `minimum_stock`, and JSONB `attributes.aliases` (e.g., `["chini", "cheeni", "white sugar"]`).
* **FR-CAT-004 [M]:** When `uom.allow_fractional == false`, the system shall reject any order or invoice quantity where `quantity % 1 != 0` with HTTP `400 Bad Request`.
* **FR-CAT-005 [M]:** `CatalogService` shall expose a fuzzy/alias search method resolving Roman Urdu product and unit names against PostgreSQL GIN-indexed JSONB `aliases` for both UI search bars and AI entity resolution.
* **FR-CAT-006 [S]:** Product deletion shall perform a soft delete (`is_deleted = true`, `is_active = false`) to preserve historical invoice and ledger integrity.

### 4.3 Feature 3: Multi-Warehouse Inventory & FEFO Batch Engine (`FR-INV`)
* **FR-INV-001 [M]:** Users shall create and manage multiple physical warehouses/godowns (`warehouses`) per tenant.
* **FR-INV-002 [M]:** Inventory shall be tracked at the batch level (`stock_batches`) per `(tenant_id, warehouse_id, product_id, batch_code)` storing `unit_cost`, `quantity_on_hand`, `quantity_reserved`, `manufactured_at`, and `expires_at`.
* **FR-INV-003 [M]:** Aggregate warehouse stock (`stock_items`) shall be read via EF Core / `v_product_stock_totals` and never mutated directly by C# services, relying on PostgreSQL trigger `trg_sync_stock_items_from_batches`.
* **FR-INV-004 [M]:** During order validation/approval, `FefoBatchPicker` shall select available batches (`quantity_on_hand - quantity_reserved > 0`) ordered by `expires_at ASC NULLS LAST, created_at ASC`, splitting an order line across multiple batches if a single batch lacks sufficient quantity.
* **FR-INV-005 [M]:** Stock reservation shall invoke PostgreSQL atomic function `fn_reserve_batch_stock(tenant_id, order_id, order_item_id, batch_id, base_qty)` to lock the batch row (`FOR UPDATE`), increment `quantity_reserved`, and create an `ACTIVE` record in `stock_reservations`.
* **FR-INV-006 [M]:** Order cancellation or modification shall invoke `fn_release_stock_reservation(tenant_id, reservation_id, release_qty)` to atomically release reserved quantities without underflow.
* **FR-INV-007 [M]:** Users shall record manual stock movements (`TRANSFER_IN`, `TRANSFER_OUT`, `DAMAGE_EXPIRY`, `ADJUSTMENT`) in `stock_movements` with mandatory reason notes and audit logging.
* **FR-INV-008 [S]:** Whenever `total_available_stock <= product.minimum_stock`, the system shall emit a `LOW_STOCK_ALERT` event to `outbox_events` and notify connected dashboards via SignalR.

### 4.4 Feature 4: Party Register & Udhaar Khata Credit Ledger (`FR-ACC`)
* **FR-ACC-001 [M]:** Users shall manage unified party accounts (`accounts`) typed as `CUSTOMER`, `SUPPLIER`, `BANK`, `CASH`, `EXPENSE`, `TRANSPORTER`, or `INVESTOR`, storing contact details, NTN/STRN, IBAN, `opening_balance` (`DR`/`CR`), `credit_limit`, and `risk_tier`.
* **FR-ACC-002 [M]:** Account balances (`current_balance` and `reserved_credit`) shall only be modified via PostgreSQL atomic lock helper `fn_apply_account_balance_delta(...)` inside an ACID transaction.
* **FR-ACC-003 [M]:** Every financial posting shall append an immutable `ledger_entries` record (`DEBIT` or `CREDIT`) capturing `amount`, `running_balance`, `order_id`/`invoice_id` references, and `idempotency_key`.
* **FR-ACC-004 [M]:** Ledger corrections shall never update or delete existing rows; instead, the system shall create a counter-entry referencing `reverses_entry_id` (enforcing single reversal per entry on the same account).
* **FR-ACC-005 [M]:** When recording a customer payment receipt (`POST /api/ledger/payments`), `FifoPaymentAllocator` shall:
  1. Post a `CREDIT` entry to `ledger_entries` and decrement `accounts.current_balance`.
  2. Query unreversed `DEBIT` entries for `(tenant_id, account_id)` ordered by `created_at ASC, id ASC` with open balance `> 0`.
  3. Create `ledger_allocations` records settling the oldest debits first, updating linked `invoices.amount_paid` and transitioning `invoice_status` (`ISSUED` $\rightarrow$ `PARTIALLY_PAID` $\rightarrow$ `PAID`).
  4. Retain any excess payment as unallocated customer advance credit (`current_balance < 0`).
* **FR-ACC-006 [S]:** `CreditRiskService` shall compute invoice aging buckets (`0–30`, `31–60`, `61–90`, `90+` days overdue) and automatically classify each party's `risk_tier` (`LOW`, `MEDIUM`, `HIGH`, `CRITICAL`).

### 4.5 Feature 5: B2B Wholesale Orders & Human-in-the-Loop Routing (`FR-ORD`)
* **FR-ORD-001 [M]:** Users (via PWA) or AI Agents (via `OrderTools`) shall submit order proposals (`POST /api/orders`) containing `account_id`, `payment_terms` (`CASH`, `CREDIT`, `PARTIAL`), `upfront_paid_amount`, `idempotency_key`, optional `ai_confidence_score`, and line items (`product_id`, `warehouse_id`, `ordered_unit_id`, `ordered_quantity`, `ordered_unit_price`).
* **FR-ORD-002 [M]:** `OrderCalculationService` shall convert ordered quantities to `base_quantity`, calculate line totals and `total_amount`, and compute `credit_exposure` based on `payment_terms`.
* **FR-ORD-003 [M]:** The order routing engine shall evaluate approval gates prior to reserving stock:
  * If `ai_confidence_score != null && ai_confidence_score < 0.85`: Set `order_status = PENDING_APPROVAL`, `requires_approval = true`, `approval_reason = "LOW_CONFIDENCE_SCORE"`.
  * Else if `credit_exposure > 0 && (current_balance + reserved_credit + credit_exposure > credit_limit)`: Set `order_status = PENDING_APPROVAL`, `requires_approval = true`, `approval_reason = "CREDIT_LIMIT_EXCEEDED"`.
  * Else: Set `order_status = VALIDATED`, `requires_approval = false`, reserve FEFO batches via `fn_reserve_batch_stock`, and increment `accounts.reserved_credit`.
* **FR-ORD-004 [M]:** Authorized Managers/Owners shall approve (`POST /api/orders/{id}/approve`) or reject (`POST /api/orders/{id}/reject`) pending orders, recording `approved_by` and `approved_at` and executing stock/credit reservations upon approval.
* **FR-ORD-005 [M]:** Cancelling a `VALIDATED` order (`POST /api/orders/{id}/cancel`) shall release all active `stock_reservations` and decrement `accounts.reserved_credit` atomically.

### 4.6 Feature 6: Dual-Series Invoicing (`00` Purchase & `01` Sale) & Charges (`FR-BIL`)
* **FR-BIL-001 [M]:** The system shall support two voucher types in `invoices`:
  * `PURCHASE` (auto-generated `voucher_series = '00'`)
  * `SALE` (auto-generated `voucher_series = '01'`)
* **FR-BIL-002 [M]:** Upon posting a `00` Purchase Invoice (`POST /api/invoices/purchase`):
  1. Prorate all `invoice_charges` marked `CAPITALIZE_LANDED_COST` (`FREIGHT_BILTY`, `LABOR_MAZDOORI`, `WEIGHING_KANTA`) across line items proportionally by net line value, assigning any `0.0001` rounding remainder to the largest line.
  2. Insert new `stock_batches` rows with landed `unit_cost` and insert `PURCHASE` records into `stock_movements`.
  3. Recalculate `products.weighted_avg_cost` (`WAC_new`).
  4. Post a `CREDIT` entry to the supplier's `ledger_entries` (and credit transporter account if `payable_account_id` is specified).
* **FR-BIL-003 [M]:** Upon posting a `01` Sale Invoice (`POST /api/invoices/sale`):
  1. Commit reserved stock via `fn_commit_batch_stock(tenant_id, batch_id, base_qty, reservation_id)` (or direct unreserved deduction for walk-in cash sales where `reservation_id == null`).
  2. Insert `SALE` records into `stock_movements` capturing historical `unit_cost` for accurate COGS tracking.
  3. Apply `ADD_TO_BILL`, `DEDUCT_FROM_BILL`, and `MEMO_ONLY` charges (`DELIVERY_OUTBOUND`, `WHT_236G`, `WHT_236H`, `KASAR_WAIVER`).
  4. Release linked order `reserved_credit`, post a `DEBIT` entry to the customer's `ledger_entries` for `grand_total`, transition the linked order to `COMMITTED`, and enqueue an `INVOICE_ISSUED` event in `outbox_events`.
* **FR-BIL-004 [S]:** Users shall query invoice profit summaries via `v_invoice_profit_summary` showing `subtotal_amount`, `total_cogs`, `fulfillment_and_waiver_costs`, `gross_profit`, and `gross_margin_pct`.

### 4.7 Feature 7: Agentic AI Orchestration, WhatsApp Ingress & Telemetry (`FR-AI`, `FR-COM`)
* **FR-AI-001 [M]:** Inbound Meta WhatsApp Cloud API webhooks (`POST /api/webhooks/whatsapp`) shall verify the `X-Hub-Signature-256` header using the tenant's app secret and check `inbound_messages.wamid` uniqueness before processing, returning HTTP `200 OK` immediately for duplicate `wamid` payloads.
* **FR-AI-002 [M]:** If an inbound message contains an audio attachment (`audio_media_id`), `WhisperSttClient` shall download the media from Meta Graph API and transcribe `.ogg`/`.wav`/`.mp3` audio into normalized Roman Urdu/English text stored in `inbound_messages.transcription_text`.
* **FR-AI-003 [M]:** `TextSanitizerPipeline` shall strip control characters, normalize whitespace/numerals, and reject prompt-injection signatures before invoking any LLM.
* **FR-AI-004 [M]:** `IntentExtractorAgent` (Semantic Kernel + Groq LPU with JSON Schema mode) shall convert sanitized text into a strictly typed `NormalizedIntentDto` containing `intent` (`CREATE_ORDER`, `CHECK_BALANCE`, `CHECK_STOCK`, `UNKNOWN`), `confidence` (`0.0000`–`1.0000`), `partyQuery`, `items[]`, and `paymentTermsHint`.
* **FR-AI-005 [M]:** `IntentValidationPipeline` shall validate `NormalizedIntentDto` using FluentValidation and resolve product aliases (`CatalogService`) and party phone/name (`AccountService`).
* **FR-AI-006 [M]:** `SupervisorAgent` shall delegate validated JSON intents to `OrderAgent` or `LedgerAgent`, which execute strictly via annotated `[KernelFunction]` C# tools (`OrderTools`, `LedgerTools`, `CatalogTools`) without direct database access.
* **FR-AI-007 [M]:** `LlmFailoverRouter` shall wrap Groq API calls in a Polly v8 resilience pipeline that rotates API keys on HTTP `429` rate limits and automatically fails over to HuggingFace Inference endpoints on timeout or `5xx` errors.
* **FR-AI-008 [M]:** `AiDecisionLogger` shall emit structured telemetry events (`AiTelemetryEventDto`) at every pipeline stage (`RECEIVED`, `TRANSCRIBED`, `SANITIZED`, `JSON_EXTRACTED`, `VALIDATED`, `TOOL_EXECUTED`, `FALLBACK_TRIGGERED`, `COMPLETED`) and broadcast them via SignalR `LedgerHub` to the frontend UI.
* **FR-COM-001 [M]:** `OutboxDispatcherWorker` (`BackgroundService`) shall poll `outbox_events` (`WHERE processed_at IS NULL AND available_at <= now()`) using row-level locking, dispatch WhatsApp template/text replies and SignalR notifications, and update `processed_at` or exponential backoff `available_at` on failure.

---

## 5. Domain Mathematical, Accounting & Risk Specifications

### 5.1 Unit Conversion & Quantity Formulas (`BR-MATH-001`)
* **Conversion Factor:**
  $$\text{conversion\_factor} = \begin{cases} 1, & \text{if } \text{ordered\_unit\_id} = \text{base\_unit\_id} \\ \text{pack\_size}, & \text{if } \text{ordered\_unit\_id} = \text{secondary\_unit\_id} \end{cases}$$
* **Canonical Base Quantity:**
  $$\text{base\_quantity} = \text{round}(\text{ordered\_quantity} \times \text{conversion\_factor}, 4)$$
* **Split-Batch Ordered Quantity:**
  $$\text{batch\_ordered\_qty} = \text{round}(\text{batch\_base\_qty} \div \text{conversion\_factor}, 4)$$

### 5.2 Order Exposure & Approval Thresholds (`BR-MATH-002`)
* **Line Totals:**
  $$\text{total\_price} = \text{round}(\text{ordered\_quantity} \times \text{ordered\_unit\_price}, 4), \quad \text{total\_cost} = \text{round}(\text{base\_quantity} \times \text{weighted\_avg\_cost}, 4)$$
* **Credit Exposure by Payment Terms:**
  * `CASH`: $\text{upfront\_paid\_amount} = \text{total\_amount}, \quad \text{credit\_exposure} = 0$
  * `PARTIAL`: $0 < \text{upfront\_paid\_amount} < \text{total\_amount}, \quad \text{credit\_exposure} = \text{total\_amount} - \text{upfront\_paid\_amount}$
  * `CREDIT`: $\text{upfront\_paid\_amount} = 0, \quad \text{credit\_exposure} = \text{total\_amount}$

### 5.3 Invoice Totals & Charge Accounting Treatments (`BR-MATH-003`)
* **Line Calculations:**
  $$\text{gross\_line} = \text{round}(\text{quantity} \times \text{unit\_price}, 4), \quad 0 \le \text{discount\_amount} \le \text{gross\_line}$$
  $$\text{tax\_amount} = \text{round}\left((\text{gross\_line} - \text{discount\_amount}) \times \frac{\text{tax\_rate}}{100}, 4\right)$$
  $$\text{line\_total} = \text{round}(\text{gross\_line} - \text{discount\_amount} + \text{tax\_amount}, 4), \quad \text{line\_cogs} = \text{round}(\text{base\_quantity} \times \text{base\_unit\_cost}, 4)$$
* **Header Grand Total:**
  $$\text{grand\_total} = \text{round}\left((\text{subtotal\_amount} - \text{discount\_amount}_{\text{inv}} + \text{tax\_amount}_{\text{inv}}) + C_{\text{ADD\_TO\_BILL}} - C_{\text{DEDUCT\_FROM\_BILL}}, 4\right)$$
* **Charge Categories & Treatments:**
  | Charge Category | Applicable Voucher | Direction | Accounting Treatment | Financial Impact |
  | :--- | :--- | :--- | :--- | :--- |
  | `FREIGHT_BILTY` | Purchase `00` | `ADD_TO_BILL` / `MEMO_ONLY` | `CAPITALIZE_LANDED_COST` | Increases batch `unit_cost` & product `WAC`. |
  | `LABOR_MAZDOORI` | Purchase `00` | `ADD_TO_BILL` / `MEMO_ONLY` | `CAPITALIZE_LANDED_COST` | Capitalized into godown landed unit cost. |
  | `WEIGHING_KANTA` | Purchase `00` | `ADD_TO_BILL` / `MEMO_ONLY` | `CAPITALIZE_LANDED_COST` | Capitalized into bulk commodity landed cost. |
  | `DELIVERY_OUTBOUND` | Sale `01` | `ADD_TO_BILL` / `MEMO_ONLY` | `FULFILLMENT_EXPENSE` | Deducted from Gross Profit in `v_invoice_profit_summary`. |
  | `WHT_236G` / `WHT_236H` | Purchase `00` / Sale `01` | `ADD_TO_BILL` / `DEDUCT_FROM_BILL` | `TAX_PASS_THROUGH` | Adjusts party ledger balance; never distorts gross margin. |
  | `KASAR_WAIVER` | Sale `01` | `DEDUCT_FROM_BILL` | `DISCOUNT_WAIVER` | Reduces `grand_total` and reduces Gross Profit. |

### 5.4 Purchase Landed Cost Proration & Weighted Average Cost (`BR-MATH-004`)
* **Prorated Landed Charge per Line:**
  $$\text{allocated\_charge}_i = \text{round}\left(L_{\text{total}} \times \frac{\text{line\_total}_i - \text{tax\_amount}_i}{V_{\text{total}}}, 4\right)$$
  *(Any `0.0001` rounding residual is added to the line item with the highest net value.)*
* **Batch Landed Unit Cost:**
  $$\text{batch\_unit\_cost}_i = \text{round}\left(\frac{(\text{line\_total}_i - \text{tax\_amount}_i) + \text{allocated\_charge}_i}{\text{base\_quantity}_i}, 4\right)$$
* **New Weighted Average Cost (`WAC_new`):**
  $$\text{WAC}_{\text{new}} = \text{round}\left(\frac{(Q_{\text{old}} \times C_{\text{old}}) + \sum (\text{base\_quantity}_{\text{in}} \times \text{batch\_unit\_cost}_i)}{\max(Q_{\text{old}} + \sum \text{base\_quantity}_{\text{in}}, 1)}, 4\right)$$

### 5.5 Udhaar Khata Sign Conventions & Credit Risk Rules (`BR-MATH-005`)
* **Balance Sign Convention (`accounts.current_balance`):**
  * `> 0 (DR)`: Party owes the business (Customer receivable or Supplier advance).
  * `< 0 (CR)`: Business owes the party (Supplier payable or Customer advance credit).
* **Gross Profit & Margin:**
  $$\text{Gross Profit} = (\text{subtotal\_amount} - \text{discount\_amount}) - \sum \text{line\_cogs} - \sum \text{charge\_amount}(\text{FULFILLMENT\_EXPENSE}, \text{DISCOUNT\_WAIVER})$$
  $$\text{Gross Margin \%} = \text{round}\left(\frac{\text{Gross Profit}}{\text{subtotal\_amount} - \text{discount\_amount}} \times 100, 2\right)$$
* **Credit Utilization & Risk Tiers:**
  $$\text{available\_credit} = \max\left(\text{credit\_limit} - (\max(\text{current\_balance}, 0) + \text{reserved\_credit}), 0\right)$$
  $$\text{utilization} = \frac{\max(\text{current\_balance}, 0) + \text{reserved\_credit}}{\max(\text{credit\_limit}, 1)}$$
  * `CRITICAL`: `90+ days overdue balance > 0` OR `utilization >= 1.00`
  * `HIGH`: `61–90 days overdue balance > 0` OR `utilization >= 0.85`
  * `MEDIUM`: `31–60 days overdue balance > 0` OR `utilization >= 0.60`
  * `LOW`: All active accounts within normal aging and credit thresholds.

---

## 6. Data Requirements & Database Constraints

### 6.1 Relational Schema Inventory (21 Tables + 2 Security-Invoker Views)
1. **Metadata Domain (6 Tables):** `tenants`, `users`, `categories`, `units_of_measure`, `products`, `warehouses`.
2. **Accounting Domain (3 Tables):** `accounts`, `ledger_entries`, `ledger_allocations`.
3. **Inventory Domain (4 Tables + 1 View):** `stock_items`, `stock_batches`, `stock_movements`, `stock_reservations`, `v_product_stock_totals`.
4. **Invoicing & Orders Domain (5 Tables + 1 View):** `orders`, `order_items`, `invoices`, `invoice_items`, `invoice_charges`, `v_invoice_profit_summary`.
5. **AI & Operations Domain (3 Tables):** `inbound_messages`, `outbox_events`, `audit_logs`.

### 6.2 Mandatory Database Integrity Invariants
* **Composite Tenant Foreign Keys:** All foreign keys across tenant-scoped tables must reference `(tenant_id, target_id)` so cross-tenant entity associations are rejected by PostgreSQL.
* **Batch Tuple Integrity:** `stock_movements`, `order_items`, `stock_reservations`, and `invoice_items` must enforce foreign key `(tenant_id, batch_id, warehouse_id, product_id)` against `stock_batches(tenant_id, id, warehouse_id, product_id)`.
* **Supabase Role Hardening:** On Supabase deployments, direct table privileges for `anon` and `authenticated` roles shall be revoked or governed strictly by `FORCE RLS`, and Npgsql connections shall execute inside explicit transactions to preserve `SET LOCAL app.current_tenant`.

---

## 7. Non-Functional Requirements (NFRs)

### 7.1 Performance Requirements (`NFR-PERF`)
* **NFR-PERF-001:** Standard CRUD endpoints (`Catalog`, `Accounts`, `Inventory` reads) shall achieve `< 200 ms` p95 response latency under 50 concurrent operators.
* **NFR-PERF-002:** Transactional voucher postings (`01` Sale Invoice with FEFO batch commit, ledger debit, and outbox insert) shall complete in `< 400 ms` p95.
* **NFR-PERF-003:** End-to-end AI text order parsing (Groq LPU structured JSON extraction + validation + draft creation) shall complete in `< 3.5 seconds` p95; voice note transcription + parsing shall complete in `< 6.0 seconds` p95.

### 7.2 Security & Isolation Requirements (`NFR-SEC`)
* **NFR-SEC-001:** Every table in the public schema (all 21 tables) shall enable and force PostgreSQL Row-Level Security (`ALTER TABLE ... FORCE ROW LEVEL SECURITY`).
* **NFR-SEC-002:** Passwords shall be hashed using `Argon2id` or `BCrypt` (work factor $\ge 12$). Plaintext secrets, API keys, and JWT signing keys shall never be committed to source control.
* **NFR-SEC-003:** All inbound Meta WhatsApp webhooks shall validate HMAC-SHA256 signatures before parsing JSON payloads.
* **NFR-SEC-004:** `audit_logs` shall remain strictly append-only; attempts to `UPDATE` or `DELETE` audit records must fail at the database engine level (`ERRCODE 42501`).

### 7.3 Reliability, Concurrency & Availability (`NFR-REL`)
* **NFR-REL-001:** Concurrent order submissions targeting the same stock batch or customer credit limit shall be serialized via PostgreSQL `FOR UPDATE` row locks (`fn_reserve_batch_stock`, `fn_apply_account_balance_delta`) with zero negative stock or oversold reservations.
* **NFR-REL-002:** Retried HTTP requests or duplicate WhatsApp webhooks carrying an existing `idempotency_key` / `wamid` shall return the previously committed result without duplicating financial or inventory mutations.
* **NFR-REL-003:** Outbound notification failures (WhatsApp API or SignalR disconnects) shall be retried automatically by `OutboxDispatcherWorker` up to 5 times with exponential backoff without rolling back core database transactions.

### 7.4 Maintainability, Modularity & Observability (`NFR-MAINT`, `NFR-OBS`)
* **NFR-MAINT-001:** All business logic shall be unit-testable via `xUnit` without requiring live LLM endpoints or WhatsApp network access.
* **NFR-OBS-001:** Every HTTP request and background worker job shall emit structured Serilog JSON logs enriched with `CorrelationId`, `TenantId`, and `UserId`.
* **NFR-OBS-002:** All AI agent decisions, confidence scores, fallback events, and tool invocations shall be observable in real time on the React PWA telemetry panel via SignalR.

---

## 8. Assumptions, Constraints, Dependencies & Exclusions

### 8.1 Assumptions
* Retail buyers have access to WhatsApp or a modern mobile/desktop browser capable of HTML5 audio recording.
* Third-party inference APIs (Groq, HuggingFace, Whisper) maintain standard cloud availability; temporary outages are gracefully handled by fallback routing or manual ERP operation.

### 8.2 Exclusions (Out of Scope for Current Release)
* Direct integration with commercial banking switches (Raast / IBFT automated bank-to-bank settlement).
* Native iOS (Swift) or Android (Kotlin) mobile apps (delivered exclusively as a cross-platform React PWA).
* Automated FBR POS real-time fiscalization hardware dongle integration (WHT `236G`/`236H` tax pass-through lines are supported in invoicing, while tax strategy plugins are deferred to post-MVP).

---

## 9. Requirements Traceability Matrix (RTM)

| Requirement ID | Domain Module | Backend Implementation Path (`LedgerAI.Api/src/`) | Database Objects (`LedgerAI_Schema_v2.sql`) | Owner |
| :--- | :--- | :--- | :--- | :--- |
| `FR-AUTH-001..005` | Security & Tenancy | `Core/Security/`, `Data/Interceptors/TenantRlsInterceptor.cs`, `Api/Controllers/AuthController.cs` | `tenants`, `users`, `ledgerai_current_tenant_id()`, `FORCE RLS` | Haider Ali |
| `FR-CAT-001..006` | Catalog & UOM | `Modules/Catalog/`, `Data/Dtos/Catalog/`, `Api/Controllers/CatalogController.cs` | `categories`, `units_of_measure`, `products`, `idx_products_attributes_gin` | Haider Ali |
| `FR-INV-001..008` | Multi-Warehouse IMS | `Modules/Inventory/`, `Modules/Inventory/Services/FefoBatchPicker.cs`, `Api/Controllers/InventoryController.cs` | `warehouses`, `stock_batches`, `stock_items`, `stock_movements`, `stock_reservations`, `fn_reserve_batch_stock` | Haider Ali |
| `FR-ACC-001..006` | Party & Udhaar Khata | `Modules/Accounts/`, `Modules/Accounts/Services/FifoPaymentAllocator.cs`, `Api/Controllers/AccountsController.cs`, `LedgerController.cs` | `accounts`, `ledger_entries`, `ledger_allocations`, `fn_apply_account_balance_delta`, `trg_validate_ledger_allocation` | Haider Ali |
| `FR-ORD-001..005` | B2B Orders & Approvals | `Modules/Orders/`, `Modules/Orders/Services/OrderCalculationService.cs`, `Api/Controllers/OrdersController.cs` | `orders`, `order_items`, `stock_reservations` | Haider Ali |
| `FR-BIL-001..004` | `00`/`01` Invoicing & WAC | `Modules/Invoicing/`, `Modules/Invoicing/Services/WacCalculator.cs`, `Api/Controllers/InvoicesController.cs` | `invoices`, `invoice_items`, `invoice_charges`, `v_invoice_profit_summary`, `fn_commit_batch_stock` | Haider Ali |
| `FR-AI-001..008` | Multi-Agent AI & Telemetry | `AI/Agents/`, `AI/Pipelines/`, `AI/Tools/`, `AI/Routers/`, `AI/Monitoring/`, `Api/Controllers/AiChatController.cs` | `inbound_messages`, `orders.execution_metadata`, `audit_logs` | Ibtisam Kashif |
| `FR-COM-001` | WhatsApp & Outbox | `Communication/WhatsApp/`, `Communication/Workers/OutboxDispatcherWorker.cs`, `Api/Webhooks/`, `Api/Hubs/LedgerHub.cs` | `inbound_messages`, `outbox_events`, `idx_outbox_ready` | Haider + Ibtisam |
| `EIR-UI-001..003` | Frontend React PWA | External React TypeScript PWA (`src/features/{dashboard,khata,inventory,ai-chat}`) | Consumes REST DTOs & SignalR `LedgerHub` | Fazina Mukhtar |
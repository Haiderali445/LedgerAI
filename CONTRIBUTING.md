# Contributing to LedgerAI

Thank you for your interest in **LedgerAI** — Next-Gen B2B Wholesale ERP, Multi-Warehouse IMS, Udhaar Khata Ledger, and WhatsApp-Native AI Copilot.

> **Notice:** LedgerAI is a **proprietary and confidential** Final Year Project developed at the Department of Software Engineering, University of Gujrat, Pakistan. All rights are reserved. External contributions, fork distributions, or public mirroring require explicit written consent from the project owners.

---

## 1. Project Team & Core Authors

* **Haider Ali** — Lead Architect & Backend / AI Engineering
* **Ibtisam Kashif** — Full-Stack & Inventory Systems
* **Fazina Mukhtar** — Frontend Engineering & Quality Assurance

**Academic Supervisor:** Department of Software Engineering, Faculty of Computing & Information Technology, University of Gujrat.

---

## 2. Development Workflow & Git Standards

### Branching Strategy
* `main`: Protected production-ready branch. All merges must pass automated builds with 0 errors.
* `feature/<domain>-<description>`: Feature development branches (e.g., `feature/ims-fefo-allocation`, `feature/billing-00-01`).
* `fix/<issue-description>`: Bug fixes and security patches.

### Commit Conventions
Follow the Conventional Commits specification:
```
<type>(<scope>): <short imperative description>

[optional body]
```
Common types:
* `feat`: A new feature or domain capability.
* `fix`: A bug fix or correction.
* `docs`: Documentation updates.
* `refactor`: Code changes that neither fix a bug nor add a feature.
* `test`: Adding or updating unit/integration tests.
* `chore`: Build tooling, dependency, or configuration updates.

---

## 3. Engineering Guidelines

### Backend (.NET 9 / C# 13)
* Target framework is `net9.0`.
* Maintain clean architectural boundaries between Domain, Application, and Persistence layers.
* Never bypass Row-Level Security (`RLS`) or multi-tenancy filters (`tenant_id`).
* Critical inventory mutations must occur inside serializable/atomic stored procedures (`fn_reserve_batch_stock`, `fn_commit_batch_stock`, `fn_apply_balance_delta`).
* Run all unit and integration tests before submitting PRs:
  ```bash
  dotnet test
  ```

### Frontend (`LedgerAI.Web` — React 18+ / TypeScript / Vite)
* Keep zero TypeScript errors: `npm run build` (`tsc -b && vite build`) must pass with exit code `0`.
* Adhere to the Obsidian/Navy design tokens (`#070B14`, `#0B1120`, emerald/mint accents, smooth `rounded-2xl` / `rounded-3xl` cards).
* Financial and stock numbers must use `tabular-nums` for alignment.
* Gate all telemetry and diagnostic logs behind `if (import.meta.env.DEV)`.

---

## 4. Submitting Pull Requests

1. Ensure your local branch is rebased on top of `origin/main`.
2. Confirm both backend and frontend build with 0 errors:
   ```bash
   # Backend
   dotnet build
   
   # Frontend
   cd LedgerAI.Web && npm run build
   ```
3. Open a Pull Request detailing:
   * Summary of changes.
   * Associated SRS or architecture requirement.
   * Testing evidence (screenshots, unit test output, or endpoint traces).

---

## 5. Security & Responsible Disclosure

If you discover a security vulnerability or sensitive data leak, do **not** open a public issue. Please email:
`rajahaider7896@gmail.com`

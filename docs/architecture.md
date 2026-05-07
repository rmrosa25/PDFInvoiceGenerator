# Architecture

## Overview

The service is a single Node.js process built on Fastify. A request arrives with invoice data and a layout name, the data is validated and enriched with computed totals, a Handlebars template is rendered to HTML, and Puppeteer converts that HTML to a PDF which is streamed back to the caller.

```
Client
  │
  │  POST /invoice/generate  (JSON)
  ▼
Fastify (JSON Schema validation)
  │
  ├─ 400 if schema invalid
  ├─ 400 if layout unknown
  │
  ▼
invoice.service  ──  computes lineTotal, vatAmount, grandTotal
  │
  ▼
template.service  ──  renders Handlebars template → HTML string
  │
  ▼
pdf.service  ──  Puppeteer page renders HTML → PDF buffer
  │
  ▼
Response: application/pdf
```

---

## Project structure

```
src/
  index.ts                    Entry point. Starts Fastify, discovers layouts,
                              registers routes, handles graceful shutdown.

  routes/
    invoice.ts                Route handlers for POST /invoice/generate
                              and GET /invoice/layouts.

  schemas/
    invoice.schema.ts         JSON Schema for the request body. Used by
                              Fastify for validation before any handler runs.

  types/
    invoice.types.ts          TypeScript interfaces for all domain objects:
                              InvoiceRequest, InvoiceRenderData, InvoiceItem,
                              InvoiceParty, InvoiceTotals.

  services/
    invoice.service.ts        Calculates per-item and invoice-level totals
                              from raw inputs. Never reads from the request
                              body after this point — only InvoiceRenderData
                              is passed downstream.

    template.service.ts       Discovers layouts at startup, compiles and
                              caches Handlebars templates, registers shared
                              helpers (formatMoney, formatDate).

    pdf.service.ts            Manages a single Puppeteer Browser instance
                              shared across requests. Opens a new Page per
                              request, renders HTML, returns a PDF buffer,
                              then closes the page.

  templates/
    <layout-name>/
      template.hbs            Handlebars HTML template for this layout.
```

---

## Components

### Fastify + JSON Schema validation

All input validation happens at the framework level before any handler code runs. The schema (`src/schemas/invoice.schema.ts`) enforces required fields, types, and constraints (e.g. `vatRate` must be 0–100, `items` must have at least one entry). Invalid requests receive a `400` response with Fastify's standard error format — no custom error handling needed for schema violations.

Layout validation is a separate check in the route handler, after schema validation passes, because valid layouts are only known at runtime (they depend on what folders exist in `src/templates/`).

### Invoice service

`buildRenderData` takes the raw `InvoiceRequest` and produces `InvoiceRenderData`, which adds:

- `lineTotal` — `quantity × unitPrice`, rounded to 2 decimal places
- `vatAmount` — `lineTotal × vatRate / 100`, rounded to 2 decimal places
- `lineTotalWithVat` — `lineTotal + vatAmount`
- `totals.subtotal`, `totals.totalVat`, `totals.grandTotal` — summed across all items
- `currencySymbol` — mapped from the ISO currency code (e.g. `EUR` → `€`)

Rounding uses `Math.round(value * 100) / 100` on each intermediate value to avoid floating-point accumulation errors.

### Template service

At startup, `discoverLayouts()` scans `src/templates/` for subdirectories that contain a `template.hbs` file. The result is stored in a `Set<string>` used for layout validation on every request.

Templates are compiled by Handlebars on first use and stored in a `Map` cache. Subsequent requests for the same layout use the cached compiled function — no disk reads after the first call.

Two helpers are registered globally and available in all templates:

| Helper | Signature | Output |
|---|---|---|
| `formatMoney` | `(value, symbol)` | `€150.00` |
| `formatDate` | `(isoDate)` | `07 May 2026` |

### PDF service

A single Chromium instance is launched on the first PDF request and reused for the lifetime of the process. Each request opens a new `Page`, sets the rendered HTML as content, waits for `networkidle0` (ensures fonts and any inline resources are settled), generates an A4 PDF with `printBackground: true`, then closes the page.

The browser is closed gracefully on `SIGINT`/`SIGTERM` via `closeBrowser()` called from the shutdown handler in `index.ts`.

**Why `networkidle0`?** Templates use inline CSS only, so there are no external requests. The wait condition is conservative but ensures consistent rendering if a template is ever updated to reference an external font.

---

## Data flow in detail

```
InvoiceRequest (from HTTP body)
  │
  │  buildRenderData()
  ▼
InvoiceRenderData
  ├── layout: string
  ├── invoice: { number, date, dueDate }
  ├── seller: InvoiceParty
  ├── buyer: InvoiceParty
  ├── currency: string
  ├── currencySymbol: string          ← added
  ├── notes?: string
  ├── items: InvoiceItemComputed[]    ← extended with lineTotal, vatAmount, lineTotalWithVat
  └── totals: InvoiceTotals           ← added
        ├── subtotal
        ├── totalVat
        └── grandTotal
  │
  │  renderTemplate(layout, data)
  ▼
HTML string
  │
  │  htmlToPdf(html)
  ▼
Buffer (PDF binary)
```

---

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `PORT` | `3000` | Port the server listens on |
| `HOST` | `0.0.0.0` | Host the server binds to |

---

## Deployment

The `Dockerfile` at the project root uses a two-stage build:

1. **builder** — installs all dependencies, compiles TypeScript, copies templates to `dist/`
2. **runtime** — `node:20-slim` with only production dependencies, compiled output, and the Puppeteer Chrome cache copied from the builder stage

The runtime image does not contain TypeScript, ts-node, or any dev tooling.

```bash
docker build -t invoice-generator .
docker run -p 3000:3000 invoice-generator
```

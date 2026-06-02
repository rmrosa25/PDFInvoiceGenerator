# PDF Invoice Generator

REST API that generates PDF invoices from JSON input. Layouts are HTML/CSS templates — adding a new one requires no code changes.

## Requirements

- Node.js 20+
- For `--docker`: Docker (on macOS, [Colima](https://github.com/abiosoft/colima) is supported)

## Quick start

```bash
npm install
npm run dev        # starts on http://localhost:3000
```

## API

### `POST /invoice/generate`

Accepts invoice data, returns a PDF binary (`application/pdf`).

**Request body:**

```json
{
  "layout": "minimal-2",
  "templateVersion": "v2.3",
  "invoice": {
    "number": "INV-2026-001",
    "date": "2026-05-07",
    "dueDate": "2026-06-07"
  },
  "seller": {
    "name": "Acme Corp",
    "address": "123 Main St",
    "city": "Lisbon",
    "country": "Portugal",
    "taxId": "PT123456789",
    "email": "billing@acme.com"
  },
  "buyer": {
    "name": "Client Ltd",
    "address": "456 Oak Ave",
    "city": "Porto",
    "country": "Portugal",
    "taxId": "PT987654321"
  },
  "items": [
    {
      "description": "Web Development",
      "quantity": 10,
      "unitPrice": 150.00,
      "vatRate": 23
    }
  ],
  "currency": "EUR",
  "notes": "Payment due within 30 days."
}
```

**Required fields:** `layout`, `invoice` (number, date, dueDate), `seller` (name, address, city, country), `buyer` (name, address, city, country), `items` (min 1), `currency` (3-letter ISO code).

**Optional fields:** `templateVersion`, `seller.taxId`, `seller.email`, `buyer.taxId`, `buyer.email`, `notes`.

**Response:** `application/pdf` binary with `Content-Disposition: attachment; filename="invoice-<number>.pdf"`.

Subtotals, VAT amounts, and grand total are always computed server-side from the raw item inputs.

---

### `GET /invoice/layouts`

Returns the list of available layout names discovered from `src/templates/*/template.hbs`.

```json
{ "layouts": ["minimal", "minimal-2", "standard"] }
```

---

## test.sh

The test script builds the project, starts the server, runs all test cases, and shuts everything down on exit.

```bash
./test.sh                      # build (tsc) + run tests against a local Node process
./test.sh --local              # same as above
./test.sh --docker             # build Docker image + run tests against a container
./test.sh --preview <layout> [templateVersion]   # generate a sample PDF and open it
./test.sh --help
```

### `--local` (default)

Ensures local dependencies exist (runs `npm ci` when local `tsc` is missing), compiles TypeScript, starts `node dist/index.js`, runs 19 test cases, then stops the server.

```bash
./test.sh
./test.sh --local
```

### `--docker`

Builds the Docker image, starts a container on port 3000, runs the same 19 test cases, then stops and removes the container.

```bash
./test.sh --docker
```

On macOS, if the Docker daemon is not running and [Colima](https://github.com/abiosoft/colima) is installed, the script starts Colima automatically. If Colima is not installed:

```bash
brew install colima docker
colima start
```

### `--preview <layout> [templateVersion]`

Generates a sample invoice PDF for the given layout and opens it with the system viewer. The file is saved to `invoice-preview-<layout>.pdf` in the project root.

`templateVersion` is optional and defaults to `v1.0`. It is passed to the API request body as `templateVersion`, so templates can print a dynamic version label.

```bash
./test.sh --preview standard
./test.sh --preview minimal
./test.sh --preview minimal-2 v2.7
```

If the layout name doesn't exist, the script exits with an error and lists the available options.

---

## npm scripts

| Command | Description |
|---|---|
| `npm run dev` | Start with auto-reload (ts-node + nodemon) |
| `npm run build` | Compile TypeScript to `dist/` |
| `npm start` | Run compiled output from `dist/` |
| `npm test` | Alias for `./test.sh --local` |

---

## Further reading

- [Architecture](docs/architecture.md) — system design, request flow, component responsibilities
- [Templates](docs/templates.md) — how to create and maintain invoice layouts

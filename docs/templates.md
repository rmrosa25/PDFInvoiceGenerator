# Templates

Invoice layouts are Handlebars HTML templates. Each layout lives in its own folder under `src/templates/`. The service discovers them at startup — no code changes are needed to add or remove a layout.

## Structure

```
src/templates/
  standard/
    template.hbs      ← required
  minimal/
    template.hbs      ← required
  your-layout/
    template.hbs      ← add yours here
```

A layout is recognised if and only if its folder contains a file named exactly `template.hbs`. Any other files in the folder (e.g. a `README`, design mockups) are ignored.

---

## Creating a new layout

1. Create a folder under `src/templates/` with the layout name you want callers to use:

   ```bash
   mkdir src/templates/detailed
   ```

2. Create `template.hbs` inside it. Start from the skeleton below or copy an existing layout.

3. Restart the server. The new layout appears in `GET /invoice/layouts` and can be used immediately via `"layout": "detailed"`.

4. Preview it:

   ```bash
   ./test.sh --preview detailed
  ./test.sh --preview detailed v2.0
   ```

  The optional second value is sent as `templateVersion` in the request body.

No other files need to change.

---

## Template skeleton

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>Invoice {{invoice.number}}</title>
  <style>
    /* All CSS must be inline — no external stylesheets */
    body { font-family: Arial, sans-serif; font-size: 13px; padding: 32px; }
  </style>
</head>
<body>

  <h1>{{seller.name}}</h1>
  <p>Invoice {{invoice.number}} · {{formatDate invoice.date}}</p>

  <table>
    <thead>
      <tr>
        <th>Description</th>
        <th>Qty</th>
        <th>Unit Price</th>
        <th>VAT</th>
        <th>Total</th>
      </tr>
    </thead>
    <tbody>
      {{#each items}}
      <tr>
        <td>{{description}}</td>
        <td>{{quantity}}</td>
        <td>{{formatMoney unitPrice ../currencySymbol}}</td>
        <td>{{vatRate}}%</td>
        <td>{{formatMoney lineTotalWithVat ../currencySymbol}}</td>
      </tr>
      {{/each}}
    </tbody>
  </table>

  <p>Subtotal: {{formatMoney totals.subtotal currencySymbol}}</p>
  <p>VAT:      {{formatMoney totals.totalVat currencySymbol}}</p>
  <p>Total:    {{formatMoney totals.grandTotal currencySymbol}}</p>

  {{#if notes}}<p>{{notes}}</p>{{/if}}

</body>
</html>
```

---

## Data reference

The following variables are available in every template. All monetary values are pre-rounded to 2 decimal places.

### Top-level

| Variable | Type | Description |
|---|---|---|
| `layout` | `string` | Name of the current layout |
| `templateVersion` | `string \| undefined` | Optional version label passed by request |
| `currency` | `string` | ISO currency code, e.g. `EUR` |
| `currencySymbol` | `string` | Resolved symbol, e.g. `€` |
| `notes` | `string \| undefined` | Optional free-text notes |

Example for dynamic template labels:

```handlebars
{{layout}}{{#if templateVersion}} {{templateVersion}}{{/if}}
```

### `invoice`

| Variable | Type | Description |
|---|---|---|
| `invoice.number` | `string` | Invoice reference number |
| `invoice.date` | `string` | Issue date (ISO 8601, e.g. `2026-05-07`) |
| `invoice.dueDate` | `string` | Due date (ISO 8601) |

### `seller` and `buyer`

Both have the same shape:

| Variable | Type | Description |
|---|---|---|
| `name` | `string` | Company or person name |
| `address` | `string` | Street address |
| `city` | `string` | City |
| `country` | `string` | Country |
| `taxId` | `string \| undefined` | VAT / tax registration number |
| `email` | `string \| undefined` | Contact email |

Always guard optional fields with `{{#if}}`:

```handlebars
{{#if seller.taxId}}<p>Tax ID: {{seller.taxId}}</p>{{/if}}
```

### `items` (array)

Each item in the `{{#each items}}` loop exposes:

| Variable | Type | Description |
|---|---|---|
| `description` | `string` | Line item description |
| `quantity` | `number` | Quantity |
| `unitPrice` | `number` | Price per unit (excl. VAT) |
| `vatRate` | `number` | VAT percentage, e.g. `23` |
| `lineTotal` | `number` | `quantity × unitPrice` |
| `vatAmount` | `number` | `lineTotal × vatRate / 100` |
| `lineTotalWithVat` | `number` | `lineTotal + vatAmount` |

Inside `{{#each items}}`, access the parent scope with `../`:

```handlebars
{{formatMoney unitPrice ../currencySymbol}}
```

### `totals`

| Variable | Type | Description |
|---|---|---|
| `totals.subtotal` | `number` | Sum of all `lineTotal` values |
| `totals.totalVat` | `number` | Sum of all `vatAmount` values |
| `totals.grandTotal` | `number` | Sum of all `lineTotalWithVat` values |

---

## Built-in helpers

### `formatMoney`

Formats a number with a currency symbol.

```handlebars
{{formatMoney totals.grandTotal currencySymbol}}
{{!-- output: €1,840.00 --}}
```

### `formatDate`

Formats an ISO date string as `DD Mon YYYY`.

```handlebars
{{formatDate invoice.date}}
{{!-- output: 07 May 2026 --}}
```

---

## Adding a custom helper

Register helpers in `src/services/template.service.ts`. They become available in all templates immediately.

```typescript
Handlebars.registerHelper('uppercase', (str: string) => str.toUpperCase());
```

```handlebars
{{uppercase seller.name}}
```

---

## CSS guidelines

Puppeteer renders templates using Chromium. A few constraints apply:

- **All CSS must be inline** (`<style>` in `<head>`). External stylesheets are not loaded.
- **Use `printBackground: true`** is already set — background colours and images render correctly.
- **Avoid `position: fixed`** for headers/footers; Puppeteer's PDF renderer does not support it reliably. Use normal document flow instead.
- **Page size is A4** with 10mm margins on all sides. Design for ~794px × 1123px effective content area.
- **Web fonts** (Google Fonts etc.) will not load because there is no network access during rendering. Use system fonts or embed fonts as base64 `@font-face` declarations.

---

## Modifying an existing layout

Edit `src/templates/<layout>/template.hbs` directly. Changes take effect on the next server restart (the compiled template is cached in memory per process).

During development with `npm run dev`, the server restarts automatically on file changes, including `.hbs` files.

---

## Removing a layout

Delete the layout folder:

```bash
rm -rf src/templates/my-old-layout
```

Restart the server. The layout will no longer appear in `GET /invoice/layouts`, and requests using it will receive a `400` error listing the remaining options.

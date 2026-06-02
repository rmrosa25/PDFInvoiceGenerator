export interface InvoiceParty {
  name: string;
  address: string;
  city: string;
  country: string;
  taxId?: string;
  email?: string;
}

export interface InvoiceItem {
  description: string;
  quantity: number;
  unitPrice: number;
  vatRate: number; // percentage, e.g. 23 for 23%
}

export interface InvoiceMeta {
  number: string;
  date: string;    // ISO date string, e.g. "2026-05-07"
  dueDate: string; // ISO date string
}

export interface InvoiceRequest {
  layout: string;
  templateVersion?: string;
  invoice: InvoiceMeta;
  seller: InvoiceParty;
  buyer: InvoiceParty;
  items: InvoiceItem[];
  currency: string; // e.g. "EUR", "USD"
  notes?: string;
}

// Computed fields added by the invoice service before rendering
export interface InvoiceItemComputed extends InvoiceItem {
  lineTotal: number;    // quantity * unitPrice
  vatAmount: number;    // lineTotal * vatRate / 100
  lineTotalWithVat: number;
}

export interface InvoiceTotals {
  subtotal: number;
  totalVat: number;
  grandTotal: number;
}

export interface InvoiceRenderData extends Omit<InvoiceRequest, 'items'> {
  items: InvoiceItemComputed[];
  totals: InvoiceTotals;
  currencySymbol: string;
}

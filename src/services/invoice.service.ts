import {
  InvoiceRequest,
  InvoiceItemComputed,
  InvoiceRenderData,
  InvoiceTotals,
} from '../types/invoice.types';

const CURRENCY_SYMBOLS: Record<string, string> = {
  EUR: '€',
  USD: '$',
  GBP: '£',
  CHF: 'CHF',
  JPY: '¥',
  BRL: 'R$',
};

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

export function buildRenderData(request: InvoiceRequest): InvoiceRenderData {
  const computedItems: InvoiceItemComputed[] = request.items.map((item) => {
    const lineTotal = round2(item.quantity * item.unitPrice);
    const vatAmount = round2(lineTotal * (item.vatRate / 100));
    const lineTotalWithVat = round2(lineTotal + vatAmount);
    return { ...item, lineTotal, vatAmount, lineTotalWithVat };
  });

  const totals: InvoiceTotals = computedItems.reduce(
    (acc, item) => ({
      subtotal: round2(acc.subtotal + item.lineTotal),
      totalVat: round2(acc.totalVat + item.vatAmount),
      grandTotal: round2(acc.grandTotal + item.lineTotalWithVat),
    }),
    { subtotal: 0, totalVat: 0, grandTotal: 0 }
  );

  const currencySymbol = CURRENCY_SYMBOLS[request.currency] ?? request.currency;

  return {
    ...request,
    items: computedItems,
    totals,
    currencySymbol,
  };
}

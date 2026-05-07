import fs from 'fs';
import path from 'path';
import Handlebars from 'handlebars';
import { InvoiceRenderData } from '../types/invoice.types';

const TEMPLATES_DIR = path.join(__dirname, '..', 'templates');

// Cache compiled templates to avoid re-reading from disk on every request
const templateCache = new Map<string, HandlebarsTemplateDelegate>();

// Discovered layout names, populated at startup
let availableLayouts: Set<string> = new Set();

export function discoverLayouts(): string[] {
  const entries = fs.readdirSync(TEMPLATES_DIR, { withFileTypes: true });
  const layouts = entries
    .filter((e) => e.isDirectory())
    .map((e) => e.name)
    .filter((name) => {
      const tplPath = path.join(TEMPLATES_DIR, name, 'template.hbs');
      return fs.existsSync(tplPath);
    });

  availableLayouts = new Set(layouts);
  return layouts;
}

export function getAvailableLayouts(): string[] {
  return Array.from(availableLayouts);
}

export function isValidLayout(layout: string): boolean {
  return availableLayouts.has(layout);
}

function loadTemplate(layout: string): HandlebarsTemplateDelegate {
  if (templateCache.has(layout)) {
    return templateCache.get(layout)!;
  }

  const tplPath = path.join(TEMPLATES_DIR, layout, 'template.hbs');
  const source = fs.readFileSync(tplPath, 'utf-8');
  const compiled = Handlebars.compile(source);
  templateCache.set(layout, compiled);
  return compiled;
}

export function renderTemplate(layout: string, data: InvoiceRenderData): string {
  const template = loadTemplate(layout);
  return template(data);
}

// Register Handlebars helpers used across templates
Handlebars.registerHelper('formatMoney', (value: number, symbol: string) => {
  return `${symbol}${value.toFixed(2)}`;
});

Handlebars.registerHelper('formatDate', (isoDate: string) => {
  return new Date(isoDate).toLocaleDateString('en-GB', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  });
});

// JSON Schema used by Fastify for request validation and serialization
export const invoiceRequestSchema = {
  type: 'object',
  required: ['layout', 'invoice', 'seller', 'buyer', 'items', 'currency'],
  properties: {
    layout: { type: 'string', minLength: 1 },
    invoice: {
      type: 'object',
      required: ['number', 'date', 'dueDate'],
      properties: {
        number: { type: 'string', minLength: 1 },
        date: { type: 'string', format: 'date' },
        dueDate: { type: 'string', format: 'date' },
      },
      additionalProperties: false,
    },
    seller: { $ref: '#/definitions/party' },
    buyer: { $ref: '#/definitions/party' },
    items: {
      type: 'array',
      minItems: 1,
      items: {
        type: 'object',
        required: ['description', 'quantity', 'unitPrice', 'vatRate'],
        properties: {
          description: { type: 'string', minLength: 1 },
          quantity: { type: 'number', exclusiveMinimum: 0 },
          unitPrice: { type: 'number', minimum: 0 },
          vatRate: { type: 'number', minimum: 0, maximum: 100 },
        },
        additionalProperties: false,
      },
    },
    currency: { type: 'string', minLength: 3, maxLength: 3 },
    notes: { type: 'string' },
  },
  additionalProperties: false,
  definitions: {
    party: {
      type: 'object',
      required: ['name', 'address', 'city', 'country'],
      properties: {
        name: { type: 'string', minLength: 1 },
        address: { type: 'string', minLength: 1 },
        city: { type: 'string', minLength: 1 },
        country: { type: 'string', minLength: 1 },
        taxId: { type: 'string' },
        email: { type: 'string', format: 'email' },
      },
      additionalProperties: false,
    },
  },
} as const;

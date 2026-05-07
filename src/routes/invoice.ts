import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { invoiceRequestSchema } from '../schemas/invoice.schema';
import { buildRenderData } from '../services/invoice.service';
import { renderTemplate, isValidLayout, getAvailableLayouts } from '../services/template.service';
import { htmlToPdf } from '../services/pdf.service';
import { InvoiceRequest } from '../types/invoice.types';

export async function invoiceRoutes(fastify: FastifyInstance): Promise<void> {
  // POST /invoice/generate — accepts invoice data, returns PDF binary
  fastify.post(
    '/invoice/generate',
    {
      schema: {
        body: invoiceRequestSchema,
        response: {
          400: {
            type: 'object',
            properties: {
              error: { type: 'string' },
              availableLayouts: { type: 'array', items: { type: 'string' } },
            },
          },
        },
      },
    },
    async (request: FastifyRequest<{ Body: InvoiceRequest }>, reply: FastifyReply) => {
      const { layout } = request.body;

      if (!isValidLayout(layout)) {
        return reply.status(400).send({
          error: `Unknown layout "${layout}".`,
          availableLayouts: getAvailableLayouts(),
        });
      }

      const renderData = buildRenderData(request.body);
      const html = renderTemplate(layout, renderData);
      const pdf = await htmlToPdf(html);

      const filename = `invoice-${request.body.invoice.number}.pdf`;
      reply
        .header('Content-Type', 'application/pdf')
        .header('Content-Disposition', `attachment; filename="${filename}"`)
        .send(pdf);
    }
  );

  // GET /invoice/layouts — list available layout names
  fastify.get('/invoice/layouts', async (_request, reply) => {
    reply.send({ layouts: getAvailableLayouts() });
  });
}

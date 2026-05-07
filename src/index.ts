import Fastify from 'fastify';
import { invoiceRoutes } from './routes/invoice';
import { discoverLayouts } from './services/template.service';
import { closeBrowser } from './services/pdf.service';

const PORT = parseInt(process.env.PORT ?? '3000', 10);
const HOST = process.env.HOST ?? '0.0.0.0';

async function start(): Promise<void> {
  const fastify = Fastify({ logger: true });

  // Discover available templates before accepting requests
  const layouts = discoverLayouts();
  fastify.log.info({ layouts }, 'Discovered invoice layouts');

  await fastify.register(invoiceRoutes);

  // Graceful shutdown: close the Puppeteer browser
  const shutdown = async (signal: string) => {
    fastify.log.info(`Received ${signal}, shutting down`);
    await fastify.close();
    await closeBrowser();
    process.exit(0);
  };

  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));

  await fastify.listen({ port: PORT, host: HOST });
}

start().catch((err) => {
  console.error(err);
  process.exit(1);
});

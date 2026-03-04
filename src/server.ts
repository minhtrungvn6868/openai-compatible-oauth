import Fastify from 'fastify';
import cors from '@fastify/cors';
import { loadConfig } from './lib/config.js';
import { KeyService } from './services/key.service.js';
import { PiAiService } from './services/pi-ai.service.js';
import { createAuthMiddleware } from './middleware/auth.js';
import { registerChatRoutes } from './routes/chat.js';
import { registerModelRoutes } from './routes/models.js';
import { registerKeyRoutes } from './routes/keys.js';
import { registerCompletionRoutes } from './routes/completions.js';
import { registerEmbeddingRoutes } from './routes/embeddings.js';

async function main() {
  const config = loadConfig();

  const app = Fastify({ logger: true });

  await app.register(cors, { origin: true });

  const keyService = new KeyService(config.secretKey, config.saltKey);
  await keyService.init();

  const piAiService = new PiAiService(config.anthropicApiKey, config.defaultModel);

  const authHook = createAuthMiddleware(keyService);

  registerChatRoutes(app, piAiService, authHook);
  registerCompletionRoutes(app, piAiService, authHook);
  registerModelRoutes(app, piAiService);
  registerEmbeddingRoutes(app, authHook);
  registerKeyRoutes(app, keyService, config.adminKey);

  app.get('/health', async () => ({
    status: 'ok',
    timestamp: new Date().toISOString(),
  }));

  await app.listen({ port: config.port, host: '0.0.0.0' });
}

main().catch((err) => {
  process.stderr.write(`Failed to start server: ${String(err)}\n`);
  process.exit(1);
});

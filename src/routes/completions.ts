import type { FastifyInstance, preHandlerHookHandler } from 'fastify';
import type { PiAiService } from '../services/pi-ai.service.js';
import type { CompletionRequest } from '../types/openai.types.js';

export function registerCompletionRoutes(
  app: FastifyInstance,
  piAiService: PiAiService,
  authHook: preHandlerHookHandler,
) {
  app.post<{ Body: CompletionRequest }>(
    '/v1/completions',
    {
      preHandler: [authHook],
      schema: {
        body: {
          type: 'object',
          required: ['prompt'],
          additionalProperties: true,
          properties: {
            model: { type: 'string' },
            prompt: {},
            stream: { type: 'boolean' },
          },
        },
      },
    },
    async (request, reply) => {
      const body = request.body;

      if (body.stream) {
        reply.raw.writeHead(200, {
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          Connection: 'keep-alive',
          'X-Accel-Buffering': 'no',
        });

        try {
          for await (const chunk of piAiService.legacyStream(body)) {
            reply.raw.write(chunk);
          }
        } catch (error) {
          const errMsg =
            error instanceof Error ? error.message : 'Internal server error';
          reply.raw.write(
            `data: ${JSON.stringify({ error: { message: errMsg } })}\n\n`,
          );
        } finally {
          reply.raw.end();
        }

        return reply;
      }

      const result = await piAiService.legacyComplete(body);
      return reply.send(result);
    },
  );
}

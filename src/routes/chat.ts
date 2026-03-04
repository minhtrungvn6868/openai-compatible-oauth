import type { FastifyInstance, preHandlerHookHandler } from 'fastify';
import type { PiAiService } from '../services/pi-ai.service.js';
import type { ChatCompletionRequest } from '../types/openai.types.js';

export function registerChatRoutes(
  app: FastifyInstance,
  piAiService: PiAiService,
  authHook: preHandlerHookHandler,
) {
  app.post<{ Body: ChatCompletionRequest }>(
    '/v1/chat/completions',
    {
      preHandler: [authHook],
      schema: {
        body: {
          type: 'object',
          required: ['model', 'messages'],
          properties: {
            model: { type: 'string' },
            messages: {
              type: 'array',
              items: {
                type: 'object',
                required: ['role', 'content'],
                properties: {
                  role: { type: 'string' },
                  content: { type: 'string' },
                },
              },
            },
            stream: { type: 'boolean' },
            temperature: { type: 'number' },
            max_tokens: { type: 'integer' },
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
          for await (const chunk of piAiService.chatStream(body)) {
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

      const result = await piAiService.chatComplete(body);
      return reply.send(result);
    },
  );
}

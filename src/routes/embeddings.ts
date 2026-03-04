import type { FastifyInstance, preHandlerHookHandler } from 'fastify';
import type { EmbeddingRequest } from '../types/openai.types.js';

export function registerEmbeddingRoutes(
  app: FastifyInstance,
  authHook: preHandlerHookHandler,
) {
  app.post<{ Body: EmbeddingRequest }>(
    '/v1/embeddings',
    {
      preHandler: [authHook],
      schema: {
        body: {
          type: 'object',
          required: ['input'],
          additionalProperties: true,
          properties: {
            model: { type: 'string' },
            input: {},
          },
        },
      },
    },
    async (_request, reply) => {
      return reply.status(501).send({
        error: {
          message: 'Embeddings are not supported by this proxy. Anthropic Claude models do not provide embeddings.',
          type: 'invalid_request_error',
          code: 'unsupported_endpoint',
        },
      });
    },
  );
}

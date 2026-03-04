import type { FastifyInstance } from 'fastify';
import type { PiAiService } from '../services/pi-ai.service.js';

export function registerModelRoutes(
  app: FastifyInstance,
  piAiService: PiAiService,
) {
  app.get('/v1/models', async (_request, reply) => {
    const models = piAiService.getModels();
    return reply.send({ object: 'list', data: models });
  });

  app.get<{ Params: { id: string } }>(
    '/v1/models/:id',
    async (request, reply) => {
      const model = piAiService.getModelById(request.params.id);

      if (!model) {
        return reply.status(404).send({
          error: {
            message: `Model '${request.params.id}' not found`,
            type: 'invalid_request_error',
          },
        });
      }

      return reply.send(model);
    },
  );
}

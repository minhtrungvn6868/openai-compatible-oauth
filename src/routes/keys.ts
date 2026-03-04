import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import type { KeyService } from '../services/key.service.js';
import type { ApiKeyCreateRequest } from '../types/key.types.js';

function createAdminAuth(adminKey: string) {
  return async (request: FastifyRequest, reply: FastifyReply) => {
    const authHeader = request.headers.authorization;

    if (authHeader !== `Bearer ${adminKey}`) {
      return reply.status(403).send({
        error: { message: 'Forbidden: invalid admin key' },
      });
    }
  };
}

export function registerKeyRoutes(
  app: FastifyInstance,
  keyService: KeyService,
  adminKey: string,
) {
  const adminAuth = createAdminAuth(adminKey);

  app.get('/api/keys', { preHandler: [adminAuth] }, async (_request, reply) => {
    return reply.send(keyService.listKeys());
  });

  app.post<{ Body: ApiKeyCreateRequest }>(
    '/api/keys',
    {
      preHandler: [adminAuth],
      schema: {
        body: {
          type: 'object',
          required: ['name', 'expiresAt'],
          properties: {
            name: { type: 'string' },
            expiresAt: { type: 'string' },
            rateLimit: { type: 'number' },
          },
        },
      },
    },
    async (request, reply) => {
      const result = await keyService.createKey(request.body);
      return reply.status(201).send(result);
    },
  );

  app.delete<{ Params: { id: string } }>(
    '/api/keys/:id',
    { preHandler: [adminAuth] },
    async (request, reply) => {
      const deleted = await keyService.deleteKey(request.params.id);

      if (!deleted) {
        return reply.status(404).send({
          error: { message: 'Key not found' },
        });
      }

      return reply.status(204).send();
    },
  );
}

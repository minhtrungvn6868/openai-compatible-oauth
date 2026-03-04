import type { FastifyRequest, FastifyReply } from 'fastify';
import type { KeyService } from '../services/key.service.js';

declare module 'fastify' {
  interface FastifyRequest {
    keyId?: string;
  }
}

export function createAuthMiddleware(keyService: KeyService) {
  return async (request: FastifyRequest, reply: FastifyReply) => {
    const authHeader = request.headers.authorization;

    if (!authHeader?.startsWith('Bearer ')) {
      return reply.status(401).send({
        error: {
          message: 'Missing or invalid Authorization header. Expected: Bearer <api-key>',
          type: 'authentication_error',
          code: 'invalid_api_key',
        },
      });
    }

    const rawKey = authHeader.slice(7);
    const result = keyService.validateKey(rawKey);

    if (!result.valid) {
      const status = result.error?.includes('Rate limit') ? 429 : 401;
      return reply.status(status).send({
        error: {
          message: result.error,
          type: status === 429 ? 'rate_limit_error' : 'authentication_error',
          code: status === 429 ? 'rate_limit_exceeded' : 'invalid_api_key',
        },
      });
    }

    request.keyId = result.keyId;
  };
}

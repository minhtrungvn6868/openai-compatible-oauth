import 'dotenv/config';

export interface Config {
  port: number;
  anthropicApiKey: string;
  secretKey: string;
  saltKey: string;
  adminKey: string;
  defaultModel: string;
}

function required(key: string): string {
  const value = process.env[key];
  if (!value) {
    throw new Error(`Missing required env var: ${key}`);
  }
  return value;
}

export function loadConfig(): Config {
  const anthropicApiKey =
    process.env['ANTHROPIC_OAUTH_TOKEN'] ??
    process.env['ANTHROPIC_API_KEY'];

  if (!anthropicApiKey) {
    throw new Error('Missing ANTHROPIC_API_KEY or ANTHROPIC_OAUTH_TOKEN');
  }

  return {
    port: parseInt(process.env['PORT'] ?? '3003', 10),
    anthropicApiKey,
    secretKey: required('SECRET_KEY'),
    saltKey: required('SALT_KEY'),
    adminKey: required('ADMIN_KEY'),
    defaultModel: process.env['DEFAULT_MODEL'] ?? 'claude-sonnet-4-20250514',
  };
}

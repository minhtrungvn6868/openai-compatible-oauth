import { randomUUID } from 'node:crypto';
import {
  getModel,
  getModels,
  stream as piStream,
  complete as piComplete,
} from '@mariozechner/pi-ai';
import type {
  Context,
  UserMessage,
  AssistantMessage as PiAssistantMessage,
  Message,
  Model,
  Api,
} from '@mariozechner/pi-ai';
import type {
  ChatCompletionRequest,
  ChatCompletionResponse,
  ChatCompletionChunk,
  ModelInfo,
} from '../types/openai.types.js';

function getAvailableModels(): ModelInfo[] {
  const models = getModels('anthropic');
  return models.map((m) => ({
    id: m.id,
    object: 'model' as const,
    created: Math.floor(Date.now() / 1000),
    owned_by: 'anthropic',
  }));
}

function resolveModel(modelName: string): Model<Api> {
  const anthropicModels = getModels('anthropic');
  const found = anthropicModels.find((m) => m.id === modelName);
  if (found) {
    return found;
  }

  return getModel('anthropic', modelName as 'claude-sonnet-4-20250514');
}

function convertToPiContext(
  messages: ChatCompletionRequest['messages'],
  modelId: string,
): Context {
  const systemMessages = messages.filter((m) => m.role === 'system');
  const systemPrompt =
    systemMessages.map((m) => m.content).join('\n') || undefined;

  const chatMessages = messages.filter((m) => m.role !== 'system');

  const piMessages: Message[] = chatMessages.map((m) => {
    if (m.role === 'user') {
      return {
        role: 'user' as const,
        content: m.content,
        timestamp: Date.now(),
      } satisfies UserMessage;
    }

    return {
      role: 'assistant' as const,
      content: [{ type: 'text' as const, text: m.content }],
      api: 'anthropic-messages' as const,
      provider: 'anthropic',
      model: modelId,
      usage: {
        input: 0,
        output: 0,
        cacheRead: 0,
        cacheWrite: 0,
        totalTokens: 0,
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
      },
      stopReason: 'stop' as const,
      timestamp: Date.now(),
    } satisfies PiAssistantMessage;
  });

  return { systemPrompt, messages: piMessages };
}

function mapStopReason(reason: string): 'stop' | 'length' {
  if (reason === 'length') return 'length';
  return 'stop';
}

function formatSSE(data: ChatCompletionChunk): string {
  return `data: ${JSON.stringify(data)}\n\n`;
}

export class PiAiService {
  constructor(
    private readonly apiKey: string,
    private readonly defaultModel: string,
  ) {}

  getModels(): ModelInfo[] {
    return getAvailableModels();
  }

  getModelById(id: string): ModelInfo | undefined {
    return getAvailableModels().find((m) => m.id === id);
  }

  async chatComplete(
    request: ChatCompletionRequest,
  ): Promise<ChatCompletionResponse> {
    const modelName = request.model || this.defaultModel;
    const model = resolveModel(modelName);
    const context = convertToPiContext(request.messages, model.id);

    const result = await piComplete(model, context, {
      apiKey: this.apiKey,
      temperature: request.temperature,
      maxTokens: request.max_tokens,
    });

    const text = result.content
      .filter((c): c is { type: 'text'; text: string } => c.type === 'text')
      .map((c) => c.text)
      .join('');

    return {
      id: `chatcmpl-${randomUUID()}`,
      object: 'chat.completion',
      created: Math.floor(Date.now() / 1000),
      model: modelName,
      choices: [
        {
          index: 0,
          message: { role: 'assistant', content: text },
          finish_reason: mapStopReason(result.stopReason),
        },
      ],
      usage: {
        prompt_tokens: result.usage.input,
        completion_tokens: result.usage.output,
        total_tokens: result.usage.totalTokens,
      },
    };
  }

  async *chatStream(
    request: ChatCompletionRequest,
  ): AsyncGenerator<string> {
    const modelName = request.model || this.defaultModel;
    const model = resolveModel(modelName);
    const context = convertToPiContext(request.messages, model.id);

    const completionId = `chatcmpl-${randomUUID()}`;
    const created = Math.floor(Date.now() / 1000);

    const eventStream = piStream(model, context, {
      apiKey: this.apiKey,
      temperature: request.temperature,
      maxTokens: request.max_tokens,
    });

    yield formatSSE({
      id: completionId,
      object: 'chat.completion.chunk',
      created,
      model: modelName,
      choices: [
        { index: 0, delta: { role: 'assistant' }, finish_reason: null },
      ],
    });

    for await (const event of eventStream) {
      if (event.type === 'text_delta') {
        yield formatSSE({
          id: completionId,
          object: 'chat.completion.chunk',
          created,
          model: modelName,
          choices: [
            { index: 0, delta: { content: event.delta }, finish_reason: null },
          ],
        });
      } else if (event.type === 'done') {
        yield formatSSE({
          id: completionId,
          object: 'chat.completion.chunk',
          created,
          model: modelName,
          choices: [{ index: 0, delta: {}, finish_reason: 'stop' }],
        });
      } else if (event.type === 'error') {
        yield formatSSE({
          id: completionId,
          object: 'chat.completion.chunk',
          created,
          model: modelName,
          choices: [{ index: 0, delta: {}, finish_reason: 'stop' }],
        });
      }
    }

    yield 'data: [DONE]\n\n';
  }
}

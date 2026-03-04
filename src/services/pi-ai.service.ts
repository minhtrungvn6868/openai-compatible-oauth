import { randomUUID } from 'node:crypto';
import {
  getModel,
  getModels,
  stream as piStream,
  complete as piComplete,
} from '@mariozechner/pi-ai';
import type {
  Context,
  UserMessage as PiUserMessage,
  AssistantMessage as PiAssistantMessage,
  ToolResultMessage as PiToolResultMessage,
  Message,
  Model,
  Api,
  Tool,
} from '@mariozechner/pi-ai';
import type {
  ChatCompletionRequest,
  ChatCompletionResponse,
  ChatCompletionChunk,
  ChatCompletionMessageParam,
  ContentPart,
  ModelInfo,
  CompletionRequest,
  CompletionResponse,
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

function extractTextFromContent(
  content: string | ContentPart[] | null | undefined,
): string {
  if (!content) return '';
  if (typeof content === 'string') return content;

  return content
    .filter((part): part is { type: 'text'; text: string } => part.type === 'text')
    .map((part) => part.text)
    .join('');
}

function convertToPiContext(
  messages: ChatCompletionMessageParam[],
  modelId: string,
  tools?: ChatCompletionRequest['tools'],
): Context {
  const systemMessages = messages.filter((m) => m.role === 'system');
  const systemPrompt =
    systemMessages.map((m) => m.content).join('\n') || undefined;

  const chatMessages = messages.filter((m) => m.role !== 'system');

  const piMessages: Message[] = [];

  for (const m of chatMessages) {
    if (m.role === 'user') {
      piMessages.push({
        role: 'user' as const,
        content: extractTextFromContent(m.content),
        timestamp: Date.now(),
      } satisfies PiUserMessage);
    } else if (m.role === 'assistant') {
      const textContent = extractTextFromContent(m.content);
      const contentParts: PiAssistantMessage['content'] = [];

      if (textContent) {
        contentParts.push({ type: 'text' as const, text: textContent });
      }

      if (m.tool_calls?.length) {
        for (const tc of m.tool_calls) {
          let args: Record<string, unknown> = {};
          try {
            args = JSON.parse(tc.function.arguments) as Record<string, unknown>;
          } catch {
            // keep empty args if parse fails
          }
          contentParts.push({
            type: 'toolCall' as const,
            id: tc.id,
            name: tc.function.name,
            arguments: args,
          });
        }
      }

      if (contentParts.length === 0) {
        contentParts.push({ type: 'text' as const, text: '' });
      }

      piMessages.push({
        role: 'assistant' as const,
        content: contentParts,
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
        stopReason: m.tool_calls?.length ? ('toolUse' as const) : ('stop' as const),
        timestamp: Date.now(),
      } satisfies PiAssistantMessage);
    } else if (m.role === 'tool') {
      let prevAssistant: PiAssistantMessage | undefined;
      for (let idx = piMessages.length - 1; idx >= 0; idx--) {
        const pm = piMessages[idx];
        if (pm && pm.role === 'assistant') {
          prevAssistant = pm;
          break;
        }
      }
      const matchingToolCall = prevAssistant?.content.find(
        (c): c is { type: 'toolCall'; id: string; name: string; arguments: Record<string, unknown> } =>
          c.type === 'toolCall' && c.id === m.tool_call_id,
      );

      piMessages.push({
        role: 'toolResult' as const,
        toolCallId: m.tool_call_id,
        toolName: matchingToolCall?.name ?? 'unknown',
        content: [{ type: 'text' as const, text: m.content }],
        isError: false,
        timestamp: Date.now(),
      } satisfies PiToolResultMessage);
    }
  }

  const piTools: Tool[] | undefined = tools?.map((t) => ({
    name: t.function.name,
    description: t.function.description ?? '',
    parameters: (t.function.parameters ?? { type: 'object', properties: {} }) as Tool['parameters'],
  }));

  return {
    systemPrompt,
    messages: piMessages,
    ...(piTools?.length ? { tools: piTools } : {}),
  };
}

function mapStopReason(reason: string): 'stop' | 'length' | 'tool_calls' {
  if (reason === 'length') return 'length';
  if (reason === 'toolUse') return 'tool_calls';
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
    const context = convertToPiContext(request.messages, model.id, request.tools);

    const result = await piComplete(model, context, {
      apiKey: this.apiKey,
      temperature: request.temperature,
      maxTokens: request.max_tokens,
    });

    const textParts = result.content.filter(
      (c): c is { type: 'text'; text: string } => c.type === 'text',
    );
    const text = textParts.map((c) => c.text).join('');

    const toolCallParts = result.content.filter(
      (c): c is { type: 'toolCall'; id: string; name: string; arguments: Record<string, unknown> } =>
        c.type === 'toolCall',
    );

    const hasToolCalls = toolCallParts.length > 0;

    return {
      id: `chatcmpl-${randomUUID()}`,
      object: 'chat.completion',
      created: Math.floor(Date.now() / 1000),
      model: modelName,
      choices: [
        {
          index: 0,
          message: {
            role: 'assistant',
            content: hasToolCalls ? null : text,
            ...(hasToolCalls
              ? {
                  tool_calls: toolCallParts.map((tc) => ({
                    id: tc.id,
                    type: 'function' as const,
                    function: {
                      name: tc.name,
                      arguments: JSON.stringify(tc.arguments),
                    },
                  })),
                }
              : {}),
          },
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
    const context = convertToPiContext(request.messages, model.id, request.tools);

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

    let hasToolCalls = false;
    let currentToolIndex = -1;

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
      } else if (event.type === 'toolcall_start') {
        hasToolCalls = true;
        currentToolIndex++;
        const toolCallContent = event.partial.content[event.contentIndex];
        const toolId = toolCallContent?.type === 'toolCall' ? toolCallContent.id : `call_${randomUUID()}`;
        const toolName = toolCallContent?.type === 'toolCall' ? toolCallContent.name : '';
        yield formatSSE({
          id: completionId,
          object: 'chat.completion.chunk',
          created,
          model: modelName,
          choices: [
            {
              index: 0,
              delta: {
                tool_calls: [
                  {
                    index: currentToolIndex,
                    id: toolId,
                    type: 'function',
                    function: { name: toolName, arguments: '' },
                  },
                ],
              },
              finish_reason: null,
            },
          ],
        });
      } else if (event.type === 'toolcall_delta') {
        yield formatSSE({
          id: completionId,
          object: 'chat.completion.chunk',
          created,
          model: modelName,
          choices: [
            {
              index: 0,
              delta: {
                tool_calls: [
                  {
                    index: currentToolIndex,
                    function: { arguments: event.delta },
                  },
                ],
              },
              finish_reason: null,
            },
          ],
        });
      } else if (event.type === 'done') {
        const finishReason = hasToolCalls ? 'tool_calls' as const : 'stop' as const;
        yield formatSSE({
          id: completionId,
          object: 'chat.completion.chunk',
          created,
          model: modelName,
          choices: [{ index: 0, delta: {}, finish_reason: finishReason }],
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

  async legacyComplete(
    request: CompletionRequest,
  ): Promise<CompletionResponse> {
    const modelName = request.model || this.defaultModel;
    const model = resolveModel(modelName);

    const prompt = Array.isArray(request.prompt)
      ? request.prompt.join('\n')
      : request.prompt;

    const context: Context = {
      messages: [
        {
          role: 'user' as const,
          content: prompt,
          timestamp: Date.now(),
        } satisfies PiUserMessage,
      ],
    };

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
      id: `cmpl-${randomUUID()}`,
      object: 'text_completion',
      created: Math.floor(Date.now() / 1000),
      model: modelName,
      choices: [
        {
          text,
          index: 0,
          logprobs: null,
          finish_reason: mapStopReason(result.stopReason) === 'tool_calls'
            ? 'stop'
            : mapStopReason(result.stopReason) as 'stop' | 'length',
        },
      ],
      usage: {
        prompt_tokens: result.usage.input,
        completion_tokens: result.usage.output,
        total_tokens: result.usage.totalTokens,
      },
    };
  }

  async *legacyStream(
    request: CompletionRequest,
  ): AsyncGenerator<string> {
    const modelName = request.model || this.defaultModel;
    const model = resolveModel(modelName);

    const prompt = Array.isArray(request.prompt)
      ? request.prompt.join('\n')
      : request.prompt;

    const context: Context = {
      messages: [
        {
          role: 'user' as const,
          content: prompt,
          timestamp: Date.now(),
        } satisfies PiUserMessage,
      ],
    };

    const completionId = `cmpl-${randomUUID()}`;
    const created = Math.floor(Date.now() / 1000);

    const eventStream = piStream(model, context, {
      apiKey: this.apiKey,
      temperature: request.temperature,
      maxTokens: request.max_tokens,
    });

    for await (const event of eventStream) {
      if (event.type === 'text_delta') {
        yield `data: ${JSON.stringify({
          id: completionId,
          object: 'text_completion',
          created,
          model: modelName,
          choices: [{ text: event.delta, index: 0, logprobs: null, finish_reason: null }],
        })}\n\n`;
      } else if (event.type === 'done') {
        yield `data: ${JSON.stringify({
          id: completionId,
          object: 'text_completion',
          created,
          model: modelName,
          choices: [{ text: '', index: 0, logprobs: null, finish_reason: 'stop' }],
        })}\n\n`;
      }
    }

    yield 'data: [DONE]\n\n';
  }
}

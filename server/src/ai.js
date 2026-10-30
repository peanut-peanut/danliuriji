import { HttpError } from './http.js';

const defaultEndpoint = 'https://api.deepseek.com/chat/completions';
const polishSystemPrompt = '请润色以下日常记录的正文，保持原意和语气，不要添加解释。';

export function createDeepSeekClient({ apiKey = process.env.DEEPSEEK_API_KEY, model = process.env.DEEPSEEK_MODEL || 'deepseek-chat', endpoint = process.env.DEEPSEEK_API_BASE_URL || defaultEndpoint, fetchImpl = fetch } = {}) {
  return {
    async polish({ body }) {
      if (!apiKey) throw new HttpError(503, 'AI 润色尚未配置。请在服务端设置 DEEPSEEK_API_KEY。');
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 30_000);
      try {
        const response = await fetchImpl(endpoint, {
          method: 'POST',
          headers: { authorization: `Bearer ${apiKey}`, 'content-type': 'application/json' },
          body: JSON.stringify({
            model,
            temperature: 0.4,
            messages: [
              { role: 'system', content: polishSystemPrompt },
              { role: 'user', content: body }
            ]
          }),
          signal: controller.signal
        });
        const payload = await response.json().catch(() => ({}));
        if (!response.ok) {
          const providerMessage = payload?.error?.message;
          throw new HttpError(502, providerMessage ? `AI 服务请求失败：${providerMessage}` : 'AI 服务暂时不可用，请稍后重试。');
        }
        const content = payload?.choices?.[0]?.message?.content;
        if (typeof content !== 'string') throw new HttpError(502, 'AI 服务返回内容无效，请稍后重试。');
        const result = parsePolishedContent(content, body);
        return result;
      } catch (error) {
        if (error instanceof HttpError) throw error;
        if (error?.name === 'AbortError') throw new HttpError(504, 'AI 润色超时，请稍后重试。');
        throw new HttpError(502, '无法连接 AI 服务，请稍后重试。');
      } finally {
        clearTimeout(timeout);
      }
    }
  };
}

function parsePolishedContent(content, fallback) {
  const body = content.trim();
  if (!body || body.length > 20_000) throw new HttpError(502, 'AI 润色结果无效，请稍后重试。');
  return { body: body || fallback };
}

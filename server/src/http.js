export const MAX_JSON_BYTES = 2 * 1024 * 1024;
export const MAX_MEDIA_BYTES = 200 * 1024 * 1024;

export class HttpError extends Error {
  constructor(status, message, details) {
    super(message);
    this.status = status;
    this.details = details;
  }
}

export function sendJson(response, status, payload) {
  response.writeHead(status, { 'content-type': 'application/json; charset=utf-8' });
  response.end(JSON.stringify(payload));
}

export function sendNoContent(response) { response.writeHead(204); response.end(); }

export function readBody(request, maxBytes) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    request.on('data', (chunk) => {
      size += chunk.length;
      if (size > maxBytes) { reject(new HttpError(413, '请求体过大')); request.destroy(); return; }
      chunks.push(chunk);
    });
    request.on('end', () => resolve(Buffer.concat(chunks)));
    request.on('error', reject);
  });
}

export async function readJson(request) {
  const raw = await readBody(request, MAX_JSON_BYTES);
  if (raw.length === 0) return {};
  try { return JSON.parse(raw.toString('utf8')); }
  catch { throw new HttpError(400, '请求体必须是合法 JSON'); }
}

export function assertObject(value, name = '请求体') {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new HttpError(400, `${name}必须是对象`);
  return value;
}

export function assertString(value, name, { required = true, maxLength = 5_000 } = {}) {
  if ((value === undefined || value === null) && !required) return undefined;
  if (typeof value !== 'string') throw new HttpError(400, `${name}必须是字符串`);
  const trimmed = value.trim();
  if (required && !trimmed) throw new HttpError(400, `${name}不能为空`);
  if (trimmed.length > maxLength) throw new HttpError(400, `${name}长度不能超过${maxLength}`);
  return trimmed;
}

export function assertISODate(value, name = 'date') {
  const date = new Date(value);
  if (typeof value !== 'string' || Number.isNaN(date.valueOf())) throw new HttpError(400, `${name}必须是 ISO 8601 时间`);
  return date.toISOString();
}

export function assertPetIDs(value) {
  const allowed = new Set(['蛋黄', '六六']);
  if (!Array.isArray(value) || value.length === 0 || value.some((pet) => !allowed.has(pet))) throw new HttpError(400, 'petIds必须包含至少一只已知宠物：蛋黄或六六');
  return [...new Set(value)];
}

export function assertMediaIDs(value) {
  if (!Array.isArray(value) || value.length === 0 || value.some((id) => typeof id !== 'string' || !id.trim())) throw new HttpError(400, 'mediaIds必须包含至少一个媒体 ID');
  return [...new Set(value)];
}

export function cors(request, response) {
  const origin = request.headers.origin;
  if (origin) response.setHeader('access-control-allow-origin', origin);
  response.setHeader('vary', 'Origin');
  response.setHeader('access-control-allow-methods', 'GET,POST,PATCH,DELETE,OPTIONS');
  response.setHeader('access-control-allow-headers', 'Content-Type');
  if (request.method === 'OPTIONS') { response.writeHead(204); response.end(); return true; }
  return false;
}

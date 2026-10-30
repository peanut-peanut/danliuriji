import { createServer } from 'node:http';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { JsonStore } from './store.js';
import { HttpError, assertISODate, assertMediaIDs, assertObject, assertPetIDs, assertString, cors, readBody, readJson, sendJson, sendNoContent } from './http.js';
import { createMediaStorageFromEnvironment, withMediaURL } from './media-storage.js';
import { LocalMediaStorage } from './local-media-storage.js';
import { openApi } from './openapi.js';
import { createDeepSeekClient } from './ai.js';
import { loadOptionalEnvFile } from './env.js';

loadOptionalEnvFile();

const moduleDirectory = dirname(fileURLToPath(import.meta.url));
const defaultDataDirectory = join(moduleDirectory, '..', 'data');
const pets = [
  { id: '蛋黄', name: '蛋黄', breed: '短毛金渐层', gender: 'female', birthday: '2023-04-08' },
  { id: '六六', name: '六六', breed: '长毛橘猫', gender: 'male', birthday: '2024-06-06' }
];
const diaryCategories = new Set(['日常', '运动', '阅读', '投资', '饮食']);

export async function createApiServer({ dataDirectory = defaultDataDirectory, mediaStorage, aiClient } = {}) {
  const storage = mediaStorage || configuredMediaStorage(dataDirectory);
  const ai = aiClient || createDeepSeekClient();
  const store = await new JsonStore(join(dataDirectory, 'db.json')).load();
  const present = (record) => presentMedia(record, storage);
  const server = createServer(async (request, response) => {
    try {
      if (cors(request, response)) return;
      const url = new URL(request.url, `http://${request.headers.host || 'localhost'}`);
      const path = url.pathname;
      const method = request.method;
      const base = '/api';

      if (method === 'GET' && path === `${base}/health`) return sendJson(response, 200, { ok: true, service: 'xiaowang-diary-api', mediaStorage: storage.kind || 'oss', timestamp: new Date().toISOString() });
      if (method === 'GET' && path === `${base}/openapi.json`) return sendJson(response, 200, openApi);
      if (method === 'GET' && path === `${base}/pets`) return sendJson(response, 200, { data: pets });
      if (method === 'POST' && path === `${base}/ai/polish`) {
        const body = assertObject(await readJson(request));
        const content = assertString(body.body, 'body', { maxLength: 20_000 });
        return sendJson(response, 200, { data: await ai.polish({ body: content }) });
      }
      if (method === 'GET' && path.startsWith(`${base}/media/`) && storage instanceof LocalMediaStorage) {
        const filePath = decodeURIComponent(path.slice(`${base}/media/`.length));
        const bytes = await storage.read(filePath);
        const extension = filePath.split('.').pop()?.toLowerCase();
        const contentType = extension === 'mp4' ? 'video/mp4' : extension === 'mov' ? 'video/quicktime' : extension === 'png' ? 'image/png' : 'image/jpeg';
        response.writeHead(200, { 'content-type': contentType });
        return response.end(bytes);
      }

      if (method === 'POST' && path === `${base}/media`) {
        const bytes = await readBody(request, 200 * 1024 * 1024);
        const media = await storage.upload({ bytes, contentType: request.headers['content-type'], originalName: request.headers['x-filename'] });
        store.collection('media').push(media);
        await store.persist();
        return sendJson(response, 201, { data: present(media) });
      }

      if (method === 'GET' && path === `${base}/diary-entries`) {
        const category = url.searchParams.get('category');
        if (category && !diaryCategories.has(category)) throw new HttpError(400, 'category无效');
        const data = store.collection('diaryEntries').filter((item) => !category || item.category === category).sort(sortByDate).map(present);
        return sendJson(response, 200, { data });
      }
      if (method === 'POST' && path === `${base}/diary-entries`) {
        const entry = createDiaryEntry(await readJson(request), store.collection('media'));
        store.collection('diaryEntries').push(entry);
        await store.persist();
        return sendJson(response, 201, { data: present(entry) });
      }

      const diaryMatch = path.match(new RegExp(`^${base}/diary-entries/([^/]+)$`));
      if (diaryMatch) {
        const entry = findById(store.collection('diaryEntries'), diaryMatch[1], '日记不存在');
        if (method === 'GET') return sendJson(response, 200, { data: present(entry) });
        if (method === 'PATCH') {
          applyDiaryChanges(entry, assertObject(await readJson(request)), store.collection('media'));
          await store.persist();
          return sendJson(response, 200, { data: present(entry) });
        }
        if (method === 'DELETE') {
          store.database.diaryEntries = store.collection('diaryEntries').filter((item) => item.id !== entry.id);
          await store.persist();
          return sendNoContent(response);
        }
      }

      if (method === 'GET' && path === `${base}/pet-assets`) {
        const petId = url.searchParams.get('petId');
        const kind = url.searchParams.get('kind');
        if (petId && !pets.some((pet) => pet.id === petId)) throw new HttpError(400, 'petId无效');
        if (kind && !['image', 'video'].includes(kind)) throw new HttpError(400, 'kind仅支持image或video');
        const data = store.collection('petAssets').filter((asset) => (!petId || asset.petIds.includes(petId)) && (!kind || asset.media.some((item) => item.kind === kind))).sort(sortByDate).map(present);
        return sendJson(response, 200, { data });
      }
      if (method === 'POST' && path === `${base}/pet-assets`) {
        const body = assertObject(await readJson(request));
        const asset = { id: crypto.randomUUID(), petIds: assertPetIDs(body.petIds), date: body.date ? assertISODate(body.date) : new Date().toISOString(), media: resolveMedia(assertMediaIDs(body.mediaIds), store.collection('media')), createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() };
        store.collection('petAssets').push(asset);
        await store.persist();
        return sendJson(response, 201, { data: present(asset) });
      }

      const assetMatch = path.match(new RegExp(`^${base}/pet-assets/([^/]+)$`));
      if (assetMatch && method === 'DELETE') {
        const asset = findById(store.collection('petAssets'), assetMatch[1], '宠物资源不存在');
        for (const item of asset.media) { await storage.remove(item.filePath); }
        store.database.petAssets = store.collection('petAssets').filter((item) => item.id !== asset.id);
        store.database.media = store.collection('media').filter((item) => !asset.media.some((media) => media.id === item.id));
        await store.persist();
        return sendNoContent(response);
      }
      throw new HttpError(404, '接口不存在');
    } catch (error) {
      const status = error instanceof HttpError ? error.status : 500;
      if (status === 500) console.error(error);
      return sendJson(response, status, { error: { message: error.message || '服务器错误', details: error.details } });
    }
  });
  return server;
}

function configuredMediaStorage(dataDirectory) {
  if (process.env.OSS_ACCESS_KEY_ID && process.env.OSS_ACCESS_KEY_SECRET && process.env.OSS_BUCKET && process.env.OSS_REGION) {
    return createMediaStorageFromEnvironment();
  }
  return new LocalMediaStorage({ directory: join(dataDirectory, 'media'), publicBaseURL: process.env.LOCAL_MEDIA_BASE_URL || `http://127.0.0.1:${process.env.PORT || 3000}/api` });
}

function createDiaryEntry(raw, media) {
  const body = assertObject(raw);
  const title = assertString(body.title, 'title', { required: false, maxLength: 120 }) ?? '';
  const content = assertString(body.body, 'body', { required: false, maxLength: 20_000 }) ?? '';
  const mediaItems = Array.isArray(body.mediaIds) && body.mediaIds.length > 0 ? resolveMedia(assertMediaIDs(body.mediaIds), media) : [];
  if (!title && !content && mediaItems.length === 0) throw new HttpError(400, '日记至少需要标题、正文或一个媒体');
  if (!diaryCategories.has(body.category)) throw new HttpError(400, 'category无效');
  const now = new Date().toISOString();
  return { id: crypto.randomUUID(), title, body: content, category: body.category, date: body.date ? assertISODate(body.date) : now, media: mediaItems, isFavorite: Boolean(body.isFavorite), createdAt: now, updatedAt: now };
}

function applyDiaryChanges(entry, changes, media) {
  if ('title' in changes) entry.title = assertString(changes.title, 'title', { required: false, maxLength: 120 }) ?? '';
  if ('body' in changes) entry.body = assertString(changes.body, 'body', { required: false, maxLength: 20_000 }) ?? '';
  if ('category' in changes) { if (!diaryCategories.has(changes.category)) throw new HttpError(400, 'category无效'); entry.category = changes.category; }
  if ('date' in changes) entry.date = assertISODate(changes.date);
  if ('isFavorite' in changes) { if (typeof changes.isFavorite !== 'boolean') throw new HttpError(400, 'isFavorite必须是布尔值'); entry.isFavorite = changes.isFavorite; }
  if ('mediaIds' in changes) entry.media = Array.isArray(changes.mediaIds) && changes.mediaIds.length > 0 ? resolveMedia(assertMediaIDs(changes.mediaIds), media) : [];
  if (!entry.title && !entry.body && entry.media.length === 0) throw new HttpError(400, '日记至少需要标题、正文或一个媒体');
  entry.updatedAt = new Date().toISOString();
}

function presentMedia(record, storage) {
  if (Array.isArray(record)) return record.map((item) => presentMedia(item, storage));
  if (!record || typeof record !== 'object') return record;
  if ('filePath' in record || 'filename' in record) return withMediaURL(normalizeLegacyMedia(record), storage);
  const result = { ...record };
  if (Array.isArray(result.media)) result.media = result.media.map((item) => withMediaURL(normalizeLegacyMedia(item), storage));
  return result;
}

function normalizeLegacyMedia(media) {
  if (media.filePath) return media;
  // Pre-OSS records remain readable through their old API URL but are not used for new uploads.
  return { ...media, filePath: undefined, url: media.url };
}

function resolveMedia(ids, media) { return ids.map((id) => findById(media, id, `媒体不存在：${id}`)); }
function findById(collection, id, message) { const normalizedID = String(id).toLowerCase(); const record = collection.find((item) => String(item.id).toLowerCase() === normalizedID); if (!record) throw new HttpError(404, message); return record; }
function sortByDate(left, right) { return new Date(right.date) - new Date(left.date); }

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const port = Number(process.env.PORT || 3000);
  const server = await createApiServer();
  server.listen(port, '0.0.0.0', () => console.log(`小王日记 API 已启动：http://localhost:${port}/api`));
}

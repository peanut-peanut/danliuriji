import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { createApiServer } from '../src/index.js';

class MemoryMediaStorage {
  constructor() { this.objects = new Map(); this.removed = []; this.sequence = 0; }
  async upload({ bytes, contentType, originalName }) {
    const id = `media-${++this.sequence}`;
    const media = { id, kind: contentType.startsWith('image/') ? 'image' : 'video', filePath: `xiaowang-diary/media/2026/10/${id}.jpg`, originalName, contentType, byteSize: bytes.length, createdAt: '2026-10-13T00:00:00.000Z' };
    this.objects.set(media.filePath, bytes);
    return media;
  }
  async remove(filePath) { this.removed.push(filePath); this.objects.delete(filePath); }
  urlFor(filePath) { return filePath ? `https://oss.example.test/${filePath}` : undefined; }
}

async function withApi(run) {
  const dataDirectory = await mkdtemp(join(tmpdir(), 'xiaowang-diary-api-'));
  const storage = new MemoryMediaStorage();
  const server = await createApiServer({ dataDirectory, mediaStorage: storage });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const api = `http://127.0.0.1:${server.address().port}/api`;
  try { await run(api, storage); }
  finally { await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve())); await rm(dataDirectory, { recursive: true, force: true }); }
}

test('媒体上传 OSS 路径并保存 filePath，资源删除同步清理对象', async () => {
  await withApi(async (api, storage) => {
    let response = await fetch(`${api}/media`, { method: 'POST', headers: { 'content-type': 'image/jpeg', 'x-filename': 'cat.jpg' }, body: new Uint8Array([0xff, 0xd8, 0xff, 0xd9]) });
    assert.equal(response.status, 201);
    const media = (await response.json()).data;
    assert.match(media.filePath, /^xiaowang-diary\/media\/\d{4}\/\d{2}\//);
    assert.match(media.url, /^https:\/\/oss\.example\.test\//);
    assert.equal('filename' in media, false);

    response = await fetch(`${api}/pet-assets`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ petIds: ['蛋黄', '六六'], mediaIds: [media.id.toUpperCase()] }) });
    assert.equal(response.status, 201);
    const asset = (await response.json()).data;
    assert.equal(asset.media[0].filePath, media.filePath);

    response = await fetch(`${api}/pet-assets/${asset.id}`, { method: 'DELETE' });
    assert.equal(response.status, 204);
    assert.deepEqual(storage.removed, [media.filePath]);
  });
});

test('纯文字日记可发布且不需要媒体', async () => {
  await withApi(async (api) => {
    const response = await fetch(`${api}/diary-entries`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ title: '测试日记', body: '纯文字记录', category: '日常', mediaIds: [] }) });
    assert.equal(response.status, 201);
    assert.deepEqual((await response.json()).data.media, []);
  });
});

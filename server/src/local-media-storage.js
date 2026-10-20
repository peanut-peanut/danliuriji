import { mkdir, readFile, unlink, writeFile } from 'node:fs/promises';
import { dirname, join, normalize, sep } from 'node:path';
import { randomUUID } from 'node:crypto';
import { HttpError } from './http.js';

const extensions = {
  'image/jpeg': '.jpg', 'image/png': '.png', 'image/heic': '.heic', 'image/webp': '.webp',
  'video/mp4': '.mp4', 'video/quicktime': '.mov'
};

/** Development-only OSS-compatible storage. Production always uses OSSMediaStorage. */
export class LocalMediaStorage {
  constructor({ directory, publicBaseURL = 'http://127.0.0.1:3000/api' }) {
    this.directory = directory;
    this.publicBaseURL = publicBaseURL.replace(/\/$/, '');
    this.kind = 'local-development';
  }

  async upload({ bytes, contentType, originalName: _originalName, now = new Date() }) {
    const extension = extensions[contentType];
    if (!extension) throw new HttpError(415, '仅支持 JPEG、PNG、HEIC、WebP、MP4 或 MOV 文件');
    const id = randomUUID();
    const date = now.toISOString().slice(0, 10).replaceAll('-', '/');
    const filePath = `xiaowang-diary/media/${date}/${id}${extension}`;
    const destination = this.absolutePath(filePath);
    await mkdir(dirname(destination), { recursive: true });
    await writeFile(destination, bytes);
    return { id, kind: contentType.startsWith('image/') ? 'image' : 'video', filePath, originalName: `media${extension}`, contentType, byteSize: bytes.length, createdAt: now.toISOString() };
  }

  urlFor(filePath) { return filePath ? `${this.publicBaseURL}/media/${encodeURIComponent(filePath)}` : undefined; }
  async remove(filePath) { if (!filePath) return; try { await unlink(this.absolutePath(filePath)); } catch (error) { if (error.code !== 'ENOENT') throw error; } }
  async read(filePath) { return readFile(this.absolutePath(filePath)); }
  absolutePath(filePath) {
    const resolved = normalize(join(this.directory, filePath));
    const root = normalize(this.directory) + sep;
    if (!resolved.startsWith(root)) throw new HttpError(404, '媒体不存在');
    return resolved;
  }
}

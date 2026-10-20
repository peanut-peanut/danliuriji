import OSS from 'ali-oss';
import { randomUUID } from 'node:crypto';
import { basename, extname } from 'node:path';
import { HttpError } from './http.js';

const allowedImageTypes = new Set(['image/jpeg', 'image/png', 'image/heic', 'image/webp']);
const allowedVideoTypes = new Set(['video/mp4', 'video/quicktime']);

export function createMediaStorageFromEnvironment(environment = process.env) {
  const required = ['OSS_ACCESS_KEY_ID', 'OSS_ACCESS_KEY_SECRET', 'OSS_BUCKET', 'OSS_REGION'];
  const absent = required.filter((name) => !environment[name]);
  if (absent.length > 0) throw new Error(`缺少 OSS 配置：${absent.join(', ')}`);

  const client = new OSS({
    region: environment.OSS_REGION,
    endpoint: environment.OSS_ENDPOINT || undefined,
    accessKeyId: environment.OSS_ACCESS_KEY_ID,
    accessKeySecret: environment.OSS_ACCESS_KEY_SECRET,
    bucket: environment.OSS_BUCKET,
    secure: true,
    timeout: 120_000
  });

  return new OSSMediaStorage({ client, publicBaseURL: environment.OSS_PUBLIC_BASE_URL });
}

export class OSSMediaStorage {
  constructor({ client, publicBaseURL }) {
    this.client = client;
    this.publicBaseURL = publicBaseURL?.replace(/\/$/, '');
    this.kind = 'oss';
  }

  async upload({ bytes, contentType, originalName, now = new Date() }) {
    const kind = mediaKind(contentType);
    const extension = safeExtension(originalName, contentType);
    const id = randomUUID();
    const filePath = objectPath(id, extension, now);

    try {
      await this.client.put(filePath, bytes, {
        headers: {
          'Content-Type': contentType,
          'Cache-Control': 'private, max-age=31536000, immutable'
        }
      });
    } catch (error) {
      throw new HttpError(502, '上传 OSS 失败', error.message);
    }

    return {
      id,
      kind,
      filePath,
      originalName: basename(originalName || `${id}${extension}`),
      contentType,
      byteSize: bytes.length,
      createdAt: now.toISOString()
    };
  }

  async remove(filePath) {
    if (!filePath) return;
    try {
      await this.client.delete(filePath);
    } catch (error) {
      if (![404, 'NoSuchKey'].includes(error.code) && error.status !== 404) throw error;
    }
  }

  urlFor(filePath) {
    if (!filePath) return undefined;
    if (this.publicBaseURL) return `${this.publicBaseURL}/${encodePath(filePath)}`;
    return this.client.signatureUrl(filePath, { expires: 60 * 60, method: 'GET' });
  }
}

export function withMediaURL(media, storage) {
  const { filename: _legacyFilename, ...value } = media;
  return { ...value, url: storage.urlFor(value.filePath) };
}

function mediaKind(contentType) {
  if (allowedImageTypes.has(contentType)) return 'image';
  if (allowedVideoTypes.has(contentType)) return 'video';
  throw new HttpError(415, '仅支持 JPEG、PNG、HEIC、WebP、MP4 或 MOV 文件');
}

function objectPath(id, extension, now) {
  const date = now.toISOString().slice(0, 10).replaceAll('-', '/');
  return `xiaowang-diary/media/${date}/${id}${extension}`;
}

function safeExtension(originalName, contentType) {
  const extension = extname(basename(originalName || '')).toLowerCase();
  const permitted = new Set(['.jpg', '.jpeg', '.png', '.heic', '.webp', '.mp4', '.mov']);
  if (permitted.has(extension)) return extension;
  return { 'image/jpeg': '.jpg', 'image/png': '.png', 'image/heic': '.heic', 'image/webp': '.webp', 'video/mp4': '.mp4', 'video/quicktime': '.mov' }[contentType];
}

function encodePath(filePath) { return filePath.split('/').map(encodeURIComponent).join('/'); }

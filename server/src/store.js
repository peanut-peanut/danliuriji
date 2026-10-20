import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';

const emptyDatabase = () => ({ version: 1, diaryEntries: [], petAssets: [], media: [] });

export class JsonStore {
  constructor(filePath) {
    this.filePath = filePath;
    this.database = emptyDatabase();
  }

  async load() {
    try {
      this.database = { ...emptyDatabase(), ...JSON.parse(await readFile(this.filePath, 'utf8')) };
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      await this.persist();
    }
    return this;
  }

  collection(name) {
    return this.database[name];
  }

  async persist() {
    await mkdir(dirname(this.filePath), { recursive: true });
    const temporaryPath = `${this.filePath}.tmp`;
    await writeFile(temporaryPath, `${JSON.stringify(this.database, null, 2)}\n`, 'utf8');
    await rename(temporaryPath, this.filePath);
  }
}

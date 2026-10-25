import fs from 'node:fs';
import path from 'node:path';

/** Small store backed by one JSON file. Writes are atomic: write a temporary file, then rename it. */
export class Store {
  constructor(file) {
    this.file = file;
    this.data = { devices: {}, orders: {}, events: {} };
    if (file && fs.existsSync(file)) this.data = { ...this.data, ...JSON.parse(fs.readFileSync(file, 'utf8')) };
  }

  save() {
    if (!this.file) return;
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    const tmp = `${this.file}.${process.pid}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(this.data));
    fs.renameSync(tmp, this.file);
  }
}

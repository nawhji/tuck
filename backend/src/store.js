import fs from 'node:fs';
import path from 'node:path';

/** JSON 파일 하나에 저장하는 작은 저장소. 쓰기는 임시 파일 → rename으로 원자적으로 한다. */
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

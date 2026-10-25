import fs from 'node:fs';

/** 따옴표·줄바꿈이 들어간 필드를 처리하는 최소 CSV 파서. */
export function parseCSV(text) {
  const records = [];
  let record = [];
  let field = '';
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; } else quoted = false;
      } else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ',') { record.push(field); field = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      record.push(field); field = '';
      records.push(record); record = [];
    } else field += c;
  }
  if (field || record.length) { record.push(field); records.push(record); }
  const [header, ...rows] = records;
  return rows.filter((r) => r.length === header.length).map((r) => Object.fromEntries(header.map((h, i) => [h, r[i]])));
}

const list = (value) => { try { const v = JSON.parse(value); return Array.isArray(v) ? v : []; } catch { return []; } };
const num = (value) => (value && value !== 'null' && Number.isFinite(Number(value)) ? Number(value) : null);

/** 카탈로그 한 행을 서버가 신뢰하는 상품 값으로 바꾼다. */
function toProduct(row) {
  return {
    id: row.id,
    name: row.name,
    brand: row.brand,
    category: row.category,
    priceCents: num(row.price_cents),
    currency: (row.currency || 'USD').toLowerCase(),
    shippingFeeCents: num(row.shipping_fee_cents),
    availability: row.availability,
    widthIn: num(row.width_in),
    depthIn: num(row.depth_in),
    heightIn: num(row.height_in),
    colorFamily: row.color_family,
    styleTags: list(row.style_tags),
    imageUrl: row.image_url || null,
    sourceUrl: row.source_url || null,
  };
}

export class Catalog {
  constructor(products) {
    this.products = products;
    this.byId = new Map(products.map((p) => [p.id, p]));
  }

  static load(file) {
    return new Catalog(parseCSV(fs.readFileSync(file, 'utf8')).map(toProduct));
  }

  get(id) { return this.byId.get(id) ?? null; }
}

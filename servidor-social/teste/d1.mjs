import { DatabaseSync } from 'node:sqlite';
export function criarD1(schema) {
  const db = new DatabaseSync(':memory:');
  db.exec(schema);
  class St {
    constructor(sql) { this.sql = sql; this.args = []; }
    bind(...a) { this.args = a.map(x => x === undefined ? null : typeof x === 'boolean' ? (x ? 1 : 0) : x); return this; }
    first() { return db.prepare(this.sql).get(...this.args) || null; }
    all() { return { results: db.prepare(this.sql).all(...this.args) }; }
    run() { const r = db.prepare(this.sql).run(...this.args); return { meta: { changes: Number(r.changes) } }; }
    exec() { return /^\s*(SELECT|WITH)/i.test(this.sql) ? this.all() : this.run(); }
  }
  return {
    prepare: s => new St(s),
    batch: async l => { db.exec('BEGIN'); try { const r = l.map(s => s.exec()); db.exec('COMMIT'); return r; } catch (e) { db.exec('ROLLBACK'); throw e; } },
    _db: db,
  };
}

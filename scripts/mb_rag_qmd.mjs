// QMD 2.8.3's CLI vsearch expands queries and its SDK opens stores read/write.
// Use its vector primitives directly to keep published generations read-only.
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { json } from "node:stream/consumers";
import { pathToFileURL } from "node:url";

const [pkg, action, dbPath, model] = process.argv.slice(2);
const load = (file) => import(pathToFileURL(join(pkg, "dist", file)).href);
const { LlamaCpp, setDefaultLlamaCpp } = await load("llm.js");
const {
  createStore, generateEmbeddings, searchVec, upsertStoreCollection,
  getHashesForEmbedding, chunkDocumentByTokens,
} = await load("store.js");
const payload = await json(process.stdin.setEncoding("utf8"));
const llm = new LlamaCpp({ embedModel: model, modelCacheDir: dirname(model) });
// QMD uses the singleton for tokenization as well as the store's embedding model.
setDefaultLlamaCpp(llm);

async function build(docs, missing, maxNewChunks) {
  let store;
  try {
    store = createStore(dbPath);
    upsertStoreCollection(store.db, "code", { path: "." });
    const now = new Date().toISOString();
    store.db.transaction(() => {
      const stale = missing === undefined ? new Map() : new Map(
        store.db.prepare("SELECT id, path, hash FROM documents WHERE collection = 'code'")
          .all().map(row => [row.path, row])
      );
      for (const [id, text] of docs) {
        // QMD includes the basename in the embedding. Keep it independent of row order.
        const path = `${id}/chunk`;
        const hash = createHash("sha256").update(text).digest("hex");
        const existing = stale.get(path);
        stale.delete(path);
        if (existing?.hash === hash) continue;
        store.insertContent(hash, text, now);
        if (existing) store.updateDocument(existing.id, path, hash, now);
        else store.insertDocument("code", path, path, hash, now, now);
      }
      if (missing !== undefined) {
        for (const path of stale.keys()) store.deactivateDocument("code", path);
        store.deleteInactiveDocuments();
        store.cleanupOrphanedVectors();
        store.cleanupOrphanedContent();
      }
    })();
    if (missing !== undefined) {
      // The SDK counts metadata, not actual vec0 rows. Never silently re-embed
      // the entire corpus on a missing vector table or fingerprint/schema change.
      if (store.getHashesNeedingEmbedding(model) !== missing) return false;
      if (store.db.prepare("SELECT 1 FROM content_vectors LIMIT 1").get()) {
        const absent = store.db.prepare(`
          SELECT 1 FROM content_vectors
          WHERE hash || '_' || seq NOT IN (SELECT hash_seq FROM vectors_vec) LIMIT 1
        `).get();
        if (absent) return false;
      }
    }
    if (missing !== 0) {
      await llm.getDeviceInfo({ allowBuild: false });
      if (maxNewChunks != null) {
        // Use the same pending hashes, document paths, tokenizer and defaults as
        // generateEmbeddings on this private SQLite copy, before its first embed().
        let chunks = 0;
        for (const { body, path } of getHashesForEmbedding(store.db, model)) {
          if (!body.trim()) continue;
          chunks += (await chunkDocumentByTokens(body, undefined, undefined, undefined, path)).length;
          if (chunks > maxNewChunks) return false;
        }
      }
      const result = await generateEmbeddings(store, { model, maxDurationMs: 0 });
      if (result.errors || store.getHashesNeedingEmbedding(model)) {
        throw new Error("QMD could not embed every document");
      }
    }
    // Read-only handles must not need a shared-memory or WAL file after publication.
    store.db.pragma("journal_mode = DELETE");
    return true;
  } catch (err) {
    if (missing !== undefined && ["SQLITE_CORRUPT", "SQLITE_NOTADB", "SQLITE_ERROR"].includes(err.code)) {
      return false;
    }
    throw err;
  } finally {
    store?.close();
  }
}

async function search({ query, k }) {
  const require = createRequire(join(pkg, "package.json"));
  const Database = require("better-sqlite3");
  const db = new Database(dbPath, { readonly: true, fileMustExist: true });
  try {
    require("sqlite-vec").load(db);
    const rows = await searchVec(db, query, model, k);
    // Older generations used the numeric ID alone.
    return rows.map((row) => row.displayPath.slice("code/".length).replace(/\/chunk$/, ""));
  } finally {
    db.close();
  }
}

try {
  if (action === "build") await build(payload);
  else if (action === "refresh") {
    console.log(JSON.stringify(await build(payload.docs, payload.missing, payload.maxNewChunks)));
  } else if (action === "search") {
    await llm.getDeviceInfo({ allowBuild: false });
    console.log(JSON.stringify(await search(payload)));
  } else throw new Error("Unknown QMD operation");
} finally {
  await llm.dispose();
}

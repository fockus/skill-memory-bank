// Native preflights for shared readers/writers that do not reject symlink aliases.
import * as fs from 'node:fs/promises';
import * as path from 'node:path';

export async function validatePath(file, kind, optional = false) {
  if (!path.isAbsolute(file) || path.normalize(file) !== file) throw new Error('unsafe path');
  const parts = file.slice(path.parse(file).root.length).split(path.sep).filter(Boolean);
  if (parts.length > 128) throw new Error('path depth limit');
  let current = path.parse(file).root;
  for (let i = 0; i < parts.length; i++) {
    current = path.join(current, parts[i]);
    let info;
    try { info = await fs.lstat(current); }
    catch (error) { if (optional && error.code === 'ENOENT') return null; throw error; }
    const directory = i < parts.length - 1 || kind === 'directory';
    if (info.isSymbolicLink() || (directory ? !info.isDirectory() : !info.isFile() || info.size > 1024 * 1024)) throw new Error('unsafe path');
  }
  return file;
}

export async function validateTree(directory) {
  if (!await validatePath(directory, 'directory', true)) return;
  const pending = [directory], deadline = Date.now() + 1000;
  let count = 0;
  while (pending.length) {
    const entries = await fs.opendir(pending.pop());
    for await (const entry of entries) {
      if (++count > 1000 || Date.now() > deadline) throw new Error('source tree limit');
      const file = path.join(entries.path, entry.name), info = await fs.lstat(file);
      if (info.isSymbolicLink()) throw new Error('unsafe source tree');
      if (info.isDirectory()) pending.push(file);
      else if (!info.isFile() || info.size > 1024 * 1024) throw new Error('unsafe source file');
    }
  }
}

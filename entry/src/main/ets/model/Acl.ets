/*******************************************************************************
 *                                                                             *
 *  Copyright (C) 2026 by Max Lv <max.c.lv@gmail.com>                          *
 *                                                                             *
 *  This program is free software: you can redistribute it and/or modify       *
 *  it under the terms of the GNU General Public License as published by       *
 *  the Free Software Foundation, either version 3 of the License, or          *
 *  (at your option) any later version.                                        *
 *                                                                             *
 *  This program is distributed in the hope that it will be useful,            *
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of             *
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              *
 *  GNU General Public License for more details.                               *
 *                                                                             *
 *  You should have received a copy of the GNU General Public License          *
 *  along with this program. If not, see <http://www.gnu.org/licenses/>.       *
 *                                                                             *
 *******************************************************************************/

/**
 * The ACL file format, and the one thing the core does not do with it.
 *
 * The format itself belongs to shadowsocks-rust, which parses the file we hand
 * it: `[bypass_all]` or `[proxy_all]` for the default, then `[bypass_list]`
 * and `[proxy_list]` for the exceptions. What the core does not know is the
 * `#IMPORT_URL <…>` comment shadowsocks-android uses to pull in a list served
 * somewhere else — to the core it is a comment, so if the app does not resolve
 * it, nothing ever does.
 *
 * `flattenAcl` is that resolution: it fetches each imported list, follows
 * imports inside those lists as far as the depth allows, and merges the entries
 * into the sections they belong to.
 */

/**
 * An ACL file, split into the parts that mean something. Entries are kept as
 * written: a hostname pattern and a subnet are both just lines here, and the
 * core is what decides which is which.
 */
export interface AclDocument {
  /** True when the file starts from "do not proxy" and lists exceptions. */
  bypass: boolean;
  /** Entries for `[bypass_list]`. */
  bypassEntries: string[];
  /** Entries for `[proxy_list]`. */
  proxyEntries: string[];
  /** Lists to pull in, one per `#IMPORT_URL <…>` line. */
  urls: string[];
}

/** Fetches the text of a list to import. Injected so it can be faked in tests. */
export type AclFetcher = (url: string) => Promise<string>;

const IMPORT_URL = new RegExp('^#\\s*IMPORT_URL\\s*<(.*)>\\s*$');

/** The sections of the format that carry entries, and what they mean. */
const BYPASS_SECTIONS: string[] = ['[black_list]', '[bypass_list]'];
const PROXY_SECTIONS: string[] = ['[white_list]', '[proxy_list]'];
const BYPASS_ALL_SECTIONS: string[] = ['[reject_all]', '[bypass_all]'];
const PROXY_ALL_SECTIONS: string[] = ['[accept_all]', '[proxy_all]'];

/** An empty document, defaulting to proxying everything. */
export function emptyAcl(): AclDocument {
  return { bypass: false, bypassEntries: [], proxyEntries: [], urls: [] };
}

/**
 * Reads an ACL file. A section the format does not define is skipped along with
 * its entries: a list from somewhere else must not be able to stop the tunnel
 * from starting, which is what the core would do with a file it cannot parse.
 */
export function parseAcl(text: string): AclDocument {
  const doc = emptyAcl();
  // Entries before any section header belong to the bypass list, and a default
  // line does not change which list is current — both are what the core's own
  // parser does, so a file it accepts reads here the way it reads there.
  let section = 'bypass';
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (line.length === 0) {
      continue;
    }
    const match = IMPORT_URL.exec(line);
    if (match !== null) {
      const url = match[1].trim();
      if (url.length > 0 && doc.urls.indexOf(url) < 0) {
        doc.urls.push(url);
      }
      continue;
    }
    if (line.startsWith('#')) {
      continue;
    }
    if (line.startsWith('[')) {
      if (BYPASS_SECTIONS.indexOf(line) >= 0) {
        section = 'bypass';
      } else if (PROXY_SECTIONS.indexOf(line) >= 0) {
        section = 'proxy';
      } else if (BYPASS_ALL_SECTIONS.indexOf(line) >= 0) {
        doc.bypass = true;
      } else if (PROXY_ALL_SECTIONS.indexOf(line) >= 0) {
        doc.bypass = false;
      } else {
        // includes `[outbound_block_list]`, whose entries are destinations the
        // proxy must not reach; the core does not act on it either way
        section = '';
      }
      continue;
    }
    if (section === 'bypass') {
      doc.bypassEntries.push(line);
    } else if (section === 'proxy') {
      doc.proxyEntries.push(line);
    }
  }
  return doc;
}

/** Writes a document back in the canonical shape: default first, then lists. */
export function serializeAcl(doc: AclDocument): string {
  const out: string[] = [doc.bypass ? '[bypass_all]' : '[proxy_all]'];
  if (doc.bypassEntries.length > 0) {
    out.push('');
    out.push('[bypass_list]');
    for (const entry of doc.bypassEntries) {
      out.push(entry);
    }
  }
  if (doc.proxyEntries.length > 0) {
    out.push('');
    out.push('[proxy_list]');
    for (const entry of doc.proxyEntries) {
      out.push(entry);
    }
  }
  if (doc.urls.length > 0) {
    out.push('');
    for (const url of doc.urls) {
      out.push(`#IMPORT_URL <${url}>`);
    }
  }
  return `${out.join('\n')}\n`;
}

function merge(into: string[], from: string[]): void {
  for (const entry of from) {
    if (into.indexOf(entry) < 0) {
      into.push(entry);
    }
  }
}

/**
 * Resolves every imported list, `depth` levels deep, and returns the file with
 * their entries folded in. The import lines are kept, so the result can be
 * flattened again later when the lists have moved on.
 *
 * A list that cannot be fetched leaves the file as it was rather than failing:
 * an unreachable list is a stale filter, not a reason to refuse to connect.
 *
 * Entries keep the meaning their own section gave them, which is a deliberate
 * departure from shadowsocks-android: it discards the subnets of an imported
 * list whose default differs from ours, because in its model an entry's meaning
 * is tied to the list it came from. Here every entry is written back into a
 * section of the file that imports it, so an imported `[proxy_list]` stays a
 * list of names that go through the proxy whatever either file's default is.
 */
export async function flattenAcl(text: string, depth: number, fetch: AclFetcher): Promise<string> {
  const doc = parseAcl(text);
  if (depth <= 0 || doc.urls.length === 0) {
    return text;
  }
  for (const url of doc.urls) {
    let childText = '';
    try {
      childText = await fetch(url);
    } catch (e) {
      continue;
    }
    const child = parseAcl(await flattenAcl(childText, depth - 1, fetch));
    merge(doc.bypassEntries, child.bypassEntries);
    merge(doc.proxyEntries, child.proxyEntries);
  }
  return serializeAcl(doc);
}

/** The URLs an ACL file imports, for deciding whether a refresh is worth it. */
export function importUrls(text: string): string[] {
  return parseAcl(text).urls;
}

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

import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { AclFetcher, flattenCompleteAcl, importUrls } from './Acl';

/**
 * Keeps an ACL file's imported lists up to date on disk.
 *
 * The tunnel cannot wait for the network: a list that is slow or unreachable
 * must not hold up connecting, and a stale filter is a far smaller problem than
 * no connection at all. So a start deploys whatever is already on disk, and the
 * refresh runs afterwards for the next start. That is the same shape as
 * shadowsocks-android's, which refreshes from a scheduled worker rather than
 * from the service start.
 *
 * A refresh either replaces the cached copy with a complete flattened file or
 * leaves the old copy alone. It never writes a partial one: a list that failed
 * would silently lose its entries for every later start.
 */

/** How deep an import chain is followed, the same ten levels Android follows. */
export const MAX_ACL_DEPTH: number = 10;

/** Where the refreshed copies live, under the app's files directory. */
function cacheDir(context: common.Context): string {
  return `${context.filesDir}/acl-cache`;
}

function cachePath(context: common.Context, name: string): string {
  return `${cacheDir(context)}/${name}`;
}

/** The refreshed copy of `name` from an earlier run, or '' if there is none. */
export async function cachedAcl(context: common.Context, name: string): Promise<string> {
  try {
    return fs.readTextSync(cachePath(context, name));
  } catch (e) {
    return '';
  }
}

/**
 * The text of an ACL file: the refreshed copy when one exists, otherwise the
 * bundled rawfile. Returns '' when neither can be read.
 *
 * The GFW List action reads through this. A refresh can replace the bundled
 * list, so the cached copy wins when it is there.
 */
export async function readAclText(context: common.Context, name: string): Promise<string> {
  const cached = await cachedAcl(context, name);
  if (cached.length > 0) {
    return cached;
  }
  try {
    const bytes = await context.resourceManager.getRawFileContent(`acl/${name}`);
    return bytesToText(bytes);
  } catch (e) {
    return '';
  }
}

/** The text of a rawfile, which arrives as bytes. The ACL files are ASCII. */
function bytesToText(bytes: Uint8Array): string {
  let out = '';
  for (let i = 0; i < bytes.length; i++) {
    out += String.fromCharCode(bytes[i]);
  }
  return out;
}

async function fetchText(url: string): Promise<string> {
  const request = http.createHttp();
  try {
    const response = await request.request(url, {
      method: http.RequestMethod.GET,
      connectTimeout: 15000,
      readTimeout: 15000,
    });
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(`HTTP ${response.responseCode}`);
    }
    return response.result as string;
  } finally {
    request.destroy();
  }
}

/**
 * Resolves the imported lists of `content` and stores the result for the next
 * start. Returns true when something was written.
 *
 * Every import must resolve before the cache is replaced. When one fails, the
 * cached file is left exactly as it was, so the previous list stays deployable,
 * and the failure is thrown to the caller to report. Writing the partial result
 * instead would deploy a list that lacks the failed list's entries on the next
 * start, which is worse than keeping the slightly older complete one.
 *
 * The write itself goes through a temporary file that is renamed over the
 * target. A start in another process reads this file while a refresh may be
 * writing it, and a rename is atomic: the reader sees the old copy or the new
 * one, never a truncated one.
 */
export async function refreshAcl(context: common.Context, name: string, content: string): Promise<boolean> {
  if (importUrls(content).length === 0) {
    return false;
  }
  const fetch: AclFetcher = (url: string) => fetchText(url);
  const failed: string[] = [];
  const flattened = await flattenCompleteAcl(content, MAX_ACL_DEPTH, fetch, failed);
  if (failed.length > 0) {
    throw new Error(`ACL import failed: ${failed.join(', ')}`);
  }
  const dir = cacheDir(context);
  try {
    fs.mkdirSync(dir);
  } catch (e) {
    // already there
  }
  const path = cachePath(context, name);
  const tmp = `${path}.tmp`;
  const file = fs.openSync(tmp,
    fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, flattened);
  } finally {
    fs.closeSync(file);
  }
  fs.renameSync(tmp, path);
  return true;
}

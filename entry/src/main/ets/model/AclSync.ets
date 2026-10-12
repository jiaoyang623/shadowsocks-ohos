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
import { AclFetcher, flattenAcl, importUrls } from './Acl';

/**
 * Keeps an ACL file's imported lists up to date on disk.
 *
 * The tunnel cannot wait for the network: a list that is slow or unreachable
 * must not hold up connecting, and a stale filter is a far smaller problem than
 * no connection at all. So a start deploys whatever is already on disk, and the
 * refresh runs afterwards for the next start. That is the same shape as
 * shadowsocks-android's, which refreshes from a scheduled worker rather than
 * from the service start.
 */

/** How deep an import chain is followed. One level covers the usual case. */
const MAX_DEPTH = 2;

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
 * A list that cannot be fetched is skipped by `flattenAcl`, so one dead URL
 * costs its own entries and nothing else.
 */
export async function refreshAcl(context: common.Context, name: string, content: string): Promise<boolean> {
  if (importUrls(content).length === 0) {
    return false;
  }
  const fetch: AclFetcher = (url: string) => fetchText(url);
  const flattened = await flattenAcl(content, MAX_DEPTH, fetch);
  const dir = cacheDir(context);
  try {
    fs.mkdirSync(dir);
  } catch (e) {
    // already there
  }
  const file = fs.openSync(cachePath(context, name),
    fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, flattened);
  } finally {
    fs.closeSync(file);
  }
  return true;
}

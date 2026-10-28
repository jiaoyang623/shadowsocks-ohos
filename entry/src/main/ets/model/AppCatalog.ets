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

import { bundleManager, common } from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { AppEntry } from './PerApp';

/**
 * The bundle name query for the Apps VPN mode picker.
 *
 * The adapter resolves a bundle name the profile already stores. It does not
 * list bundles, because a public list needs a system permission. A name that
 * the query cannot resolve stays in the profile, and the picker accepts a
 * name the user types.
 */

/** `bundleManager.getBundleInfo` is public since API 14. */
export const QUERY_MIN_API: number = 14;

/** The runtime is too old, or it has no query function. */
export const REASON_UNAVAILABLE: string = 'query-unavailable';
/** The app does not hold `ohos.permission.GET_BUNDLE_INFO`. */
export const REASON_PERMISSION: string = 'permission-denied';
/** The bundle manager knows no bundle with this name. */
export const REASON_NOT_FOUND: string = 'not-found';
/** The query failed for another reason. */
export const REASON_FAILED: string = 'query-failed';

/** One bundle name and what the query learned about it. */
export interface ResolvedApp {
  entry: AppEntry;
  found: boolean;
  reason: string;
}

/** True when the runtime has the API the query needs. */
export function queryAvailable(): boolean {
  return deviceInfo.sdkApiVersion >= QUERY_MIN_API;
}

/**
 * The bundle name of this app.
 *
 * The VPN lists need the name because the client must stay outside the
 * tunnel. The context knows its own application record. When that read
 * fails, the bundle manager answers for this app without a permission. When
 * both reads fail, the function returns an empty name, and the caller then
 * adds no client name.
 */
export function selfBundleName(context: common.Context): string {
  try {
    return context.applicationInfo.name;
  } catch (e) {
    return ownBundleName();
  }
}

function ownBundleName(): string {
  try {
    return bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).name;
  } catch (e) {
    return '';
  }
}

/** True when the runtime can answer a query for another bundle. */
function queryUsable(): boolean {
  return queryAvailable() && typeof bundleManager.getBundleInfo === 'function';
}

/** A row for a name the query did not confirm. */
function absent(bundleName: string, reason: string): ResolvedApp {
  return {
    entry: { bundleName: bundleName, label: bundleName },
    found: false,
    reason: reason,
  };
}

/**
 * One bundle name as a picker row.
 *
 * The row label is the bundle name. The public query returns another app's
 * label as a resource descriptor, and resolving that needs a privileged API.
 */
export async function resolveName(bundleName: string): Promise<ResolvedApp> {
  if (!queryUsable()) {
    return absent(bundleName, REASON_UNAVAILABLE);
  }
  try {
    await bundleManager.getBundleInfo(bundleName, bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    return {
      entry: { bundleName: bundleName, label: bundleName },
      found: true,
      reason: '',
    };
  } catch (e) {
    return absent(bundleName, reasonOf(e as BusinessError));
  }
}

/** The reason a failed query reports. The picker shows it beside the list. */
function reasonOf(err: BusinessError): string {
  if (err.code === 17700001) {
    return REASON_NOT_FOUND;
  }
  if (err.code === 201) {
    return REASON_PERMISSION;
  }
  return REASON_FAILED;
}

/** Every name in order. An error for one name does not stop the rest. */
export async function resolveNames(bundleNames: string[]): Promise<ResolvedApp[]> {
  const resolved: ResolvedApp[] = [];
  for (const name of bundleNames) {
    try {
      resolved.push(await resolveName(name));
    } catch (e) {
      resolved.push(absent(name, REASON_FAILED));
    }
  }
  return resolved;
}

/**
 * The names the VPN extension may pass to the platform, and why the query
 * could not verify them.
 *
 * `names` removes a name only when the bundle manager reports it absent. A
 * transient failure must not remove a name, because the app cannot tell the
 * two apart.
 *
 * `reason` is '' when every name resolved, and otherwise one of the REASON_*
 * values. An unavailable query keeps the stored names: the names are exact
 * bundle names the user selected, the platform ignores a name with no matching
 * bundle, and an empty list would change which apps use the tunnel. The reason
 * lets the caller log that the list was not verified.
 */
export interface InstalledNames {
  names: string[];
  reason: string;
}

/** The names the VPN extension may pass to the platform. */
export async function installedNames(bundleNames: string[]): Promise<InstalledNames> {
  if (!queryUsable()) {
    return { names: bundleNames.slice(), reason: REASON_UNAVAILABLE };
  }
  const installed: string[] = [];
  let reason: string = '';
  for (const name of bundleNames) {
    let resolved: ResolvedApp;
    try {
      resolved = await resolveName(name);
    } catch (e) {
      resolved = absent(name, REASON_FAILED);
    }
    if (resolved.reason === REASON_NOT_FOUND) {
      continue;
    }
    if (resolved.reason.length > 0 && reason.length === 0) {
      reason = resolved.reason;
    }
    installed.push(name);
  }
  return { names: installed, reason: reason };
}

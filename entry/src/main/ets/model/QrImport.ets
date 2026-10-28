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

import { Profile } from './Profile';
import { parseProfileUrls } from './ProfilesFile';

/**
 * Profiles from a scanned QR code.
 *
 * A QR code holds text. The text usually holds one `ss://` URL, and it can hold
 * more. The parser accepts `ss://` URLs only, as the Android analyzer does.
 *
 * The functions are pure. The QR platform adapter calls them, and the host
 * specs check them without a device.
 */

/**
 * Copies the settings that belong to the device from the current profile.
 *
 * A QR code describes a server. The route, the resolver settings, the metered
 * flag and the per-app settings describe how this device uses a server, so they
 * come from the profile in use. The scanned value keeps its own identity: host,
 * port, method, password, name, plugin, and plugin options.
 *
 * It copies the same set as `Profile.copyFeatureSettings`, plus the remote
 * resolver.
 */
export function copyFeatureSettings(target: Profile, current: Profile | null): void {
  if (current === null) {
    return;
  }
  target.route = current.route;
  target.ipv6 = current.ipv6;
  target.udpdns = current.udpdns;
  target.remoteDns = current.remoteDns;
  target.metered = current.metered;
  target.proxyAppsEnabled = current.proxyAppsEnabled;
  target.proxyAppsBypass = current.proxyAppsBypass;
  target.proxyAppsList = current.proxyAppsList;
}

/**
 * The profiles a scanned text holds, in text order.
 *
 * A malformed URL is dropped. The other URLs still import, because one bad URL
 * must not discard a whole scan.
 */
export function profilesFromScan(text: string, current: Profile | null): Profile[] {
  const profiles: Profile[] = parseProfileUrls(text);
  for (const profile of profiles) {
    copyFeatureSettings(profile, current);
  }
  return profiles;
}

/**
 * The profiles a batch of scanned texts holds, in array and text order.
 *
 * The page calls this for a batch of images. Each image contributes its own
 * profiles, and an image with no profile contributes nothing.
 */
export function profilesFromScanTexts(texts: string[], current: Profile | null): Profile[] {
  const profiles: Profile[] = [];
  for (const text of texts) {
    const scanned: Profile[] = profilesFromScan(text, current);
    for (const profile of scanned) {
      profiles.push(profile);
    }
  }
  return profiles;
}

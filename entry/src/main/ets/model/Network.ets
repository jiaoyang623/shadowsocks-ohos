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

import { connection } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'Network';

/**
 * The resolver the current network hands out, or '' when it cannot be read.
 *
 * This is what names the route sends directly are resolved with, and it matters
 * that it is the network's own resolver rather than a fixed one: a hardcoded
 * public resolver is exactly the kind of address a network can block, and being
 * behind such a network is one reason to be running this at all.
 * shadowsocks-android reads its resolver the same way, through the platform.
 */
export function localDnsServer(): string {
  try {
    const net = connection.getDefaultNetSync();
    if (net.netId === 0) {
      return ''; // no default network yet
    }
    const properties = connection.getConnectionPropertiesSync(net);
    for (const dns of properties.dnses) {
      if (dns.address.length > 0) {
        return dns.address;
      }
    }
  } catch (e) {
    hilog.warn(0x0000, TAG, 'could not read the network resolver');
  }
  return '';
}

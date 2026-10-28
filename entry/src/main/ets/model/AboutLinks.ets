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
 * The About page's links and text.
 *
 * The file is pure. It imports nothing, so the host specs can check the link
 * classification without a device.
 */

/** A link that opens in a browser. */
export const ABOUT_LINK_WEB: string = 'web';
/** A link that opens a mail client. */
export const ABOUT_LINK_EMAIL: string = 'email';
/** A link into the licence text itself. This app has no such page. */
export const ABOUT_LINK_OSS: string = 'oss';

/** The Shadowsocks project site. */
export const ABOUT_URL_SHADOWSOCKS: string = 'http://shadowsocks.org';
/** The GNU licence page. */
export const ABOUT_URL_GNU: string = 'http://www.gnu.org/licenses/';
/** The address of the original author. */
export const ABOUT_MAIL_MAX_LV: string = 'mailto:max.c.lv@gmail.com';
/** The address of Mygod Studio. */
export const ABOUT_MAIL_MYGOD: string = 'mailto:contact-shadowsocks-android@mygod.be';

/**
 * The seven upstream links from shadowsocks-android's `about.html`, in order.
 *
 * The last value is an in-page anchor. The About page shows the row for display
 * parity and reports that the list is unavailable on this device.
 */
export const ABOUT_LICENCE_URLS: string[] = [
  'https://github.com/shadowsocks/redsocks/blob/shadowsocks-android/README',
  'https://github.com/shadowsocks/libevent/blob/master/LICENSE',
  'https://github.com/shadowsocks/badvpn/blob/shadowsocks-android/COPYING',
  'https://github.com/shadowsocks/shadowsocks-rust/blob/master/LICENSE',
  'https://github.com/jedisct1/libsodium/blob/master/LICENSE',
  'https://www.openssl.org/source/license-openssl-ssleay.txt',
  '#other-licenses',
];

/** The kind of handler a link needs: one of the ABOUT_LINK_* constants. */
export function classifyAboutLink(url: string): string {
  if (url.startsWith('#')) {
    return ABOUT_LINK_OSS;
  }
  if (url.startsWith('mailto:')) {
    return ABOUT_LINK_EMAIL;
  }
  return ABOUT_LINK_WEB;
}

/** Title for the About page: the app name, with the version when present. */
export function aboutTitle(appName: string, version: string): string {
  return version.length > 0 ? `${appName} ${version}` : appName;
}

/**
 * The paragraphs of the About body, in order.
 *
 * One blank line separates two paragraphs. Each block is trimmed, and an empty
 * block is dropped.
 */
export function splitAboutBody(text: string): string[] {
  const paragraphs: string[] = [];
  for (const block of text.split(/\n\s*\n/)) {
    const trimmed = block.trim();
    if (trimmed.length > 0) {
      paragraphs.push(trimmed);
    }
  }
  return paragraphs;
}

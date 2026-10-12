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
import { AclDocument, emptyAcl, parseAcl, serializeAcl } from './Acl';

/**
 * The rules the user writes, and the file the core is given for them.
 *
 * The presets ship as files. These do not: the user writes them in the app, and
 * what the core reads is composed from what they wrote. The composition is
 * small but it decides what the route means, so it lives here, where the host
 * specs can reach it, rather than inside the page that edits it.
 */

/** The file holding what the user wrote, under the app's files directory. */
export const USER_RULES_FILE = 'custom-rules-user.acl';

/** The three kinds of rule the editor offers, as shadowsocks-android does. */
export const RULE_KIND_DOMAIN = 'domain';
export const RULE_KIND_SUBNET = 'subnet';
export const RULE_KIND_URL = 'url';

function userRulesPath(context: common.Context): string {
  return `${context.filesDir}/${USER_RULES_FILE}`;
}

/** What the user wrote, or '' when they have written nothing yet. */
export function readUserRules(context: common.Context): string {
  try {
    return fs.readTextSync(userRulesPath(context));
  } catch (e) {
    return '';
  }
}

/** Keeps what the user wrote, creating the directory if it is the first time. */
export function writeUserRules(context: common.Context, text: string): void {
  const file = fs.openSync(userRulesPath(context),
    fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, text);
  } finally {
    fs.closeSync(file);
  }
}

/**
 * The rules file to hand the core: what the user wrote, with the default forced
 * to bypassing the proxy and the exceptions they listed going through it. A
 * list of "what should be proxied" is the only thing this route can sensibly
 * mean, so a file that says otherwise is turned round rather than obeyed.
 *
 * shadowsocks-android does the same, except that it also drops the subnets of a
 * file whose default it had to turn round. Here nothing is dropped: entries are
 * written back into sections that state what they mean, so a subnet the user
 * listed as bypassed stays bypassed whatever the default is.
 */
export function composeCustomRules(userText: string): string {
  const doc: AclDocument = userText.trim().length === 0 ? emptyAcl() : parseAcl(userText);
  doc.bypass = true;
  return serializeAcl(doc);
}

/**
 * Adds one rule to what the user wrote and returns the new text. A URL is an
 * import rather than an entry, which is the one kind of rule that names another
 * list instead of a destination.
 */
export function addRule(userText: string, kind: string, value: string): string {
  const doc: AclDocument = userText.trim().length === 0 ? emptyAcl() : parseAcl(userText);
  const rule = value.trim();
  if (rule.length === 0) {
    return userText;
  }
  if (kind === RULE_KIND_URL) {
    if (doc.urls.indexOf(rule) < 0) {
      doc.urls.push(rule);
    }
  } else if (doc.bypassEntries.indexOf(rule) < 0 && doc.proxyEntries.indexOf(rule) < 0) {
    // a rule the user adds is one they want proxied, which is what the route
    // does with everything it is given
    doc.proxyEntries.push(rule);
  }
  return serializeAcl(doc);
}

/** Removes one rule, from whichever list holds it. Returns the new text. */
export function removeRule(userText: string, value: string): string {
  const doc = parseAcl(userText);
  const rule = value.trim();
  doc.bypassEntries = doc.bypassEntries.filter((entry) => entry !== rule);
  doc.proxyEntries = doc.proxyEntries.filter((entry) => entry !== rule);
  doc.urls = doc.urls.filter((entry) => entry !== rule);
  return serializeAcl(doc);
}

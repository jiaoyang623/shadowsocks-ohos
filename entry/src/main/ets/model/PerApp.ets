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

/**
 * The per-app proxy rules for Apps VPN mode.
 *
 * This module is pure ArkTS. It imports no kit. It reads no file and writes no
 * file. The page and the VPN extension call it, and the host specs reach it.
 *
 * shadowsocks-android uses a UID as the selection key. HarmonyOS has no public
 * UID for another app, so the bundle name is the key here (R-UG-03).
 */

/** Apps VPN mode is off. */
export const APP_MODE_OFF: string = 'off';
/** Apps VPN mode is on: only the selected apps use the tunnel. */
export const APP_MODE_ON: string = 'on';
/** Apps VPN mode is bypass: the selected apps skip the tunnel. */
export const APP_MODE_BYPASS: string = 'bypass';

/** The platform accepts at most 64 bundle names per list before API 23. */
export const MAX_APP_LIST: number = 64;

/** The longest bundle name that the validator accepts. */
const MAX_BUNDLE_NAME: number = 128;

/** Two or more dot-separated segments, each one starting with a letter. */
const BUNDLE_NAME_PATTERN: RegExp =
  /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$/;

/** One app row. HarmonyOS has no UID, so the label is the bundle name. */
export interface AppEntry {
  bundleName: string;
  label: string;
}

/** The mode and the list, as the draft and the profile hold them. */
export interface PerAppState {
  enabled: boolean;
  bypass: boolean;
  list: string;
}

/** The two application lists a VpnConfig takes. Only one is non-empty. */
export interface VpnAppLists {
  trusted: string[];
  blocked: string[];
}

/** Trims the names, drops empty names and duplicates, and keeps the order. */
function uniqueNames(names: string[]): string[] {
  const kept: string[] = [];
  for (const name of names) {
    const trimmed = name.trim();
    if (trimmed.length > 0 && kept.indexOf(trimmed) < 0) {
      kept.push(trimmed);
    }
  }
  return kept;
}

/**
 * The mode that one pair of flags means.
 *
 * A disabled profile is Off, whatever the bypass flag says.
 */
export function appMode(enabled: boolean, bypass: boolean): string {
  if (!enabled) {
    return APP_MODE_OFF;
  }
  return bypass ? APP_MODE_BYPASS : APP_MODE_ON;
}

/**
 * The names of one stored list.
 *
 * The function splits on a newline. It trims each line. It drops empty lines
 * and duplicates. It keeps the input order.
 */
export function namesOf(list: string): string[] {
  return uniqueNames(list.split('\n'));
}

/**
 * The normalized list text for an array of names.
 *
 * The function applies the `namesOf` rule and joins the result with a newline.
 */
export function joinNames(names: string[]): string {
  return uniqueNames(names).join('\n');
}

/**
 * The list text with one name toggled.
 *
 * The function removes the name when it is present. It appends the name when
 * it is not. The other names keep their order.
 */
export function toggleName(list: string, bundleName: string): string {
  const names = namesOf(list);
  const index = names.indexOf(bundleName);
  if (index >= 0) {
    names.splice(index, 1);
  } else {
    names.push(bundleName);
  }
  return joinNames(names);
}

/**
 * True when the text is a bundle name that the VPN config accepts.
 *
 * The name has two or more dot-separated segments. Each segment starts with
 * an ASCII letter. The later characters are letters, digits, or `_`. The
 * total length is at most 128.
 */
export function isValidBundleName(name: string): boolean {
  return name.length <= MAX_BUNDLE_NAME && BUNDLE_NAME_PATTERN.test(name);
}

/**
 * True when the query is empty, or when it occurs in the label or the bundle
 * name.
 *
 * The match ignores case. Spaces around the query do not count.
 */
export function matchesQuery(entry: AppEntry, query: string): boolean {
  const needle = query.trim().toLowerCase();
  if (needle.length === 0) {
    return true;
  }
  return entry.label.toLowerCase().indexOf(needle) >= 0
    || entry.bundleName.toLowerCase().indexOf(needle) >= 0;
}

/** The entries that match the query, in the input order. */
export function visibleEntries(entries: AppEntry[], query: string): AppEntry[] {
  return entries.filter((entry: AppEntry) => matchesQuery(entry, query));
}

/**
 * A copy of the entries in display order.
 *
 * The selected names come first. Within one group the label sorts ascending.
 * The function does not write the stored list, so the stored order stays.
 */
export function sortEntries(entries: AppEntry[], selected: string): AppEntry[] {
  const chosen = namesOf(selected);
  const copy = entries.slice();
  copy.sort((left: AppEntry, right: AppEntry) => {
    const leftChosen = chosen.indexOf(left.bundleName) >= 0;
    const rightChosen = chosen.indexOf(right.bundleName) >= 0;
    if (leftChosen !== rightChosen) {
      return leftChosen ? -1 : 1;
    }
    if (left.label < right.label) {
      return -1;
    }
    if (left.label > right.label) {
      return 1;
    }
    return 0;
  });
  return copy;
}

/**
 * The clipboard text for one bypass flag and one list.
 *
 * The first line holds the bypass flag. Each later line holds one bundle name.
 */
export function exportText(bypass: boolean, list: string): string {
  return `${bypass}\n${joinNames(namesOf(list))}`;
}

/**
 * The state that one clipboard text means, or null for an empty text.
 *
 * The first line is the bypass flag. The value `true` in any letter case sets
 * the bypass flag. Every other value clears the bypass flag. The later lines
 * are the names. A text without a newline gives an empty list.
 */
export function parseImportText(text: string): PerAppState | null {
  if (text.length === 0) {
    return null;
  }
  const lines = text.split('\n');
  const bypass = lines[0].trim().toLowerCase() === 'true';
  let list = '';
  if (lines.length > 1) {
    list = joinNames(lines.slice(1));
  }
  return { enabled: true, bypass: bypass, list: list };
}

/**
 * Copies the bypass flag and the list to every profile.
 *
 * The enabled flag does not change, so a profile with Apps VPN mode off stays
 * off. The function returns the same array. The caller saves the array.
 */
export function applyToAll(profiles: Profile[], bypass: boolean, list: string): Profile[] {
  const normalized = joinNames(namesOf(list));
  for (const profile of profiles) {
    profile.proxyAppsBypass = bypass;
    profile.proxyAppsList = normalized;
  }
  return profiles;
}

/**
 * The number of names that the page lets the user select.
 *
 * In Bypass mode the client bundle takes one slot in the blocked list.
 */
export function selectionCap(bypass: boolean): number {
  return bypass ? MAX_APP_LIST - 1 : MAX_APP_LIST;
}

/**
 * The two VpnConfig application lists for one mode and one list.
 *
 * Only one list is non-empty. On mode gives the selected names as trusted.
 * Bypass mode gives the client bundle first, then the selected names that are
 * not the client bundle, as blocked. Each list is cut to `cap`.
 */
export function vpnApplicationLists(enabled: boolean, bypass: boolean, list: string,
  clientBundle: string, cap: number = MAX_APP_LIST): VpnAppLists {
  if (!enabled) {
    return { trusted: [], blocked: [] };
  }
  const names = namesOf(list).filter((name: string) => name !== clientBundle);
  if (!bypass) {
    return { trusted: names.slice(0, cap), blocked: [] };
  }
  const blocked: string[] = [];
  if (clientBundle.length > 0) {
    blocked.push(clientBundle);
  }
  for (const name of names) {
    blocked.push(name);
  }
  return { trusted: [], blocked: blocked.slice(0, cap) };
}

/**
 * The per-app values of the profile that the editor has open.
 *
 * One draft exists per UI process. The VPN extension never reads it. A process
 * death discards the unsaved edits.
 */
export class PerAppDraft {
  static profileId: string = '';
  static enabled: boolean = false;
  static bypass: boolean = false;
  static list: string = '';
  static dirty: boolean = false;

  /**
   * Starts the draft from one profile.
   *
   * The list takes the normalized form. The draft is clean after the call.
   */
  static open(profile: Profile): void {
    PerAppDraft.profileId = profile.id;
    PerAppDraft.enabled = profile.proxyAppsEnabled;
    PerAppDraft.bypass = profile.proxyAppsBypass;
    PerAppDraft.list = joinNames(namesOf(profile.proxyAppsList));
    PerAppDraft.dirty = false;
  }

  /**
   * Turns the draft on when it was off.
   *
   * The call marks the draft dirty only when it changes the flag.
   */
  static ensureEnabled(): void {
    if (!PerAppDraft.enabled) {
      PerAppDraft.enabled = true;
      PerAppDraft.dirty = true;
    }
  }

  /**
   * Sets one mode. The list does not change.
   *
   * Off keeps the bypass flag, so the mode can return to Bypass.
   */
  static setMode(mode: string): void {
    if (mode === APP_MODE_OFF) {
      PerAppDraft.enabled = false;
    } else if (mode === APP_MODE_ON) {
      PerAppDraft.enabled = true;
      PerAppDraft.bypass = false;
    } else if (mode === APP_MODE_BYPASS) {
      PerAppDraft.enabled = true;
      PerAppDraft.bypass = true;
    } else {
      return;
    }
    PerAppDraft.dirty = true;
  }

  /** Replaces the list with the normalized form. */
  static setList(list: string): void {
    PerAppDraft.list = joinNames(namesOf(list));
    PerAppDraft.dirty = true;
  }

  /** A copy of the three values. */
  static state(): PerAppState {
    return {
      enabled: PerAppDraft.enabled,
      bypass: PerAppDraft.bypass,
      list: PerAppDraft.list,
    };
  }

  /** The text that the editor compares to find an unsaved change. */
  static snapshot(): string {
    const enabled = PerAppDraft.enabled ? '1' : '0';
    const bypass = PerAppDraft.bypass ? '1' : '0';
    return `${enabled}|${bypass}|${PerAppDraft.list}`;
  }

  /** Resets every field. */
  static clear(): void {
    PerAppDraft.profileId = '';
    PerAppDraft.enabled = false;
    PerAppDraft.bypass = false;
    PerAppDraft.list = '';
    PerAppDraft.dirty = false;
  }
}

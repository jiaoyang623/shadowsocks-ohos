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
import { JsonStore } from './JsonStore';
import {
  DEFAULT_REMOTE_DNS, Profile, STATUS_ACTIVE, STATUS_OBSOLETE, STATUS_USER_CONFIGURED,
  newManualProfile, nextUserOrder,
} from './Profile';
import { ROUTE_ALL } from './Routes';

const STORE_PROFILES = 'profiles';
const STORE_CURRENT_ID = 'current_profile_id';

/**
 * Persists the profile list and the selected (active) profile, mirroring
 * shadowsocks-android's profile database. Storage is a JSON file via
 * JsonStore (see there for why not @ohos.data.preferences).
 */
export class ProfileStore {
  static fromJson(parsed: Profile): Profile {
    const profile = new Profile();
    profile.id = parsed.id ?? '';
    profile.name = parsed.name ?? 'Default';
    profile.host = parsed.host ?? '';
    profile.remotePort = parsed.remotePort ?? 8388;
    profile.password = parsed.password ?? '';
    profile.method = parsed.method ?? 'aes-256-gcm';
    profile.route = parsed.route ?? ROUTE_ALL;
    profile.subscriptionId = parsed.subscriptionId ?? '';
    profile.localAddress = parsed.localAddress ?? '127.0.0.1';
    profile.localPort = parsed.localPort ?? 1080;
    profile.plugin = parsed.plugin ?? '';
    profile.pluginOpts = parsed.pluginOpts ?? '';
    // A record written before 5.4.0 has no plugin map. Its absence decides
    // whether an empty options text is a choice or a missing configuration.
    const storesPluginConfigs =
      parsed.pluginConfigs !== null && parsed.pluginConfigs !== undefined;
    profile.pluginConfigs = ProfileStore.copyPluginConfigs(parsed.pluginConfigs);
    profile.remoteDns = parsed.remoteDns ?? DEFAULT_REMOTE_DNS;
    profile.udpdns = parsed.udpdns ?? false;
    profile.ipv6 = parsed.ipv6 ?? false;
    profile.metered = parsed.metered ?? false;
    profile.proxyAppsEnabled = parsed.proxyAppsEnabled ?? false;
    profile.proxyAppsBypass = parsed.proxyAppsBypass ?? false;
    profile.proxyAppsList = parsed.proxyAppsList ?? '';
    profile.udpFallbackId = parsed.udpFallbackId ?? '';
    // A 5.3.5 record has no status field. A record that names a subscription
    // still belongs to it, so it stays active on upgrade. The first 5.4.0
    // refresh can then update or obsolete it. An empty id stays user owned.
    profile.subscriptionStatus = parsed.subscriptionStatus ??
      (profile.subscriptionId.length > 0 ? STATUS_ACTIVE : STATUS_USER_CONFIGURED);
    profile.tx = parsed.tx ?? 0;
    profile.rx = parsed.rx ?? 0;
    profile.userOrder = parsed.userOrder ?? 0;
    // An old record has no plugin map, so an empty options text there takes
    // the catalogue default. A record with the map states its options, so an
    // explicit empty text stays empty and round-trips.
    profile.normalizePluginOptions(!storesPluginConfigs);
    return profile;
  }

  /**
   * A copy of a stored plugin map. The copy keeps the load separate from the
   * stored record. An entry that is not a string is dropped.
   */
  private static copyPluginConfigs(
    source: Record<string, string> | null | undefined): Record<string, string> {
    const target: Record<string, string> = {};
    if (source === null || source === undefined) {
      return target;
    }
    const entries = source as Record<string, Object>;
    for (const key of Object.keys(entries)) {
      const value = entries[key];
      if (typeof value === 'string') {
        target[key] = value;
      }
    }
    return target;
  }

  /**
   * The list from one stored text. An empty text gives an empty list. A JSON
   * error gives null, so a caller can tell a corrupt file from an empty one.
   */
  private static parse(raw: string): Profile[] | null {
    if (raw.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as Profile[];
      const profiles = parsed.map((p) => ProfileStore.fromJson(p));
      // The file order is not the display order: the user's is kept in
      // userOrder, and a stable sort leaves a file written before that field
      // existed in the order it was already in.
      return ProfileStore.sorted(profiles);
    } catch (e) {
      return null;
    }
  }

  static async getAll(context: common.Context): Promise<Profile[]> {
    const raw = await JsonStore.read(context, STORE_PROFILES);
    return ProfileStore.parse(raw) ?? [];
  }

  /**
   * The stored list, or null when the file is present and cannot be read.
   * `getAll` returns an empty list for an absent file and for a corrupt file
   * alike. A caller that writes back what it read must tell the two apart.
   */
  static async getAllOrNull(context: common.Context): Promise<Profile[] | null> {
    const raw = await JsonStore.read(context, STORE_PROFILES);
    if (raw.length === 0) {
      return JsonStore.exists(context, STORE_PROFILES) ? null : [];
    }
    return ProfileStore.parse(raw);
  }

  static async saveAll(context: common.Context, profiles: Profile[]): Promise<void> {
    await JsonStore.write(context, STORE_PROFILES, JSON.stringify(profiles));
  }

  /** Inserts a new profile or updates the existing one with the same id. */
  static async upsert(context: common.Context, profile: Profile): Promise<void> {
    profile.ensureId();
    const profiles = await ProfileStore.getAll(context);
    const index = profiles.findIndex((p) => p.id === profile.id);
    if (index >= 0) {
      profiles[index] = profile;
    } else {
      if (profile.userOrder <= 0) {
        profile.userOrder = nextUserOrder(profiles);
      }
      profiles.push(profile);
    }
    await ProfileStore.saveAll(context, profiles);
  }

  /**
   * Android's `ensureNotEmpty`: an empty list gets Android's default profile
   * (an empty name and `example.shadowsocks.org:8388`) and it is selected, so
   * a fresh install shows the same row Android does. A user who deletes the
   * last profile gets it back, which is also what Android does.
   *
   * Seeding writes the whole list, so an empty read is not enough to act on:
   * `getAll` also returns an empty array when the file cannot be read, and
   * overwriting then would destroy every profile it holds. The file has to be
   * absent, or parse to an empty array, before anything is written.
   */
  static async ensureNotEmpty(context: common.Context): Promise<void> {
    const profiles = await ProfileStore.getAll(context);
    if (profiles.length > 0) {
      return;
    }
    if (JsonStore.exists(context, STORE_PROFILES)) {
      const raw = (await JsonStore.read(context, STORE_PROFILES)).trim();
      if (raw !== '[]') {
        return;
      }
    }
    const profile = newManualProfile(null);
    await ProfileStore.upsert(context, profile);
    await ProfileStore.setCurrentId(context, profile.id);
  }

  /**
   * The profiles to show: a subscription no longer lists an obsolete one, so it
   * is kept for a possible return but not offered.
   *
   * Filtering here rather than in `getAll` is deliberate: `getAll` is the
   * storage view, and writing back what it returned must not drop anything.
   */
  static visible(profiles: Profile[]): Profile[] {
    return profiles.filter((p) => p.subscriptionStatus !== STATUS_OBSOLETE);
  }

  /** A copy of the list in ascending userOrder. The stored order stays. */
  static sorted(profiles: Profile[]): Profile[] {
    const copy = profiles.slice();
    copy.sort((a, b) => a.userOrder - b.userOrder);
    return copy;
  }

  /**
   * The rows to show. The search text filters by name and host, and the ids in
   * `hiddenIds` stay hidden because their delete is not committed.
   *
   * An empty query keeps every profile. The compare ignores case.
   */
  static filter(profiles: Profile[], query: string, hiddenIds: string[] = []): Profile[] {
    const needle = query.trim().toLowerCase();
    return profiles.filter((p) => {
      if (hiddenIds.indexOf(p.id) >= 0) {
        return false;
      }
      if (needle.length === 0) {
        return true;
      }
      return p.name.toLowerCase().indexOf(needle) >= 0
        || p.host.toLowerCase().indexOf(needle) >= 0;
    });
  }

  /** The row index of a profile id, or -1 when the id has no row. */
  static indexOf(profiles: Profile[], id: string): number {
    return profiles.findIndex((p) => p.id === id);
  }

  /**
   * Moves the profile at `from` to `to` in the display order, then rewrites
   * every key. Renumbering rather than swapping keeps the keys agreeing with
   * the list the user sees, which is the only thing they order.
   */
  static async move(context: common.Context, from: number, to: number): Promise<Profile[]> {
    const profiles = await ProfileStore.getAll(context);
    if (from === to || from < 0 || to < 0 || from >= profiles.length || to >= profiles.length) {
      return profiles;
    }
    const moved = profiles.splice(from, 1);
    profiles.splice(to, 0, moved[0]);
    for (let i = 0; i < profiles.length; i++) {
      profiles[i].userOrder = i + 1;
    }
    await ProfileStore.saveAll(context, profiles);
    return profiles;
  }

  /**
   * Adds a session's counters to a profile, the way shadowsocks-android keeps
   * tx and rx per profile.
   */
  static async addTraffic(context: common.Context, id: string, tx: number, rx: number): Promise<void> {
    const profiles = await ProfileStore.getAll(context);
    const index = profiles.findIndex((p) => p.id === id);
    if (index < 0) {
      return;
    }
    profiles[index].tx += tx;
    profiles[index].rx += rx;
    await ProfileStore.saveAll(context, profiles);
  }

  static async remove(context: common.Context, id: string): Promise<void> {
    const profiles = (await ProfileStore.getAll(context)).filter((p) => p.id !== id);
    await ProfileStore.saveAll(context, profiles);
    const currentId = await ProfileStore.getCurrentId(context);
    if (currentId === id) {
      await ProfileStore.setCurrentId(context,
        ProfileStore.currentIdAfterRemove(profiles, currentId, id));
    }
  }

  /**
   * The selection to keep after `removedId` leaves the list. A selection that
   * names another profile stays. A selection that named the removed profile
   * moves to the first visible row, or clears when the list holds no visible
   * row. `visible()` hides an obsolete profile, so selecting one would leave
   * the screen with no check mark while a start used it.
   *
   * The stored list is expected to be the one after the removal.
   */
  static currentIdAfterRemove(profiles: Profile[], currentId: string,
    removedId: string): string {
    if (currentId !== removedId) {
      return currentId;
    }
    const visible = ProfileStore.visible(profiles);
    return visible.length > 0 ? visible[0].id : '';
  }

  static async getCurrentId(context: common.Context): Promise<string> {
    return JsonStore.read(context, STORE_CURRENT_ID);
  }

  static async setCurrentId(context: common.Context, id: string): Promise<void> {
    await JsonStore.write(context, STORE_CURRENT_ID, id);
  }

  /**
   * The selected profile, or null when the stored id names no visible profile.
   * The first profile is not a substitute: a start with no selection stops
   * with "Please select a profile" (R-UA-27).
   */
  static async getCurrent(context: common.Context): Promise<Profile | null> {
    const profiles = await ProfileStore.getAll(context);
    const currentId = await ProfileStore.getCurrentId(context);
    return ProfileStore.currentOf(profiles, currentId);
  }

  /**
   * The profile the id names, or null when it names no visible row. A
   * selection is valid only for a row the main screen shows: an obsolete
   * profile stays in the store but `visible()` hides it, so selecting one
   * would start a tunnel with no check mark on the list.
   */
  static currentOf(profiles: Profile[], currentId: string): Profile | null {
    if (currentId.length === 0) {
      return null;
    }
    for (const profile of profiles) {
      if (profile.id === currentId && profile.subscriptionStatus !== STATUS_OBSOLETE) {
        return profile;
      }
    }
    return null;
  }
}

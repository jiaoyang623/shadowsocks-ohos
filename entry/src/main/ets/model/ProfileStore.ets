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
import { DEFAULT_REMOTE_DNS, Profile, STATUS_USER_CONFIGURED, nextUserOrder } from './Profile';
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
    profile.remoteDns = parsed.remoteDns ?? DEFAULT_REMOTE_DNS;
    profile.udpdns = parsed.udpdns ?? false;
    profile.ipv6 = parsed.ipv6 ?? false;
    profile.udpFallbackId = parsed.udpFallbackId ?? '';
    profile.subscriptionStatus = parsed.subscriptionStatus ?? STATUS_USER_CONFIGURED;
    profile.tx = parsed.tx ?? 0;
    profile.rx = parsed.rx ?? 0;
    profile.userOrder = parsed.userOrder ?? 0;
    return profile;
  }

  static async getAll(context: common.Context): Promise<Profile[]> {
    const raw = await JsonStore.read(context, STORE_PROFILES);
    if (raw.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as Profile[];
      const profiles = parsed.map((p) => ProfileStore.fromJson(p));
      // The file order is not the display order: the user's is kept in
      // userOrder, and a stable sort leaves a file written before that field
      // existed in the order it was already in.
      return profiles.sort((a, b) => a.userOrder - b.userOrder);
    } catch (e) {
      return [];
    }
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
      await ProfileStore.setCurrentId(context, profiles.length > 0 ? profiles[0].id : '');
    }
  }

  /**
   * Atomically replaces every profile owned by `subscriptionId` with the
   * freshly-fetched list (used by subscription updates). Returns the new
   * full profile list.
   */
  static async replaceSubscription(context: common.Context, subscriptionId: string,
    fresh: Profile[]): Promise<Profile[]> {
    const manual = (await ProfileStore.getAll(context)).filter((p) => p.subscriptionId !== subscriptionId);
    const profiles = manual.concat(fresh);
    await ProfileStore.saveAll(context, profiles);
    const current = await ProfileStore.getCurrent(context);
    if (current === null && profiles.length > 0) {
      await ProfileStore.setCurrentId(context, profiles[0].id);
    }
    return profiles;
  }

  static async getCurrentId(context: common.Context): Promise<string> {
    return JsonStore.read(context, STORE_CURRENT_ID);
  }

  static async setCurrentId(context: common.Context, id: string): Promise<void> {
    await JsonStore.write(context, STORE_CURRENT_ID, id);
  }

  /** The selected profile, or null when none is configured. */
  static async getCurrent(context: common.Context): Promise<Profile | null> {
    const profiles = await ProfileStore.getAll(context);
    if (profiles.length === 0) {
      return null;
    }
    const currentId = await ProfileStore.getCurrentId(context);
    return profiles.find((p) => p.id === currentId) ?? profiles[0];
  }
}

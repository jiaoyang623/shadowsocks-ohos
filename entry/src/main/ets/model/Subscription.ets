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

import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { JsonStore } from './JsonStore';
import { STATUS_ACTIVE, STATUS_OBSOLETE, STATUS_USER_CONFIGURED, newProfileId, nextUserOrder, Profile } from './Profile';
import { addressKey } from './ProfilesFile';

const STORE_SUBSCRIPTIONS = 'subscriptions';

/** A remote profile subscription (a URL serving ss:// links). */
export class Subscription {
  id: string = '';
  url: string = '';
  /** Last successful update, milliseconds since epoch; 0 = never. */
  updatedAt: number = 0;

  ensureId(): void {
    if (this.id.length === 0) {
      this.id = newProfileId();
    }
  }
}

/** Persists the subscription list as a JSON file via JsonStore. */
export class SubscriptionStore {
  /**
   * Rebuilds a Subscription from a parsed JSON object. JSON.parse yields
   * plain objects, so the class methods (`ensureId`) are absent until the
   * fields are copied onto a real instance — same reason ProfileStore has a
   * `fromJson`.
   */
  static fromJson(parsed: Subscription): Subscription {
    const subscription = new Subscription();
    subscription.id = parsed.id ?? '';
    subscription.url = parsed.url ?? '';
    subscription.updatedAt = parsed.updatedAt ?? 0;
    return subscription;
  }

  static async getAll(context: common.Context): Promise<Subscription[]> {
    const raw = await JsonStore.read(context, STORE_SUBSCRIPTIONS);
    if (raw.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as Subscription[];
      return parsed.map((s) => SubscriptionStore.fromJson(s));
    } catch (e) {
      return [];
    }
  }

  static async saveAll(context: common.Context, subscriptions: Subscription[]): Promise<void> {
    await JsonStore.write(context, STORE_SUBSCRIPTIONS, JSON.stringify(subscriptions));
  }

  static async upsert(context: common.Context, subscription: Subscription): Promise<void> {
    subscription.ensureId();
    const all = await SubscriptionStore.getAll(context);
    const index = all.findIndex((s) => s.id === subscription.id);
    if (index >= 0) {
      all[index] = subscription;
    } else {
      all.push(subscription);
    }
    await SubscriptionStore.saveAll(context, all);
  }

  static async remove(context: common.Context, id: string): Promise<void> {
    const all = (await SubscriptionStore.getAll(context)).filter((s) => s.id !== id);
    await SubscriptionStore.saveAll(context, all);
  }
}

/** Shape of one server entry in a SIP008 online config document. */
interface Sip008Server {
  server?: string;
  server_port?: number;
  password?: string;
  method?: string;
  remarks?: string;
}

/** Shape of a SIP008 online config document. */
interface Sip008Document {
  servers?: Sip008Server[];
}

/**
 * Parses a subscription response body into profiles. Two formats are
 * supported, matching what shadowsocks providers serve:
 *
 * - a base64 blob of newline-separated `ss://` URLs (the common case);
 * - a SIP008 JSON online config (`{"servers": [...]}`), as used by `ssd://`.
 */
export function parseSubscriptionBody(body: string, subscriptionId: string): Profile[] {
  const trimmed = body.trim();
  if (trimmed.length === 0) {
    return [];
  }
  let text = trimmed;
  if (!trimmed.startsWith('{') && trimmed.indexOf('ss://') < 0) {
    try {
      text = Profile.decodeBase64(trimmed);
    } catch (e) {
      return [];
    }
  }
  if (text.trim().startsWith('{')) {
    return parseSip008(text, subscriptionId);
  }
  const profiles: Profile[] = [];
  for (const line of text.split(/\r?\n/)) {
    const entry = line.trim();
    if (entry.length === 0) {
      continue;
    }
    const profile = Profile.parseUrl(entry);
    if (profile !== null) {
      profile.subscriptionId = subscriptionId;
      profile.ensureId();
      profiles.push(profile);
    }
  }
  return profiles;
}

function parseSip008(text: string, subscriptionId: string): Profile[] {
  let doc: Sip008Document;
  try {
    doc = JSON.parse(text) as Sip008Document;
  } catch (e) {
    return [];
  }
  const profiles: Profile[] = [];
  for (const server of doc.servers ?? []) {
    if (!server.server || !server.server_port || !server.password || !server.method) {
      continue;
    }
    const profile = new Profile();
    profile.name = server.remarks && server.remarks.length > 0 ? server.remarks : server.server;
    profile.host = server.server;
    profile.remotePort = server.server_port;
    profile.password = server.password;
    profile.method = server.method;
    profile.subscriptionId = subscriptionId;
    profile.ensureId();
    profiles.push(profile);
  }
  return profiles;
}

/**
 * Folds a subscription's freshly-fetched profiles into the stored list, the way
 * shadowsocks-android's `createProfilesFromSubscription` does.
 *
 * A profile is the same profile when its name and its address match, which is
 * why Android warns that names matter: renaming a server in a subscription
 * makes a new profile here and leaves the old one behind as obsolete.
 *
 * The states are what make an update survivable. A profile this subscription
 * listed before and lists again keeps its id, its counters and its place in the
 * list; one it no longer lists becomes obsolete and stays visible, so a server
 * that disappears from a provider and comes back is not lost in between. What
 * a re-listed profile takes from the new copy is its transport — password,
 * method, plugin — and not its route or resolver, which are the user's.
 *
 * A profile that is not this subscription's is left exactly as it is: one the
 * user configured by hand, or one belonging to another subscription.
 */
export function mergeSubscription(existing: Profile[], fresh: Profile[],
  subscriptionId: string): Profile[] {
  const result: Profile[] = [];
  const mine: Profile[] = [];

  for (const profile of existing) {
    const isMine = profile.subscriptionStatus !== STATUS_USER_CONFIGURED &&
      profile.subscriptionId === subscriptionId;
    if (!isMine) {
      // another subscription's, or the user's own: untouched
      result.push(profile);
      continue;
    }
    // duplicates within one subscription: the first one wins, as in Android
    let duplicate = false;
    for (const kept of mine) {
      if (kept.name === profile.name && addressKey(kept) === addressKey(profile)) {
        duplicate = true;
        break;
      }
    }
    if (duplicate) {
      continue;
    }
    // still listed or not is decided below; until then it is obsolete
    if (profile.subscriptionStatus === STATUS_ACTIVE) {
      profile.subscriptionStatus = STATUS_OBSOLETE;
    }
    mine.push(profile);
    result.push(profile);
  }

  for (const incoming of fresh) {
    let matched: Profile | null = null;
    for (const candidate of mine) {
      if (candidate.name === incoming.name && addressKey(candidate) === addressKey(incoming)) {
        matched = candidate;
        break;
      }
    }
    if (matched !== null) {
      if (matched.subscriptionStatus === STATUS_OBSOLETE) {
        matched.password = incoming.password;
        matched.method = incoming.method;
        matched.plugin = incoming.plugin;
        matched.pluginOpts = incoming.pluginOpts;
        matched.subscriptionStatus = STATUS_ACTIVE;
      }
      // an already-active match is a duplicate inside the new list itself, and
      // the copy already kept is left alone
      continue;
    }
    const created = incoming;
    created.subscriptionId = subscriptionId;
    created.subscriptionStatus = STATUS_ACTIVE;
    created.ensureId();
    created.userOrder = nextUserOrder(result);
    result.push(created);
  }

  return result;
}

/**
 * Downloads a subscription URL and parses it into profiles owned by
 * `subscriptionId`. Rejects on network errors or non-2xx responses; an
 * unparseable body yields an empty list.
 */
export async function fetchSubscription(url: string, subscriptionId: string): Promise<Profile[]> {
  const request = http.createHttp();
  try {
    const response = await request.request(url, {
      method: http.RequestMethod.GET,
      connectTimeout: 15000,
      readTimeout: 15000,
    });
    const code = response.responseCode;
    if (code < 200 || code >= 300) {
      throw new Error(`HTTP ${code}`);
    }
    return parseSubscriptionBody(response.result as string, subscriptionId);
  } finally {
    request.destroy();
  }
}

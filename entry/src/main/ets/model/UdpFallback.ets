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
 * The rules of the UDP fallback chooser.
 *
 * The chooser lists the profiles that can serve as a fallback for the edited
 * profile. It writes the user's choice to AppStorage, and the editor takes the
 * choice from there. This module holds the eligibility rule, the display text,
 * the row index, and the handoff codec.
 *
 * This module is pure ArkTS. It imports no kit and does no I/O, so the
 * host-side spec can load it. Only `Profile.ets` is imported.
 */

import { Profile, STATUS_OBSOLETE } from './Profile';

/**
 * The shape of the handoff value. The chooser writes it and the editor reads
 * it. An empty `fallbackId` means Disabled.
 */
interface FallbackChoiceJson {
  profileId?: string;
  fallbackId?: string;
}

/** The stored profile with one id, or null when no profile has the id. */
function findProfileById(profiles: Profile[], id: string): Profile | null {
  for (const profile of profiles) {
    if (profile.id === id) {
      return profile;
    }
  }
  return null;
}

/**
 * The profiles a chooser may offer for the profile under edit.
 *
 * A profile stays when it is not obsolete, is not the edited profile, and has
 * no plugin. The input order is kept, because `ProfileStore.getAll` already
 * sorts by `userOrder`.
 */
export function eligibleFallbacks(profiles: Profile[], editedId: string): Profile[] {
  const eligible: Profile[] = [];
  for (const profile of profiles) {
    if (profile.subscriptionStatus === STATUS_OBSOLETE) {
      continue;
    }
    if (profile.id === editedId) {
      continue;
    }
    if (profile.plugin.length > 0) {
      continue;
    }
    eligible.push(profile);
  }
  return eligible;
}

/**
 * The chooser label of one profile: its name when it has one, else its
 * address. An IPv6 host takes brackets. The two address forms match Android's
 * `formattedAddress`.
 */
export function fallbackDisplayName(profile: Profile): string {
  if (profile.name.length > 0) {
    return profile.name;
  }
  if (profile.host.indexOf(':') >= 0) {
    return `[${profile.host}]:${profile.remotePort}`;
  }
  return `${profile.host}:${profile.remotePort}`;
}

/**
 * The editor's row summary of a fallback id. Returns '' for an empty id and
 * for an id that names no stored profile. A dangling id shows as Disabled and
 * stays in the draft, as Android does.
 */
export function fallbackSummary(profiles: Profile[], fallbackId: string): string {
  if (fallbackId.length === 0) {
    return '';
  }
  const profile = findProfileById(profiles, fallbackId);
  if (profile === null) {
    return '';
  }
  return fallbackDisplayName(profile);
}

/**
 * The chooser list index of a fallback id. Row 0 is the Disabled row, so a
 * stored profile at list index `i` sits at `i + 1`. An id that names no stored
 * profile returns 0.
 */
export function fallbackRowIndex(profiles: Profile[], fallbackId: string): number {
  for (let i = 0; i < profiles.length; i++) {
    if (profiles[i].id === fallbackId) {
      return i + 1;
    }
  }
  return 0;
}

/**
 * The handoff text for one choice. An empty `fallbackId` means Disabled.
 */
export function encodeFallbackChoice(profileId: string, fallbackId: string): string {
  const choice: FallbackChoiceJson = {
    profileId: profileId,
    fallbackId: fallbackId,
  };
  return JSON.stringify(choice);
}

/**
 * The fallback id in a handoff text, or null.
 *
 * Returns null for an empty text, a text that is not JSON, a text for another
 * profile, and a text without a string `fallbackId`. The value '' means
 * Disabled, so the caller must test the result against null.
 */
export function decodeFallbackChoice(profileId: string, raw: string): string | null {
  if (raw.length === 0) {
    return null;
  }
  let parsed: FallbackChoiceJson | null = null;
  try {
    parsed = JSON.parse(raw) as FallbackChoiceJson | null;
  } catch (e) {
    return null;
  }
  if (parsed === null || typeof parsed !== 'object') {
    return null;
  }
  if (parsed.profileId !== profileId) {
    return null;
  }
  if (typeof parsed.fallbackId !== 'string') {
    return null;
  }
  return parsed.fallbackId;
}

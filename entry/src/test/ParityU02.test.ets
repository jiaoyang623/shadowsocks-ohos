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

import { describe, expect, it } from '@ohos/hypium';
import { Profile, STATUS_OBSOLETE } from '../main/ets/model/Profile';
import { ProfileStore } from '../main/ets/model/ProfileStore';
import {
  PHASE_CONNECTED, PHASE_CONNECTING, PHASE_FAILED, PHASE_IDLE, PHASE_LOST, PHASE_PROBE_FAILED,
  PHASE_STOPPING, PHASE_VERIFYING, activeProfileIds, isEnabled, isProfileEditable,
} from '../main/ets/model/Diagnostics';
import { UndoBin } from '../main/ets/model/UndoRemoval';
import { formatTraffic, withLive } from '../main/ets/model/TrafficStats';

/** Every known phase except PHASE_STOPPING. */
const ENABLED_PHASES: string[] = [
  PHASE_IDLE, PHASE_CONNECTING, PHASE_VERIFYING, PHASE_CONNECTED, PHASE_PROBE_FAILED, PHASE_LOST,
  PHASE_FAILED,
];

/** Builds a profile with the fields the row rules read. */
function profile(id: string, name: string, host: string, port: number, order: number): Profile {
  const p = new Profile();
  p.id = id;
  p.name = name;
  p.host = host;
  p.remotePort = port;
  p.userOrder = order;
  return p;
}

/** The ids of a profile list, in list order. */
function ids(profiles: Profile[]): string[] {
  return profiles.map((p: Profile) => p.id);
}

export default function parityU02Test() {
  describe('U02', () => {
    /* ---- list order and visibility ---- */

    it('U02#list-orders-by-user-order', 0, () => {
      const first = profile('1', 'One', 'a.example', 8388, 1);
      const second = profile('2', 'Two', 'b.example', 8388, 2);
      const third = profile('3', 'Three', 'c.example', 8388, 3);
      // The stored array is in the order 2, 1, 3.
      const stored: Profile[] = [second, first, third];

      const ordered = ProfileStore.sorted(stored);
      expect(ids(ordered)).assertEqual(['1', '2', '3']);
      // The input array keeps its order.
      expect(ids(stored)).assertEqual(['2', '1', '3']);
    });

    it('U02#list-hides-obsolete-profiles', 0, () => {
      const user = profile('u', 'User', 'u.example', 8388, 1);
      const obsolete = profile('o', 'Old', 'o.example', 8388, 2);
      obsolete.subscriptionStatus = STATUS_OBSOLETE;

      expect(ids(ProfileStore.visible([user, obsolete]))).assertEqual(['u']);
    });

    it('U02#selection-names-a-visible-profile-only', 0, () => {
      const first = profile('a', 'Alpha', 'a.example', 8388, 1);
      const second = profile('b', 'Beta', 'b.example', 8388, 2);
      const hidden = profile('o', 'Old', 'o.example', 8388, 3);
      hidden.subscriptionStatus = STATUS_OBSOLETE;
      const stored: Profile[] = [first, second, hidden];

      // A valid id takes its own row, not the first one.
      const selected = ProfileStore.currentOf(stored, 'b');
      expect(selected === null).assertFalse();
      if (selected !== null) {
        expect(selected.id).assertEqual('b');
      }

      // No id, a stale id, and an obsolete id select nothing. The first
      // profile is not a substitute, so the start path stops with Please
      // select a profile instead of running an unmarked row (R-UA-27).
      expect(ProfileStore.currentOf(stored, '') === null).assertTrue();
      expect(ProfileStore.currentOf(stored, 'missing') === null).assertTrue();
      expect(ProfileStore.currentOf(stored, 'o') === null).assertTrue();
      expect(ProfileStore.currentOf([], 'a') === null).assertTrue();
    });

    it('U02#removal-selects-a-visible-row', 0, () => {
      const hidden = profile('o', 'Old', 'o.example', 8388, 1);
      hidden.subscriptionStatus = STATUS_OBSOLETE;
      const visible = profile('b', 'Beta', 'b.example', 8388, 2);
      const after: Profile[] = [hidden, visible];

      // The current row went away, so the first visible row takes the mark.
      expect(ProfileStore.currentIdAfterRemove(after, 'removed', 'removed')).assertEqual('b');
      // An obsolete row is never selected, and no row clears the selection.
      expect(ProfileStore.currentIdAfterRemove([hidden], 'removed', 'removed')).assertEqual('');
      expect(ProfileStore.currentIdAfterRemove([], 'removed', 'removed')).assertEqual('');
      // Removing another row keeps the selection.
      expect(ProfileStore.currentIdAfterRemove(after, 'b', 'removed')).assertEqual('b');
    });

    /* ---- row title and secondary line ---- */

    it('U02#title-uses-name-or-host-port', 0, () => {
      const named = profile('a', 'Home', '1.2.3.4', 8388, 1);
      expect(named.displayName()).assertEqual('Home');

      const unnamed = profile('b', '', '1.2.3.4', 8388, 2);
      expect(unnamed.displayName()).assertEqual('1.2.3.4:8388');
    });

    it('U02#secondary-line-uses-address-when-named', 0, () => {
      const named = profile('a', 'Home', '1.2.3.4', 8388, 1);
      expect(named.displaySecondary()).assertEqual('1.2.3.4:8388');
    });

    it('U02#secondary-line-adds-plugin', 0, () => {
      const named = profile('a', 'Home', '1.2.3.4', 8388, 1);
      named.plugin = 'obfs-local';
      expect(named.displaySecondary()).assertEqual('1.2.3.4:8388\nPlugin: obfs-local');

      const unnamed = profile('b', '', '1.2.3.4', 8388, 2);
      unnamed.plugin = 'obfs-local';
      expect(unnamed.displaySecondary()).assertEqual('Plugin: obfs-local');
    });

    it('U02#secondary-line-empty-when-nothing-to-show', 0, () => {
      const unnamed = profile('a', '', '1.2.3.4', 8388, 1);
      expect(unnamed.displaySecondary()).assertEqual('');
    });

    /* ---- traffic line ---- */

    it('U02#traffic-line-empty-at-zero', 0, () => {
      expect(formatTraffic(0, 0)).assertEqual('');
      // A live counter still shows, so the hidden line is not permanent.
      expect(formatTraffic(1024, 2048)).assertEqual('↑ 1.0 KB  ↓ 2.0 KB');
    });

    it('U02#live-counters-only-for-running-profile', 0, () => {
      expect(withLive(100, 10, true)).assertEqual(110);
      expect(withLive(100, 10, false)).assertEqual(100);
    });

    /* ---- search ---- */

    it('U02#search-ignores-case', 0, () => {
      const alpha = profile('a', 'Alpha', 'a.example', 8388, 1);
      expect(ids(ProfileStore.filter([alpha], 'ALP'))).assertEqual(['a']);
    });

    it('U02#search-matches-host', 0, () => {
      const alpha = profile('a', 'Alpha', 'a.example', 8388, 1);
      expect(ids(ProfileStore.filter([alpha], 'example'))).assertEqual(['a']);
    });

    it('U02#search-ignores-port', 0, () => {
      const alpha = profile('a', 'Alpha', 'a.example', 8388, 1);
      expect(ProfileStore.filter([alpha], '8388').length).assertEqual(0);
    });

    it('U02#empty-search-restores-all', 0, () => {
      const all: Profile[] = [
        profile('a', 'Alpha', 'a.example', 1001, 1),
        profile('b', 'Beta', 'b.example', 1002, 2),
        profile('c', 'Gamma', 'c.example', 1003, 3),
      ];
      expect(ids(ProfileStore.filter(all, ''))).assertEqual(['a', 'b', 'c']);
      // White space alone is an empty query.
      expect(ids(ProfileStore.filter(all, '   '))).assertEqual(['a', 'b', 'c']);
    });

    /* ---- row input gates ---- */

    it('U02#row-input-refused-while-stopping', 0, () => {
      expect(isEnabled(PHASE_STOPPING)).assertFalse();
      for (let i = 0; i < ENABLED_PHASES.length; i++) {
        expect(isEnabled(ENABLED_PHASES[i])).assertTrue();
      }
      // An unknown phase stays usable.
      expect(isEnabled('unknown-phase')).assertTrue();
    });

    it('U02#idle-phase-accepts-row-input', 0, () => {
      expect(isEnabled(PHASE_IDLE)).assertTrue();
    });

    it('U02#edit-enabled-when-profile-not-active', 0, () => {
      const a = profile('a', 'A', 'a.example', 8388, 1);
      const b = profile('b', 'B', 'b.example', 8388, 2);
      const activeIds = activeProfileIds([a, b], 'a');
      // Connected locks the active row and leaves the other row editable.
      expect(isProfileEditable(PHASE_CONNECTED, activeIds, 'a')).assertFalse();
      expect(isProfileEditable(PHASE_CONNECTED, activeIds, 'b')).assertTrue();
      // Stopped unlocks both rows.
      expect(isProfileEditable(PHASE_IDLE, activeIds, 'a')).assertTrue();
      expect(isProfileEditable(PHASE_IDLE, activeIds, 'b')).assertTrue();
    });

    it('U02#active-ids-cover-udp-fallback', 0, () => {
      const a = profile('a', 'A', 'a.example', 8388, 1);
      const b = profile('b', 'B', 'b.example', 8388, 2);
      a.udpFallbackId = 'b';
      expect(activeProfileIds([a, b], 'a')).assertEqual(['a', 'b']);

      // A fallback id without a profile is dropped.
      a.udpFallbackId = 'missing';
      expect(activeProfileIds([a, b], 'a')).assertEqual(['a']);

      // An absent selection falls back to the first profile.
      a.udpFallbackId = 'b';
      expect(activeProfileIds([a, b], 'no-such-id')).assertEqual(['a', 'b']);
    });

    /* ---- undo bin ---- */

    it('U02#undo-bin-counts-removals', 0, () => {
      const bin = new UndoBin();
      bin.add('a');
      bin.add('b');
      bin.add('a');
      expect(bin.size()).assertEqual(2);
      expect(bin.ids()).assertEqual(['a', 'b']);
      expect(bin.has('a')).assertTrue();
    });

    it('U02#undo-restores-store-order', 0, () => {
      const stored: Profile[] = [
        profile('a', 'Alpha', 'a.example', 1001, 1),
        profile('b', 'Bravo', 'b.example', 1002, 2),
        profile('c', 'Charlie', 'c.example', 1003, 3),
      ];
      const bin = new UndoBin();
      bin.add('a');
      bin.add('b');

      // The pending ids stay hidden and the store order holds.
      expect(ids(ProfileStore.filter(stored, '', bin.ids()))).assertEqual(['c']);

      // Undo writes no store record, so the original order returns.
      bin.clear();
      expect(ids(ProfileStore.filter(stored, '', bin.ids()))).assertEqual(['a', 'b', 'c']);
      expect(ids(stored)).assertEqual(['a', 'b', 'c']);
    });

    it('U02#commit-clears-the-bin', 0, () => {
      const bin = new UndoBin();
      bin.add('a');
      const copy = bin.ids();
      bin.clear();
      expect(copy).assertEqual(['a']);
      expect(bin.size()).assertEqual(0);
      expect(bin.ids()).assertEqual([]);
      expect(bin.has('a')).assertFalse();
    });

    it('U02#pending-removal-stays-hidden-under-search', 0, () => {
      const alpha = profile('a', 'Alpha', 'a.example', 8388, 1);
      const beta = profile('b', 'Beta', 'b.example', 8388, 2);
      const bin = new UndoBin();
      bin.add('a');

      // The pending profile matches the query but keeps its row hidden.
      expect(ProfileStore.filter([alpha, beta], 'alp', bin.ids()).length).assertEqual(0);
      expect(ids(ProfileStore.filter([alpha, beta], '', bin.ids()))).assertEqual(['b']);
    });

    /* ---- scroll to selection ---- */

    it('U02#selected-index-found-for-scroll', 0, () => {
      const shown: Profile[] = [
        profile('a', 'Alpha', 'a.example', 1001, 1),
        profile('b', 'Beta', 'b.example', 1002, 2),
        profile('c', 'Gamma', 'c.example', 1003, 3),
      ];
      expect(ProfileStore.indexOf(shown, 'b')).assertEqual(1);
      expect(ProfileStore.indexOf(shown, 'missing')).assertEqual(-1);
    });
  });
}

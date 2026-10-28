import { describe, expect, it } from '@ohos/hypium';
import {
  NotificationText, TrafficSample, TrafficUpdate, notificationText, notificationTitle,
  trafficUpdate,
} from '../main/ets/model/NotificationContent';

/** A sample that says no previous counters exist. */
const NO_SAMPLE: TrafficSample = { tx: -1, rx: -1, at: 0 };

export default function parityU11Test() {
  describe('ParityU11Test', () => {
    it('U11#title-uses-the-profile-name', 0, () => {
      expect(notificationTitle('Tokyo', 'Shadowsocks')).assertEqual('Tokyo');
    });

    it('U11#title-falls-back-to-the-app-name', 0, () => {
      expect(notificationTitle('', 'Shadowsocks')).assertEqual('Shadowsocks');
    });

    it('U11#starting-notification-uses-the-app-name', 0, () => {
      const content: NotificationText =
        notificationText('', 'Shadowsocks', 'Connecting…', '', '');
      expect(content.title).assertEqual('Shadowsocks');
      expect(content.text).assertEqual('Connecting…');
      expect(content.totals).assertEqual('');
    });

    it('U11#text-shows-rates-and-totals', 0, () => {
      const content: NotificationText = notificationText('Tokyo', 'Shadowsocks', 'Connected',
        '12 KB/s up, 34 KB/s down', '1.2 MB up, 3.4 MB down');
      expect(content.title).assertEqual('Tokyo');
      expect(content.text).assertEqual('12 KB/s up, 34 KB/s down');
      expect(content.totals).assertEqual('1.2 MB up, 3.4 MB down');
    });

    it('U11#text-falls-back-before-a-sample', 0, () => {
      const content: NotificationText =
        notificationText('Tokyo', 'Shadowsocks', 'Connected', '', '');
      expect(content.title).assertEqual('Tokyo');
      // The rates are empty, so the fallback label takes the text line.
      expect(content.text).assertEqual('Connected');
    });

    it('U11#body-is-never-empty', 0, () => {
      const content: NotificationText = notificationText('', 'Shadowsocks', '', '', '');
      expect(content.title.length > 0).assertTrue();
      expect(content.text.length > 0).assertTrue();
      expect(content.title).assertEqual('Shadowsocks');
      expect(content.text).assertEqual('Shadowsocks');
    });

    it('U11#first-sample-is-a-baseline', 0, () => {
      const update: TrafficUpdate = trafficUpdate(NO_SAMPLE, 1000, 2000, 5000, true);
      expect(update.sample).assertEqual({ tx: 1000, rx: 2000, at: 5000 });
      expect(update.rates).assertEqual({ up: 0, down: 0 });
      expect(update.publish).assertFalse();
    });

    it('U11#second-sample-computes-both-rates', 0, () => {
      const previous: TrafficSample = { tx: 1000, rx: 2000, at: 3000 };
      const update: TrafficUpdate = trafficUpdate(previous, 4000, 3000, 5000, true);
      expect(update.sample).assertEqual({ tx: 4000, rx: 3000, at: 5000 });
      // 3000 bytes up over 2000 ms is 1500 B/s. 1000 bytes down is 500 B/s.
      expect(update.rates).assertEqual({ up: 1500, down: 500 });
      expect(update.publish).assertTrue();
    });

    it('U11#zero-elapsed-time-yields-no-rate', 0, () => {
      const previous: TrafficSample = { tx: 1000, rx: 2000, at: 5000 };
      const update: TrafficUpdate = trafficUpdate(previous, 2000, 3000, 5000, true);
      expect(update.sample).assertEqual({ tx: 2000, rx: 3000, at: 5000 });
      expect(update.rates).assertEqual({ up: 0, down: 0 });
      expect(update.publish).assertFalse();
    });

    it('U11#counters-going-backwards-yield-zero', 0, () => {
      const previous: TrafficSample = { tx: 5000, rx: 4000, at: 1000 };
      const update: TrafficUpdate = trafficUpdate(previous, 4000, 3000, 2000, true);
      // A reset counter gives a lower total. The rates stay at zero and the
      // update still publishes, so the notification shows the new totals.
      expect(update.sample).assertEqual({ tx: 4000, rx: 3000, at: 2000 });
      expect(update.rates).assertEqual({ up: 0, down: 0 });
      expect(update.publish).assertTrue();
    });

    it('U11#screen-off-clears-the-rate-baseline', 0, () => {
      const previous: TrafficSample = { tx: 1000, rx: 2000, at: 1000 };
      const update: TrafficUpdate = trafficUpdate(previous, 6000, 8000, 2000, false);
      expect(update.sample).assertEqual({ tx: -1, rx: -1, at: 0 });
      expect(update.rates).assertEqual({ up: 0, down: 0 });
      expect(update.publish).assertFalse();
    });

    it('U11#screen-on-after-off-needs-a-fresh-baseline', 0, () => {
      const before: TrafficSample = { tx: 1000, rx: 2000, at: 1000 };
      const off: TrafficUpdate = trafficUpdate(before, 6000, 8000, 2000, false);
      expect(off.publish).assertFalse();
      // The first update after the screen turns on is a baseline again.
      const first: TrafficUpdate = trafficUpdate(off.sample, 100, 200, 3000, true);
      expect(first.sample).assertEqual({ tx: 100, rx: 200, at: 3000 });
      expect(first.rates).assertEqual({ up: 0, down: 0 });
      expect(first.publish).assertFalse();
      // The next update has an elapsed time and publishes the rates.
      const second: TrafficUpdate = trafficUpdate(first.sample, 600, 1200, 4000, true);
      expect(second.sample).assertEqual({ tx: 600, rx: 1200, at: 4000 });
      expect(second.rates).assertEqual({ up: 500, down: 1000 });
      expect(second.publish).assertTrue();
    });
  });
}

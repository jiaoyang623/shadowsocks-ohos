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
 * Notification content and traffic rates for the connection notification.
 *
 * The functions are pure. The notification publisher and the VPN extension call
 * them, and the host specs check them without a device.
 */

/** Cumulative traffic counters and the time of the sample. */
export interface TrafficSample {
  /** Bytes sent through the tunnel. */
  tx: number;
  /** Bytes received through the tunnel. */
  rx: number;
  /** Time of the sample, in milliseconds. */
  at: number;
}

/** Traffic rates in bytes per second. */
export interface TrafficRates {
  up: number;
  down: number;
}

/** One traffic update: the new sample, the rates, and whether to publish. */
export interface TrafficUpdate {
  sample: TrafficSample;
  rates: TrafficRates;
  publish: boolean;
}

/** The three text fields of the notification. */
export interface NotificationText {
  title: string;
  text: string;
  totals: string;
}

/** Title for the notification: the profile name, or the app name. */
export function notificationTitle(profileName: string, appName: string): string {
  return profileName.length > 0 ? profileName : appName;
}

/**
 * The three text fields of the notification.
 *
 * The rates take the text line when they exist. Before the first rate, the
 * fallback label takes the text line. The app name is the last resort. The
 * platform rejects an empty title and an empty text, so the app name is always
 * a valid value.
 */
export function notificationText(profileName: string, appName: string, fallbackText: string,
                                 rates: string, totals: string): NotificationText {
  const text = rates.length > 0
    ? rates
    : (fallbackText.length > 0 ? fallbackText : appName);
  const result: NotificationText = {
    title: notificationTitle(profileName, appName),
    text: text,
    totals: totals,
  };
  return result;
}

/**
 * The next traffic update from a counter sample.
 *
 * A screen that is off clears the baseline. A missing or unusable previous
 * sample becomes the new baseline. Both cases publish nothing, because the
 * first sample describes a baseline rather than a rate.
 *
 * The rates never go below zero. A counter can reset, and a negative rate has
 * no meaning.
 */
export function trafficUpdate(previous: TrafficSample, tx: number, rx: number, now: number,
                              screenActive: boolean): TrafficUpdate {
  if (!screenActive) {
    const cleared: TrafficUpdate = {
      sample: { tx: -1, rx: -1, at: 0 },
      rates: { up: 0, down: 0 },
      publish: false,
    };
    return cleared;
  }
  const sample: TrafficSample = { tx: tx, rx: rx, at: now };
  if (previous.tx < 0 || previous.rx < 0 || previous.at <= 0 || now <= previous.at) {
    const baseline: TrafficUpdate = {
      sample: sample,
      rates: { up: 0, down: 0 },
      publish: false,
    };
    return baseline;
  }
  const elapsed = now - previous.at;
  const up = Math.max(0, (tx - previous.tx) * 1000 / elapsed);
  const down = Math.max(0, (rx - previous.rx) * 1000 / elapsed);
  const update: TrafficUpdate = {
    sample: sample,
    rates: { up: up, down: down },
    publish: true,
  };
  return update;
}

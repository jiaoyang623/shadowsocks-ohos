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

import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { http } from '@kit.NetworkKit';
import { Profile } from './Profile';
import { ProfileStore } from './ProfileStore';
import {
  Subscription, SubscriptionFetchControl, SubscriptionStore, fetchSubscriptionBody,
  mergeSubscriptionRun, parseSubscriptionBody,
} from './Subscription';
import { ensureEnabled } from './ConnectionNotification';

const TAG = 'SubscriptionRefresh';

/** The event the notification's Stop button sends. */
export const SUBSCRIPTION_ABORT_EVENT = 'com.xbt.project.subscription.abort';

/** Fixed, so that publishing again replaces what is there. */
export const SUBSCRIPTION_NOTIFICATION_ID = 2;

/** One subscription as the run snapshots it. */
export interface SubscriptionUrlRef {
  id: string;
  url: string;
}

/** The result of one download. `error` is '' when the download succeeded. */
export interface SubscriptionFetchOutcome {
  id: string;
  body: string;
  error: string;
}

/** How much of the run is done. */
export interface SubscriptionRefreshProgress {
  done: number;
  total: number;
  finishing: boolean;
}

export type SubscriptionRefreshErrorKind = 'fetch' | 'parse' | 'store';

/** One failure the page reports with a long toast. */
export interface SubscriptionRefreshError {
  kind: SubscriptionRefreshErrorKind;
  message: string;
}

export interface SubscriptionRefreshCallbacks {
  onProgress: (progress: SubscriptionRefreshProgress) => void;
  onError: (error: SubscriptionRefreshError) => void;
}

/** The message of a thrown value, or a plain fallback. */
function errorMessage(error: Object): string {
  const err = error as Error;
  return typeof err.message === 'string' && err.message.length > 0 ? err.message : 'error';
}

/**
 * The state of one refresh run. It reads the subscription list once, at
 * construction, so a page change in the middle of a run cannot alter what the
 * run fetches.
 *
 * This class makes no native call. The host spec loads it on its own.
 */
export class SubscriptionRefreshRun {
  readonly urls: SubscriptionUrlRef[];
  readonly outcomes: SubscriptionFetchOutcome[];
  done: number = 0;
  finishing: boolean = false;
  cancelled: boolean = false;
  merging: boolean = false;

  constructor(subscriptions: Subscription[]) {
    this.urls = [];
    for (const subscription of subscriptions) {
      this.urls.push({ id: subscription.id, url: subscription.url });
    }
    this.outcomes = [];
  }

  /** Records one settled download. Extra calls beyond the URL count are ignored. */
  recordFetch(outcome: SubscriptionFetchOutcome): void {
    if (this.done >= this.urls.length) {
      return;
    }
    this.outcomes.push(outcome);
    this.done++;
  }

  markFinishing(): void {
    this.finishing = true;
  }

  requestCancel(): void {
    this.cancelled = true;
  }

  /**
   * Opens the merge window. A cancel before this call stops the write. A
   * cancel after it does not.
   */
  beginMerge(): boolean {
    this.merging = !this.cancelled;
    return this.merging;
  }

  /** True when the merge may write the profile list. */
  shouldCommit(): boolean {
    return this.merging;
  }

  /** The ids whose download succeeded. */
  succeededIds(): string[] {
    const ids: string[] = [];
    for (const outcome of this.outcomes) {
      if (outcome.error.length === 0) {
        ids.push(outcome.id);
      }
    }
    return ids;
  }

  /** How many downloads failed. */
  failureCount(): number {
    let count = 0;
    for (const outcome of this.outcomes) {
      if (outcome.error.length > 0) {
        count++;
      }
    }
    return count;
  }
}

/**
 * One refresh of every subscription URL, in the UI process.
 *
 * HarmonyOS has no Android service, so the run lives here, and a second start
 * is ignored rather than queued. A process death ends the run. The Stop
 * button sends a common event, and the run listens for it only while it is
 * active.
 */
/**
 * The fetch control of one run. A class rather than an object literal, because
 * ArkTS accepts an object literal only when a class or interface type is
 * directly visible at the literal.
 */
class RefreshFetchControl implements SubscriptionFetchControl {
  private readonly requests: http.HttpRequest[];
  private readonly run: SubscriptionRefreshRun;

  constructor(requests: http.HttpRequest[], run: SubscriptionRefreshRun) {
    this.requests = requests;
    this.run = run;
  }

  register(request: http.HttpRequest): void {
    this.requests.push(request);
  }

  unregister(request: http.HttpRequest): void {
    const index = this.requests.indexOf(request);
    if (index >= 0) {
      this.requests.splice(index, 1);
    }
  }

  isCancelled(): boolean {
    return this.run.cancelled;
  }
}

export class SubscriptionRefresh {
  private static run: SubscriptionRefreshRun | undefined = undefined;
  private static requests: http.HttpRequest[] = [];
  private static subscriber: commonEventManager.CommonEventSubscriber | undefined = undefined;

  /** True while a run exists, including its cleanup. */
  static isRunning(): boolean {
    return SubscriptionRefresh.run !== undefined;
  }

  /**
   * Starts one run. A second call while a run exists returns at once. The run
   * is set before the first await, so a page that asks `isRunning` right after
   * the call sees it.
   */
  static async start(context: common.UIAbilityContext, subscriptions: Subscription[],
    callbacks: SubscriptionRefreshCallbacks): Promise<void> {
    if (SubscriptionRefresh.run !== undefined) {
      return;
    }
    const run = new SubscriptionRefreshRun(subscriptions);
    SubscriptionRefresh.run = run;
    try {
      await SubscriptionRefresh.subscribeAbort();
      await ensureEnabled(context);
      await SubscriptionRefresh.publishProgress(context, run);
      const tasks: Promise<void>[] = [];
      for (const ref of run.urls) {
        tasks.push(SubscriptionRefresh.fetchOne(context, run, ref, callbacks));
      }
      await Promise.all(tasks);
      run.markFinishing();
      await SubscriptionRefresh.publishProgress(context, run);
      if (run.beginMerge()) {
        await SubscriptionRefresh.mergeRun(context, run, callbacks);
      }
    } finally {
      await SubscriptionRefresh.cleanup();
    }
  }

  /**
   * Stops the downloads. A profile write that has already started continues,
   * and `shouldCommit` reports that state.
   */
  static cancel(): void {
    const run = SubscriptionRefresh.run;
    if (run === undefined) {
      return;
    }
    run.requestCancel();
    const pending = SubscriptionRefresh.requests.slice();
    for (const request of pending) {
      try {
        request.destroy();
      } catch (e) {
        hilog.warn(0x0000, TAG, 'could not cancel a subscription request: %{public}s',
          errorMessage(e as Object));
      }
    }
  }

  /** Publishes the current count, or the finishing title. */
  private static async publishProgress(context: common.UIAbilityContext,
    run: SubscriptionRefreshRun): Promise<void> {
    try {
      const strings = context.resourceManager;
      const total = run.urls.length;
      const title = run.finishing
        ? strings.getStringSync($r('app.string.subscription_finishing').id)
        : strings.getStringSync($r('app.string.subscription_syncing_n').id, run.done, total);
      const request: notificationManager.NotificationRequest = {
        id: SUBSCRIPTION_NOTIFICATION_ID,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: strings.getStringSync($r('app.string.subscription_service').id),
          },
        },
        isOngoing: true,
        actionButtons: [{
          title: strings.getStringSync($r('app.string.subscription_stop').id),
          wantAgent: await SubscriptionRefresh.stopAgent(),
        }],
      };
      await notificationManager.publish(request);
    } catch (e) {
      // a refused notification permission does not stop the run
      hilog.warn(0x0000, TAG, 'could not publish the refresh notification: %{public}s',
        errorMessage(e as Object));
    }
  }

  /** Subscribes to the Stop event for the life of the run. */
  private static async subscribeAbort(): Promise<void> {
    if (SubscriptionRefresh.subscriber !== undefined) {
      return;
    }
    try {
      const subscriber = await commonEventManager.createSubscriber({
        events: [SUBSCRIPTION_ABORT_EVENT],
      });
      SubscriptionRefresh.subscriber = subscriber;
      commonEventManager.subscribe(subscriber, (err: BusinessError) => {
        SubscriptionRefresh.cancel();
      });
    } catch (e) {
      hilog.warn(0x0000, TAG, 'could not subscribe to the abort event: %{public}s',
        errorMessage(e as Object));
    }
  }

  /** Drops the Stop subscription, if there is one. */
  private static async unsubscribeAbort(): Promise<void> {
    const subscriber = SubscriptionRefresh.subscriber;
    if (subscriber === undefined) {
      return;
    }
    SubscriptionRefresh.subscriber = undefined;
    try {
      commonEventManager.unsubscribe(subscriber);
    } catch (e) {
      hilog.warn(0x0000, TAG, 'could not unsubscribe from the abort event: %{public}s',
        errorMessage(e as Object));
    }
  }

  /** The Stop button's action. */
  private static async stopAgent(): Promise<WantAgent> {
    return await wantAgent.getWantAgent({
      wants: [{ action: SUBSCRIPTION_ABORT_EVENT }],
      actionType: wantAgent.OperationType.SEND_COMMON_EVENT,
      requestCode: 0,
    });
  }

  /** Fetches one URL and records its outcome. The promise never rejects. */
  private static async fetchOne(context: common.UIAbilityContext,
    run: SubscriptionRefreshRun, ref: SubscriptionUrlRef,
    callbacks: SubscriptionRefreshCallbacks): Promise<void> {
    const control: SubscriptionFetchControl =
      new RefreshFetchControl(SubscriptionRefresh.requests, run);
    try {
      const body = await fetchSubscriptionBody(ref.url, control);
      run.recordFetch({ id: ref.id, body: body, error: '' });
    } catch (e) {
      const message = errorMessage(e as Object);
      run.recordFetch({ id: ref.id, body: '', error: message });
      if (!run.cancelled) {
        callbacks.onError({ kind: 'fetch', message: message });
      }
    } finally {
      await SubscriptionRefresh.publishProgress(context, run);
      callbacks.onProgress({
        done: run.done,
        total: run.urls.length,
        finishing: run.finishing,
      });
    }
  }

  /**
   * Parses every successful body and merges the result into the stored list
   * in one write. A parse error skips that body. A store error leaves the old
   * file in place, because `JsonStore` writes a temporary file and renames it.
   *
   * The order of the steps is deliberate. Every download has settled, and the
   * selection that supplies feature defaults is read, before any parsing. The
   * list the merge writes back is read after all parsing, and that read is the
   * last await before the merge and the write. `JsonStore.write` does its file
   * I/O synchronously inside an async function, so on the single-threaded page
   * process a profile save, delete, reorder or Apply Settings write cannot
   * land between the read and the write. A merge snapshot taken before the
   * parsing would overwrite such a write, and a refresh runs for seconds.
   */
  private static async mergeRun(context: common.UIAbilityContext,
    run: SubscriptionRefreshRun, callbacks: SubscriptionRefreshCallbacks): Promise<void> {
    try {
      const fresh: Profile[] = [];
      const updatedIds: string[] = [];
      // The selection supplies feature settings to the fresh profiles only.
      // A stale selection gives null, and the defaults apply.
      const feature = await ProfileStore.getCurrent(context);
      for (const outcome of run.outcomes) {
        if (outcome.error.length > 0) {
          continue;
        }
        try {
          const profiles = parseSubscriptionBody(outcome.body, outcome.id, feature);
          for (const profile of profiles) {
            fresh.push(profile);
          }
          if (profiles.length > 0) {
            updatedIds.push(outcome.id);
          }
        } catch (e) {
          callbacks.onError({ kind: 'parse', message: errorMessage(e as Object) });
        }
      }
      // Read the selection first, so the store read below is the last await
      // before the write.
      const currentId = await ProfileStore.getCurrentId(context);
      // A corrupt profiles.json reads as an empty list through getAll, and a
      // merge would then write back only the fresh subscription profiles: the
      // user's other profiles would be gone. The refresh stops instead, and
      // the old file stays in place.
      const existing = await ProfileStore.getAllOrNull(context);
      if (existing === null) {
        callbacks.onError({
          kind: 'store',
          message: 'The profile store is unreadable. The refresh changed nothing.',
        });
        return;
      }
      const merged = mergeSubscriptionRun(existing, fresh, currentId);
      await ProfileStore.saveAll(context, merged.profiles);
      if (merged.currentId !== currentId) {
        await ProfileStore.setCurrentId(context, merged.currentId);
      }
      // The update times follow the same rule: a subscription store that
      // cannot be read is left alone instead of being replaced with an empty
      // list. The read and the write have no await between them.
      const subscriptions = await SubscriptionStore.getAllOrNull(context);
      if (subscriptions === null) {
        callbacks.onError({
          kind: 'store',
          message: 'The subscription store is unreadable. The update times were not saved.',
        });
        return;
      }
      const now = Date.now();
      for (const subscription of subscriptions) {
        if (updatedIds.indexOf(subscription.id) >= 0) {
          subscription.updatedAt = now;
        }
      }
      await SubscriptionStore.saveAll(context, subscriptions);
    } catch (e) {
      callbacks.onError({ kind: 'store', message: errorMessage(e as Object) });
    }
  }

  /** Removes the notification, drops the subscription and clears the run. */
  private static async cleanup(): Promise<void> {
    try {
      await notificationManager.cancel(SUBSCRIPTION_NOTIFICATION_ID);
    } catch (e) {
      hilog.warn(0x0000, TAG, 'could not cancel the refresh notification: %{public}s',
        errorMessage(e as Object));
    }
    await SubscriptionRefresh.unsubscribeAbort();
    SubscriptionRefresh.requests = [];
    SubscriptionRefresh.run = undefined;
  }
}

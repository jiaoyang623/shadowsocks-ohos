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

import { bundleManager } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { ProfileStore } from '../model/ProfileStore';
import { abilityContext } from '../model/AppContext';
import {
  addSubscriptionUrl,
  editResult,
  findSubscriptionByUrl,
  replaceSubscriptionUrl,
  restoreSubscriptions,
  Subscription,
  SubscriptionDialogButton,
  SubscriptionEditResult,
  SubscriptionListChange,
  SubscriptionStore,
  SubscriptionUrlCheck,
  validateSubscriptionUrl,
} from '../model/Subscription';
import {
  SubscriptionRefresh,
  SubscriptionRefreshCallbacks,
  SubscriptionRefreshError,
  SubscriptionRefreshProgress,
} from '../model/SubscriptionRefresh';

/** How long a removed URL can be put back. */
const UNDO_WINDOW_MS = 5000;

/** How long a refresh error stays on the screen. */
const LONG_TOAST_MS = 10000;

/** The message of a thrown value, or its text when it is not an Error. */
function errorText(error: Object): string {
  const err = error as Error;
  return typeof err.message === 'string' && err.message.length > 0 ? err.message : String(error);
}

/** Reports a failed subscription write, which leaves the stored list unchanged. */
function reportSaveFailed(error: Object): void {
  promptAction.showToast({
    message: $r('app.string.subscription_update_failed', errorText(error)),
    duration: LONG_TOAST_MS,
  });
}

/**
 * Reports a stored list that is present and cannot be read. A write built on
 * the empty read would replace every stored URL, so the caller stops.
 */
function reportStoreUnreadable(): void {
  reportSaveFailed(new Error('The stored subscriptions cannot be read. Nothing was changed.'));
}

/**
 * Subscription management: a sorted list of subscription URLs, mirroring
 * shadowsocks-android's subscription settings. One dialog adds and edits a
 * URL. A swipe removes a URL with an undo bar. One button refreshes every URL
 * in a single run.
 */
@Entry
@Component
struct SubscriptionPage {
  @State subscriptions: Subscription[] = [];
  @State profileCounts: Map<string, number> = new Map();
  @State refreshRunning: boolean = false;
  @State removed: Subscription[] = [];
  @State undoVisible: boolean = false;

  private undoTimer: number = -1;
  private listScroller: Scroller = new Scroller();
  private dialog: CustomDialogController | null = null;

  aboutToAppear(): void {
    this.reload();
    this.refreshRunning = SubscriptionRefresh.isRunning();
  }

  aboutToDisappear(): void {
    this.hideUndo();
    // The page leaves a running refresh alone. The run cleans up in its own
    // finally block.
  }

  private async reload(): Promise<void> {
    const context = abilityContext();
    this.subscriptions = await SubscriptionStore.getAll(context);
    const profiles = await ProfileStore.getAll(context);
    const counts = new Map<string, number>();
    for (const profile of profiles) {
      if (profile.subscriptionId.length > 0) {
        counts.set(profile.subscriptionId, (counts.get(profile.subscriptionId) ?? 0) + 1);
      }
    }
    this.profileCounts = counts;
  }

  private openAdd(): void {
    this.openDialog('', false);
  }

  private openEdit(subscription: Subscription): void {
    this.openDialog(subscription.url, true);
  }

  private openDialog(initialUrl: string, editing: boolean): void {
    if (this.dialog !== null) {
      this.dialog.close();
    }
    const controller: CustomDialogController = new CustomDialogController({
      builder: EditSubscriptionDialog({
        initialUrl: initialUrl,
        editing: editing,
        onResult: (button: SubscriptionDialogButton, text: string): void => {
          this.applyResult(button, text, initialUrl);
        },
      }),
      autoCancel: true,
    });
    this.dialog = controller;
    controller.open();
  }

  /**
   * Applies one dialog answer. Cancel changes nothing. Remove drops the URL
   * and offers it back. OK adds or replaces a URL, and never makes a duplicate.
   */
  private async applyResult(button: SubscriptionDialogButton, text: string,
    original: string): Promise<void> {
    const result: SubscriptionEditResult | null = editResult(button, text, original);
    if (result === null) {
      return;
    }
    const context = abilityContext();
    const list: Subscription[] | null = await SubscriptionStore.getAllOrNull(context);
    if (list === null) {
      reportStoreUnreadable();
      return;
    }
    const old: Subscription | null = result.replacing === null
      ? null : findSubscriptionByUrl(list, result.replacing);
    let next: Subscription[] = list;
    if (result.replacing !== null && result.edited === null) {
      if (old !== null) {
        const removedId: string = old.id;
        next = list.filter((s: Subscription) => s.id !== removedId);
        this.removed = this.removed.concat([old]);
        this.showUndo();
      }
    } else if (result.edited !== null) {
      const url: string = result.edited.trim();
      const record: Subscription = new Subscription();
      record.id = old === null ? '' : old.id;
      record.updatedAt = old === null ? 0 : old.updatedAt;
      record.url = url;
      record.ensureId();
      if (result.replacing === null) {
        const change: SubscriptionListChange = addSubscriptionUrl(list, record);
        if (!change.changed) {
          return;
        }
        next = change.list;
      } else {
        next = replaceSubscriptionUrl(list, result.replacing, record);
      }
    }
    try {
      await SubscriptionStore.saveAll(context, next);
    } catch (e) {
      reportSaveFailed(e as Object);
      return;
    }
    await this.reload();
    if (result.edited !== null) {
      this.scrollToUrl(result.edited.trim());
    } else if (result.replacing !== null) {
      this.scrollToUrl(result.replacing);
    }
  }

  private async remove(subscription: Subscription): Promise<void> {
    const context = abilityContext();
    const list: Subscription[] | null = await SubscriptionStore.getAllOrNull(context);
    if (list === null) {
      reportStoreUnreadable();
      return;
    }
    const next: Subscription[] = list.filter((s: Subscription) => s.id !== subscription.id);
    try {
      await SubscriptionStore.saveAll(context, next);
    } catch (e) {
      reportSaveFailed(e as Object);
      return;
    }
    this.removed = this.removed.concat([subscription]);
    this.showUndo();
    await this.reload();
  }

  private showUndo(): void {
    this.undoVisible = true;
    if (this.undoTimer !== -1) {
      clearTimeout(this.undoTimer);
      this.undoTimer = -1;
    }
    this.undoTimer = setTimeout(() => {
      this.hideUndo();
    }, UNDO_WINDOW_MS);
  }

  private hideUndo(): void {
    if (this.undoTimer !== -1) {
      clearTimeout(this.undoTimer);
      this.undoTimer = -1;
    }
    this.undoVisible = false;
    this.removed = [];
  }

  private async undo(): Promise<void> {
    const context = abilityContext();
    const list: Subscription[] | null = await SubscriptionStore.getAllOrNull(context);
    if (list === null) {
      // The bar stays up, so the user can try the undo again.
      reportStoreUnreadable();
      return;
    }
    const next: Subscription[] = restoreSubscriptions(list, this.removed);
    try {
      await SubscriptionStore.saveAll(context, next);
    } catch (e) {
      // The bar stays up, so the user can try the undo again.
      reportSaveFailed(e as Object);
      return;
    }
    this.hideUndo();
    await this.reload();
  }

  /**
   * Refreshes every stored URL in one run. A second tap while a run exists is
   * ignored. The run reports its count in the notification.
   */
  private async refreshAll(): Promise<void> {
    if (this.refreshRunning) {
      return;
    }
    this.refreshRunning = true;
    const callbacks: SubscriptionRefreshCallbacks = {
      onProgress: (progress: SubscriptionRefreshProgress): void => {
        // The notification carries the count. The page shows no progress text.
      },
      onError: (error: SubscriptionRefreshError): void => {
        let message: ResourceStr;
        if (error.kind === 'fetch') {
          message = $r('app.string.subscription_update_failed', error.message);
        } else if (error.kind === 'parse') {
          message = $r('app.string.subscription_parse_failed', error.message);
        } else {
          message = $r('app.string.common_save_failed', error.message);
        }
        promptAction.showToast({ message: message, duration: LONG_TOAST_MS });
      },
    };
    try {
      await SubscriptionRefresh.start(abilityContext(), this.subscriptions, callbacks);
    } finally {
      this.refreshRunning = false;
      await this.reload();
    }
  }

  private scrollToUrl(url: string): void {
    const record: Subscription | null = findSubscriptionByUrl(this.subscriptions, url);
    if (record === null) {
      return;
    }
    const id: string = record.id;
    const index: number = this.subscriptions.findIndex((s: Subscription) => s.id === id);
    if (index >= 0) {
      this.listScroller.scrollToIndex(index);
    }
  }

  @Builder
  DeleteAction() {
    Row() {
      Text($r('app.string.subscription_remove'))
        .fontSize(14)
        .fontColor($r('app.color.on_container'))
        .backgroundColor($r('app.color.error_container'))
        .padding({ left: 20, right: 20, top: 12, bottom: 12 })
        .borderRadius(8)
    }
  }

  build() {
    Column() {
      Row() {
        Text($r('app.string.common_back'))
          .fontSize(16)
          .fontColor($r('app.color.accent'))
          .onClick(() => router.back())
        Text($r('app.string.index_subscriptions'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text(' ')
      }
      .width('100%')
      .padding(16)

      Row({ space: 8 }) {
        Button($r('app.string.subscription_add_subscription'))
          .fontSize(14)
          .layoutWeight(1)
          .backgroundColor($r('app.color.accent_container'))
          .fontColor($r('app.color.on_container'))
          .onClick(() => this.openAdd())
        Button($r('app.string.subscription_refresh'))
          .fontSize(14)
          .layoutWeight(1)
          .backgroundColor($r('app.color.accent_container'))
          .fontColor($r('app.color.on_container'))
          .enabled(!this.refreshRunning)
          .onClick(() => this.refreshAll())
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      if (this.subscriptions.length === 0) {
        Text($r('app.string.subscription_no_subscriptions'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 32 })
      }

      List({ space: 8, scroller: this.listScroller }) {
        ForEach(this.subscriptions, (subscription: Subscription) => {
          ListItem() {
            Column({ space: 6 }) {
              Text(subscription.url)
                .fontSize(14)
                .fontColor($r('app.color.text_body'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Row() {
                Text(subscription.updatedAt > 0
                  ? $r('app.string.subscription_profiles_updated',
                    this.profileCounts.get(subscription.id) ?? 0,
                    new Date(subscription.updatedAt).toLocaleDateString())
                  : $r('app.string.subscription_never_updated'))
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .layoutWeight(1)
              }
              .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(12)
            .borderRadius(8)
            .backgroundColor($r('app.color.surface'))
          }
          .swipeAction({
            start: {
              builder: () => {
                this.DeleteAction();
              },
              onAction: () => {
                this.remove(subscription);
              },
            },
          })
          .onClick(() => this.openEdit(subscription))
        }, (subscription: Subscription) => subscription.id + '\n' + subscription.url + '\n'
          + subscription.updatedAt + '\n' + (this.profileCounts.get(subscription.id) ?? 0))
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16 })
      .scrollBar(BarState.Auto)

      if (this.undoVisible) {
        Row({ space: 12 }) {
          Text(this.removed.length === 1
            ? $r('app.string.subscription_removed')
            : $r('app.string.subscription_removed_n', this.removed.length))
            .fontSize(14)
            .fontColor($r('app.color.text_body'))
            .layoutWeight(1)
          Button($r('app.string.subscription_undo'))
            .backgroundColor($r('app.color.accent_container'))
            .fontColor($r('app.color.on_container'))
            .onClick(() => this.undo())
        }
        .width('100%')
        .padding(12)
        .margin({ left: 16, right: 16, top: 8, bottom: 16 })
        .borderRadius(8)
        .backgroundColor($r('app.color.surface'))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}

/**
 * One dialog for add and edit. The dialog checks the URL on every change. OK
 * stays disabled until the text passes. Remove is absent for an add, because
 * there is no stored URL to remove.
 */
@CustomDialog
struct EditSubscriptionDialog {
  controller: CustomDialogController;
  initialUrl: string = '';
  editing: boolean = false;
  onResult: (button: SubscriptionDialogButton, text: string) => void = () => {
  };

  @State url: string = '';
  @State valid: boolean = false;
  @State error: ResourceStr = '';
  @State warning: ResourceStr = '';

  aboutToAppear(): void {
    this.url = this.initialUrl;
    this.validate(this.url);
  }

  private validate(text: string): void {
    const check: SubscriptionUrlCheck =
      validateSubscriptionUrl(text, (link: string): boolean => this.canOpen(link));
    this.valid = check.valid;
    this.warning = check.cleartext ? $r('app.string.subscription_cleartext_warning') : '';
    if (check.error === 'no_protocol') {
      this.error = $r('app.string.subscription_url_no_protocol', text);
    } else if (check.error === 'unknown_protocol') {
      this.error = $r('app.string.subscription_url_unknown_protocol', check.scheme);
    } else {
      this.error = '';
    }
  }

  /** Asks the platform whether a link can be opened. A throw means no. */
  private canOpen(link: string): boolean {
    try {
      return bundleManager.canOpenLink(link);
    } catch (e) {
      return false;
    }
  }

  /** True when the message holds text. A Resource always counts as text. */
  private hasText(value: ResourceStr): boolean {
    if (typeof value === 'string') {
      return value.length > 0;
    }
    return true;
  }

  build() {
    Column({ space: 12 }) {
      Text($r('app.string.subscription_edit_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
      TextArea({ placeholder: 'https://…', text: this.url })
        .height(96)
        .fontSize(14)
        .onChange((value: string): void => {
          this.url = value;
          this.validate(value);
        })
      if (this.hasText(this.error)) {
        Text(this.error)
          .fontSize(12)
          .fontColor($r('app.color.error'))
          .width('100%')
      }
      if (this.hasText(this.warning)) {
        Text(this.warning)
          .fontSize(12)
          .fontColor($r('app.color.warning'))
          .width('100%')
      }
      Row({ space: 8 }) {
        if (this.editing) {
          Button($r('app.string.subscription_remove'))
            .fontSize(14)
            .layoutWeight(1)
            .backgroundColor($r('app.color.error_container'))
            .fontColor($r('app.color.on_container'))
            .onClick(() => {
              this.onResult('remove', this.url);
              this.controller.close();
            })
        }
        Button($r('app.string.common_cancel'))
          .fontSize(14)
          .layoutWeight(1)
          .backgroundColor($r('app.color.button_neutral'))
          .fontColor($r('app.color.on_neutral'))
          .onClick(() => {
            this.onResult('cancel', this.url);
            this.controller.close();
          })
        Button($r('app.string.common_ok'))
          .fontSize(14)
          .layoutWeight(1)
          .backgroundColor($r('app.color.accent_container'))
          .fontColor($r('app.color.on_container'))
          .enabled(this.valid)
          .onClick(() => {
            this.onResult('ok', this.url);
            this.controller.close();
          })
      }
      .width('100%')
    }
    .padding(20)
  }
}

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

const KEY = 'ability_context';

/**
 * Holds the UIAbility context for the UI process. Pages must not keep their
 * own `context` property (it collides with the component framework's
 * internal field and silently resolves to undefined) and the deprecated
 * `getContext(this)` returns a context that newer runtimes reject in
 * data-kit calls, so EntryAbility registers its real context here at
 * startup and pages read it back via abilityContext().
 */
export function setAbilityContext(context: common.UIAbilityContext): void {
  AppStorage.setOrCreate(KEY, context);
}

const IMPORT_KEY = 'pending_import_uri';

/**
 * A profile link the ability was launched with, waiting for the page to take
 * it. It is kept here because the link arrives with the want, which can be
 * before the page exists (a cold start) or while it is already showing (a link
 * opened from a browser).
 */
export function setPendingImport(uri: string): void {
  AppStorage.setOrCreate(IMPORT_KEY, uri);
}

/** Takes the pending link, if any, and clears it so it is handled once. */
export function takePendingImport(): string {
  const uri = AppStorage.get(IMPORT_KEY) as string | undefined;
  if (uri === undefined || uri.length === 0) {
    return '';
  }
  AppStorage.setOrCreate(IMPORT_KEY, '');
  return uri;
}

export function abilityContext(): common.UIAbilityContext {
  const context = AppStorage.get(KEY) as common.UIAbilityContext | undefined;
  if (context !== undefined) {
    return context;
  }
  return getContext() as common.UIAbilityContext;
}

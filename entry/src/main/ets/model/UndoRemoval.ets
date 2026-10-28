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

/** How long the undo bar waits before the delete commits. */
export const UNDO_TIMEOUT_MS: number = 4000;

/**
 * The profile ids whose rows are hidden and whose delete is not committed.
 *
 * The bin keeps ids only. The store is the source of the row and the order. A
 * pending removal does not write the store. Undo therefore restores the
 * original position.
 */
export class UndoBin {
  private entries: string[] = [];

  /** Adds one id. An empty id and an id already in the bin are ignored. */
  add(id: string): void {
    if (id.length === 0 || this.entries.indexOf(id) >= 0) {
      return;
    }
    this.entries.push(id);
  }

  /** A copy of the ids in removal order. */
  ids(): string[] {
    return this.entries.slice();
  }

  size(): number {
    return this.entries.length;
  }

  has(id: string): boolean {
    return this.entries.indexOf(id) >= 0;
  }

  /** Empties the bin. */
  clear(): void {
    this.entries = [];
  }
}

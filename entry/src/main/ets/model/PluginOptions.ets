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
 * The built-in SIP003 plugin catalogue and the plugin options syntax.
 *
 * This module is pure ArkTS. It imports no kit and does no I/O. `Profile.ets`
 * imports this module, and the dependency runs one way only.
 *
 * The catalogue must stay in step with `parse_plugin` in
 * `native/sslocal-ffi/src/plugin.rs`. The native parser accepts these names:
 * `obfs-local`, `simple-obfs`, `obfs`, and `v2ray-plugin`.
 *
 * The options tokenizer copies `PluginOptions.kt` from shadowsocks-android.
 */

/** Canonical id of the simple-obfs plugin. */
export const PLUGIN_OBFS_LOCAL: string = 'obfs-local';
/** Canonical id of the v2ray-plugin plugin. */
export const PLUGIN_V2RAY: string = 'v2ray-plugin';
/** Plugin state for an empty id. */
export const PLUGIN_STATE_DISABLED: string = 'disabled';
/** Plugin state for an id in the catalogue. */
export const PLUGIN_STATE_KNOWN: string = 'known';
/** Plugin state for an id outside the catalogue. */
export const PLUGIN_STATE_UNKNOWN: string = 'unknown';
/** Validation result for a valid options text. */
export const PLUGIN_OPTIONS_OK: string = '';
/** Validation result for an ISO control character. */
export const PLUGIN_OPTIONS_CONTROL: string = 'control';
/** Validation result for a bad or missing obfs mode. */
export const PLUGIN_OPTIONS_OBFS_MODE: string = 'obfs-mode';
/** Validation result for a bad v2ray mode. */
export const PLUGIN_OPTIONS_V2RAY_MODE: string = 'v2ray-mode';

/** One entry of the built-in plugin catalogue. */
export interface PluginDefinition {
  /** Canonical plugin id. */
  id: string;
  /** Other ids that resolve to this definition. */
  aliases: string[];
  /** Display label. Plugin data for tests, not for the page. */
  label: string;
  /** Options text used when the user selects the plugin first. */
  defaultOptions: string;
}

/** One `key=value` pair of an options text. A bare key has a null value. */
export interface PluginOptionEntry {
  key: string;
  value: string | null;
}

/** One row of the plugin picker. */
export interface PluginChoice {
  /** Plugin id. The empty string is the Disabled row. */
  id: string;
  /** True for the row that resolves to the current plugin. */
  current: boolean;
}

/**
 * The built-in plugins, in the Android discovery order after Disabled.
 *
 * The page chooses a string resource by id, so the Chinese UI keeps its own
 * text. The page does not render `label`.
 */
export const BUILTIN_PLUGINS: PluginDefinition[] = [
  {
    id: PLUGIN_OBFS_LOCAL,
    aliases: ['simple-obfs', 'obfs'],
    label: 'simple-obfs',
    defaultOptions: 'obfs=tls',
  },
  {
    id: PLUGIN_V2RAY,
    aliases: [],
    label: 'v2ray-plugin',
    defaultOptions: 'mode=websocket',
  },
];

/**
 * Finds a definition by its id or by one of its aliases.
 *
 * @returns the definition, or null for an empty id and for an unknown id.
 */
export function findPlugin(id: string): PluginDefinition | null {
  if (id.length === 0) {
    return null;
  }
  for (let i = 0; i < BUILTIN_PLUGINS.length; i++) {
    const definition: PluginDefinition = BUILTIN_PLUGINS[i];
    if (definition.id === id) {
      return definition;
    }
    for (let j = 0; j < definition.aliases.length; j++) {
      if (definition.aliases[j] === id) {
        return definition;
      }
    }
  }
  return null;
}

/** Returns true when the id or one of its aliases is in the catalogue. */
export function isKnownPlugin(id: string): boolean {
  return findPlugin(id) !== null;
}

/**
 * Returns true when two ids mean the same plugin.
 *
 * Equal ids match. Two ids that resolve to the same definition match. A known
 * id never matches an unknown id.
 */
export function samePlugin(first: string, second: string): boolean {
  if (first === second) {
    return true;
  }
  const a: PluginDefinition | null = findPlugin(first);
  const b: PluginDefinition | null = findPlugin(second);
  if (a === null || b === null) {
    return false;
  }
  return a.id === b.id;
}

/** Returns the default options of a plugin. Returns '' for an unknown id. */
export function pluginDefaultOptions(id: string): string {
  const definition: PluginDefinition | null = findPlugin(id);
  return definition === null ? '' : definition.defaultOptions;
}

/**
 * Returns the plugin state of an id.
 *
 * @returns PLUGIN_STATE_DISABLED for '', PLUGIN_STATE_KNOWN for a known id,
 *   and PLUGIN_STATE_UNKNOWN for any other id.
 */
export function pluginStateOf(id: string): string {
  if (id.length === 0) {
    return PLUGIN_STATE_DISABLED;
  }
  return findPlugin(id) !== null ? PLUGIN_STATE_KNOWN : PLUGIN_STATE_UNKNOWN;
}

/**
 * Returns the picker rows for a current id.
 *
 * Disabled comes first, then the two built-in definitions. The row that
 * resolves to the current id is marked and moves to position 0. An unknown
 * current id marks no row and moves no row. An alias current id marks the
 * canonical row.
 */
export function pluginChoices(currentId: string): PluginChoice[] {
  const choices: PluginChoice[] = [];
  const disabled: PluginChoice = { id: '', current: currentId.length === 0 };
  choices.push(disabled);
  for (let i = 0; i < BUILTIN_PLUGINS.length; i++) {
    const definition: PluginDefinition = BUILTIN_PLUGINS[i];
    const choice: PluginChoice = {
      id: definition.id,
      current: samePlugin(definition.id, currentId),
    };
    choices.push(choice);
  }
  for (let i = 1; i < choices.length; i++) {
    if (choices[i].current) {
      const marked: PluginChoice = choices[i];
      choices.splice(i, 1);
      choices.unshift(marked);
      break;
    }
  }
  return choices;
}

/**
 * The plugin options syntax: check, parse, serialize, and validate.
 *
 * See `PluginOptions.kt` in shadowsocks-android for the original tokenizer.
 */
export class PluginOptions {
  static readonly CONTROL_MESSAGE: string = 'No control characters allowed.';

  /**
   * Checks a text for ISO control characters.
   *
   * @returns CONTROL_MESSAGE when the text holds a character in U+0000 to
   *   U+001F or in U+007F to U+009F, and '' otherwise.
   */
  static check(text: string): string {
    for (let i = 0; i < text.length; i++) {
      const code: number = text.charCodeAt(i);
      if ((code <= 0x1F) || (code >= 0x7F && code <= 0x9F)) {
        return PluginOptions.CONTROL_MESSAGE;
      }
    }
    return '';
  }

  /**
   * Splits an options text into ordered entries.
   *
   * The rules copy the Android tokenizer:
   * - A backslash escapes the next character.
   * - The first unescaped '=' splits a token into key and value.
   * - A later '=' stays in the value.
   * - ';' ends a token.
   * - A token with a key stores `key=value`.
   * - A token without '=' stores a bare key with a null value.
   * - An empty token is skipped.
   * - Keys and values keep their spaces.
   *
   * The text is read as if a ';' follows it. A trailing backslash therefore
   * consumes that terminator, and the last pair drops.
   *
   * @throws Error(CONTROL_MESSAGE) when the text holds a control character.
   */
  static parse(text: string): PluginOptionEntry[] {
    if (PluginOptions.check(text).length > 0) {
      throw new Error(PluginOptions.CONTROL_MESSAGE);
    }
    const entries: PluginOptionEntry[] = [];
    let current: string = '';
    let key: string | null = null;
    let escaped: boolean = false;
    for (let i = 0; i < text.length; i++) {
      const ch: string = text.charAt(i);
      if (escaped) {
        current += ch;
        escaped = false;
        continue;
      }
      if (ch === '\\') {
        escaped = true;
        continue;
      }
      if (ch === '=') {
        if (key === null) {
          key = current;
          current = '';
        } else {
          current += ch;
        }
        continue;
      }
      if (ch === ';') {
        PluginOptions.flush(entries, key, current);
        key = null;
        current = '';
        continue;
      }
      current += ch;
    }
    if (!escaped) {
      PluginOptions.flush(entries, key, current);
    }
    return entries;
  }

  /**
   * Joins entries into one options text.
   *
   * Entries keep their order. A null value writes the bare key. A backslash
   * escapes '\', '=', and ';' in keys and values.
   */
  static serialize(entries: PluginOptionEntry[]): string {
    let result: string = '';
    for (let i = 0; i < entries.length; i++) {
      if (i > 0) {
        result += ';';
      }
      const entry: PluginOptionEntry = entries[i];
      result += PluginOptions.escape(entry.key);
      const value: string | null = entry.value;
      if (value !== null) {
        result += '=';
        result += PluginOptions.escape(value);
      }
    }
    return result;
  }

  /** Returns the normalized form of a text. Returns '' for an empty text. */
  static canonical(text: string): string {
    return PluginOptions.serialize(PluginOptions.parse(text));
  }

  /**
   * Checks an options text against the schema of a plugin.
   *
   * The last entry with a matching key wins, as a map put does on Android.
   * A key the plugin does not know passes, because the native parser logs it
   * and ignores it. An unknown plugin id passes, because the editor cannot
   * open for that case.
   *
   * @returns PLUGIN_OPTIONS_OK, PLUGIN_OPTIONS_CONTROL,
   *   PLUGIN_OPTIONS_OBFS_MODE, or PLUGIN_OPTIONS_V2RAY_MODE.
   */
  static validate(pluginId: string, text: string): string {
    if (PluginOptions.check(text).length > 0) {
      return PLUGIN_OPTIONS_CONTROL;
    }
    const definition: PluginDefinition | null = findPlugin(pluginId);
    if (definition === null) {
      return PLUGIN_OPTIONS_OK;
    }
    const entries: PluginOptionEntry[] = PluginOptions.parse(text);
    if (definition.id === PLUGIN_OBFS_LOCAL) {
      const index: number = PluginOptions.lastIndexForKey(entries, 'obfs');
      if (index < 0) {
        return PLUGIN_OPTIONS_OBFS_MODE;
      }
      const value: string | null = entries[index].value;
      if (value === null) {
        return PLUGIN_OPTIONS_OBFS_MODE;
      }
      const mode: string = value.trim();
      if (mode !== 'http' && mode !== 'tls') {
        return PLUGIN_OPTIONS_OBFS_MODE;
      }
    }
    if (definition.id === PLUGIN_V2RAY) {
      const index: number = PluginOptions.lastIndexForKey(entries, 'mode');
      if (index >= 0) {
        const value: string | null = entries[index].value;
        if (value === null) {
          return PLUGIN_OPTIONS_V2RAY_MODE;
        }
        const mode: string = value.trim().toLowerCase();
        if (mode !== 'websocket' && mode !== 'ws') {
          return PLUGIN_OPTIONS_V2RAY_MODE;
        }
      }
    }
    return PLUGIN_OPTIONS_OK;
  }

  /** Stores one token. An empty token stores nothing. */
  private static flush(entries: PluginOptionEntry[], key: string | null,
    current: string): void {
    if (key !== null) {
      const entry: PluginOptionEntry = { key: key, value: current };
      entries.push(entry);
    } else if (current.length > 0) {
      const entry: PluginOptionEntry = { key: current, value: null };
      entries.push(entry);
    }
  }

  /** Returns the index of the last entry with this key, or -1. */
  private static lastIndexForKey(entries: PluginOptionEntry[], name: string): number {
    let found: number = -1;
    for (let i = 0; i < entries.length; i++) {
      if (entries[i].key.trim() === name) {
        found = i;
      }
    }
    return found;
  }

  /** Escapes '\', '=', and ';' with a backslash. */
  private static escape(text: string): string {
    let result: string = '';
    for (let i = 0; i < text.length; i++) {
      const ch: string = text.charAt(i);
      if (ch === '\\' || ch === '=' || ch === ';') {
        result += '\\';
      }
      result += ch;
    }
    return result;
  }
}

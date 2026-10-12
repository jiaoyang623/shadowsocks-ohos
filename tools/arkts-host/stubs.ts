/**
 * Stand-ins for the `@kit.*` modules the model layer imports.
 *
 * Every one of them is a native API with no developer-host equivalent. The
 * specs reach none of them: they cover parsing, serialisation and arithmetic,
 * which is what makes running them here worthwhile. A call that does reach one
 * throws with the name, rather than failing somewhere further away.
 */

/**
 * The only name the model layer takes from @kit.AbilityKit. It stands for the
 * SDK's ability context, so `any` is the honest type here: the ArkTS compiler
 * in the build is what checks how it is used.
 */
export namespace common {
  export type Context = any;
}

/**
 * The ArkUI global resource lookup, which is a compile-time construct rather
 * than an import. Only `ConnectionNotification` uses it, for the strings the
 * notification API takes as plain text, and no spec goes near that.
 */
declare global {
  function $r(key: string, ...args: (string | number)[]): { id: number };
}

const unavailable = new Proxy({}, {
  get: (_target, name) => {
    if (typeof name === 'symbol') {
      return undefined;
    }
    return () => {
      throw new Error(`@kit API '${String(name)}' has no host implementation`);
    };
  },
});

export const fileIo: any = unavailable;
export const http: any = unavailable;
export const socket: any = unavailable;
export const BusinessError: any = unavailable;

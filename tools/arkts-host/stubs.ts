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
  export type UIAbilityContext = any;
}

/**
 * The ArkUI global resource lookup, which is a compile-time construct rather
 * than an import. Only `ConnectionNotification` uses it, for the strings the
 * notification API takes as plain text, and no spec goes near that.
 */
declare global {
  function $r(key: string, ...args: (string | number)[]): { id: number; params?: Array<string | number> };
  type ResourceStr = string | { id: number; params?: Array<string | number> };
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
export namespace http {
  export interface HttpRequest {
    request(url: string, options: Object): Promise<{ responseCode: number; result: Object }>;
    destroy(): void;
  }
  export const createHttp: any = unavailable;
  export const RequestMethod: any = { GET: 'GET', POST: 'POST' };
}
export const socket: any = unavailable;
export interface BusinessError {
  code: number;
  message: string;
}
export const BusinessError: any = unavailable;
export namespace notificationManager {
  export interface NotificationRequest {
    [key: string]: any;
  }
  export interface NotificationActionButton {
    [key: string]: any;
  }
  export const ContentType: any = { NOTIFICATION_CONTENT_BASIC_TEXT: 0 };
  export const SlotType: any = { CONTENT_INFORMATION: 0, OTHER_TYPES: 1 };
  export const publish: any = unavailable;
  export const cancel: any = unavailable;
  export const isNotificationEnabled: any = unavailable;
  export const requestEnableNotification: any = unavailable;
}
export namespace commonEventManager {
  export type CommonEventSubscriber = any;
  export const createSubscriber: any = unavailable;
  export const subscribe: any = unavailable;
  export const unsubscribe: any = unavailable;
}
export const hilog: any = unavailable;
export const wantAgent: any = unavailable;
export type WantAgent = any;

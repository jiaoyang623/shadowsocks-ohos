/**
 * Minimal stand-in for `@ohos/hypium`, so the model-layer specs can run on a
 * developer host with node.
 *
 * The specs' own runner drives the SDK previewer, whose Linux build cannot
 * execute them: it prints nothing and exits 0 (AGENTS.md records the same about
 * CI). That leaves the pure-ArkTS logic in `entry/src/main/ets/model`, which is
 * the part with no native dependency and the part most worth checking, with no
 * test loop outside DevEco Studio. This provides the three functions the specs
 * use, so `test-arkts-host.sh` can run those same spec files directly.
 *
 * Assertions compare by identity, or by value for objects and arrays, which is
 * all the specs here ask for.
 */

type Body = () => void;

// Declared rather than depended on: @types/node is not installed, and these two
// are the only host globals the harness touches.
declare const process: { exitCode?: number };
declare const console: { log(...args: unknown[]): void; error(...args: unknown[]): void };

let suite = '';
let passed = 0;
let failed = 0;
const failures: string[] = [];

export function describe(name: string, body: Body): void {
  const previous = suite;
  suite = previous.length === 0 ? name : `${previous} > ${name}`;
  body();
  suite = previous;
}

export function it(name: string, _level: number, body: Body): void {
  try {
    body();
    passed++;
  } catch (error) {
    failed++;
    const message = error instanceof Error ? error.message : String(error);
    failures.push(`${suite} > ${name}\n    ${message}`);
  }
}

function same(a: unknown, b: unknown): boolean {
  if (a === b) {
    return true;
  }
  if (typeof a === 'object' && typeof b === 'object' && a !== null && b !== null) {
    return JSON.stringify(a) === JSON.stringify(b);
  }
  return false;
}

class Assertion {
  value: unknown;

  constructor(value: unknown) {
    this.value = value;
  }

  assertEqual(expected: unknown): void {
    if (!same(this.value, expected)) {
      throw new Error(`expected ${JSON.stringify(expected)}, got ${JSON.stringify(this.value)}`);
    }
  }

  assertTrue(): void {
    if (this.value !== true) {
      throw new Error(`expected true, got ${JSON.stringify(this.value)}`);
    }
  }

  assertFalse(): void {
    if (this.value !== false) {
      throw new Error(`expected false, got ${JSON.stringify(this.value)}`);
    }
  }
}

export function expect(value: unknown): Assertion {
  return new Assertion(value);
}

/** Prints the tally and fails the process when anything did not pass. */
export function report(): void {
  if (failures.length > 0) {
    console.error('');
    for (const failure of failures) {
      console.error(`FAIL ${failure}`);
    }
  }
  console.log(`\n${passed} passed, ${failed} failed`);
  if (failed > 0) {
    process.exitCode = 1;
  }
}

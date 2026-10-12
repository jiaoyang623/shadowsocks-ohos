/**
 * Host entry point for the model-layer specs. Assembles nothing itself: the
 * script copies the sources and the shims into one directory, and this runs the
 * same suite entry the device runner uses.
 */
import testsuite from './test/List.test';
import { report } from './hypium';

testsuite();
report();

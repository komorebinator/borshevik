// Unit tests for the Image Manager's pure helpers, run with gjs from the repository root:
//   gjs -m tests/image-manager.js <case>
// Prints "ok" and exits 0 when every assertion holds; otherwise prints each failure and exits 1.

import System from 'system';

import { formatUptime } from '../build_files/root/usr/share/borshevik-image-manager/util.js';
import { computeUiState } from '../build_files/root/usr/share/borshevik-image-manager/app_state.js';

const failures = [];
function expectEqual(actual, expected, what) {
  if (actual !== expected)
    failures.push(`${what}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}

const cases = {
  'format-uptime': () => {
    expectEqual(formatUptime(0, 'd'), '0:00:00', 'zero');
    expectEqual(formatUptime(59, 'd'), '0:00:59', 'under a minute');
    expectEqual(formatUptime(899, 'd'), '0:14:59', 'under an hour');
    expectEqual(formatUptime(11645, 'd'), '3:14:05', 'under a day');
    expectEqual(formatUptime(86400, 'd'), '1d 0:00:00', 'exactly one day');
    expectEqual(formatUptime(184445, 'd'), '2d 3:14:05', 'days, hours, minutes, seconds');
    expectEqual(formatUptime(184445, 'д'), '2д 3:14:05', 'localized day suffix');
  },

  'report-issue-visibility': () => {
    const i18n = { t: (key) => key };
    const show = (phase, needsReboot) =>
      computeUiState({ i18n, facts: { needsReboot }, check: { phase, downloadSize: null, message: '' } })
        .showReportIssue;

    expectEqual(show('no_updates', false), true, 'up to date');
    expectEqual(show('no_updates', true), false, 'update staged, waiting for reboot');
    expectEqual(show('available', false), false, 'update available');
    expectEqual(show('checking', false), false, 'check in progress');
    expectEqual(show('error', false), false, 'check failed');
    expectEqual(show('idle', false), false, 'not checked yet');
  },
};

const name = ARGV[0];
if (!(name in cases)) {
  print(`unknown case ${JSON.stringify(name)}; expected one of: ${Object.keys(cases).join(', ')}`);
  System.exit(2);
}

cases[name]();

if (failures.length > 0) {
  for (const f of failures)
    print(`FAIL ${f}`);
  System.exit(1);
}
print('ok');

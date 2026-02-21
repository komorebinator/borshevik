// Command execution with optional pkexec and live output.

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

function _prependPkexec(argv) {
  return ['pkexec', ...argv];
}

export class CommandRunner {
  constructor({ onStdout, onStderr, onExit } = {}) {
    this._onStdout = onStdout || (() => {});
    this._onStderr = onStderr || (() => {});
    this._onExit = onExit || (() => {});
    this._proc = null;
  }

  cancel() {
    if (this._proc) {
      try {
        this._proc.force_exit();
      } catch (e) {
        console.error('Failed to cancel process:', e);
      }
    }
  }

  async run(argv, { root = false } = {}) {
    const finalArgv = root ? _prependPkexec(argv) : argv;

    // Create subprocess launcher with TERM=xterm
    const launcher = new Gio.SubprocessLauncher({
      flags: Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE
    });
    
    // Set environment variable
    launcher.setenv('TERM', 'xterm', true);
    
    const proc = launcher.spawnv(finalArgv);
    this._proc = proc;

    const stdout = proc.get_stdout_pipe();
    const stderr = proc.get_stderr_pipe();

    const stdoutStream = new Gio.DataInputStream({ base_stream: stdout });
    const stderrStream = new Gio.DataInputStream({ base_stream: stderr });

    // GJS' implicit promisification of Gio.DataInputStream.read_line_async() is
    // unreliable across versions. Implement an explicit async/finish wrapper.
    const readLine = (stream) => new Promise((resolve, reject) => {
      stream.read_line_async(GLib.PRIORITY_DEFAULT, null, (s, res) => {
        try {
          const [line /* Uint8Array? */, _len] = s.read_line_finish(res);
          resolve(line);
        } catch (e) {
          reject(e);
        }
      });
    });

    const decoder = new TextDecoder('utf-8');

    const readLoop = async (stream, cb) => {
      // Never reject: errors during pipe drain are expected when a child exits.
      while (true) {
        let line;
        try {
          line = await readLine(stream);
        } catch (_e) {
          break;
        }
        if (line === null) break;
        try {
          cb(decoder.decode(line) + '\n');
        } catch (_e) {
          // Ignore consumer errors to keep draining the stream.
        }
      }
    };

    // Read both streams concurrently.
    const p1 = readLoop(stdoutStream, this._onStdout);
    const p2 = readLoop(stderrStream, this._onStderr);

    // NOTE: We intentionally do NOT rely on GJS' implicit promisification for
    // Gio.Subprocess.wait_async(). In practice it may resolve before the child
    // has fully transitioned to an exited state, which makes get_exit_status()
    // trigger: g_subprocess_get_exit_status: assertion 'pid == 0' failed.
    // Wrapping the async/finish pair explicitly avoids that race.
    const waitForExit = () => new Promise((resolve, reject) => {
      proc.wait_async(null, (p, res) => {
        try {
          p.wait_finish(res);
          resolve();
        } catch (e) {
          reject(e);
        }
      });
    });

    let success = false;
    let status = 1;

    try {
      await waitForExit();
      success = proc.get_successful();
      status = proc.get_exit_status();
      return { success, status };
    } finally {
      await Promise.allSettled([p1, p2]);
      // At this point the process is guaranteed to be in a finished state.
      // Still, guard status to avoid throwing inside finally.
      try {
        status = proc.get_exit_status();
      } catch (_) {
        status = 1;
      }
      this._onExit({ success, status });
    }
  }
}

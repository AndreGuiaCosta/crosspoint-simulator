#pragma once

#include <cstdint>
#include <string>

/**
 * Script-driven test harness for the simulator.
 *
 * Reads a sequence of commands from a file (or stdin) and feeds them into
 * the simulator's input + control surface. Lets external agents (CI, AI
 * coding assistants) drive the simulator end-to-end without an SDL-aware
 * windowing environment.
 *
 * Wire-up:
 *   - simulator_main.cpp parses `--script <path>` (or `--script -` for
 *     stdin) and calls `init(...)`. Without `--script` everything below
 *     no-ops and the binary behaves identically to today.
 *   - simulator_main.cpp calls `tick()` once per loop iteration to drain
 *     pending commands.
 *   - HWCDC::write tees stderr through `onLogChar()` so `expect`
 *     commands can match against log output.
 *   - Firmware `KeyboardEntryActivity::onEnter()` (under #ifdef SIMULATOR)
 *     calls `consumeQueuedText()` and short-circuits to `onComplete()`
 *     when the script driver has typing queued — bypasses the on-screen
 *     keyboard navigation entirely.
 *
 * Command grammar (one per line, '#' starts a comment, blank lines OK):
 *
 *   press  back|confirm|left|right|up|down|power
 *   release back|confirm|left|right|up|down|power
 *   tap    back|confirm|left|right|up|down|power     (press + release)
 *   type   <text>           # queue for next KeyboardEntryActivity
 *   wait   <ms>             # delay before next command
 *   screenshot <path>       # write 1-bit BMP framebuffer dump (path resolved
 *                           # under the simulator working directory)
 *   expect <substring>      # block until the substring appears on stderr
 *   expect_timeout <ms>     # cap subsequent `expect` waits (default 30000)
 *   log    <text>           # echo to stderr — useful for marking sections
 *   quit                    # exit the simulator cleanly (exit code 0)
 *
 * Anything unrecognised aborts the script with exit code 2.
 */
namespace ScriptDriver {

// Returns true if `--script <path>` was found and the script loaded.
bool init(int argc, char** argv);

bool isActive();

// Called once per simulator main-loop iteration. No-op when inactive.
void tick();

// Called by the HWCDC write path so `expect` can see log output.
void onLogChar(char c);

// Called by KeyboardEntryActivity::onEnter (under #ifdef SIMULATOR) to
// consume any text queued by a `type` command. Returns empty string when
// nothing queued. Each call removes the head of the queue.
std::string consumeQueuedText();

}  // namespace ScriptDriver

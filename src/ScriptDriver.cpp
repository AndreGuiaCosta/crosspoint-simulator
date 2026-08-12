#include "ScriptDriver.h"

#include <SDL2/SDL.h>
#include <unistd.h>  // _exit

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <fstream>
#include <iostream>
#include <queue>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

#include "HalDisplay.h"

extern HalDisplay display;
extern std::atomic<bool> quitRequested;  // defined in HalDisplay.cpp

namespace ScriptDriver {
namespace {

// ---------- script storage ----------

struct Command {
  enum Op { PRESS, RELEASE, TAP, TYPE, WAIT, SCREENSHOT, EXPECT, EXPECT_TIMEOUT, LOG, QUIT };
  Op op;
  std::string arg;
  uint32_t numeric = 0;  // wait ms, expect_timeout ms
};

std::vector<Command> commands;
size_t cursor = 0;
bool active = false;

// ---------- timing ----------

uint32_t nextRunAtMs = 0;       // SDL_GetTicks deadline; 0 = run immediately
uint32_t expectStartedAtMs = 0; // when the current EXPECT began waiting
uint32_t expectTimeoutMs = 30000;
bool waitingOnExpect = false;
std::string expectPattern;

// ---------- log capture ----------

constexpr size_t LOG_RING_LINES = 256;
constexpr size_t LOG_LINE_MAX = 1024;
std::deque<std::string> logRing;
std::string currentLine;

// ---------- typing queue ----------

std::queue<std::string> typingQueue;

// ---------- button mapping ----------

const std::unordered_map<std::string, SDL_Scancode>& buttonMap() {
  static const std::unordered_map<std::string, SDL_Scancode> m = {
      {"back", SDL_SCANCODE_ESCAPE}, {"confirm", SDL_SCANCODE_RETURN}, {"left", SDL_SCANCODE_LEFT},
      {"right", SDL_SCANCODE_RIGHT}, {"up", SDL_SCANCODE_UP},          {"down", SDL_SCANCODE_DOWN},
      {"power", SDL_SCANCODE_P},
  };
  return m;
}

// ---------- helpers ----------

std::string trim(const std::string& s) {
  const auto first = s.find_first_not_of(" \t\r\n");
  if (first == std::string::npos) return "";
  const auto last = s.find_last_not_of(" \t\r\n");
  return s.substr(first, last - first + 1);
}

bool readScript(const std::string& path) {
  std::istream* in = nullptr;
  std::ifstream file;
  if (path == "-") {
    in = &std::cin;
  } else {
    file.open(path);
    if (!file.is_open()) {
      std::fprintf(stderr, "[SCRIPT] cannot open %s\n", path.c_str());
      return false;
    }
    in = &file;
  }

  std::string raw;
  int lineNo = 0;
  while (std::getline(*in, raw)) {
    ++lineNo;
    std::string line = trim(raw);
    if (line.empty() || line[0] == '#') continue;

    const auto sp = line.find(' ');
    const std::string head = sp == std::string::npos ? line : line.substr(0, sp);
    const std::string rest = sp == std::string::npos ? "" : trim(line.substr(sp + 1));

    Command c;
    if (head == "press") {
      c.op = Command::PRESS;
      c.arg = rest;
    } else if (head == "release") {
      c.op = Command::RELEASE;
      c.arg = rest;
    } else if (head == "tap") {
      c.op = Command::TAP;
      c.arg = rest;
    } else if (head == "type") {
      c.op = Command::TYPE;
      c.arg = rest;
    } else if (head == "wait") {
      c.op = Command::WAIT;
      c.numeric = static_cast<uint32_t>(std::strtoul(rest.c_str(), nullptr, 10));
    } else if (head == "screenshot") {
      c.op = Command::SCREENSHOT;
      c.arg = rest;
    } else if (head == "expect") {
      c.op = Command::EXPECT;
      c.arg = rest;
    } else if (head == "expect_timeout") {
      c.op = Command::EXPECT_TIMEOUT;
      c.numeric = static_cast<uint32_t>(std::strtoul(rest.c_str(), nullptr, 10));
    } else if (head == "log") {
      c.op = Command::LOG;
      c.arg = rest;
    } else if (head == "quit") {
      c.op = Command::QUIT;
    } else {
      std::fprintf(stderr, "[SCRIPT] line %d: unknown command '%s'\n", lineNo, head.c_str());
      return false;
    }
    commands.push_back(std::move(c));
  }
  return true;
}

// Push a paired KEYDOWN/KEYUP through SDL so HalGPIO sees it via its
// existing event pump. Using SDL_PushEvent rather than mutating HalGPIO's
// per-frame arrays directly keeps `isPressed`/`SDL_GetKeyboardState` in
// sync (SDL updates its internal state when it processes pushed events).
void pushKey(SDL_Scancode sc, uint32_t type) {
  SDL_Event e{};
  e.type = type;
  e.key.type = type;
  e.key.state = (type == SDL_KEYDOWN) ? SDL_PRESSED : SDL_RELEASED;
  e.key.repeat = 0;
  e.key.keysym.scancode = sc;
  e.key.keysym.sym = SDL_GetKeyFromScancode(sc);
  SDL_PushEvent(&e);
}

bool resolveButton(const std::string& name, SDL_Scancode& out) {
  const auto& m = buttonMap();
  const auto it = m.find(name);
  if (it == m.end()) {
    std::fprintf(stderr, "[SCRIPT] unknown button '%s'\n", name.c_str());
    return false;
  }
  out = it->second;
  return true;
}

// ---------- BMP writer (1-bit, bottom-up) ----------

bool writeFramebufferBmp(const std::string& path) {
  // Resolve relative paths under the simulator working directory so script
  // paths line up with how the firmware sees the SD root.
  std::string out = path;
  if (!out.empty() && out.front() == '/') {
    // Treat /foo as ./fs_/foo to match HalStorage's path mapping.
    out = "./fs_" + out;
  }
  // Ensure parent dir exists.
  const auto slash = out.find_last_of('/');
  if (slash != std::string::npos) {
    const std::string dir = out.substr(0, slash);
    std::string mk = "mkdir -p '" + dir + "'";
    (void)std::system(mk.c_str());
  }

  const uint8_t* fb = display.getFrameBuffer();
  if (!fb) {
    std::fprintf(stderr, "[SCRIPT] screenshot: framebuffer unavailable\n");
    return false;
  }

  const int width = HalDisplay::DISPLAY_WIDTH;
  const int height = HalDisplay::DISPLAY_HEIGHT;
  const int srcStride = width / 8;
  // BMP rows are padded to 4-byte boundaries.
  const int rowBytes = ((width + 31) / 32) * 4;
  const int pixelArrayBytes = rowBytes * height;
  // 14 (file header) + 40 (DIB header) + 8 (2-entry palette) = 62
  const int paletteBytes = 8;
  const int pixelOffset = 14 + 40 + paletteBytes;
  const int fileSize = pixelOffset + pixelArrayBytes;

  std::ofstream f(out, std::ios::binary);
  if (!f.is_open()) {
    std::fprintf(stderr, "[SCRIPT] screenshot: cannot open %s\n", out.c_str());
    return false;
  }

  auto put32 = [&](uint32_t v) {
    char b[4] = {char(v & 0xff), char((v >> 8) & 0xff), char((v >> 16) & 0xff), char((v >> 24) & 0xff)};
    f.write(b, 4);
  };
  auto put16 = [&](uint16_t v) {
    char b[2] = {char(v & 0xff), char((v >> 8) & 0xff)};
    f.write(b, 2);
  };

  // BITMAPFILEHEADER
  f.put('B'); f.put('M');
  put32(fileSize);
  put16(0); put16(0);
  put32(pixelOffset);
  // BITMAPINFOHEADER
  put32(40);
  put32(width);
  put32(height);
  put16(1);
  put16(1);   // bits per pixel
  put32(0);   // BI_RGB
  put32(pixelArrayBytes);
  put32(2835); put32(2835);  // ~72 DPI
  put32(2);   // 2 colours used
  put32(2);
  // Palette: 0 = white, 1 = black (firmware framebuffer uses bit-set = white)
  // Actually re-reading refreshDisplay: `isWhite = (fb[byteIdx] & (1 << bitIdx)) != 0`
  // → set bit = white. BMP palette index 0 should map to white, 1 to black.
  // BMP palette entries are 4 bytes: BB GG RR 00.
  f.put((char)0xff); f.put((char)0xff); f.put((char)0xff); f.put(0);  // index 0: white
  f.put(0);          f.put(0);          f.put(0);          f.put(0);  // index 1: black

  // Pixel data: bottom-up rows. Each source row is `srcStride` bytes; we
  // pad to `rowBytes`. Source bit semantics already match BMP 1-bit when
  // we invert (BMP: 0 = palette[0] = white, 1 = palette[1] = black; our
  // framebuffer: 1 = white). Invert each byte before writing.
  std::vector<uint8_t> row(rowBytes, 0);
  for (int y = height - 1; y >= 0; --y) {
    const uint8_t* src = fb + y * srcStride;
    for (int i = 0; i < srcStride; ++i) row[i] = ~src[i];
    for (int i = srcStride; i < rowBytes; ++i) row[i] = 0;
    f.write(reinterpret_cast<const char*>(row.data()), rowBytes);
  }
  f.flush();
  return f.good();
}

// ---------- log ring + expect ----------

void commitLine() {
  if (currentLine.empty()) return;
  if (logRing.size() >= LOG_RING_LINES) logRing.pop_front();
  logRing.push_back(std::move(currentLine));
  currentLine.clear();
}

bool ringContains(const std::string& needle) {
  for (const auto& line : logRing) {
    if (line.find(needle) != std::string::npos) return true;
  }
  return false;
}

// ---------- command execution ----------

void executeCurrent();

void scheduleAfter(uint32_t ms) {
  nextRunAtMs = SDL_GetTicks() + ms;
}

void advance() {
  ++cursor;
  nextRunAtMs = 0;  // Run next immediately on the following tick.
}

void executeCurrent() {
  if (cursor >= commands.size()) {
    std::fprintf(stderr, "[SCRIPT] script complete\n");
    quitRequested.store(true);
    active = false;
    return;
  }
  const Command& c = commands[cursor];
  switch (c.op) {
    case Command::PRESS: {
      SDL_Scancode sc;
      if (!resolveButton(c.arg, sc)) _exit(2);
      pushKey(sc, SDL_KEYDOWN);
      advance();
      break;
    }
    case Command::RELEASE: {
      SDL_Scancode sc;
      if (!resolveButton(c.arg, sc)) _exit(2);
      pushKey(sc, SDL_KEYUP);
      advance();
      break;
    }
    case Command::TAP: {
      SDL_Scancode sc;
      if (!resolveButton(c.arg, sc)) _exit(2);
      pushKey(sc, SDL_KEYDOWN);
      pushKey(sc, SDL_KEYUP);
      // Give the firmware loop one tick to consume both events before next
      // command — without this consecutive taps can collapse into one.
      advance();
      scheduleAfter(50);
      break;
    }
    case Command::TYPE:
      typingQueue.push(c.arg);
      advance();
      break;
    case Command::WAIT:
      advance();
      scheduleAfter(c.numeric);
      break;
    case Command::SCREENSHOT:
      if (!writeFramebufferBmp(c.arg)) _exit(2);
      std::fprintf(stderr, "[SCRIPT] screenshot -> %s\n", c.arg.c_str());
      advance();
      break;
    case Command::EXPECT:
      // If already in the ring, satisfy immediately; otherwise wait.
      if (ringContains(c.arg)) {
        std::fprintf(stderr, "[SCRIPT] expect satisfied (cached): %s\n", c.arg.c_str());
        advance();
      } else {
        waitingOnExpect = true;
        expectPattern = c.arg;
        expectStartedAtMs = SDL_GetTicks();
      }
      break;
    case Command::EXPECT_TIMEOUT:
      expectTimeoutMs = c.numeric;
      advance();
      break;
    case Command::LOG:
      std::fprintf(stderr, "[SCRIPT] %s\n", c.arg.c_str());
      advance();
      break;
    case Command::QUIT:
      std::fprintf(stderr, "[SCRIPT] quit\n");
      quitRequested.store(true);
      active = false;
      break;
  }
}

}  // namespace

bool init(int argc, char** argv) {
  std::string path;
  for (int i = 1; i < argc; ++i) {
    if (std::strcmp(argv[i], "--script") == 0 && i + 1 < argc) {
      path = argv[i + 1];
      ++i;
    }
  }
  if (path.empty()) return false;
  if (!readScript(path)) _exit(2);
  active = true;
  std::fprintf(stderr, "[SCRIPT] loaded %zu commands from %s\n", commands.size(), path.c_str());
  return true;
}

bool isActive() { return active; }

void tick() {
  if (!active) return;

  if (waitingOnExpect) {
    if (ringContains(expectPattern)) {
      std::fprintf(stderr, "[SCRIPT] expect satisfied: %s\n", expectPattern.c_str());
      waitingOnExpect = false;
      expectPattern.clear();
      advance();
    } else if (SDL_GetTicks() - expectStartedAtMs > expectTimeoutMs) {
      std::fprintf(stderr, "[SCRIPT] expect TIMEOUT (%u ms): %s\n", expectTimeoutMs, expectPattern.c_str());
      _exit(3);
    }
    return;
  }

  if (SDL_GetTicks() < nextRunAtMs) return;
  executeCurrent();
}

void onLogChar(char c) {
  if (!active) return;  // Avoid the per-char overhead when no script is running.
  if (c == '\n') {
    commitLine();
    return;
  }
  if (currentLine.size() < LOG_LINE_MAX) currentLine.push_back(c);
}

std::string consumeQueuedText() {
  if (typingQueue.empty()) return "";
  std::string t = std::move(typingQueue.front());
  typingQueue.pop();
  return t;
}

}  // namespace ScriptDriver

#pragma once
#include <Arduino.h>
#include <EInkDisplay.h>

class HalDisplay {
public:
  // Constructor with pin configuration
  HalDisplay();

  // Destructor
  ~HalDisplay();

  // Refresh modes
  enum RefreshMode {
    FULL_REFRESH, // Full refresh with complete waveform
    HALF_REFRESH, // Half refresh (1720ms) - balanced quality and speed
    FAST_REFRESH  // Fast refresh using custom LUT
  };

  // Initialize the display hardware and driver
  void begin();
  void begin(bool seamless);

  // Display dimensions
  static constexpr uint16_t DISPLAY_WIDTH = EInkDisplay::DISPLAY_WIDTH;
  static constexpr uint16_t DISPLAY_HEIGHT = EInkDisplay::DISPLAY_HEIGHT;
  static constexpr uint16_t DISPLAY_WIDTH_BYTES = DISPLAY_WIDTH / 8;
  static constexpr uint32_t BUFFER_SIZE = DISPLAY_WIDTH_BYTES * DISPLAY_HEIGHT;

  // Frame buffer operations
  void clearScreen(uint8_t color = 0xFF) const;
  void drawImage(const uint8_t *imageData, uint16_t x, uint16_t y, uint16_t w,
                 uint16_t h, bool fromProgmem = false) const;
  void drawImageTransparent(const uint8_t *imageData, uint16_t x, uint16_t y,
                            uint16_t w, uint16_t h,
                            bool fromProgmem = false) const;

  void displayBuffer(RefreshMode mode = RefreshMode::FAST_REFRESH,
                     bool turnOffScreen = false);
  void displayWindow(int x, int y, int w, int h);
  void refreshDisplay(RefreshMode mode = RefreshMode::FAST_REFRESH,
                      bool turnOffScreen = false);

  // CrumBLE's GfxRenderer calls this under #ifdef SIMULATOR to mirror the
  // device panel rotation. GfxRenderer already applies the logical coordinate
  // transform; the host sim renders portrait for our test flows, so just
  // record the value (no framebuffer rotation needed for portrait screens).
  void setSimulatorOrientation(int orientation) { simulatorOrientation_ = orientation; }
  int getSimulatorOrientation() const { return simulatorOrientation_; }

  // Power management
  void deepSleep();

  // Access to frame buffer
  uint8_t *getFrameBuffer() const;

  // Runtime geometry passthrough
  uint16_t getDisplayWidth() const;
  uint16_t getDisplayHeight() const;
  uint16_t getDisplayWidthBytes() const;
  uint32_t getBufferSize() const;

  // X3 grayscale preconditioning settle pass — no-op in the simulator, which
  // emulates the X4 panel (firmware's X4 path is also a no-op).
  void preconditionGrayscale() {}
  void preconditionGrayscale(uint16_t x, uint16_t y, uint16_t w, uint16_t h) {
    (void)x;
    (void)y;
    (void)w;
    (void)h;
  }

  // Base frame for a following grayscale overlay. The simulator has no
  // differential base waveform, so it displays normally with the fallback
  // mode (matches firmware's non-X3 behavior).
  void displayGrayscaleBase(RefreshMode fallback = HALF_REFRESH, bool turnOffScreen = false) {
    displayBuffer(fallback, turnOffScreen);
  }

  void copyGrayscaleBuffers(const uint8_t *lsbBuffer, const uint8_t *msbBuffer);
  void copyGrayscaleLsbBuffers(const uint8_t *lsbBuffer);
  void copyGrayscaleMsbBuffers(const uint8_t *msbBuffer);
  void cleanupGrayscaleBuffers(const uint8_t *bwBuffer);

  void displayGrayBuffer(bool turnOffScreen = false,
                         const unsigned char *lut = nullptr,
                         bool factoryMode = false);

  // Tiled grayscale strip — no-op in simulator; supportsStripGrayscale()
  // returns false so callers fall back to the framebuffer path.
  void writeGrayscalePlaneStrip(bool lsbPlane, const uint8_t* rows, uint16_t yStart, uint16_t numRows);
  bool supportsStripGrayscale() const;

  // Simulator only: call from main thread to push rendered pixels to SDL.
  void presentIfNeeded();
  // Simulator only: returns true once a hard shutdown has been requested.
  bool shouldQuit() const;

private:
  EInkDisplay einkDisplay;
  int simulatorOrientation_ = 0;
};

extern HalDisplay display;

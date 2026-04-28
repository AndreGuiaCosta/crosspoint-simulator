#pragma once
#include <mutex>

#include "FreeRTOS.h"
#include "task.h"  // for xTaskGetCurrentTaskHandle

// Use a real recursive mutex for the rendering semaphore.
struct SimMutex {
  std::recursive_mutex mtx;
  // Track "holder" so xSemaphoreGetMutexHolder mirrors FreeRTOS semantics —
  // the firmware uses this to assert that a task isn't trying to wait on
  // its own RenderLock. Not strictly thread-safe but good enough for the
  // simulator (only updated by the lock-owning thread).
  TaskHandle_t holder = nullptr;
};
typedef SimMutex* SemaphoreHandle_t;

inline SemaphoreHandle_t xSemaphoreCreateMutex() { return new SimMutex(); }

inline bool xSemaphoreTake(SemaphoreHandle_t sem, uint32_t /*ticksToWait*/) {
  if (!sem) return true;
  sem->mtx.lock();
  // Record the holder AFTER acquiring the lock. Without this, the firmware's
  // `mutexHolder == currTaskHandler` check in requestUpdateAndWait() compares
  // nullptr == nullptr (main thread has no task handle, holder was never
  // updated) and trips a spurious assertion.
  sem->holder = xTaskGetCurrentTaskHandle();
  return true;
}

inline bool xSemaphoreGive(SemaphoreHandle_t sem) {
  if (!sem) return true;
  sem->holder = nullptr;
  sem->mtx.unlock();
  return true;
}

inline TaskHandle_t xSemaphoreGetMutexHolder(SemaphoreHandle_t sem) { return sem ? sem->holder : nullptr; }

// xQueuePeek on a mutex: returns pdTRUE if the mutex is available (not taken).
inline int xQueuePeek(SemaphoreHandle_t sem, void*, uint32_t) {
  if (!sem) return pdTRUE;
  bool locked = sem->mtx.try_lock();
  if (locked) {
    sem->mtx.unlock();
    return pdTRUE;
  }
  return pdFALSE;
}

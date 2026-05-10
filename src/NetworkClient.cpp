#include "NetworkClient.h"

#include <sys/socket.h>
#include <unistd.h>

#include "Stream.h"

struct NetworkClient::Impl {
  explicit Impl(int socketFd) : fd(socketFd) {}
  ~Impl() {
    if (fd >= 0)
      ::close(fd);
  }

  int fd = -1;
};

NetworkClient::NetworkClient(int fd) : impl_(std::make_shared<Impl>(fd)) {}

size_t NetworkClient::write(const uint8_t *buf, size_t size) {
  if (!buf || size == 0)
    return 0;
  if (!impl_)
    return 0;
  if (impl_->fd < 0)
    return 0;

  size_t writtenTotal = 0;
#ifdef MSG_NOSIGNAL
  constexpr int sendFlags = MSG_NOSIGNAL;
#else
  constexpr int sendFlags = 0;
#endif
  while (writtenTotal < size) {
    const ssize_t written =
        ::send(impl_->fd, buf + writtenTotal, size - writtenTotal, sendFlags);
    if (written <= 0)
      break;
    writtenTotal += static_cast<size_t>(written);
  }
  return writtenTotal;
}

size_t NetworkClient::write(Stream &stream) {
  uint8_t buffer[4096];
  size_t total = 0;
  while (stream.available() > 0) {
    size_t count = 0;
    while (count < sizeof(buffer) && stream.available() > 0) {
      const int value = stream.read();
      if (value < 0)
        break;
      buffer[count++] = static_cast<uint8_t>(value);
    }
    if (count == 0)
      break;
    const size_t written = write(buffer, count);
    total += written;
    if (written != count)
      break;
  }
  return total;
}

void NetworkClient::stop() {
  if (impl_ && impl_->fd >= 0) {
    ::close(impl_->fd);
    impl_->fd = -1;
  }
}

uint8_t NetworkClient::connected() { return (impl_ && impl_->fd >= 0) ? 1 : 0; }

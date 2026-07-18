#define _POSIX_C_SOURCE 200809L

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>

int main(void) {
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
    perror("clock_gettime(CLOCK_MONOTONIC)");
    return 1;
  }

  uint64_t nanoseconds =
      (uint64_t)now.tv_sec * UINT64_C(1000000000) + (uint64_t)now.tv_nsec;
  printf("%" PRIu64 "\n", nanoseconds);
  return 0;
}

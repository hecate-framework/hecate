/* libFuzzer target `decode`: arbitrary bytes to native.decode with the default limits of hecate.json. */
#include "harness.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  fuzz_decode(data, size, 128, 1 << 20);
  return 0;
}

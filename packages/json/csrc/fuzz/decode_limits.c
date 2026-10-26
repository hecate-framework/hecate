/*
 * libFuzzer target `decode_limits`: the first two bytes choose max_depth (1 to 1000) and max_size (a tenth of the
 * text up to twice its length), the rest is the text. It reaches the depth and size checks that the default
 * limits of `decode` hide.
 */
#include "harness.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  if (size < 2) return 0;
  lua_Integer max_depth = 1 + ((lua_Integer)data[0] * 1000) / 256;
  size_t body = size - 2;
  lua_Integer max_size = (lua_Integer)(body / 10) + ((lua_Integer)data[1] * (lua_Integer)(body + 1)) / 128;
  fuzz_decode(data + 2, body, max_depth, max_size);
  return 0;
}

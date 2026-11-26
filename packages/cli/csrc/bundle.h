/* The Lua modules embedded in the executable (generated into bundle.c by `build-cli`). */
#ifndef HECATE_BUNDLE_H
#define HECATE_BUNDLE_H

#include <stddef.h>

typedef struct hecate_module {
  const char *name;   /* module name, e.g. "hecate.cli.main"; NULL ends the table */
  const char *source; /* Lua source text */
  size_t length;
} hecate_module;

extern const hecate_module hecate_modules[];

#endif

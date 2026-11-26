# Build matrix of the Hecate images (docker buildx bake -f docker/bake.hcl <target>).
# Run from the repository root. Specification: docs/architecture/versioning-and-distribution.md#docker-images

variable "HECATE_VERSION" { default = "0.0.0-dev" }
variable "LUA_LINE" { default = "5.5" }
variable "REGISTRY" { default = "hecate" }

group "default" {
  targets = ["runtime", "build"]
}

target "image" {
  context   = "."
  platforms = ["linux/amd64", "linux/arm64"]
  args = {
    HECATE_VERSION = HECATE_VERSION
    LUA_VERSION    = LUA_LINE
  }
}

target "runtime" {
  inherits   = ["image"]
  name       = "runtime-${variant}"
  matrix     = { variant = ["debian", "alpine"] }
  dockerfile = "docker/runtime/Dockerfile.${variant}"
  tags       = ["${REGISTRY}/runtime:${HECATE_VERSION}-lua${LUA_LINE}-${variant}"]
}

target "build" {
  inherits   = ["image"]
  name       = "build-${variant}"
  matrix     = { variant = ["debian", "alpine"] }
  dockerfile = "docker/build/Dockerfile.${variant}"
  tags       = ["${REGISTRY}/build:${HECATE_VERSION}-lua${LUA_LINE}-${variant}"]
}

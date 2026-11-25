---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field
local test = require("harness.test")
local dockerfile = require("lib.dockerfile")
local task = require("tasks.check_docker")
local T = test.Case("DockerfileTest")

local function matches(self, text, pattern) self:assert_true(tostring(text):find(pattern), ("%q does not match %s"):format(tostring(text), pattern)) end

local ROOT = ((debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or ".") .. "/../.."):gsub("\\", "/")

local GOOD = [[
ARG TAG=3.22
FROM alpine:${TAG} AS toolchain
RUN apk add curl
FROM alpine:${TAG}
LABEL org.hecate.lua-version="5.5"
RUN apk add --no-cache \
    ca-certificates
USER hecate
]]

function T:test_a_compliant_dockerfile_has_no_problem() self:assert_equal(0, #dockerfile.check("d", GOOD)) end

function T:test_parse_joins_continuations_and_splits_stages()
  local parsed = dockerfile.parse(GOOD)
  self:assert_equal(2, #parsed.stages)
  self:assert_equal("ARG TAG=3.22", parsed.preamble[1])
  self:assert_equal("RUN apk add --no-cache  ca-certificates", parsed.stages[2].lines[2])
end

function T:test_an_unpinned_base_image_is_reported()
  local problems = dockerfile.check("d", (GOOD:gsub("alpine:%${TAG}", "alpine:latest")))
  self:assert_equal(2, #problems)
  matches(self, problems[1], "not pinned")
  local untagged = dockerfile.check("d", (GOOD:gsub("FROM alpine:%${TAG}\n", "FROM alpine\n")))
  matches(self, untagged[1], "not pinned")
end

function T:test_a_digest_pins_an_image()
  local text = (GOOD:gsub("FROM alpine:%${TAG}\n", "FROM alpine@sha256:" .. ("a"):rep(64) .. "\n"))
  self:assert_equal(0, #dockerfile.check("d", text))
end

function T:test_a_variable_without_default_is_reported()
  local problems = dockerfile.check("d", (GOOD:gsub("ARG TAG=3.22\n", "")))
  matches(self, problems[1], "without a default")
end

function T:test_the_final_stage_must_be_non_root()
  matches(self, dockerfile.check("d", (GOOD:gsub("USER hecate\n", "")))[1], "non%-root")
  matches(self, dockerfile.check("d", (GOOD:gsub("USER hecate", "USER root")))[1], "non%-root")
  matches(self, dockerfile.check("d", (GOOD:gsub("USER hecate", "USER 0")))[1], "non%-root")
end

function T:test_the_label_and_the_certificates_are_required()
  matches(self, dockerfile.check("d", (GOOD:gsub("LABEL [^\n]*\n", "")))[1], "org.hecate.lua%-version")
  matches(self, dockerfile.check("d", (GOOD:gsub("ca%-certificates", "curl")))[1], "ca%-certificates")
end

function T:test_a_file_without_from_is_reported() matches(self, dockerfile.check("d", "RUN true\n")[1], "no FROM") end

function T:test_bake_dockerfiles_expands_the_variants()
  local paths = dockerfile.bake_dockerfiles([[
target "image" { context = "." }
target "runtime" {
  name       = "runtime-${variant}"
  matrix     = { variant = ["debian", "alpine"] }
  dockerfile = "docker/runtime/Dockerfile.${variant}"
}
]])
  self:assert_equal("docker/runtime/Dockerfile.debian,docker/runtime/Dockerfile.alpine", table.concat(paths, ","))
end

function T:test_the_images_of_the_repository_comply()
  local report = task.run({ root = ROOT })
  self:assert_equal("", table.concat(report.problems, "\n"))
  self:assert_equal(4, #report.data)
end

return T

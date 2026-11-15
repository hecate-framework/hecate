"""Validates OpenAPI documents against the official OpenAPI 3.1 JSON Schema (ADR 0031).

Development-only helper of `lua tools/run.lua validate-openapi`; never shipped.

    python validate_openapi.py --resources DIR --schema FILE [--schema FILE ...] DOCUMENT...

Needs `jsonschema` (Draft202012Validator, with `referencing`). Formats are not asserted (the 2020-12 default). No
network access: the 2020-12 meta-schemas come from `jsonschema-specifications`, and every other schema the official
files reference (`dialect`, `meta`, `schema`, `schema-base` of oas/3.1) is registered from the JSON files under
--resources, by its `$id`.

Output: one line per document and schema (`ok <name>` or `invalid <name>: <n> error(s)`), then one indented line per
error: the JSON Pointer of the failing value and the message of the validator. Exit code: 0 all valid, 1 a document is
invalid, 2 usage or environment error.
"""
import json
import os
import sys

MAX_MESSAGE = 200


def pointer(path):
    return "/" + "/".join(str(p).replace("~", "~0").replace("/", "~1") for p in path) if path else "(root)"


def load(path):
    with open(path, "rb") as handle:
        return json.loads(handle.read().decode("utf-8"))


def main(argv):
    resources, schemas, documents = None, [], []
    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg == "--resources" and index + 1 < len(argv):
            resources = argv[index + 1]
            index += 2
        elif arg == "--schema" and index + 1 < len(argv):
            schemas.append(argv[index + 1])
            index += 2
        else:
            documents.append(arg)
            index += 1
    if resources is None or not schemas or not documents:
        sys.stderr.write("usage: validate_openapi.py --resources DIR --schema FILE [--schema FILE ...] DOCUMENT...\n")
        return 2
    try:
        from jsonschema import Draft202012Validator
        from jsonschema_specifications import REGISTRY
        from referencing import Resource
        from referencing.jsonschema import DRAFT202012
    except ImportError as error:
        sys.stderr.write("jsonschema is not installed: %s\n" % error)
        return 2

    registry = REGISTRY
    for directory, _, names in os.walk(resources):
        for name in sorted(names):
            if name.endswith(".md"):
                continue
            try:
                schema = load(os.path.join(directory, name))
            except (ValueError, OSError):
                continue
            if isinstance(schema, dict) and isinstance(schema.get("$id"), str):
                registry = registry.with_resource(
                    schema["$id"], Resource.from_contents(schema, default_specification=DRAFT202012))

    failed = False
    for schema_path in schemas:
        schema = load(schema_path)
        Draft202012Validator.check_schema(schema)
        validator = Draft202012Validator(schema, registry=registry)
        label = os.path.basename(os.path.dirname(schema_path)) + "/" + os.path.basename(schema_path)
        for path in documents:
            name = os.path.basename(path)
            try:
                document = load(path)
            except (ValueError, OSError) as error:
                print("invalid %s [%s]: not readable JSON (%s)" % (name, label, type(error).__name__))
                failed = True
                continue
            errors = sorted(validator.iter_errors(document), key=lambda e: (pointer(e.absolute_path), e.message))
            if not errors:
                print("ok %s [%s]" % (name, label))
                continue
            failed = True
            print("invalid %s [%s]: %d error(s)" % (name, label, len(errors)))
            for error in errors:
                message = error.message if len(error.message) <= MAX_MESSAGE else error.message[:MAX_MESSAGE] + "..."
                print("  %s: %s" % (pointer(error.absolute_path), message))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

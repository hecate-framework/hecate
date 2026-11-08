-- Represent an instance for a response: declared attributes only, enumeration members as names, then encode.
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")

local Status = core.enumeration("AccountStatus", { "active", "disabled" })

local Account = core.class("Account", nil, { implements = { schema.Representable } })
function Account.schema()
  return schema.object({
    name = schema.string(),
    status = schema.enumeration(Status),
    tags = schema.array(schema.string()),
  })
end
core.finalise(Account)

local accounts = schema.of(Account)
local _, account = accounts:build({ name = "Ada", status = "active", tags = {} })
account.password = "secret" -- not declared by the schema: it never reaches the response

local plain = accounts:represent(account)
print(plain.status, plain.password, core.is_instance_of(plain, Account))
print(json.encode(plain.tags), json.encode(plain.name))

-- A cycle in the object graph ends with an error that names the limit, instead of a hang.
local Node = core.class("Node", nil, { implements = { schema.Representable } })
function Node.schema() return schema.object({ next = schema.optional(schema.of(Node)) }) end
core.finalise(Node)

local node = core.allocate(Node)
node.next = node
local ok, err = pcall(schema.of(Node).represent, schema.of(Node), node)
print(ok, err.context.violations[1].code)
-- Prints: active	nil	false
-- []	"Ada"
-- false	depth_limit

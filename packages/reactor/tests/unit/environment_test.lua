local test = require("harness.test")
local environment = require("hecate.reactor.internal.environment")
local T = test.Case("EnvironmentTest")

function T:test_additions_win_over_the_inherited_environment_and_the_list_is_sorted()
  local list = environment.merge({ B = "1", A = "2" }, { B = "3", C = "4" }, false)
  self:assert_equal("A=2,B=3,C=4", table.concat(list, ","))
end

function T:test_names_are_case_sensitive_on_unix()
  local list = environment.merge({ Path = "x" }, { PATH = "y" }, false)
  self:assert_equal("PATH=y,Path=x", table.concat(list, ","))
end

function T:test_windows_names_compare_without_case_and_keep_the_existing_spelling()
  local list = environment.merge({ Path = "x", SystemRoot = "C:\\Windows" }, { PATH = "y", systemroot = "D:\\" }, true)
  self:assert_equal("Path=y,SystemRoot=D:\\", table.concat(list, ","))
end

function T:test_the_dropped_variable_is_removed_unless_added_again()
  local inherited = { HECATE_IPC_FD = "3", KEEP = "1" }
  self:assert_equal("KEEP=1", table.concat(environment.merge(inherited, {}, false, "HECATE_IPC_FD"), ","))
  self:assert_equal("HECATE_IPC_FD=3,KEEP=1",
    table.concat(environment.merge(inherited, { HECATE_IPC_FD = "3" }, false, "HECATE_IPC_FD"), ","))
  -- On Windows the inherited spelling is dropped whatever its case; the addition keeps its own.
  local windows = environment.merge({ Hecate_Ipc_Fd = "9" }, { HECATE_IPC_FD = "3" }, true, "HECATE_IPC_FD")
  self:assert_equal("HECATE_IPC_FD=3", table.concat(windows, ","))
end

return T

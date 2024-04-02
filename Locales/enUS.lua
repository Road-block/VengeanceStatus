local addonName, VGS = ...
local L = LibStub("AceLocale-3.0"):NewLocale(addonName, "enUS", true)
if not L then return end
  --L["Term"] = true -- Example
L.CMD_LOCK = "Lock"
L.CMD_SHOW = "Show/Hide"
L.CMD_RESET = "Reset Position"
L["Stats"] = true
L["History"] = true
L["Hide from Minimap"] = true
L["Width"] = true
L["Height"] = true
L["Border"] = true
L["Set the statusbar border."] = true
L["|cffff7f00Click|r to report last stats"] = true
L["|cffff7f00Right Click|r to open options"] = true
L["|cffff7f00Middle Click|r to toggle lock"] = true

VGS.L = L
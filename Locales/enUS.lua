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
L["Font"] = true
L["Drag to Move. Right-click to Lock."] = true
L["Statusbar Options"] = true
L["Border Size"] = true
L["Border Color"] = true
L["Fill Color"] = true
L["Text Color"] = true
L["Hide Statusbar"] = true
L["API Doc"] = true
L["Use VengeanceStatus as an LDB feed & API only"] = true
L["Flash Bar"] = true
L["Set the % of Max Vengeance that flashes the bar."] = true
L["Last Fight Max"] = true
L["Historical Max"] = true
L["|cffff7f00Click|r to report last stats"] = true
L["|cffff7f00Right Click|r to open options"] = true
L["|cffff7f00Middle Click|r to toggle lock"] = true
L["|cffff7f00Shift Click|r to hide the bar"] = true
L.APIDOC = [[

--Using VengeanceStatus as a data source

-- Assuming MyAddon is the addon object or a table
-- 1. Create a method that will receive values
function MyAddon:VengeanceUpdate(vng,vngMax,vngDecay)
  -- will receive current +AP, AP cap and AP decay / sec
end

-- 2. Register with VengeanceStatus for updates
-- Notice the dot notation, it's important registration is done
-- with AddonObject, AddonObject.Callback passed in
VengeanceStatus:GetVengeanceUpdates(MyAddon,MyAddon.VengeanceUpdate)

]]

VGS.L = L

local _
local addonName, addon = ...
local addon = LibStub("AceAddon-3.0"):NewAddon(addon, addonName, "AceConsole-3.0", "AceHook-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceBucket-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local AC = LibStub("AceConfig-3.0")
local ACD = LibStub("AceConfigDialog-3.0")
local ADBO = LibStub("AceDBOptions-3.0")
local LDBO = LibStub("LibDataBroker-1.1"):NewDataObject(addonName)
local LDI = LibStub("LibDBIcon-1.0")
local LSM = LibStub("LibSharedMedia-3.0",true)
local LS = LibStub("LibSink-2.0")

local RAID_CLASS_COLORS = (_G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS)
local wowver, wowbuild, wowbuildate, wowtocver = GetBuildInfo()
addon._DEBUG = false
addon._cata = wowtocver > 40000 and wowtocver < 50000
if not addon._cata then -- cata beta workaround build 53750, wow_project_id not updated yet
  addon._classic = _G.WOW_PROJECT_ID and (_G.WOW_PROJECT_ID == _G.WOW_PROJECT_CLASSIC) or false
  addon._bcc = _G.WOW_PROJECT_ID and (_G.WOW_PROJECT_ID == _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC) or false
  addon._wrath = _G.WOW_PROJECT_ID and (_G.WOW_PROJECT_ID == _G.WOW_PROJECT_WRATH_CLASSIC) or false
end
addon._version = C_AddOns.GetAddOnMetadata(addonName,"Version")
addon._addonName = addonName.." v"..addon._version
addon._addonNameC = LIGHTBLUE_FONT_COLOR:WrapTextInColorCode(addon._addonName)
addon._playerClassLoc, addon._playerClass, addon._playerClassID = UnitClass("player")
addon._playerRaceLoc, addon._playerRace, addon._playerRaceID = UnitRace("player")
local _p = {}
_p.spellData = {
  PALADIN = 84839,
  DRUID = 84840,
  WARRIOR = 93098,
  DEATHKNIGHT = 93099,
  buffID = 76691,
  vigiID = 50720,
}
_p.cleu_parser = CreateFrame("Frame")
_p.cleu_parser.OnEvent = function(frame, event, ...)
  addon.HandleCombatEvent(addon,event,...)
end
_p.cleu_parser:SetScript("OnEvent", _p.cleu_parser.OnEvent)
_p.unit_events = CreateFrame("Frame")
_p.unit_events.OnEvent = function(frame, event, ...)
  return addon[event] and addon[event](addon,event,...)
end
_p.unit_events:SetScript("OnEvent", _p.unit_events.OnEvent)

_p.consolecmd = {type = "group", handler = addon, args = {
  show = {type="execute",name=_G.SHOW,desc=L.CMD_SHOW,func=function()end,order=1},
  lock = {type="execute",name=L.CMD_LOCK,desc=L.CMD_LOCK,func=function()end,order=2},
  reset = {type="execute",name=_G.RESET,desc=L.CMD_RESET,func=function()end,order=3},
}}

-- UTILS
_p.denominations = {{"T",1e12},{"G",1e9},{"M",1e6},{"k",1e3}}--,{"h",1e2},{"da",10}}
local function formatBigNumber(n,uncap)
  local uncap = uncap or _p.denominations[#_p.denominations][2]
  if n <= uncap then return string.format("%d",n) end
  for _,d in ipairs(_p.denominations) do
    local v = n/d[2]
    if v >=1 then
      return string.format("%.1f %s",v,d[1])
    end
  end
end
local function formatTime(date_fmt, time_fmt, epoch)
  local epoch = epoch or GetServerTime()
  local date_fmt = date_fmt or "%b-%d" -- Mon-dd, alt example: "%Y-%m-%d" > YYYY-MM-DD
  local time_fmt = time_fmt or "%H:%M:%S" -- HH:mm:SS
  local d = date(date_fmt,epoch)
  local t = date(time_fmt,epoch)
  local timestamp = string.format("%s %s",d,t)
  return tostring(epoch), timestamp
end
local function table_count(t)
  local count = 0
  for k,v in pairs(t) do
    count = count +1
  end
  return count
end
local function setDecay()
  if _p.vengeance and _p.vengeance > 0 then
    _p.vengeanceDecay = _p.vengeance*0.1/2
  else
    _p.vengeanceDecay = nil
  end
end
local function calcBaseHP(trusted,newLevel)
  local statStorage = addon:StatStorage(newLevel)
  local _,effectiveStam = UnitStat("player",LE_UNIT_STAT_STAMINA)
  local baseStam = math.min(20, effectiveStam)
  local moreStam = effectiveStam - baseStam
  local hpFromStam = (baseStam + (moreStam*UnitHPPerStamina("player")))*GetUnitMaxHealthModifier("player")
  local baseHP = UnitHealthMax("player")-hpFromStam
  if (not statStorage.baseHP) or (not statStorage.trusted) then
    statStorage.baseHP = baseHP
    statStorage.trusted = trusted or false
  end
  _p.baseHP = statStorage.trusted and statStorage.baseHP or baseHP
  addon:GetVengeanceMax()
  return _p.baseHP
end

-- METHODS
_p.bar_defaults = {
  width = 225,
  height = 18,
  point = "CENTER",
  relPoint = "CENTER",
  x = 0,
  y = -80,
  texture = "Interface\\TargetingFrame\\UI-StatusBar",
  border = "Interface\\CastingBar\\UI-CastingBar-Border-Small",
  spark = "Interface\\CastingBar\\UI-CastingBar-Spark",
  flash = "Interface\\CastingBar\\UI-CastingBar-Flash-Small",
  font = "SystemFont_Shadow_Med1_Outline",
  color = {0.5,0.5,0.5,1},
  fillColor = {0.85,0.0,0.0,0.85},
  bgColor = {0.1,0.1,0.1,1},
  iconSize = 18,
}
function addon:createUI()
  if _p.Bar then return _p.Bar end

  local VengeanceStatusBarMixin = {}
  function VengeanceStatusBarMixin:SetCenterText(text)
    self.textCenter:SetText(text or "")
  end
  function VengeanceStatusBarMixin:SetLeftText(text)
    self.textLeft:SetText(text or "")
  end
  function VengeanceStatusBarMixin:SetRightText(text)
    self.textRight:SetText(text or "")
  end
  function VengeanceStatusBarMixin:SetIconLeft(fileid)
    if fileid then
      self.iconLeft:SetTexture(fileid)
      self.iconLeft:Show()
    else
      self.iconLeft:Hide()
    end
  end
  function VengeanceStatusBarMixin:SetIconRight(fileid)
    if fileid then
      self.iconRight:SetTexture(fileid)
      self.iconRight:Show()
    else
      self.iconRight:Hide()
    end
  end
  function VengeanceStatusBarMixin:StartFlashing()
    self.flash:Show()
    self.flash.anim:Play()
  end
  function VengeanceStatusBarMixin:StopFlashing()
    self.flash.anim:Stop()
    self.flash:Hide()
  end
  function VengeanceStatusBarMixin:Lock()
    self:EnableMouse(false)
    self:SetMovable(false)
    self.locked = true
    addon.db.char.barOptions.point, _, addon.db.char.barOptions.relPoint, addon.db.char.barOptions.x, addon.db.char.barOptions.y = self:GetPoint()
  end
  function VengeanceStatusBarMixin:Unlock()
    self:EnableMouse(true)
    self:SetMovable(true)
    self:SetScript("OnMouseDown", function(f,button)
      self:StartMoving()
    end)
    self:SetScript("OnMouseUp", function(f,button)
      self:StopMovingOrSizing()
    end)
    self:SetScript("OnHide", function(f)
      self:StopMovingOrSizing()
    end)
    self:SetScript("OnLeave", function(f)
      self:StopMovingOrSizing()
    end)
    self.locked = false
  end
  function VengeanceStatusBarMixin:SetBorder(border)
    self.border:SetTexture(border)
  end
  function VengeanceStatusBarMixin:ApplySettings(method, ...)
    if self[method] then
      self[method](self,...)
    end
  end
  function VengeanceStatusBarMixin:LoadDefaults()

  end
  function VengeanceStatusBarMixin:UpdateValues(v,vMax,...)
    self:SetMinMaxValues(0,vMax)
    self:SetValue(v)
    local textL,textR,textC = ...
    local barWidth = self:GetWidth()
    local sparkPos = (vMax > 0) and v/vMax * barWidth
    if sparkPos then
      self.spark:SetPoint("CENTER",self, "LEFT", sparkPos, 0)
      self.spark:Show()
    end
    if v >= (vMax*.95) then
      self:StartFlashing()
    elseif v > 0 then
      self:StopFlashing()
    else
      textL,textC = nil, nil
      self.spark:Hide()
      self:StopFlashing()
    end
    if barWidth < 120 then
      self.textLeft:SetWidth(math.floor(barWidth/2))
      self.textRight:SetWidth(math.floor(barWidth/2))
      textL = textC
      textC = nil
    else
      self.textLeft:SetWidth(math.floor(barWidth/3))
      self.textRight:SetWidth(math.floor(barWidth/3))
    end
    self:SetLeftText(textL)
    self:SetRightText(textR)
    self:SetCenterText(textC)
  end
  local barOpt = self:GetBarOptions()
  barOpt = setmetatable(barOpt or {}, {__index = function(t,k)
    return _p.bar_defaults[k]
  end})

  local bar = CreateFrame("StatusBar",nil,UIParent)
  bar:SetSize(barOpt.width,barOpt.height)
  bar:SetPoint(barOpt.point, UIParent, barOpt.relPoint, barOpt.x,barOpt.y)
  bar:SetStatusBarTexture(barOpt.texture)
  bar:SetStatusBarColor(unpack(barOpt.color))
  bar:SetColorFill(unpack(barOpt.fillColor))
  bar:SetFillStyle("STANDARD")
  bar:SetMinMaxValues(0,100)
  bar:SetValue(0)
  bar.locked = true
  local drawLayer = "BORDER"
  bar:SetDrawLayerEnabled(drawLayer,true)
  drawLayer = "BACKGROUND"
  bar.background = bar:CreateTexture()
  bar.background:SetAllPoints()
  bar.background:SetDrawLayer(drawLayer)
  bar.background:SetColorTexture(unpack(barOpt.bgColor))
  drawLayer = "ARTWORK"
  bar.border = bar:CreateTexture()
  bar.border:SetTexture(barOpt.border)
  bar.border:SetPoint("TOPLEFT",bar,"TOPLEFT",-34,26)
  bar.border:SetPoint("BOTTOMRIGHT",bar,"BOTTOMRIGHT",34,-26)
  bar.border:SetDrawLayer(drawLayer,1)
  --bar.border:Hide()
  bar.iconLeft = bar:CreateTexture()
  bar.iconLeft:SetSize(barOpt.iconSize,barOpt.iconSize)
  bar.iconLeft:SetPoint("RIGHT",bar,"LEFT",2,0)
  bar.iconLeft:SetDrawLayer(drawLayer,2)
  bar.iconLeft:Hide()
  bar.iconRight = bar:CreateTexture()
  bar.iconRight:SetSize(barOpt.iconSize,barOpt.iconSize)
  bar.iconRight:SetPoint("LEFT",bar,"RIGHT",-3,0)
  bar.iconRight:SetDrawLayer(drawLayer,2)
  bar.iconRight:Hide()
  bar.textLeft = bar:CreateFontString(nil,drawLayer,barOpt.font)
  bar.textLeft:SetSize(math.floor(barOpt.width/3),16)
  bar.textLeft:SetPoint("LEFT")
  bar.textLeft:SetJustifyH("LEFT")
  bar.textCenter = bar:CreateFontString(nil,drawLayer,barOpt.font)
  bar.textCenter:SetSize(math.floor(barOpt.width/3),16)
  bar.textCenter:SetPoint("CENTER")
  bar.textCenter:SetJustifyH("CENTER")
  bar.textRight = bar:CreateFontString(nil,drawLayer,barOpt.font)
  bar.textRight:SetSize(math.floor(barOpt.width/3),16)
  bar.textRight:SetPoint("RIGHT")
  bar.textRight:SetJustifyH("RIGHT")
  drawLayer = "OVERLAY"
  bar.spark = bar:CreateTexture()
  bar.spark:SetSize(32,32)
  bar.spark:SetPoint("CENTER",bar,0,2)
  bar.spark:SetTexture(barOpt.spark)
  bar.spark:SetDrawLayer(drawLayer)
  bar.spark:SetBlendMode("ADD")
  bar.spark:Hide()
  bar.flash = bar:CreateTexture()
  bar.flash:SetPoint("TOPLEFT",bar.border,"TOPLEFT",0,0)
  bar.flash:SetPoint("BOTTOMRIGHT",bar.border,"BOTTOMRIGHT",0,0)
  bar.flash:SetTexture(barOpt.flash)
  bar.flash:SetDrawLayer(drawLayer)
  bar.flash:SetBlendMode("ADD")
  bar.flash:Hide()
  bar.flash.anim = bar.flash:CreateAnimationGroup()
  bar.flash.anim:SetLooping("BOUNCE")
  local alpha = bar.flash.anim:CreateAnimation("ALPHA")
  alpha:SetFromAlpha(0)
  alpha:SetToAlpha(0.75)
  alpha:SetDuration(1.0)

  Mixin(bar,VengeanceStatusBarMixin)

  _p.Bar = bar
  return _p.Bar
end

function addon:GetBarOptions()
  return CopyTable(self.db.char.barOptions)
end

function addon:ToggleOptionsFrame()
  if ACD.OpenFrames[addonName] then
    ACD:Close(addonName)
  else
    ACD:Open(addonName,"general")
  end
end

function addon:ToggleLocked(status)
  if _p.Bar then
    if status == nil then
      _p.Bar[(_p.Bar.locked and "Unlock" or "Lock")](_p.Bar)
    elseif status == true then
      _p.Bar:Lock()
    else
      _p.Bar:Unlock()
    end
  end
end

function addon:Report()

end

function addon:RefreshConfig()
end

function addon:GetOptionTable()
  if _p.Options and type(_p.Options)=="table" then return _p.Options end
  _p.Options = {type = "group", handler = addon, args = {
    general = {
      type = "group",
      name = _G.OPTIONS,
      childGroups = "tab",
      args = {
        main = {
          type = "group",
          name = _G.GENERAL,
          order = 1,
          args = { },
        },
        stats = {
          type = "group",
          name = L["Stats"],
          order = 2,
          args = { },
        },
        history = {
          type = "group",
          name = L["History"],
          order = 3,
          args = { },
        },
      }
    }
  }}
  _p.Options.args.general.args.main.args.lock = {
    type = "toggle",
    name = L.CMD_LOCK,
    desc = L.CMD_LOCK,
    order = 20,
    get = function() return not not addon.db.char.lock end,
    set = function(info, val)
      addon.db.char.lock = not addon.db.char.lock
      addon:ToggleLocked(addon.db.char.lock)
    end,
  }
  _p.Options.args.general.args.main.args.width = {
    type = "input",
    name = L["Width"],
    desc = L["Width"],
    order = 25,
    get = function() return tostring(addon.db.char.barOptions.width) end,
    set = function(info, val)
      addon.db.char.barOptions.width = tonumber(val)
      _p.Bar:ApplySettings("SetWidth",addon.db.char.barOptions.width)
    end,
  }
  _p.Options.args.general.args.main.args.height = {
    type = "input",
    name = L["Height"],
    desc = L["Height"],
    order = 26,
    get = function() return tostring(addon.db.char.barOptions.height) end,
    set = function(info, val)
      addon.db.char.barOptions.height = tonumber(val)
      _p.Bar:ApplySettings("SetHeight",addon.db.char.barOptions.height)
    end,
  }
  _p.Options.args.general.args.main.args.border = {
    type = "select",
    name = L["Border"],
    desc = L["Set the statusbar border."],
    order = 30,
    get = function(info) return addon.db.char.barOptions.border end,
    set = function(info, value)
        addon.db.char.barOptions.border = value
        _p.Bar:ApplySettings("SetBorder",LSM:Fetch("border",addon.db.char.barOptions.border))
    end,
    values = LSM:HashTable("border"),
    dialogControl = "LSM30_Statusbar",
  }
  _p.Options.args.general.args.main.args.minimap = {
    type = "toggle",
    name = L["Hide from Minimap"],
    desc = L["Hide from Minimap"],
    order = 120,
    get = function() return not not addon.db.profile.minimap.hide end,
    set = function(info, val)
      addon.db.profile.minimap.hide = not addon.db.profile.minimap.hide
    end,
  }
  return _p.Options
end

function addon:StatStorage(newLevel)
  local expansion = GetClassicExpansionLevel()
  local playerLevel = UnitLevel("player")
  if newLevel and newLevel > playerLevel then
    playerLevel = newLevel
  end
  VengeanceStatusDB.STATS = VengeanceStatusDB.STATS or {}
  VengeanceStatusDB.STATS[expansion] = VengeanceStatusDB.STATS[expansion] or {}
  VengeanceStatusDB.STATS[expansion][addon._playerClass] = VengeanceStatusDB.STATS[expansion][addon._playerClass] or {}
  VengeanceStatusDB.STATS[expansion][addon._playerClass][addon._playerRace] = VengeanceStatusDB.STATS[expansion][addon._playerClass][addon._playerRace] or {}
  VengeanceStatusDB.STATS[expansion][addon._playerClass][addon._playerRace][playerLevel] = VengeanceStatusDB.STATS[expansion][addon._playerClass][addon._playerRace][playerLevel] or {}
  return VengeanceStatusDB.STATS[expansion][addon._playerClass][addon._playerRace][playerLevel]
end

function addon:HistoryStorage()
end

function addon:startProcessing()
  _p.baseHP = calcBaseHP()
  self:RegisterEvent("PLAYER_REGEN_DISABLED")
  self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
  self:RegisterEvent("PLAYER_DEAD")
  self:RegisterEvent("PLAYER_LEVEL_UP")
  if addon._playerClass == "DRUID" then
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
  end
  _p.unit_events:RegisterUnitEvent("UNIT_STATS","player")
  _p.unit_events:RegisterUnitEvent("UNIT_AURA","player")
  _p.cleu_parser:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  self:GetVengeance()
end

function addon:stopProcessing()
  self:UnregisterEvent("PLAYER_REGEN_DISABLED")
  _p.unit_events:UnregisterEvent("UNIT_STATS","player")
  _p.unit_events:UnregisterEvent("UNIT_AURA","player")
  _p.cleu_parser:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  self:GetVengeance(0)
end

function addon:DispatchUpdates(feed)
  local veng, vengMax, vengDecay = (_p.vengeance or 0), (_p.vengeanceMax or 0), (_p.vengeanceDecay or 0)
  if veng == 0 then
    _p.vengeanceDecay = nil
    vengDecay = 0
  end
  local vengShort, vengMaxShort = formatBigNumber(veng,1000),formatBigNumber(vengMax,1000)
  local perc = vengMax > 0 and RoundToSignificantDigits(veng*100/vengMax,1) or 0
  local LDBtext = string.format("%s/%s (%.1f %%)",vengShort,vengMaxShort,perc)
  if UnitAffectingCombat("player") or _p.decayTimer then
    LDBO.text = LDBtext
  end
  if _p.Bar then
    _p.Bar:UpdateValues(veng,vengMax, vengShort,vengMaxShort, string.format("%.1f %%",perc))
  end
  if _p.callbacks and table_count(_p.callbacks) > 0 then
    _p.CBR:TriggerEvent("VENGEANCE_UPDATE",veng,vengMax,vengDecay)
  end
end

function addon:DecayTimer()
  if _p.vengeance and (_p.vengeance > 0) then
    self:DispatchUpdates()
  else
    LDBO.text = _p.spellInfo.name
    self:CancelTimer(_p.decayTimer)
    _p.decayTimer = nil
  end
end

-- INSTANTIATION
local defaults = {
  profile = {
    minimap = {hide = false,},
  },
  char = {
    lock = true,
    barOptions = {},
  },
}
do
  for k,v in pairs(_p.bar_defaults) do
    defaults.char.barOptions[k] = v
  end
end
function addon:OnInitialize() -- ADDON_LOADED
  _p.spellID = _p.spellData[addon._playerClass]
  if not _p.spellID then return end
  _p.spellInfo = {}
  _p.spellInfo.name,_, _p.spellInfo.icon = GetSpellInfo(_p.spellID)

  self.db = LibStub("AceDB-3.0"):New("VengeanceStatusDB", defaults)
  _p.Options = self:GetOptionTable()
  _p.Options.args.profile = ADBO:GetOptionsTable(self.db)
  _p.Options.args.profile.guiHidden = true
  _p.Options.args.profile.cmdHidden = true
  AC:RegisterOptionsTable(addonName.."_cmd", _p.consolecmd, {addonName:lower(),"vgs"})
  AC:RegisterOptionsTable(addonName, _p.Options)
  self.blizzoptions = ACD:AddToBlizOptions(addonName,nil,nil,"general")
  self.blizzoptions.profile = ACD:AddToBlizOptions(addonName, "Profiles", addonName, "profile")
  self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
  self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
  self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")

  LDBO.type = "data source"
  LDBO.text = _p.spellInfo.name
  LDBO.label = addon._addonNameC
  LDBO.icon = _p.spellInfo.icon
  LDBO.OnClick = addon.OnLDBClick
  LDBO.OnTooltipShow = addon.OnLDBTooltipShow
  LDI:Register(addonName, LDBO, addon.db.profile.minimap)
end

function addon:OnEnable() -- PLAYER_LOGIN
  _p.spellID = _p.spellData[addon._playerClass]
  if not _p.spellID then return end
  _p.Bar = self:createUI()
  if IsPlayerSpell(_p.spellID) then
    self:startProcessing()
  else
    _p.spell_learned_bucket = self:RegisterBucketEvent("LEARNED_SPELL_IN_TAB",1.0,"LEARNED_SPELL_IN_TAB")
    return
  end
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function addon.OnLDBClick(obj,button)
  if button == "LeftButton" then
    addon:Report()
  elseif button == "RightButton" then
    addon:ToggleOptionsFrame()
  elseif button == "MiddleButton" then
    addon:ToggleLocked()
  end
end
function addon.OnLDBTooltipShow(tooltip)
  tooltip = tooltip or GameTooltip
  local title = addon._addonNameC
  tooltip:SetText(title)
  local hint = L["|cffff7f00Click|r to report last stats"]
  tooltip:AddLine(hint)
  hint = L["|cffff7f00Right Click|r to open options"]
  tooltip:AddLine(hint)
  hint = L["|cffff7f00Middle Click|r to toggle lock"]
  tooltip:AddLine(hint)
end

-- EVENTS
_p.vengeance_buff_instance = {}
function addon:LEARNED_SPELL_IN_TAB(args)
  if type(args) == "table" then
    for spellID in pairs(args) do
      if spellID == _p.spellID then
        self:startProcessing()
        self:UnregisterBucketEvent(_p.spell_learned_bucket)
        break
      end
    end
  end
end
function addon:ACTIVE_TALENT_GROUP_CHANGED(event,...)
  local toSpec, fromSpec = ...
  if IsPlayerSpell(_p.spellID) then
    self:startProcessing()
  else
    self:stopProcessing()
  end
end
function addon:UPDATE_SHAPESHIFT_FORM(event)
  local formid = GetShapeshiftFormID()
  if formid and (formid == CAT_FORM) then
    self:stopProcessing()
  elseif formid and (formid == BEAR_FORM) then
    self:startProcessing()
  end
end
function addon:PLAYER_ENTERING_WORLD(event,...)
  local isLogin,isReload = ...
  if UnitAffectingCombat("player") then
    self:GetVengeanceMax()
    self:GetVengeance()
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
  end
end
function addon:PLAYER_REGEN_DISABLED(event)
  self:RegisterEvent("PLAYER_REGEN_ENABLED")
end
function addon:PLAYER_REGEN_ENABLED(event)
  if not _p.vengeance or (_p.vengeance == 0) then
    LDBO.text = _p.spellInfo.name
  else
    if not _p.decayTimer then
      _p.decayTimer = self:ScheduleRepeatingTimer("DecayTimer",2.0)
    end
  end
end
function addon:PLAYER_DEAD()
  calcBaseHP(true)
end
function addon:PLAYER_LEVEL_UP(event,...)
  local newLevel = ...
  calcBaseHP(nil,newLevel)
end
function addon:UNIT_STATS(event)
  self:GetVengeanceMax()
  self:GetVengeance()
end
function addon:UNIT_AURA(event,unit,...)
  local args = ...
  if args.isFullUpdate then
    self:GetVengeance()
    return
  end
  if args.addedAuras then
    for k,auraData in pairs(args.addedAuras) do
      if auraData.name and auraData.name == _p.spellInfo.name then
        _p.vengeance_buff_instance[auraData.auraInstanceID]=true
        self:GetVengeance(auraData.points and auraData.points[1] or 0)
      end
    end
  end
  if args.updatedAuraInstanceIDs then
    for k, instanceID in pairs(args.updatedAuraInstanceIDs) do
      local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, instanceID)
      if auraData and auraData.name and (auraData.name == _p.spellInfo.name) then
        _p.vengeance_buff_instance[instanceID]=true
        self:GetVengeance(auraData.points and auraData.points[1] or 0)
      end
    end
  end
  if args.removedAuraInstanceIDs then
    for k, instanceID in pairs(args.removedAuraInstanceIDs) do
      if _p.vengeance_buff_instance[instanceID] then
        self:GetVengeance(0)
        _p.vengeance_buff_instance[instanceID] = nil
      end
    end
  end
end
local CombatLog_Object_IsA = _G.CombatLog_Object_IsA
local CombatLogGetCurrentEventInfo = _G.CombatLogGetCurrentEventInfo
local COMBATLOG_FILTER_HOSTILE_PVE = bit.bor(
  COMBATLOG_OBJECT_AFFILIATION_PARTY,
  COMBATLOG_OBJECT_AFFILIATION_RAID,
  COMBATLOG_OBJECT_AFFILIATION_OUTSIDER,
  COMBATLOG_OBJECT_REACTION_HOSTILE,
  COMBATLOG_OBJECT_REACTION_NEUTRAL,
  COMBATLOG_OBJECT_CONTROL_NPC,
  COMBATLOG_OBJECT_TYPE_PLAYER,
  COMBATLOG_OBJECT_TYPE_NPC,
  COMBATLOG_OBJECT_TYPE_PET,
  COMBATLOG_OBJECT_TYPE_GUARDIAN,
  COMBATLOG_OBJECT_TYPE_OBJECT
  )
local COMBATLOG_FILTER_ME = _G.COMBATLOG_FILTER_ME
local subEvents = {
  ["SWING_DAMAGE"] = true,
  ["SPELL_DAMAGE"] = true,
  ["RANGE_DAMAGE"] = true,
  ["SPELL_PERIODIC_DAMAGE"] = true,
}
if addon._playerClass == "WARRIOR" and IsPlayerSpell(_p.spellData.vigiID) then
  subEvents["SPELL_AURA_APPLIED"] = true
  subEvents["SPELL_AURA_REFRESH"] = true
  subEvents["SPELL_AURA_REMOVED"] = true
end
function addon:HandleCombatEvent(event,...)
  local timestamp, subevent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, arg12, arg13, arg14, arg15, arg16, arg17, arg18, arg19, arg20, arg21, arg22, arg23, arg24  = CombatLogGetCurrentEventInfo()
  if not (subEvents[subevent]) then return end
  if not (sourceFlags and destFlags) then return end
  local is_aura_event = strfind(subevent,"^SPELL_AURA")
  local me_source = CombatLog_Object_IsA(sourceFlags,COMBATLOG_FILTER_ME)
  local spellID
  if not (sourceGUID and destGUID) then return end
  if is_aura_event then
    if not me_source then return end
    spellID = arg12
    if not _p.spellData.vigiID or (spellID ~= _p.spellData.vigiID) then return end
    if (subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH") then
      _p.vigiTargetGUID = destGUID
    else
      if _p.vigiTargetGUID then
        _p.vigiTargetGUID = nil
      end
    end
  end
  local is_damage_event = strfind(subevent,"_DAMAGE$")
  local me_dest = CombatLog_Object_IsA(destFlags,COMBATLOG_FILTER_ME)
  local vigi_dest = _p.vigiTargetGUID and (destGUID == _p.vigiTargetGUID) or false
  local hostile_pve = CombatLog_Object_IsA(sourceFlags,COMBATLOG_FILTER_HOSTILE_PVE)
  if is_damage_event then
    if not (me_dest or vigi_dest) then return end
    if not hostile_pve then return end
    C_Timer.After(1.5,setDecay) -- give
  end
end

-- API
function addon:GetVengeanceUpdates(owner, func, ...)
  if not _p.CBR then
    _p.CBR = _p.CBR or CreateFromMixins(CallbackRegistryMixin)
    _p.CBR:OnLoad()
    _p.CBR:SetUndefinedEventsAllowed(true)
  end
  if not (owner and func) then
    print("Usage: VengeanceStatus:GetVengeanceUpdates(owner, callback)")
    print("--Example")
    print("function MyAddon:VengeanceUpdate(vengeance,vengeanceMax,vengeanceDecayPerSec)")
    print("  -- do something with vengeance values")
    print("end")
    print("-- plug it in")
    print("VengeanceStatus:GetVengeanceUpdates(MyAddon,MyAddon.VengeanceUpdate)")
  end
  assert((type(owner)=="table"),"Usage: VengeanceStatus:GetVengeanceUpdates(owner, callback); owner is not a table")
  assert((type(func)=="function"),"Usage: VengeanceStatus:GetVengeanceUpdates(owner, callback); callback is not a function")
  _p.callbacks = _p.callbacks or {}
  if not _p.callbacks[owner] then
    _p.callbacks[owner] = _p.CBR:RegisterCallback("VENGEANCE_UPDATE",func,owner,...)
    self:DispatchUpdates()
  else
    print(addon._addonNameC..": "..RED_FONT_COLOR:WrapTextInColorCode(format("%s is already registered",tostring(owner))))
  end
end

function addon:GetVengeance(value)
  if not value then
    local auraData = C_UnitAuras.GetPlayerAuraBySpellID(_p.spellData.buffID)
    --local auraData = C_UnitAuras.GetAuraDataBySpellName("player", _p.spellInfo.name)
    if auraData and auraData.points then
      _p.vengeance = auraData.points[1]
      _p.vengeance_buff_instance[auraData.auraInstanceID]=true
    end
  else
    _p.vengeance = value
  end
  self:DispatchUpdates()
  return _p.vengeance or 0
end

function addon:GetVengeanceMax()
  if not _p.baseHP then return end
  local _, effectiveStam = UnitStat("player",LE_UNIT_STAT_STAMINA)
  _p.vengeanceMax = math.floor((_p.baseHP*0.1)+effectiveStam)
  self:DispatchUpdates()
  return _p.vengeanceMax or 0
end

function addon:GetVengeanceDecay()
  return _p.vengeanceDecay or nil
end

function addon:GetBaseHP()
  _p.baseHP = calcBaseHP()
  return _p.baseHP
end

function addon:GetVengeanceSpell()
  local spellid = _p.spellID
  local spellname = _p.spellInfo.name
  local spellicon = _p.spellInfo.icon
  local buffid = _p.spellData.buffID
  _p.vengeance_spell = _p.vengeance_spell or {}
  _p.vengeance_spell.id, _p.vengeance_spell.name, _p.vengeance_spell.icon, _p.vengeance_spell.buff = (spellid or 0), (spellname or ""), (spellicon or 0), buffid
  return _p.vengeance_spell
end

function addon:GetStatusFrame()
  if _p.Bar then
    return _p.Bar
  end
end

_G[addonName] = addon
-- Theorycraft
--[[
4.3.4
Vengeance Cap: baseHP/10 + stamina
Vengeance Decay: Last Value/10 every 2 sec (20sec from last addition to zero out)
Vengeance Add: 33% of first damage taken, 33% of a rolling 2 sec average, if less than cap
Vengeance from Vigilance: 20% of your vigilance target damage taken as if taken by you
                          Same 33% rule applied.
Vigilance range: 30 to apply, 80+ still applies effect (probably unlimited while char visible)
]]
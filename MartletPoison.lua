-- MartletPoison 0.1.0
-- 所见即所涂的涂毒助手。基于 EzPoison (Sunelegy/qyj) 的成熟逻辑改造:
-- 涂抹连招/武器附魔解析/pfUI皮肤移植自 EzPoison, UI 按 MartletPoison README 新设计实现。

-- 命名空间: 本客户端环境已预置全局 MP(字符串), 必须用插件全名并做类型防护
if type(MartletPoison) ~= "table" then MartletPoison = {} end
local MP = MartletPoison

MP.api = getfenv()

-- ==================== 数据表 ====================
-- 种类定义 (id 与 EzPoison 保持一致, 便于对照)
MP.Types = {
	[1]  = { name = "速效毒药",     icon = "Interface\\Icons\\Ability_Poisons" },
	[2]  = { name = "致命毒药",     icon = "Interface\\Icons\\Ability_Rogue_DualWeild" },
	[3]  = { name = "致残毒药",     icon = "Interface\\Icons\\INV_Potion_19" },
	[4]  = { name = "致伤毒药",     icon = "Interface\\Icons\\Ability_PoisonSting" },
	[5]  = { name = "腐蚀毒药",     icon = "Interface\\Icons\\inv_corrosive_01" },
	[6]  = { name = "麻痹毒药",     icon = "Interface\\Icons\\Spell_Nature_NullifyDisease" },
	[7]  = { name = "煽动毒药",     icon = "Interface\\Icons\\Spell_Nature_NullifyPoison" },
	[8]  = { name = "溶解毒药",     icon = "Interface\\Icons\\Spell_Nature_SlowPoison" },
	[9]  = { name = "致密磨刀石",   icon = "Interface\\Icons\\inv_stone_sharpeningstone_05" },
	[10] = { name = "致密平衡石",   icon = "Interface\\Icons\\INV_Stone_WeightStone_05" },
	[11] = { name = "元素磨刀石",   icon = "Interface\\Icons\\inv_stone_02" },
	[12] = { name = "神圣磨刀石",   icon = "Interface\\Icons\\INV_Stone_SharpeningStone_02" },
	[13] = { name = "卓越巫师之油", icon = "Interface\\Icons\\INV_Potion_105" },
	[14] = { name = "卓越法力之油", icon = "Interface\\Icons\\INV_Potion_100" },
	[15] = { name = "神圣巫师之油", icon = "Interface\\Icons\\INV_POTION_26" },
}

-- 各等级物品: { 后缀, 物品ID }, 从高到低 (移植自 EzPoison.GetInventoryID 的硬编码)
MP.RANKS = {
	[1]  = { { " VI", 8928 }, { " V", 8927 }, { " IV", 8926 }, { " III", 6950 }, { " II", 6949 }, { "", 6947 } },
	[2]  = { { " V", 20844 }, { " IV", 8985 }, { " III", 8984 }, { " II", 2893 }, { "", 2892 } },
	[3]  = { { " II", 3776 }, { "", 3775 } },
	[4]  = { { " IV", 10922 }, { " III", 10921 }, { " II", 10920 }, { "", 10918 } },
	[5]  = { { " II", 47409 }, { "", 47408 } },
	[6]  = { { " III", 9186 }, { " II", 6951 }, { "", 5237 } },
	[7]  = { { "", 65032 } },
	[8]  = { { " II", 54010 }, { "", 54009 } },
	[9]  = { { "", 12404 } },
	[10] = { { "", 12643 } },
	[11] = { { "", 18262 } },
	[12] = { { "", 23122 } },
	[13] = { { "", 20749 } },
	[14] = { { "", 20748 } },
	[15] = { { "", 23123 } },
}

-- README 固定顺序: 速效→致命→致伤→致残→麻痹→腐蚀→溶解→煽动 | 致密→神圣→元素→致密平衡 | 油
local ORDER_INDEX = { [1]=1, [2]=2, [4]=3, [3]=4, [6]=5, [5]=6, [8]=7, [7]=8,
	[9]=9, [12]=10, [11]=11, [10]=12, [13]=13, [14]=14, [15]=15 }

-- 武器附魔行文字特征 (名称匹配不到的种类, 移植自 EzPoison.checkNotPoisonActiveSettings)
MP.SIGNS = {
	[9]  = "磨快",
	[10] = "增重",
	[11] = "致命一击",
	[12] = "攻击强度vs亡灵",
	[13] = "卓越巫师之油",
	[14] = "卓越法力之油",
	[15] = "法术伤害vs亡灵",
}

-- 职业过滤 (移植自 EzPoison.vPlayerClass)
local function vPlayerClass(itemName, playerClassEN)
	if type(itemName) ~= "string" then return false end
	local phisicalClasses = { ["WARRIOR"]=1, ["ROGUE"]=1, ["HUNTER"]=1, ["PALADIN"]=1, ["SHAMAN"]=1, ["DRUID"]=1 }
	local magicalClasses  = { ["MAGE"]=1, ["PRIEST"]=1, ["WARLOCK"]=1, ["SHAMAN"]=1, ["DRUID"]=1, ["PALADIN"]=1, ["HUNTER"]=1 }
	if playerClassEN == "ROGUE" and string.find(itemName, "毒药") then return true end
	if magicalClasses[playerClassEN] and string.find(itemName, "油$") then return true end
	if phisicalClasses[playerClassEN] and string.find(itemName, "石$") then return true end
	return false
end

-- ==================== 框架/全局 ====================
local screenWidth = GetScreenWidth()
local screenHeight = GetScreenHeight()
local screenCenterX = screenWidth / 2
local screenCenterY = screenHeight / 2

MP.Frame = CreateFrame("Frame")
MP.Parser = CreateFrame("GameTooltip", "MPParser", nil, "GameTooltipTemplate")

-- 小地图图标 (FuBar 链路) 独立容错: 失败只影响图标, 不拖死面板
MP.ACE = nil
if AceLibrary then
	local okLib, ace = pcall(AceLibrary, "AceAddon-2.0")
	if okLib and ace then
		local okNew, obj = pcall(ace.new, ace, "FuBarPlugin-2.0")
		if okNew then MP.ACE = obj end
	end
end

MP.Frame:RegisterEvent("ADDON_LOADED")
MP.Frame:RegisterEvent("BAG_UPDATE")
MP.Frame:RegisterEvent("UNIT_INVENTORY_CHANGED")

if MP.ACE then
	MP.ACE.name = "MartletPoison"
	MP.ACE.hasIcon = "Interface\\Icons\\Ability_Rogue_DualWeild"
	MP.ACE.defaultMinimapPosition = 210
	MP.ACE.cannotDetachTooltip = true
end

MP.Work = {
	slotInfo = {},      -- GetWeaponEnchantInfo 缓存
	activeMH = nil,     -- 主手当前附魔的种类 id (tooltip 解析)
	activeOH = nil,
	counts = {},        -- 背包各种类总数
	rankCounts = {},    -- 背包各等级数量 [type][rankIdx]
	NAME2ENTRY = {},    -- 小写物品名 -> {t=种类, r=等级序号}
	UsableOrder = {},   -- 排序后的可用种类列表
	Icons = {},         -- [type] = button
	Time = 0,
	Tick = 0,
	iSCasting = nil,
	SkinApplied = nil,
}

local function logMsg(text)
	DEFAULT_CHAT_FRAME:AddMessage("MartletPoison: " .. "|cFFFFFFFF" .. text .. "|r", 0.4, 0.8, 0.4)
end

-- 名字索引 (一次性构建)
local function buildNameIndex()
	for t, ranks in pairs(MP.RANKS) do
		local base = MP.Types[t].name
		for r = 1, table.getn(ranks) do
			MP.Work.NAME2ENTRY[string.lower(base .. ranks[r][1])] = { t = t, r = r }
		end
	end
end

-- 可用种类 (按职业过滤 + README 固定顺序)
local function buildUsableOrder()
	local _, playerClassEN = UnitClass("player")
	local usable = {}
	for t = 1, 15 do
		if vPlayerClass(MP.Types[t].name, playerClassEN) then
			table.insert(usable, t)
		end
	end
	table.sort(usable, function(a, b) return ORDER_INDEX[a] < ORDER_INDEX[b] end)
	MP.Work.UsableOrder = usable
end

-- ==================== 配置 ====================
local function initConfig()
	if not MPcfg then
		MPcfg = {
			PosX = screenCenterX,
			PosY = -screenCenterY,
			Scale = 1,
			LockPosition = 0,
			isVisible = 1,
			Hidden = {},        -- [type]=1 收进抽屉
			DrawerOpen = 0,
			LastMH = 0,         -- 该手最后涂的种类 (仅显示用)
			LastOH = 0,
			MaxCharges = {},    -- 涂抹时自动标定的满次数
			MaxDuration = {},   -- 满时长 ms
			TimeWarn = 5,       -- 时间 <N 分钟时角标切时间并标红
		}
	end
	if not MPcfg.TimeWarn then MPcfg.TimeWarn = 5 end
end

-- ==================== 背包扫描 ====================
function MP:BagScan()
	local counts, rankCounts = {}, {}
	for t = 1, 15 do rankCounts[t] = {} end
	for i = 0, 4 do
		local n = GetContainerNumSlots(i)
		for j = 1, n do
			if GetContainerItemInfo(i, j) then
				local link = GetContainerItemLink(i, j)
				if link then
					local nm = string.lower(gsub(link, "^.*%[(.*)%].*$", "%1"))
					local e = MP.Work.NAME2ENTRY[nm]
					if e then
						local _, c = GetContainerItemInfo(i, j)
						if c and c < 0 then c = c * -1 end
						c = c or 0
						rankCounts[e.t][e.r] = (rankCounts[e.t][e.r] or 0) + c
						counts[e.t] = (counts[e.t] or 0) + c
					end
				end
			end
		end
	end
	MP.Work.counts = counts
	MP.Work.rankCounts = rankCounts
end

-- 找背包里该种类最高等级的一瓶, 返回 bag, slot, itemId
function MP:FindItem(typeId, skipTopRank)
	local ranks = MP.RANKS[typeId]
	if not ranks then return nil end
	local base = MP.Types[typeId].name
	for r = 1, table.getn(ranks) do
		if not (skipTopRank and r == 1) then
			local want = string.lower(base .. ranks[r][1])
			for i = 0, 4 do
				local n = GetContainerNumSlots(i)
				for j = 1, n do
					if GetContainerItemInfo(i, j) then
						local link = GetContainerItemLink(i, j)
						if link then
							local nm = string.lower(gsub(link, "^.*%[(.*)%].*$", "%1"))
							if nm == want then
								return i, j, ranks[r][2]
							end
						end
					end
				end
			end
		end
	end
	return nil
end

-- ==================== 武器附魔状态 ====================
-- 解析武器 tooltip, 返回当前附魔的种类 id (移植自 EzPoison 的武器行匹配)
function MP:ScanHand(slot)
	local parser = MP.Parser
	parser:SetOwner(UIParent, "ANCHOR_NONE")
	local ok = parser:SetInventoryItem("player", slot)
	if not ok then
		parser:Hide()
		return nil
	end
	local pname = parser:GetName()
	for i = 1, 20 do
		local fs = getglobal(pname .. "TextLeft" .. i)
		if fs then
			local line = fs:GetText()
			if line then
				local lowerText = gsub(string.lower(line), "-", "")
				for _, t in ipairs(MP.Work.UsableOrder) do
					local sign = MP.SIGNS[t] or MP.Types[t].name
					if string.find(lowerText, gsub(string.lower(sign), "-", "")) then
						parser:Hide()
						return t
					end
				end
			end
		end
	end
	parser:Hide()
	return nil
end

-- 角标文字与颜色: 返回 text, r, g, b 或 nil(无角标)
local COLOR_GREEN  = { 0, 1, 0 }
local COLOR_YELLOW = { 1, 1, 0 }
local COLOR_ORANGE = { 1, 0.5, 0 }
local COLOR_RED    = { 1, 0, 0 }

local function pctColor(pct)
	if pct <= 0 then return COLOR_RED end
	if pct <= 0.25 then return COLOR_ORANGE end
	if pct <= 0.5 then return COLOR_YELLOW end
	return COLOR_GREEN
end

local function fmtTime(ms)
	local s = math.floor(ms / 1000 + 0.5)
	if s >= 60 then
		return math.floor(s / 60 + 0.5) .. "m"
	end
	return s .. "s"
end

function MP:HandBadge(typeId, hand)
	local si = MP.Work.slotInfo
	local has, exp, chg, active, last
	if hand == "MH" then
		has, exp, chg = si[1], si[2], si[3]
		active, last = MP.Work.activeMH, MPcfg.LastMH
	else
		has, exp, chg = si[4], si[5], si[6]
		active, last = MP.Work.activeOH, MPcfg.LastOH
	end

	if has and active == typeId then
		local warn = (MPcfg.TimeWarn or 5) * 60000
		if exp and exp < warn then
			-- 附魔马上超时, 次数再多也没意义: 切剩余时间并标红
			return fmtTime(exp), COLOR_RED[1], COLOR_RED[2], COLOR_RED[3]
		elseif chg and chg > 0 then
			local max = MPcfg.MaxCharges[typeId] or (typeId <= 8 and 30 or nil)
			local col = pctColor(max and (chg / max) or 1)
			return tostring(chg), col[1], col[2], col[3]
		elseif exp then
			local max = MPcfg.MaxDuration[typeId] or 1800000
			local col = pctColor(exp / max)
			return fmtTime(exp), col[1], col[2], col[3]
		end
		return "", COLOR_GREEN[1], COLOR_GREEN[2], COLOR_GREEN[3]
	end

	if (not has) and last == typeId then
		-- 这只手空着, 上次涂的是它: 停一个红色 0, 方便无脑补涂
		return "0", COLOR_RED[1], COLOR_RED[2], COLOR_RED[3]
	end

	return nil
end

-- ==================== 图标状态刷新 ====================
function MP:UpdateIcons()
	local si = MP.Work.slotInfo
	for _, t in ipairs(MP.Work.UsableOrder) do
		local btn = MP.Work.Icons[t]
		if btn then
			-- 满值标定: 附魔刚涂上时次数/时间即满值 (自校准, 含乌龟服自定义物品)
			local active = nil
			if si[1] and MP.Work.activeMH == t then active = "MH" end
			if si[4] and MP.Work.activeOH == t then active = active or "OH" end
			if active == "MH" then
				if si[3] and si[3] > 0 and (not MPcfg.MaxCharges[t] or si[3] > MPcfg.MaxCharges[t]) then MPcfg.MaxCharges[t] = si[3] end
				if si[2] and (not MPcfg.MaxDuration[t] or si[2] > MPcfg.MaxDuration[t]) then MPcfg.MaxDuration[t] = si[2] end
			elseif active == "OH" then
				if si[6] and si[6] > 0 and (not MPcfg.MaxCharges[t] or si[6] > MPcfg.MaxCharges[t]) then MPcfg.MaxCharges[t] = si[6] end
				if si[5] and (not MPcfg.MaxDuration[t] or si[5] > MPcfg.MaxDuration[t]) then MPcfg.MaxDuration[t] = si[5] end
			end

			-- 角标
			local mhText, mhR, mhG, mhB = MP:HandBadge(t, "MH")
			if mhText then
				btn.bMH:SetText(mhText)
				btn.bMH:SetTextColor(mhR, mhG, mhB)
			else
				btn.bMH:SetText("")
			end
			local ohText, ohR, ohG, ohB = MP:HandBadge(t, "OH")
			if ohText then
				btn.bOH:SetText(ohText)
				btn.bOH:SetTextColor(ohR, ohG, ohB)
			else
				btn.bOH:SetText("")
			end

			-- 库存 (白色常显)
			local stock = MP.Work.counts[t] or 0
			btn.bStock:SetText(tostring(stock))

			-- 亮度: 背包没货降亮度; 抽屉内去色
			btn:SetAlpha(stock == 0 and 0.35 or 1)
			if btn.Icon.SetDesaturated then
				btn.Icon:SetDesaturated(MPcfg.Hidden[t] == 1 and 1 or nil)
			end
		end
	end
end

function MP:Refresh()
	local s1, s2, s3, s4, s5, s6, s7 = GetWeaponEnchantInfo()
	MP.Work.slotInfo[1], MP.Work.slotInfo[2], MP.Work.slotInfo[3], MP.Work.slotInfo[4], MP.Work.slotInfo[5], MP.Work.slotInfo[6], MP.Work.slotInfo[7] =
		s1, s2, s3, s4, s5, s6, s7

	MP.Work.activeMH = s1 and MP:ScanHand(16) or nil
	MP.Work.activeOH = s4 and MP:ScanHand(17) or nil
	-- 角标跟随真实状态: 附魔在 -> 记忆同步为它
	if MP.Work.activeMH then MPcfg.LastMH = MP.Work.activeMH end
	if MP.Work.activeOH then MPcfg.LastOH = MP.Work.activeOH end

	MP:BagScan()
	MP:UpdateIcons()
end

-- ==================== 涂抹 (连招移植自 EzPoison.ApplyPoisen) ====================
function MP:Apply(typeId, hand)
	if not typeId or MP.Work.iSCasting then return end

	if hand == "OH" and not GetInventoryItemTexture("player", 17) then
		logMsg("未装备副手。")
		return
	end

	-- 双致命/双腐蚀: 副手自动低一级 (移植自 EzPoison 的 offhandLevelDown 规则)
	local skipTop = false
	if hand == "OH" and (typeId == 2 or typeId == 5) then
		if MP.Work.activeMH == typeId or (MPcfg.LastMH or 0) == typeId then
			skipTop = true
		end
	end

	local bag, slot = MP:FindItem(typeId, skipTop)
	if not bag then
		local who = hand == "MH" and "MainHand" or "OffHand"
		logMsg("|cFFCC9900" .. who .. "|r |cFFFFFFFF未发现" .. MP.Types[typeId].name .. "。|r")
		return
	end

	MP.Frame:RegisterEvent("SPELLCAST_START")
	MP.Frame:RegisterEvent("SPELLCAST_STOP")
	MP.Frame:RegisterEvent("SPELLCAST_INTERRUPTED")
	MP.Frame:RegisterEvent("SPELLCAST_FAILED")
	UseContainerItem(bag, slot)
	if hand == "MH" then
		PickupInventoryItem(16)
	else
		PickupInventoryItem(17)
	end
	ReplaceEnchant()
	ClearCursor()

	if hand == "MH" then
		MPcfg.LastMH = typeId
	else
		MPcfg.LastOH = typeId
	end
	MP.Work.dirty = 1
end

-- ==================== UI 构建 ====================
local ICON = 32
local STEP = 36
local PAD = 5

function MP:Layout()
	local frame = MP.ConfigFrame
	if not frame or table.getn(MP.Work.UsableOrder) == 0 then return end

	local main, drawer = {}, {}
	for _, t in ipairs(MP.Work.UsableOrder) do
		if MPcfg.Hidden[t] == 1 then table.insert(drawer, t) else table.insert(main, t) end
	end

	local drawerOpen = MPcfg.DrawerOpen == 1 and table.getn(drawer) > 0

	-- 主行
	for i = 1, table.getn(main) do
		local btn = MP.Work.Icons[main[i]]
		btn:ClearAllPoints()
		btn:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (i - 1) * STEP, -PAD)
		btn:Show()
	end
	-- 抽屉行 (紧贴主行下方, 行距 4px)
	for i = 1, table.getn(drawer) do
		local btn = MP.Work.Icons[drawer[i]]
		if drawerOpen then
			btn:ClearAllPoints()
			btn:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (i - 1) * STEP, -(PAD + ICON + 4))
			btn:Show()
		else
			btn:Hide()
		end
	end

	-- 抽屉开关 (常驻可见, 吸取方案小点的教训)
	local chev = frame.Chev
	chev:ClearAllPoints()
	if table.getn(main) > 0 then
		chev:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + table.getn(main) * STEP, -(PAD + (ICON - 16) / 2))
	else
		chev:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(PAD + (ICON - 16) / 2))
	end
	if drawerOpen then
		chev:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
	else
		chev:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
	end

	local w1 = PAD + table.getn(main) * STEP + 16 + 4 + PAD
	local w2 = drawerOpen and (PAD + table.getn(drawer) * STEP + PAD) or 0
	local width = w1 > w2 and w1 or w2
	local height = PAD + ICON + PAD
	if drawerOpen then height = PAD + ICON + 4 + ICON + PAD end
	frame:SetWidth(width)
	frame:SetHeight(height)
end

function MP:ShowTooltip(btn, typeId)
	MP:BagScan()
	local t = MP.Types[typeId]
	GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
	GameTooltip:AddLine(t.name, 1, 1, 1)

	local ranks = MP.RANKS[typeId]
	local base = t.name
	local any = nil
	for r = 1, table.getn(ranks) do
		local cnt = MP.Work.rankCounts[typeId][r] or 0
		if cnt > 0 then
			any = 1
			GameTooltip:AddLine(base .. ranks[r][1] .. " ×" .. cnt, 0.4, 0.8, 0.4)
		end
	end
	if not any then
		GameTooltip:AddLine("背包没有", 0.6, 0.6, 0.6)
	end

	-- 武器状态
	local mhText = MP:HandBadge(typeId, "MH")
	if mhText then
		if mhText == "0" then
			GameTooltip:AddLine("主手: 已用尽 (上次涂的)", 1, 0, 0)
		else
			GameTooltip:AddLine("主手: 剩 " .. mhText, 0.4, 0.8, 0.4)
		end
	end
	local ohText = MP:HandBadge(typeId, "OH")
	if ohText then
		if ohText == "0" then
			GameTooltip:AddLine("副手: 已用尽 (上次涂的)", 1, 0, 0)
		else
			GameTooltip:AddLine("副手: 剩 " .. ohText, 0.4, 0.8, 0.4)
		end
	end

	if MPcfg.Hidden[typeId] == 1 then
		GameTooltip:AddLine("左键 主手 · 右键 副手 · 中键 放回主行", 0.6, 0.6, 0.6)
	else
		GameTooltip:AddLine("左键 主手 · 右键 副手 · 中键 收进抽屉", 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

local function ToggleHidden(typeId)
	if MPcfg.Hidden[typeId] == 1 then
		MPcfg.Hidden[typeId] = nil
		logMsg(MP.Types[typeId].name .. " 已放回主行")
	else
		MPcfg.Hidden[typeId] = 1
		logMsg(MP.Types[typeId].name .. " 已收进抽屉")
	end
	MP:Layout()
	MP:UpdateIcons()
end

function MP:ConfigureUI()
	if not MP.ConfigFrame then
		MP.ConfigFrame = CreateFrame("Frame", "MartletPoisonFrame", UIParent)
	end
	local frame = MP.ConfigFrame

	function frame:StartMove()
		this:StartMoving()
	end
	function frame:StopMove()
		this:StopMovingOrSizing()
		local a, _, b, x, y = frame:GetPoint()
		local currentScale = frame:GetScale() or (MPcfg.Scale or 1)
		MPcfg.PosX = x * currentScale
		MPcfg.PosY = y * currentScale
	end

	local backdrop = {
		bgFile = "Interface\\TutorialFrame\\TutorialFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 3, right = 5, top = 3, bottom = 5 }
	}
	frame:SetBackdrop(backdrop)
	frame:SetBackdropColor(0, 0, 0, 0.8)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMove)
	frame:SetScript("OnDragStop", frame.StopMove)
	frame:SetScript("OnShow", function() MPcfg.isVisible = 1 end)
	frame:SetScript("OnHide", function() MPcfg.isVisible = nil end)

	buildUsableOrder()

	-- 图标工厂: 循环控制变量经由参数传入 (本客户端 Lua 的 for 控制变量
	-- 在循环结束后于闭包中读到 nil, 参数局部变量则永远正确)
	local function createIcon(frame, t)
		local btn = CreateFrame("Button", nil, frame)
		btn.typeId = t
		btn:SetWidth(ICON)
		btn:SetHeight(ICON)
		btn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
		btn:SetScript("OnClick", function()
			local b = tostring(arg1 or "")
			if b == "LeftButton" or b == "LeftButtonUp" then
				MP:Apply(t, "MH")
			elseif b == "RightButton" or b == "RightButtonUp" then
				MP:Apply(t, "OH")
			elseif b == "MiddleButton" or b == "MiddleButtonUp" then
				ToggleHidden(t)
			end
		end)
		btn:SetScript("OnEnter", function()
			MP:ShowTooltip(btn, t)
		end)
		btn:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		if btn.SetHighlightTexture then
			btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
		end

		btn.Icon = btn:CreateTexture(nil, "ARTWORK")
		btn.Icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
		btn.Icon:SetWidth(ICON)
		btn.Icon:SetHeight(ICON)
		btn.Icon:SetTexture(MP.Types[t].icon)

		btn.bMH = btn:CreateFontString(nil, "OVERLAY")
		btn.bMH:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
		btn.bMH:SetFont("Fonts\\ARIALN.TTF", 10, "OUTLINE")

		btn.bOH = btn:CreateFontString(nil, "OVERLAY")
		btn.bOH:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
		btn.bOH:SetFont("Fonts\\ARIALN.TTF", 10, "OUTLINE")

		btn.bStock = btn:CreateFontString(nil, "OVERLAY")
		btn.bStock:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
		btn.bStock:SetFont("Fonts\\ARIALN.TTF", 10, "OUTLINE")
		btn.bStock:SetTextColor(1, 1, 1)

		return btn
	end

	for _, t in ipairs(MP.Work.UsableOrder) do
		MP.Work.Icons[t] = createIcon(frame, t)
	end

	-- 抽屉开关
	local chev = CreateFrame("Button", nil, frame)
	frame.Chev = chev
	chev:SetWidth(16)
	chev:SetHeight(16)
	if chev.SetHighlightTexture then
		chev:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
	end
	chev:SetScript("OnClick", function()
		MPcfg.DrawerOpen = (MPcfg.DrawerOpen == 1) and 0 or 1
		MP:Layout()
	end)
	chev:SetScript("OnEnter", function()
		GameTooltip:SetOwner(chev, "ANCHOR_RIGHT")
		GameTooltip:AddLine("展开/收起抽屉 (隐藏的种类)", 1, 1, 1)
		GameTooltip:Show()
	end)
	chev:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	frame:SetScale(MPcfg.Scale or 1)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", (MPcfg.PosX or screenCenterX) / (MPcfg.Scale or 1), (MPcfg.PosY or -screenCenterY) / (MPcfg.Scale or 1))
	MP:Layout()

	if not MPcfg.isVisible then frame:Hide() end

	MP:ApplyLockPosition()
	MP.skin_pfUI()
end

-- 位置/缩放/锁定 (移植自 EzPoison)
function MP:ApplyLockPosition()
	local frame = MP.ConfigFrame
	if not frame then return end
	if MPcfg.LockPosition == 1 then
		frame:SetMovable(false)
		frame:EnableMouse(false)
		frame:SetScript("OnDragStart", nil)
		frame:SetScript("OnDragStop", nil)
		frame:RegisterForDrag()
	else
		frame:SetMovable(true)
		frame:EnableMouse(true)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", frame.StartMove)
		frame:SetScript("OnDragStop", frame.StopMove)
	end
	-- 面板可穿透, 但图标按钮始终可交互
	for _, t in ipairs(MP.Work.UsableOrder) do
		local btn = MP.Work.Icons[t]
		if btn then btn:EnableMouse(true) end
	end
	if frame.Chev then frame.Chev:EnableMouse(true) end
end

function MP:ApplyScale(newScale)
	local frame = MP.ConfigFrame
	if not frame then return end
	MPcfg.Scale = newScale
	frame:SetScale(newScale)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", (MPcfg.PosX or screenCenterX) / newScale, (MPcfg.PosY or -screenCenterY) / newScale)
end

function MP:ApplyPosition()
	local frame = MP.ConfigFrame
	if not frame then return end
	local scale = frame:GetScale() or (MPcfg.Scale or 1)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", (MPcfg.PosX or screenCenterX) / scale, (MPcfg.PosY or -screenCenterY) / scale)
end

function MP:ResetPosition()
	MPcfg.PosX = screenCenterX
	MPcfg.PosY = -screenCenterY
	MPcfg.Scale = 1
	local frame = MP.ConfigFrame
	if frame then
		frame:SetScale(1)
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", screenCenterX, -screenCenterY)
		if not frame:IsVisible() then frame:Show() end
	end
	logMsg("窗口位置已重置")
end

-- ==================== pfUI 皮肤 (移植自 EzPoison, 含时序兼容) ====================
local skinListener
local skinChatOnce
local skinLoadedOnce
local skinRetryFrame
local skinConfigBootstrapped

local function skinAllIcons()
	if not (IsAddOnLoaded("pfUI") and pfUI and pfUI.api and pfUI.api.SkinButton) then return end
	for _, t in ipairs(MP.Work.UsableOrder) do
		local btn = MP.Work.Icons[t]
		if btn then
			pcall(function() pfUI.api.SkinButton(btn, nil, nil, nil, btn.Icon) end)
		end
	end
end

local function ensureSkinLoaded()
	if skinLoadedOnce then return true end
	if pfUI and pfUI.bootup and not skinConfigBootstrapped then
		skinConfigBootstrapped = true
		pcall(function()
			if pfUI.LoadConfig then pfUI:LoadConfig() end
			if pfUI.MigrateConfig then pfUI:MigrateConfig() end
			if pfUI.UpdateFonts then pfUI:UpdateFonts() end
		end)
	end
	if not (pfUI and pfUI.api and pfUI.LoadSkin and pfUI.skin and pfUI.skin["MartletPoison"]) then
		return false
	end
	local ok = pcall(function() pfUI:LoadSkin("MartletPoison") end)
	if ok then
		skinLoadedOnce = true
		return true
	end
	return false
end

local function registerSkin()
	if not (pfUI and pfUI.api and pfUI.RegisterSkin) then return false end
	if pfUI.skin["MartletPoison"] then
		if skinListener then
			skinListener:UnregisterAllEvents()
			skinListener:SetScript("OnEvent", nil)
			skinListener = nil
		end
		return true
	end

	pfUI:RegisterSkin("MartletPoison", function()
		if not skinChatOnce then
			skinChatOnce = true
			DEFAULT_CHAT_FRAME:AddMessage("MartletPoison: " .. "|cFFFFFFFF" .. "pfUI skin applied." .. "|r", 0.4, 0.8, 0.4)
		end
		pfUI.api.StripTextures(MP.ConfigFrame, true)
		pfUI.api.CreateBackdrop(MP.ConfigFrame, nil, nil, .75)
		pfUI.api.CreateBackdropShadow(MP.ConfigFrame)
	end)

	if not pfUI.skin["MartletPoison"] then return false end

	if not ensureSkinLoaded() and not skinRetryFrame then
		skinRetryFrame = CreateFrame("Frame")
		skinRetryFrame.baseTime = GetTime()
		skinRetryFrame:SetScript("OnUpdate", function()
			if ensureSkinLoaded() then
				skinRetryFrame:SetScript("OnUpdate", nil)
				skinRetryFrame = nil
				return
			end
			if GetTime() - this.baseTime > 8 then
				skinRetryFrame:SetScript("OnUpdate", nil)
				skinRetryFrame = nil
			end
		end)
	end

	if skinListener then
		skinListener:UnregisterAllEvents()
		skinListener:SetScript("OnEvent", nil)
		skinListener = nil
	end
	return true
end

function MP.skin_pfUI()
	if registerSkin() then
		return
	end
	if skinListener then return end
	skinListener = CreateFrame("Frame")
	skinListener:RegisterEvent("ADDON_LOADED")
	skinListener:SetScript("OnEvent", function()
		if pfUI and pfUI.api and pfUI.RegisterSkin then
			registerSkin()
		end
	end)
end

-- ==================== FuBar 菜单 ====================
local options

function MP:ConfigFubar()
	if not options then
		options = {
			handler = MP.ACE,
			type = "group",
			args = {
				scaling = {
					type = "range",
					name = "窗口缩放",
					desc = "UI界面的窗口缩放比例",
					min = 0.5, max = 2, step = 0.1,
					get = function() return MPcfg.Scale end,
					set = function(value) MP:ApplyScale(value) end,
					order = 1,
				},
				lockPosition = {
					type = 'toggle',
					name = "锁定位置",
					desc = "锁定后面板点击穿透, 图标按钮仍可交互",
					get = function() return MPcfg.LockPosition == 1 end,
					set = function(value)
						MPcfg.LockPosition = value and 1 or 0
						MP:ApplyLockPosition()
					end,
					order = 2,
				},
				timeWarn = {
					type = 'range',
					name = "时间红字阈值(分钟)",
					desc = "附魔剩余时间低于该值时角标切换为时间并标红",
					min = 1, max = 15, step = 1,
					get = function() return MPcfg.TimeWarn or 5 end,
					set = function(value) MPcfg.TimeWarn = value end,
					order = 3,
				},
				apply = {
					type = 'toggle',
					name = "重置位置",
					desc = "重置窗口位置和缩放比例",
					get = function() end,
					set = function() MP:ResetPosition() end,
					order = 4,
				},
			},
		}
	end
	if MP.ACE then MP.ACE.OnMenuRequest = options end
end

if MP.ACE then
	function MP.ACE:OnClick()
		if arg1 == "LeftButton" then
			if MP.ConfigFrame and MP.ConfigFrame:IsVisible() then
				MP.ConfigFrame:Hide()
			elseif MP.ConfigFrame then
				MP:Refresh(); MP.ConfigFrame:Show()
			end
		end
	end
end

-- ==================== 事件/心跳 ====================
function MP:OnEvent()
	if event == "BAG_UPDATE" then
		if arg1 == 0 or arg1 == 1 or arg1 == 2 or arg1 == 3 or arg1 == 4 then
			MP.Work.dirty = 1
		end
	elseif event == "ADDON_LOADED" and arg1 == "MartletPoison" then
		initConfig()
		buildNameIndex()
		MP.loaded = 1
		logMsg("v0.1.0 已加载, 等待初始化...")
	elseif event == "SPELLCAST_START" then
		MP.Work.iSCasting = 1
	elseif event == "SPELLCAST_STOP" or event == "SPELLCAST_INTERRUPTED" or event == "SPELLCAST_FAILED" then
		MP.Frame:UnregisterEvent("SPELLCAST_STOP")
		MP.Frame:UnregisterEvent("SPELLCAST_START")
		MP.Frame:UnregisterEvent("SPELLCAST_INTERRUPTED")
		MP.Frame:UnregisterEvent("SPELLCAST_FAILED")
		MP.Work.iSCasting = nil
		MP.Work.dirty = 1
	elseif event == "UNIT_INVENTORY_CHANGED" then
		MP.Work.dirty = 1
	end
end
MP.Frame:SetScript("OnEvent", MP.OnEvent)

function MP.OnFrameUpdateInner()
	local W = MP.Work
	W.Time = W.Time + arg1
	if W.Time < 2 then return end -- 启动后等客户端稳定 (临时附魔晚于插件加载)

	if not W.SkinApplied and IsAddOnLoaded("pfUI") and pfUI and pfUI.api then
		skinAllIcons()
		W.SkinApplied = 1
	end

	if W.dirty then
		W.dirty = nil
		MP:Refresh()
	end

	W.Tick = W.Tick + arg1
	if W.Tick >= 1 then
		W.Tick = 0
		local s1, s2, s3, s4, s5, s6 = GetWeaponEnchantInfo()
		local si = W.slotInfo
		if s1 ~= si[1] or s4 ~= si[4] then
			-- 附魔出现/消失 (超时脱落不触发事件), 全量刷新
			MP:Refresh()
		else
			-- 时间角标需要每秒推进
			if s1 then
				W.slotInfo[2] = s2
				W.slotInfo[3] = s3
			end
			if s4 then
				W.slotInfo[5] = s5
				W.slotInfo[6] = s6
			end
			MP:UpdateIcons()
		end
	end
end

function MP.OnFrameUpdate()
	local ok, err = pcall(MP.OnFrameUpdateInner)
	if not ok and not MP.Work.updateErrReported then
		MP.Work.updateErrReported = 1
		DEFAULT_CHAT_FRAME:AddMessage("MartletPoison 运行错误: " .. tostring(err), 1, 0, 0)
	end
end

-- 启动引导 (移植自 EzPoison.classCheckFrame)
local classCheckFrame = CreateFrame("Frame")
classCheckFrame:SetScript("OnUpdate", function()
	local _, playerClassEN = UnitClass("player")
	if playerClassEN and MP.loaded then
		classCheckFrame:SetScript("OnUpdate", nil)
		local ok, err = pcall(function()
			MP:ConfigureUI()
			MP:ConfigFubar()
			MP.Work.Time = 0
			MP.ConfigFrame:SetScript("OnUpdate", MP.OnFrameUpdate)
			MP.Work.dirty = 1
		end)
		if ok then
			logMsg("面板初始化完成, /mpoison 开关")
		else
			DEFAULT_CHAT_FRAME:AddMessage("MartletPoison 初始化失败: " .. tostring(err), 1, 0, 0)
		end
	end
end)

-- ==================== 命令 ====================
local function mpSlash(arg1)
	arg1 = string.lower(arg1 or "")
	if string.sub(arg1, 1, 5) == "scale" then
		local scale = tonumber(string.sub(arg1, 6, string.len(arg1)))
		if scale and scale <= 3 and scale >= 0.3 then
			MP:ApplyScale(scale)
		end
	elseif string.sub(arg1, 1, 4) == "lock" then
		MPcfg.LockPosition = 1
		MP:ApplyLockPosition()
		logMsg("窗口位置已锁定")
	elseif string.sub(arg1, 1, 6) == "unlock" then
		MPcfg.LockPosition = 0
		MP:ApplyLockPosition()
		logMsg("窗口位置已解锁")
	elseif string.sub(arg1, 1, 3) == "pos" then
		local _, _, x, y = string.find(arg1, "^pos%s+([%-%d]+)[, ]([%-%d]+)")
		if x and y then
			MPcfg.PosX = tonumber(x)
			MPcfg.PosY = -tonumber(y)
			MP:ApplyPosition()
			logMsg("窗口位置已设置为 (" .. x .. ", " .. y .. ")")
		else
			logMsg("|cFFFF0000命令参数错误 (例: /mpoison pos 100,100)|r")
		end
	elseif string.sub(arg1, 1, 5) == "time " then
		local n = tonumber(string.sub(arg1, 6, string.len(arg1)))
		if n and n >= 1 and n <= 15 then
			MPcfg.TimeWarn = n
			logMsg("时间红字阈值: " .. n .. " 分钟")
		end
	elseif string.sub(arg1, 1, 5) == "reset" then
		MP:ResetPosition()
	elseif arg1 == "" then
		if MP.ConfigFrame:IsVisible() then
			MP.ConfigFrame:Hide()
		else
			MP:Refresh(); MP.ConfigFrame:Show()
		end
	else
		logMsg("命令: /mpoison 开关面板 | scale N | lock | unlock | pos x,y | time N | reset")
	end
end

BINDING_HEADER_MPHEADER = "MartletPoison"

function MartletPoisonToggle()
	if MP.ConfigFrame and MP.ConfigFrame:IsVisible() then
		MP.ConfigFrame:Hide()
	elseif MP.ConfigFrame then
		MP:Refresh(); MP.ConfigFrame:Show()
	end
end

SlashCmdList['MARTLETPOISON'] = mpSlash
SLASH_MARTLETPOISON1 = '/mpoison'
SLASH_MARTLETPOISON2 = '/martletpoison'

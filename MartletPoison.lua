-- MartletPoison 0.2.0 看板版
-- 所见即所涂的涂毒助手。基于 EzPoison (Sunelegy/qyj) 的成熟逻辑改造。
-- 双看板(主手/副手) + 四角信息(次数/时间/等级/库存) + 有货/全量列表。
-- 面板显示武器状态而非背包库存; 点击=涂抹; 无影响行为的隐藏状态。

-- 命名空间: 本客户端环境已预置全局 MP(字符串), 必须用插件全名并做类型防护
if type(MartletPoison) ~= "table" then MartletPoison = {} end
local MP = MartletPoison

MP.api = getfenv()
MP.INF_CHAR = "∞" -- 时间型无次数概念; 若客户端字形缺失, 改成 "--"

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

-- 看板/列表的展示顺序: 速效→致命→致伤→致残→麻痹→腐蚀→溶解→煽动 | 致密→神圣→元素→致密平衡 | 油
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
	activeMH = nil, rankMH = nil,   -- 主手当前附魔种类+等级 (tooltip 解析)
	activeOH = nil, rankOH = nil,
	counts = {},        -- 背包各种类总数
	rankCounts = {},    -- 背包各等级数量 [type][rankIdx]
	NAME2ENTRY = {},    -- 小写物品名 -> {t=种类, r=等级序号}
	UsableOrder = {},   -- 排序后的可用种类列表
	ListMode = nil,     -- nil/"stock"/"all" (会话态, 不存档)
	DashIcons = {},     -- ["MH"/"OH"] = 看板按钮
	ListIcons = {},     -- [type] = 列表按钮
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

-- 可用种类 (按职业过滤 + 固定顺序)
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
			LastMH = 0,         -- 该手最后涂的种类 (看板显示+补涂用)
			LastOH = 0,
			MaxCharges = {},    -- 涂抹时自动标定的满次数
			MaxDuration = {},   -- 满时长 ms
			TimeWarn = 5,       -- 时间 <N 分钟时时间角标红 (阈值可调)
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
-- 解析武器 tooltip, 返回 种类id, 等级序号 (等级来自行内后缀, 高等级优先避免 II/III 子串误匹配)
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
					if string.find(lowerText, gsub(string.lower(sign), "-", ""), 1, true) then
						local rank = table.getn(MP.RANKS[t]) -- 无后缀 = 基础等级(列表末位)
						for r = 1, table.getn(MP.RANKS[t]) do
							if MP.RANKS[t][r][1] ~= "" then
								local full = gsub(string.lower(MP.Types[t].name .. MP.RANKS[t][r][1]), "-", "")
								if string.find(lowerText, full, 1, true) then
									rank = r
									break
								end
							end
						end
						parser:Hide()
						return t, rank
					end
				end
			end
		end
	end
	parser:Hide()
	return nil
end

-- ==================== 颜色/格式 ====================
local COLOR_GREEN  = { 0, 1, 0 }
local COLOR_YELLOW = { 1, 1, 0 }
local COLOR_ORANGE = { 1, 0.5, 0 }
local COLOR_RED    = { 1, 0, 0 }
local COLOR_GRAY   = { 0.75, 0.75, 0.75 }

local function fmtTime(ms)
	local s = math.floor(ms / 1000 + 0.5)
	if s >= 60 then
		return math.floor(s / 60 + 0.5) .. "m"
	end
	return s .. "s"
end

local function pctColor(pct)
	if pct <= 0 then return COLOR_RED end
	if pct <= 0.25 then return COLOR_ORANGE end
	if pct <= 0.5 then return COLOR_YELLOW end
	return COLOR_GREEN
end

-- 余量档位 (次数与时间取更紧迫的那个)
local function marginPct(typeId, exp, chg)
	local p1, p2
	if typeId <= 8 and chg and chg > 0 then
		local max = MPcfg.MaxCharges[typeId] or 30
		p1 = chg / max
	end
	if exp and exp > 0 then
		local max = MPcfg.MaxDuration[typeId] or 1800000
		p2 = exp / max
	end
	if p1 and p2 then
		if p1 < p2 then return p1 else return p2 end
	elseif p1 then return p1
	elseif p2 then return p2 end
	return 1
end

-- ==================== 看板四角 ====================
-- 返回: typeId, 次数文字+RGB, 时间文字+RGB, 等级文字, 库存
function MP:DashCorners(hand)
	local si = MP.Work.slotInfo
	local has, exp, chg
	if hand == "MH" then
		has, exp, chg = si[1], si[2], si[3]
	else
		has, exp, chg = si[4], si[5], si[6]
	end
	local active, rank
	if hand == "MH" then
		active, rank = MP.Work.activeMH, MP.Work.rankMH
	else
		active, rank = MP.Work.activeOH, MP.Work.rankOH
	end
	local last
	if hand == "MH" then last = MPcfg.LastMH or 0 else last = MPcfg.LastOH or 0 end

	local typeId = nil
	if has and active then
		typeId = active
	elseif last ~= 0 then
		typeId = last
	end
	if not typeId then
		return nil -- 全空: 无记忆
	end

	local isPoison = typeId <= 8
	local cT, cR, cG, cB
	local tT, tR, tG, tB
	local rankT

	if has and active == typeId then
		if isPoison and chg and chg > 0 then
			local max = MPcfg.MaxCharges[typeId] or 30
			local col = pctColor(chg / max)
			cT, cR, cG, cB = tostring(chg), col[1], col[2], col[3]
		elseif isPoison then
			cT, cR, cG, cB = "0", COLOR_RED[1], COLOR_RED[2], COLOR_RED[3]
		else
			cT, cR, cG, cB = MP.INF_CHAR, COLOR_GRAY[1], COLOR_GRAY[2], COLOR_GRAY[3]
		end
		if exp then
			local max = MPcfg.MaxDuration[typeId] or 1800000
			local col = pctColor(exp / max)
			tT, tR, tG, tB = fmtTime(exp), col[1], col[2], col[3]
		else
			tT, tR, tG, tB = "", 1, 1, 1
		end
		if rank then
			local suf = MP.RANKS[typeId][rank][1]
			rankT = gsub(suf, " ", "")
			if rankT == "" then rankT = "-" end
		else
			rankT = "-"
		end
	else
		-- 空手有记忆: 红 0 常驻, 方便无脑补涂
		if isPoison then
			cT, cR, cG, cB = "0", COLOR_RED[1], COLOR_RED[2], COLOR_RED[3]
		else
			cT, cR, cG, cB = MP.INF_CHAR, COLOR_GRAY[1], COLOR_GRAY[2], COLOR_GRAY[3]
		end
		tT, tR, tG, tB = "0", COLOR_RED[1], COLOR_RED[2], COLOR_RED[3]
		rankT = "-"
	end

	local stock = MP.Work.counts[typeId] or 0
	return typeId, cT, cR, cG, cB, tT, tR, tG, tB, rankT, stock
end

-- 剩余量文字 (tooltip 用)
function MP:RemainText(typeId, hand)
	local si = MP.Work.slotInfo
	local exp, chg
	if hand == "MH" then
		exp, chg = si[2], si[3]
	else
		exp, chg = si[5], si[6]
	end
	local warn = (MPcfg.TimeWarn or 5) * 60000
	if exp and exp < warn then
		return fmtTime(exp)
	elseif chg and chg > 0 then
		return tostring(chg)
	elseif exp then
		return fmtTime(exp)
	end
	return "?"
end

-- ==================== 图标状态刷新 ====================
function MP:UpdateIcons()
	local si = MP.Work.slotInfo

	-- 满值标定: 附魔刚涂上时次数/时间即满值 (自校准, 含乌龟服自定义物品)
	local hands = { "MH", "OH" }
	for _, hand in ipairs(hands) do
		local has, exp, chg, active
		if hand == "MH" then
			has, exp, chg, active = si[1], si[2], si[3], MP.Work.activeMH
		else
			has, exp, chg, active = si[4], si[5], si[6], MP.Work.activeOH
		end
		if has and active then
			if chg and chg > 0 and (not MPcfg.MaxCharges[active] or chg > MPcfg.MaxCharges[active]) then
				MPcfg.MaxCharges[active] = chg
			end
			if exp and (not MPcfg.MaxDuration[active] or exp > MPcfg.MaxDuration[active]) then
				MPcfg.MaxDuration[active] = exp
			end
		end
	end

	-- 看板四角
	for _, hand in ipairs(hands) do
		local dash = MP.Work.DashIcons[hand]
		if dash then
			local typeId, cT, cR, cG, cB, tT, tR, tG, tB, rankT, stock = MP:DashCorners(hand)
			if typeId then
				local active
				if hand == "MH" then active = MP.Work.activeMH else active = MP.Work.activeOH end
				dash.typeId = typeId
				dash.Icon:SetTexture(MP.Types[typeId].icon)
				dash:SetAlpha(active and 1 or 0.55)
				dash.cTL:SetText(cT); dash.cTL:SetTextColor(cR, cG, cB)
				dash.cTR:SetText(tT); dash.cTR:SetTextColor(tR, tG, tB)
				dash.cBL:SetText(rankT); dash.cBL:SetTextColor(0.85, 0.85, 0.85)
				dash.cBR:SetText(tostring(stock)); dash.cBR:SetTextColor(1, 1, 1)
			else
				dash.typeId = nil
				dash.Icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
				dash:SetAlpha(0.4)
				dash.cTL:SetText(""); dash.cTR:SetText("")
				dash.cBL:SetText("-"); dash.cBL:SetTextColor(0.6, 0.6, 0.6)
				dash.cBR:SetText("0"); dash.cBR:SetTextColor(1, 1, 1)
			end
		end
	end

	-- 列表项: 只显示库存
	for _, t in ipairs(MP.Work.UsableOrder) do
		local item = MP.Work.ListIcons[t]
		if item then
			local c = MP.Work.counts[t] or 0
			item.bStock:SetText(tostring(c))
			item:SetAlpha(c == 0 and 0.35 or 1)
		end
	end

	MP:Layout() -- 有货模式的显隐随库存变化
end

function MP:Refresh()
	local s1, s2, s3, s4, s5, s6, s7 = GetWeaponEnchantInfo()
	MP.Work.slotInfo[1], MP.Work.slotInfo[2], MP.Work.slotInfo[3], MP.Work.slotInfo[4], MP.Work.slotInfo[5], MP.Work.slotInfo[6], MP.Work.slotInfo[7] =
		s1, s2, s3, s4, s5, s6, s7

	if s1 then
		local t, r = MP:ScanHand(16)
		MP.Work.activeMH, MP.Work.rankMH = t, r
	else
		MP.Work.activeMH, MP.Work.rankMH = nil, nil
	end
	if s4 then
		local t, r = MP:ScanHand(17)
		MP.Work.activeOH, MP.Work.rankOH = t, r
	else
		MP.Work.activeOH, MP.Work.rankOH = nil, nil
	end
	-- 记忆跟随真实状态: 附魔在 -> 记忆同步为它
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
		local mhActive = MP.Work.activeMH
		if mhActive == typeId or (MPcfg.LastMH or 0) == typeId then
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

-- 看板左键: 补涂该手上次的毒 (带防浪费护栏)
function MP:Reapply(hand)
	local last
	if hand == "MH" then last = MPcfg.LastMH or 0 else last = MPcfg.LastOH or 0 end
	if last == 0 then
		logMsg(hand == "MH" and "主手还没涂过毒" or "副手还没涂过毒")
		return
	end
	local active
	if hand == "MH" then active = MP.Work.activeMH else active = MP.Work.activeOH end
	if active == last then
		local si = MP.Work.slotInfo
		local exp, chg
		if hand == "MH" then
			exp, chg = si[2], si[3]
		else
			exp, chg = si[5], si[6]
		end
		if marginPct(last, exp, chg) > 0.25 then
			logMsg(MP.Types[last].name .. " 余量还充足, 不重涂 (橙/红时才会补)")
			return
		end
	end
	MP:Apply(last, hand)
end

-- ==================== 列表 ====================
function MP:ToggleList(mode)
	if MP.Work.ListMode == mode then
		MP.Work.ListMode = nil
	else
		MP.Work.ListMode = mode
	end
	MP:Layout()
end

-- ==================== UI 构建 ====================
local PAD = 5      -- 面板内边距
local DASH = 40    -- 看板图标尺寸
local LICON = 32   -- 列表图标尺寸
local STEP = 36    -- 列表项步进
local GAP = 6      -- 看板间距 / 行距

-- 展开态绿色边框 (兼容 pfUI 的独立 backdrop)
local function setGroupBorder(frame, r, g, b, a)
	if frame.backdrop and frame.backdrop.SetBackdropBorderColor then
		frame.backdrop:SetBackdropBorderColor(r, g, b, a)
	end
	if frame.SetBackdropBorderColor then
		frame:SetBackdropBorderColor(r, g, b, a)
	end
end

function MP:Layout()
	local frame = MP.ConfigFrame
	if not frame then return end
	local dashMH = MP.Work.DashIcons.MH
	local dashOH = MP.Work.DashIcons.OH
	if not dashMH or not dashOH then return end

	dashMH:ClearAllPoints()
	dashMH:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
	dashOH:ClearAllPoints()
	dashOH:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + DASH + GAP, -PAD)

	local mode = MP.Work.ListMode
	local listW = 0
	if mode then
		local x = PAD
		for _, t in ipairs(MP.Work.UsableOrder) do
			local item = MP.Work.ListIcons[t]
			local show = (mode == "all") or ((MP.Work.counts[t] or 0) > 0)
			if show then
				item:ClearAllPoints()
				item:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -(PAD + DASH + GAP))
				item:Show()
				x = x + STEP
			else
				item:Hide()
			end
		end
		listW = x - STEP + LICON + PAD
	else
		-- 收起: 藏掉所有列表项, 防止上一模式的图标残留
		for _, t in ipairs(MP.Work.UsableOrder) do
			local item = MP.Work.ListIcons[t]
			if item then item:Hide() end
		end
	end

	local groupW = PAD + DASH + GAP + DASH + PAD
	local width = groupW > listW and groupW or listW
	local height = PAD + DASH + PAD
	if mode then height = PAD + DASH + GAP + STEP + PAD end
	frame:SetWidth(width)
	frame:SetHeight(height)

	if mode then
		setGroupBorder(frame, 0, 1, 0, 1)
	else
		setGroupBorder(frame, 1, 1, 1, 1)
	end
end

function MP:ShowTooltip(btn, typeId, hint)
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

	-- 两手状态 (含等级)
	if MP.Work.slotInfo[1] and MP.Work.activeMH == typeId then
		local rankT = "-"
		if MP.Work.rankMH then
			local suf = MP.RANKS[typeId][MP.Work.rankMH][1]
			rankT = gsub(suf, " ", "")
			if rankT == "" then rankT = "-" end
		end
		GameTooltip:AddLine("主手: 已涂 " .. rankT .. " · 剩 " .. MP:RemainText(typeId, "MH"), 0.4, 0.8, 0.4)
	elseif (MPcfg.LastMH or 0) == typeId then
		GameTooltip:AddLine("主手: 已用尽 (上次涂的)", 1, 0, 0)
	end
	if MP.Work.slotInfo[4] and MP.Work.activeOH == typeId then
		local rankT = "-"
		if MP.Work.rankOH then
			local suf = MP.RANKS[typeId][MP.Work.rankOH][1]
			rankT = gsub(suf, " ", "")
			if rankT == "" then rankT = "-" end
		end
		GameTooltip:AddLine("副手: 已涂 " .. rankT .. " · 剩 " .. MP:RemainText(typeId, "OH"), 0.4, 0.8, 0.4)
	elseif (MPcfg.LastOH or 0) == typeId then
		GameTooltip:AddLine("副手: 已用尽 (上次涂的)", 1, 0, 0)
	end

	if hint then
		GameTooltip:AddLine(hint, 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
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

	-- 工厂函数: 迭代变量一律经参数传入 (本客户端 for 控制变量在循环后的闭包里读到 nil)
	local function createDash(hand)
		local btn = CreateFrame("Button", nil, frame)
		btn.hand = hand
		btn:SetWidth(DASH)
		btn:SetHeight(DASH)
		btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		btn:SetScript("OnClick", function()
			local b = tostring(arg1 or "")
			if b == "LeftButton" or b == "LeftButtonUp" then
				MP:Reapply(hand)
			elseif b == "RightButton" or b == "RightButtonUp" then
				if IsShiftKeyDown() then
					MP:ToggleList("all")
				else
					MP:ToggleList("stock")
				end
			end
		end)
		btn:SetScript("OnEnter", function()
			if btn.typeId then
				MP:ShowTooltip(btn, btn.typeId, "左键 补涂 | 右键 有货列表 | Shift+右键 全部")
			else
				GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
				GameTooltip:AddLine("空槽 - 先从列表涂一次毒", 0.8, 0.8, 0.8)
				GameTooltip:Show()
			end
		end)
		btn:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		if btn.SetHighlightTexture then
			btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
		end

		btn.Icon = btn:CreateTexture(nil, "ARTWORK")
		btn.Icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
		btn.Icon:SetWidth(DASH - 4)
		btn.Icon:SetHeight(DASH - 4)
		btn.Icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")

		btn.cTL = btn:CreateFontString(nil, "OVERLAY")
		btn.cTL:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
		btn.cTL:SetFont("Fonts\\ARIALN.TTF", 9, "OUTLINE")

		btn.cTR = btn:CreateFontString(nil, "OVERLAY")
		btn.cTR:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
		btn.cTR:SetFont("Fonts\\ARIALN.TTF", 9, "OUTLINE")

		btn.cBL = btn:CreateFontString(nil, "OVERLAY")
		btn.cBL:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 1)
		btn.cBL:SetFont("Fonts\\ARIALN.TTF", 9, "OUTLINE")

		btn.cBR = btn:CreateFontString(nil, "OVERLAY")
		btn.cBR:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
		btn.cBR:SetFont("Fonts\\ARIALN.TTF", 9, "OUTLINE")

		return btn
	end
	MP.Work.DashIcons.MH = createDash("MH")
	MP.Work.DashIcons.OH = createDash("OH")

	local function createListItem(t)
		local btn = CreateFrame("Button", nil, frame)
		btn.typeId = t
		btn:SetWidth(LICON)
		btn:SetHeight(LICON)
		btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		btn:SetScript("OnClick", function()
			local b = tostring(arg1 or "")
			if b == "RightButton" or b == "RightButtonUp" then
				MP:Apply(t, "OH")
			elseif IsShiftKeyDown() then
				MP:Apply(t, "OH")
			else
				MP:Apply(t, "MH")
			end
		end)
		btn:SetScript("OnEnter", function()
			MP:ShowTooltip(btn, t, "左键 涂主手 | 右键/Shift+左键 涂副手")
		end)
		btn:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		if btn.SetHighlightTexture then
			btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
		end

		btn.Icon = btn:CreateTexture(nil, "ARTWORK")
		btn.Icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
		btn.Icon:SetWidth(LICON)
		btn.Icon:SetHeight(LICON)
		btn.Icon:SetTexture(MP.Types[t].icon)

		btn.bStock = btn:CreateFontString(nil, "OVERLAY")
		btn.bStock:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
		btn.bStock:SetFont("Fonts\\ARIALN.TTF", 10, "OUTLINE")
		btn.bStock:SetTextColor(1, 1, 1)

		btn:Hide()
		return btn
	end
	for _, t in ipairs(MP.Work.UsableOrder) do
		MP.Work.ListIcons[t] = createListItem(t)
	end

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
	local function keepMouse(btn) if btn then btn:EnableMouse(true) end end
	keepMouse(MP.Work.DashIcons.MH)
	keepMouse(MP.Work.DashIcons.OH)
	for _, t in ipairs(MP.Work.UsableOrder) do
		keepMouse(MP.Work.ListIcons[t])
	end
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
	local function skin(btn)
		if btn then
			pcall(function() pfUI.api.SkinButton(btn, nil, nil, nil, btn.Icon) end)
		end
	end
	skin(MP.Work.DashIcons.MH)
	skin(MP.Work.DashIcons.OH)
	for _, t in ipairs(MP.Work.UsableOrder) do
		skin(MP.Work.ListIcons[t])
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
					desc = "附魔剩余时间低于该值时时间角标变红",
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
		logMsg("v0.2.0 已加载, 等待初始化...")
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
		if MP.ConfigFrame and MP.ConfigFrame:IsVisible() then
			MP.ConfigFrame:Hide()
		elseif MP.ConfigFrame then
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

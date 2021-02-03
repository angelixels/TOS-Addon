local acutil = require('acutil');

_G['ADDONS'] = _G['ADDONS'] or {};
_G['ADDONS']['CHARSIM'] = _G['ADDONS']['CHARSIM'] or {};

local g = _G['ADDONS']['CHARSIM'];
g.configDir = "../addons/charsim/config.json";

-- config file format
-- { (charName)_(teamName)_eq: { slotName:classID } }
-- slotName is taken from equippableSlot. DYE will be special name with headIndex as value
function CHARSIM_LOAD()
	if not g.loaded then
		g.config = {};
		local t, err = acutil.loadJSON(g.configDir, g.config);
		if not err then
			g.config = t;
		end
		g.loaded = true;
	end
	if g.config['_rate'] == nil then
		g.config['_rate'] = -1;
	end
	CHARSIM_UPDATE_PLAYER();
end

function CHARSIM_SAVE()
	acutil.saveJSON(g.configDir, g.config);
end

-- DYE not included and is handled separately
local equippableSlot = {
	'HELMET', 'HAT_T', 'HAT', 'HAT_L', 'HAIR', 'LENS', 'OUTER', 'LH', 'RH', 'ARMBAND', 'WING'
};

-- [SlotName] = {dropdown index => '', {value:ClassName, name:Name}, ...}
-- For dye, ClassName will be headIndex corresponding to hair,dye pair instead (dye is always setup after hair dropdown changed)
local availableEquip = {}; 
local availableEquipCount = {} -- [SlotName] = count
local currentEquip = {}; -- [SlotName] = dropdown index

function CHARSIM_INIT_SETTING()
	currentEquip = {};
	for i, slotName in ipairs(equippableSlot) do
		currentEquip[slotName] = 0;
	end
	currentEquip['DYE'] = 0;
end

-- Check for character equipment compatibility. Use ies string
function CHARSIM_CHECKEQUIP_COMPAT(myjobStr, mygenderStr, equipjob, equipgender, slot, name)
	local jobCompat = false;
	local genderCompat = false;
	if equipjob == 'All' or string.find(equipjob, myjobStr) then
		jobCompat = true;
	end
	if equipgender == 'Both' or equipgender == mygenderStr then
		genderCompat = true;
	end
	if slot == 'RH' then
		print(name .. (jobCompat and 'true' or 'false') .. ' ' .. (genderCompat and 'true' or 'false'));
	end
	return jobCompat and genderCompat;
end

-- Refresh available equipment and dropdown list.
function CHARSIM_REFRESHLIST()
	-- Get player's job and gender in string that is compatible with ies
	local job = math.floor(GetMyJobList()[1]/1000); --SW:1 Wiz:2 Archer:3 Cleric:4
	job = 'Char'..job;
	local handle = session.GetMyHandle();
	local gender = info.GetGender(handle); --Male:1 Female:2
	if gender == 1 then
		gender = 'Male';
	else
		gender = 'Female';
	end

	-- Clear previous list
	availableEquip = {};
	for i, slotName in ipairs(equippableSlot) do
		availableEquip[slotName] = {};
		availableEquip[slotName][0] = { value = '', name = 'Default' };
		availableEquipCount[slotName] = 1;
	end

	-- Refresh equip list
	local itemClassList, itemClassCount = GetClassList("Item");
	for i=0, itemClassCount-1 do
		local itemClass = GetClassByIndexFromList(itemClassList, i);
		--For some reason, there are items that we can GetClassByIndexFromList(classList, index) but cannot GetClass(ies, className)
		if GetClass("Item",itemClass.ClassName) ~= nil then
			-- Something else, filter for valid equip
			local defaultEqpSlot = TryGetProp(itemClass,'DefaultEqpSlot');
			local usejob = TryGetProp(itemClass,'UseJob');
			local usegender = TryGetProp(itemClass,'UseGender');
			if defaultEqpSlot ~= nil and usejob ~= nil and usegender ~= nil and CHARSIM_CHECKEQUIP_COMPAT(job,gender,usejob,usegender) then
				-- Filter slot
				local targetSlot = nil;
				if defaultEqpSlot == 'RH LH' then
					-- Sword has special type, equip to RH instead
					targetSlot = 'RH';
				else
					for j, slotName in ipairs(equippableSlot) do
						if slotName == defaultEqpSlot then
							targetSlot = slotName;
							break;
						end
					end
				end
				-- Set dropdown index => ClassName map
				if targetSlot ~= nil then
					local dropdownIndex = availableEquipCount[targetSlot];
					availableEquip[targetSlot][dropdownIndex] = { 
						value = itemClass.ClassName, 
						name = dictionary.ReplaceDicIDInCompStr(itemClass.Name)
					};
					availableEquipCount[targetSlot] = availableEquipCount[targetSlot]+1;
				end
			end
		end
	end

	-- Sort data and refresh dropdown
	for i, slotName in ipairs(equippableSlot) do
		table.sort(availableEquip[slotName], CHARSIM_AVAIL_EQUIP_COMPARATOR);
		CHARSIM_SETUP_DROPDOWN(slotName);
	end

	CHARSIM_SETUP_DYE_DROPDOWN();
end

function CHARSIM_SETUP_DROPDOWN(slotName)
	local frame = ui.GetFrame('charsim');
	local dropdown = GET_CHILD_RECURSIVELY(frame, 'dropdown_'..slotName);
	if dropdown ~= nil then
		dropdown = tolua.cast(dropdown,'ui::CDropList');
		dropdown:ClearItems();
		for j=0, availableEquipCount[slotName]-1 do
			dropdown:AddItem(j, availableEquip[slotName][j].name);
		end
		-- Clear selection
		currentEquip[slotName] = 0;
	end
end

function CHARSIM_SETUP_DYE_DROPDOWN()
	availableEquip['DYE'] = {};
	availableEquip['DYE'][0] = { value = nil, name = 'Default' };
	availableEquipCount['DYE'] = 1;

	-- Setup availableEquip for dye
	local hairClassName = availableEquip['HAIR'][currentEquip['HAIR']].value;
	if hairClassName ~= '' then
		local hairArgName = GetClass("Item", hairClassName).StringArg;

		-- Search for compatible dye
		local pc = GetMyPCObject();
		local PartClass = imcIES.GetClass("CreatePcInfo", "Hair");
    	local GenderList = PartClass:GetSubClassList();
    	local Selectclass   = GenderList:GetClass(pc.Gender);
    	local Selectclasslist = Selectclass:GetSubClassList();

    	local listCount = Selectclasslist:Count();    
    	for i=0, listCount do
        	local cls = Selectclasslist:GetByIndex(i);
        	if cls ~= nil and imcIES.GetString(cls, "EngName") == hairArgName then
        		local dropdownIndex = availableEquipCount['DYE'];
				availableEquip['DYE'][dropdownIndex] = { 
					value = cls:GetID(),
					name = imcIES.GetString(cls, "Color")
				};
				availableEquipCount['DYE'] = dropdownIndex+1;
				-- Set first dye found to default (first dye should always be the basic one)
				if availableEquip['DYE'][0].value == nil then
					availableEquip['DYE'][0].value = cls:GetID();
				end
	        end
    	end
    	table.sort(availableEquip['DYE'], CHARSIM_AVAIL_EQUIP_COMPARATOR);
	end
	-- Just in case hair not found for some reason, so the addon does not crash
	if availableEquip['DYE'][0].value == nil then
		availableEquip['DYE'][0].value = 0;
	end

	-- Setup dropdown
	CHARSIM_SETUP_DROPDOWN('DYE');
end

function CHARSIM_AVAIL_EQUIP_COMPARATOR(a,b)
	if a.name == 'Default' then
		return true;
	elseif b.name == 'Default' then
		return false;
	else
		return a.name < b.name;
	end
end

-- Update appearance PC with specified rotation (0:reset 1:CCW 2:CW) using currentEquip
function CHARSIM_UPDATE_APC(rotation)
	local pcSession = session.GetMySession();
    if pcSession == nil then
        return
    end
    
    local apc = pcSession:GetPCDummyApc();
    for i, slotName in ipairs(equippableSlot) do
    	local dropdownIndex = currentEquip[slotName];
    	local className = availableEquip[slotName][dropdownIndex].value;
    	if className == nil or className == '' then
	    	apc:SetEquipItem(item.GetEquipSpotNum(slotName), 0);
    	else
    		local itemClass = GetClass("Item",className);
    		apc:SetEquipItem(item.GetEquipSpotNum(slotName), itemClass.ClassID);
    	end
    end
    -- Special case for dye
	local headIndexByItem = availableEquip['DYE'][currentEquip['DYE']].value;
	apc:SetHeadType(headIndexByItem);

	-- Wig visibility
	local myPCetc = GetMyEtcObject();
    local hairWig_Visible = myPCetc.HAIR_WIG_Visible
    if hairWig_Visible == 1 then
        apc:SetHairWigVisible(true);
    else
        apc:SetHairWigVisible(false);
    end

    local imgName = ui.CaptureMyFullStdImageByAPC(apc,rotation);

    local frame = ui.GetFrame('charsim');
    local picture = GET_CHILD_RECURSIVELY(frame, 'apc', 'ui::CPicture');
    picture:SetImage(imgName);
end

-- Update player characte appearance using config
function CHARSIM_UPDATE_PLAYER()
	--[[
	local handle = session.GetMyHandle();
	local key = info.GetName(handle)..' '..info.GetFamilyName(handle)..'_eq';
	if g.config[key] ~= nil then
		local conf = g.config[key];
		for i, slotName in ipairs(equippableSlot) do
			if slotName ~= "LH" or conf['_sub'] then
				if conf[slotName] ~= nil then
					GetMyActor():GetSystem():ChangeEquipApperance(item.GetEquipSpotNum(slotName), conf[slotName]);
				else
					GetMyActor():GetSystem():ChangeEquipApperance(item.GetEquipSpotNum(slotName), 0);
				end
			end
		end
		if conf['DYE'] ~= nil then
			item.ChangeHeadAppearance(conf['DYE']);
		else
			item.ChangeHeadAppearance( session.GetMySession():GetPCApc():GetHeadType() );
		end
	else
		for i, slotName in ipairs(equippableSlot) do
			print(slotName);
			if slotName ~= "LH" then
				GetMyActor():GetSystem():ChangeEquipApperance(item.GetEquipSpotNum(slotName), 0);
			end
		end
		item.ChangeHeadAppearance( session.GetMySession():GetPCApc():GetHeadType() );
	end
	--]]
end



-- Apply equipment change. Call this after dropdown item is selected
-- This function setup currentEquip for render
function CHARSIM_APPLYEQUIP(frame)
	for i, slotName in ipairs(equippableSlot) do
		local dropdown = GET_CHILD_RECURSIVELY(frame, 'dropdown_'..slotName, 'ui::CDropList');
		currentEquip[slotName] = dropdown:GetSelItemIndex();
	end
	-- Special case for dye
	local dyeDropdown = GET_CHILD_RECURSIVELY(frame, 'dropdown_DYE', 'ui::CDropList');
	currentEquip['DYE'] = dyeDropdown:GetSelItemIndex();
	CHARSIM_UPDATE_APC(0);
end

function CHARSIM_APPLYEQUIP_HAIR(frame)
	CHARSIM_APPLYEQUIP(frame); -- Need to know which hair is selected first
	CHARSIM_SETUP_DYE_DROPDOWN();
	CHARSIM_UPDATE_APC(0);
end

function CHARSIM_UPDATEROTATION_CCW()
	CHARSIM_UPDATE_APC(1);
end

function CHARSIM_UPDATEROTATION_CW()
	CHARSIM_UPDATE_APC(2);
end

function CHARSIM_TRY_ON(frame)
	-- Populate config with setup from UI
	local handle = session.GetMyHandle();
	local key = info.GetName(handle)..' '..info.GetFamilyName(handle)..'_eq';
	if g.config[key] and g.config[key]['_sub'] then
		g.config[key] = { ['_sub'] = true };
	else
		g.config[key] = {};
	end
	for i, slotName in ipairs(equippableSlot) do
		local eqClassName = availableEquip[slotName][currentEquip[slotName]].value;
		local classIdFound = false;
		if eqClassName == nil or eqClassName == '' then
			g.config[key][slotName] = nil;
		else
			local itemClass = GetClass("Item",eqClassName);
			g.config[key][slotName] = itemClass.ClassID;
		end
	end

	-- Special case for dye
	local headIndex = availableEquip['DYE'][currentEquip['DYE']].value;
	if headIndex == nil or headIndex == 0 then
		g.config[key]['DYE'] = nil;
	else
		g.config[key]['DYE'] = headIndex;
	end

	CHARSIM_SAVE();
	CHARSIM_UPDATE_PLAYER();
end

function CHARSIM_CLEAR_APPEARANCE(frame)
	local handle = session.GetMyHandle();
	local key = info.GetName(handle)..' '..info.GetFamilyName(handle)..'_eq';
	if g.config[key] and g.config[key]['_sub'] then
		g.config[key] = { ['_sub'] = true };
	else
		g.config[key] = nil;
	end
	CHARSIM_SAVE();
	CHARSIM_UPDATE_PLAYER();
end



local fpscounter = 0;

function CHARSIM_FPSUPDATE()
	if g.config['_rate'] >= 0 then
		if fpscounter >= g.config['_rate'] then
			CHARSIM_UPDATE_PLAYER();
			fpscounter = 0;
		else
			fpscounter = fpscounter + 1;
		end
	end
end



function CHARSIM_CMD(command)
	CHARSIM_LOAD();
	CHARSIM_INIT_SETTING();
	CHARSIM_REFRESHLIST();
	if #command > 0 then
		local subcmd = table.remove(command, 1);
		if subcmd == "rate" and #command > 0 then
			local refreshRate = tonumber(table.remove(command, 1));
			g.config['_rate'] = refreshRate;
			if refreshRate >= 0 then
				CHAT_SYSTEM("CharSimulator : set refresh rate="..refreshRate);
			else
				CHAT_SYSTEM("CharSimulator : turn off 'try on' refresh");
			end
			CHARSIM_SAVE();
		elseif subcmd == "sub" then
			local handle = session.GetMyHandle();
			local key = info.GetName(handle)..' '..info.GetFamilyName(handle)..'_eq';
			if g.config[key] == nil or g.config[key]['_sub'] == nil then
				if g.config[key] == nil then
					g.config[key] = {};
				end
				g.config[key]['_sub'] = true;
				CHAT_SYSTEM("CharSimulator : 'try on' sub equip display turned ON for " .. info.GetName(handle));
			else
				g.config[key]['_sub'] = nil;
				CHAT_SYSTEM("CharSimulator : 'try on' sub equip display turned OFF for " .. info.GetName(handle));
			end
			CHAT_SYSTEM('You may need to switch channel or map to take effect');
			CHARSIM_SAVE();
		else
			CHAT_SYSTEM("CharSimulator : Available commands are:");
			CHAT_SYSTEM("/sim : toggle simulator UI");
			CHAT_SYSTEM("/sim rate [number] : set 'try on' refresh rate. 0 = refresh every frames. -1 = disable refresh");
			CHAT_SYSTEM("/sim sub : toggle 'try on' sub equip display. Turning on can make some sub equip unusable");
		end
	else
		CHARSIM_UPDATE_APC(0);
		ui.ToggleFrame('charsim');
	end
end


function CHARSIM_ON_INIT(addon, frame)
	acutil.slashCommand('/sim',CHARSIM_CMD);
	CHAT_SYSTEM("CharSimulator loaded! Use /sim to open simulator. For help, use /sim help");

	addon:RegisterMsg("GAME_START_3SEC", "CHARSIM_LOAD");
	addon:RegisterMsg("FPS_UPDATE", "CHARSIM_FPSUPDATE");
end

for key,value in pairs(getmetatable(GetMyPCObject())) do
    print(key, value)
end
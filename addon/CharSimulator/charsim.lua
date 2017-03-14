--TODO: Check status_dummypc (GET_PORTRAIT_IMG_NAME, SET_EQUIP_LIST) Check beautyhair (item.ChangeHeadAppearance(hairIndex);)

local acutil = require('acutil');
CHAT_SYSTEM("Charsim loaded! Use /sim to open simulator");

local equippableSlot = {
	'HELMET', 'HAT_T', 'HAT', 'HAT_L', 'HAIR', 'LENS', 'OUTER', 'LH', 'RH', 'ARMBAND', 'DYE'
};

local availableEquip = {}; -- [SlotName] = {dropdown index => '', ClassName, ClassName, ...}
local availableEquipCount = {} -- [SlotName] = count
local currentEquip = {}; -- [SlotName] = dropdown index

function CHARSIM_INIT_SETTING()
	currentEquip = {};
	for i, slotName in ipairs(equippableSlot) do
		currentEquip[slotName] = 0;
	end
end

-- Check for character equipment compatibility. Use ies string
function CHARSIM_CHECKEQUIP_COMPAT(myjobStr, mygenderStr, equipjob, equipgender)
	local jobCompat = false;
	local genderCompat = false;
	if equipjob == 'All' or string.find(equipjob, myjobStr) then
		jobCompat = true;
	end
	if equipgender == 'Both' or equipgender == mygenderStr then
		genderCompat = true;
	end
	return jobCompat and genderCompat;
end

-- Refresh available equipment and dropdown list.
function CHARSIM_REFRESHLIST()
	-- Get player's job and gender in string that is compatible with ies
	local job = math.floor(session.GetHaveJobIdByIndex(0)/1000); --SW:1 Wiz:2 Archer:3 Cleric:4
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
		availableEquip[slotName][0] = '';
		availableEquipCount[slotName] = 1;
	end

	-- Refresh equip list
	local itemClassList, itemClassCount = GetClassList("Item");
	for i=0, itemClassCount-1 do
		local itemClass = GetClassByIndexFromList(itemClassList, i);
		--For some reason, there are items that we can GetClassByIndexFromList(classList, index) but cannot GetClass(ies, className)
		if GetClass("Item",itemClass.ClassName) ~= nil then
			if string.find(itemClass.ClassName, '_hairColor') ~= nil then
				-- Hair color is handled here, since we cant test slotName against anything in ies to determine it
				local dropdownIndex = availableEquipCount['DYE'];
				availableEquip['DYE'][dropdownIndex] = itemClass.ClassName;
				availableEquipCount['DYE'] = availableEquipCount['DYE']+1;
			else
				-- Something else, filter for valid equip
				local defaultEqpSlot = TryGetProp(itemClass,'DefaultEqpSlot');
				local usejob = TryGetProp(itemClass,'UseJob');
				local usegender = TryGetProp(itemClass,'UseGender');
				if defaultEqpSlot ~= nil and usejob ~= nil and usegender ~= nil and CHARSIM_CHECKEQUIP_COMPAT(job,gender,usejob,usegender) then
					-- Filter slot
					local targetSlot = nil;
					for j, slotName in ipairs(equippableSlot) do
						if slotName == defaultEqpSlot then
							targetSlot = slotName;
							break;
						end
					end
					-- Set dropdown index => ClassName map
					if targetSlot ~= nil then
						local dropdownIndex = availableEquipCount[targetSlot];
						availableEquip[targetSlot][dropdownIndex] = itemClass.ClassName;
						availableEquipCount[targetSlot] = availableEquipCount[targetSlot]+1;
					end
				end
			end
		end
	end

	-- Refresh dropdown
	local frame = ui.GetFrame('charsim');
	for i, slotName in ipairs(equippableSlot) do
		local dropdown = GET_CHILD_RECURSIVELY(frame, 'dropdown_'..slotName);
		if dropdown ~= nil then
			dropdown = tolua.cast(dropdown,'ui::CDropList');
			dropdown:ClearItems();
			for j=0, availableEquipCount[slotName]-1 do
				if j == 0 then
					dropdown:AddItem(0, 'Default');
				else
					local itemClass = GetClass("Item",availableEquip[slotName][j]);
					local itemName = dictionary.ReplaceDicIDInCompStr(itemClass.Name);
					dropdown:AddItem(j, itemName);
				end
			end
			-- Select current item
			local selectedIndex = currentEquip[slotName];
			if selectedIndex >= dropdown:GetItemCount() then
				currentEquip[slotName] = 0;
				dropdown:SelectItem(0);
			else
				dropdown:SelectItem(currentEquip[slotName]);
			end
		end
	end
end

-- Update appearance PC with specified rotation (0:reset 1:CCW 2:CW)
function CHARSIM_UPDATE_APC(rotation)
	local pcSession = session.GetMySession();
    if pcSession == nil then
        return
    end
    
    local apc = pcSession:GetPCDummyApc();
    local hairName = "None";
    local hairColor = "default";
    for i, slotName in ipairs(equippableSlot) do
    	local dropdownIndex = currentEquip[slotName];
    	local className = availableEquip[slotName][dropdownIndex];
    	if slotName == 'DYE' then
    		if className ~= '' then
    			local itemClass = GetClass("Item",className);
    			hairColor = itemClass.StringArg;
    		end
    	else
    		if className == '' then
	    		apc:SetEquipItem(item.GetEquipSpotNum(slotName), 0);
    		else
    			local itemClass = GetClass("Item",className);
    			apc:SetEquipItem(item.GetEquipSpotNum(slotName), itemClass.ClassID);
    			if(slotName == 'HAIR') then
    				hairName = itemClass.StringArg;
	    		end
    		end
    	end
    end
    -- Special case for dye
	local headIndexByItem = ui.GetHeadIndexByXML(apc:GetGender(), hairName, hairColor);
	apc:SetHeadType(headIndexByItem);

    local imgName = ui.CaptureMyFullStdImageByAPC(apc,rotation);

    local frame = ui.GetFrame('charsim');
    local picture = GET_CHILD_RECURSIVELY(frame, 'apc', 'ui::CPicture');
    picture:SetImage(imgName);
end

-- Apply equipment change. Call this after dropdown item is selected
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

function CHARSIM_UPDATEROTATION_CCW()
	CHARSIM_UPDATE_APC(1);
end

function CHARSIM_UPDATEROTATION_CW()
	CHARSIM_UPDATE_APC(2);
end

function CHARSIM_TOGGLE_UI()
	CHARSIM_UPDATE_APC(0);
	ui.ToggleFrame('charsim');
end

function CHARSIM_ON_INIT(addon, frame)
	CHARSIM_INIT_SETTING();
	CHARSIM_REFRESHLIST();
	acutil.slashCommand('/sim',CHARSIM_TOGGLE_UI);
end
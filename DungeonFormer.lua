--- DungeonFormer Main File ---

-- Addon namespace
-- luacheck: globals UIParent DEFAULT_CHAT_FRAME CreateFrame SendWho GetNumWhoResults GetWhoInfo SendChatMessage InviteUnit SlashCmdList UIDropDownMenu_SetText UIDropDownMenu_AddButton Print DungeonFormerBlacklist DungeonFormerFrame DungeonFormerDungeonDropdown DungeonFormerClassFilter DungeonFormerScanButton DungeonFormerScrollFrame DungeonFormerScrollChild DungeonFormerAutoInviteCheck DungeonFormerVerboseCheck DungeonFormerFrameCloseButton Dungeons tonumber ipairs pairs string table

DungeonFormer = {}

-- Configuration
local config = {
    startLevel = 1,
    endLevel = 60,
    message = "Hey! Looking for a group for [dungeon]? We need more people.",
    autoInvite = false, -- Toggles instant invites vs. just messaging
    verbose = true,
    inviteInterval = 2 -- seconds between sending invites/messages
}

-- Player database
local playerDB = {}

local searchResults = {}

-- Dungeons List (sname is for the message)
Dungeons = { -- Global scope for dropdown access
    { name = "[13-18] Ragefire Chasm", low = 13, high = 18, sname = "Ragefire Chasm" },
    { name = "[17-24] Wailing Caverns", low = 17, high = 24, sname = "Wailing Caverns" },
    { name = "[17-26] The Deadmines", low = 17, high = 26, sname = "The Deadmines" },
    { name = "[22-30] Shadowfang Keep", low = 22, high = 30, sname = "Shadowfang Keep" },
    { name = "[24-32] Blackfathom Deeps", low = 24, high = 32, sname = "Blackfathom Deeps" },
    { name = "[24-32] The Stockade", low = 24, high = 32, sname = "The Stockade" },
    { name = "[29-38] Gnomeregan", low = 29, high = 38, sname = "Gnomeregan" },
    { name = "[29-38] Razorfen Kraul", low = 29, high = 38, sname = "Razorfen Kraul" },
    { name = "[26-36] SM: Graveyard", low = 26, high = 36, sname = "SM Graveyard" },
    { name = "[29-39] SM: Library", low = 29, high = 39, sname = "SM Library" },
    { name = "[32-42] SM: Armory", low = 32, high = 42, sname = "SM Armory" },
    { name = "[35-45] SM: Cathedral", low = 35, high = 45, sname = "SM Cathedral" },
    { name = "[37-46] Razorfen Downs", low = 37, high = 46, sname = "Razorfen Downs" },
    { name = "[41-51] Uldaman", low = 41, high = 51, sname = "Uldaman" },
    { name = "[42-46] Zul'Farrak", low = 42, high = 56, sname = "Zul'Farrak" },
    { name = "[46-55] Maraudon", low = 46, high = 55, sname = "Maraudon" },
    { name = "[50-56] Sunken Temple", low = 50, high = 56, sname = "Sunken Temple" },
    { name = "[52-60] Blackrock Depths", low = 52, high = 60, sname = "Blackrock Depths" },
    { name = "[55-60] L. Blackrock Spire", low = 55, high = 60, sname = "LBRS" },
    { name = "[55-60] U. Blackrock Spire", low = 55, high = 60, sname = "UBRS" },
    { name = "[55-60] Dire Maul East", low = 55, high = 60, sname = "Dire Maul East" },
    { name = "[55-60] Dire Maul West", low = 55, high = 60, sname = "Dire Maul West" },
    { name = "[55-60] Dire Maul North", low = 55, high = 60, sname = "Dire Maul North" },
    { name = "[58-60] Scholomance", low = 58, high = 60, sname = "Scholomance" },
    { name = "[58-60] Stratholme", low = 58, high = 60, sname = "Stratholme" },
}

local currentDungeon = nil
local selectedDungeonIndex = nil

-- UI Elements (will be populated on ADDON_LOADED)
local ui = {}

-- Utility Functions
-- Note to linter: DEFAULT_CHAT_FRAME is a global provided by the WoW API.
function DungeonFormer:Print(message)
    if config.verbose then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99DungeonFormer:|r " .. message)
    end
end

-- New function for unconditional debug printing
function DebugPrint(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffeda55f[DF_Debug]|r " .. message)
end

-- Core Functions
function DungeonFormer:StartScan(dungeonIndex, classes)
    DebugPrint("StartScan called with DungeonIndex: " .. tostring(dungeonIndex) .. ", Classes: " .. tostring(classes))
    if not dungeonIndex or not Dungeons[dungeonIndex] then
        DungeonFormer:Print("Invalid dungeon index. Please select a dungeon from the dropdown.")
        return
    end

    currentDungeon = Dungeons[dungeonIndex]
    config.startLevel = currentDungeon.low
    config.endLevel = currentDungeon.high
    
    local whoQuery = config.startLevel .. "-" .. config.endLevel
    if classes and classes ~= "" then
        whoQuery = whoQuery .. " c-" .. classes
    end

    DungeonFormer:Print("Starting scan for " .. currentDungeon.name .. ".")
    searchResults = {} -- Clear previous results
    DungeonFormer:UpdateResultsList() -- Clear the UI
    -- Note to linter: SendWho is a global function provided by the WoW API.
    SendWho(whoQuery)
    DebugPrint("Sent /who query: " .. whoQuery)
end

function DungeonFormer:ProcessWhoList()
    -- Note to linter: GetNumWhoResults and GetWhoInfo are global functions provided by the WoW API.
    DebugPrint("WHO_LIST_UPDATE event received.")
    local numResults = GetNumWhoResults()
    DungeonFormer:Print("Processing " .. numResults .. " players from /who list.")
    for i=1, numResults do
        local name, _, level, _, class, zone = GetWhoInfo(i)
        if name and not playerDB[name] and not DungeonFormerBlacklist[name] then
            table.insert(searchResults, {name=name, level=level, class=class, zone=zone})
            DebugPrint("Added player to search results: " .. name .. " (Level " .. level .. " " .. class .. ")")
        end
    end
    DungeonFormer:UpdateResultsList()
end

function DungeonFormer:UpdateResultsList()
    -- Clear previous results from scroll frame by hiding all of its children
    -- We iterate backwards to avoid issues with modifying the table while iterating
    if not DungeonFormerScrollChild then
        DebugPrint("ERROR: DungeonFormerScrollChild is missing!")
        return
    end
    for i = DungeonFormerScrollChild:GetNumChildren(), 1, -1 do
        local child = select(i, DungeonFormerScrollChild:GetChildren())
        child:Hide()
        child:SetParent(nil)
    end

    -- Create new UI elements for the current search results
    for i, player in ipairs(searchResults) do
        local yPos = -((i - 1) * 30)

        -- Player info text
        local infoText = DungeonFormerScrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        infoText:SetText(string.format("%s - Lvl %d %s", player.name, player.level, player.class))
        infoText:SetPoint("TOPLEFT", 20, yPos - 10)
        infoText:Show()

        -- Whisper Button
        local whisperButton = CreateFrame("Button", nil, DungeonFormerScrollChild, "UIPanelButtonTemplate")
        whisperButton:SetText("Whisper")
        whisperButton:SetSize(70, 22)
        whisperButton:SetPoint("TOPRIGHT", -165, yPos - 5)
        whisperButton:SetScript("OnClick", function()
            if not currentDungeon then
                DungeonFormer:Print("Please select a dungeon first.")
                return
            end
            local dungeonName = (currentDungeon and currentDungeon.sname) or "the dungeon"
            local finalMessage = string.gsub(config.message, "%%[dungeon%%]", dungeonName)
            SendChatMessage(finalMessage, "WHISPER", nil, player.name)
            playerDB[player.name] = {messaged = true, replied = false}
            DungeonFormer:Print("Messaged " .. player.name .. ": '" .. finalMessage .. "'")
        end)
        whisperButton:Show()

        -- Invite Button
        local inviteButton = CreateFrame("Button", nil, DungeonFormerScrollChild, "UIPanelButtonTemplate")
        inviteButton:SetText("Invite")
        inviteButton:SetSize(70, 22)
        inviteButton:SetPoint("LEFT", whisperButton, "RIGHT", 5, 0)
        inviteButton:SetScript("OnClick", function()
            InviteUnit(player.name)
            DungeonFormer:Print("Invited " .. player.name .. " to the group.")
        end)
        inviteButton:Show()

        -- Blacklist Button
        local blacklistButton = CreateFrame("Button", nil, DungeonFormerScrollChild, "UIPanelButtonTemplate")
        blacklistButton:SetText("Blacklist")
        blacklistButton:SetSize(70, 22)
        blacklistButton:SetPoint("LEFT", inviteButton, "RIGHT", 5, 0)
        blacklistButton:SetScript("OnClick", function()
            DungeonFormerBlacklist[player.name] = true
            DungeonFormer:Print(player.name .. " has been blacklisted.")
            -- Remove from current search results and refresh the list
            for j, p in ipairs(searchResults) do
                if p.name == player.name then
                    table.remove(searchResults, j)
                    break
                end
            end
            DungeonFormer:UpdateResultsList()
        end)
        blacklistButton:Show()
        DebugPrint("UI row created for player: " .. player.name)
    end
    if DungeonFormerScrollFrame then DungeonFormerScrollFrame:Show() end
    DungeonFormerScrollChild:Show()
    DebugPrint("Results UI updated and shown.")

    -- Set the scrollable area height based on the number of results
    local resultCount = table.getn(searchResults)
    DungeonFormerScrollChild:SetHeight(resultCount * 30)
end

-- Event Handling & Main Frame
-- Note to linter: CreateFrame is a global function provided by the WoW API.
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("WHO_LIST_UPDATE")
eventFrame:RegisterEvent("CHAT_MSG_WHISPER")

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == "DungeonFormer" then
        DebugPrint("ADDON_LOADED event received for DungeonFormer.")
        -- Load saved variables. DungeonFormerBlacklist is our global table defined in the .toc file.
        if DungeonFormerBlacklist == nil then
            DebugPrint("Blacklist not found, creating new table.")
            DungeonFormerBlacklist = {}
        end
        
        -- Initialize settings database
        if not DungeonFormer.db then
            DebugPrint("Settings database not found, creating new table.")
            DungeonFormer.db = {
                autoInvite = config.autoInvite,
                verbose = config.verbose
            }
        end

        -- Initialize tab switching logic
        DebugPrint("Initializing tab switching logic")
        -- No need to load a separate addon - DungeonFormerTabs.xml is already included via DungeonFormer.xml
        
        -- Define the tab switching function if it doesn't exist
        if not DungeonFormer_SelectTab then
            function DungeonFormer_SelectTab(tabIndex)
                DebugPrint("Switching to tab: " .. tabIndex)
                
                -- Direct frame references - no getglobal needed in WoW 1.12
                -- Hide all tabs first
                if DungeonFormerScanTab then 
                    DungeonFormerScanTab:Hide() 
                    DebugPrint("DungeonFormerScanTab exists and is now hidden")
                else
                    DebugPrint("ERROR: DungeonFormerScanTab is nil")
                end
                
                if DungeonFormerSettingsTab then 
                    DungeonFormerSettingsTab:Hide() 
                    DebugPrint("DungeonFormerSettingsTab exists and is now hidden")
                else
                    DebugPrint("ERROR: DungeonFormerSettingsTab is nil")
                end
                
                if DungeonFormerBlacklistTab then 
                    DungeonFormerBlacklistTab:Hide() 
                    DebugPrint("DungeonFormerBlacklistTab exists and is now hidden")
                else
                    DebugPrint("ERROR: DungeonFormerBlacklistTab is nil")
                end
                
                -- Show the selected tab
                if tabIndex == 1 then
                    if DungeonFormerScanTab then
                        DungeonFormerScanTab:Show()
                        DebugPrint("DungeonFormerScanTab is now shown")
                    end
                elseif tabIndex == 2 then
                    if DungeonFormerSettingsTab then
                        DungeonFormerSettingsTab:Show()
                        DebugPrint("DungeonFormerSettingsTab is now shown")
                    end
                elseif tabIndex == 3 then
                    if DungeonFormerBlacklistTab then
                        DungeonFormerBlacklistTab:Show()
                        DebugPrint("DungeonFormerBlacklistTab is now shown")
                    end
                end
            end
            DebugPrint("Tab switching function created")
        end

        -- Initialize UI elements for new tabbed layout
        ui.frame = DungeonFormerFrame
        ui.dungeonDropdown = DungeonFormerDungeonDropdown
        ui.classFilter = DungeonFormerClassFilter
        ui.scanButton = DungeonFormerScanButton
        ui.resultsFrame = DungeonFormerScrollFrame
        ui.autoInviteCheck = DungeonFormerAutoInviteCheck
        ui.verboseCheck = DungeonFormerVerboseCheck

        -- Dropdown setup
        if DungeonFormerDungeonDropdown then
            UIDropDownMenu_Initialize(DungeonFormerDungeonDropdown, DungeonFormer_Dropdown_Initialize)
            UIDropDownMenu_SetWidth(DungeonFormerDungeonDropdown, 220)
            UIDropDownMenu_SetSelectedID(DungeonFormerDungeonDropdown, 1)
            UIDropDownMenu_SetText("Select Dungeon", DungeonFormerDungeonDropdown)
            DebugPrint("Dropdown initialized on load.")
        else
            DebugPrint("ERROR: DungeonFormerDungeonDropdown missing!")
        end
        -- Checkboxes (Settings Tab)
        if DungeonFormerAutoInviteCheck then
            DungeonFormerAutoInviteCheck:SetChecked(DungeonFormer.db.autoInvite)
            DungeonFormerAutoInviteCheck:SetScript("OnClick", function(self)
                DungeonFormer.db.autoInvite = self:GetChecked()
                DungeonFormer:Print("Auto-invite is now " .. (DungeonFormer.db.autoInvite and "ON" or "OFF"))
                DebugPrint("Auto-invite checkbox clicked: " .. tostring(DungeonFormer.db.autoInvite))
            end)
        end
        if DungeonFormerVerboseCheck then
            DungeonFormerVerboseCheck:SetChecked(DungeonFormer.db.verbose)
            DungeonFormerVerboseCheck:SetScript("OnClick", function(self)
                DungeonFormer.db.verbose = self:GetChecked()
                DungeonFormer:Print("Verbose mode is now " .. (DungeonFormer.db.verbose and "ON" or "OFF"))
                DebugPrint("Verbose checkbox clicked: " .. tostring(DungeonFormer.db.verbose))
            end)
        end
        -- Scan button (Scan Tab)
        if DungeonFormerScanButton then
            DungeonFormerScanButton:SetScript("OnClick", function()
                local selectedID = UIDropDownMenu_GetSelectedID(DungeonFormerDungeonDropdown)
                local classFilter = DungeonFormerClassFilter:GetText()
                DungeonFormer:StartScan(selectedID, classFilter)
            end)
        end
    elseif event == "WHO_LIST_UPDATE" then
        DungeonFormer:ProcessWhoList()
    elseif event == "CHAT_MSG_WHISPER" then
        -- Optionally handle whispers for reply tracking
    end
end)

function DungeonFormer_OnLoad()
    DebugPrint("DungeonFormer_OnLoad called. Checking UI frame globals...")
    DebugPrint("DungeonFormerFrame: " .. tostring(DungeonFormerFrame))
    DebugPrint("DungeonFormerScrollFrame: " .. tostring(DungeonFormerScrollFrame))
    DebugPrint("DungeonFormerScrollChild: " .. tostring(DungeonFormerScrollChild))
    DebugPrint("DungeonFormerDungeonDropdown: " .. tostring(DungeonFormerDungeonDropdown))
    DebugPrint("DungeonFormerClassFilter: " .. tostring(DungeonFormerClassFilter))
    DebugPrint("DungeonFormerScanButton: " .. tostring(DungeonFormerScanButton))
    DebugPrint("DungeonFormerAutoInviteCheck: " .. tostring(DungeonFormerAutoInviteCheck))
    DebugPrint("DungeonFormerVerboseCheck: " .. tostring(DungeonFormerVerboseCheck))
    DebugPrint("--- End UI frame existence check ---")
    DebugPrint("DungeonFormer_OnLoad called")
    -- Dropdown setup
    if DungeonFormerDungeonDropdown then
        UIDropDownMenu_Initialize(DungeonFormerDungeonDropdown, DungeonFormer_Dropdown_Initialize)
        UIDropDownMenu_SetWidth(DungeonFormerDungeonDropdown, 220)
        UIDropDownMenu_SetSelectedID(DungeonFormerDungeonDropdown, 1)
        UIDropDownMenu_SetText("Select Dungeon", DungeonFormerDungeonDropdown)
        DebugPrint("Dropdown initialized on load.")
    else
        DebugPrint("ERROR: DungeonFormerDungeonDropdown missing!")
    end
    -- Checkboxes
    if DungeonFormerAutoInviteCheck then
        DungeonFormerAutoInviteCheck:SetChecked(DungeonFormer.db.autoInvite)
        DungeonFormerAutoInviteCheck:SetScript("OnClick", function(self)
            DungeonFormer.db.autoInvite = self:GetChecked()
            DungeonFormer:Print("Auto-invite is now " .. (DungeonFormer.db.autoInvite and "ON" or "OFF"))
            DebugPrint("Auto-invite checkbox clicked: " .. tostring(DungeonFormer.db.autoInvite))
        end)
    end
    if DungeonFormerVerboseCheck then
        DungeonFormerVerboseCheck:SetChecked(DungeonFormer.db.verbose)
        DungeonFormerVerboseCheck:SetScript("OnClick", function(self)
            DungeonFormer.db.verbose = self:GetChecked()
            DungeonFormer:Print("Verbose mode is now " .. (DungeonFormer.db.verbose and "ON" or "OFF"))
            DebugPrint("Verbose checkbox clicked: " .. tostring(DungeonFormer.db.verbose))
        end)
    end
    -- Scan button
    if DungeonFormerScanButton then
        DungeonFormerScanButton:SetScript("OnClick", function()
            local id = UIDropDownMenu_GetSelectedID(DungeonFormerDungeonDropdown)
            if not id then
                DungeonFormer:Print("Please select a dungeon first.")
                return
            end
            local classes = DungeonFormerClassFilter and DungeonFormerClassFilter:GetText() or ""
            DungeonFormer:StartScan(id, classes)
            DungeonFormerFrame:Show()
            DungeonFormerScrollFrame:Show()
            DungeonFormerScrollChild:Show()
            DebugPrint("Scan button clicked. Scan started for dungeon id: " .. tostring(id) .. ", classes: " .. classes)
        end)
        DebugPrint("Scan button handler set.")
    end
    DebugPrint("DungeonFormer_OnLoad complete.")
end

-- Consolidated dropdown initialization function
function DungeonFormer_Dropdown_Initialize(self, level)
    -- Make sure Dungeons table exists and has entries
    if not Dungeons or #Dungeons == 0 then
        DebugPrint("ERROR: Dungeons table is empty or nil!")
        return
    end
    
    DebugPrint("Initializing dropdown with " .. #Dungeons .. " dungeons")
    
    -- Clear any existing entries first
    UIDropDownMenu_ClearAll(self)
    
    for i, dungeon in ipairs(Dungeons) do
        local info = {}
        info.text = dungeon.name
        info.value = i
        info.func = function(self)
            local index = self:GetID()
            UIDropDownMenu_SetSelectedID(DungeonFormerDungeonDropdown, index)
            UIDropDownMenu_SetText(Dungeons[index].name, DungeonFormerDungeonDropdown)
            DebugPrint("Dungeon selected: " .. Dungeons[index].name)
            DungeonFormer.currentDungeon = index
            return index
        end
        UIDropDownMenu_AddButton(info, level)
    end
end

-- Wrapper function for backward compatibility
function DungeonFormer:PopulateDungeonDropdown()
    DebugPrint("Populating dungeon dropdown via wrapper function...")
    if DungeonFormerDungeonDropdown then
        UIDropDownMenu_Initialize(DungeonFormerDungeonDropdown, DungeonFormer_Dropdown_Initialize)
        UIDropDownMenu_SetWidth(DungeonFormerDungeonDropdown, 220)
        UIDropDownMenu_SetSelectedID(DungeonFormerDungeonDropdown, 1)
        UIDropDownMenu_SetText("Select Dungeon", DungeonFormerDungeonDropdown)
        DebugPrint("Dropdown initialized successfully.")
    else
        DebugPrint("ERROR: DungeonFormerDungeonDropdown missing!")
    end
end

function DungeonFormer:ToggleUI()
    if not DungeonFormerFrame then
        DebugPrint("ERROR: DungeonFormerFrame is nil! UI cannot be toggled.")
        return
    end
    
    if DungeonFormerFrame:IsShown() then
        DungeonFormerFrame:Hide()
        DebugPrint("UI hidden")
    else
        DungeonFormerFrame:Show()
        -- Select the first tab by default when showing the UI
        if DungeonFormer_SelectTab then
            DungeonFormer_SelectTab(1)
            DebugPrint("Selected first tab by default")
        end
        DebugPrint("UI shown")
    end
end

-- Slash Command Handler
-- Note to linter: SlashCmdList is a global table provided by the WoW API.
SLASH_DUNGEONFORMER1 = "/dungeonformer"
SLASH_DUNGEONFORMER2 = "/df"

function SlashCmdList.DUNGEONFORMER(text, editBox)
    text = text or ""
    DebugPrint("Slash command received: /df " .. text)
    local command = ""
    local rest = ""
    local spacePos = string.find(text, " ")
    if spacePos then
        command = string.sub(text, 1, spacePos - 1)
        rest = string.sub(text, spacePos + 1)
    else
        command = text
    end
    command = string.lower(command)
    rest = string.lower(rest)

    if command == "" then
        -- Try to show the UI; if frames are missing, attempt to reinitialize
        DungeonFormer:ToggleUI()
        local uiReady = DungeonFormerFrame and DungeonFormerFrame.Show and DungeonFormerScrollFrame and DungeonFormerScrollFrame.Show and DungeonFormerScrollChild and DungeonFormerScrollChild.Show
        if not uiReady then
            DebugPrint("UI frames missing after ToggleUI. Attempting to reinitialize UI via DungeonFormer_OnLoad().")
            if DungeonFormer_OnLoad then DungeonFormer_OnLoad() end
        end
        -- Try again to show frames after reinit
        if DungeonFormerFrame and DungeonFormerFrame.Show then
            DungeonFormerFrame:Show()
        else
            DebugPrint("ERROR: DungeonFormerFrame is still nil or missing Show method after reinit!")
        end
        if DungeonFormerScrollFrame and DungeonFormerScrollFrame.Show then
            DungeonFormerScrollFrame:Show()
        else
            DebugPrint("ERROR: DungeonFormerScrollFrame is still nil or missing Show method after reinit!")
        end
        if DungeonFormerScrollChild and DungeonFormerScrollChild.Show then
            DungeonFormerScrollChild:Show()
        else
            DebugPrint("ERROR: DungeonFormerScrollChild is still nil or missing Show method after reinit!")
            -- Optionally, create a minimal fallback frame here
        end
        -- The command proceeds regardless of UI frame state

    elseif command == "scan" then
        local dungeonIndex = ""
        local classes = ""
        local spacePos = string.find(rest, " ")
        if spacePos then
            dungeonIndex = string.sub(rest, 1, spacePos - 1)
            classes = string.sub(rest, spacePos + 1)
        else
            dungeonIndex = rest
        end
        DungeonFormer:StartScan(tonumber(dungeonIndex), classes)
        DungeonFormerFrame:Show()
        if DungeonFormerScrollFrame then DungeonFormerScrollFrame:Show() end
        if DungeonFormerScrollChild then DungeonFormerScrollChild:Show() end
    elseif command == "stop" then
        searchResults = {}
        DungeonFormer:UpdateResultsList()
        DungeonFormer:Print("All messaging stopped and results cleared.")
    elseif command == "msg" then
        config.message = rest
        DungeonFormer:Print("New message set to: '" .. rest .. "'")
    elseif command == "list" then
        DungeonFormer:Print("Available Dungeons:")
        for i, d in ipairs(Dungeons) do
            DEFAULT_CHAT_FRAME:AddMessage(i .. ": " .. d.name)
        end
    elseif command == "blacklist" then
        if rest and rest ~= "" then
            DungeonFormerBlacklist[rest] = true
            DungeonFormer:Print(rest .. " has been blacklisted.")
        else
            DungeonFormer:Print("Blacklisted Players:")
            for name, _ in pairs(DungeonFormerBlacklist) do
                DungeonFormer:Print("- " .. name)
            end
        end
    elseif command == "unblacklist" then
        if rest and rest ~= "" then
            DungeonFormerBlacklist[rest] = nil
            DungeonFormer:Print(rest .. " has been unblacklisted.")
        else
            DungeonFormer:Print("Usage: /df unblacklist [playername]")
        end
    elseif command == "clearblacklist" then
        DungeonFormerBlacklist = {}
        DungeonFormer:Print("Blacklist cleared.")
    elseif command == "clear" then
        playerDB = {}
        DungeonFormer:Print("Player database cleared.")
    elseif command == "verbose" then
        config.verbose = not config.verbose
        DungeonFormer:Print("Verbose mode is now " .. (config.verbose and "ON" or "OFF"))
    else
        DungeonFormer:Print("--- DungeonFormer Help ---")
        DungeonFormer:Print("/df - Toggles the main UI.")
        DungeonFormer:Print("/df scan [dungeon_index] [classes] - Scans for players.")
        DungeonFormer:Print("/df stop - Stops scanning and clears results.")
        DungeonFormer:Print("/df msg [message] - Sets the whisper message.")
        DungeonFormer:Print("/df list - Lists available dungeons with their index.")
        DungeonFormer:Print("/df blacklist [name] - Adds a player to the blacklist.")
        DungeonFormer:Print("/df blacklist - Shows the blacklist.")
        DungeonFormer:Print("/df unblacklist [name] - Removes a player from the blacklist.")
        DungeonFormer:Print("/df clearblacklist - Clears the entire blacklist.")
        DungeonFormer:Print("/df clear - Clears the temporary player database.")
        DungeonFormer:Print("/df verbose - Toggles verbose messages.")
    end
end

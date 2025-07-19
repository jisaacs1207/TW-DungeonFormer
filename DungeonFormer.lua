--- DungeonFormer Main File ---

-- Addon namespace
-- luacheck: globals UIParent DEFAULT_CHAT_FRAME CreateFrame SendWho GetNumWhoResults GetWhoInfo SendChatMessage InviteUnit SlashCmdList UIDropDownMenu_SetText UIDropDownMenu_AddButton Print DungeonFormerBlacklist DungeonFormerFrame DungeonFormerDungeonDropdown DungeonFormerClassFilter DungeonFormerScanButton DungeonFormerScrollFrame DungeonFormerScrollChild DungeonFormerAutoInviteCheck DungeonFormerVerboseCheck DungeonFormerFrameCloseButton tonumber ipairs pairs string table

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
local Dungeons = {
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
local function DebugPrint(message)
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
        whoQuery = whoQuery .. " c-\"" .. classes .. "\""
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
    DebugPrint("Updated results list with " .. #searchResults .. " players.")
end

function DungeonFormer:UpdateResultsList()
    -- Clear previous results from scroll frame
    -- Note to linter: DungeonFormerScrollChild is the child frame of the ScrollFrame defined in XML.
    DungeonFormerScrollChild:SetHeight(0)
    DebugPrint("Cleared previous results from scroll frame.")

    for i, player in ipairs(searchResults) do
        local yPos = -((i-1) * 30)

        -- Player info text
        local infoText = DungeonFormerScrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        infoText:SetText(string.format("%s - Lvl %d %s", player.name, player.level, player.class))
        infoText:SetPoint("TOPLEFT", 20, yPos - 10)
        DebugPrint("Created player info text for " .. player.name)

        -- Whisper Button
        -- Note to linter: CreateFrame is a global function from the WoW API to create UI elements.
        local whisperButton = CreateFrame("Button", nil, DungeonFormerScrollChild, "UIPanelButtonTemplate")
        whisperButton:SetText("Whisper")
        whisperButton:SetSize(70, 22)
        whisperButton:SetPoint("TOPRIGHT", -165, yPos - 5)
        whisperButton:SetScript("OnClick", function()
            if not currentDungeon then
                DungeonFormer:Print("Please select a dungeon first.")
                return
            end
            DebugPrint("Whisper button clicked for: " .. player.name)
            local finalMessage = string.gsub(config.message, "%%[dungeon%%]", currentDungeon.sname)
            SendChatMessage(finalMessage, "WHISPER", nil, player.name)
            playerDB[player.name] = {messaged = true, replied = false}
            DungeonFormer:Print("Messaged " .. player.name .. ": '" .. finalMessage .. "'")
        end)

        -- Invite Button
        local inviteButton = CreateFrame("Button", nil, DungeonFormerScrollChild, "UIPanelButtonTemplate")
        inviteButton:SetText("Invite")
        inviteButton:SetSize(70, 22)
        inviteButton:SetPoint("LEFT", whisperButton, "RIGHT", 5, 0)
        inviteButton:SetScript("OnClick", function()
            DebugPrint("Invite button clicked for: " .. player.name)
            InviteUnit(player.name)
            DungeonFormer:Print("Invited " .. player.name .. " to the group.")
        end)

        -- Blacklist Button
        local blacklistButton = CreateFrame("Button", nil, DungeonFormerScrollChild, "UIPanelButtonTemplate")
        blacklistButton:SetText("Blacklist")
        blacklistButton:SetSize(70, 22)
        blacklistButton:SetPoint("LEFT", inviteButton, "RIGHT", 5, 0)
        blacklistButton:SetScript("OnClick", function()
            DebugPrint("Blacklist button clicked for: " .. player.name)
            DungeonFormerBlacklist[player.name] = true
            DungeonFormer:Print(player.name .. " has been blacklisted.")
            -- Remove from search results and refresh the list
            for j, p in ipairs(searchResults) do
                if p.name == player.name then
                    table.remove(searchResults, j)
                    break
                end
            end
            DungeonFormer:UpdateResultsList()
        end)

        DungeonFormerScrollChild:SetHeight(i * 30)
        DebugPrint("Updated scroll frame height to " .. (i * 30))
    end
end

-- Event Handling & Main Frame
-- Note to linter: CreateFrame is a global function provided by the WoW API.
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("WHO_LIST_UPDATE")
eventFrame:RegisterEvent("CHAT_MSG_WHISPER")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" and ... == "DungeonFormer" then
        DebugPrint("ADDON_LOADED event received for DungeonFormer.")
        -- Load saved variables. DungeonFormerBlacklist is our global table defined in the .toc file.
        -- The game client will automatically load it. We just need to ensure it's a table if it's the first time.
        if DungeonFormerBlacklist == nil then
            DebugPrint("Blacklist not found, creating new table.")
            DungeonFormerBlacklist = {}
        end

        -- Initialize UI elements
        -- Note to linter: The following globals are frames and widgets defined in DungeonFormer.xml
        ui.frame = DungeonFormerFrame
        ui.dungeonDropdown = DungeonFormerDungeonDropdown
        ui.classFilter = DungeonFormerClassFilter
        ui.scanButton = DungeonFormerScanButton
        ui.resultsFrame = DungeonFormerScrollFrame
        ui.autoInviteCheck = DungeonFormerAutoInviteCheck
        ui.verboseCheck = DungeonFormerVerboseCheck

        -- Populate the dropdown
        DungeonFormer:PopulateDungeonDropdown()
        DebugPrint("Populated dungeon dropdown.")

        -- Sync checkboxes with config
        ui.autoInviteCheck:SetChecked(config.autoInvite)
        ui.verboseCheck:SetChecked(config.verbose)

        ui.autoInviteCheck:SetScript("OnClick", function(self)
            config.autoInvite = self:GetChecked()
            DungeonFormer:Print("Auto-invite is now " .. (config.autoInvite and "ON" or "OFF"))
            DebugPrint("Auto-invite checkbox clicked: " .. tostring(config.autoInvite))
        end)

        ui.verboseCheck:SetScript("OnClick", function(self)
            config.verbose = self:GetChecked()
            DungeonFormer:Print("Verbose mode is now " .. (config.verbose and "ON" or "OFF"))
            DebugPrint("Verbose checkbox clicked: " .. tostring(config.verbose))
        end)

        -- Set button scripts
        ui.scanButton:SetScript("OnClick", function()
            DebugPrint("Scan button clicked.")
            local classes = ui.classFilter:GetText()
            DungeonFormer:StartScan(selectedDungeonIndex, classes)
        end)

        -- Note to linter: DungeonFormerFrameCloseButton is also defined in the XML.
        DungeonFormerFrameCloseButton:SetScript("OnClick", function()
            DebugPrint("Close button clicked.")
            DungeonFormerFrame:Hide()
        end)

        DungeonFormer:Print("Addon loaded. Type /df to toggle the UI.")
        DebugPrint("Addon loaded.")
    elseif event == "WHO_LIST_UPDATE" then
        DebugPrint("WHO_LIST_UPDATE event handled.")
        DungeonFormer:ProcessWhoList()
    elseif event == "CHAT_MSG_WHISPER" then
        local message, author = ...
        if playerDB[author] and playerDB[author].messaged then
            DungeonFormer:Print("|cff00ff00Reply from " .. author .. ":|r " .. message)
            playerDB[author].replied = true
        end
    end
end)



function DungeonFormer:PopulateDungeonDropdown()
    -- Note to linter: UIDropDownMenu_SetText and UIDropDownMenu_AddButton are global functions provided by the WoW API.
    local function OnSelect(self, index)
        selectedDungeonIndex = index
        UIDropDownMenu_SetText(ui.dungeonDropdown, Dungeons[index].name)
    end

    for i, dungeon in ipairs(Dungeons) do
        local info = {}
        info.text = dungeon.name
        info.func = function() OnSelect(Dungeons, i) end
        UIDropDownMenu_AddButton(info)
    end
end

function DungeonFormer:ToggleUI()
    DebugPrint("ToggleUI called. Current state: " .. (ui.frame:IsShown() and "Shown" or "Hidden"))
    if ui.frame:IsShown() then
        ui.frame:Hide()
    else
        ui.frame:Show()
    end
end

-- Slash Command Handler
-- Note to linter: SlashCmdList is a global table provided by the WoW API.
SLASH_DUNGEONFORMER1 = "/dungeonformer"
SLASH_DUNGEONFORMER2 = "/df"

function SlashCmdList.DUNGEONFORMER(msg, editBox)
    DebugPrint("Slash command received: /df " .. msg)
    local command, rest = msg:match("([^ ]*) ?(.*)")
    command = command and string.lower(command) or ""
    rest = rest and string.lower(rest) or ""

    if command == "" then
        DungeonFormer:ToggleUI()
    elseif command == "scan" then
        local dungeonIndex, classes = rest:match("([^ ]*) (.*)")
        DungeonFormer:StartScan(tonumber(dungeonIndex), classes)
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

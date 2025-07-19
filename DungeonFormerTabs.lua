-- DungeonFormerTabs.lua
-- Handles tab switching and dynamic UI logic for pfUI-inspired tabbed interface

function DungeonFormer_SelectTab(tabIndex)
    -- Hide all tab content frames
    DungeonFormerScanTab:Hide()
    DungeonFormerSettingsTab:Hide()
    DungeonFormerBlacklistTab:Hide()
    
    -- Deselect all tabs
    PanelTemplates_DeselectTab(DungeonFormerTab1)
    PanelTemplates_DeselectTab(DungeonFormerTab2)
    PanelTemplates_DeselectTab(DungeonFormerTab3)

    -- Show the selected tab and select it
    if tabIndex == 1 then
        DungeonFormerScanTab:Show()
        PanelTemplates_SelectTab(DungeonFormerTab1)
    elseif tabIndex == 2 then
        DungeonFormerSettingsTab:Show()
        PanelTemplates_SelectTab(DungeonFormerTab2)
    elseif tabIndex == 3 then
        DungeonFormerBlacklistTab:Show()
        PanelTemplates_SelectTab(DungeonFormerTab3)
    end
end

-- OnLoad hook for main frame to default to first tab
function DungeonFormer_OnLoadTabs()
    DungeonFormer_SelectTab(1)
end

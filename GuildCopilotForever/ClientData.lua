local _, GC = ...

GC.Constants.INTERFACE_VERSION = 16001
GC.Constants.COMM_PREFIX = "GCPForever"
GC.Constants.ARMORY_CHARACTER_URL = ""
GC.Constants.WCL_CHARACTER_URL = ""
GC.Constants.WCL_DEFAULT_HOST = ""
GC.LeadLevelMax = GC.Client.maxLevel

-- No verified Forever raid catalogue or enchant recommendations yet. Use an
-- editable search plan and guild-authored rules, never silently reuse TBC BiS.
GC.RaidInstances = {}
GC.RaidBosses = {}
GC.Consumables = {}
GC.EnchantRecipeKeys = {}
GC.CoverageRules = {}
GC.ContentPhases = { { key = "FOREVER_BETA", label = "WoW Forever Beta", order = 1 } }
GC.ContentPhaseByKey = { FOREVER_BETA = GC.ContentPhases[1] }
GC.DefaultContentPhase = "FOREVER_BETA"
GC.EnchantRuleSet = { version = 1, phase = "FOREVER_BETA", source = "Gildenregeln für WoW Forever", rules = {} }
-- Equipment remains inspectable. Mandatory enchant slots need a verified
-- Forever ruleset before they can be scored as missing.
for _, slot in ipairs(GC.GearSlots) do slot.enchantRequired = false end
local capabilities = {}
for _, capability in ipairs(GC.Capabilities) do
    if capability ~= "raidmonitor" and capability ~= "wclimport" then
        capabilities[#capabilities + 1] = capability
    end
end
capabilities[#capabilities + 1] = "forever1"
GC.Capabilities = capabilities

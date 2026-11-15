-- MarketForces: event dispatch.
-- One hidden frame receives every game event and fans it out to listeners.
-- Modules also talk to each other through "messages" so they never need to
-- reference each other directly (e.g. Scan sends "MF_SCAN_COMPLETE",
-- Prices listens for it).
local _, MF = ...

local frame = CreateFrame("Frame", "MarketForcesEventFrame")
MF.eventFrame = frame

local events = {}   -- event -> { [owner] = handler }
local messages = {} -- message -> { [owner] = handler }

local function dispatch(registry, name, ...)
    local listeners = registry[name]
    if not listeners then return end
    for owner, handler in pairs(listeners) do
        local ok, err
        if type(handler) == "string" then
            ok, err = pcall(owner[handler], owner, name, ...)
        else
            ok, err = pcall(handler, owner, name, ...)
        end
        if not ok then
            MF:Print("|cffff4444error|r in", name, "handler:", err)
        end
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    dispatch(events, event, ...)
end)

-- owner:handler(event, ...) is called when the game fires the event.
-- handler is a function or a method name on owner; it defaults to the
-- event name, so a module can just define Module:AUCTION_HOUSE_SHOW().
function MF:RegisterEvent(event, owner, handler)
    owner = owner or self
    handler = handler or event
    if not events[event] then
        events[event] = {}
        frame:RegisterEvent(event)
    end
    events[event][owner] = handler
end

function MF:UnregisterEvent(event, owner)
    owner = owner or self
    local listeners = events[event]
    if not listeners then return end
    listeners[owner] = nil
    if next(listeners) == nil then
        events[event] = nil
        frame:UnregisterEvent(event)
    end
end

function MF:UnregisterAllEvents(owner)
    for event in pairs(events) do
        self:UnregisterEvent(event, owner)
    end
end

function MF:RegisterMessage(message, owner, handler)
    owner = owner or self
    messages[message] = messages[message] or {}
    messages[message][owner] = handler or message
end

function MF:UnregisterMessage(message, owner)
    owner = owner or self
    if messages[message] then
        messages[message][owner] = nil
    end
end

function MF:UnregisterAllMessages(owner)
    for message in pairs(messages) do
        self:UnregisterMessage(message, owner)
    end
end

function MF:SendMessage(message, ...)
    dispatch(messages, message, ...)
end

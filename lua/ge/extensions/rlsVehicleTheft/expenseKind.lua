-- Classify only direct vehicle spending that belongs in the Underground profit estimate.
local function hasTag(tags, wanted)
  if type(tags) ~= "table" then return false end
  if tags[wanted] then return true end
  for _, tag in ipairs(tags) do if tag == wanted then return true end end
  return false
end

return function(reason, amount)
  if type(reason) ~= "table" or type(amount) ~= "number" then return nil end
  if amount < 0 then
    if hasTag(reason.tags, "vehiclePainting") then return "paint" end
    if hasTag(reason.tags, "partsBought") then return "parts" end
    if hasTag(reason.tags, "tuning") then return "tuning" end
    if reason.category == "repair" then return "repair" end
  elseif amount > 0 and reason.category == "refund" and type(reason.label) == "string"
    and reason.label:match("^Vehicle repair refund: id ") then
    return "repair"
  end
end

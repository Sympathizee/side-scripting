--MAXIME
local selectedQuests = {{}}
function startStep11(retest)
	local remainHours, remainMinutes, remainSeconds = nil
	local userid = getElementData(client, "account:id")
	local faData = exports.mysql:query_fetch_assoc("SELECT (UNIX_TIMESTAMP(NOW())-UNIX_TIMESTAMP(`forceapp_date`)) AS `secdiff` FROM `force_apps` WHERE `account`='"..userid.."' LIMIT 1")
	if faData and faData["secdiff"] and tonumber(faData["secdiff"]) then
		
		local secdiff = tonumber(faData["secdiff"])
		local secsInADay = 60*60*24
						-- sec,min,hour
		if secdiff < secsInADay then
			remainHours = math.floor((secsInADay-secdiff)/60/60)
			if remainHours <= 0 then
				remainMinutes = math.floor((secsInADay-secdiff)/60)
				if remainMinutes <= 0 then
					remainSeconds = math.floor(secsInADay-secdiff)
				end
			end
		else
			exports.mysql:query_free("DELETE FROM `force_apps` WHERE `account`='"..userid.."' ")
		end
	end
	
	selectedQuests[client] = {}
	local quests = {} 
	local preparedQ = ""
	local mQuery = nil
	
	
	triggerEvent("apps:finishStep1", client)
end
addEvent("apps:startStep11", true)
addEventHandler("apps:startStep11", root, startStep11)

function isThisQuestSelected(client, quest)
	for i = 1, #selectedQuests[client] do
		if quest == selectedQuests[client][i] then
			return true
		end
	end
	return false
end

function finishStep1()
	if source and isElement(source) and getElementType(source) == "player" then
		client = source
	end
	local id = getElementData(client, "account:id")
	if id then
		local preparedQuery = "UPDATE `account_details` SET `appstate`='1' WHERE `account_id`='"..id.."' "
		exports.mysql:query_free(preparedQuery)
	end
	triggerEvent("apps:startStep2", client)
end
addEvent("apps:finishStep1", true)
addEventHandler("apps:finishStep1", root, finishStep1)
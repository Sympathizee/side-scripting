--[[
* ***********************************************************************************************************************
* Copyright (c) 2015 OwlGaming Community - All Rights Reserved
* All rights reserved. This program and the accompanying materials are private property belongs to OwlGaming Community
* Unauthorized copying of this file, via any medium is strictly prohibited
* Proprietary and confidential
* ***********************************************************************************************************************
]]

local resultPool = { }
local queryPool = { }
local sqllog = false
local countqueries = 0
local lastInsertId = false

function getMySQLUsername() return username end
function getMySQLPassword() return password end
function getMySQLDBName() return db end
function getMySQLHost() return host end
function getMySQLPort() return port end
function getForumsPrefix() return externalprefix end

function tellMeMySQLStates(thePlayer)
	if exports.integration:isPlayerScripter(thePlayer) then
		local conn = getConn('mta')
		if conn then
			outputChatBox("Main DB is online.", thePlayer, 0, 255, 0)
		else
			outputChatBox("Main DB is offline.", thePlayer, 255, 0, 0)
		end
	end
end
addCommandHandler("testdb", tellMeMySQLStates, false, false)

function connectToDatabase(res)
	return nil
end

function destroyDatabaseConnection()
	return nil
end

function logSQLError(str)
	local message = str or 'N/A'
	outputDebugString("MYSQL ERROR: " .. message)
end

function getFreeResultPoolID()
	local size = #resultPool
	if (size == 0) then return 1 end
	for index, query in ipairs(resultPool) do
		if (query == nil) then return index end
	end
	return (size + 1)
end

function ping()
	local conn = getConn('mta')
	if conn then return true else return false end
end

function escape_string(self, str)
	if not str then
		str = self
	end
	if str then
		local s = string.gsub(tostring(str), "(['\"\\%z])", function(c)
			if c == "\0" then return "\\0" end
			return "\\" .. c
		end)
		return s
	end
	return false
end

function query(str)
	if sqllog then outputDebugString(str) end
	countqueries = countqueries + 1

	local conn = getConn('mta')
	if not conn then return false end

	local qh = dbQuery(conn, str)
	if not qh then
		logSQLError(str)
		return false
	end

	local result, num_affected_rows, last_insert_id = dbPoll(qh, -1)
	if result == nil then
		logSQLError(str)
		return false
	end

	if last_insert_id and last_insert_id > 0 then
		lastInsertId = last_insert_id
	end

	local resultid = getFreeResultPoolID()
	resultPool[resultid] = {
		data = result or {},
		current_row = 1,
		num_rows = result and #result or 0,
		affected_rows = num_affected_rows
	}
	queryPool[resultid] = str
	return resultid
end

function unbuffered_query(str)
	return query(str)
end

function query_free(str)
	local queryresult = query(str)
	if queryresult then
		free_result(queryresult)
		return true
	end
	return false
end

function rows_assoc(resultid)
	if (not resultPool[resultid]) then return false end
	return resultPool[resultid].data
end

function fetch_assoc(resultid)
	local res = resultPool[resultid]
	if not res then return false end
	if res.current_row > res.num_rows then return false end
	
	local row = res.data[res.current_row]
	res.current_row = res.current_row + 1
	return row
end

function free_result(resultid)
	if (not resultPool[resultid]) then return false end
	resultPool[resultid] = nil
	queryPool[resultid] = nil
	return nil
end

function result(resultid, row_offset, field_offset)
	local res = resultPool[resultid]
	if not res then return false end
	if not res.data[row_offset] then return false end
	
	local i = 1
	for k, v in pairs(res.data[row_offset]) do
		if i == field_offset then return v end
		i = i + 1
	end
	return false
end

function num_rows(resultid)
	if (not resultPool[resultid]) then return false end
	return resultPool[resultid].num_rows
end

function insert_id()
	return lastInsertId or false
end

function query_fetch_assoc(str)
	local queryresult = query(str)
	if not (queryresult == false) then
		local result = fetch_assoc(queryresult)
		free_result(queryresult)
		return result
	end
	return false
end

function query_rows_assoc(str)
	local queryresult = query(str)
	if not (queryresult == false) then
		local result = rows_assoc(queryresult)
		free_result(queryresult)
		return result
	end
	return false
end

function query_insert_free(str)
	local queryresult = query(str)
	if not (queryresult == false) then
		local result = insert_id()
		free_result(queryresult)
		return result
	end
	return false
end

function debugMode()
	sqllog = not sqllog
	return sqllog
end

function returnQueryStats()
	return countqueries
end

function getOpenQueryStr(resultid)
	if (not queryPool[resultid]) then return false end
	return queryPool[resultid]
end

local resources = {
	["mysql"] = getResourceFromName("mysql"),
	["shop-system"] = getResourceFromName("npc"),
	["vehicle-manager"] = getResourceFromName("vehicle_manager"),
}

addCommandHandler( 'mysqlleaky',
	function(thePlayer)
		if exports.integration:isPlayerScripter(thePlayer) then
			outputChatBox("#queryPool="..tostring(countqueries), thePlayer)
		end
	end
)

local function createWhereClause( array, required )
	if not array then
		return not required and '' or nil
	end
	local strings = { }
	for i, k in pairs( array ) do
		table.insert( strings, "`" .. i .. "` = '" .. ( tonumber( k ) or escape_string( k ) ) .. "'" )
	end
	return ' WHERE ' .. table.concat(strings, ' AND ')
end

function select( tableName, clause )
	local array = {}
	local result = query( "SELECT * FROM " .. tableName .. createWhereClause( clause ) )
	if result then
		while true do
			local a = fetch_assoc( result )
			if not a then break end
			table.insert(array, a)
		end
		free_result( result )
		return array
	end
	return false
end

function select_one( tableName, clause )
	local a
	local result = query( "SELECT * FROM " .. tableName .. createWhereClause( clause ) .. ' LIMIT 1' )
	if result then
		a = fetch_assoc( result )
		free_result( result )
		return a
	end
	return false
end

function insert( tableName, array )
	local keyNames = { }
	local values = { }
	for i, k in pairs( array ) do
		table.insert( keyNames, i )
		table.insert( values, tonumber( k ) or escape_string( k ) )
	end

	local q = "INSERT INTO `"..tableName.."` (`" .. table.concat( keyNames, "`, `" ) .. "`) VALUES ('" .. table.concat( values, "', '" ) .. "')"

	return query_insert_free( q )
end

function update( tableName, array, clause )
	local strings = { }
	for i, k in pairs( array ) do
        local val = ""
        if type(mysql_null) == "function" and k == mysql_null() then
            val = "NULL"
        elseif k == "NULL" then
            val = "NULL"
        else
            val = "'" .. (tonumber(k) or escape_string(k)) .. "'"
        end
		table.insert( strings, "`" .. i .. "` = " .. val )
	end
	local q = "UPDATE `" .. tableName .. "` SET " .. table.concat( strings, ", " ) .. createWhereClause( clause, true )

	return query_free( q )
end

function delete( tableName, clause )
	return query_free( "DELETE FROM " .. tableName .. createWhereClause( clause, true ) )
end

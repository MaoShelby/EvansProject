script_name("АвтоБазар")
script_author("Cosmo")
script_version("2.0")

local se = require "samp.events"

DIR = getWorkingDirectory() .. "\\config"
PATH = DIR .. "\\prices.ab"
AB_AREA = {
	-2154.29, -744.62, -- [A]
	-2113.49, -975.06  -- [B]
}

PLATES = {}
MARKERS = {}
V = {}

parsing = {
	active = false,
	last_body = nil,
	timer = 0
}

if doesFileExist(PATH) then
	local file = io.open(PATH, "r")
	V = decodeJson(file:read("*a"))
	file:close()

	if type(V) ~= "table" then
		V = {}
	end
end

function VCount()
	local i = 0
	for _, _ in pairs(V) do
		i = i + 1
	end
	return i
end

function save_prices()
	if not doesDirectoryExist(DIR) then
		createDirectory(DIR)
	end

	local file = io.open(PATH, "w")
	file:write(encodeJson(V))
	file:close()
end

do -- Custom string's methods
	local mt = getmetatable("")
	local lower = string.lower
	function mt.__index:lower() -- Patch string.lower() for working with Cyrillic
		for i = 192, 223 do
			self = self:gsub(string.char(i), string.char(i + 32))
		end
		self = self:gsub(string.char(168), string.char(184))
		return lower(self)
	end
	function mt.__index:split(sep, plain) -- Splits a string by separator
		result, pos = {}, 1
		repeat
			local s, f = self:find(sep or " ", pos, plain)
			result[#result + 1] = self:sub(pos, s and s - 1)
			pos = f and f + 1
		until pos == nil
		return result
	end
end

function chatMessage(message, ...)
	message = ("[Автобазар] {EEEEEE}" .. message):format(...)
	return sampAddChatMessage(message, 0xFF6640)
end

function convertToPriceFormat(num)
	num = tostring(num)
	if num ~= nil and #num > 3 then
		local b, e = ("%d"):format(num):gsub("^%-", "")
		local c = b:reverse():gsub("%d%d%d", "%1.")
		local d = c:reverse():gsub("^%.", "")
		return (e == 1 and "-" or "") .. d
	end
	return num
end

function findListInDialog(text, style, search)
	local t_text = text:split("\n")
	if style == 5 then
		table.remove(t_text, 1)
	end

	for i, line in ipairs(t_text) do
		if line:find(search, 1, true) then
			return (i - 1)
		end
	end
	return nil
end

function isViceCity()
	local ip, port = sampGetCurrentServerAddress()
	local address = ("%s:%s"):format(ip, port)
	return (address == "80.66.82.147:7777")
end

function sampSetRaceCheckpoint(type, x, y, z, radius)
	local bs = raknetNewBitStream()
	raknetBitStreamWriteInt8(bs, type)
	raknetBitStreamWriteFloat(bs, x)
	raknetBitStreamWriteFloat(bs, y)
	raknetBitStreamWriteFloat(bs, z)
	raknetBitStreamWriteFloat(bs, 0)
	raknetBitStreamWriteFloat(bs, 0)
	raknetBitStreamWriteFloat(bs, 0)
	raknetBitStreamWriteFloat(bs, radius)
	raknetEmulRpcReceiveBitStream(38, bs)
	raknetDeleteBitStream(bs)
end

function sampDisableRaceCheckpoint()
	local bs = raknetNewBitStream()
	raknetEmulRpcReceiveBitStream(39, bs)
	raknetDeleteBitStream(bs)
end

function parsePage(text)
	for line in string.gmatch(text, "[^\n]+") do
		local model, price = string.match(line, "^(.+)\t%$?([0-9%.,]+)%$?$")
		if model and price then
			price = string.gsub(price, "[%.,]", "")
			price = tonumber(price)
			if price ~= nil then
				V[model] = price
			end
		end
	end
end

function main()
	assert(isSampLoaded(), "SA:MP is required!")
	repeat wait(0) until isSampAvailable()

	local dialogId = 1001345 -- Идентификатор диалога

	sampRegisterChatCommand("ab", function(arg)
		if VCount() == 0 then
			chatMessage("Средние цены на автомобили не загружены!")
			if isViceCity() then
				chatMessage("Загрузить их можно на специальном пикапе автобазара")
			else
				chatMessage("Загрузить их можно на специальном пикапе (отмечено на карте)")
				sampSetRaceCheckpoint(2, -2131.36, -745.71, 32.02, 1)   
				CHECKPOINT = { -2131.36, -745.71 }
			end
			return nil
		elseif string.find(arg, "^[%s%c]*$") then
			return chatMessage("Используйте: /ab [ Название транспорта ]", 0xFFB03B)
		end
	
		local results = {}
	
		arg = string.lower(arg)
		for model, price in pairs(V) do
			if string.find(string.lower(model), arg, 1, true) then
				table.insert(results, {
					model = model,
					price = price
				})
			end
		end
	
		if #results == 0 then
			chatMessage("Не найдено ни одного автомобиля с похожим названием")
		else
			local dialogText
			if #results > 50 then
				dialogText = "Выведено наиболее похожих моделей транспорта:\n\n"
			else
				dialogText = ""
			end
	
			for i, v in ipairs(results) do
				local price = convertToPriceFormat(v.price)
				dialogText = dialogText .. string.format("%s - {FF6640}$%s\n", v.model, price)
				if i >= 50 then break end
			end
	
			sampShowDialog(dialogId, "Рынок Автомобилей", dialogText, "OK", "", 5)
		end
	end)

	while true do
		wait(0)
		if CHECKPOINT ~= nil then
			local x, y, z = getCharCoordinates(PLAYER_PED)
			local dist = getDistanceBetweenCoords2d(CHECKPOINT[1], CHECKPOINT[2], x, y)
			if dist <= 3.00 then
				sampDisableRaceCheckpoint()
				CHECKPOINT = nil
			end
		end

		if parsing.active and os.clock() - parsing.timer > 5.00 then
			chatMessage("Не удалось просканировать цены! Превышено время ожидания ответа от сервера.")
			parsing.active = false
		end
	end
end

function onScriptTerminate(scr, is_quit)
	if scr == thisScript() then
		if CHECKPOINT ~= nil then
			sampDisableRaceCheckpoint()
			CHECKPOINT = nil
		end

		for handle, _ in pairs(MARKERS) do
			removeUser3dMarker(handle)
			MARKERS[handle] = nil
		end
	end
end

function se.onSetRaceCheckpoint(type, pos_1, pos_2, size)
	CHECKPOINT = nil
end

function se.onShowDialog(id, style, header, but_1, but_2, body)
	-- \\ Главное окно средних цен на транспорт
	if style == 5 and string.find(header, "Средняя цена автомобилей при продаже") then
		if not parsing.active then
			body = string.gsub(body, "Поиск по названию\t \n", "%1{70FF70}Просканировать цены\t \n", 1)
		end

		if parsing.active then
			if body == parsing.last_body then
				save_prices()
				parsing.active = false
				chatMessage("Сканирование завершено! Транспорта в базе: {FF6640}%d", VCount())
				sampSendDialogResponse(id, 0, 0, nil)
				return false
			else
				parsePage(body)
			end

			parsing.last_body = body
			parsing.timer = os.clock()
			local list = findListInDialog(body, style, "Следующая страница")
			if list ~= nil then
				sampSendDialogResponse(id, 1, list, nil)
				return false
			else
				chatError("Неизвестная ошибка! Невозможно продолжить сканирование.")
				return { id, 0, list, input }
			end
		else
			if VCount() > 0 then
				parsePage(body)
				save_prices()
			end

			body = string.gsub(body, "%$(%d+)", function(num)
				local price = convertToPriceFormat(num)
				return "$" .. price
			end)
		end
	end

	-- \\ Окно средних цен на транспорт, найденных через поиск в пикапе
	if style == 5 and string.find(header, "Средние цены продажи авто") then
		parsePage(body)
		save_prices()

		body = string.gsub(body, "(%d+)%$", function(num)
			local price = convertToPriceFormat(num)
			return "$" .. price
		end)
	end

	-- \\ Окно детальной статистики продаж транспортного средства
	if style == 5 and string.find(header, "Продажа транспорта \'.-\' за последние %d+ дней") then
		body = string.gsub(body, "%$(%d+)", function(num)
			local price = convertToPriceFormat(num)
			return "$" .. price
		end)
	end

	-- \\ Окно просмотра технического паспорта транспорта
	if style == 0 and string.find(header, "Технический паспорт транспорта") then
		local model = string.match(body, "Транспорт: {%x+}(.-)%[%d+%]{%x+}")
		
		local average_price
		if model ~= nil and V[model] ~= nil then
			average_price = ("{FFFFFF}Средняя цена на рынке: {73B461}$%d"):format(V[model])
		else
			average_price = "{AAAAAA}Средняя рыночная цена неизвестна"
		end

		body = body .. average_price
		body = string.gsub(body, "%$(%d+)", function(num)
			local price = convertToPriceFormat(num)
			return "$" .. price
		end)
	end

	-- \\ Окно подтверждения покупки транспортного средства
	if style == 0 and string.find(header, "Подтверждение покупки") then
		local price, comm = string.match(body, "Стоимость транспорта: {%x+}%$(%d+) %+ %$(%d+)%( Комиссия %)")
		if price and comm then
			local sum = tonumber(price) + tonumber(comm)
			body = body .. ("\n\n{FFFFFF}Итоговая цена: {FF6640}$%d"):format(sum)
		end

		body = string.gsub(body, "%$(%d+)", function(num)
			local price = convertToPriceFormat(num)
			return "$" .. price
		end)
	end

	-- \\ Окно ввода ставки для транспорта на аукционе
	if style == 1 and string.find(header, "Поставить ставку") and string.find(body, "Выбранный транспорт") then
		body = string.gsub(body, "%$(%d+)", function(num)
			local price = convertToPriceFormat(num)
			return "$" .. price
		end)
	end

	return { id, style, header, but_1, but_2, body }
end

function se.onSendDialogResponse(id, button, list, input)
	if not parsing.active and button == 1 then
		local header = sampGetDialogCaption()
		local style = sampGetCurrentDialogType()
		local body = sampGetDialogText()

		-- \\ Запуск сканирования средних цен
		if style == 5 and string.find(header, "Средняя цена автомобилей при продаже") then
			local list_go = findListInDialog(body, style, "Просканировать цены")
			if list_go ~= nil then
				if list == list_go then
					chatMessage("Идёт сканирование средних цен, не открывайте другие диалоговые окна..")
					
					V = {}
					parsePage(body)

					parsing.active = true
					parsing.last_body = nil
					parsing.timer = os.clock()
					return { id, button, list + 1, input }
				elseif list > list_go then
					return { id, button, list - 1, input }
				end
			end
		end
	end
end

function se.onSetObjectMaterialText(id, data)
	local object = sampGetObjectHandleBySampId(id)
	if doesObjectExist(object) then
		if getObjectModel(object) == 18663 then
			if isObjectInArea2d(object, AB_AREA[1], AB_AREA[2], AB_AREA[3], AB_AREA[4], false) then
				do -- \\ Обычная продажа транспорта
					local model, price = string.match(data.text, "(.-)\n{%x+}%$(%d+)")
					if model and price then
						local _, x, y, z = getObjectCoordinates(object)
						local str_i = string.format("%d/%d/%d", x, y, z)
						local str_v = string.format("%s/%s", model, price)
						if PLATES[str_i] ~= str_v then
							PLATES[str_i] = str_v
							
							price = convertToPriceFormat(price)

							if isCharInArea2d(PLAYER_PED, AB_AREA[1], AB_AREA[2], AB_AREA[3], AB_AREA[4], false) then
								chatMessage("На продажу выставлен: {FF6640}%s{EEEEEE} за {FF6640}$%s", model, price)
								if V[model] ~= nil then
									local average = convertToPriceFormat(V[model])
									chatMessage("Средняя рыночная цена: {AAAAAA}$%s", average)
								else
									chatMessage("Средняя рыночная цена {AAAAAA}неизвестна")
								end
							end

							local marker = createUser3dMarker(x, y, z + 2, 0)
							MARKERS[marker] = true
							lua_thread.create(function()
								wait(10000)
								removeUser3dMarker(marker)
								MARKERS[marker] = nil
							end)
						end
					end
				end

				do -- \\ Выставление транспорта на аукцион
					local model = string.match(data.text, "^Аукцион №%d+\n([^\n]+)")
					if model then
						local _, x, y, z = getObjectCoordinates(object)
						local str_i = string.format("%d/%d/%d", x, y, z)
						local str_v = string.format("%s", model)
						if PLATES[str_i] ~= str_v then
							PLATES[str_i] = str_v

							if isCharInArea2d(PLAYER_PED, AB_AREA[1], AB_AREA[2], AB_AREA[3], AB_AREA[4], false) then
								chatMessage("Новый транспорт на аукционе: {FF6640}%s", model)
							end

							local marker = createUser3dMarker(x, y, z + 2, 0)
							MARKERS[marker] = true
							lua_thread.create(function()
								wait(10000)
								removeUser3dMarker(marker)
								MARKERS[marker] = nil
							end)
						end
					end
				end

				-- \\ Разделение цифр в ценах на табличках
				data.text = string.gsub(data.text, "%$(%d+)", function(num)
					local price = convertToPriceFormat(num)
					return "$" .. price
				end)
			end
		end
	end
	return { id, data }
end
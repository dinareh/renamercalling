-- Simple Remote Renamer (Passive Mode)
-- Переименовывает все RemoteEvents и RemoteFunctions без их активации

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

-- Конфигурация
local CONFIG = {
    WEBHOOK_URL = "https://discord.com/api/webhooks/1434181472423776277/wrgeevBbOT05meDtUawJvTomccDgrCn8qml8x2Y18fRhAswj_fOPE3LLM13-R3bCkC7g",
    SEND_TO_DISCORD = true,
    RENAME_IN_GAME = true,
    DEBUG_MODE = true,
    USE_PARENT_NAMES = true,  -- Использовать имена родительских папок
    ADD_PREFIX = true,         -- Добавлять префикс по типу
    MAX_NAME_LENGTH = 50       -- Максимальная длина имени
}

-- Глобальные переменные
local renamedRemotes = {}
local processedRemotes = 0
local successfullyRenamed = 0

-- Функция для логирования
local function log(message)
    if CONFIG.DEBUG_MODE then
        print("[RemoteRenamer]: " .. message)
    end
end

-- Функция для отправки на Discord вебхук
local function sendToDiscord(message)
    if not CONFIG.SEND_TO_DISCORD or not CONFIG.WEBHOOK_URL then
        return false
    end
    
    local success, result = pcall(function()
        local payload = {
            content = message,
            username = "Passive Remote Renamer",
            avatar_url = "https://cdn.discordapp.com/attachments/1067061486574907412/1067061597392310292/Simple_Spy_logo.png"
        }
        
        local jsonPayload = HttpService:JSONEncode(payload)
        
        -- Пробуем разные методы отправки
        local requestFunc = syn and syn.request or request or http_request
        if requestFunc then
            requestFunc({
                Url = CONFIG.WEBHOOK_URL,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonPayload
            })
        end
        
        return true
    end)
    
    return success
end

-- Функция для поиска всех ремоутов в игре
local function findAllRemotes()
    local remotes = {}
    
    -- Рекурсивная функция поиска
    local function searchIn(instance, depth)
        if depth > 20 then return end -- Ограничение глубины для безопасности
        
        -- Проверяем, является ли ремоутом
        if instance:IsA("RemoteEvent") or instance:IsA("RemoteFunction") or instance:IsA("UnreliableRemoteEvent") then
            table.insert(remotes, {
                Instance = instance,
                Path = instance:GetFullName(),
                OriginalName = instance.Name,
                Parent = instance.Parent,
                ClassName = instance.ClassName,
                Depth = depth
            })
        end
        
        -- Ищем в дочерних объектах
        for _, child in ipairs(instance:GetChildren()) do
            searchIn(child, depth + 1)
        end
    end
    
    -- Начинаем поиск с основных мест
    local startPoints = {
        ReplicatedStorage,
        game:GetService("ServerStorage"),
        game:GetService("ServerScriptService"),
        game:GetService("Workspace"),
        game:GetService("StarterPack"),
        game:GetService("StarterGui"),
        game:GetService("StarterPlayer"),
        game:GetService("Lighting"),
        game:GetService("SoundService")
    }
    
    for _, startPoint in ipairs(startPoints) do
        searchIn(startPoint, 0)
    end
    
    log("Найдено ремоутов: " .. #remotes)
    return remotes
end

-- Функция для анализа структуры папок вокруг ремоута
local function analyzeRemoteContext(remote)
    local context = {
        ParentName = remote.Parent.Name,
        GrandparentName = remote.Parent.Parent and remote.Parent.Parent.Name or "Game",
        SiblingRemotes = 0,
        FolderStructure = {},
        ScriptsNearby = 0
    }
    
    -- Собираем структуру папок (до 3 уровней вверх)
    local current = remote.Parent
    local depth = 0
    while current and current ~= game and depth < 3 do
        table.insert(context.FolderStructure, 1, current.Name)
        current = current.Parent
        depth = depth + 1
    end
    
    -- Считаем другие ремоуты в той же папке
    for _, child in ipairs(remote.Parent:GetChildren()) do
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
            context.SiblingRemotes = context.SiblingRemotes + 1
        end
        -- Считаем скрипты в той же папке
        if child:IsA("Script") or child:IsA("LocalScript") or child:IsA("ModuleScript") then
            context.ScriptsNearby = context.ScriptsNearby + 1
        end
    end
    
    return context
end

-- Функция для генерации имени на основе контекста
local function generateNameFromContext(remote, context)
    local baseName = ""
    
    -- Стратегия 1: Используем имя родительской папки
    if CONFIG.USE_PARENT_NAMES then
        if context.SiblingRemotes > 1 then
            -- Если несколько ремоутов в папке, добавляем индекс
            baseName = context.ParentName .. "_" .. context.SiblingRemotes
        else
            baseName = context.ParentName
        end
    else
        -- Стратегия 2: Используем структуру папок
        if #context.FolderStructure >= 2 then
            baseName = context.FolderStructure[#context.FolderStructure - 1] .. "_" .. context.FolderStructure[#context.FolderStructure]
        elseif #context.FolderStructure >= 1 then
            baseName = context.FolderStructure[#context.FolderStructure]
        else
            baseName = "Remote"
        end
    end
    
    -- Очищаем имя
    local cleanName = baseName:gsub("%s+", "_")
    cleanName = cleanName:gsub("[^%w_]", "")
    
    -- Обрезаем если слишком длинное
    if cleanName:len() > CONFIG.MAX_NAME_LENGTH then
        cleanName = cleanName:sub(1, CONFIG.MAX_NAME_LENGTH)
    end
    
    -- Добавляем префикс по типу
    if CONFIG.ADD_PREFIX then
        if remote:IsA("RemoteEvent") then
            cleanName = "Event_" .. cleanName
        elseif remote:IsA("RemoteFunction") then
            cleanName = "Function_" .. cleanName
        elseif remote:IsA("UnreliableRemoteEvent") then
            cleanName = "Unreliable_" .. cleanName
        end
    else
        -- Или добавляем суффикс
        if remote:IsA("RemoteEvent") then
            cleanName = cleanName .. "_Event"
        elseif remote:IsA("RemoteFunction") then
            cleanName = cleanName .. "_Function"
        end
    end
    
    -- Если рядом есть скрипты, добавляем пометку
    if context.ScriptsNearby > 0 then
        cleanName = cleanName .. "_Scripted"
    end
    
    return cleanName
end

-- Функция для безопасного переименования
local function safeRename(remote, newName)
    local originalName = remote.Name
    
    -- Проверяем, не пытаемся ли переименовать в то же имя
    if originalName == newName then
        return false, "Уже имеет это имя"
    end
    
    -- Проверяем длину имени
    if newName:len() > 100 then
        newName = newName:sub(1, 100)
    end
    
    -- Пробуем переименовать
    local success, errorMsg = pcall(function()
        remote.Name = newName
    end)
    
    if success then
        return true, newName
    else
        -- Пробуем альтернативное имя
        local altName = "Renamed_" .. originalName:gsub("[^%w_]", "")
        local altSuccess, altError = pcall(function()
            remote.Name = altName
        end)
        
        if altSuccess then
            return true, altName
        else
            return false, errorMsg
        end
    end
end

-- Основная функция переименования
local function renameRemotesPassive()
    log("Запуск Passive Remote Renamer...")
    log("Режим: Без активации ремоутов")
    
    -- Находим все ремоуты
    local allRemotes = findAllRemotes()
    log("Всего найдено ремоутов: " .. #allRemotes)
    
    -- Создаем отчет
    local report = "=== ОТЧЕТ О ПЕРЕИМЕНОВАНИИ РЕМОУТОВ ===\n"
    report = report .. "Режим: Passive (без активации)\n"
    report = report .. "Всего ремоутов: " .. #allRemotes .. "\n\n"
    
    local renameCommands = {}
    local renameLog = {}
    local failedRenames = {}
    
    -- Обрабатываем каждый ремоут
    for index, remoteData in ipairs(allRemotes) do
        processedRemotes = processedRemotes + 1
        local remote = remoteData.Instance
        
        log(string.format("Обработка [%d/%d]: %s", index, #allRemotes, remoteData.Path))
        
        -- Анализируем контекст ремоута
        local context = analyzeRemoteContext(remote)
        
        -- Генерируем новое имя на основе контекста
        local newName = generateNameFromContext(remote, context)
        
        -- Пробуем переименовать
        local success, resultName = safeRename(remote, newName)
        
        if success then
            successfullyRenamed = successfullyRenamed + 1
            
            -- Создаем команду для скрипта
            local command = string.format([[
-- Успешно переименован
-- Путь: %s
local remote = game:GetService("%s"):WaitForChild("%s"):WaitForChild("%s")
if remote then
    remote.Name = "%s"
    print("✅ Переименован: %s -> %s")
end]],
                remoteData.Path,
                remote.Parent.ClassName,
                remote.Parent.Name,
                resultName == newName and remoteData.OriginalName or "Renamed_" .. remoteData.OriginalName,
                resultName,
                remoteData.OriginalName,
                resultName
            )
            
            table.insert(renameCommands, command)
            
            -- Записываем в лог
            table.insert(renameLog, {
                OriginalName = remoteData.OriginalName,
                NewName = resultName,
                Path = remoteData.Path,
                ClassName = remoteData.ClassName,
                Context = {
                    Parent = context.ParentName,
                    Siblings = context.SiblingRemotes,
                    Scripts = context.ScriptsNearby
                },
                Success = true
            })
            
            log(string.format("  ✅ %s -> %s", remoteData.OriginalName, resultName))
        else
            -- Записываем неудачную попытку
            table.insert(failedRenames, {
                Remote = remoteData,
                Error = resultName
            })
            
            log(string.format("  ❌ %s -> Ошибка: %s", remoteData.OriginalName, resultName))
        end
        
        -- Небольшая задержка для стабильности
        if index % 10 == 0 then
            wait(0.01)
        end
    end
    
    -- Формируем итоговый скрипт
    local finalScript = "-- === PASSIVE REMOTE RENAME SCRIPT ===\n"
    finalScript = finalScript .. "-- Сгенерировано Passive Remote Renamer\n"
    finalScript = finalScript .. "-- Режим: Без активации ремоутов\n"
    finalScript = finalScript .. "-- Время: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"
    finalScript = finalScript .. "-- Всего ремоутов: " .. #allRemotes .. "\n"
    finalScript = finalScript .. "-- Успешно переименовано: " .. successfullyRenamed .. "\n"
    finalScript = finalScript .. "-- Не удалось: " .. #failedRenames .. "\n\n"
    
    -- Добавляем преамбулу
    finalScript = finalScript .. "print(\"=== Passive Remote Renamer ===\")\n"
    finalScript = finalScript .. string.format('print("Всего ремоутов: %d")', #allRemotes) .. "\n"
    finalScript = finalScript .. string.format('print("Успешно переименовано: %d")', successfullyRenamed) .. "\n"
    finalScript = finalScript .. string.format('print("Не удалось: %d")', #failedRenames) .. "\n\n"
    
    -- Добавляем команды переименования
    if #renameCommands > 0 then
        finalScript = finalScript .. "-- Команды переименования\n"
        for i, command in ipairs(renameCommands) do
            finalScript = finalScript .. command .. "\n\n"
        end
    end
    
    -- Добавляем обработку неудачных попыток
    if #failedRenames > 0 then
        finalScript = finalScript .. "-- Неудачные попытки\n"
        finalScript = finalScript .. "print(\"\\nНеудачные попытки переименования:\")\n"
        
        for i, failed in ipairs(failedRenames) do
            finalScript = finalScript .. string.format('print("%d. %s - %s")', 
                i, 
                failed.Remote.Path, 
                failed.Error) .. "\n"
        end
        finalScript = finalScript .. "\n"
    end
    
    -- Добавляем итог
    finalScript = finalScript .. string.format([[
print("==================================")
print("Passive Remote Renamer завершил работу")
print("Обработано ремоутов: %d")
print("Успешно переименовано: %d")
print("Не удалось: %d")
print("==================================")]],
        processedRemotes,
        successfullyRenamed,
        #failedRenames
    )
    
    -- Копируем в буфер обмена
    if setclipboard then
        setclipboard(finalScript)
        log("Скрипт скопирован в буфер обмена (" .. #finalScript .. " символов)")
    end
    
    -- Формируем подробный отчет
    report = report .. "СТАТИСТИКА:\n"
    report = report .. string.rep("-", 40) .. "\n"
    report = report .. "Обработано: " .. processedRemotes .. "\n"
    report = report .. "Успешно: " .. successfullyRenamed .. "\n"
    report = report .. "Не удалось: " .. #failedRenames .. "\n\n"
    
    if #renameLog > 0 then
        report = report .. "УСПЕШНО ПЕРЕИМЕНОВАННЫЕ РЕМОУТЫ:\n"
        report = report .. string.rep("=", 80) .. "\n"
        
        for i, logEntry in ipairs(renameLog) do
            report = report .. string.format("%-30s → %-30s [%s]\n", 
                logEntry.OriginalName, 
                logEntry.NewName,
                logEntry.ClassName)
            report = report .. "    Путь: " .. logEntry.Path .. "\n"
            report = report .. "    Контекст: Родитель=" .. logEntry.Context.Parent .. 
                         ", Соседи=" .. logEntry.Context.Siblings .. 
                         ", Скрипты=" .. logEntry.Context.Scripts .. "\n"
            report = report .. string.rep("-", 80) .. "\n"
        end
    end
    
    if #failedRenames > 0 then
        report = report .. "\nНЕУДАЧНЫЕ ПОПЫТКИ:\n"
        report = report .. string.rep("=", 80) .. "\n"
        
        for i, failed in ipairs(failedRenames) do
            report = report .. string.format("%s\n", failed.Remote.Path)
            report = report .. "    Ошибка: " .. failed.Error .. "\n"
            report = report .. string.rep("-", 80) .. "\n"
        end
    end
    
    -- Формируем сообщение для Discord
    local discordMessage = "**Passive Remote Renamer - Отчет**\n\n"
    discordMessage = discordMessage .. "**Режим:** Без активации ремоутов\n"
    discordMessage = discordMessage .. "**Статистика:**\n"
    discordMessage = discordMessage .. "```\n"
    discordMessage = discordMessage .. "Всего ремоутов: " .. #allRemotes .. "\n"
    discordMessage = discordMessage .. "Успешно: " .. successfullyRenamed .. "\n"
    discordMessage = discordMessage .. "Не удалось: " .. #failedRenames .. "\n"
    discordMessage = discordMessage .. "```\n\n"
    
    if #renameLog > 0 then
        discordMessage = discordMessage .. "**Примеры переименований:**\n"
        discordMessage = discordMessage .. "```\n"
        
        for i = 1, math.min(10, #renameLog) do
            local logEntry = renameLog[i]
            discordMessage = discordMessage .. string.format("%s → %s\n", 
                logEntry.OriginalName, 
                logEntry.NewName)
        end
        
        if #renameLog > 10 then
            discordMessage = discordMessage .. "... и еще " .. (#renameLog - 10) .. "\n"
        end
        
        discordMessage = discordMessage .. "```\n"
    end
    
    -- Отправляем на Discord
    if CONFIG.SEND_TO_DISCORD then
        local webhookSuccess = sendToDiscord(discordMessage)
        if webhookSuccess then
            log("Отчет отправлен на Discord")
        end
    end
    
    -- Показываем уведомление
    if Players.LocalPlayer then
        spawn(function()
            local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
            local notification = Instance.new("ScreenGui", PlayerGui)
            notification.Name = "RemoteRenamerNotification"
            notification.ResetOnSpawn = false
            
            local frame = Instance.new("Frame", notification)
            frame.Size = UDim2.new(0, 350, 0, 200)
            frame.Position = UDim2.new(0.5, -175, 0.5, -100)
            frame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
            frame.BorderSizePixel = 0
            
            local title = Instance.new("TextLabel", frame)
            title.Size = UDim2.new(1, 0, 0, 40)
            title.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
            title.Text = "Passive Remote Renamer"
            title.TextColor3 = Color3.new(1, 1, 1)
            title.TextSize = 18
            
            local stats = Instance.new("TextLabel", frame)
            stats.Position = UDim2.new(0, 20, 0, 50)
            stats.Size = UDim2.new(1, -40, 0, 80)
            stats.BackgroundTransparency = 1
            stats.Text = string.format("Обработано: %d\nУспешно: %d\nНе удалось: %d\n\nСкрипт в буфере обмена", 
                processedRemotes, 
                successfullyRenamed,
                #failedRenames)
            stats.TextColor3 = Color3.new(1, 1, 1)
            stats.TextSize = 14
            stats.TextWrapped = true
            
            local closeBtn = Instance.new("TextButton", frame)
            closeBtn.Position = UDim2.new(0.5, -50, 1, -40)
            closeBtn.Size = UDim2.new(0, 100, 0, 30)
            closeBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
            closeBtn.Text = "Закрыть"
            closeBtn.TextColor3 = Color3.new(1, 1, 1)
            
            closeBtn.MouseButton1Click:Connect(function()
                notification:Destroy()
            end)
            
            -- Автоматическое закрытие через 15 секунд
            delay(15, function()
                if notification and notification.Parent then
                    notification:Destroy()
                end
            end)
        end)
    end
    
    -- Выводим отчет в консоль
    print("\n" .. report)
    log("Passive Remote Renamer завершил работу")
    
    return {
        TotalRemotes = #allRemotes,
        Processed = processedRemotes,
        SuccessfullyRenamed = successfullyRenamed,
        Failed = #failedRenames,
        Script = finalScript,
        Log = renameLog
    }
end

-- Запускаем переименование
local success, result = pcall(renameRemotesPassive)

if not success then
    log("Критическая ошибка: " .. tostring(result))
    
    -- Простой fallback метод
    log("Пробуем простой метод...")
    
    local simpleSuccess = pcall(function()
        local count = 0
        local function renameAll(obj)
            if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                local newName = "Renamed_" .. obj.Name:gsub("[^%w_]", "")
                pcall(function() obj.Name = newName end)
                count = count + 1
            end
            
            for _, child in ipairs(obj:GetChildren()) do
                renameAll(child)
            end
        end
        
        renameAll(game)
        log("Простой метод переименовал: " .. count .. " ремоутов")
    end)
end

log("Скрипт завершил выполнение")

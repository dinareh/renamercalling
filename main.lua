-- Simple Remote Renamer
-- Автономный скрипт для переименования ремоутов по их calling script

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

-- Настройки
local SETTINGS = {
    MaxNameLength = 50,
    AddRandomSuffix = true,
    RenameAllRemotes = true, -- Переименовать все ремоуты, даже те, что не найдены в логах
    ShowDetailsMenu = true
}

-- Глобальные переменные
local remoteLogs = {}
local originalNames = {}
local renameOperations = {}
local mainGui = nil

-- Утилиты
local function deepClone(tbl, seen)
    if type(tbl) ~= 'table' then return tbl end
    if seen and seen[tbl] then return seen[tbl] end
    
    local copy = {}
    seen = seen or {}
    seen[tbl] = copy
    
    for k, v in pairs(tbl) do
        copy[deepClone(k, seen)] = deepClone(v, seen)
    end
    return setmetatable(copy, getmetatable(tbl))
end

local function getScriptName(scriptInstance)
    if not scriptInstance then return "Unknown" end
    
    local path = {}
    local current = scriptInstance
    
    while current and current ~= game do
        table.insert(path, 1, current.Name)
        current = current.Parent
    end
    
    local fullPath = table.concat(path, "_")
    -- Очищаем от недопустимых символов
    fullPath = fullPath:gsub("[^%w_]", "_")
    
    return fullPath
end

local function generateRemoteName(scriptName, originalName, index)
    local baseName = scriptName
    if baseName == "Unknown" then
        baseName = originalName:gsub("[^%w_]", "_")
    end
    
    local newName = baseName
    
    -- Добавляем суффикс для уникальности
    if SETTINGS.AddRandomSuffix then
        newName = string.format("%s_%03d", newName, math.random(100, 999))
    end
    
    -- Ограничиваем длину
    if #newName > SETTINGS.MaxNameLength then
        newName = newName:sub(1, SETTINGS.MaxNameLength)
    end
    
    -- Гарантируем уникальность в рамках сессии
    newName = string.format("%s_R%d", newName, index or 1)
    
    return newName
end

-- Сбор информации о ремоутах
local function collectRemoteInformation()
    local remotes = {}
    local remoteCount = 0
    
    -- Функция для рекурсивного поиска ремоутов
    local function searchForRemotes(instance)
        if instance:IsA("RemoteEvent") or instance:IsA("RemoteFunction") then
            remoteCount = remoteCount + 1
            table.insert(remotes, {
                Instance = instance,
                OriginalName = instance.Name,
                ClassName = instance.ClassName,
                ParentPath = instance:GetFullName(),
                Index = remoteCount
            })
        end
        
        -- Рекурсивно проверяем дочерние объекты
        for _, child in ipairs(instance:GetChildren()) do
            searchForRemotes(child)
        end
    end
    
    -- Ищем ремоуты во всем игровом дереве
    searchForRemotes(game)
    
    return remotes, remoteCount
end

-- Получение calling script для ремоутов
local function getCallingScriptInfo(remote)
    local callingScripts = {}
    
    -- Пытаемся найти вызовы через hookfunction или другие методы
    if hookfunction and getconnections then
        local success, connections = pcall(getconnections, remote.OnClientEvent)
        if success and connections then
            for _, connection in ipairs(connections) do
                local func = connection.Function
                if func then
                    local env = getfenv(func)
                    local script = env.script
                    if script then
                        table.insert(callingScripts, script)
                    end
                end
            end
        end
    end
    
    -- Альтернативный метод: ищем скрипты, которые могут использовать этот ремоут
    local potentialScripts = {}
    local remoteName = remote.Name
    
    local function searchScripts(instance)
        if instance:IsA("LocalScript") or instance:IsA("Script") then
            -- Проверяем содержимое скрипта (если доступно)
            local source = ""
            pcall(function()
                source = instance.Source
            end)
            
            if source:find(remoteName, 1, true) then
                table.insert(potentialScripts, instance)
            end
        end
        
        for _, child in ipairs(instance:GetChildren()) do
            searchScripts(child)
        end
    end
    
    searchScripts(game)
    
    -- Объединяем результаты
    for _, script in ipairs(potentialScripts) do
        local alreadyExists = false
        for _, existing in ipairs(callingScripts) do
            if existing == script then
                alreadyExists = true
                break
            end
        end
        if not alreadyExists then
            table.insert(callingScripts, script)
        end
    end
    
    return callingScripts
end

-- Создание GUI меню
local function createMenu()
    if mainGui and mainGui.Parent then
        mainGui:Destroy()
    end
    
    mainGui = Instance.new("ScreenGui")
    mainGui.Name = "RemoteRenamerGUI"
    mainGui.ResetOnSpawn = false
    mainGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    
    local MainFrame = Instance.new("Frame")
    MainFrame.Name = "MainFrame"
    MainFrame.Size = UDim2.new(0, 400, 0, 500)
    MainFrame.Position = UDim2.new(0.5, -200, 0.5, -250)
    MainFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    MainFrame.BorderSizePixel = 0
    MainFrame.Parent = mainGui
    
    local TopBar = Instance.new("Frame")
    TopBar.Name = "TopBar"
    TopBar.Size = UDim2.new(1, 0, 0, 30)
    TopBar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    TopBar.BorderSizePixel = 0
    TopBar.Parent = MainFrame
    
    local Title = Instance.new("TextLabel")
    Title.Name = "Title"
    Title.Size = UDim2.new(1, -60, 1, 0)
    Title.Position = UDim2.new(0, 10, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Text = "Remote Renamer v2.0"
    Title.TextColor3 = Color3.new(1, 1, 1)
    Title.TextSize = 14
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Parent = TopBar
    
    local CloseButton = Instance.new("TextButton")
    CloseButton.Name = "CloseButton"
    CloseButton.Size = UDim2.new(0, 30, 0, 30)
    CloseButton.Position = UDim2.new(1, -30, 0, 0)
    CloseButton.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
    CloseButton.BorderSizePixel = 0
    CloseButton.Text = "X"
    CloseButton.TextColor3 = Color3.new(1, 1, 1)
    CloseButton.TextSize = 14
    CloseButton.Parent = TopBar
    
    CloseButton.MouseButton1Click:Connect(function()
        mainGui:Destroy()
    end)
    
    local ContentFrame = Instance.new("Frame")
    ContentFrame.Name = "ContentFrame"
    ContentFrame.Size = UDim2.new(1, -20, 1, -50)
    ContentFrame.Position = UDim2.new(0, 10, 0, 40)
    ContentFrame.BackgroundTransparency = 1
    ContentFrame.Parent = MainFrame
    
    -- Таблица с ремоутами
    local RemoteList = Instance.new("ScrollingFrame")
    RemoteList.Name = "RemoteList"
    RemoteList.Size = UDim2.new(1, 0, 0.7, 0)
    RemoteList.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    RemoteList.BorderSizePixel = 0
    RemoteList.ScrollBarThickness = 4
    RemoteList.CanvasSize = UDim2.new(0, 0, 0, 0)
    RemoteList.Parent = ContentFrame
    
    local UIListLayout = Instance.new("UIListLayout")
    UIListLayout.Padding = UDim.new(0, 2)
    UIListLayout.Parent = RemoteList
    
    -- Панель управления
    local ControlPanel = Instance.new("Frame")
    ControlPanel.Name = "ControlPanel"
    ControlPanel.Size = UDim2.new(1, 0, 0.3, -10)
    ControlPanel.Position = UDim2.new(0, 0, 0.7, 10)
    ControlPanel.BackgroundTransparency = 1
    ControlPanel.Parent = ContentFrame
    
    -- Кнопки действий
    local buttonTemplates = {
        {
            Name = "ScanButton",
            Text = "🔍 Сканировать ремоуты",
            Position = UDim2.new(0, 0, 0, 0),
            Size = UDim2.new(1, 0, 0, 30),
            Callback = function()
                scanRemotes()
            end
        },
        {
            Name = "RenameButton",
            Text = "🔄 Переименовать все",
            Position = UDim2.new(0, 0, 0, 35),
            Size = UDim2.new(1, 0, 0, 30),
            Callback = function()
                renameAllRemotes()
            end
        },
        {
            Name = "GenerateScriptButton",
            Text = "📋 Сгенерировать скрипт",
            Position = UDim2.new(0, 0, 0, 70),
            Size = UDim2.new(1, 0, 0, 30),
            Callback = function()
                generateRenameScript()
            end
        },
        {
            Name = "SettingsButton",
            Text = "⚙️ Настройки",
            Position = UDim2.new(0, 0, 0, 105),
            Size = UDim2.new(1, 0, 0, 30),
            Callback = function()
                showSettingsMenu()
            end
        }
    }
    
    for _, template in ipairs(buttonTemplates) do
        local button = Instance.new("TextButton")
        button.Name = template.Name
        button.Size = template.Size
        button.Position = template.Position
        button.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
        button.BorderSizePixel = 0
        button.Text = template.Text
        button.TextColor3 = Color3.new(1, 1, 1)
        button.TextSize = 12
        button.Parent = ControlPanel
        
        button.MouseButton1Click:Connect(template.Callback)
        
        -- Эффект наведения
        button.MouseEnter:Connect(function()
            button.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
        end)
        
        button.MouseLeave:Connect(function()
            button.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
        end)
    end
    
    -- Статус бар
    local StatusBar = Instance.new("TextLabel")
    StatusBar.Name = "StatusBar"
    StatusBar.Size = UDim2.new(1, 0, 0, 20)
    StatusBar.Position = UDim2.new(0, 0, 1, -20)
    StatusBar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    StatusBar.BorderSizePixel = 0
    StatusBar.Text = "Готов к работе"
    StatusBar.TextColor3 = Color3.new(1, 1, 1)
    StatusBar.TextSize = 12
    StatusBar.Parent = ContentFrame
    
    -- Функция для обновления статуса
    function updateStatus(message)
        StatusBar.Text = message
    end
    
    -- Добавление ремоута в список
    function addRemoteToList(remoteInfo, index)
        local RemoteItem = Instance.new("Frame")
        RemoteItem.Name = "RemoteItem_" .. index
        RemoteItem.Size = UDim2.new(1, 0, 0, 40)
        RemoteItem.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        RemoteItem.BorderSizePixel = 0
        RemoteItem.Parent = RemoteList
        
        local NameLabel = Instance.new("TextLabel")
        NameLabel.Name = "NameLabel"
        NameLabel.Size = UDim2.new(0.6, -5, 0.5, 0)
        NameLabel.Position = UDim2.new(0, 5, 0, 2)
        NameLabel.BackgroundTransparency = 1
        NameLabel.Text = remoteInfo.OriginalName
        NameLabel.TextColor3 = Color3.new(1, 1, 1)
        NameLabel.TextSize = 11
        NameLabel.TextXAlignment = Enum.TextXAlignment.Left
        NameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        NameLabel.Parent = RemoteItem
        
        local NewNameLabel = Instance.new("TextLabel")
        NewNameLabel.Name = "NewNameLabel"
        NewNameLabel.Size = UDim2.new(0.6, -5, 0.5, 0)
        NewNameLabel.Position = UDim2.new(0, 5, 0.5, 2)
        NewNameLabel.BackgroundTransparency = 1
        NewNameLabel.Text = remoteInfo.NewName or "..."
        NewNameLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        NewNameLabel.TextSize = 10
        NewNameLabel.TextXAlignment = Enum.TextXAlignment.Left
        NewNameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        NewNameLabel.Parent = RemoteItem
        
        local ClassLabel = Instance.new("TextLabel")
        ClassLabel.Name = "ClassLabel"
        ClassLabel.Size = UDim2.new(0.4, -5, 0.5, 0)
        ClassLabel.Position = UDim2.new(0.6, 5, 0, 2)
        ClassLabel.BackgroundTransparency = 1
        ClassLabel.Text = remoteInfo.ClassName
        ClassLabel.TextColor3 = Color3.fromRGB(180, 180, 255)
        ClassLabel.TextSize = 11
        ClassLabel.TextXAlignment = Enum.TextXAlignment.Right
        ClassLabel.Parent = RemoteItem
        
        local PathLabel = Instance.new("TextLabel")
        PathLabel.Name = "PathLabel"
        PathLabel.Size = UDim2.new(0.4, -5, 0.5, 0)
        PathLabel.Position = UDim2.new(0.6, 5, 0.5, 2)
        PathLabel.BackgroundTransparency = 1
        PathLabel.Text = remoteInfo.SourceScript or "Неизвестно"
        PathLabel.TextColor3 = Color3.fromRGB(255, 180, 180)
        PathLabel.TextSize = 9
        PathLabel.TextXAlignment = Enum.TextXAlignment.Right
        PathLabel.TextTruncate = Enum.TextTruncate.AtEnd
        PathLabel.Parent = RemoteItem
        
        -- Обновление размера канваса
        RemoteList.CanvasSize = UDim2.new(0, 0, 0, UIListLayout.AbsoluteContentSize.Y)
    end
    
    -- Функция сканирования
    function scanRemotes()
        updateStatus("🔍 Сканирование ремоутов...")
        RemoteList:ClearAllChildren()
        
        local remotes, count = collectRemoteInformation()
        updateStatus(string.format("Найдено ремоутов: %d", count))
        
        remoteLogs = {}
        
        for index, remoteInfo in ipairs(remotes) do
            -- Получаем информацию о calling script
            local callingScripts = getCallingScriptInfo(remoteInfo.Instance)
            local sourceScript = "Неизвестно"
            
            if #callingScripts > 0 then
                sourceScript = getScriptName(callingScripts[1])
                if #callingScripts > 1 then
                    sourceScript = sourceScript .. " (+" .. (#callingScripts - 1) .. ")"
                end
            end
            
            remoteInfo.SourceScript = sourceScript
            remoteInfo.NewName = generateRemoteName(sourceScript, remoteInfo.OriginalName, index)
            
            table.insert(remoteLogs, remoteInfo)
            addRemoteToList(remoteInfo, index)
            
            -- Сохраняем оригинальное имя
            originalNames[remoteInfo.Instance] = remoteInfo.OriginalName
        end
        
        updateStatus(string.format("✅ Сканирование завершено: %d ремоутов", #remoteLogs))
    end
    
    -- Функция переименования
    function renameAllRemotes()
        if #remoteLogs == 0 then
            updateStatus("❌ Сначала выполните сканирование!")
            return
        end
        
        updateStatus("🔄 Начинаю переименование...")
        
        local successCount = 0
        local failCount = 0
        renameOperations = {}
        
        for _, remoteInfo in ipairs(remoteLogs) do
            local success, errorMsg = pcall(function()
                remoteInfo.Instance.Name = remoteInfo.NewName
                
                -- Записываем операцию
                table.insert(renameOperations, {
                    OriginalName = remoteInfo.OriginalName,
                    NewName = remoteInfo.NewName,
                    Instance = remoteInfo.Instance,
                    Timestamp = os.time(),
                    Success = true
                })
                
                successCount = successCount + 1
                
                -- Обновляем отображение
                for _, item in ipairs(RemoteList:GetChildren()) do
                    if item:IsA("Frame") and item.Name:find("RemoteItem_") then
                        local nameLabel = item:FindFirstChild("NameLabel")
                        if nameLabel and nameLabel.Text == remoteInfo.OriginalName then
                            nameLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
                        end
                    end
                end
            end)
            
            if not success then
                failCount = failCount + 1
                table.insert(renameOperations, {
                    OriginalName = remoteInfo.OriginalName,
                    NewName = remoteInfo.NewName,
                    Instance = remoteInfo.Instance,
                    Timestamp = os.time(),
                    Success = false,
                    Error = errorMsg
                })
            end
            
            task.wait(0.05) -- Небольшая задержка между операциями
        end
        
        updateStatus(string.format("✅ Переименовано: %d | ❌ Ошибок: %d", successCount, failCount))
        
        -- Показываем детальный отчет
        if SETTINGS.ShowDetailsMenu then
            showResultsMenu(successCount, failCount)
        end
    end
    
    -- Генерация скрипта
    function generateRenameScript()
        if #remoteLogs == 0 then
            updateStatus("❌ Нет данных для генерации скрипта!")
            return
        end
        
        local scriptLines = {
            "-- Remote Rename Script",
            "-- Generated by Remote Renamer v2.0",
            "-- " .. os.date("%Y-%m-%d %H:%M:%S"),
            "",
            "local function renameRemotes()",
            "    print(\"Starting remote rename operation...\")",
            "",
            "    local remotesToRename = {"
        }
        
        for _, remoteInfo in ipairs(remoteLogs) do
            local line = string.format('        {original = "%s", new = "%s", class = "%s", path = "%s"},',
                remoteInfo.OriginalName,
                remoteInfo.NewName,
                remoteInfo.ClassName,
                remoteInfo.ParentPath
            )
            table.insert(scriptLines, line)
        end
        
        table.insert(scriptLines, "    }")
        table.insert(scriptLines, "")
        table.insert(scriptLines, "    for _, remoteData in ipairs(remotesToRename) do")
        table.insert(scriptLines, '        local remote = game:GetService("ReplicatedStorage"):FindFirstChild(remoteData.original)')
        table.insert(scriptLines, "        if remote then")
        table.insert(scriptLines, '            remote.Name = remoteData.new')
        table.insert(scriptLines, string.format('            print("✓ Renamed: " .. remoteData.original .. " -> " .. remoteData.new)'))
        table.insert(scriptLines, "        else")
        table.insert(scriptLines, '            print("✗ Not found: " .. remoteData.original)')
        table.insert(scriptLines, "        end")
        table.insert(scriptLines, "        task.wait(0.05)")
        table.insert(scriptLines, "    end")
        table.insert(scriptLines, "")
        table.insert(scriptLines, '    print("Rename operation completed!")')
        table.insert(scriptLines, "end")
        table.insert(scriptLines, "")
        table.insert(scriptLines, "-- Execute the function")
        table.insert(scriptLines, "renameRemotes()")
        
        local fullScript = table.concat(scriptLines, "\n")
        
        -- Копируем в буфер обмена
        if setclipboard then
            setclipboard(fullScript)
            updateStatus("📋 Скрипт скопирован в буфер обмена!")
        else
            updateStatus("❌ Функция setclipboard недоступна")
        end
    end
    
    -- Показ меню настроек
    function showSettingsMenu()
        local SettingsFrame = Instance.new("Frame")
        SettingsFrame.Name = "SettingsFrame"
        SettingsFrame.Size = UDim2.new(0, 300, 0, 200)
        SettingsFrame.Position = UDim2.new(0.5, -150, 0.5, -100)
        SettingsFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        SettingsFrame.BorderSizePixel = 0
        SettingsFrame.ZIndex = 20
        SettingsFrame.Parent = mainGui
        
        local SettingsTitle = Instance.new("TextLabel")
        SettingsTitle.Name = "SettingsTitle"
        SettingsTitle.Size = UDim2.new(1, 0, 0, 30)
        SettingsTitle.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
        SettingsTitle.BorderSizePixel = 0
        SettingsTitle.Text = "Настройки"
        SettingsTitle.TextColor3 = Color3.new(1, 1, 1)
        SettingsTitle.TextSize = 14
        SettingsTitle.Parent = SettingsFrame
        
        local CloseSettings = Instance.new("TextButton")
        CloseSettings.Name = "CloseSettings"
        CloseSettings.Size = UDim2.new(0, 30, 0, 30)
        CloseSettings.Position = UDim2.new(1, -30, 0, 0)
        CloseSettings.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
        CloseSettings.BorderSizePixel = 0
        CloseSettings.Text = "X"
        CloseSettings.TextColor3 = Color3.new(1, 1, 1)
        CloseSettings.TextSize = 14
        CloseSettings.Parent = SettingsFrame
        
        CloseSettings.MouseButton1Click:Connect(function()
            SettingsFrame:Destroy()
        end)
        
        local Content = Instance.new("Frame")
        Content.Name = "Content"
        Content.Size = UDim2.new(1, -20, 1, -50)
        Content.Position = UDim2.new(0, 10, 0, 40)
        Content.BackgroundTransparency = 1
        Content.Parent = SettingsFrame
        
        -- Настройки
        local settingOptions = {
            {
                Name = "AddRandomSuffix",
                Text = "Добавлять случайный суффикс",
                Value = SETTINGS.AddRandomSuffix,
                Type = "checkbox"
            },
            {
                Name = "ShowDetailsMenu",
                Text = "Показывать меню с результатами",
                Value = SETTINGS.ShowDetailsMenu,
                Type = "checkbox"
            },
            {
                Name = "RenameAllRemotes",
                Text = "Переименовывать все ремоуты",
                Value = SETTINGS.RenameAllRemotes,
                Type = "checkbox"
            }
        }
        
        local yOffset = 0
        for _, option in ipairs(settingOptions) do
            local Checkbox = Instance.new("TextButton")
            Checkbox.Name = "Checkbox_" .. option.Name
            Checkbox.Size = UDim2.new(1, 0, 0, 25)
            Checkbox.Position = UDim2.new(0, 0, 0, yOffset)
            Checkbox.BackgroundColor3 = option.Value and Color3.fromRGB(80, 180, 80) or Color3.fromRGB(80, 80, 80)
            Checkbox.BorderSizePixel = 0
            Checkbox.Text = option.Text
            Checkbox.TextColor3 = Color3.new(1, 1, 1)
            Checkbox.TextSize = 12
            Checkbox.Parent = Content
            
            Checkbox.MouseButton1Click:Connect(function()
                SETTINGS[option.Name] = not SETTINGS[option.Name]
                Checkbox.BackgroundColor3 = SETTINGS[option.Name] and Color3.fromRGB(80, 180, 80) or Color3.fromRGB(80, 80, 80)
            end)
            
            yOffset = yOffset + 30
        end
    end
    
    -- Показ результатов
    function showResultsMenu(successCount, failCount)
        local ResultsFrame = Instance.new("Frame")
        ResultsFrame.Name = "ResultsFrame"
        ResultsFrame.Size = UDim2.new(0, 350, 0, 250)
        ResultsFrame.Position = UDim2.new(0.5, -175, 0.5, -125)
        ResultsFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        ResultsFrame.BorderSizePixel = 0
        ResultsFrame.ZIndex = 20
        ResultsFrame.Parent = mainGui
        
        local ResultsTitle = Instance.new("TextLabel")
        ResultsTitle.Name = "ResultsTitle"
        ResultsTitle.Size = UDim2.new(1, 0, 0, 30)
        ResultsTitle.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
        ResultsTitle.BorderSizePixel = 0
        ResultsTitle.Text = "Результаты переименования"
        ResultsTitle.TextColor3 = Color3.new(1, 1, 1)
        ResultsTitle.TextSize = 14
        ResultsTitle.Parent = ResultsFrame
        
        local CloseResults = Instance.new("TextButton")
        CloseResults.Name = "CloseResults"
        CloseResults.Size = UDim2.new(0, 30, 0, 30)
        CloseResults.Position = UDim2.new(1, -30, 0, 0)
        CloseResults.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
        CloseResults.BorderSizePixel = 0
        CloseResults.Text = "X"
        CloseResults.TextColor3 = Color3.new(1, 1, 1)
        CloseResults.TextSize = 14
        CloseResults.Parent = ResultsFrame
        
        CloseResults.MouseButton1Click:Connect(function()
            ResultsFrame:Destroy()
        end)
        
        local Content = Instance.new("ScrollingFrame")
        Content.Name = "Content"
        Content.Size = UDim2.new(1, -20, 1, -50)
        Content.Position = UDim2.new(0, 10, 0, 40)
        Content.BackgroundTransparency = 1
        Content.ScrollBarThickness = 4
        Content.CanvasSize = UDim2.new(0, 0, 0, 0)
        Content.Parent = ResultsFrame
        
        local Summary = Instance.new("TextLabel")
        Summary.Name = "Summary"
        Summary.Size = UDim2.new(1, 0, 0, 50)
        Summary.BackgroundTransparency = 1
        Summary.Text = string.format("✅ Успешно: %d\n❌ Ошибок: %d\n📊 Всего: %d",
            successCount, failCount, successCount + failCount)
        Summary.TextColor3 = Color3.new(1, 1, 1)
        Summary.TextSize = 14
        Summary.TextWrapped = true
        Summary.Parent = Content
        
        local OperationsList = Instance.new("TextLabel")
        OperationsList.Name = "OperationsList"
        OperationsList.Size = UDim2.new(1, 0, 0, 0)
        OperationsList.Position = UDim2.new(0, 0, 0, 60)
        OperationsList.BackgroundTransparency = 1
        OperationsList.Text = ""
        OperationsList.TextColor3 = Color3.new(1, 1, 1)
        OperationsList.TextSize = 11
        OperationsList.TextWrapped = true
        OperationsList.TextXAlignment = Enum.TextXAlignment.Left
        OperationsList.TextYAlignment = Enum.TextYAlignment.Top
        OperationsList.Parent = Content
        
        -- Заполняем список операций
        local operationsText = "Операции:\n"
        for i, op in ipairs(renameOperations) do
            local status = op.Success and "✅" or "❌"
            local errorText = op.Error and " (" .. op.Error .. ")" or ""
            operationsText = operationsText .. string.format("%s %s -> %s%s\n",
                status, op.OriginalName, op.NewName, errorText)
        end
        
        OperationsList.Text = operationsText
        OperationsList.Size = UDim2.new(1, 0, 0, #renameOperations * 20 + 20)
        Content.CanvasSize = UDim2.new(0, 0, 0, 60 + OperationsList.Size.Y.Offset)
    end
    
    -- Перемещение GUI
    local dragging
    local dragInput
    local dragStart
    local startPos
    
    TopBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = MainFrame.Position
            
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    
    TopBar.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = input
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    
    return mainGui
end

-- Основная функция запуска
local function initialize()
    print("🚀 Remote Renamer v2.0 запущен!")
    print("📋 Автономный скрипт для переименования ремоутов")
    
    -- Создаем GUI
    local gui = createMenu()
    gui.Parent = CoreGui
    
    -- Автоматически сканируем ремоуты при запуске
    task.wait(1)
    
    if mainGui and mainGui.Parent then
        -- Находим кнопку сканирования и имитируем клик
        local success = pcall(function()
            local mainFrame = mainGui:FindFirstChild("MainFrame")
            if mainFrame then
                local contentFrame = mainFrame:FindFirstChild("ContentFrame")
                if contentFrame then
                    local controlPanel = contentFrame:FindFirstChild("ControlPanel")
                    if controlPanel then
                        local scanButton = controlPanel:FindFirstChild("ScanButton")
                        if scanButton then
                            scanButton.BackgroundColor3 = Color3.fromRGB(100, 100, 255)
                            task.wait(0.5)
                            scanButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
                            scanRemotes()
                        end
                    end
                end
            end
        end)
    end
    
    print("✅ GUI успешно создан!")
    print("📝 Используйте меню для управления переименованием")
end

-- Запускаем скрипт
initialize()

-- Возвращаем управляющие функции
return {
    ScanRemotes = function() 
        if scanRemotes then 
            scanRemotes() 
        end 
    end,
    RenameAll = function() 
        if renameAllRemotes then 
            renameAllRemotes() 
        end 
    end,
    GenerateScript = function() 
        if generateRenameScript then 
            generateRenameScript() 
        end 
    end,
    ShowMenu = function()
        if mainGui and mainGui.Parent then
            mainGui.Enabled = not mainGui.Enabled
        else
            initialize()
        end
    end
}

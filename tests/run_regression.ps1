# Регрессия: всё ли в игре работает, как задумано. ~10 минут, окно игры открывается само.
# 1) Сквозное прохождение всей игры (tests/regression_test.gd) — каждая механика и весь сюжет по порядку.
# 2) Мир собирается так же, как эталон (tests/regression_baseline.txt): меши, вершины, коллизии, гора.
# 3) Отдельные проверки: лестницы, лифт, летающие машины, высоты тропы, регуляторы камеры.
# Итог «прошло X из Y» — в консоли и в tests/regression_report.txt.
# Запуск: двойной клик по tests/run_regression.bat
# После намеренного изменения мира (новые постройки, гора) — обновить эталон:
#   powershell -File tests/run_regression.ps1 -UpdateBaseline

param([switch]$UpdateBaseline)

# Godot пишет в UTF-8: без этого русские строки вывода читаются кракозябрами и не находятся.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$project = Split-Path -Parent $PSScriptRoot
$godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
$report = Join-Path $PSScriptRoot "regression_report.txt"
$baselineFile = Join-Path $PSScriptRoot "regression_baseline.txt"
$script:passed = 0
$script:failed = 0
$lines = New-Object System.Collections.Generic.List[string]

function Say([string]$text, [string]$color = "Gray") {
    Write-Host $text -ForegroundColor $color
    $lines.Add($text)
}

function Check([string]$name, [bool]$ok, [string]$detail = "") {
    $mark = if ($ok) { "✔" } else { "✘" }
    $text = "$mark $name" + $(if ($detail) { " — $detail" } else { "" })
    if ($ok) { $script:passed++ ; Say $text "Green" } else { $script:failed++ ; Say $text "Red" }
}

function Run([string]$test, [string[]]$extra = @()) {
    $arguments = @("--path", $project, "-s", $test) + $extra
    return (& $godot @arguments 2>&1 | ForEach-Object { "$_" })
}

Say "Регрессия Megastructure — $(Get-Date -Format 'dd.MM.yyyy HH:mm')" "Cyan"

# --- 1. Мир как эталон --------------------------------------------------------------
Say "`n== Мир собирается как эталон" "Cyan"
$finger = Run "tests/world_fingerprint.gd" | Where-Object { $_ -match "^FINGERPRINT" } | ForEach-Object { $_ -replace " sum=\d+", "" }
if ($UpdateBaseline) {
    $finger | Out-File $baselineFile -Encoding utf8
    Say "Эталон обновлён: $baselineFile" "Yellow"
}
$baseline = Get-Content $baselineFile -Encoding utf8
Check "постройки: меши, вершины, коллизии, окклюдеры" ($finger[0] -eq $baseline[0]) $finger[0]
Check "гора: высоты, цвета, дыры, коллизия" ($finger[1] -eq $baseline[1]) $finger[1]
$load = [string](Run "tests/world_fingerprint.gd" | Where-Object { $_ -match "\[мир\] всё остальное" } | Select-Object -First 1)
if ($load -match "всего (\d+) мс") { Check "мир строится быстрее 5 с" ([int]$Matches[1] -lt 5000) "$($Matches[1]) мс" } else { Check "мир строится" $false "нет строки о времени постройки" }

# --- 2. Отдельные механики мира ------------------------------------------------------
Say "`n== Механики мира" "Cyan"
$out = Run "tests/stairs_test.gd"
if (($out -join "`n") -match "STAIRS RESULT max_y=([\d.]+)") { Check "лестница в доме: поднимается на этаж" ([double]$Matches[1] -ge 3.0) "высота $($Matches[1]) м" } else { Check "лестница в доме" $false "нет результата" }
$out = Run "tests/elevator_test.gd"
if (($out -join "`n") -match "LIFT RESULT max_y=([\d.]+)") { Check "лифт довозит до 75 м" ([double]$Matches[1] -ge 74.0) "$($Matches[1]) м" } else { Check "лифт" $false "нет результата" }
$out = Run "tests/traffic_test.gd"
if (($out -join "`n") -match "with_detours=(\d+)") { Check "летающие машины не проходят сквозь здания" ([int]$Matches[1] -eq 0) "в зданиях: $($Matches[1])" } else { Check "летающие машины" $false "нет результата" }
$out = Run "tests/mountain_test.gd" | Where-Object { $_ -match "^MOUNTAIN at" }
$okMountain = $out.Count -ge 4
foreach ($l in $out) {
    if ($l -match "expected=([\d.\-]+) terrain=([\d.\-]+) player_y=([\d.\-]+) on_floor=(\w+)") {
        if ([math]::Abs([double]$Matches[1] - [double]$Matches[2]) -gt 1.0 -or $Matches[4] -ne "true") { $okMountain = $false }
    }
}
Check "тропа горы: высоты совпадают, герой стоит" $okMountain "$($out.Count) точек"
$out = (Run "tests/bodycam_slider_test.gd") -join "`n"
$roll0 = $out -match "turn roll 0%: max roll=0\.00"
$bob0 = $out -match "bob 0%: walking speed=[\d.]+, camera offset=0\.0000"
Check "регуляторы: крен 0% и покачивание 0% выключают эффект" ($roll0 -and $bob0)

# --- Меню и настройки ---------------------------------------------------------------
Say "`n== Меню и настройки" "Cyan"
$out = Run "tests/menu_test.gd" @("--", "--prologue")
foreach ($l in ($out | Where-Object { $_ -match "^MENU [✔✘]" })) {
    $text = $l.Substring(5)
    if ($text.StartsWith("✔")) { $script:passed++ ; Say $text "Green" } else { $script:failed++ ; Say $text "Red" }
}
if (-not ($out -match "^MENU ИТОГ")) { Check "тест меню дошёл до конца" $false }

# --- Новые механики ------------------------------------------------------------------
Say "`n== Звук, скамейка, окурок, снимки, реклама" "Cyan"
$out = Run "tests/features_test.gd"
foreach ($l in ($out | Where-Object { $_ -match "^FEAT [✔✘]" })) {
    $text = $l.Substring(5)
    if ($text.StartsWith("✔")) { $script:passed++ ; Say $text "Green" } else { $script:failed++ ; Say $text "Red" }
}
if (-not ($out -match "^FEAT ИТОГ")) { Check "тест новых механик дошёл до конца" $false }

# --- 3. Вся игра по порядку ---------------------------------------------------------
Say "`n== Прохождение всей игры (несколько минут)" "Cyan"
$out = Run "tests/regression_test.gd" @("--", "--prologue")
$reg = $out | Where-Object { $_ -match "^REG " } | ForEach-Object { $_.Substring(4) }
$summary = $null
foreach ($l in $reg) {
    if ($l -match "^== (.*)") { Say "-- $($Matches[1])" "DarkCyan" }
    elseif ($l -match "^ИТОГ") { $summary = $l }
    elseif ($l.StartsWith("✔")) { $script:passed++ ; Say $l "Green" }
    elseif ($l.StartsWith("✘")) { $script:failed++ ; Say $l "Red" }
}
if (-not $summary) { Check "прохождение дошло до конца" $false "оборвалось — см. ошибки ниже" }
$errors = $out | Where-Object { $_ -match "SCRIPT ERROR|Parse Error" } | Select-Object -Unique
foreach ($e in $errors) { Say "   $e" "Red" }
Check "в прохождении нет ошибок скриптов" ($errors.Count -eq 0) "$($errors.Count) разных"

# --- Итог ---------------------------------------------------------------------------
$total = $script:passed + $script:failed
$color = if ($script:failed -eq 0) { "Green" } else { "Red" }
Say "`nИТОГ: прошло $($script:passed) из $total$(if ($script:failed) { " — НЕ ПРОШЛО: $($script:failed)" })" $color
$lines | Out-File $report -Encoding utf8
Say "Отчёт: $report" "Cyan"

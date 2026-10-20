# Прогон истории целиком: пролог → падение → текст во тьме → подъём → рассказ об ангеле →
# мост с припадками и рассказом на 68% → прощание с ангелом и глитч к вершине → финал. Печатает итоги и сохраняет отчёт в tests/story_report.txt,
# снимки — в screenshots/ (prologue_*.png, story_*.png).
# Запуск: двойной клик по tests/run_story_tests.bat (или powershell -File tests/run_story_tests.ps1)

$project = Split-Path -Parent $PSScriptRoot
$godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
$report = Join-Path $PSScriptRoot "story_report.txt"
$runs = @(
    @{ Name = "1. Пролог (слайды только по пробелу)"; Script = "tests/prologue_view.gd"; Args = @("--", "--prologue"); Filter = "PROLOGUE" },
    @{ Name = "2. Падение, текст во тьме, подъём, рассказ об ангеле"; Script = "tests/story_intro_test.gd"; Args = @(); Filter = "STORY" },
    @{ Name = "3. Мост: припадки, рассказ на 68%"; Script = "tests/seizure_test.gd"; Args = @(); Filter = "FIT" },
    @{ Name = "4. Гора: прощание с ангелом, через 100 м глитч к вершине, рассказ о солнце"; Script = "tests/farewell_jump_test.gd"; Args = @(); Filter = "JUMP" }
)

"Прогон истории $(Get-Date -Format 'dd.MM.yyyy HH:mm')" | Out-File $report -Encoding utf8
foreach ($run in $runs) {
    Write-Host "`n=== $($run.Name) ===" -ForegroundColor Cyan
    "`n=== $($run.Name) ===" | Out-File $report -Append -Encoding utf8
    $output = & $godot --path $project -s $run.Script @($run.Args) 2>&1 | ForEach-Object { "$_" }
    $lines = $output | Where-Object { $_ -match $run.Filter -or $_ -match "SCRIPT ERROR|Parse Error" }
    $lines | ForEach-Object { Write-Host $_ }
    $lines | Out-File $report -Append -Encoding utf8
}
Write-Host "`nОтчёт: $report" -ForegroundColor Green

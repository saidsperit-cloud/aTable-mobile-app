Set-Location "e:\vs\repos\aTable\atable_app"
$result = dart run flutter_launcher_icons 2>&1
$result | Out-File "e:\vs\repos\aTable\_temp\icons_run.txt" -Encoding utf8
Write-Output "Exit code: $LASTEXITCODE"
Write-Output "Output lines: $($result.Count)"
$result | Select-Object -First 20 | Write-Output

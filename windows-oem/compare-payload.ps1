$off = Get-ChildItem 'C:\RadioBot\official-extract' -Recurse -File | Select-Object -ExpandProperty FullName
$pay = Get-ChildItem 'C:\RadioBot\payload-official' -Recurse -File | Select-Object -ExpandProperty FullName

$offRel = $off | ForEach-Object { $_.Substring('C:\RadioBot\official-extract\'.Length) }
$payRel = $pay | ForEach-Object { $_.Substring('C:\RadioBot\payload-official\'.Length) }

$onlyOfficial = $offRel | Where-Object { $_ -notin $payRel } | Sort-Object
$onlyPayload = $payRel | Where-Object { $_ -notin $offRel } | Sort-Object

Write-Host "Only in official ($($onlyOfficial.Count)):"
$onlyOfficial | Select-Object -First 80 | ForEach-Object { Write-Host "  $_" }

Write-Host "Only in payload ($($onlyPayload.Count)):"
$onlyPayload | Select-Object -First 80 | ForEach-Object { Write-Host "  $_" }

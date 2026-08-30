# Download the test MP3s used for end-to-end RadioBot testing.
# These tracks are from the Free Music Archive and are licensed CC0 1.0 Universal.
# See README.md for attribution.

$OutDir = "$PSScriptRoot\mp3s"
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$ua = 'Mozilla/5.0'

Invoke-WebRequest -Uri 'https://files.freemusicarchive.org/storage-freemusicarchive-org/music/Music_for_Video/Soft_and_Furious/Bae/Soft_and_Furious_-_01_-_Youre_Magic.mp3' -UserAgent $ua -OutFile "$OutDir\Soft_and_Furious_-_01_-_Youre_Magic.mp3"
Invoke-WebRequest -Uri 'https://files.freemusicarchive.org/storage-freemusicarchive-org/music/Music_for_Video/Soft_and_Furious/Bae/Soft_and_Furious_-_02_-_Game_On.mp3' -UserAgent $ua -OutFile "$OutDir\Soft_and_Furious_-_02_-_Game_On.mp3"

Write-Host "Test MP3s downloaded to $OutDir"

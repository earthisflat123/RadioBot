param(
    [Parameter(Mandatory=$true)]
    [string[]]$Projects,

    [string]$Sln = "C:\RadioBot\IRCBot\IRCBot.sln"
)

$ErrorActionPreference = "Stop"

$text = Get-Content -Raw $Sln

# Find the GUIDs of projects we are removing
$guids = [System.Collections.Generic.List[string]]::new()
foreach ($name in $Projects) {
    $pattern = '(?m)^Project\("\{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942\}"\) = "' + $name + '", "[^"]+", "\{([^}]+)\}"'
    if ($text -cmatch $pattern) {
        $guids.Add($matches[1])
    }
}

# Remove the Project ... EndProject blocks for those names
foreach ($name in $Projects) {
    $pattern = '(?ms)^Project\("\{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942\}"\) = "' + $name + '", "[^"]+", "\{[^}]+\}"\r?\nEndProject\r?\n'
    $text = [regex]::Replace($text, $pattern, "")
}

# Remove all remaining lines that mention any removed project GUID
# (ProjectDependencies, ProjectConfigurationPlatforms, NestedProjects, etc.)
foreach ($g in $guids) {
    $pattern = '(?m)^.*\{' + $g + '\}.*\r?\n'
    $text = [regex]::Replace($text, $pattern, "")
}

$text | Set-Content $Sln -Encoding UTF8
Write-Host "Pruned $Projects from $Sln"

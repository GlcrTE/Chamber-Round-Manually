Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$modRoot = $PSScriptRoot
$modName = "Chamber-Round-Manually"
$modsDir = "D:\Games\SteamLibrary\steamapps\common\Road to Vostok\mods"
$vmzPath = "$modRoot\$modName.vmz"

Remove-Item -Force -ErrorAction SilentlyContinue $vmzPath

$stream = [System.IO.File]::Open($vmzPath, [System.IO.FileMode]::Create)
$zip    = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)

function Add-Dir($zip, $entryName) {
    $entry = $zip.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
    $entry.ExternalAttributes = 16
}

function Add-File($zip, $entryName, $filePath) {
    $entry = $zip.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
    $entry.ExternalAttributes = 32
    $entry.LastWriteTime = [System.IO.File]::GetLastWriteTime($filePath)
    $writer = $entry.Open()
    $bytes  = [System.IO.File]::ReadAllBytes($filePath)
    $writer.Write($bytes, 0, $bytes.Length)
    $writer.Dispose()
}

Add-File $zip "mod.txt"                         "$modRoot\mod.txt"
Add-Dir  $zip "mods/"
Add-Dir  $zip "mods/chamberroundmanually/"
Add-File $zip "mods/chamberroundmanually/Main.gd"       "$modRoot\mods\chamberroundmanually\Main.gd"
Add-File $zip "mods/chamberroundmanually/context.gd"       "$modRoot\mods\chamberroundmanually\context.gd"
Add-File $zip "mods/chamberroundmanually/Interface.gd"  "$modRoot\mods\chamberroundmanually\Interface.gd"
Add-File $zip "mods/chamberroundmanually/Config.gd"  "$modRoot\mods\chamberroundmanually\Config.gd"
Add-File $zip "mods/chamberroundmanually/ModSettings.gd"  "$modRoot\mods\chamberroundmanually\ModSettings.gd"
Add-File $zip "mods/chamberroundmanually/ModSettings.tres"  "$modRoot\mods\chamberroundmanually\ModSettings.tres"



$zip.Dispose()
$stream.Dispose()

Copy-Item -Path $vmzPath -Destination "$modsDir\$modName.vmz" -Force

Write-Host "Done: $modsDir\$modName.vmz"

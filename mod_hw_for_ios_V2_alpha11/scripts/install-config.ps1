[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$HostName,
    [Parameter(Mandatory = $true)]
    [string]$PlistPath,
    [string]$UserName = 'mobile'
)

$ErrorActionPreference = 'Stop'
$ssh = Get-Command ssh -ErrorAction Stop
$scp = Get-Command scp -ErrorAction Stop
if (-not (Test-Path -LiteralPath $PlistPath -PathType Leaf)) {
    throw "Configuration file not found: $PlistPath"
}
$resolved = (Resolve-Path -LiteralPath $PlistPath).Path
$target = "$UserName@$HostName"
$stage = "/tmp/mod_hw_for_ios.devices.$PID.plist"
$destination = "/var/mobile/Library/Preferences/com.modhw.ios.devices.plist"
& $ssh.Source $target "mkdir -p /var/mobile/Library/Preferences"
if ($LASTEXITCODE -ne 0) { throw 'SSH connection or directory creation failed.' }
$scpTarget = $target + ":" + $stage
& $scp.Source -- $resolved $scpTarget
if ($LASTEXITCODE -ne 0) { throw 'SCP upload failed.' }
$remote = "set -eu; plutil -lint '$stage'; if [ -f '$destination' ]; then cp -p '$destination' '$destination.bak'; fi; mv '$stage' '$destination'; chmod 0644 '$destination'; plutil -lint '$destination'"
& $ssh.Source $target $remote
if ($LASTEXITCODE -ne 0) { throw 'Remote validation or installation failed.' }
Write-Host ("Installed to " + $target + ":" + $destination + ". No processes were restarted.")

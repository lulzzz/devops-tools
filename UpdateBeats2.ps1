Set-StrictMode -v latest
$ErrorActionPreference = "Stop"

function Main($mainargs)
{
    InstallBeatagent "metricbeat"
    InstallBeatagent "winlogbeat"
}

function InstallBeatagent([string] $beatname)
{
    Log ("*** Upgrading: '" + $beatname + "' ***")

    SaveOldConfigFile $beatname

    ReinstallBeatagent $beatname

    RestoreConfigFile $beatname
}

function SaveOldConfigFile([string] $beatname)
{
    [string] $folder = "C:\ProgramData\chocolatey\lib\" + $beatname
    [string] $pattern = $beatname + ".yml"
    $files = @(dir -Recurse $folder -Include $pattern)
    if ($files.Count -eq 0)
    {
        Log ("Didn't find any config file.") Yellow
        return
    }
    if ($files.Count -gt 1)
    {
        Log ("Too many config files, found: " + $files.Count) Red
        $files | % { Log ("'" + $_.FullName + "'") }
        exit 1
    }

    [string] $source = $files[0].FullName
    [string] $target = $files[0].Name

    Log ("Copying: '" + $source + "' -> '" + $target + "'")
    copy $source $target
}

function ReinstallBeatagent([string] $beatname)
{
    Log ("Stopping service: '" + $beatname + "'")
    Stop-Service $beatname -ErrorAction SilentlyContinue

    Log ("Uninstalling: '" + $beatname + "'")
    choco uninstall $beatname -y -f

    [string] $folder = "C:\ProgramData\" + $beatname
    Log ("Deleting folder: '" + $folder + "'")
    rd -recurse -force $folder -ErrorAction SilentlyContinue

    [string] $folder = "C:\ProgramData\chocolatey\lib\" + $beatname
    Log ("Deleting folder: '" + $folder + "'")
    rd -recurse -force $folder -ErrorAction SilentlyContinue

    Log ("Installing: '" + $beatname + "'")
    choco install $beatname -y
}

function RestoreConfigFile([string] $beatname)
{
    [string] $folder = "C:\ProgramData\chocolatey\lib\" + $beatname
    [string] $pattern = $beatname + ".yml"
    $files = @(dir -Recurse $folder -Include $pattern)
    if ($files.Count -ne 1)
    {
        Log ("Expected 1 config file, found: " + $files.Count) Red
        $files | % { Log ("'" + $_.FullName + "'") }
        exit 1
    }

    [string] $filename = $files[0].Name
    if (!(Test-Path $filename))
    {
        Log ("Didn't find any backuped config file: '" + $filename + "'") Yellow
        return
    }

    [string] $source = $files[0].FullName
    [string] $target = $files[0].Name + "_old"

    Log ("Renaming: '" + $source + "' -> '" + $target + "'")
    ren $source $target

    [string] $source = $files[0].Name
    [string] $target = $files[0].FullName

    Log ("Moving: '" + $source + "' -> '" + $target + "'")
    move $source $target
}

function Log([string] $message, $color)
{
    if ($color)
    {
        Write-Host $message -f $color
    }
    else
    {
        Write-Host $message -f Cyan
    }
}

Main $args

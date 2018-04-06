Set-StrictMode -v latest
$ErrorActionPreference = "Stop"

function Main([string[]] $mainargs)
{
    [bool] $dryrun = $false
    if ($mainargs -contains "-dryrun")
    {
        [bool] $dryrun = $true
    }


    [string] $nugeturl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"

    Log ("Downloading: '" + $nugeturl + "' -> 'nuget.exe'")
    Invoke-WebRequest $nugeturl -UseBasicParsing -OutFile nuget.exe

    Log ("Clearing nuget caches...")
    if (!$dryrun)
    {
        .\nuget.exe locals all -clear
    }


    [string[]] $nugetfolders = @(dir "C:\Users\*\.nuget","C:\Users\*\AppData\*\NuGet" | % { $_.FullName })

    Log ("Found " + $nugetfolders.Count + " folders:")
    Log ("`n  '" + ($nugetfolders -join "'`n  '") + "'")

    foreach ($nugetfolder in $nugetfolders)
    {
        Log ("Deleting: '" + $nugetfolder + "'")
        if (!$dryrun)
        {
            for ([int] $i=0; $i -lt 5 -and (Test-Path $nugetfolder); $i++)
            {
                try
                {
                    rd -Recurse -Force $nugetfolder
                }
                catch
                {
                    Log ("Error: " + $_.Exception)
                }
                if (Test-Path $nugetfolder)
                {
                    Log ("Waiting for folder to be deleted...")
                    Start-Sleep 5
                }
            }
        }
    }
}

function Log([string] $message, $color)
{
    [string] $now = [DateTime]::UtcNow.ToString("yyyy-MM-dd HH:mm:ss")
    if ($color)
    {
        Write-Host ($now + ": " + $message) -f $color
    }
    else
    {
        Write-Host ($now + ": " + $message) -f Green
    }
}

Main $args

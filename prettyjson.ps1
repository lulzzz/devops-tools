Set-StrictMode -v latest
$ErrorActionPreference = "Stop"

function Main()
{
    Load-Dependencies

    $jsonfiles = @(dir -r -i *.json)
    Log ("Found " + $jsonfiles.Count + " json files.")

    $jsonfiles | % {
        Pretty-JsonFile $_.FullName
    }
}

function Load-Dependencies()
{
    if ([Environment]::Version.Major -lt 4)
    {
        Log ("Newtonsoft.Json 10.0.2 requires .net 4 (Powershell 3.0), you have: " + [Environment]::Version) Red
        exit 1
    }

    [string] $nugetpkg = "https://www.nuget.org/api/v2/package/Newtonsoft.Json/10.0.2"
    [string] $zipfile = Join-Path $env:temp "json.zip"
    [string] $dllfile = "Newtonsoft.Json.dll"
    [string] $zipfilepath = Join-Path (Join-Path $zipfile "lib\net45") $dllfile
    [string] $dllfilepath = Join-Path $env:temp $dllfile

    Log ("Downloading: '" + $nugetpkg + "' -> '" + $zipfile + "'")
    if (Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue)
    {
        Invoke-WebRequest -UseBasicParsing $nugetpkg -OutFile $zipfile
    }
    else
    {
        curl.exe -L $nugetpkg -o $zipfile
    }
    if (!(Test-Path $zipfile))
    {
        Log ("Couldn't download: '" + $zipfile + "'") Red
        exit 1
    }

    Log ("Extracting: '" + $zipfilepath + "' -> '" + $env:temp + "'")
    $shell = New-Object -com Shell.Application
    $shell.Namespace($env:temp).CopyHere($zipfilepath, 20)

    if (!(Test-Path $dllfilepath))
    {
        Log ("Couldn't extract: '" + $dllfilepath + "'") Red
        exit 1
    }

    Log ("Deleting file: '" + $zipfile + "'")
    del $zipfile

    Log ("Loading assembly: '" + $dllfilepath + "'")
    [Reflection.Assembly]::LoadFile($dllfilepath) | Out-Null
}

function Pretty-JsonFile([string] $filename)
{
    Log ("Reading: '" + $filename + "'") Magenta
    [string] $content = [IO.File]::ReadAllText($filename)

    Log ("Prettifying: '" + $filename + "'") Magenta
    [string] $pretty = [Newtonsoft.Json.Linq.JToken]::Parse($content).ToString([Newtonsoft.Json.Formatting]::Indented)

    if ($pretty -ne $content)
    {
        Log ("Saving: '" + $filename + "'")
        [IO.File]::WriteAllText($filename, $pretty)
    }
}

function Log([string] $message, $color)
{
    if ($color)
    {
        Write-Host ((Get-Date).ToString("HHmmss") + ": " + $message) -f $color
    }
    else
    {
        Write-Host ((Get-Date).ToString("HHmmss") + ": " + $message) -f Green
    }
}

Main

Set-StrictMode -v latest
$ErrorActionPreference = "Stop"

function Main()
{
    [string] $content = $OctopusParameters['ConfigfileContent']
    if (!$content)
    {
        Write-Host ("ConfigfileContent not set") -f Red
        exit 1
    }
    [string] $username = $OctopusParameters['Username']
    if (!$username)
    {
        Write-Host ("Username not set") -f Red
        exit 1
    }
    [string] $password = $OctopusParameters['Password']
    if (!$password)
    {
        Write-Host ("Password not set") -f Red
        exit 1
    }


    [string] $servicename = "metricbeat"

    if (Get-Service | ? { $_.Name -eq $servicename })
    {
        Stop-Service $servicename
    }

    iwr https://chocolatey.org/install.ps1 -UseBasicParsing | iex
    choco install metricbeat -y --force

    [string] $filepattern = "metricbeat.yml"

    $files = @(dir -r (Join-Path $env:ProgramData "chocolatey\lib\metricbeat\tools") -i $filepattern)
    if ($files.Count -eq 0)
    {
        Write-Host ("Found " + $files.Count + " " + $filepattern + " files.") -f Red
        exit 1
    }

    Write-Host ("Found " + $files.Count + " " + $filepattern + " files.")


    $files | % {
        [string] $filename = $_.FullName
        Write-Host ("Updating: '" + $filename + "'")

        $content = $content.Replace("#{Username}", $username)
        $content = $content.Replace("#{Password}", $password)

        [IO.File]::WriteAllText($filename, $content)
    }

    if (!(Get-Service | ? { $_.Name -eq $servicename }))
    {
        Write-Host ("Service not found: '" + $servicename + "'")
        exit 1
    }

    Start-Service $servicename
}

Main

Set-StrictMode -v latest
$ErrorActionPreference = "Stop"

function Main()
{
    iwr https://chocolatey.org/install.ps1 -UseBasicParsing | iex
    choco install notepadplusplus "7-zip" -y

    Deploy-Metricbeat
}

function Deploy-Metricbeat()
{
    [string] $content = $OctopusParameters['MetricbeatConfigfileContent']
    if (!$content)
    {
        Write-Host ("MetricbeatConfigfileContent not set") -f Red
        exit 1
    }
    [string] $username = $OctopusParameters['MetricbeatUsername']
    if (!$username)
    {
        Write-Host ("MetricbeatUsername not set") -f Red
        exit 1
    }
    [string] $password = $OctopusParameters['MetricbeatPassword']
    if (!$password)
    {
        Write-Host ("MetricbeatPassword not set") -f Red
        exit 1
    }


    [string] $servicename = "metricbeat"

    if (Get-Service | ? { $_.Name -eq $servicename })
    {
        Stop-Service $servicename
    }

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
        $content = $content.Replace("`n", "`r`n")

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

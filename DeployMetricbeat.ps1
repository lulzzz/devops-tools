Set-StrictMode -v latest
$ErrorActionPreference = "Stop"

function Main()
{
    [string] $elasticurl = $OctopusParameters['elasticurl']
    if (!$elasticurl)
    {
        Write-Host ("Elasticurl not set") -f Red
        exit 1
    }
    [string] $username = $OctopusParameters['username']
    if (!$username)
    {
        Write-Host ("Username not set") -f Red
        exit 1
    }
    [string] $password = $OctopusParameters['password']
    if (!$password)
    {
        Write-Host ("Password not set") -f Red
        exit 1
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
        [string] $content = [IO.File]::ReadAllText($filename)

        $content = $content.Replace("#- diskio", "- diskio")
        $content = $content.Replace("hosts: [""localhost:9200""]", "hosts: [""" + $elasticurl + """]")
        $content = $content.Replace("#username: ""elastic""", ("username: """ + $username + """"))
        $content = $content.Replace("#password: ""changeme""", ("password: """ + $password + """"))

        [IO.File]::WriteAllText($filename, $content)
    }

    [string] $servicename = "metricbeat"

    if (!(Get-Service | ? { $_.Name -eq $servicename }))
    {
        Write-Host ("Service not found: '" + $servicename + "'")
        exit 1
    }

    Start-Service $servicename
}

Main

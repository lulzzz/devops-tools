Set-StrictMode -v latest
$ErrorActionPreference = "Stop"

function Main($mainargs)
{
    if (!$mainargs -or $mainargs.Count -ne 6)
    {
        Log ("Usage: powershell .\UpdateBeats2.ps1 <environment> <serverurl> <metricusername> <metricpassword> <winlogusername> <winlogpassword>") Red
        return
    }

    [string] $environment = $mainargs[0]
    [string] $serverurl = $mainargs[1]
    [string] $metricusername = $mainargs[2]
    [string] $metricpassword = $mainargs[3]
    [string] $winlogusername = $mainargs[4]
    [string] $winlogpassword = $mainargs[5]

    InstallBeatagent "metricbeat" $environment $serverurl $metricusername $metricpassword
    InstallBeatagent "winlogbeat" $environment $serverurl $winlogusername $winlogpassword
}

function InstallBeatagent([string] $beatname, [string] $environment, [string] $server, [string] $username, [string] $password)
{
    Log ("*** Installing: '" + $beatname + "' ***")

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

    [string] $folder = "C:\ProgramData\chocolatey\lib\" + $beatname
    [string] $pattern = $beatname + ".yml"
    $files = @(dir -Recurse $folder -Include $pattern)
    if ($files.Count -gt 1)
    {
        Log ("Found " + $files.Count + " files.")
        $files | % { Log ("'" + $_.FullName + "'") }
    }
    if ($files.Count -eq 0)
    {
        Log ("Couldn't find any '" + $pattern + "'") -f Yellow
        return
    }

    $files | % {
        [string] $filename = $_

        [string] $oldfilename = Join-Path (Split-Path $filename) ($beatname + "_old.yml")
        Log ("Copying: '" + $filename + "' -> '" + $oldfilename + "'")
        copy $filename $oldfilename

        Log ("Reading: '" + $filename + "'")
        $rows = gc $filename
        [string[]] $rows = $rows | % {
            if ($_ -eq "    #- diskio")
            {
                [string] $new = "    - diskio"
                Log ("'" + $_ + "' -> '" + $new + "'")
                $new
            }
            elseif ($_ -eq "#name:")
            {
                [string] $hostname = [System.Net.Dns]::GetHostName()
                [string] $new = "name: " + $environment + "." + $hostname
                Log ("'" + $_ + "' -> '" + $new + "'")
                $new
            }
            elseif ($_ -eq "#fields:")
            {
                [string] $new = "fields:"
                Log ("'" + $_ + "' -> '" + $new + "'")
                $new
            }
            elseif ($_ -eq "#  env: staging")
            {
                [string] $new = "  env: " + $environment
                Log ("'" + $_ + "' -> '" + $new + "'")
                $new
            }
            elseif ($_ -eq '  hosts: ["localhost:9200"]')
            {
                [string] $new = '  hosts: ["' + $server + '"]'
                Log ("'" + $_ + "' -> '" + $new + "'")
                $new
            }
            elseif ($_ -eq '  #username: "elastic"')
            {
                [string] $new = '  username: "' + $username + '"'
                Log ("'" + $_ + "' -> '" + $new + "'")
                $new
            }
            elseif ($_ -eq '  #password: "changeme"')
            {
                [string] $new = '  password: "' + $password + '"'
                Log ("'" + $_ + "' -> '" + $new + "'")
                $new
            }
            else
            {
                $_
            }
        }

        Log ("Saving: '" + $filename + "'")
        sc $filename $rows
    }
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

# edit with: powershell_ise.exe

Set-StrictMode -v latest
$ErrorActionPreference = "Stop"

function Main([string[]] $mainargs)
{
    if ($mainargs.Length -eq 11)
    {
        Log ("Installing Chocolatey.")
        iwr "https://chocolatey.org/install.ps1" -UseBasicParsing | iex

        [string] $sourceurl       = $mainargs[0]
        [string] $environment     = $mainargs[1]

        [string] $metricServer    = $mainargs[2]
        [string] $metricUsername  = $mainargs[3]
        [string] $metricPassword  = $mainargs[4]

        [string] $winlogServer    = $mainargs[5]
        [string] $winlogUsername  = $mainargs[6]
        [string] $winlogPassword  = $mainargs[7]

        [string] $fileServer      = $mainargs[8]
        [string] $fileUsername    = $mainargs[9]
        [string] $filePassword    = $mainargs[10]

        Install-Beat "metricbeat" $sourceurl $environment $metricServer $metricUsername $metricPassword
        Install-Beat "winlogbeat" $sourceurl $environment $winlogServer $winlogUsername $winlogPassword
        Install-Beat "filebeat" $sourceurl $environment $fileServer $fileUsername $filePassword

        Log ("Done!")
    }
    else
    {
        Log ("Got " + $mainargs.Length + " parameters.")
        Log ("The purpose of this script is to install/update the beats agents in a robust manner,")
        Log ("according to a sane convention. Custom configuration files, and configuration")
        Log ("parameters which should be set in the configuration files, can specified as arguments.")
        Log ("")
        Log ("Usage: powershell .\SetupBeats.ps1 <sourceurl> <environment>")
        Log ("                  <metricServer> <metricUsername> <metricPassword>")
        Log ("                  <winlogServer> <winlogUsername> <winlogPassword>")
        Log ("                  <fileServer>   <fileUsername>   <filePassword>")
        Log ("")
        Log ("sourceurl: From this folder, each beat configuration file will be downloaded.")
        Log ("Parameters in the configuration files which are replaced are:")
        Log ("#{UniqueName}, #{Environment}, #{Server}, #{Username}, #{Password}")

        exit 1
    }
}

function Install-Beat([string] $beatname, [string] $sourceurl, [string] $environment, [string] $server, [string] $username, [string] $password)
{
    if (!$environment)
    {
        Log ("Beat environment not specified.") Yellow
        return
    }
    if (!$server)
    {
        Log ("Beat server not specified.") Yellow
        return
    }
    if (!$username)
    {
        Log ("Beat username not specified.") Yellow
        return
    }
    if (!$password)
    {
        Log ("Beat password not specified.") Yellow
        return
    }

    Log ("Installing Beat: '" + $beatname + "', '" + $sourceurl + "', '" + $environment + "', '" + $server + "', '" + $username + "', '" + ("*" * $password.Length) + "'") Cyan


    [string] $configfileUrl = $sourceurl + "/" + $beatname + ".yml"
    [string] $localconfigfile = $beatname + ".yml"

    Download-FileRobust $configfileUrl $localconfigfile


    if (Get-Service | ? { $_.Name -eq $beatname })
    {
        Log ("Stopping service: '" + $beatname + "'")
        Stop-Service $beatname
        Start-Sleep 5
    }

    choco uninstall $beatname -y -force

    [string] $beatfolder = Join-Path $env:ProgramData ("chocolatey\lib\" + $beatname)
    Delete-Robust $beatfolder

    if (Get-Service | ? { $_.Name -eq $beatname })
    {
        sc.exe delete $beatname
    }


    choco install $beatname -y


    [string] $configpattern = Join-Path $beatfolder ("tools\*\" + $beatname + ".yml")

    $files = @(dir $configpattern)
    if ($files.Count -ne 1)
    {
        Log ("Found " + $files.Count + " config files with: '" + $configpattern + "'") Red
        exit 1
    }

    [string] $configfile = $files[0]
    Log ("Found config file: '" + $configfile + "'")


    [string] $oldconfigfile = $configfile + "_old"
    if (Test-Path $oldconfigfile)
    {
        Log ("Deleting old config file: '" + $oldconfigfile + "'")
        del $oldconfigfile
    }

    [string] $oldconfigfile = Split-Path -Leaf $oldconfigfile
    Log ("Renaming config file: '" + $configfile + "' -> '" + $oldconfigfile + "'")
    ren $configfile $oldconfigfile


    Log ("Reading downloaded config file: '" + $localconfigfile + "'")
    [string[]] $rows = @(gc $localconfigfile)

    Log ("Got " + $rows.Count + " rows.")

    $rows = $rows | % {
        [string] $row = $_
        $row = $row.Replace("#{UniqueName}", ($environment + "." + [Net.Dns]::GetHostName()))
        $row = $row.Replace("#{Environment}", $environment)
        $row = $row.Replace("#{Server}", $server)
        $row = $row.Replace("#{Username}", $username)
        $row = $row.Replace("#{Password}", $password)
        return $row
    }

    Log ("Saving " + $rows.Count + " rows to config file: '" + $configfile + "'")
    $rows | sc $configfile


    if (!(Get-Service | ? { $_.Name -eq $beatname }))
    {
        Log ("Service not found: '" + $beatname + "'") Red
        exit 1
    }

    Log ("Starting service: '" + $beatname + "'")
    Start-Service $beatname
}

function Delete-Robust([string] $path)
{
    [int] $i=0

    do
    {
        if (Test-Path $path)
        {
            Log ("Trying to delete: '" + $path + "'")
            try
            {
                del -r $path
                return
            }
            catch
            {
                Log ("Exception: " + $_.Exception) Yellow
                Start-Sleep 5
            }
        }
        else
        {
            return
        }

        $i++
    }
    while ($i -lt 12)


    if (Test-Path $path)
    {
        Log ("Trying to delete: '" + $path + "'")
        del -r $path
    }
}

function Download-FileRobust([string] $url, [string] $localfile)
{
    [int] $i=0

    do
    {
        Log ("Trying to download file: '" + $url + "' -> '" + $localfile + "'")
        try
        {
            Invoke-WebRequest -UseBasicParsing $url -OutFile $localfile
            return
        }
        catch
        {
            Log ("Exception: " + $_.Exception) Yellow
            Start-Sleep 5
        }

        $i++
    }
    while ($i -lt 60)

    Log ("Trying to download file: '" + $url + "' -> '" + $localfile + "'")
    Invoke-WebRequest -UseBasicParsing $url -OutFile $localfile
}

function Log([string] $message, $color)
{
    md "C:\installlogs" -ErrorAction SilentlyContinue | Out-Null

    [string] $dateMessage = [DateTime]::UtcNow.ToString("yyyy-MM-dd HH:mm:ss") + ": " + $message
    $dateMessage | ac "C:\installlogs\SetupBeats.log"

    [string] $hostMessage = [Net.Dns]::GetHostName() + ": " + $message

    if ($color)
    {
        Write-Host $hostMessage -f $color
    }
    else
    {
        Write-Host $hostMessage -f Green
    }
}

Main $args

<#
.SYNOPSIS
This script will install Elastic Beat agents on remote servers.

.DESCRIPTION
For actual usage, run this script with the -usage parameter.

Requires 2 files:
agents.txt - Each line specifies a beat agent to install: The windows service
             name and the download url.
creds.txt  - Each line contains a group of servers sharing powershell remoting
             credentials: hostnames/ips, username and (optional) encrypted password.

I.e. If you want to install two beat agents, and have two groups of servers,
the files could look something like this:
agents.txt:
metricbeat https://domain/metricbeat.zip
winlogbeat https://domain/winlogbeat.zip
creds.txt:
10.0.0.1,10.0.0.2 myuser1 01000000...
10.0.1.1,10.0.1.2 myuser2 01000000...

The password string must be encrypted at the machine and by the user who executes
this script, using the following command:
Read-Host -AsSecureString | ConvertFrom-SecureString
#>

Set-StrictMode -v latest
$ErrorActionPreference = "Stop"

function Main($mainArgs)
{
    [Diagnostics.Stopwatch] $totalWatch = [Diagnostics.Stopwatch]::StartNew()

    $parsedArgs = Parse-Args $mainargs # b/c powershell's own argument parser has caused me nothing but PAIN.
    if (!$parsedArgs)
    {
        Log ("Usage: powershell .\UpdateBeats.ps1 [-InstallLocal] [-DontStartServices] -s <elasticservers> -e <environments> -u <usernames> -p <passwords>") Red
        Log ("") Red
        Log ("Each parameter can be a single value or a comma separated array of values") Red
        Log ("matching the agents to be installed. If any of the 4 parameters are not") Red
        Log ("specified .yml files from existing beat agents will be reused.") Red
        exit 1
    }

    try
    {
        Setup-Environment $parsedArgs.installLocal $parsedArgs.startServices $parsedArgs.beatServers $parsedArgs.beatEnvironments $parsedArgs.beatUsernames $parsedArgs.beatPasswords
    }
    catch
    {
        Log ($_.Exception.ToString()) Red
        exit 1
    }

    Log ("Done: " + $totalWatch.Elapsed)
}

function Parse-Args([string[]] $mainArgs)
{
    $parsedArgs = $mainArgs
    $resultArgs = @{}

    if ($parsedArgs -contains "-InstallLocal")
    {
        $resultArgs.installLocal = $true
        $parsedArgs = @($parsedArgs | ? { $_ -ne "-InstallLocal" })
    }
    else
    {
        $resultArgs.installLocal = $false
    }
    if ($parsedArgs -contains "-DontStartServices")
    {
        $resultArgs.startServices = $false
        $parsedArgs = @($parsedArgs | ? { $_ -ne "-DontStartServices" })
    }
    else
    {
        $resultArgs.startServices = $true
    }

    
    [int] $offset = $parsedArgs.IndexOf("-s")
    if ($offset -ge 0 -and $offset -lt $parsedArgs.Count-1)
    {
        $resultArgs.beatServers = $parsedArgs[$offset+1].Split(",")
        $parsedArgs = @($parsedArgs | select -First $offset -Last ($parsedArgs.Count-$offset-2))
    }
    else
    {
        Log ("Reusing servers from old configuration files.")
        $resultArgs.beatServers = $null
    }

    [int] $offset = $parsedArgs.IndexOf("-e")
    if ($offset -ge 0 -and $offset -lt $parsedArgs.Count-1)
    {
        $resultArgs.beatEnvironments = $parsedArgs[$offset+1].Split(",")
        $parsedArgs = @($parsedArgs | select -First $offset -Last ($parsedArgs.Count-$offset-2))
    }
    else
    {
        Log ("Reusing environments from old configuration files.")
        $resultArgs.beatEnvironments = $null
    }

    [int] $offset = $parsedArgs.IndexOf("-u")
    if ($offset -ge 0 -and $offset -lt $parsedArgs.Count-1)
    {
        $resultArgs.beatUsernames = @($parsedArgs[$offset+1].Split(","))
        $parsedArgs = @($parsedArgs | select -First $offset -Last ($parsedArgs.Count-$offset-2))
    }
    else
    {
        Log ("Reusing usernames from old configuration files.")
        $resultArgs.beatUsernames = $null
    }

    [int] $offset = $parsedArgs.IndexOf("-p")
    if ($offset -ge 0 -and$offset -lt $parsedArgs.Count-1)
    {
        $resultArgs.beatPasswords = $parsedArgs[$offset+1].Split(",")
        $parsedArgs = @($parsedArgs | select -First $offset -Last ($parsedArgs.Count-$offset-2))
    }
    else
    {
        Log ("Reusing passwords from old configuration files.")
        $resultArgs.beatPasswords = $null
    }


    if ($parsedArgs.Count -ne 0)
    {
        Log ("Args left: '" + $parsedArgs + "'")
        return $null
    }

    return $resultArgs
}

function Get-Agents([string[]] $beatServers, [string[]] $beatEnvironments, [string[]] $beatUsernames, [string[]] $beatPasswords, [bool] $startServices)
{
    [string] $filename = "agents.txt"
    if (!(Test-Path $filename))
    {
        throw ("File not found: '" + $filename + "'")
    }

    [string[]] $rows = gc $filename | ? { !$_.StartsWith("#") }
    $agents = @()

    for ([int] $i=0; $i -lt $rows.Count; $i++)
    {
        [string[]] $tokens = $rows[$i].Split(" ")

        if ($tokens.Count -ne 2)
        {
            Log ("Malformed row: '" + $rows[$i] + "'") Yellow
            continue
        }

        $agent = @{
            name = $tokens[0]
            url = $tokens[1]
        }

        if (!$beatServers)
        {
            $agent.server = $null
        }
        elseif ($beatServers.Count -eq 1)
        {
            $agent.server = $beatServers[0]
        }
        else
        {
            $agent.server = $beatServers[$i]
        }

        if (!$beatEnvironments)
        {
            $agent.environment = $null
        }
        elseif ($beatEnvironments.Count -eq 1)
        {
            $agent.environment = $beatEnvironments[0]
        }
        else
        {
            $agent.environment = $beatEnvironments[$i]
        }

        if (!$beatUsernames)
        {
            $agent.username = $null
        }
        elseif ($beatUsernames.Count -eq 1)
        {
            $agent.username = $beatUsernames[0]
        }
        else
        {
            $agent.username = $beatUsernames[$i]
        }

        if (!$beatPasswords)
        {
            $agent.password = $null
        }
        elseif ($beatPasswords.Count -eq 1)
        {
            $agent.password = $beatPasswords[0]
        }
        else
        {
            $agent.password = $beatPasswords[$i]
        }

        [string] $customscript = $agent.name + ".ps1"
        if (Test-Path $customscript)
        {
            Log ("Reading custom script: '" + $customscript + "'")
            $agent.customscript = [IO.File]::ReadAllText((Join-Path (pwd).Path $customscript))
        }
        else
        {
            $agent.customscript = $null
        }

        [string] $customconfig = $agent.name + ".yml"
        if (Test-Path $customconfig)
        {
            Log ("Reading custom config: '" + $customconfig + "'")
            $agent.customconfig = [IO.File]::ReadAllText((Join-Path (pwd).Path $customconfig))
        }
        else
        {
            $agent.customconfig = $null
        }

        $agent.startservice = $startServices

        $agents += $agent
    }

    return $agents
}

function Get-ServerGroups()
{
    [string] $filename = "creds.txt"
    if (!(Test-Path $filename))
    {
        throw ("File not found: '" + $filename + "'")
    }

    [string[]] $rows = gc $filename | ? { !$_.StartsWith("#") }
    $serverGroups = @()

    for ([int] $i=0; $i -lt $rows.Count; $i++)
    {
        [string[]] $tokens = $rows[$i].Split(" ")

        $servers = $tokens[0].Split(",")

        $group = @{ servers = $servers }

        if ($tokens.Count -eq 3)
        {
            [string] $username = $tokens[1]
            [string] $encryptedPassword = $tokens[2]

            $ss = $encryptedPassword | ConvertTo-SecureString
            $group.credential = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $ss
        }
        else
        {
            Log ("Specify vm credentials for: '" + ($servers -join "', '") + "'")
            if ($tokens.Count -eq 2)
            {
                try
                {
                    $creds = Get-Credential $tokens[1]
                }
                catch
                {
                    throw ("Credentials not specified: " + $_.Exception.ToString())
                }
            }
            else
            {
                try
                {
                    $creds = Get-Credential
                }
                catch
                {
                    throw ("Credentials not specified: " + $_.Exception.ToString())
                }
            }

            $group.credential = $creds
        }

        $serverGroups += $group
    }

    return $serverGroups
}

function Get-Length([string] $text)
{
    if ($text)
    {
        return $text.Length
    }
    else
    {
        return "<null>"
    }
}

function Setup-Environment([bool] $installLocal, [bool] $startServices,
    [string[]] $beatServers, [string[]] $beatEnvironments, [string[]] $beatUsernames, [string[]] $beatPasswords)
{
    Log ("InstallLocal: " + $installLocal)

    if (!$installLocal)
    {
        $serverGroups = @(Get-ServerGroups)

        Log ("Servers:     '" + (($serverGroups | % { $_.servers }) -join "', '") + "'")
        Log ("Credentials: '" + (($serverGroups | % { $_.credential.username }) -join "', '") + "'")

        for ([int] $i=0; $i -lt $serverGroups.Count; $i++)
        {
            Invoke-Command -ComputerName $serverGroups[$i].servers -Credential $serverGroups[$i].credential { hostname }
        }
    }

    $agents = @(Get-Agents $beatServers $beatEnvironments $beatUsernames $beatPasswords $startServices)

    Log ("Names:                 '" + (($agents | % { $_.name }) -join "', '") + "'")
    Log ("Urls:                  '" + (($agents | % { $_.url }) -join "', '") + "'")
    Log ("Servers:               '" + (($agents | % { $_.server }) -join "', '") + "'")
    Log ("Environments:          '" + (($agents | % { $_.environment }) -join "', '") + "'")
    Log ("Usernames:             '" + (($agents | % { $_.username }) -join "', '") + "'")
    Log ("Passwords (length):    " + (($agents | % { Get-Length $_.password }) -join ", "))
    Log ("Customconfig (length): " + (($agents | % { Get-Length $_.customconfig }) -join ", "))
    Log ("Customscript (length): " + (($agents | % { Get-Length $_.customscript }) -join ", "))
    Log ("Startservice:          " + (($agents | % { $_.startservice }) -join ", "))

    [ScriptBlock] $installAgents = {
        Set-StrictMode -v latest
        $ErrorActionPreference = "Stop"

        [Diagnostics.Stopwatch] $watch = [Diagnostics.Stopwatch]::StartNew()

        function Log([string] $message, $color)
        {
            [string] $hostname = [System.Net.Dns]::GetHostName()
            [DateTime] $now = [DateTime]::UtcNow
            [string] $annotatedMessage = $now.ToString("yyyy-MM-dd HH:mm:ss") + ": " + $hostname + ": " + $message

            if ($color)
            {
                Write-Host $annotatedMessage -f $color
            }
            else
            {
                Write-Host $annotatedMessage -f Cyan
            }
        }

        function Robust-Delete([string] $folder)
        {
            if (Test-Path $folder)
            {
                for ([int] $tries=0; $tries -lt 10 -and (Test-Path $folder); $tries++)
                {
                    if ($tries -eq 0)
                    {
                        Log ("Deleting folder: '" + $folder + "'")
                    }
                    else
                    {
                        Log ("Deleting folder (try " + ($tries+1) + "): '" + $folder + "'")
                    }
                    rd $folder -Recurse -Force -ErrorAction SilentlyContinue
                    Start-Sleep 2
                }
                if (Test-Path $folder)
                {
                    throw ("Couldn't delete folder: '" + $folder + "'")
                }
            }
        }

        function Robust-Download([string] $url, [string] $filename)
        {
            for ([int] $tries=0; $tries -lt 10 -and (!(Test-Path $filename) -or (dir $filename).Length -eq 0); $tries++)
            {
                if ($tries -eq 0)
                {
                    Log ("Downloading: '" + $url + "' -> '" + $filename + "'")
                }
                else
                {
                    Log ("Downloading (try " + ($tries+1) + "): '" + $url + "' -> '" + $filename + "'")
                }

                try
                {
                    iwr $url -UseBasicParsing -OutFile $filename
                }
                catch
                {
                    Log ("Exception: '" + $_.Exception.ToString() + "'") Yellow
                }
            }
            if (!(Test-Path $filename) -or (dir $filename).Length -eq 0)
            {
                throw ("Couldn't download file: '" + $filename + "'")
            }
        }

        function Robust-StopService([string] $servicename)
        {
            if (!(Get-Service | ? { $_.Name -eq $servicename }))
            {
                Log ("Service not found: '" + $servicename + "'")
                return
            }

            if ((Get-Service $servicename).Status -eq "Stopped")
            {
                Log ("Service already stopped: '" + $servicename + "'")
            }
            else
            {
                for ([int] $tries=0; $tries -lt 10 -and (Get-Service $servicename).Status -ne "Stopped"; $tries++)
                {
                    if ($tries -eq 0)
                    {
                        Log ("Stopping service: '" + $servicename + "'")
                    }
                    else
                    {
                        Log ("Stopping service (try " + ($tries+1) + "): '" + $servicename + "'")
                    }
                    Stop-Service $servicename -ErrorAction SilentlyContinue
                    Start-Sleep 2
                }
                if ((Get-Service $servicename).Status -ne "Stopped")
                {
                    throw ("Couldn't stop service: '" + $servicename + "'")
                }
            }
        }

        function Robust-Move([string] $source, [string] $target)
        {
            for ([int] $tries=0; $tries -lt 10 -and !(Test-Path $target); $tries++)
            {
                Log ("Moving: '" + $source + "' -> '" + $target + "'")
                move $source $target -ErrorAction SilentlyContinue
                Start-Sleep 2
            }
            if (!(Test-Path $target))
            {
                throw ("Couldn't move: '" + $source + "' -> '" + $target + "'")
            }
        }

        function Update-ConfigFile([string] $filename, [string] $beatServer, [string] $beatEnvironment, [string] $beatUsername, [string] $beatPassword)
        {
            if (!$beatServer -and !$beatEnvironment -and !$beatUsername -and !$beatPassword)
            {
                return
            }

            Log ("Reading config file: '" + $filename + "'")
            [string[]] $rows = gc $filename

            for ([int] $i=0; $i -lt $rows.Count; $i++)
            {
                [string] $row = $rows[$i]
                if ($beatEnvironment -and $row -eq "#name:")
                {
                    [string] $newrow = "name: " + $beatEnvironment + "." + [System.Net.Dns]::GetHostName()
                    Log ("Updating row: '" + $row + "' -> '" + $newrow + "'")
                    $rows[$i] = $newrow
                }
                elseif ($beatEnvironment -and $row -eq "#fields:")
                {
                    [string] $newrow = "fields:"
                    Log ("Updating row: '" + $row + "' -> '" + $newrow + "'")
                    $rows[$i] = $newrow
                }
                elseif ($beatEnvironment -and $row -eq "#  env: staging")
                {
                    [string] $newrow = "  env: " + $beatEnvironment
                    Log ("Updating row: '" + $row + "' -> '" + $newrow + "'")
                    $rows[$i] = $newrow
                }
                elseif ($beatServer -and $row -eq '  hosts: ["localhost:9200"]')
                {
                    [string] $newrow = '  hosts: ["' + $beatServer + '"]'
                    Log ("Updating row: '" + $row + "' -> '" + $newrow + "'")
                    $rows[$i] = $newrow
                }
                elseif ($beatUsername -and $row -eq '  #username: "elastic"')
                {
                    [string] $newrow = '  username: "' + $beatUsername + '"'
                    Log ("Updating row: '" + $row + "' -> '" + $newrow + "'")
                    $rows[$i] = $newrow
                }
                elseif ($beatPassword -and $row -eq '  #password: "changeme"')
                {
                    [string] $newrow = '  password: "' + $beatPassword + '"'
                    Log ("Updating row: '" + $row + "' -> '" + $newrow + "'")
                    $rows[$i] = $newrow
                }
            }

            Log ("Saving " + $rows.Count + " rows: '" + $filename + "'")
            sc $filename $rows
        }

        function Download-Files($agents)
        {
            [string] $folder = (pwd).Path

            for ([int] $i=0; $i -lt $agents.Count; $i++)
            {
                [string] $url = $agents[$i].url
                [string] $filename = Join-Path $folder ($agents[$i].name + ".zip")

                Robust-Download $url $filename
            }
        }

        function Prepare-Files($agents)
        {
            [string] $dllpath = Join-Path $env:windir "Microsoft.NET\Framework64\v4.0.30319\System.IO.Compression.FileSystem.dll"
            Log ("Loading assembly: '" + $dllpath + "'")
            Add-Type -Path $dllpath

            for ([int] $i=0; $i -lt $agents.Count; $i++)
            {
                [string] $filename = $agents[$i].name + ".zip"

                Log ("Extracting zip file: '" + $filename + "'")
                [System.IO.Compression.ZipFile]::ExtractToDirectory($filename, ".")

                [string[]] $folders = @(dir ($agents[$i].name + "*") -Directory)
                if ($folders.Count -ne 1)
                {
                    throw ("Couldn't extract zip file: '" + $filename + "': Found " + $folders.Count + " subfolders.")
                }

                [string] $folder = $folders[0]
                if ($folder.Contains("-"))
                {
                    [string] $newname = $folder.Substring(0, $folder.IndexOf("-"))
                    Robust-Move $folder $newname
                    [string] $folder = $newname
                }

                [string] $configfile = Join-Path $agents[$i].name ($agents[$i].name + ".yml")
                [string] $target = Join-Path $agents[$i].name ($agents[$i].name + "_old.yml")
                Log ("Copying: '" + $configfile + "' -> '" + $target + "'")
                copy $configfile $target

                [string] $beatname        = $agents[$i].name
                [string] $beatServer      = $agents[$i].server
                [string] $beatEnvironment = $agents[$i].environment
                [string] $beatUsername    = $agents[$i].username
                [string] $beatPassword    = $agents[$i].password
                [string] $customConfig    = $agents[$i].customconfig

                if ($customConfig)
                {
                    Log ("Saving custom config file: '" + $configfile + "'")
                    [IO.File]::WriteAllText((Join-Path (pwd).Path $configfile), $customConfig)

                    if ($beatServer -or $beatEnvironment -or $beatUsername -or $beatPassword)
                    {
                        Update-ConfigFile $configfile $beatServer $beatEnvironment $beatUsername $beatPassword
                    }
                }
                elseif ($beatServer -or $beatEnvironment -or $beatUsername -or $beatPassword)
                {
                    Update-ConfigFile $configfile $beatServer $beatEnvironment $beatUsername $beatPassword
                }
                else
                {
                    [string] $oldconfigfile = Join-Path (Join-Path $env:ProgramFiles $beatname) ($beatname + ".yml")
                    if (Test-Path $oldconfigfile)
                    {
                        Log ("Keeping old config file: '" + $oldconfigfile + "' -> '" + $configfile + "'")
                        copy $oldconfigfile $configfile -Force
                    }
                }
            }
        }

        function Install-Beatagents($agents)
        {
            for ([int] $i=0; $i -lt $agents.Count; $i++)
            {
                [string] $beatname = $agents[$i].name
                [string] $url = $agents[$i].url

                Robust-StopService $beatname

                if (Get-Service | ? { $_.Name -eq $beatname })
                {
                    Log ("Deleting service: '" + $beatname + "'")
                    sc.exe delete $beatname
                    if (!$?)
                    {
                        throw ("Couldn't delete service: '" + $beatname + "'")
                    }
                }

                [string] $folder = Join-Path (Join-Path (Join-Path $env:ProgramData "chocolatey") "lib") $beatname
                Robust-Delete $folder


                [string] $folder = Join-Path $env:ProgramFiles $beatname

                Robust-Delete $folder

                Robust-Move $beatname $folder

                pushd
                cd $folder
                [System.IO.Directory]::SetCurrentDirectory((pwd).Path)

                [string] $scriptfile = Join-Path "." ("install-service-" + $beatname + ".ps1")
                Log ("Running script: '" + $scriptfile + "'")
                &$scriptfile

                popd
                [System.IO.Directory]::SetCurrentDirectory((pwd).Path)
            }
        }

        function Run-CustomScript($agents)
        {
            for ([int] $i=0; $i -lt $agents.Count; $i++)
            {
                if ($agents[$i].customscript)
                {
                    [string] $customscript = $agents.customscript
                    [string] $beatname = $agents[$i].name

                    [string] $folder = Join-Path $env:ProgramFiles $beatname

                    pushd
                    cd $folder
                    [System.IO.Directory]::SetCurrentDirectory((pwd).Path)

                    Log ("Current dir: '" + [System.IO.Directory]::GetCurrentDirectory() + "'")

                    [string] $scriptfile = Join-Path "." "customscript.ps1"
                    Log ("Saving custom script: '" + $scriptfile + "'")
                    [IO.File]::WriteAllText((Join-Path (pwd).Path $scriptfile), $customscript)


                    Log ("Running custom script: '" + $scriptfile + "'")
                    &$scriptfile

                    popd
                    [System.IO.Directory]::SetCurrentDirectory((pwd).Path)
                }
            }
        }

        function Start-Services($agents)
        {
            for ([int] $i=0; $i -lt $agents.Count; $i++)
            {
                [string] $servicename = $agents[$i].name

                if ($agents[$i].startservice)
                {
                    Log ("Starting service: '" + $servicename + "'")
                    Start-Service $servicename
                }
                else
                {
                    Log ("Not starting service: '" + $servicename + "'")
                }
            }
        }

        $agents = @($args[0])

        Log ("Got " + $agents.Count + " agents.")

        try
        {
            [string] $folder = "C:\install"
            Robust-Delete $folder

            [string] $folder = "C:\beatinstall"
            Robust-Delete $folder

            Log ("Creating folder: '" + $folder + "'")
            md $folder | Out-Null

            pushd
            cd $folder
            [System.IO.Directory]::SetCurrentDirectory((pwd).Path)

            Download-Files $agents
            Prepare-Files $agents

            Install-Beatagents $agents

            Run-CustomScript $agents

            Start-Services $agents

            popd
            [System.IO.Directory]::SetCurrentDirectory((pwd).Path)
            Robust-Delete $folder
        }
        catch
        {
            $now = [DateTime]::UtcNow
            [string] $logfile = Join-Path ([System.IO.Path]::GetTempPath()) ("beat_exception_" + $now.ToString("yyyyMMdd_HHmmss") + ".txt")

            "***** ERROR *****"  | Out-File -encoding Default $logfile -Append

            "Date: " + $now.ToString("yyyy-MM-dd HH:mm:ss")  | Out-File -Encoding Default $logfile -Append
            "Server: " + [System.Net.Dns]::GetHostName()     | Out-File -Encoding Default $logfile -Append
            "Exception: " + $_.Exception.ToString()          | Out-File -Encoding Default $logfile -Append

            # Notice: When outputting InvocationInfo using Out-File it will be serialized with more useful information.
            "InvocationInfo:"    | Out-File -Encoding Default $logfile -Append
            $_.InvocationInfo    | Out-File -Encoding Default $logfile -Append

            Write-Host ((@(gc $logfile) | ? { $_ }) -join "`n")

            Write-Host ([System.Net.Dns]::GetHostName() + ": Local log file: '" + $logfile + "'.")

            throw $_
        }


        Log ("Done: " + $watch.Elapsed)
    }

    if ($installLocal)
    {
        Invoke-Local $agents $installAgents
    }
    else
    {
        $invokeArgs = $agents,$null
        for ([int] $i=0; $i -lt $serverGroups.Count; $i++)
        {
            Invoke-Command -ComputerName $serverGroups[$i].servers -Credential $serverGroups[$i].credential -ArgumentList $invokeArgs -ScriptBlock $installAgents
        }
    }
}

function Invoke-Local($agents, [ScriptBlock] $installAgents)
{
    &$installAgents $agents
}

function Log([string] $message, $color)
{
    [string] $hostname = [System.Net.Dns]::GetHostName()
    [DateTime] $now = [DateTime]::UtcNow
    [string] $annotatedMessage = $now.ToString("yyyy-MM-dd HH:mm:ss") + ": " + $hostname + ": " + $message

    if ($color)
    {
        Write-Host $annotatedMessage -f $color
    }
    else
    {
        Write-Host $annotatedMessage -f Cyan
    }
}

Main $args

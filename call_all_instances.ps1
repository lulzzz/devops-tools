Set-StrictMode -v latest
$ErrorActionPreference = "Stop"

function Main()
{
    [string] $dllfile = "C:\Program Files (x86)\Microsoft SDKs\NuGetPackages\Microsoft.Net.Native.Compiler\2.0.0\tools\x64\ilc\tools\Newtonsoft.Json.dll"
    Write-Host ("Loading assembly: '" + $dllfile + "'")
    [Reflection.Assembly]::LoadFile($dllfile) | Out-Null


    [string] $tenantid = "xx"
    [string] $subscriptionid = "xx"
    [string] $clientid = "xx"
    [string] $key = "xx"

    [string] $resourcegroup = "xx"
    [string] $websitename = "xx"

    [string] $loginurl = "https://login.microsoftonline.com"
    [string] $managementurl = "https://management.azure.com"
    [string] $siteurl = "xx"


    [string] $url = $loginurl + "/" + $tenantid + "/oauth2/token?api-version=1.0"
    [string] $data = 'grant_type=client_credentials&resource=https%3A%2F%2Fmanagement.core.windows.net%2F&client_id=' + $clientid + '&client_secret=' + $key

    $result = curl.exe -XPOST $url `
        -d $data `
        -A '""' `
        -H 'Content-Type: application/x-www-form-urlencoded'

    $jtoken = [Newtonsoft.Json.Linq.Jtoken]::Parse($result)

    [string] $access_token = $jtoken.access_token.value


    [string] $url = $managementurl + "/subscriptions/" + $subscriptionid + "/resourceGroups/" + $resourcegroup + "/providers/Microsoft.Web/sites/" + $websitename + "/instances?api-version=2015-01-01"
    [string] $auth = "Authorization: Bearer " + $access_token

    $result = curl.exe $url `
        -A '""' `
        -H $auth `
        -H 'Content-Type: application/json'

    $jtoken = [Newtonsoft.Json.Linq.Jtoken]::Parse($result)

    $value = $jtoken.value

    [string[]] $instanceids = $value | % { $_.name.value }


    $instanceids | % {
        [string] $arraffinity = $_

        [string] $url = $siteurl + "/api/v1/heartbeat"
        $result = curl.exe $url `
            -A '""' `
            -b $arraffinity

        Write-Host $arraffinity
        Write-Host ("result: '" + $result + "'")
    }
}

Main

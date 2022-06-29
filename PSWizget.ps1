<#PSScriptInfo

.VERSION 1.0.11

.GUID acb8f443-01c8-40b3-9369-c5e6e28548d1

.AUTHOR zakret.code@gmx.com

.COMPANYNAME

.COPYRIGHT GPL-3.0

.TAGS PSEdition_Core PSEdition_Desktop windows winget batch upgrade wizard update all queue

.LICENSEURI https://opensource.org/licenses/GPL-3.0

.PROJECTURI https://github.com/zakret/PSwizget

.ICONURI

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES
- fixed issue with  Windows Powershell (desktop)
Long name packages (chars > 30) are still not supported on the desktop edition

.PRIVATEDATA

#>

<#
.SYNOPSIS
    PowerShell script that allow you to manage the upgrade process with winget.

.DESCRIPTION
    PowerShell script that allow you to manage the upgrade process with winget. 
    It adds a few more options than 'winget upgrade --all':
    - create a file with the packages you would like to omit
    - add or remove packages from toSkip file directly from the script
    - automatically omit packages with "unknown" installed version, or when the formats of
      the installed version and the available version formatest does not match
    - it tries to guess the correct installed version by reading the pattern 
      from the available version
    - manually edit the upgrade queue
    - quick mode (it's similar to 'winget upgrade --all' but with a blacklist applied)
    
    Known issue with Windows Powershell ver. <= 5.1 (desktop):
    Due to the ascii encoding, packages with longer names than 30 chars may corrupt 
    the 'winget upgrade' result, i.e. info about the long name package 
    and the packages listed after it. 
    Please use this script with PowerShell ver. > 5.1 (core) if you can 
    or avoid installing long name packages with winget.

.NOTES
    This is my first powershell script for educational purposes.

.EXAMPLE
    PS> .PSWizget.ps1

.PARAMETER quick
    The Script won't ask for any unessentialy input. It will exclude packages blacklisted 
    or with an unrecognized version and then the update will start.

.INPUTS
    None. You cannot pipe objects to PSWizget.ps1.

.OUTPUTS
    None. PSWizget.ps1 does not generate any output.

.LINK
    Project page https://github.com/Zakret/PSwizget

.FUNCTIONALITY
    winget batch upgrade wizard update all queue

#>

param (
    [switch]$quick
)

#region FUNCTIONS
function Split-Result {
    <#
    .SYNOPSIS
        Split the 'winget upgrade' result into three arrays: okList, noList, unknownVer

    .DESCRIPTION
        Split the 'winget upgrade' result into three groups: skippable (noList), 
        unrecognizable (unknownList) and upgradeable (okList) ones. 
        Also tries to correctly recognize packages with an incorrect format of the installed version.

        These objects must be defined in the script before calling this function:
        $upgradeList collection, with Package object with Name, ID, Version, AvailableVersion
        $toSkip array with packages IDs
    #>
    $Script:upgradeList | ForEach-Object -Begin {
        $okList = @()
        $noList = @()
        $unknownVer = @()
        $toSkip = Get-Content $Script:toSkipPath
    } -Process {   
        if ($toSkip -contains $_.Id) { $noList += $_ }
        elseif ($_.Version -contains "Unknown") { $unknownVer += $_ }
        elseif ([Math]::Abs($_.Version.Length - $_.AvailableVersion.Length) -gt 1){
            if (($_.Version.Length - $_.AvailableVersion.Length -gt 0) -and !$quick) {
                $versionPattern = $_.AvailableVersion -replace "[a-z]",'[a-z]'
                $versionPattern = $versionPattern -replace "[0-9]",'[0-9]'
                $versionPattern = $versionPattern -replace "\.",'\.'
                $_.Version -match "(?<Version>$($versionPattern))" | Out-Null
                $hostResponse = Read-Host "Is version '$($Matches.Version)' the correct version$(
                                        ) of $($_.Name) installed? Available version is '$(
                                        $_.AvailableVersion)'. [ Y ] for Yes, anything else to skip$(
                                        ) this package"
                if ( $hostResponse -like "y" ) {
                    $_.Version = $Matches.Version
                    $versionsCoparison = @($_.Version, $_.AvailableVersion) | 
                    Sort-Object -Descending
                    if ( $_.Version -eq $_.AvailableVersion -or `
                    $versionsCoparison[0] -eq $_.Version) {
                        Write-Host "There is no need to update $($_.Name). Omitting the package."
                    } else { $okList += $_ }
                } else { $unknownVer += $_ }
            } else {
                Write-Host "Installed ($($_.Version)) and available version ($(
                            $_.AvailableVersion)) formats for package $(
                            $_.Name) are different."
                $unknownList += $_
            }
        } else { $okList += $_ }
    } -End {
    return $okList, $noList, $unknownVer
    }
}

function Get-Answer {
    <#
    .SYNOPSIS
        Wait for user input for specified amount of time.

    .DESCRIPTION
        Wait for user input for specified amount of time. The delay is an integer and amounts to 0.1s. 
        By default it's 50, so ~5s. It only takes one key ready. After the delay, function
        returns False.

    .EXAMPLE
        Get-Answer -Delay 100
        wait 10 seconds for user input, return single key object or false if no input has been entered

    .PARAMETER Delay
        Waiting time for the function to return False expressed in 0.1s.
        
    .NOTES
        Code by Every Villain Is Lemons
        https://stackoverflow.com/a/16965646

    #>
    param( [ Parameter() ] [int]$Delay = 50 )
    $counter = 0    
    $host.UI.RawUI.FlushInputBuffer()
    while( $counter++ -lt $Delay ) {
        if ( $Host.UI.RawUI.KeyAvailable ) {
            $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp")
            break
        }
        else{
            Start-Sleep -Milliseconds 100
            $key = $false
        }
    }
    return ( $key )
}

function Write-PackagesStatus {
    <#
    .SYNOPSIS
        Show packages from array and message about their status

    .DESCRIPTION
        Show the status of packages, that means an array to which the package has been moved by 
        Split-Result function.
        It's displayed as follows: "Package/s <array> is/are <message>" or "<message>" 
        if list is empty.
    
    .EXAMPLE
        Write-PackagesStatus -packagesArray @(Package1, Package2) -secondHalf "fantastic!"
        "Packages Package1, Package2 are fantastic!"

    .PARAMETER packagesArray
        Array with list of packages of the same status.

    .PARAMETER secondHalf
        The string displayed after the package list. It's a status description.

    .PARAMETER emptyMessage
        The string displayed if the package array is empty
    #>

    param(
         [ Parameter(Mandatory) ]
         $packagesArray,
         [ Parameter(Mandatory) ]
         [string]$secondHalf,
         [ Parameter() ]
         [string]$emptyMessage = ""
    )
    if ( $packagesArray.Count -eq 1 ) {
        Write-Host "The package " -NoNewline
        Write-Host $packagesArray[0].Name -ForegroundColor Yellow -NoNewline
        Write-Host " is $($secondHalf)"
    } 
    elseif ( $packagesArray.Count -ne 0) {
        Write-Host "Packages " -NoNewline
        for ( $i=0; $i -lt $packagesArray.count; $i++){
            Write-Host $packagesArray[$i].Name -ForegroundColor Yellow -NoNewline
            if ( $i -ne $packagesArray.count-1 ) {Write-Host ', ' -NoNewline}
        }
        Write-Host " are $($secondHalf)"
    } 
    elseif ( $emptyMessage -ne "" ) {
        Write-Host $emptyMessage
    }
}

function Get-IntAnswer {
    <#
    .SYNOPSIS
        Get selected numbers from the options presented to the user. User input must be integers separated by 
        spaces.

    .DESCRIPTION
        Get selected numbers from the options presented to the user. Options are packages that can be manipulated. 
        User input must be integers separated by spaces, any other input will be rejected 
        by function.

        This object must be defined in the script before calling this function:
        $optionList collection of Package objects with Name, ID, Version, AvailableVersion
    #>
    $i = 0
    foreach ( $package in $optionsList ) {
        $i ++
        Write-Host "[$($i)] $($package.Name)"
    }
    $hostSelection = Read-Host @"

Select the package indexes to which you want to apply the changes (eg. 1 4). 
Press [ Q ] to return to the menu
"@
    do {
        $hostArray = $hostSelection.Split(" ")
        $wrongInput = $false
        if ( !$hostArray -or $hostArray -eq 'q') { 
            $hostArray = $false
            break
        }
        try {
            $hostArray = foreach ( $i in $hostArray ) { [Convert]::ToInt32($i) }
        } catch { $wrongInput = $true }
        if ( $wrongInput -eq $false ) {
            $wrongInput = $hostArray.Where({ $_ -le 0 -or $_ -gt $optionsList.Length},
                'SkipUntil', 1)
            $wrongInput = [boolean]$wrongInput
        }
        if ( $wrongInput -eq $true ) {
            $hostSelection = Read-Host "Don't be silly! Only mentioned numbers separated $(
                                        )by a space! Please select"
        }
    } while ( $wrongInput -eq $true )
    return $hostArray
}

function Show-Result {
    <#
    .DESCRIPTION
        It uses the Write-PackagesStatus function to return all the messages needed in this script 
        at once.
    #>
    Write-PackagesStatus -packagesArray $unknownVer -secondHalf $Script:unknownVerMessage
    Write-PackagesStatus -packagesArray $noList -secondHalf $Script:noListMessage
    Write-PackagesStatus -packagesArray $okList -secondHalf $Script:okListMessage `
    -emptyMessage $Script:emptyListMessage
}

function Write-Separator {
    <#
    .DESCRIPTION
        Write-Host a colored line made of multipled string.

    .PARAMETER type
        The string to be multiplied.

    .PARAMETER number
        Line length.

    .PARAMETER color
        Line color.
    .PARAMETER allowMultiLines
        Don't trim line to the window size
    #>

    param (
        [string]$type = '-',
        [int]$number = $host.UI.RawUI.BufferSize.Width,
        [string]$color = 'Green',
        [switch]$allowMultiLines
    )
$line = ''
for ( $i = 0; $i -lt $number; $i ++ ) { $line = $line + $type } 
if ( !$allowMultiLines -and $line -gt $host.UI.RawUI.BufferSize.Width) {
    $line = $line.Substring(0,$host.UI.RawUI.BufferSize.Width)
}
Write-Host $line -ForegroundColor $color
}

function Show-UI {
    <#
    .SYNOPSIS
        It shows the user all the available options that he can choose to manipulate the Skipt blacklist file
        or the update queue.

    .DESCRIPTION
        It shows the user all the available options that he can choose to manipulate the toSkip blacklist file
        or the update queue. Options available:
        - Add the package Id to the toSkip file
        - Remove package Id from file toSkip
        - Add the excluded packages to the update queue
        - Only this time, skip the package in the queue 
        - Create a new custom upgrade queue
        The function determines which packages are relevant to which option and shows them to the user 
        as an indexed list. The user select packages by entering their indexes separated 
        by spaces.
        The function has all the mechanisms needed for manipulation.

    .PARAMETER okList
        an object with packages to be updated

    .PARAMETER noList
        an object with blacklisted packages to be omitted

    .PARAMETER  unknownVer
        an object with packages to be omitted due to unrecognized version info

    .EXAMPLE
        Show-UI -okList $okList -noList $noList -unknownVer $unknownVer
        <Table with upgradable packages>
        ---
        Packages A, B are recognized incorrectly (installed version info).
        Package C is listed in the toSkip file.
        Package D id going to be updated.
        ---
        <a list with options indexed with single letters>
        [A] Option A
        ---
        Wait 10 sec or press anything else to continue
        <User input - only one char read>
        A
        <indexed list of packages relevant to selected option>
        [1] Package B
        [2] Package D
        Select the package indexes to which you want to apply the changes (eg. 1 4):
        <User input - integers seperated by spaces>
        1 2
        <Packages B and D are manipulated as indicated by the option>
        <Clear-Host and run function again>
        <User unput Enter>
        <Function ends>
    #>
param (
    [ Parameter(Mandatory) ]$okList, 
    [ Parameter(Mandatory) ]$noList, 
    [ Parameter(Mandatory) ]$unknownVer
)
Clear-Host
$Script:upgradeList | Format-Table
Write-Separator -type "‾"
Show-Result
Write-Separator
Write-Host @"
[ B ]    Add the package Id to the toSkip file
[ W ]    Remove package Id from file toSkip
[ A ]    Add the excluded packages to the update queue
[ S ]    Only this time, skip the package in the queue 
[ C ]    Create a new custom upgrade queue
"@
Write-Separator -number 55
Write-Host "Wait 10 sec or press anything else to continue"
Write-Separator -number 55

$hostResponse = Get-Answer -Delay 100
$optionsList = @()
switch ( $hostResponse.Character ) {
    'b' {
        $optionsList = $Script:upgradeList | Where-Object {$_ -NotIn $noList}
        if ( !$optionsList ) {
            Write-Host "There are no packages that could be added to the toSkip file."
        } else {
            $hostArray = Get-IntAnswer
            if ( $hostArray ) {
                foreach ( $k in $hostArray ) {
                    Add-Content -Path $Script:toSkipPath -Value $optionsList[$k - 1].Id
                    $toSkip, $noList = @(), @()
                    $toSkip = Get-Content $Script:toSkipPath
                    foreach ($package in $Script:upgradeList) {
                        if ($toSkip -contains $package.Id) 
                        { $noList += $package }
                    }
                    $okList = $oklist | Where-Object {$_ -notIn @($optionsList[$k - 1])}
                    if ( $null -eq $okList) { $okList = @() }
                    Write-Host "Added $($optionsList[$k - 1].Name) to the toSkip file."
                }
            }
        }
    }
    'w' {
        $optionsList = $noList
        if ( !$optionsList ) {
            Write-Host "For now, the toSkip file is empty"
        } else {
            $hostArray = Get-IntAnswer
            if ( $hostArray ) {
                foreach ( $k in $hostArray ) {
                    Set-Content -Path $Script:toSkipPath -Value (get-content -Path $Script:toSkipPath |
                    Select-String -SimpleMatch $optionsList[$k - 1].Id -NotMatch)
                    $noList = $nolist | Where-Object {$_ -notIn @($optionsList[$k - 1])}
                    if ( $null -eq $noList) { $noList = @() }
                    if ( $optionsList[$k - 1].Version -ne 'Unknown' ){
                        $okList += @($optionsList[$k - 1])
                    }
                    Write-Host "Removed $($optionsList[$k - 1].Name) from the toSkip file."
                }   
            }
        }
    }
    'a' {
        $optionsList = $unknownVer + $noList
        if ( !$optionsList ) {
            Write-Host "There are no excluded packages"
        } else {
            $hostArray = Get-IntAnswer
            if ( $hostArray ) {
                foreach ( $k in $hostArray ) {
                    $okList += @($optionsList[$k - 1])
                    Write-Host "Added $($optionsList[$k - 1].Name) to this upgrade queue."
                }
            }
        }
    }
    's' {
        $optionsList = $okList
        if ( !$optionsList ) {
            Write-Host "There are no upgradeable packages"
        } else {
            $hostArray = Get-IntAnswer
            if ( $hostArray ) {
                foreach ( $k in $hostArray ) {
                    $okList = $oklist | Where-Object {$_ -notin @($optionsList[$k - 1])}
                    if ( $null -eq $okList) { $okList = @() }
                    Write-Host "Removed $($optionsList[$k - 1].Name) from this upgrade queue."
                }
            }    
        }
    }
    'c' {
        $optionsList = $Script:upgradeList
        $hostArray = Get-IntAnswer
        if ( $hostArray ) {
            $okList = @()
            foreach ($k in $hostArray) {
                $okList += $optionsList[$k - 1]
            }
            $Script:okListS = $okList
            break
        }
    }
    { $_ -in 'b', 'w', 'a', 's'} { 
        if ( $hostArray ) { Get-Answer -Delay 20 | Out-Null }
        $Script:okListS = $okList
        Show-UI -okList $okList -noList $noList -unknownVer $unknownVer
    }
}
}
#endregion FUNCTIONS

#region STARTUP
Write-Host 'Please wait...'

# window configuration
$host.UI.RawUI.BufferSize.Width = 120;  $host.UI.RawUI.WindowSize.Width = 120
$oldTitle = $host.UI.RawUI.WindowTitle; $host.UI.RawUI.WindowTitle = 'PS Wizget'

# winget test
$wingetExist = test-path -path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\winget.exe"
if ( !$wingetExist ) {
    Write-Host -NoNewline -ForegroundColor Yellow "First please install winget from msstore"
    return
}

# encoding test
if( $OutputEncoding.WindowsCodePage -ne 1200 ) {
    Write-Host "Your Powershell encoding is not utf8. Packages with longer names than 30 chars $(
               )may corrupt the 'winget upgrade' result." -ForegroundColor Red
    Write-Host "Powershell encoding : ", $OutputEncoding.HeaderName
} 

# create and read toSkip blacklist file
$toSkipPath = "~\toSkip.txt"
if ( !(Test-Path -Path $toSkipPath) ) {
  New-Item -Path $toSkipPath -ItemType file
  Write-Host
  Write-Host "A 'toSkip' file has been created in " -NoNewline
  Write-Host $(Resolve-Path -path $toSkipPath) -ForegroundColor Yellow
  Read-Host "Add the IDs of packages with a different format for 'version' and $(
            )'available version' to this file"
}

# internet connection test
Write-Host -NoNewline  -ForegroundColor Yellow "`rTesting connection...         "
if ( !( Test-Connection 8.8.8.8 -Count 3 -Quiet ) ) {
    Write-Host -ForegroundColor Yellow "`rNo internet connection.       "
  Return
}
#endregion STARTUP

Write-Host -ForegroundColor Yellow "`rConnected. Fetching from 'winget upgrade'..."
#region FETCHING UPGRADEABLE PACKAGES
#       FROM WINGET TO COLLECTION OF OBJECT
#It's not mine code in this region. I found it on stackoverflow some time ago but can't find it now.
#Temporory no author, no link

class Software {
    [string]$Name
    [string]$Id
    [string]$Version
    [string]$AvailableVersion
}

$upgradeResult = winget upgrade | Out-String

# my fix to this code
$upgradeResult = $upgradeResult -replace 'ÔÇŽ', ' '


$lines = $upgradeResult.Split([Environment]::NewLine)

# Find the line that starts with Name, it contains the header
$fl = 0
while (-not $lines[$fl].StartsWith("Name")) { $fl++ }

# Line $i has the header, we can find char where we find ID and Version
$idStart = $lines[$fl].IndexOf("Id")
$versionStart = $lines[$fl].IndexOf("Version")
$availableStart = $lines[$fl].IndexOf("Available")
$sourceStart = $lines[$fl].IndexOf("Source")

# Now cycle in real package and split accordingly
$upgradeList = @()
for ($i = $fl + 1; $i -le $lines.Length; $i++) {
    $line = $lines[$i]
    if ($line.Length -gt ($availableStart + 1) -and -not $line.StartsWith('-')) {
        $name = $line.Substring(0, $idStart).TrimEnd()
        $id = $line.Substring($idStart, $versionStart - $idStart).TrimEnd()
        $version = $line.Substring($versionStart, $availableStart - $versionStart).TrimEnd()
        $available = $line.Substring($availableStart, $sourceStart - $availableStart).TrimEnd()
        $software = [Software]::new()
        $software.Name = $name
        $software.Id = $id
        $software.Version = $version
        $software.AvailableVersion = $available

        $upgradeList += $software
    }
}
#endregion FETCHING UPGRADEABLE PACKAGES

#region POSTPROCESSING WINGET UPGRAGE RESULT      
$upgradeList = $upgradeList | Sort-Object -Property Id -Unique
If ( !$upgradeList ) {
    Read-Host "There are no packages to upgrade. Press Enter to close this window"
    return
}

$maxLength = 20
foreach ( $package in $upgradeList) {
    if ( $package.Name.Length -gt $maxLength -and $package.Name.Length -le $package.ID.Length) {
        $package.Name = $package.Name.Substring(0,$maxLength-3) + '...'
    } 
    elseif ( $package.Name.Length -gt $maxLength -and $package.Name.Length -gt $package.ID.Length) {
        $package.Name = $package.Name.Substring(0,$package.ID.Length-3) + '...'
    }
}
#endregion POSTPROCESSING WINGET UPGRAGE RESULT

#region PREPARING MESSAGES ABOUT PACKAGES STATUSES
$unknownVerMessage = "recognized incorrectly (installed version info)."
$noListMessage = "listed in the toSkip file."
$okListMessage = "going to be updated."
$emptyListMessage = "There are no packages to upgrade."
#endregion PREPARING MESSAGES ABOUT PACKAGES STATUSES

#region UI
$okListS, $noListS, $unknownVerS = @(), @(), @()
$okListS, $noListS, $unknownVerS = Split-Result

if ( !$quick ) {
    Show-UI -okList $okListS -noList $noListS -unknownVer $unknownVerS
}
#endregion UI

#region UPGRADE A BATCH OF PACKAGES
Write-PackagesStatus -packagesArray $okListS -secondHalf $okListMessage -emptyMessage $emptyListMessage

if ( $oklistS.Count -gt 0) {
    Write-Host
    $abort = Read-Host '[ Enter ] to continue, [ Q ] to abort'
    if ( $abort -ne 'q') {
        foreach ($package in $okListS) {
            $host.UI.RawUI.WindowTitle = "PS Wizget: Updating " + $package.Name
            Write-Host
            Write-Host "Updating the $($package.Name) application."
            & winget upgrade $package.Id -h
        }
        Write-Host
        Write-Host "All updates completed" -ForegroundColor Yellow
    }
}

$host.UI.RawUI.WindowTitle = $oldTitle
#endregion UPGRADE A BATCH OF PACKAGES

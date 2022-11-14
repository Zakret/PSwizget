<#PSScriptInfo

.VERSION 1.0.15-alpha

.GUID acb8f443-01c8-40b3-9369-c5e6e28548d1

.AUTHOR zakret.code@gmx.com

.COMPANYNAME

.COPYRIGHT GPL-3.0

.TAGS PSEdition_Core PSEdition_Desktop windows winget batch upgrade wizard update all queue

.LICENSEURI https://opensource.org/licenses/GPL-3.0

.PROJECTURI https://github.com/zakret/PSwizget

.ICONURI

.EXTERNALMODULEDEPENDENCIES PowerShellGet

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES
    - the package manifest file is downloaded if there is an update for it. 
    Information about the release notes and the URL for them are retrieved from the manifest file;
    - additional files to the script are now placed in the folder;
    - testing the Internet connection can be omitted with the omitNetTest parameter;
    - reformating the table, separators and menu;
    - better parameter validation, error handling and easier debugging;
    - adjusted version recognition mechanism;
    - the script can now play an idle animation while waiting for the user's response 
    ( idleAnimation parameter ).

.PRIVATEDATA

#>

<#
.SYNOPSIS
    PowerShell script that allow you to manage the upgrade process with winget.

.DESCRIPTION
    PowerShell script that allow you to manage the upgrade process with winget. 
    It adds a few more options than 'winget upgrade --all':
    - create a file with the packages you would like to omit;
    - add or remove packages from the blacklist file directly from the script;
    - automatically omit packages with "unknown" installed version, or when the formats of
      the installed version and the available version formats does not match;
    - it tries to guess the correct installed version by reading the pattern 
      from the available version;
    - manually edit the upgrade queue;
    - quick mode (it's similar to 'winget upgrade --all' but with a blacklist applied);
    - wingetParam <string> option with custom parameters to pass to winget. '-h' is set by default;
    - you can preselect one of the options available from the menu by adding the -option parameter
    with A, C or S argument.
    
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

.INPUTS
    None. You cannot pipe objects to PSWizget.ps1.

.OUTPUTS
    None. PSWizget.ps1 does not generate any output.

.LINK
    Project page https://github.com/Zakret/PSwizget

.FUNCTIONALITY
    winget batch upgrade wizard update all queue

.PARAMETER quick
    The Script won't ask for any unessentialy input. It will exclude packages blacklisted 
    or with an unrecognized version and then the update will start.

.PARAMETER wizgetFolderPath
    Non-standard location of the local Wizget folder. Default is "~\Wizget\". It will contain all 
    files required by the script. It doesn't need to be created beforehand.

.PARAMETER wingetParam
    custom parameters to pass to winget. '-h' is set by default.

.PARAMETER omitNetTest
    With this parameter setting, the script will assume that you are connected.

.PARAMETER idleAnimation
    Add an ASCII animation in the bottom-right corner of the menu. Put the animation in a folder 
    and save all its frames as txt files.

.PARAMETER option
    Start with the pre-selected option:
    C custom queue creation.
    A package addition.
    S package omission.

.PARAMETER waitingTime
    Wait x seconds and then proceed with the update.
#>

[CmdletBinding(DefaultParameterSetName = 'set0')]
param (
    [Parameter(Position=2)]
    [string]$wizgetFolderPath = "~\Wizget\",
    [Parameter(Position=3)]
    [string]$wingetParam = "-h",
    [switch]$omitNetTest,
    [Parameter(Position=4)]
    [string[]]$idleAnimation,
    [ Parameter(ParameterSetName="set1") ]
    [switch]$quick,
    [ Parameter(ParameterSetName="set2", Position=1) ]
    [ ValidateSet( 'a', 's', 'c' ) ]
    [char]$option,
    [ Parameter(ParameterSetName="set2", Position=1) ]
    [int32]$waitingTime
)

DynamicParam {
  if ($idleAnimation) {
    $parameterAttribute = [System.Management.Automation.ParameterAttribute]@{
        Mandatory = $false
        ParameterSetName = '__AllParameterSets'
        Position = 5
    }

    $attributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
    $attributeCollection.Add($parameterAttribute)
    $attributeCollection.Add((New-Object System.Management.Automation.ValidateRangeAttribute(1,100)))

    $dynParam1 = [System.Management.Automation.RuntimeDefinedParameter]::new(
      "idleSpeed", [Int32], $attributeCollection
    )
    $PSBoundParameters["idleSpeed"] = 1

    $paramDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
    $paramDictionary.Add('idleSpeed', $dynParam1)
    return $paramDictionary
  }
}

Process {
    
#region FUNCTIONS
#region UNIVERSAL FUNCTIONS
function Write-Art {
    param (
        [Parameter(Mandatory, Position=1)]
        [ValidateCount(2,2)]
        [int[]]$startPoint,
        [Parameter(Mandatory, Position=2)]
        [string]$artPath,
        [Parameter(Position=3)]
        [ValidateCount(0,2)]
        [string[]]$chosenColors
    )

    $currentPosition = $Host.UI.RawUI.CursorPosition
    $Colors = [enum]::GetValues([System.ConsoleColor])
    foreach ($color in $chosenColors) {
        if ($color -eq "Random") {
            $chosenColors[$chosenColors.IndexOf($color)] = Get-Random -InputObject $Colors
        } elseif ($Colors -notcontains $color) {
            [Console]::SetCursorPosition($startPoint[0],$startPoint[1]-1)
            Write-Error "'$($color)' is not a color supported by Powershell" -ErrorAction SilentlyContinue
            $Host.UI.RawUI.CursorPosition = $currentPosition
            if ($color -eq $chosenColors[0]) {
                $chosenColors[$chosenColors.IndexOf($color)] = $host.UI.RawUI.ForegroundColor
            } else {
                $chosenColors[$chosenColors.IndexOf($color)] = $host.UI.RawUI.BackgroundColor
            }
        }
    }
    
    if (!$chosenColors[0]) {
        $chosenColors =@()
        $chosenColors += $host.UI.RawUI.ForegroundColor
    } 
    if(!$chosenColors[1]) {$chosenColors += $host.UI.RawUI.BackgroundColor}

    if (!(Test-Path -Path $artPath)) {
        $art = $artPath.Split("`n")
    } else {
        $art = Get-Content -Path $artPath
    }
    for ($l=0; $l -lt $art.Count; $l++) {
        [Console]::SetCursorPosition($startPoint[0],$startPoint[1]+$l)
        Write-Host $art[$l] -ForegroundColor $chosenColors[0] -BackgroundColor $chosenColors[1]
    }
    $Host.UI.RawUI.CursorPosition = $currentPosition
}

function Clear-HostRange {
    <#
    .DESCRIPTION
        The function clears the specified range of console lines. After that, the cursor 
        will return to its last location. If no parameters are specified, clears the line 
        before the cursor position and moves the cursor to that position. 
        If only a start point is specified, the end point will be the index of the line before 
        the cursor position. If only the end point is specified, the start point will be set to 0.
    .PARAMETER Startpoint
        Index of the line at which line clear up will begin.
    .PARAMETER Endpoint
        Index of the line at which line clear up will end.
    #>
    Param (
        [Parameter(Position=1)]
        [int32]$Startpoint,
        [Parameter(Position=2)]
        [int32]$Endtpoint
    )
    $CurrentLine  = $Host.UI.RawUI.CursorPosition.Y
    $ConsoleWidth = $Host.UI.RawUI.BufferSize.Width
    if ( !$Startpoint -and !$Endtpoint ) {
        $Range = @($($CurrentLine-1),$($CurrentLine))
    } else{
        $Range = @(0,$($CurrentLine-1))
        if ( $Startpoint ) { $Range[0] = $Startpoint }
        if ( $Endtpoint ) { $Range[1] = $Endtpoint }
    }
    $Range | ForEach-Object {
        if ( $_ -lt 0 -or $_ -ge ($host.UI.RawUI.BufferSize.Height)) {Write-Error "'$_' is out of the buffer size."}
    }
    
    $Range = $Range | Sort-Object
    
    $Count = $Range[1]-$Range[0]
    $i = 0
    for ($i; $i -le $Count; $i++) {
        [Console]::SetCursorPosition(0,($Range[0] + $i))
        [Console]::Write("{0,$ConsoleWidth}" -f " ")
        [Console]::SetCursorPosition(0,($Range[0] + $i))
    }
    if ( !$Startpoint -and !$Endtpoint ) {
        [Console]::SetCursorPosition(0,($Currentline-1))
    } else {
        [Console]::SetCursorPosition(0,($Currentline-1))
        [Console]::Write("{0,$ConsoleWidth}" -f " ")
        [Console]::SetCursorPosition(0,($Currentline-1))
    }
}
function Write-Separator {
    <#
    .DESCRIPTION
        Write-Host a colored line made of multipled string.

    .PARAMETER type
        The string to be multiplied.

    .PARAMETER length
        Line length.

    .PARAMETER color
        Line color.

    .PARAMETER allowMultiLines
        The line won't be trimmed to the window size.

    .PARAMETER noNewLine
        Cursor position will be set to the end of the line.

    .PARAMETER header
        Header will be print on the central position of the line.
        
    #>

    param (
        [string]$type = '-',
        [string]$color = 'Green',
        [string]$header,
        [string]$headerColor,
        [switch]$allowMultiLines,
        [int]$length = $host.UI.RawUI.BufferSize.Width,
        [switch]$noNewLine,
        $position
    )
    $currentPosition = $Host.UI.RawUI.CursorPosition.Y

    if ($color -notin ([enum]::GetValues([System.ConsoleColor]))) {$color = 'Green'}
    $line = ''
    if ($header) { $start = [int32]$($length/2-$header.Length/2-2)}
    for ( $i = 0; $i -lt $length; $i ++ ) { 
        $line = $line + $type 
    } 
    if ( !$allowMultiLines -and $line -gt $host.UI.RawUI.BufferSize.Width) {
        $line = $line.Substring(0,$host.UI.RawUI.BufferSize.Width)
    }
    
    if ($null -ne $position) {
        if ($position -isnot 'int' -or $position -lt 0) { 
            Write-Error '$position is not an valid integer'
        }
        [Console]::SetCursorPosition(0,($position))
    } 
    
    if ($header) {
        if (!$headerColor) { $headerColor = $color }
        if ($headerColor -notin ([enum]::GetValues([System.ConsoleColor]))) {$color = 'Green'}
        [int32]$start = [int32]$($line.Length/2 - ($header.Length+4)/2)
        $shortLine = $line.Substring(0,$start)
        Write-host "$($shortLine)[ " -ForegroundColor $color -NoNewline
        Write-Host $header -ForegroundColor $headerColor -NoNewline
        Write-host " ]$($shortLine)" -ForegroundColor $color

    } else {
        Write-Host $line -ForegroundColor $color
    }
    
    if ($noNewLine){
        if ( $null -eq $position ) { [Console]::SetCursorPosition($line.Length, `
            ($Host.UI.RawUI.CursorPosition.Y-1)) 
        } else { [Console]::SetCursorPosition($line.Length,$position) }
    }
    if ( $null -ne $position -and !$noNewLine ) { [Console]::SetCursorPosition(0, ($currentPosition)) }
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
    param( [ Parameter(Position = 1) ] [int]$Delay = 0 )
    $counter = 0    
    $host.UI.RawUI.FlushInputBuffer()
    if ($Delay -eq 0) {Write-Host "`rPress anything else to continue.    " -NoNewline}
    while( ($counter++ -lt $Delay) -or $Delay -eq 0) {
        if ( $Host.UI.RawUI.KeyAvailable ) {
            $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp")
            break
        }
        else{
            #start extra useless segment for the script (not universal)
            if (($i=($counter-1)/$Script:PSBoundParameters.idlespeed) -is "int" -and ($Delay -gt 50 -or $Delay -eq 0) -and $frames) {
                $i = $i - [int]($i/($frames.Count-1))*($frames.Count-1)
                Write-Art 56,($host.UI.RawUI.CursorPosition.Y-7) $frames[$i].FullName $idleAnimation[1],$idleAnimation[2]
            } 
            #end extra useless segment for the script (not universal)
            if (($k=($counter-1)/10) -is "int" -and $Delay -ne 0) {
                Write-Host "`rWait $($Delay/10-[int32]$k) sec or press anything else to continue.    " -NoNewline
            }
            Start-Sleep -Milliseconds 100
            $key = $false
        }
    }
    Write-Host "`r                                                   " -NoNewline
    Write-Host "`r" -NoNewline
    return ( $key )
}

function Get-IntAnswer {
    <#
    .SYNOPSIS
        Get selected numbers from the options presented to the user. User input must be integers separated by 
        spaces.

    .DESCRIPTION
        Get selected numbers from the options presented to the user.  
        User input must be integers separated by spaces, any other input will be rejected 
        by function.

    .PARAMETER options
        an array of item names from which the user can choose
    #>

    param (
        [ Parameter(Mandatory) ]
        [ string[] ]$options
    )
    $options | ForEach-Object {$i = 0} {
        $i ++
        Write-Host "[ $($i) ]    $($_)"
    }
    Write-Separator -length 55
    $hostSelection = Read-Host @"
Select the package indexes to which you want to apply the changes (eg. 1 4). 
Press [ Q ] to return to the menu
"@
    do {
        $hostArray = $hostSelection.Split(" ")
        $wrongInput = $false
        if ( !$hostArray -or $hostArray -eq 'q') { 
            break
        }
        try {
            $hostArray = foreach ( $i in $hostArray ) { [Convert]::ToInt32($i) }
        } catch { $wrongInput = $true }
        if ( $wrongInput -eq $false ) {
            $wrongInput = $hostArray.Where({ $_ -le 0 -or $_ -gt $options.Count},
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
        Write-PackagesStatus -namesArray @(Package1, Package2) -secondHalf "fantastic!"
        "Packages Package1, Package2 are fantastic!"

    .PARAMETER namesArray
        Array with list of packages names of the same status.

    .PARAMETER secondHalf
        The string displayed after the package list. It's a status description.

    .PARAMETER emptyMessage
        The string displayed if the package array is empty
    #>

    param(
         [ Parameter(Mandatory) ]
         [ AllowNull() ]
         [string[]]$namesArray,
         [ Parameter(Mandatory) ]
         [string]$secondHalf,
         [ Parameter() ]
         [string]$emptyMessage = ""
    )
    if ( $namesArray.Count -eq 1 ) {
        Write-Host "The " -NoNewline
        Write-Host $namesArray[0] -ForegroundColor Yellow -NoNewline
        Write-Host " package is $($secondHalf)"
    } 
    elseif ( $namesArray.Count -ne 0) {
        Write-Host "Packages " -NoNewline
        for ( $i=0; $i -lt $namesArray.count; $i++){
            Write-Host $namesArray[$i] -ForegroundColor Yellow -NoNewline
            if ( $i -ne $namesArray.count-1 ) {Write-Host ', ' -NoNewline}
        }
        Write-Host " are $($secondHalf)"
    } 
    elseif ( $emptyMessage -ne "" ) {
        Write-Host $emptyMessage -ForegroundColor Yellow
    }
}
#endregion UNIVERSAL FUNCTIONS

#region FUNCTIONS SPECIFIED FOR THE SCRIPT
function Reset-Setup {
    <#
    .DESCRIPTION
        Reset the values to their past state before the script was initialized.
    #>
    $host.UI.RawUI.WindowTitle = $initialSetup.WindowTitle
    $VerbosePreference = $initialSetup.VerbosePreference
    $InformationPreference = $initialSetup.InformationPreference
}

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
        $blacklistPath with location to the blacklist file
    #>
    [OutputType([Object[]])]
    $Script:upgradeList | ForEach-Object -Begin {
        $okList = @()
        $noList = @()
        $unknownVer = @()
    } -Process {   
        if ($Script:toSkip -contains $_.Id) { $noList += $_ }
        elseif ($_.Version -contains "Unknown") { $unknownVer += $_ }
        elseif (($_.Version.Length -gt $_.AvailableVersion.Length) -and !$quick) {
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
                $versionsComparison = @($_.Version, $_.AvailableVersion) | 
                Sort-Object -Descending
                if ( $_.Version -eq $_.AvailableVersion -or `
                $versionsComparison[0] -eq $_.Version) {
                    Write-Information "There is no need to update $($_.Name). Omitting the package."
                    $dummyAnswer = Get-Answer 30
                    if ( $dummyAnswer ){}
                } else { $okList += $_ }
            } else { $unknownVer += $_ }
        } elseif ($_.Version.Length -lt $_.AvailableVersion.Length) {
            $_.AvailableVersion -match '(^.*(?<numberToCompare>[0-9])\.[0-9]+$)' | Out-Null
            $availableNumber = $Matches.numberToCompare
            $_.Version -match '(^.*(?<numberToCompare>[0-9])$)' | Out-Null
            $currentNumber = $Matches.numberToCompare
            if ( $availableNumber -and $currentNumber) {
                if ( $availableNumber -ge $currentNumber ) { 
                    $okList += $_
                } else {
                    Write-Information "There is no need to update $($_.Name). Omitting the package."
                    $dummyAnswer = Get-Answer 30
                    if ( $dummyAnswer ){}
                }
            } else {
                $unknownVer += $_
                Write-Information "Installed ($($_.Version)) and available version ($(
                            $_.AvailableVersion)) formats for package $(
                            $_.Name) are different."
                $dummyAnswer = Get-Answer 30
                if ( $dummyAnswer ){}
            }
        } else { $okList += $_ }
    } -End {
        return $okList, $noList, $unknownVer
    }
}

function Show-Result {
    <#
    .DESCRIPTION
        It uses the Write-PackagesStatus function to return all the messages needed in this script 
        at once.
    #>
    Write-PackagesStatus -namesArray $unknownVer.Name -secondHalf $Script:unknownVerMessage
    Write-PackagesStatus -namesArray $noList.Name -secondHalf $Script:noListMessage
    Write-PackagesStatus -namesArray $okList.Name -secondHalf $Script:okListMessage `
    -emptyMessage $Script:emptyListMessage
}

function Show-UI {
    <#
    .SYNOPSIS
        It shows the user all the available options that he can choose to manipulate the blacklist file
        or the update queue.

    .DESCRIPTION
        It shows the user all the available options that he can choose to manipulate the blacklist file
        or the update queue. Options available:
        - Add the package Id to the blacklist file
        - Remove package Id from the blacklist
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
        Package C is listed in the blacklist file.
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
if ( !$Script:extraLine ) {Write-Host} # BUG 01 fix

#region CUSTOM FORMAT-TABLE
$columnsDivision = @(0.30,0.30,0.20,0.20)
$List = $Script:upgradeList
if ($Script:timeForUpdate) { $List += $Script:WizgetInfo}
$formatedList = $List | Select-Object -Property * `
-ExcludeProperty ManifestURL,ReleaseNotes,ReleaseNotesURL
if ( $($columnsDivision | Measure-Object -Sum).sum -ne 1 ) {Write-Error "Wrong division"}

$columnsTitles = $formatedList[0].psobject.properties | Select-Object name
$columnsTitles = $columnsTitles.Name

$columnsTitles | ForEach-Object -Begin {$columnsWidth = ''; $i =0} -Process {
    $columnsWidth += '@{ e="'+$_+'"; Width = '+
        $([Math]::Truncate($columnsDivision[$i]*$maxWidth))+' }, '
    $i++
} -End {$columnsWidth = $columnsWidth.TrimEnd(', ')}

$codeString = [scriptblock]::Create($('$formatedList | Format-Table -Property '+$columnsWidth))
Invoke-Command -ScriptBlock $codeString
Clear-HostRange
Write-Separator -position 3 -length $maxWidth
#endregion CUSTOM FORMAT-TABLE

# Headline
$halfWidth = [math]::Truncate($maxWidth/2)
$currentLine = $host.UI.RawUI.CursorPosition.Y
Write-Separator -position 0 -header ($Script:scriptInfo.Name+", ver. "+$Script:scriptInfo.Version) `
-headerColor $host.UI.RawUI.ForegroundColor -length $halfWidth -noNewLine
Write-Separator -header $Script:scriptInfo.ProjectUri `
-headerColor $host.UI.RawUI.ForegroundColor -length $halfWidth
[Console]::SetCursorPosition(0,$currentLine)

# Menu
Write-Separator -length $maxWidth
Show-Result
Write-Separator -length $maxWidth
Write-Host @"
[ B ]    Add the package Id to the blacklist file
[ W ]    Remove package Id from the blacklist
[ A ]    Add the excluded packages to the update queue
[ S ]    Only this time, skip the package in the queue 
[ C ]    Create a new custom upgrade queue
[ R ]    Read the release notes for the package
"@
Write-Separator -length 55
if ($idleAnimation -and !$frames) {
    Write-Art 56,($host.UI.RawUI.CursorPosition.Y-8) $idleAnimation[0] $idleAnimation[1],$idleAnimation[2]
}
$hostResponse = New-Object -TypeName System.Management.Automation.Host.KeyInfo
if ( $option -eq 'a' ) {
    Write-Host "Do you want to add one of these packages to the update queue?"
    $hostResponse.Character = "a"
    $option = $false
} elseif ( $option -eq 'c' ) {
    Write-Host "Please define the update queue:"
    $hostResponse.Character = "c"
    $option = $false
} elseif ( $option -eq 's' ) {
    Write-Host "Do you want to omit any of these packages?"
    $hostResponse.Character = "s"
    $option = $false
} else {
    $hostResponse = Get-Answer -Delay $($waitingTime*10)
}
$optionsList = @()
switch ( $hostResponse.Character ) {
    'b' {
        $optionsList = $Script:upgradeList | Where-Object {$_ -NotIn $noList}
        if ( !$optionsList ) {
            Write-Verbose "`rThere are no packages that could be added to the blacklist file."
        } else {
            $hostArray = Get-IntAnswer -options $optionsList.Name
            if ( $hostArray -notin @('q', $false ) ) {
                foreach ( $k in $hostArray ) {
                    Add-Content -Path $Script:blacklistPath -Value $optionsList[$k - 1].Id
                    $toSkip, $noList = @(), @()
                    $toSkip = Get-Content $Script:blacklistPath
                    foreach ($package in $Script:upgradeList) {
                        if ($toSkip -contains $package.Id) 
                        { $noList += $package }
                    }
                    $okList = $oklist | Where-Object {$_ -notIn @($optionsList[$k - 1])}
                    if ( $null -eq $okList) { $okList = @() }
                    Write-Verbose "`rAdded $($optionsList[$k - 1].Name) to the blacklist file."
                }
            }
        }
    }
    'w' {
        $optionsList = $noList
        if ( !$optionsList ) {
            Write-Verbose "`rFor now, the blacklist file is empty"
        } else {
            $hostArray = Get-IntAnswer -options $optionsList.Name
            if ( $hostArray -notin @('q', $false ) ) {
                foreach ( $k in $hostArray ) {
                    Set-Content -Path $Script:blacklistPath -Value (get-content `
                    -Path $Script:blacklistPath | Where-Object {$_.trim() -ne ""} | Select-String `
                    -SimpleMatch $optionsList[$k - 1].Id -NotMatch)
                    $noList = $nolist | Where-Object {$_ -notIn @($optionsList[$k - 1])}
                    if ( $null -eq $noList) { $noList = @() }
                    if ( $optionsList[$k - 1].Version -ne 'Unknown' ){
                        $okList += @($optionsList[$k - 1])
                    }
                    Write-Verbose "`rRemoved $($optionsList[$k - 1].Name) from the blacklist file."
                }   
            }
        }
    }
    'a' {
        $optionsList = $unknownVer + $noList
        if ( !$optionsList ) {
            Write-Verbose "`rThere are no excluded packages"
        } else {
            $hostArray = Get-IntAnswer -options $optionsList.Name
            if ( $hostArray -notin @('q', $false ) ) {
                foreach ( $k in $hostArray ) {
                    $okList += @($optionsList[$k - 1])
                    Write-Verbose "`rAdded $($optionsList[$k - 1].Name) to this upgrade queue."
                }
            }
        }
    }
    's' {
        $optionsList = $okList
        if ( !$optionsList ) {
            Write-Verbose "`rThere are no upgradeable packages"
        } else {
            $hostArray = Get-IntAnswer -options $optionsList.Name
            if ( $hostArray -notin @('q', $false ) ) {
                foreach ( $k in $hostArray ) {
                    $okList = $oklist | Where-Object {$_ -notin @($optionsList[$k - 1])}
                    if ( $null -eq $okList) { $okList = @() }
                    Write-Verbose "`rRemoved $($optionsList[$k - 1].Name) from this upgrade queue."
                }
            }    
        }
    }
    'c' {
        $optionsList = $Script:upgradeList
        $hostArray = Get-IntAnswer -options $optionsList.Name
        if ( $hostArray -notin @('q', $false ) ) {
            $okList = @()
            foreach ($k in $hostArray) {
                $okList += $optionsList[$k - 1]
            }
            $Script:okListS = $okList
            break
        }
    }
    { $_ -in 'b', 'w', 'a', 's', 'c'} { 
        if ( $hostArray -notin @('q', $false ) ) { Get-Answer -Delay 20 | Out-Null }
        $Script:okListS = $okList
        Show-UI -okList $okList -noList $noList -unknownVer $unknownVer
    }
    <#
    'r' {

    }
    #>
}
}
#endregion FUNCTIONS SPECIFIED FOR THE SCRIPT
#endregion FUNCTIONS

#region STARTUP
$scriptInfo = Test-ScriptFileInfo -LiteralPath $MyInvocation.MyCommand.Path
$powershellgalleryName = $scriptInfo.Name
$scriptInfo.Name = 'PS Wizget'
$maxWidth = 100
$host.UI.RawUI.BufferSize.Width = $maxWidth;  $host.UI.RawUI.WindowSize.Width = $maxWidth
if ($host.UI.RawUI.BufferSize.Width -lt $maxWidth) {
    $maxWidth = $host.UI.RawUI.BufferSize.Width 
}

$initialSetup = [PSCustomObject]@{
    WindowTitle              = $host.UI.RawUI.WindowTitle
    VerbosePreference        = $VerbosePreference
    InformationPreference    = $InformationPreference
}

$host.UI.RawUI.WindowTitle = $scriptInfo.Name
if (!$quick) {
    $VerbosePreference = 'Continue'
    $InformationPreference = 'Continue'
}
#endregion STARTUP

#region PARAMETERS VALIDATION
if ( $waitingTime -lt 0 ) { Write-Error "Waiting time lesser than 0" }

# idleAnimation test

if ($idleAnimation){
    try {
        $frames = Get-ChildItem -Path $idleAnimation[0] -ErrorAction SilentlyContinue
    }
    catch {
        Write-Information 'Provided string as idleAnimation' -InformationAction SilentlyContinue
    }
    $Colors = [enum]::GetValues([System.ConsoleColor])
    if ($idleAnimation[1] -eq "Random") {
        $idleAnimation[1] = Get-Random -InputObject $Colors
    }
    if ($idleAnimation[2] -eq "Random") {
        $idleAnimation[2] = Get-Random -InputObject $Colors
    }
} 
if ( !$PSBoundParameters.idleSpeed ) { $PSBoundParameters.idleSpeed = 1 }

# create and read files from profile directory
$invalidChar = '[^"<>*|?:]'
$test = "^"+$invalidChar+"+$"
if ( $wizgetFolderPath -notmatch $test ) {
    Write-Error 'The passed string is not a location!'
    Reset-Setup
    Exit 102   
}

if ( $wizgetFolderPath[-1] -notin @( "\", "/" )) {
    $wizgetFolderPath = "$($wizgetFolderPath)\"
}
$wizgetFolderPath = $wizgetFolderPath -replace '/', "\"


if ( !(Test-Path -Path $wizgetFolderPath) ) {
    try {
        Write-Information "A wizget folder has been created in:" -InformationAction Continue
        New-Item -ItemType Directory -Path "$($wizgetFolderPath)Manifests" -ErrorAction Stop
    }
    catch {
        Write-Error "The wizget folder could not be created. Make sure that you $(
            )have a read/write permissions to the target path"
        Reset-Setup
        Exit 105
    }
    # BUG 01 an additional line is created after the Clear-Host call. 
    # This is somehow related to the New-Item function.
    $extraLine = $true 
}

$blacklistPath = "$($wizgetFolderPath)blacklist.txt"

if ( !(Test-Path -Path $blacklistPath) ) {
    try {
        "" | Out-File -LiteralPath $blacklistPath -ErrorAction Stop
        Write-Information "A blacklist file has been created in:" -InformationAction Continue
        Write-Information $blacklistPath
    } catch {
        Write-Error "The blacklist file could not be created. Make sure that you $(
        )have a read/write permissions to the target folder"
        Reset-Setup
        Exit 106
    }
    Write-Information "$(Resolve-Path -path $blacklistPath)" -InformationAction SilentlyContinue
    Write-Information ""
    Write-Information "Add the IDs of packages with a different format for 'version' and $(
            )'available version' to this file."
    If (!$quick) {Read-Host | Out-Null}
} else {
    #test blacklist file
    try{
        [string[]]$toSkip = Get-Content $blacklistPath -TotalCount 1 -ErrorAction Stop
        Add-Content -path $blacklistPath -Value "" -ErrorAction Stop
    } catch {
        Write-Error "The blacklist file could not be accessed. Make sure that it $(
        )is a valid text file with read/write permissions and is not being used by any process."
        Reset-Setup
        Exit 107
    }
    if ( $null -ne $toSkip ) {
        $invalidChar = $invalidChar.TrimEnd("]")+"\\/.]"
        $test = '^'+$invalidChar+'+\.'+$invalidChar+'+$'
        if ( $toSkip[0] -match $test -or $toSkip[0] -eq "") {
            [string[]]$toSkip = Get-Content $Script:blacklistPath
            $toSkip | ForEach-Object -Begin {$i=0} -Process{
                if ( $_ -notmatch $test -and $_ -ne "" ) {
                    Write-Error "The blacklist have an invalid record (No. $($i+1))."
                    Reset-Setup
                    Exit 108
                }
                $i++
            }   
        } else {
            Write-Error "It seems the blacklist contains invalid records."
            Reset-Setup
            Exit 109
        }
        [string[]]$toSkip = Get-Content $blacklistPath
    }
}
#endregion PARAMETERS VALIDATION

#region REQUIREMENTS TEST
# winget test
$wingetExist = test-path -path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\winget.exe"
if ( !$wingetExist ) {
    Write-Verbose "`rFirst please install winget from msstore"
    Reset-Setup
    Exit 101
}

# encoding test
if( $OutputEncoding.WindowsCodePage -ne 1200 ) {
    Write-Warning "`rYour Powershell encoding is not utf8. Packages with longer names than 30 chars $(
               )may corrupt the 'winget upgrade' result."
    Write-Information "Powershell encoding : $($OutputEncoding.HeaderName)"
} 

Write-Information 'Please wait...'
#internet connection test
$oldProgressPreference = $Global:ProgressPreference
$Global:ProgressPreference = 'SilentlyContinue'
if (!$omitNetTest){
    Write-Verbose "`rTesting connection...         "
    if (!$quick) {[Console]::SetCursorPosition(0,($host.UI.RawUI.CursorPosition.Y-1))}
    if ( !( Test-NetConnection -InformationLevel Quiet)) {
        Write-Verbose "`rNo internet connection.       "
        Reset-Setup
        Exit 110
    }
}
$Global:ProgressPreference = $oldProgressPreference
#endregion REQUIREMENTS TEST

Write-Verbose "`rConnected. Fetching from 'winget upgrade'..."
if (!$quick) {[Console]::SetCursorPosition(0,($host.UI.RawUI.CursorPosition.Y-1))}

#region FETCHING UPGRADEABLE PACKAGES
#       FROM WINGET TO COLLECTION OF OBJECT
#It's not mine code in this region. I found it on stackoverflow some time ago but can't find it now.
#Temporory no author, no link

$upgradeResult = winget upgrade --include-unknown | Out-String

# my fix to this code
$upgradeResult = $upgradeResult -replace 'ÔÇŽ', ' '

$lines = $upgradeResult.Split("`n")

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

$webclient = New-Object System.Net.WebClient
Write-Verbose "`rFetching release notes for packages...      "
for ($i = $fl + 1; $i -le $lines.Count; $i++) {
    $line = $lines[$i]
    if ($line.Length -gt ($availableStart + 1) -and -not $line.StartsWith('-')) {
        $name = $line.Substring(0, $idStart).TrimEnd()
        $id = $line.Substring($idStart, $versionStart - $idStart).TrimEnd()
        $version = $line.Substring($versionStart, $availableStart - $versionStart).TrimEnd()
        $available = $line.Substring($availableStart, $sourceStart - $availableStart).TrimEnd()
        #if ( Test-Path -LiteralPath "$($wizgetFolderPath)Manifests\$($id)_[$($available)].yaml" ) {
        $idSplit = $id -split "\."
        $manifestURL = "https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests/"+
            $id[0].ToString().ToLower()+"/"+$idSplit[0]+"/"+$idSplit[1]+"/"+$available+"/"+$id+".locale.en-US.yaml"
        try {
            $manifest = Get-Content -LiteralPath "$($wizgetFolderPath)Manifests\$($id)_$($available).yaml" -ErrorAction Stop
        } catch {
            $manifest = $($webclient.DownloadString($manifestURL))
            $manifest | Out-File -LiteralPath "$($wizgetFolderPath)Manifests\$($id)_$($available).yaml"
            $manifest = $manifest.split("`n")
        }
        try{
            $startLine = $($manifest | Select-String -Pattern '^\s*ReleaseNotes:')[0].LineNumber-1
            $endLine = $($manifest | Select-String -Pattern '^\s*(ReleaseNotesURL:)|(ManifestType:)')[0].LineNumber-2
            $releaseNotes = $manifest[$startLine..$endLine]
        } catch { $releaseNotes = @("") }
        try {
            $releaseNotesURL = $($manifest | Select-String -Pattern '^\s*ReleaseNotesURL:.*$')[0]
        } catch { $releaseNotesURL = @("") }
        
        if ( !$releaseNotes ) { $releaseNotes = @("") }
        if ( !$releaseNotesURL ) { $releaseNotesURL = @("") }

        $software = [PSCustomObject]@{
            Name              = $name
            Id                = $id
            Version           = $version
            AvailableVersion  = $available
            ManifestURL       = $manifestURL
            ReleaseNotes      = $releaseNotes
            ReleaseNotesURL   = $releaseNotesURL
        }
    
        $upgradeList += $software
    }
}
#endregion FETCHING UPGRADEABLE PACKAGES

<# Dummy Package
$dummySoftware = [PSCustomObject]@{
    Name              = "Dummy Package"
    Id                = "Dummy.Package"
    Version           = "1.0.5"
    AvailableVersion  = "1.0.4.32"
    ReleaseNotes      = ""
    ReleaseNotesURL   = ""
}

$upgradeList += $dummySoftware
#>

#region POSTPROCESSING WINGET UPGRAGE RESULT      
$upgradeList = $upgradeList | Sort-Object -Property Id -Unique
If ( !$upgradeList ) {
    Write-Information "There are no packages to upgrade." -InformationAction Continue
    Reset-Setup
    Exit
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

#region FETCHING AVAILABLE VERSION FOR WIZGET

$updateMarker = Get-ChildItem -Path "$($wizgetFolderPath)updateMarker" -ErrorAction SilentlyContinue
if ( $updateMarker ) {
    if ( $updateMarker.CreationTime -ge (Get-Date).AddDays(-7)) {
        $timeToCheckForUpdate = $true
    }
} else {
    $timeToCheckForUpdate = $true
}

if ( $timeToCheckForUpdate ) {    
    $wizgetNewVersion = $(Find-Script $powershellgalleryName).Version
    try {
        "" | Out-File -FilePath "$($wizgetFolderPath)updateMarker" -ErrorAction SilentlyContinue
    } catch {
        Write-Error "The updateMarker could not be created. Make sure that you $(
        )have a read/write permissions to the target folder"
        Reset-Setup
        Exit 106
    }
} else {
    $wizgetNewVersion = ""
}

$WizgetInfo = [PSCustomObject]@{
    Name              = "`e[93m$($scriptInfo.Name)"
    Id                = ""
    Version           = $scriptInfo.Version
    AvailableVersion  = $wizgetNewVersion
    ReleaseNotes      = $scriptInfo.ReleaseNotes
    ReleaseNotesURL   = ""
}

if ($(@($WizgetInfo.Version,  $WizgetInfo.AvailableVersion) | Sort-Object -Descending)[0] `
   -ne $WizgetInfo.Version) {
    $timeForUpdate = $true
}

#endregion FETCHING AVAILABLE VERSION FOR WIZGET

#region PREPARING MESSAGES ABOUT PACKAGES STATUSES
$unknownVerMessage = "recognized incorrectly (installed version info)."
$noListMessage = "listed in the blacklist file."
$okListMessage = "going to be updated."
$emptyListMessage = "There are no packages to upgrade."
#endregion PREPARING MESSAGES ABOUT PACKAGES STATUSES

#region UI

$okListS, $noListS, $unknownVerS = Split-Result

if ( !$quick ) {
    Show-UI -okList $okListS -noList $noListS -unknownVer $unknownVerS
}
#endregion UI

#region UPGRADE A BATCH OF PACKAGES
Write-PackagesStatus -namesArray $okListS.Name -secondHalf $okListMessage -emptyMessage $emptyListMessage

if ( $oklistS.Count -gt 0) {
    Write-Information ''
    if ( !$quick ){
         $abort = Read-Host '[ Enter ] to continue, [ Q ] to abort' 
    } else { $abort = $false }
    if ( $abort -ne 'q' ) {
        foreach ($package in $okListS) {
            $winget = "winget upgrade" + " " + $package.Id + " " + $wingetParam
            $host.UI.RawUI.WindowTitle = "PS Wizget: Updating " + $package.Name
            Write-Separator -length 55
            Write-Host "Updating the $($package.Name) application." -ForegroundColor Yellow
            & Invoke-Expression $winget
        }
        Write-Separator -length 55
        Write-Information "All updates completed" -InformationAction Continue
    }
}

Reset-Setup
#endregion UPGRADE A BATCH OF PACKAGES
}
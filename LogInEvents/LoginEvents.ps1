Function Get-LastLoginInfo {
#requires -RunAsAdministrator
<#
.Synopsis
    This will get a Information on the last users who logged into a machine.
    More info can be found: https://docs.microsoft.com/en-us/windows/security/threat-protection/auditing/basic-audit-logon-events
 
 
.NOTES
    Name: Get-LastLoginInfo
    Author: theSysadminChannel
    Version: 1.0
    DateCreated: 2020-Nov-27
 
 
.EXAMPLE
    Get-LastLoginInfo -ComputerName Server01, Server02, PC03 -SamAccountName username
 
.LINK
    https://thesysadminchannel.com/get-computer-last-login-information-using-powershell -
#>
 
 
    [CmdletBinding(DefaultParameterSetName="Default")]
    param(
        [Parameter(
            Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0
        )]
        [string[]]  $ComputerName = $env:COMPUTERNAME,
 
 
        [Parameter(
            Position = 1,
            Mandatory = $false,
            ParameterSetName = "Include"
        )]
        [string]    $SamAccountName,
 
 
        [Parameter(
            Position = 1,
            Mandatory = $false,
            ParameterSetName = "Exclude"
        )]
        [string]    $ExcludeSamAccountName,
 
 
        [Parameter(
            Mandatory = $false
        )]
        [ValidateSet("SuccessfulLogin", "FailedLogin", "Logoff", "DisconnectFromRDP")]
        [string]    $LoginEvent = "SuccessfulLogin",
 
 
        [Parameter(
            Mandatory = $false
        )]
        [int]       $DaysFromToday = 3,
 
 
        [Parameter(
            Mandatory = $false
        )]
        [int]       $MaxEvents = 1024,
 
 
        [System.Management.Automation.PSCredential]
        $Credential
    )
 
 
    BEGIN {
        $StartDate = (Get-Date).AddDays(-$DaysFromToday)
        Switch ($LoginEvent) {
            SuccessfulLogin   {$EventID = 4624}
            FailedLogin       {$EventID = 4625}
            Logoff            {$EventID = 4647}
            DisconnectFromRDP {$EventID = 4779}
        }
    }
 
    PROCESS {
        foreach ($Computer in $ComputerName) {
            try {
                $Computer = $Computer.ToUpper()
                $Time = "{0:F0}" -f (New-TimeSpan -Start $StartDate -End (Get-Date) | Select -ExpandProperty TotalMilliseconds) -as [int64]
 
                if ($PSBoundParameters.ContainsKey("SamAccountName")) {
                    $EventData = "
                        *[EventData[
                                Data[@Name='TargetUserName'] != 'SYSTEM' and
                                Data[@Name='TargetUserName'] != '$($Computer)$' and
                                Data[@Name='TargetUserName'] = '$($SamAccountName)'
                            ]
                        ]
                    "
                }
 
                if ($PSBoundParameters.ContainsKey("ExcludeSamAccountName")) {
                    $EventData = "
                        *[EventData[
                                Data[@Name='TargetUserName'] != 'SYSTEM' and
                                Data[@Name='TargetUserName'] != '$($Computer)$' and
                                Data[@Name='TargetUserName'] != '$($ExcludeSamAccountName)'
                            ]
                        ]
                    "
                }
 
                if ((-not $PSBoundParameters.ContainsKey("SamAccountName")) -and (-not $PSBoundParameters.ContainsKey("ExcludeSamAccountName"))) {
                    $EventData = "
                        *[EventData[
                                Data[@Name='TargetUserName'] != 'SYSTEM' and
                                Data[@Name='TargetUserName'] != '$($Computer)$'
                            ]
                        ]
                    "
                }
 
                $Filter = @"
                    <QueryList>
                        <Query Id="0">
                            <Select Path="Security">
                            *[System[
                                    Provider[@Name='Microsoft-Windows-Security-Auditing'] and
                                    EventID=$EventID and
                                    TimeCreated[timediff(@SystemTime) &lt;= $($Time)]
                                ]
                            ]
                            and
                                $EventData
                            </Select>
                        </Query>
                    </QueryList>
"@
 
                if ($PSBoundParameters.ContainsKey("Credential")) {
                    $EventLogList = Get-WinEvent -ComputerName $Computer -FilterXml $Filter -Credential $Credential -ErrorAction Stop
                  } else {
                    $EventLogList = Get-WinEvent -ComputerName $Computer -FilterXml $Filter -ErrorAction Stop
                }
 
 
                $Output = foreach ($Log in $EventLogList) {
                    #Removing seconds and milliseconds from timestamp as this is allow duplicate entries to be displayed
                    $TimeStamp = $Log.timeCReated.ToString('MM/dd/yyyy hh:mm tt') -as [DateTime]
 
                    switch ($Log.Properties[8].Value) {
                        2  {$LoginType = 'Interactive'}
                        3  {$LoginType = 'Network'}
                        4  {$LoginType = 'Batch'}
                        5  {$LoginType = 'Service'}
                        7  {$LoginType = 'Unlock'}
                        8  {$LoginType = 'NetworkCleartext'}
                        9  {$LoginType = 'NewCredentials'}
                        10 {$LoginType = 'RemoteInteractive'}
                        11 {$LoginType = 'CachedInteractive'}
                    }
 
                    if ($LoginEvent -eq 'FailedLogin') {
                        $LoginType = 'FailedLogin'
                    }
 
                    if ($LoginEvent -eq 'DisconnectFromRDP') {
                        $LoginType = 'DisconnectFromRDP'
                    }
 
                    if ($LoginEvent -eq 'Logoff') {
                        $LoginType = 'Logoff'
                        $UserName = $Log.Properties[1].Value.toLower()
                    } else {
                        $UserName = $Log.Properties[5].Value.toLower()
                    }
 
 
                    [PSCustomObject]@{
                        ComputerName = $Computer
                        TimeStamp    = $TimeStamp
                        UserName     = $UserName
                        LoginType    = $LoginType
                    }
                }
 
                #Because of duplicate items, we'll append another select object to grab only unique objects
                $Output | select ComputerName, TimeStamp, UserName, LoginType -Unique | select -First $MaxEvents
 
            } catch {
                Write-Error $_.Exception.Message
 
            }
        }
    }
 
    END {}
}
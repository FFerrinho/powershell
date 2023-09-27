#requires -version 2

<#
    .SYNOPSIS
    Manage de state of THESEUS nodes on F5.
    .DESCRIPTION
    Enables controled actions such as website deploys. This script will validate the number of servers per DC, keeping least three servers online. Nevertheless, there will be an option to force the continuation of the script, for cases when it's still a controled action with less online servers.
    The script will also keep a snapshot of the present activation state, so when activating again (after disabling) it'll keep the FRONTs as they were, enabled or disabled/offline.
    .PARAMETER DisableGroup
    Append the Group number to the end of the parameter, according to which Group you want to disable. For example, to disable Group 1: F5Management.ps1 DisableGroup1        
    .PARAMETER GetConnectionsGroup
    Append the Group number to the end of the parameter, according to which Group you want to get the connection count. For example, for Group 1: F5Management.ps1 GetConnectionsGroup1
    .PARAMETER EnableGroup
    Append the Group number to the end of the parameter, according to which Group you want to enable. For example, for Group 1: F5Management.ps1 EnableGroup1
    .OUTPUTS
    N/A
    .NOTES
    Version:        1.2
    Author:         Francisco Ferrinho
    Creation Date:  2016/11/21
    Purpose/Change: Project THESEUS
    .CHANGELOG
    v1.2
    Added new servers to the groups and configured validations to accept the mixed names (DC and FR)
  
    .EXAMPLE
    Disable Group from F5
    F5Management.ps1 DisableGroup1(2/3/4)
    Get the connections count
    F5Management.ps1 GetConnectionsGroup1(2/3/4)
    Enable Grup on F5
    F5Management.ps1 EnableGroup1(2/3/4)
    
    .ATTENTION
    CHANGE THE USER AND PASSWORD FOR F5  
#>

# ------------------------------------------------------------------------------------
# Variables
param ([Parameter(Mandatory=$true)]
  [ValidateNotNullOrEmpty()]
$Group)
Set-Location 'C:\PS Scripts' # The location from which the script will run and store files
$userlog=$Credentials.username
$TimeStamp=Get-Date -Format yyyyMMdd_HHmmss
$User_Passwd=convertto-securestring -String 'CHANGE_ME' -AsPlainText -Force
$User=new-object -typename System.Management.Automation.PSCredential -argumentlist 'CHANGE_ME',$User_Passwd
#$User=Get-Credential
Add-PSSnapin iControlSnapIn
$F5FR1='172.25.200.172', '172.25.200.138'
$F5FR2='172.25.200.203', '172.25.200.176'
$Group1='LRSDC1THFRONT15', 'LRSDC1THFRONT17', 'LRSDC1THFRONT19', 'LRSDC1THFRONT21', 'LRSFR1THFRONT01', 'LRSFR1THFRONT03', 'LRSFR1THFRONT05', 'LRSFR1THFRONT07'
$Group3='LRSDC1THFRONT23', 'LRSDC1THFRONT25', 'LRSDC1THFRONT27', 'LRSDC1THFRONT29', 'LRSFR1THFRONT09', 'LRSFR1THFRONT11', 'LRSFR1THFRONT13', 'LRSFR1THFRONT15'
$Group2='LRSDC2THFRONT12', 'LRSDC2THFRONT14', 'LRSDC2THFRONT16', 'LRSDC2THFRONT18', 'LRSFR2THFRONT02', 'LRSFR2THFRONT04', 'LRSFR2THFRONT06', 'LRSFR2THFRONT08'
$Group4='LRSDC2THFRONT20', 'LRSDC2THFRONT22', 'LRSDC2THFRONT24', 'LRSDC2THFRONT26', 'LRSFR2THFRONT10', 'LRSFR2THFRONT12', 'LRSFR2THFRONT14', 'LRSFR2THFRONT16'
# ------------------------------------------------------------------------------------
# Code to bypass HTTPS issues, this is valid only for each script session, so won't change host security configurations
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    
    public class IDontCarePolicy : ICertificatePolicy {
        public IDontCarePolicy() {}
        public bool CheckValidationResult(
            ServicePoint sPoint, X509Certificate cert,
            WebRequest wRequest, int certProb) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = new-object IDontCarePolicy 
# ------------------------------------------------------------------------------------
# Functions needed for this script
function Validate-Population
# Function to validate if there are enough active Nodes prior to disabling a FRONT Group. This also stores an image of the active/disabled state for later reference.
{
  param
  ([Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
  $WorkingGroup,$Group,$F5)
  Check-ActiveF5 $F5
  Get-ChildItem .\FrontState*.txt | Remove-Item
  $script:NodeState=@()
  foreach ($Member in $Group)
  {
    # Code to validate if the number of active Nodes allows the removal of additional Nodes
    Initialize-F5.iControl -HostName $ActiveF5 -Credentials $User | Out-Null
    $NodeIP=[System.Net.Dns]::GetHostAddresses($Member) | foreach {Write-Output $_.IPAddressToString }
    $script:NodeState+=Get-F5.LTMNodeAddress -Node $NodeIP | Where-Object -Property Enabled -NotMatch 'DISABLED' | Select-Object -ExpandProperty Name
  }
  # Write the the WorkingGroup enabled/disabled state to a text file so the Data can be later obtained in another script iteration
  if ($Member -contains ($Member | Select-String -Pattern 'DC1'))
  {
    foreach ($Item in $WorkingGroup)
    {
      $WorkingNodeIP=[System.Net.Dns]::GetHostAddresses($Item) | foreach {Write-Output $_.IPAddressToString }
      $WorkingNodeState=Get-F5.LTMNodeAddress -Node $WorkingNodeIP | Where-Object -Property Enabled -NotMatch 'DISABLED' | Select-Object -ExpandProperty Name
      $WorkingNodeState | Out-File .\FrontStateFR1.txt -Append
    }
  }
  elseif ($Member -contains ($Member | Select-String -Pattern 'FR1'))
  {
    foreach ($Item in $WorkingGroup)
    {
      $WorkingNodeIP=[System.Net.Dns]::GetHostAddresses($Item) | foreach {Write-Output $_.IPAddressToString }
      $WorkingNodeState=Get-F5.LTMNodeAddress -Node $WorkingNodeIP | Where-Object -Property Enabled -NotMatch 'DISABLED' | Select-Object -ExpandProperty Name
      $WorkingNodeState | Out-File .\FrontStateFR1.txt -Append
    }
  }
  else 
  {
    foreach ($Item in $WorkingGroup)
    {
      $WorkingNodeIP=[System.Net.Dns]::GetHostAddresses($Item) | foreach {Write-Output $_.IPAddressToString }
      $WorkingNodeState=Get-F5.LTMNodeAddress -Node $WorkingNodeIP | Where-Object -Property Enabled -NotMatch 'DISABLED' | Select-Object -ExpandProperty Name
      $WorkingNodeState | Out-File .\FrontStateFR2.txt -Append
    }
  }
}
# ------------------------------------------------------------------------------------
function Change-NodeState
# Function to change Node states (enable, disable or forceoffline)
{
  param
  ([Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
  $Group,$state,$F5)
  Initialize-F5.iControl -HostName $ActiveF5 -Credentials $User | Out-Null # Initialize session on the Active F5
  foreach ($Member in $Group)
  {
    $NodeIP=[System.Net.Dns]::GetHostAddresses($Member) | foreach {Write-Output $_.IPAddressToString }
    if ($State -eq 'enable')
    {
      (Get-F5.iControl).LocalLBNodeAddress.set_session_enabled_state( (,$NodeIP), (,'STATE_ENABLED'))
      (Get-F5.iControl).LocalLBNodeAddress.set_monitor_state( (,$NodeIP), (,'STATE_ENABLED'))
    }
    elseif ($State -eq 'disable')
    {
      (Get-F5.iControl).LocalLBNodeAddress.set_session_enabled_state( (,$NodeIP), (,'STATE_DISABLED'))
    }
    elseif ($state -eq 'forceoffline')
    {
      (Get-F5.iControl).LocalLBNodeAddress.set_session_enabled_state( (,$NodeIP), (,'STATE_DISABLED'))
      (Get-F5.iControl).LocalLBNodeAddress.set_monitor_state( (,$NodeIP), (,'STATE_DISABLED'))
    }
  }
  
}
# ------------------------------------------------------------------------------------
function Enable-Node
# Function to enable a Node according to the Group previous state (as stored with Validate-Population)
{
  param
  ([Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
  $Group,$F5)
  Check-ActiveF5 $F5
  if ($Group -match 'DC1' -and 'FR1')
  {
    $Data=Get-Content .\FrontStateFR1.txt -ErrorAction SilentlyContinue
  }
  else
  {
    $Data=Get-Content .\FrontStateFR2.txt -ErrorAction SilentlyContinue
  }
  $NodeIPMatch=@()
  foreach ($Node in $Group)
  {
    $NodeIPMatch+=([System.Net.Dns]::GetHostAddresses($Node)).IPAddressToString
  }
  $Compare=$NodeIPMatch | Select-String -Pattern $Data
  if ($Compare.Count -ge '1') # Validation to ensure that the file contents are equal to the desired Group to enable
  {
    Initialize-F5.iControl -HostName $ActiveF5 -Credentials $User | Out-Null
    foreach ($Item in $Data)
    {
      Change-NodeState $Item 'enable'
      Write-Host 'Node' $Item "is now set according to it`'s previous state."
      Start-Sleep -Seconds 5
    }
  }
  else
  {
    Write-Host "Requested Group to enable doesn't match with the Group stored, please verify if you are enabling the previously disabled group."
  }
}
# ------------------------------------------------------------------------------------
function Check-ActiveF5
# This function will check which F5 is active and create the $ActiveF5 variable that will be used for the rest of the functions
{
  param
  ([Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
  $F5)
  foreach ($Item in $F5)
  {
    Initialize-F5.iControl -HostName $Item -Credentials $User | Out-Null
    if (((Get-F5.iControl).ManagementDBVariable.get_list() | Where-Object -Property Name -eq 'Failover.State' | Select-Object -ExpandProperty value) -eq 'active')
    {
      $script:ActiveF5=$Item
    }
  }
}
# ------------------------------------------------------------------------------------
function Get-NodeConnections
# This function serves to Loop until the connections don't reach the specified threshold
{param ($Group,$F5)
  Check-ActiveF5 $F5
  foreach ($Node in $Group)
  {
    do {
      Initialize-F5.iControl -HostName $ActiveF5 -Credentials $User | Out-Null # Initialize session on the Active F5
      $NodeIP=[System.Net.Dns]::GetHostAddresses($Node) | foreach {Write-Output $_.IPAddressToString }
      $connections=Get-F5.iControl
      $Loop=$connections.LocalLBNodeAddress.get_statistics($NodeIP) | %{$_.statistics.statistics | Where-Object {$_.type -eq 'STATISTIC_SERVER_SIDE_CURRENT_CONNECTIONS'} | %{$_.value.low} }
      Write-Host 'Node' $Node 'still has' $Loop 'active connections, looping until SLA (20) is reached...'
      Start-Sleep -Seconds 15
    } # Get the Nodes active connections 
    until(
      ($connections.LocalLBNodeAddress.get_statistics($NodeIP) | %{$_.statistics.statistics | Where-Object {$_.type -eq 'STATISTIC_SERVER_SIDE_CURRENT_CONNECTIONS'} | %{$_.value.low}}) -le '20'
    )
  }
}
# ------------------------------------------------------------------------------------
function Bypass-Population
# Function to allow proceeding with the disabling of a group, even if the Validate-Population threshold wasn't met
{param ($Group)
  Write-Host "There aren`'t enough active Members for $Group, please verify if you really want to proceed and check manually on F5 management page."
  $answer=Read-Host 'If you are sure you want to proceed enter YES. Otherwise enter NO to exit and restart the procedure after validation'
  if ($answer -eq 'YES')
  {
    Add-Content Bypass-Population.log "$userlog bypassed population validation in $timestamp"
    Write-Host 'Population count validated bypassed, disabling Group 1...'
    Check-ActiveF5 $F5FR1
    Change-NodeState $Group 'forceoffline' $ActiveF5
    Write-Host 'Nodes disabled for Group 1.'
  }
  else
  {
    Write-Host 'Aborting script, please validate and restart the deploy from the group where you stopped'
    Exit
  }
  

}
# ------------------------------------------------------------------------------------
# Switch to accept the input parameter and execute the actions accordingly
Switch($Group)
{
  DisableGroup1 {
    Write-Host 'Executing validations to disable Group 1...'
    Validate-Population $Group1 $Group3 $F5FR1
    if ($NodeState.Count -ge 3)
    {
      Write-Host 'Population count validated, disabling Group 1...'
      Check-ActiveF5 $F5FR1
      Change-NodeState $Group1 'forceoffline' $ActiveF5
      Write-Host 'Nodes disabled for Group 1.'
    }
    Else
    {
      Bypass-Population $Group
    }
  }
  ForceDisableGroup1 {
    Add-Content Bypass-Population.log "$userlog bypassed population validation in $timestamp for Group 1"
    Write-Host 'Bypassing validations and disabling Group 1...'

    Check-ActiveF5 $F5FR1
    Change-NodeState $Group1 'forceoffline' $ActiveF5
    Write-Host 'Nodes disabled for Group 1.'
  }
  DisableGroup2 {
    Write-Host 'Executing validations to disable Group 2...'
    Write-Host 'Validating active population'
    Validate-Population $Group2 $Group4 $F5FR2
    if ($NodeState.Count -ge 3)
    {
      Write-Host 'Population count validated, disabling Group 2...'
      Check-ActiveF5 $F5FR2
      Change-NodeState $Group2 'forceoffline' $ActiveF5
      Write-Host 'Nodes disabled for Group 2.'
    }
    Else
    {
      Bypass-Population
    }
  }
  ForceDisableGroup2 {
    Add-Content Bypass-Population.log "$userlog bypassed population validation in $timestamp for Group 2"
    Write-Host 'Bypassing validations and disabling Group 2...'

    Check-ActiveF5 $F5FR2
    Change-NodeState $Group2 'forceoffline' $ActiveF5
    Write-Host 'Nodes disabled for Group 2.'
  }
  DisableGroup3 {
    Write-Host 'Executing validations to disable Group 3...'
    Validate-Population $Group3 $Group1 $F5FR1
    if ($NodeState.Count -ge 3)
    {
      Write-Host 'Population count validated, disabling Group 3...'
      Check-ActiveF5 $F5FR1
      Change-NodeState $Group3 'forceoffline' $ActiveF5
      Write-Host 'Nodes disabled for Group 3.'
    }
    Else
    {
      Bypass-Population
    }
  }
  ForceDisableGroup3 {
    Add-Content Bypass-Population.log "$userlog bypassed population validation in $timestamp for Group 3"
    Write-Host 'Bypassing validations and disabling Group 1...'

    Check-ActiveF5 $F5FR1
    Change-NodeState $Group3 'forceoffline' $ActiveF5
    Write-Host 'Nodes disabled for Group 1.'
  }
  DisableGroup4 {
    Write-Host 'Executing validations to disable Group 4...'
    Validate-Population $Group4 $Group2 $F5FR2
    if ($NodeState.Count -ge 3)
    {
      Write-Host 'Population count validated, disabling Group 4...'
      Check-ActiveF5 $F5FR2
      Change-NodeState $Group4 'forceoffline' $ActiveF5
      Write-Host 'Nodes disabled for Group 4.'
    }
    Else
    {
      Bypass-Population
    }
  }
  ForceDisableGroup4 {
    Add-Content Bypass-Population.log "$userlog bypassed population validation in $timestamp for Group 4"
    Write-Host 'Bypassing validations and disabling Group 1...'

    Check-ActiveF5 $F5FR2
    Change-NodeState $Group4 'forceoffline' $ActiveF5
    Write-Host 'Nodes disabled for Group 1.'
  }
  # ------------------------------------------------------------------------------------
  EnableGroup1 {
    Enable-Node $Group1 $F5FR1
  }
  EnableGroup2 {
    Enable-Node $Group2 $F5FR2
  }
  EnableGroup3 {
    Enable-Node $Group3 $F5FR1
  }
  EnableGroup4 {
    Enable-Node $Group4 $F5FR2
  }
  # ------------------------------------------------------------------------------------
  GetConnectionsGroup1 {
    Get-NodeConnections $Group1 $F5FR1
    exit 1
  }
  GetConnectionsGroup2 {
    Get-NodeConnections $Group2 $F5FR2
    exit 1
  }
  GetConnectionsGroup3 {
    Get-NodeConnections $Group3 $F5FR1
    exit 1
  }
  GetConnectionsGroup4 {
    Get-NodeConnections $Group4 $F5FR2
    exit 1
  }
}
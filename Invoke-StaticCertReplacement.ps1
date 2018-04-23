﻿<#
.SYNOPSIS
   Transfers Certificates to each ESXi host

.DESCRIPTION
    Leveraging the .NET assembly for WinSCP, this script will loop through an array of vCenter servers, 
    performing the transfer of files on each ESXi host under the control of its respective vCenter

.INPUTS
    None

.OUTPUTS
    None

.NOTES
    Author(s): Ricky Nelson, Troy Bailey, Josh Hart, Allen Parsons, Jeff Peters 
    Date: 20171031
   
.EXAMPLE
    .\script_name.ps1
    without parameters

#>

# Static parameters
$baseCertPath = "\\server\pathtocerts\"
$CAStorePath = "\\server\rootserverPath\castore.pem"


# get script directory and remote paths
$scriptdir = split-path $script:myinvocation.MyCommand.Path
$remotePath = "/etc/vmware/ssl/"

# Adds WinSCP functionality to PowerShell
Add-Type -Path "$scriptdir\Resources\WinSCP\WinSCPnet.dll"
if(!$vcred){
    $vcred = Get-Credential -Message "Enter local login information for ESXi Host"
}

#gets all vmhosts
$vmhosts = import-csv -Path "$scriptdir\Resources\static.csv"

foreach($v in $vmhosts){
    Connect-VIServer -Server $v.name -Credential $vcred
    Get-VMHostService -VMHost $v.name | Where-Object {$_.label -eq "ssh"} | Start-VMHostService
    Disconnect-VIServer -Server $v.name -Confirm:$false
    #local path - recursive
    ##### If your cert has no domain suffix, remove this from the following two lines + $v.Name.TrimEnd(".domain.com"): 
    $localFiles1 = $baseCertPath + $v.Name.TrimEnd(".domain.com") + "\"+ "rui.crt"
    $localFiles2 = $baseCertPath + $v.Name.TrimEnd(".domain.com") + "\"+ "rui.key"


   # Enable SHHHH on all hosts
   Get-VMHostService -VMHost $v.name | Where-Object {$_.label -eq "ssh"} | Start-VMHostService
    # Specify WinSCP session and transfer parameters
    $winSCPSession = New-Object WinSCP.SessionOptions -Property @{
        HostName = $v.name;
        GiveUpSecurityAndAcceptAnySshHostKey = $true;
        PortNumber = '22';
        SecurePassword = $vcred.Password;
        UserName = $vcred.UserName
    }
    $winSCPSession.Protocol = [WinSCP.Protocol]::Sftp
    $winSCPTransfer = New-Object WinSCP.TransferOptions
    # Mostly cuz i have no idea how to do it within the object
    # THIS IS HOW I BROKE EVERYTHING
    $winSCPTransfer.TransferMode = [WinSCP.TransferMode]::Ascii

    # Connect to the host and begin the transfer of files, closing the connection upon completion
    $winSCPConnection = New-Object WinSCP.Session
    $winSCPConnection.Open($winSCPSession)
    Write-Host "Transferring files to " + $v.Name -ForegroundColor Cyan
    try{$winSCPConnection.MoveFile($remotePath+"/castore.pem",$remotePath+"/castore.pem.old")}catch{"castore.pem does not exist; backup not necessary"}
    try{$winSCPConnection.MoveFile($remotePath+"/rui.crt",$remotepath+"/rui.crt.old")}catch{"rui.crt does not exist; backup not necessary"}
    try{$winSCPConnection.MoveFile($remotePath+"/rui.key",$remotepath+"/rui.key.old")}catch{"rui.key does not exist; backup not necessary"}
    $winSCPConnection.PutFiles($CAStorePath,$remotePath,$false,$winSCPTransfer)
    $winSCPConnection.PutFiles($localFiles1,$remotePath,$false,$winSCPTransfer)
    $winSCPConnection.PutFiles($localFiles2,$remotePath,$false,$winSCPTransfer)

    

    $winSCPConnection.Close()


    #start SSH session to issue commands
    Write-Output y| plink -ssh $v.Name -l root -pw $vcred.GetNetworkCredential().password "/etc/init.d/hostd restart"
    Write-Output y| plink -ssh $v.Name -l root -pw $vcred.GetNetworkCredential().password "/etc/init.d/vpxa restart"
    Write-Output y| plink -ssh $v.Name -l root -pw $vcred.GetNetworkCredential().password "/etc/init.d/vsanmgmtd restart"
    Write-Output y| plink -ssh $v.Name -l root -pw $vcred.GetNetworkCredential().password "/etc/init.d/vsanvpd restart"
}
Disconnect-VIServer -Server * -ErrorAction SilentlyContinue
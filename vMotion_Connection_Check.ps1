# $DebugPreference = "Continue"
$DebugPreference = "SilentlyContinue"
$ScriptVersion = "2022.03.1.2"
$StartDate = Get-Date
#Select Number of Pings to perform per VMK test
[int]$NumOfPings = 2

Clear-Host
$ScriptPath = Split-Path $MyInvocation.MyCommand.Path
$reportPath = Join-Path $ScriptPath -ChildPath "Reports"
if(!(Test-Path $reportPath)){New-Item -Path $reportPath -ItemType Directory|Out-Null}
$dateSerial = Get-Date -Format yyyyMMddHHmmss
$reportName = "$dateSerial-vMotionReport.csv"
$ReportFile = Join-Path $reportPath -ChildPath $reportName
write-host ""
Write-Host ("="*80) -ForegroundColor DarkGreen
write-host "This Script will generate a list of all vMotion kernel IPs and cross check connectivity between them all"
write-host "A report will be generated and placed in the same location as this script"
write-host ""
write-host "Connect to all relavent vCenter instances before running this script" -ForegroundColor Yellow
Write-Host ("="*80) -ForegroundColor DarkGreen
write-host ""
$selectDC = New-Object System.Management.Automation.Host.ChoiceDescription "&Datacenter","Pick a datacenter"
$selectCluster = New-Object System.Management.Automation.Host.ChoiceDescription "&Cluster","Pick a cluster"
$selectAll = New-Object System.Management.Automation.Host.ChoiceDescription "&All","All Hosts in current connection"
$defaultPings = New-Object System.Management.Automation.Host.ChoiceDescription "&Default","Leave Ping count at $NumOfPings"
$changePings = New-Object System.Management.Automation.Host.ChoiceDescription "&Change","Increase or decrease the number of test pings"
$cancel = New-Object System.Management.Automation.Host.ChoiceDescription "&Exit","Eject! Eject! Eject!"

$title = "DC or All Hosts?";$message = "Run against a single Datacenter or All Hosts?"
$options = [System.Management.Automation.Host.ChoiceDescription[]]($selectDC,$selectCluster,$selectAll,$cancel)
$result = $host.UI.PromptForChoice($title, $message, $options, 1)
Write-Host ""
switch($result){
	0{
		$dcName = Read-Host -Prompt "Which vCenter Datacenter to check? (Comma seperated for multiple datacenters)"
		if($dcName){
			$dcList = $dcName -split ","
			write-host "You have selected to check all vMotion adapters in:" -NoNewline
			write-host $($dcList) -ForegroundColor Cyan
			$vmhostList = Get-Datacenter $dcList|Get-VMHost|Where-Object{$_.ConnectionState -match "connected|maintenance"}|Sort-Object Parent,Name
		}
		else{
			write-host "missing Datacenter name, please try again"
			Exit-Script
		}
	}
	1{
		$clusterName = Read-Host -Prompt "Which vCenter Cluster to check? (Comma seperated for multiple clusters)"
		if($clusterName){
			$clusterList = $clusterName -split ","
			write-host "You have selected to check all vMotion adapters in " -NoNewline
			write-host $($clusterList) -ForegroundColor Cyan
			$vmhostList = Get-Cluster $clusterList|Get-VMHost|Where-Object{$_.ConnectionState -match "connected|maintenance"}|Sort-Object Parent,Name
		}
		else{
			write-host "missing Cluster name, please try again"
			Exit-Script
		}
	}
	2{
		write-host "You have opted to check every vMotion adapter in the currently connected vCenter instance(s)"
		write-host "NOTE:" -ForegroundColor Red
		Write-Host "This will generate a lot of failures trying to connect between CBO and Datacenter vMotion VLANs"
		write-host "You will need to manually reconcile these failures afterwards to determine validity of communication failures."
		$vmhostList = Get-VMHost|Where-Object{$_.ConnectionState -match "connected|maintenance"}|Sort-Object Parent,Name
	}
	3{
		write-host "Cancelling"
		Exit-Script
	}
}

write-host ""
Write-Host ("="*80) -ForegroundColor DarkGreen
$title = "Change Ping Count?";$message = "Keep Default PING count of $NumOfPings or change number of pings to send?"
$options = [System.Management.Automation.Host.ChoiceDescription[]]($defaultPings,$changePings)
$result = $host.UI.PromptForChoice($title, $message, $options, 0)
switch ($result){
	0{
		write-host "Testing with default PING count of $NumOfPings"

	}
	1{
		write-host "You selected to change the test PING count.  Provide an integer form 1-100"
		write-host "*NOTE:" -ForegroundColor Yellow -NoNewline;write-host "Increasing the number of PINGs can greatly increase the time to test."
		write-host "Modify this setting with caution."
		[int]$NumOfPings = Read-Host -Prompt "Provide new number of Pings to test per VMK connection:"
	}
}
write-host "Testing with " -NoNewline
write-host $NumOfPings -ForegroundColor Cyan -NoNewline
write-host " pings per VMK test"
Write-Host ("="*80) -ForegroundColor DarkGreen
write-host ""


if($vmhostList.count -gt 0){
	$hostCount = $vmhostList.count
	write-host "Found " -NoNewline
	write-host $vmhostList.count -ForegroundColor Cyan -NoNewline
	write-host " hosts to check"
	write-host ""
	write-host "Collecting vMotion adapters"
	$vMOadapters = $vmhostList|Get-VMHostNetworkAdapter -VMKernel|Where-Object{$_.VMotionEnabled}
	$vmkCount = $vMOadapters.Count
	write-host "Found " -NoNewline
	write-host $vMOadapters.count -ForegroundColor Cyan -NoNewline
	write-host " adapters to test communications on"
	write-host ""
	write-host "Beginning Host Testing, this can take a while depending on the number of hosts and vMotion Kernel ports..."
	write-host $(Get-Date)
	$vMotionReport = @()
	$h = 1
	$vmhostList|ForEach-Object{
		$localVMHost = $_.Name
		Write-Progress -Id 1 -Activity "Testing Host $_ | v$ScriptVersion | Started:$StartDate" -Status "$localVMHost [ $h of $hostCount ]" -PercentComplete (($h/$hostCount)*100);$h++
		write-host "$(Get-Date)" -ForegroundColor Cyan -NoNewline
		write-host `t" Testing " -NoNewline;write-host $localVMHost -ForegroundColor Cyan
		$esxcli = Get-EsxCli -VMHost $_ -V2
		$params = $esxcli.network.diag.ping.CreateArgs()
		$localKernels = $_|Get-VMHostNetworkAdapter -VMKernel|Where-Object{$_.VMotionEnabled}
		write-host "$(Get-Date -UFormat "%R")" -ForegroundColor Cyan -NoNewline
		write-host `t`t`t`t"Found $($localKernels.count) local VMK to test"
		$k = 1
		$localKernels|foreach-Object{
			Write-Progress -Id 2 -ParentId 1 -Activity "Testing Local VMK Ports" -Status "$($_.Name) [ $k of $($localKernels.count) ]" -PercentComplete (($k/$($localKernels.count))*100);$k++
			$localVMK = $_.Name
			$localVMKip = $_.IP
			$localStack = $_.ExtensionData.Spec.NetstackInstanceKey
			$localMTU = $_.Mtu
			$v = 1
			$vMOadapters|ForEach-Object{
				$testCounter++
				Write-Progress -Id 3 -ParentId 2 -Activity "Testing Remote VMK Ports" -Status "$($_.Name) on $($_.VMhost.Name) [ $v of $vmkCount ]" -PercentComplete (($v/$vmkCount)*100);$v++
				if($localMTU -ne $_.Mtu){
					write-host `t`t`t`t">> MTU MISMATCH <<" -ForegroundColor Yellow
					$mtuMismatch = $true
					$mtuCounter++
				}
				else{
					$mtuMismatch = $false
				}
				$arrMTU = @($localMTU,$_.Mtu)
				$maxMTU = ($arrMTU|Measure-Object -Minimum).Minimum
				Write-Debug -Message "MTU: $maxMTU, from Local:$localMTU Remote:$($_.Mtu)"
				if ($maxMTU -eq 1500) {
					$thisPacket = '1472'
					write-host `t`t`t`t">> NO JUMBOS <<" -ForegroundColor Yellow
				}
				else{
					$thisPacket = '8972'
				}
				$params.host = $_.IP
				$params.size = $thisPacket
				$params.interface = $localVMK
				$params.netstack = $localStack
				$params.count = $NumOfPings
				Write-Debug -Message "HOST: $($params.host)"
				Write-Debug -Message "Size: $($params.size)"
				Write-Debug -Message "VMK: $($params.interface)"
				Write-Debug -Message "STCK: $($params.netstack)"
				Write-Debug -Message "PINGs: $($params.count)"
				$thisResult = $null;$error.Clear();$testErrorValue=""
				try {
					$thisResult = $esxcli.network.diag.ping.Invoke($params)
					if($thisResult.Summary.PacketLost -eq 0){
						$testPassed = $true
						write-host "$(Get-Date -UFormat "%R")" -ForegroundColor Cyan -NoNewline
						# write-host `t`t`t`t"PASS: $localVMK $localVMKip >> $($params.interface) $($params.host) $($params.size)bytes" -ForegroundColor Green
						$passCounter++
					}
					else{
						$testPassed = $false
						write-host "$(Get-Date -UFormat "%R")" -ForegroundColor Cyan -NoNewline
						write-host `t`t`t`t"FAIL: $localVMK $localVMKip >> $($params.interface) $($params.host) $($params.size)bytes" -ForegroundColor Red
						$failCounter++
					}
					$packetStats = "$($thisResult.Summary.Transmitted);$($thisResult.Summary.Received);$($thisResult.Summary.PacketLost)"
				}
				catch {
					if ($error.Exception.Message|ForEach-Object{$_ -like "*Network is unreachable*"}){
						write-host "$(Get-Date -UFormat "%R")" -ForegroundColor Cyan -NoNewline
						write-host `t`t`t`t"Network is unreachable: $localVMK $localVMKip >> $($params.interface) $($params.host)" -ForegroundColor Red
						$testErrorValue = "Destination Newtork Unreachable"
					}
					else{
						write-host "$(Get-Date -UFormat "%R")" -ForegroundColor Cyan -NoNewline
						write-host `t`t`t`t"ESXCLI Error: $localVMK $localVMKip >> $($params.interface) $($params.host)" -ForegroundColor Red
						$testErrorValue = "Unknown"
					}
				}
				
				$columnList = @('SourceHost','SourceVMK','SourceIP','SourceMTU','DestinationHost','DestinationVMK','DestinationIP','DestinationMTU','PacketSize','testPassed','Stats T/R/L','mtuMismatch','Error')
				$row = ""|Select-Object $columnList
				$row.SourceHost = $localVMHost
				$row.SourceVMK = $localVMK
				$row.SourceIP = $localVMKip
				$row.SourceMTU = $localMTU
				$row.DestinationHost = $_.VMhost
				$row.DestinationVMK = $_.Name
				$row.DestinationIP = $_.IP
				$row.DestinationMTU = $_.Mtu
				$row.PacketSize = $thisPacket
				$row.mtuMismatch = $mtuMismatch
				$row.Error = $testErrorValue
				if($thisResult){
					$row.testPassed = $testPassed
					$row."Stats T/R/L" = $packetStats
				}
				else{
					$row.testPassed = $false
					$row."Stats T/R/L" = ""
				}
				$vMotionReport += $row
			}
		}
	}
	write-host ""
	Write-Host ("="*80) -ForegroundColor DarkGreen
	write-host "Passed:" -NoNewline;write-host $passCounter -ForegroundColor Green
	write-host "Failed:" -NoNewline;write-host $failCounter -ForegroundColor Red
	write-host "FailurePercent:" -NoNewline;write-host "$([math]::Round((($failCounter/$testCounter)*100),1))" -ForegroundColor Cyan
	write-host "Number of MTU Mismatch connections:" -NoNewline;write-host $mtuCounter -ForegroundColor Cyan
	Write-Host ("="*80) -ForegroundColor DarkGreen
	write-host "Saving Report to Disk:"
	write-host $ReportFile-foregroundColor Cyan
	$vMotionReport|Export-Csv -NoTypeInformation $ReportFile
}
else{
	write-host "No Hosts found, check connection to vCenter and try again."
	Exit-Script
}
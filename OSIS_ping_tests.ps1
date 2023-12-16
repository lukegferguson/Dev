#Variables
$logdirectory = "C:\OSIS"
$logfilename = "PingLog.txt"
$logpath = "$logdirectory\$logfilename"
#Initialize Target List with CloudFlare DNS
$Targets = @("1.1.1.1")

#Intro paragraph
Write-Host "OSIS Ping Test" -ForegroundColor green -BackgroundColor Blue

#Create directory for logs if not already existing
Write-Host "Verifying log location"
If ((Test-Path -Path $logdirectory) -eq $FALSE) {
    New-Item -Path 'C:\OSIS' -ItemType Directory | Out-Null
    Write-Host "Created $logdirectory"
} else {
    Write-Host "Location $logdirectory already exists"
}

#Acquire and confirm addition of gateway IPs to target list
Write-Host "Getting local gateway IP"
$Gateways = (Get-NetIPConfiguration | ForEach-Object IPv4DefaultGateway).NextHop

foreach ($Gateway in $Gateways){
    write-host "Gateway $gateway, add to ping target list?"
    $include = read-host "Yes or no?"
    
    if ($include -eq "no") {continue}
        else {$Targets += $Gateway}
}

#Prompt user for additional targets to ping
#Trims spaces from the beginning and end of user entered string
Write-host "ADD TARGETS TO PING" -ForegroundColor Green
Write-host "Already in target list CloudFlare DNS 1.1.1.1" -foregroundcolor DarkGreen
Write-Host "Recommended additional targets include:" 
Write-host "OSIS RDS gateway servers like    " -NoNewline 
write-host "SQRLCB.SQRL.local" -ForegroundColor DarkRed 
write-host "OSIS public facing internet resources like    " -NoNewline
write-host "SQRL.osisonline.org" -ForegroundColor DarkRed
write-host "DONE to continue" -ForegroundColor Green

do { $response = Read-host "Enter IP or URL to add to target list"
    
    if ($response -eq "DONE") {continue} 
    else {$targets += $response.Trim()}
    
} until ($response -eq "DONE")

Write-Host "Target list to ping:" -ForegroundColor Green
foreach ($Target in $Targets){write-host "$Target"}

Write-Host "Initializing Logs, located at $logpath" -ForegroundColor Green
Out-File -FilePath $logpath -Append -InputObject "$(get-date) ######## STARTING PING TEST ########"
Out-File -Filepath $logpath -Append -InputObject "Date, Target Adapter Name, Source IP Address, Destination address, Destination DNS Result, Ping Status, TTL, RTT"
foreach ($Target in $Targets){
    Out-File -FilePath $logpath -Append -InputObject "$(get-date) - starting ping test for $target"
}


Write-host "Starting background jobs..." -ForegroundColor DarkGreen

#Create background jobs to run tests, one job per ping target
foreach ($target in $targets){
    start-job -name "$Target" -ScriptBlock {
        
        #Import variables from parent scope
        $target = $using:target
        $LOG = $using:logpath


        #Test-netconnection doesn't have the option to stay on like ping -t, so infinite DoWhile loop instead
        do {
            
            #test connection to target
            $t = Test-NetConnection -Computername "$target"

            #Specify information from ping result to write in log
            #If multiple records are returned, filter for A (IPv4) records and use the first one
            if ($t.AllNameResolutionResults.name.count -gt 1){
                $result = @(
                    "Target-$target",
                    $t.NetAdapter.Name,
                    $t.sourceaddress.ipaddress,
                    (($t.allnameresolutionresults | Where-Object -Property Type -eq "A")[0]).name,
                    (($t.allnameresolutionresults | Where-Object -Property Type -eq "A")[0]).ipaddress,
                    $t.pingreplydetails.status,
                    (($t.DNSonlyrecords | Where-Object -Property Type -eq "A")[0]).ttl,
                    $t.pingreplydetails.roundtriptime
                )
            } 
            #No selection needed on single records,
            #does seem to work for IPv6 single records
            elseif ($t.allnameresolutionresults.name.count -eq 1){
                $result = @(
                    "Target-$target",
                    $t.NetAdapter.Name,
                    $t.sourceaddress.ipaddress,
                    $t.allnameresolutionresults.name,
                    $t.allnameresolutionresult.ipaddress,
                    $t.pingreplydetails.status,
                    $t.DNSonlyrecords.ttl,
                    $t.pingreplydetails.roundtriptime
                )
            } else { 
                $result = @(
                "Target-$target",
                "Ping Success: $($t.PingSucceeded)"
                )
            }

            #Write results of ping
            #Fields: Date, Target, Adapter Name, Source IP Address, Destination address, Destination DNS Result, Ping Status, TTL, RTT 
            Out-File -FilePath "$LOG" -Append -InputObject "$(Get-date) $result"
            
            #sleep to avoid over-logging, failed resolutions can return several times a second
            start-sleep -Seconds 1
        
        } while ($true -eq $true)
    }
}

#Once jobs have started, wait for user input to continue
do {
    Write-Host 'Type "EXIT" to quit' -ForegroundColor DarkRed
    $exit = read-host
} until ($exit -eq "EXIT")

#Stop jobs
foreach ($target in $targets){
    Write-host "Removing background job $target" -ForegroundColor Gray
    Stop-Job -name "$target"
    Remove-Job -name "$target"
    Out-file -filepath "$logpath" -Append  -InputObject "$(Get-date) - Stopping ping test for $target"
    Start-Sleep -Milliseconds 100 #avoids log write collisions
}

#finalize logs
Write-host "Finalizing Logs...." -ForegroundColor Green
Out-File -FilePath $logpath -Append -InputObject "$(get-date) ######## PING TEST ENDED ########"

#Salutation
Write-Host "Goodbye" -ForegroundColor  DarkGreen -BackgroundColor White
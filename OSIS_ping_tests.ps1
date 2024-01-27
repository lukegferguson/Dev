
#Variables
$Scriptver = "1.5"
$LogPath = "C:\OSIS\LOGS\PingScriptLog.txt"
$ResultsPath = "C:\OSIS\LOGS\PingResults.csv"

#Initialize Target List with CloudFlare DNS
$Targets = @("1.1.1.1")

function Write-Log {
    param (
        #InputObject is what is to be written to log/host
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipelineByPropertyName = $true)]
        $InputObject,
        
        #LogPath must include filename
        $LogPath = $Logpath,
        
        #adding -WriteHost switch will show user the log message
        [switch]$WriteHost,
        
        #changes the color of text displayed to user
        $Foregroundcolor = "white",
        
        #Default action is to stop and display message on log write fail
        #Setting erroraction to "SilentlyContinue" will keep script running even if writing logs fails
        $ErrAct = "Stop"
        )

    try {
        if (Test-Path (Split-Path $LogPath)){
            Out-File -FilePath $LogPath -Append -InputObject "$(Get-date) $InputObject" -ErrorAction $ErrAct

        } else {
            New-Item -Path (Split-Path $LogPath) -ItemType Directory -ErrorAction $ErrAct | Out-Null
            Out-File -FilePath $LogPath -Append -InputObject "$(Get-date) Created log file: $logpath"
            Out-File -FilePath $LogPath -Append -InputObject "$(Get-date) $InputObject" -ErrorAction $ErrAct
         }
    } catch {
        Write-Host "UNABLE TO WRITE LOG FILE" -ForegroundColor red -BackgroundColor White
        Write-host "Attempted to write: $InputObject"
        Write-host "System error: $_" -ForegroundColor red
        do {
            $EXIT = read-host -Prompt "EXIT to quit"
        } until ($exit -eq "exit")
        exit
    }

    if ($WriteHost){
        Write-Host "$InputObject" -ForegroundColor "$Foregroundcolor"
    }
}

#Intro paragraph
#Write-Log will stop script if log cannot be written or created
Write-Log "######## OSIS Ping Test Version $ScriptVer ########" -WriteHost -Foregroundcolor "Blue"
Write-Log "Script Log location $logpath" -WriteHost
Write-Log "Verifying CSV for ping test results exists, location $ResultsPath" -WriteHost

#Create CSV for results
#Script stops here if CSV cannot be created
    if(Test-Path $ResultsPath){
        Write-Log "$ResultsPath already exists" -WriteHost
    } else {
        try {
            New-Item -Path $ResultsPath -ItemType File -ErrorAction Stop | Out-Null
            Write-Log "Successfully created CSV for ping test results" -WriteHost
             $CSVHeader = "Date,Time (24 hour),Target,Ping Success,Ping Status,Network Adapter,Source IP Address,Destination IP Address,RTT"
             Out-File -FilePath $ResultsPath -InputObject $CSVheader -Append -Encoding utf8

            
        } catch {
            Write-Log "Unable to create CSV for ping test results at $ResultsPath" -WriteHost
            Write-Log "System Error: $_" -Foregroundcolor red -WriteHost
            do {
                $EXIT = read-host -Prompt "EXIT to quit"
            } until ($exit -eq "exit")
            exit
        }
    }


#Acquire and confirm addition of gateway IPs to target list
Write-log "Getting local gateway IP" -WriteHost
try{
    $Gateways = (Get-NetIPConfiguration -ErrorAction stop | foreach IPv4DefaultGateway).NextHop
    foreach ($Gateway in $Gateways){
        write-log "Gateway $gateway, add to ping target list?" -WriteHost
        $include = read-host "Yes or no?"
        
        if ($include -eq "no") {
            continue
        } else {
                $Targets += $Gateway
                Write-log "Added gateway $gateway to target list" -WriteHost
            }
    }
} catch {
    Write-Log "Unable to obtain local gateway IP" -WriteHost
    Write-Log "System Error $_" -WriteHost
}



#Prompt user for additional targets to ping
#Trims spaces from the beginning and end of user entered string
Write-host "ADD TARGETS TO PING" -ForegroundColor Green
Write-host "Already in target list CloudFlare DNS 1.1.1.1" -foregroundcolor DarkGreen
Write-Host "Recommended additional targets include:" 
Write-host "OSIS RDS connection brokers (internal resources) like    " -NoNewline 
write-host "RDCB.osisonline.org" -ForegroundColor Red
write-host "OSIS public internet facing RDS Gateways like    " -NoNewline
write-host "RDGW.osisonline.org" -ForegroundColor Red
write-host "Type DONE to continue" -ForegroundColor Green

do { $response = Read-host "Enter IP or URL to add to target list"
    
    if ($response -eq "DONE") {continue} 
    else {
        $targets += $response.Trim()
        Write-Log "Added $($response.Trim()) to target list." -WriteHost
    }
    
} until ($response -eq "DONE")

Write-Log "Final target list: $targets" -WriteHost

Write-Log "Starting background jobs..." -WriteHost

#Create background jobs to run tests, one job per ping target
foreach ($target in $targets){
  try {  
    start-job -name "$Target" -ErrorAction stop -ScriptBlock {
        
        #Import variables from parent scope
        $target = $using:target
        $ResultsPath = $using:ResultsPath

        #Test-netconnection doesn't have the option to stay on like ping -t, so infinite DoWhile loop instead
        do {
            #test connection to target
            $t = Test-NetConnection $target

            #Specify information from ping result to write in log
            $result = "$(Get-Date -format "yyyy.MM.dd"),$(Get-Date -Format HH:mm:ss),$($target),$($t.PingSucceeded),$($t.PingReplyDetails.Status),$($t.NetAdapter.Name),$($t.sourceaddress.ipaddress),$($t.PingReplyDetails.Address.IPAddressToString),$($t.pingreplydetails.roundtriptime)"
            
            #Write results of ping
            Out-File -FilePath $ResultsPath -InputObject $result -Append -Encoding utf8
            
            #sleep to avoid over-logging, failed name resolutions can return several times a second
            start-sleep -Seconds 1
        
        } while (
            $true -eq $true
            )
        }
    } catch {
        Write-Log "Unable to start job for $target" -WriteHost
    }
}

#Once jobs have started, wait for user input to continue
try {
    do {
    Write-Host 'Type "EXIT" to quit' -ForegroundColor DarkRed
    $exit = read-host
    } until (
        $exit -eq "EXIT"
        )
} finally {
    #Stop jobs
    foreach ($target in $targets){
        Write-Log "Removing background job $target" -WriteHost
        try {
            Stop-Job -name "$target" -ErrorAction stop
            Remove-Job -name "$target" -ErrorAction stop
            Write-log "Stopped ping test for $target"
        } catch {
            write-log "Unable to stop or remove job for $target" -WriteHost
            Write-Log "System error: $_" -WriteHost
        }
        
        #avoids log write collisions
        Start-Sleep -Milliseconds 100
    }
    #finalize logs
    write-log "######## PING TEST ENDED ########" -WriteHost
    
}

#Salutation
Write-Host "Goodbye" -ForegroundColor  DarkGreen -BackgroundColor White
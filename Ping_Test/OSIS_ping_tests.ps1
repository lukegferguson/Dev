#Create directory for logs if not already existing
If ((Test-Path -Path $loglocation) -eq $FALSE) {
    New-Item -Path 'C:\OSIS' -ItemType Directory
}

#Ping each target, select the pertinent lines from the ping results, then output to file with a timestamp
Start-Job -name "pings" -scriptblock {
    $DNSIP = "8.8.8.8"
    $GatewayIPs = (Get-NetIPConfiguration | foreach IPv4DefaultGateway).NextHop
    $RDSgateway = "SQRLCB.SQRL.local"
    $RDSwebsite = "sqrl.osisonline.org"
    
    $Targets = $DNSIP, $GatewayIPs, $RDSgateway, $RDSwebsite
    
    $loglocation = "C:\OSIS"
    $logfile = "PingLog.txt"
    $go = $true

     while ($go -eq $true) {
        foreach ($Target in $Targets){ 
            $time = (get-date).ToString()
            ping $target | Select-Object -index 2,3,4,5 | foreach {Out-File -FilePath "$loglocation\$logfile" -Append -InputObject "$time - $_ target:$target"}
        }
    }
}

do {
    $exit = read-host 'Type "EXIT" to quit'
} until ($exit -eq "EXIT")

Stop-job "pings"


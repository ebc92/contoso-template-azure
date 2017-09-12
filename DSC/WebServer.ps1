Configuration WebServer {

    Param(
        [Parameter(Mandatory)]
        [String]$DomainName = "contoso.no",

        [Parameter(Mandatory)]
        [PSCredential]$credential
    )

    Import-DscResource -ModuleName xDSCDomainjoin, PSDesiredStateConfiguration

    Node localhost {

        xDSCDomainjoin JoinDomain { 
            Domain    = $DomainName
            Credential    = $credential
        }

        WindowsFeature IIS {
            Ensure               = 'Present'
            Name                 = 'Web-Server'
            IncludeAllSubFeature = $true
        }

        Script createIndex {

            DependsOn = "[xDSCDomainjoin]JoinDomain"

            GetScript = { return get-childitem -Path "C:\inetpub\wwwroot" }

            SetScript = {

                $site = New-Item -Path "C:\inetpub\wwwroot" -ItemType File -Name "index.html"
                Add-Content -Path $site -Value "<h1> <font color='#0000FF'>This website is hosted on $($env:COMPUTERNAME) </font> </h1>"

            }

            TestScript = { Test-Path -Path "C:\inetpub\wwwroot\index.html" }
        }
    }
}
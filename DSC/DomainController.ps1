Configuration DomainController {

    param (

    [Parameter(Mandatory)]
    [String]$DomainName,

    [Parameter(Mandatory)]
    [PSCredential]$credential

    )

    Import-DscResource -ModuleName xActiveDirectory, PSDesiredStateConfiguration, xDscDomainJoin

    <#
    $adminuser = 'contoso\contosoadmin'
    $password = ConvertTo-SecureString 'azurePa$$w0rd' -AsPlainText -Force

    $creds = New-Object System.Management.Automation.PSCredential($adminuser, $password)

    #>

    Node localhost {

        xDscDomainJoin JoinAdDomain {
            Domain = $DomainName
            Credential = $credential
        }

        WindowsFeature DNS {
            Ensure = "Present"
            Name = "DNS"
            DependsOn = "[xDscDomainJoin]JoinAdDomain"
        }

        WindowsFeature ADDSInstall {
            Ensure = "Present"
            Name = "AD-Domain-Services"
            IncludeAllSubFeature = $true
            DependsOn = "[WindowsFeature]DNS"
        }

        WindowsFeature RSATTools {
            Ensure = "Present"
            Name = "RSAT-AD-Tools"
            IncludeAllSubFeature = $true
            DependsOn = "[WindowsFeature]ADDSInstall"
        }

        xADDomainController DomainController {
            DomainName = $DomainName
            DomainAdministratorCredential = $credential
            SafemodeAdministratorPassword = $credential
            DatabasePath = "C:\NTDS"
            LogPath = "C:\NTDS"
            SysvolPath = "C:\SYSVOL"
            DependsOn = "[WindowsFeature]ADDSInstall"
        }


    }


}
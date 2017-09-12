<#
    Declare variables
#>
$rg = "TemplateDeploymentRG"
$automationRg = "ContosoAutomationRG"
$location = "West Europe"

<# 
    Create resource group and deploy ARM template to the resource group.
#>
$rg = New-AzureRmResourceGroup -Name $rg -Location $location
New-AzureRmResourceGroupDeployment -ResourceGroupName $rg.ResourceGroupName -TemplateFile "C:\Users\slk0emcl\Desktop\MSU\Prosjekt\azuredeployment.json" -Verbose -ErrorAction Stop

<# 
    Get VPN gateway public IP and add it to on-premise RRAS gateway using Azure Script Extension.
#>
$gwyPip = Get-AzureRmPublicIpAddress -Name gatewayPip -ResourceGroupName $rg.ResourceGroupName
$extension = Set-AzureRmVMCustomScriptExtension -ResourceGroupName OnPremiseRG `
    -VMName DC1 `
    -Location $location `
    -FileUri "https://onpremisergdiag925.blob.core.windows.net/dscsupportmsu/SetVpnInterface.ps1" `
    -Run "SetVpnInterface.ps1" `
    -Argument "$($gwyPip.IpAddress)" `
    -Name UpdateS2SInterface

<# 
    Define domain info and configuration required to run DscCompilationJob
#>
$Parameters = @{
    "DomainName" = "contoso.no"
    "Credential" = "Contosoadmin"
    
}

$cd = @{
    AllNodes = @(
        @{
            NodeName = "*"
            PSDscAllowDomainUser = $true
            PSDscAllowPlainTextPassword = $true
        }
    )
}

<# 
    Compile DSC configurations using parameters and configuration data
#>
$iisJob = Start-AzureRmAutomationDscCompilationJob -ResourceGroupName $automationRg `
    -AutomationAccountName "ContosoAutomation" -ConfigurationName "WebServer" `
    -Parameters $Parameters -ConfigurationData $cd

$dcJob = Start-AzureRmAutomationDscCompilationJob -ResourceGroupName $automationRg `
    -AutomationAccountName "ContosoAutomation" -ConfigurationName "DomainController" `
    -Parameters $Parameters -ConfigurationData $cd

do {
    $iisJob = $iisJob | Get-AzureRmAutomationDscCompilationJob
    $dcJob = $dcJob | Get-AzureRmAutomationDscCompilationJob
    Start-Sleep -s 10
    Write-Output "Venter 10 sekunder på jobbstatus..."
} while ($iisJob.Status -ne "Completed" -or $dcJob.Status -ne "Completed")

<# 
    Register DSC configurations with corresponding VMs
#>
$webAvailabilitySet = @("Web1", "Web2") | % {Register-AzureRmAutomationDscNode `
    -ResourceGroupName $automationRg -AzureVMName $_.ToString() `
    -NodeConfigurationName "WebServer.localhost" -ConfigurationMode ApplyAndMonitor `
    -AutomationAccountName ContosoAutomation -AzureVMResourceGroup $rg.ResourceGroupName }

$dcAvailabilitySet = @("DC2", "DC3") | % { Register-AzureRmAutomationDscNode `
    -ResourceGroupName $automationRg -AzureVMName $_.ToString() `
    -NodeConfigurationName "DomainController.localhost" -ActionAfterReboot ContinueConfiguration `
     -RebootNodeIfNeeded $true -ConfigurationMode ApplyAndMonitor `
     -AutomationAccountName ContosoAutomation -AzureVMResourceGroup $rg.ResourceGroupName }
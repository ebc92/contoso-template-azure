<#
    Declare variables
#>
$rg = "TemplateDeploymentRG"
$automationRg = "ContosoAutomationRG"
$automationAcc = "ContosoAutomation"
$location = "West Europe"
$path = "C:\Users\slk0emcl\Desktop\MSU\contoso-template-azure\ARM\"

<#
    List resources
#>
Write-Host -ForegroundColor Cyan "Listing all resources in resource group $($rg):"

<# 
    Create resource group and deploy ARM template to the resource group.
#>
Write-Host -ForegroundColor Yellow "Starting ARM template deployment.."
$rg = New-AzureRmResourceGroup -Name $rg -Location $location
New-AzureRmResourceGroupDeployment -ResourceGroupName $rg.ResourceGroupName -TemplateFile (Join-Path -Path $path -ChildPath 'azuredeployment.json') -Verbose -ErrorAction Stop
Write-Host -ForegroundColor Green "ARM template was deployed!"

<# 
    Get VPN gateway public IP and add it to on-premise RRAS gateway using Azure Script Extension.
#>
Write-Host -ForegroundColor Yellow "Getting IP for Azure VPN gateway.."
$gwyPip = Get-AzureRmPublicIpAddress -Name gatewayPip -ResourceGroupName $rg.ResourceGroupName
Write-Host -ForegroundColor Green "VPN gateway is on $($gwyPip.IpAddress)!"
Write-Host -ForegroundColor Yellow "Registering Azure VPN endpoint to on-premise RRAS VPN gateway.."
$extension = Set-AzureRmVMCustomScriptExtension -ResourceGroupName OnPremiseRG `
    -VMName DC1 `
    -Location $location `
    -FileUri "https://onpremisergdiag925.blob.core.windows.net/dscsupportmsu/SetVpnInterface.ps1" `
    -Run "SetVpnInterface.ps1" `
    -Argument "$($gwyPip.IpAddress)" `
    -Name UpdateS2SInterface
if($extension.IsSuccessStatusCode){Write-Host -ForegroundColor Green "Azure VPN endpoint was successfully registered!"}

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
$wsConfig = "WebServer"
Write-Host -ForegroundColor Yellow "Starting DSC compile job for $($wsConfig).."
$iisJob = Start-AzureRmAutomationDscCompilationJob -ResourceGroupName $automationRg `
    -AutomationAccountName "ContosoAutomation" -ConfigurationName $wsConfig `
    -Parameters $Parameters -ConfigurationData $cd

$dcConfig = "DomainController"
Write-Host -ForegroundColor Yellow "Starting DSC compile job for $($dcConfig).."
$dcJob = Start-AzureRmAutomationDscCompilationJob -ResourceGroupName $automationRg `
    -AutomationAccountName "ContosoAutomation" -ConfigurationName $dcConfig `
    -Parameters $Parameters -ConfigurationData $cd

do {
    Write-Host -ForegroundColor Yellow "Waiting for compilation job.."
    Write-Host -ForegroundColor Cyan "$($wsConfig) job: $($iisJob.Status) `n$($dcConfig) job: $($dcJob.Status)"
    $iisJob = $iisJob | Get-AzureRmAutomationDscCompilationJob
    $dcJob = $dcJob | Get-AzureRmAutomationDscCompilationJob
    Start-Sleep -s 30
} while ($iisJob.Status -ne "Completed" -or $dcJob.Status -ne "Completed")
Write-Host -ForegroundColor Green "DSC compilation jobs completed successfully!"

<# 
    Register DSC configurations with corresponding VMs
#>
$webAvailabilitySet = @("Web1", "Web2") | % {
    Write-Host -ForegroundColor Yellow "Registering Azure VM $($_.ToString()) as DSC node using the $($wsConfig) configuration.."

    $registration = Register-AzureRmAutomationDscNode `
    -ResourceGroupName $automationRg -AzureVMName $_.ToString() `
    -NodeConfigurationName "WebServer.localhost" -ConfigurationMode ApplyAndMonitor `
    -AutomationAccountName ContosoAutomation -AzureVMResourceGroup $rg.ResourceGroupName
    
    if ($?){Write-Host -ForegroundColor Green "$($_.ToString()) was successfully registered as a DSC node!"}
}

$dcAvailabilitySet = @("DC2", "DC3") | % { 
    Write-Host -ForegroundColor Yellow "Registering Azure VM $($_.ToString()) as DSC node using the $($dcConfig) configuration.."

    $registration = Register-AzureRmAutomationDscNode `
    -ResourceGroupName $automationRg -AzureVMName $_.ToString() `
    -NodeConfigurationName "DomainController.localhost" -ActionAfterReboot ContinueConfiguration `
     -RebootNodeIfNeeded $true -ConfigurationMode ApplyAndMonitor `
     -AutomationAccountName ContosoAutomation -AzureVMResourceGroup $rg.ResourceGroupName 
     
     if ($?){Write-Host -ForegroundColor Green "$($_.ToString()) was successfully registered as a DSC node!"}
}

$allNodes = Get-AzureRmAutomationDscNode -AutomationAccountName $automationAcc -ResourceGroupName $automationRg | sort-object -Property RegistrationTime

$allNodes | ForEach-Object {
    do {
        $uniqueCompliantId = Get-AzureRmAutomationDscNodeReport -NodeId $_.Id -ResourceGroupName $automationRg -AutomationAccountName $automationAcc | ? { $_.ReportType -eq "Consistency" -and $_.Status -eq "Compliant"} | sort -Unique
        $compliantVmName = (Get-AzureRmAutomationDscNode -AutomationAccountName $automationAcc -ResourceGroupName $automationRg -Id $uniqueCompliantId.NodeId).Name
        if ($uniqueCompliantId -eq $null){Write-Host -ForegroundColor Cyan "Still waiting, trying again in 1 minute.."; start-sleep -s 60}
    } while ($uniqueCompliantId -eq $null)
    Write-Host -ForegroundColor Green "DSC node $($compliantVmName) is now compliant!"
}

<#
    webappdeploy
#>
Write-Host -ForegroundColor Yellow "Deploying WebApp & Azure SQL..."
New-AzureRmResourceGroupDeployment -ResourceGroupName $rg.ResourceGroupName -TemplateFile (Join-Path -Path $path -ChildPath 'azuredeploywebapp.json') -Verbose
Write-Host -ForegroundColor Green "WebApp & Azure SQL deployed!"


Write-Host -ForegroundColor Cyan "Listing all resources in resource group $($rg.ResourceGroupName):"
Get-AzureRmResource | ? {$_.ResourceGroupName –eq $rg.ResourceGroupName} | select ResourceName
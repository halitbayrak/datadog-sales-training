param (
    [Parameter(Mandatory=$true)]
    [int] $NumberOfUsers,

    [Parameter(Mandatory=$true)]
    [string] $SubscriptionId,

    [Parameter(Mandatory=$true)]
    [securestring] $Password,

    [Parameter(Mandatory=$true)]
    [string] $DomainName,

    [Parameter(Mandatory=$true)]
    [string] $OwnerId,

    [Parameter(Mandatory=$true)]
    [string] $DefaultResourceGroup,
    
    [Parameter(Mandatory=$false)]
    [string] $ResourceGroupPrefix = "dd-training",

    [Parameter(Mandatory=$false)]
    [string] $Location = "Central US"
)

$subscription = Get-AzSubscription -SubscriptionId $SubscriptionId
if (-not $subscription) {
    Write-Host "unable to find subscription '$($SubscriptionId)'. please ensure that it exists."
    exit 1
}

$ManagementGroupName = "datadog-sales-training"
$managementGroup = Get-AzManagementGroup -GroupName $ManagementGroupName -ErrorAction SilentlyContinue
if (-not $managementGroup) {
    Write-Host "management group '$ManagementGroupName' does not exist. creating..."
    $managementGroup = New-AzManagementGroup -GroupName $ManagementGroupName -DisplayName 'Datadog Sales Training'
}


$ownerRole = Get-AzRoleDefinition -Name "Owner"
$assignedRoles = Get-AzRoleAssignment -Scope $managementGroup.Id
$ownerAssignedRole = $assignedRoles | Where-Object { $_.ObjectId -eq $OwnerId }
if (-not $ownerAssignedRole) {
    Write-Host "unable to find owner assigned role for management group. will assign."
    $ownerAssignedRole = New-AzRoleAssignment `
        -ObjectId $OwnerId `
        -RoleDefinitionId $ownerRole.Id `
        -Scope $managementGroup.Id
}

$groupSubscription = Get-AzManagementGroupSubscription `
    -GroupName $managementGroup.Name `
    -SubscriptionId $subscription.Id `
    -ErrorAction SilentlyContinue
if (-not $groupSubscription) {
    Write-Host "management group '$($managementGroup.DisplayName)' does not have subscription '$($SubscriptionId)'. moving it."
    $groupSubscription = New-AzManagementGroupSubscription -GroupName $managementGroup.Name -SubscriptionId $subscription.Id
}

$createdRgs = New-Object -TypeName System.Collections.Generic.List[string]
$context = Set-AzContext -SubscriptionObject (Get-AzSubscription -SubscriptionId $subscription.Id)
$defaultResourceGroup = New-AzResourceGroup `
    -Name "$DefaultResourceGroup" `
    -Location "$Location" `
    -Tag @{ business_unit="sales-training"; company="datadog"; env="development" } `
    -Force

for ($i = 1; $i -le $NumberOfUsers; $i++) {
    $user = "user$i"
    $upn = "$user@$DomainName"

    $currentUser = Get-AzADUser -Filter "DisplayName eq '$user'"
    if ($currentUser) {
        Write-Host "user '$user' already exists. this could be an error. skipping to the next user."
        continue
    }

    $newUser = New-AzADUser `
        -DisplayName $user `
        -Password $Password `
        -AccountEnabled $true `
        -MailNickname $user `
        -UserPrincipalName $upn
    
    Write-Host "created user '$($newUser.DisplayName)'."
    Start-Sleep -Seconds 5

    $resourceGroup = New-AzResourceGroup `
        -Name "$ResourceGroupPrefix-$user-rg" `
        -Location "$Location" `
        -Tag @{ owned_by="$user"; business_unit="sales-training"; company="datadog"; env="development" } `
        -Force
    $createdRgs.Add($resourceGroup.ResourceGroupName)
    $role = New-AzRoleAssignment -ObjectId $newUser.Id `
        -RoleDefinitionName $ownerRole.Name `
        -Scope $resourceGroup.ResourceId
    Start-Sleep -Seconds 5
}

$createdRgs = $createdRgs | Join-String -Separator ' | '
return $createdRgs
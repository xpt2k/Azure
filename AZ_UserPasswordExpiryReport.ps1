<#
Link to script:
https://o365reports.com/2020/02/17/export-office-365-users-last-password-change-date-to-csv/

Export Office 365 Users’ Password Expiry Date Report:
./AZ_UserPasswordExpiryReport.ps1

Office 365 Soon to Expire Password Users Report:
Soon to expire password users report allows you to generate a report based on a number of days available for password expiry, I.e., passwords going to expire.
With the help of a soon-to-expire password report, you can remind users to change their password by sending password expiry notification.
Run the script with –SoonToExpire param with X number of days.
./AZ_UserPasswordExpiryReport.ps1 -SoonToExpire 7

Office 365 Password Expired Users report using PowerShell:
To list users whose password has expired, run the script with –PwdExpired switch param. By using this report, you can notify users about password expiry.
./AZ_UserPasswordExpiryReport.ps1 -PwdExpired

Get a list of Users with Password Never Expires
Using –PwdNeverExpires switch, you can retrieve users whose password set to never expire.

./AZ_UserPasswordExpiryReport.ps1 -PwdNeverExpires
Note: Microsoft recommends to set “Password Never Expires” to prevent unneeded password change.
Because when users forced to change their password, often they choose a small, predictable alteration to their existing password or reusing their old passwords

Get all Licensed Users’ Password Last Change Date and Expiry Date:
Most organizations won’t delete terminated user accounts; instead, they will unlicense them. When running a password expiry report, getting old/terminated user accounts is unnecessary. In that case, you can ignore unlicensed users.

By using –LicensedUserOnly switch, you can export licensed users’ password related attributes like password last change date, password age, password expiry date, days to password expiry, etc.
./AZ_UserPasswordExpiryReport.ps1 -LicensedUserOnly
You can also refer our dedicated blog on Office 365 users’ detailed license report.

Export Recently Password Changed Users Report:
To get a list of recent password changers report, run the script with –RecentPwdChanges param. You can pass the number of days in –RecentPwdChanges param.

./AZ_UserPasswordExpiryReport.ps1 -RecentPwdChanges 7
The above script will export a list of users who changed their password in the past 7 days.

Export More Granular Password Expiry Report:
To get a more granular password report, you can use multiple filters together. For example,

./AZ_UserPasswordExpiryReport.ps1 -PasswordExpired –LicensedUserOnly
The above script will export all licensed users whose password was expired.

Schedule Office 365 Password Reports:
You can schedule a password expiry report in Task Scheduler. If you schedule the script to run every week, you can send password expiry notification to password soon to expire users.

./AZ_UserPasswordExpiryReport.ps1 -UserName Admin@contoso.com -Password XXX

#>

Param
(
    [Parameter(Mandatory = $false)]
    [switch]$PwdNeverExpires,
    [switch]$PwdExpired,
    [switch]$LicensedUserOnly,
    [int]$SoonToExpire,
    [int]$RecentPwdChanges,
    [string]$UserName,
    [string]$Password
)

#Check for MSOnline module
$Module = Get-Module -Name MSOnline -ListAvailable
if ($Module.count -eq 0) {
    Write-Host MSOnline module is not available  -ForegroundColor yellow
    $Confirm = Read-Host Are you sure you want to install module? [Y] Yes [N] No
    if ($Confirm -match "[yY]") {
        Install-Module MSOnline
        Import-Module MSOnline
    }
    else {
        Write-Host MSOnline module is required to connect AzureAD.Please install module using Install-Module MSOnline cmdlet.
        Exit
    }
}

#Storing credential in script for scheduling purpose/ Passing credential as parameter
if (($UserName -ne "") -and ($Password -ne "")) {
    $SecuredPassword = ConvertTo-SecureString -AsPlainText $Password -Force
    $Credential = New-Object System.Management.Automation.PSCredential $UserName, $SecuredPassword
    Connect-MsolService -Credential $credential
}
else {
    Connect-MsolService | Out-Null
}

$Result = ""
$PwdPolicy = @{}
$Results = @()
$UserCount = 0
$PrintedUser = 0

#Output file declaration
$ExportCSV = ".\AZ_UserPasswordExpiryReport_$((Get-Date -format yyyy-MMM-dd-ddd` hh-mm` tt).ToString()).csv"

#Getting Password policy for the domain
$Domains = Get-MsolDomain   #-Status Verified
foreach ($Domain in $Domains) {
    #Check for federated domain
    if ($Domain.Authentication -eq "Federated") {
        $PwdValidity = 0
    }
    else {
        $PwdValidity = (Get-MsolPasswordPolicy -DomainName $Domain -ErrorAction SilentlyContinue ).ValidityPeriod
        if ($PwdValidity -eq $null) {
            $PwdValidity = 90
        }
    }
    $PwdPolicy.Add($Domain.name, $PwdValidity)
}
Write-Host Generating report...
#Loop through each user
Get-MsolUser -All | ForEach-Object {
    $UPN = $_.UserPrincipalName
    $DisplayName = $_.DisplayName
    [boolean]$Federated = $false
    $UserCount++
    #Remove external users
    if ($UPN -like "*#EXT#*") {
        return
    }

    $PwdLastChange = $_.LastPasswordChangeTimestamp
    $PwdNeverExpire = $_.PasswordNeverExpires
    $LicenseStatus = $_.isLicensed
    $Print = 0
    Write-Progress -Activity "`n     Processed user count: $UserCount "`n"  Currently Processing: $DisplayName"
    if ($LicenseStatus -eq $true) {
        $LicenseStatus = "Licensed"
    }
    else {
        $LicenseStatus = "Unlicensed"
    }


    #Finding password validity period for user
    $UserDomain = $UPN -Split "@" | Select-Object -Last 1
    $PwdValidityPeriod = $PwdPolicy[$UserDomain]

    #Check for Pwd never expires set from pwd policy
    if ([int]$PwdValidityPeriod -eq 2147483647) {
        $PwdNeverExpire = $true
        $PwdExpireIn = "Never Expires"
        $PwdExpiryDate = "-"
        $PwdExpiresIn = "-"
    }
    elseif ($PwdValidityPeriod -eq 0) { #Users from federated domain
        $Federated = $true
        $PwdExpireIn = "Insufficient data in O365"
        $PwdExpiryDate = "-"
        $PwdExpiresIn = "-"
    }
    elseif ($PwdNeverExpire -eq $False) { #Check for Pwd never expires set from Set-MsolUser
        $PwdExpiryDate = $PwdLastChange.AddDays($PwdValidityPeriod)
        $PwdExpiresIn = (New-TimeSpan -Start (Get-Date) -End $PwdExpiryDate).Days
        if ($PwdExpiresIn -gt 0) {
            $PwdExpireIn = "in $PwdExpiresIn days"
        }
        elseif ($PwdExpiresIn -lt 0) {
            #Write-host `n $PwdExpiresIn
            $PwdExpireIn = $PwdExpiresIn * (-1)
            #Write-Host ************$pwdexpiresin
            $PwdExpireIn = "$PwdExpireIn days ago"
        }
        else {
            $PwdExpireIn = "Today"
        }
    }
    else {
        $PwdExpireIn = "Never Expires"
        $PwdExpiryDate = "-"
        $PwdExpiresIn = "-"
    }

    #Calculating Password since last set
    $PwdSinceLastSet = (New-TimeSpan -Start $PwdLastChange).Days

    #Filter for user with Password nerver expires
    if (($PwdNeverExpires.IsPresent) -and ($PwdNeverExpire = $false)) {
        return
    }

    #Filter for password expired users
    if (($pwdexpired.IsPresent) -and (($PwdExpiresIn -ge 0) -or ($PwdExpiresIn -eq "-"))) {
        return
    }

    #Filter for licensed users
    if (($LicensedUserOnly.IsPresent) -and ($LicenseStatus -eq "Unlicensed")) {
        return
    }

    #Filter for soon to expire pwd users
    if (($SoonToExpire -ne "") -and (($PwdExpiryDate -eq "-") -or ([int]$SoonToExpire -lt $PwdExpiresIn) -or ($PwdExpiresIn -lt 0))) {
        return
    }

    #Filter for recently password changed users
    if (($RecentPwdChanges -ne "") -and ($PwdSinceLastSet -gt $RecentPwdChanges)) {
        return
    }

    if ($Federated -eq $true) {
        $PwdExpiryDate = "Insufficient data in O365"
        $PwdExpiresIn = "Insufficient data in O365"
    }

    $PrintedUser++

    #Export result to csv
    $Result = @{'Display Name' = $DisplayName; 'User Principal Name' = $upn; 'Pwd Last Change Date' = $PwdLastChange; 'Days since Pwd Last Set' = $PwdSinceLastSet; 'Pwd Expiry Date' = $PwdExpiryDate; 'Days since Expiry(-) / Days to Expiry(+)' = $PwdExpiresIn ; 'Friendly Expiry Time' = $PwdExpireIn; 'License Status' = $LicenseStatus }
    $Results = New-Object PSObject -Property $Result
    $Results | Select-Object 'Display Name', 'User Principal Name', 'Pwd Last Change Date', 'Days since Pwd Last Set', 'Pwd Expiry Date', 'Friendly Expiry Time', 'License Status', 'Days since Expiry(-) / Days to Expiry(+)' | Export-Csv -Path $ExportCSV -Notype -Append
}

If ($UserCount -eq 0) {
    Write-Host No records found
}
else {
    Write-Host `nThe output file contains $PrintedUser users.
    if ((Test-Path -Path $ExportCSV) -eq "True") {
        Write-Host `nThe Output file available in $ExportCSV -ForegroundColor Green
        $Prompt = New-Object -ComObject wscript.shell
        $UserInput = $Prompt.popup("Do you want to open output file?", `
                0, "Open Output File", 4)
        If ($UserInput -eq 6) {
            Invoke-Item "$ExportCSV"
        }
    }
}

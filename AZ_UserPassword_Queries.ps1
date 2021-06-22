# Check if a specific user has their pwd set to never expire
Get-AzADUser -objectid xx@postoffice.co.uk | select-object @{n = "PasswordNeverExpires"; e = { $_.passwordpolicies -contains "DisablePasswordExpiration" } }

# Check when last a specific user has changed their pwd
Get-msoluser -userprincipalname xx@postoffice.co.uk | select-object displayname, lastpasswordchangetimestamp

# Check all Azure users pwd never expire value
Get-msoluser -all | Select-Object Userprincipalname, passwordneverexpires | export-csv C:\temp\AzureAD_PwdNeverExpires.csv -nti
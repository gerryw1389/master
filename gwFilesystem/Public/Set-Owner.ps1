<#######<Script>#######>
<#######<Header>#######>
# Name: Set-Template
# Copyright: Gerry Williams (https://www.gerrywilliams.net)
# License: MIT License (https://opensource.org/licenses/mit)
# Script Modified from: Boe Prox - https://gallery.technet.microsoft.com/scriptcenter/set-owner-ff4db177
<#######</Header>#######>
<#######<Body>#######>

FUNCTION Set-Owner
{
    <#
.SYNOPSIS
Changes owner of a file or folder to another user or group.
.DESCRIPTION
Changes owner of a file or folder to another user or group.
.PARAMETER Source
The folder or file that will have the owner changed.
.PARAMETER Account
Optional parameter to change owner of a file or folder to specified account.
Default value is 'Builtin\Administrators'
.PARAMETER Recurse
Recursively set ownership on subfolders and files beneath given folder.
.Parameter Logfile
Specifies A Logfile. Default is $PSScriptRoot\..\Logs\Scriptname.Log and is created for every script automatically.
Note: If you don't like my scripts forcing logging, I wrote a post on how to fix this at https://www.gerrywilliams.net/2018/02/ps-forcing-preferences/
.EXAMPLE
Set-Owner -Path C:\temp\test.txt
.EXAMPLE
Set-Owner -Path C:\temp\test.txt -Account 'Domain\bprox'
.EXAMPLE
Set-Owner -Path C:\temp -Recurse 
Description
-----------
Changes the owner of all files and folders under C:\Temp to Builtin\Administrators
.EXAMPLE
Get-ChildItem C:\Temp | Set-Owner -Recurse -Account 'Domain\bprox'
.NOTES
2017-09-08: v1.0 Initial script 
.Functionality
Please see https://www.gerrywilliams.net/2017/09/running-ps-scripts-against-multiple-computers/ on how to run against multiple computers.

#>  
    [cmdletbinding(SupportsShouldProcess = $True)]
    
    Param 
    (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True)]
        [string[]]$Source,
        
        [string]$Account = 'Builtin\Administrators',
        
        [switch]$Recurse,
        
        [String]$Logfile = "$PSScriptRoot\..\Logs\Set-Owner.Log"
    )

    Begin
    {

        #Prevent Confirmation on each Write-Debug command when using -Debug
        If ($PSBoundParameters['Debug']) 
        {
            $DebugPreference = 'Continue'
        }
        Try 
        {
            [void][TokenAdjuster]
        } 
        Catch
        {
            $AdjustTokenPrivileges = @"
            using System;
            using System.Runtime.InteropServices;

             public class TokenAdjuster
             {
              [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
              internal static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall,
              ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);
              [DllImport("kernel32.dll", ExactSpelling = true)]
              internal static extern IntPtr GetCurrentProcess();
              [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
              internal static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr
              phtok);
              [DllImport("advapi32.dll", SetLastError = true)]
              internal static extern bool LookupPrivilegeValue(string host, string name,
              ref long pluid);
              [StructLayout(LayoutKind.Sequential, Pack = 1)]
              internal struct TokPriv1Luid
              {
               public int Count;
               public long Luid;
               public int Attr;
              }
              internal const int SE_PRIVILEGE_DISABLED = 0x00000000;
              internal const int SE_PRIVILEGE_ENABLED = 0x00000002;
              internal const int TOKEN_QUERY = 0x00000008;
              internal const int TOKEN_ADJUST_PRIVILEGES = 0x00000020;
              public static bool AddPrivilege(string privilege)
              {
               try
               {
                bool retVal;
                TokPriv1Luid tp;
                IntPtr hproc = GetCurrentProcess();
                IntPtr htok = IntPtr.Zero;
                retVal = OpenProcessToken(hproc, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, ref htok);
                tp.Count = 1;
                tp.Luid = 0;
                tp.Attr = SE_PRIVILEGE_ENABLED;
                retVal = LookupPrivilegeValue(null, privilege, ref tp.Luid);
                retVal = AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
                return retVal;
               }
               catch (Exception ex)
               {
                throw ex;
               }
              }
              public static bool RemovePrivilege(string privilege)
              {
               try
               {
                bool retVal;
                TokPriv1Luid tp;
                IntPtr hproc = GetCurrentProcess();
                IntPtr htok = IntPtr.Zero;
                retVal = OpenProcessToken(hproc, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, ref htok);
                tp.Count = 1;
                tp.Luid = 0;
                tp.Attr = SE_PRIVILEGE_DISABLED;
                retVal = LookupPrivilegeValue(null, privilege, ref tp.Luid);
                retVal = AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
                return retVal;
               }
               catch (Exception ex)
               {
                throw ex;
               }
              }
             }
"@
            Add-Type $AdjustTokenPrivileges
        }

        #Activate necessary admin privileges to make changes without NTFS perms
        [void][TokenAdjuster]::AddPrivilege("SeRestorePrivilege") #Necessary to set Owner Permissions
        [void][TokenAdjuster]::AddPrivilege("SeBackupPrivilege") #Necessary to bypass Traverse Checking
        [void][TokenAdjuster]::AddPrivilege("SeTakeOwnershipPrivilege") #Necessary to override FilePermissions

        Import-Module -Name "$Psscriptroot\..\Private\helpers.psm1" 
		$PSDefaultParameterValues = @{ "*-Log:Logfile" = $Logfile }
Set-Variable -Name "Logfile" -Value $Logfile -Scope "Global"
        Set-Console
        Start-Log

    }
    
    Process
    {    
        
        


        ForEach ($Item in $Source)
        {
            Log "FullName: $Item" 
            #The ACL objects do not like being used more than once, so re-create them on the Process block
            $DirOwner = New-Object System.Security.AccessControl.DirectorySecurity
            $DirOwner.SetOwner([System.Security.Principal.NTAccount]$Account)
            $FileOwner = New-Object System.Security.AccessControl.FileSecurity
            $FileOwner.SetOwner([System.Security.Principal.NTAccount]$Account)
            $DirAdminAcl = New-Object System.Security.AccessControl.DirectorySecurity
            $FileAdminAcl = New-Object System.Security.AccessControl.DirectorySecurity
            $AdminACL = New-Object System.Security.AccessControl.FileSystemAccessRule('Builtin\Administrators', 'FullControl', 'ContainerInherit,ObjectInherit', `
                    'InheritOnly', 'Allow')
            $FileAdminAcl.AddAccessRule($AdminACL)
            $DirAdminAcl.AddAccessRule($AdminACL)
            Try 
            {
                $Item = Get-Item -LiteralPath $Item -Force -ErrorAction Stop
                If (-NOT $Item.PSIsContainer) 
                {
                    If ($PSCmdlet.ShouldProcess($Item, 'Set File Owner'))
                    {
                        Try
                        {
                            $Item.SetAccessControl($FileOwner)
                        } 
                        Catch
                        {
                            Log "Couldn't take ownership of $($Item.FullName)! Taking FullControl of $($Item.Directory.FullName)" `
                                -Color DarkRed 
                            $Item.Directory.SetAccessControl($FileAdminAcl)
                            $Item.SetAccessControl($FileOwner)
                        }
                    }
                } 
                Else 
                {
                    If ($PSCmdlet.ShouldProcess($Item, 'Set Directory Owner'))
                    {                        
                        Try
                        {
                            $Item.SetAccessControl($DirOwner)
                        } 
                        
                        Catch
                        {
                            Log "Couldn't take ownership of $($Item.FullName)! Taking FullControl of $($Item.Parent.FullName)"-Color DarkRed 
                            $Item.Parent.SetAccessControl($DirAdminAcl) 
                            $Item.SetAccessControl($DirOwner)
                        }
                    }
                    
                    If ($Recurse) 
                    {
                        [void]$PSBoundParameters.Remove('Source')
                        Get-ChildItem $Item -Force | Set-Owner @PSBoundParameters
                    }
                }  
            }
        
            Catch
            {
                Log "$_.Exception.Message" -Color DarkRed 
            }
        }
    }

    End
    {
        [void][TokenAdjuster]::RemovePrivilege("SeRestorePrivilege") 
        [void][TokenAdjuster]::RemovePrivilege("SeBackupPrivilege") 
        [void][TokenAdjuster]::RemovePrivilege("SeTakeOwnershipPrivilege")
        Log "Remove Privileges that have been granted" 
        
        Stop-Log  
    }

}  

# Set-Owner -Source C:\temp\test.txt -Account 'Domain\bprox'

<#######</Body>#######>
<#######</Script>#######>
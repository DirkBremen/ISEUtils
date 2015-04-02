﻿if ($host.Name -ne 'Windows PowerShell ISE Host'){
    Write-Warning "This Module can be only installed from within ISE"
    exit
}
. $PSScriptRoot\functions\Get-ZenCode.ps1
. $PSScriptRoot\functions\Get-ISEShortcuts.ps1
. $PSScriptRoot\functions\Add-ISESnippet.ps1
. $PSScriptRoot\functions\Get-ISESnippet.ps1
. $PSScriptRoot\functions\Remove-ISESnippet.ps1
. $PSScriptRoot\functions\Export-SelectionToRTF.ps1
. $PSScriptRoot\functions\Export-SelectionToHTML.ps1

#menu items

#compiled functions
#region
Add-Type -Path $PSScriptRoot\resources\ISEUtils.dll
ipmo $PSScriptRoot\resources\DirectorySearcher.dll


$newISEMenu = [scriptblock]::Create('$psISE.CurrentPowerShellTab.VerticalAddOnTools.Add("New-ISEMenu",[ISEUtils.NewISEMenu],$true);($psISE.CurrentPowerShellTab.VerticalAddOnTools | where {$_.Name -eq "New-ISEMenu"}).IsVisible=$true')
$newISESnippet = [scriptblock]::Create('$psISE.CurrentPowerShellTab.VerticalAddOnTools.Add("New-ISESnippet",[ISEUtils.NewISESnippet],$true);($psISE.CurrentPowerShellTab.VerticalAddOnTools | where {$_.Name -eq "New-ISESnippet"}).IsVisible=$true')
$fileTree = [scriptblock]::Create('$psISE.CurrentPowerShellTab.VerticalAddOnTools.Add("FileTree",[ISEUtils.FileTree],$true);($psISE.CurrentPowerShellTab.VerticalAddOnTools | where {$_.Name -eq "FileTree"}).IsVisible=$true')
$addScriptHelp = [scriptblock]::Create('$psISE.CurrentPowerShellTab.VerticalAddOnTools.Add("Add-ScriptHelp",[ISEUtils.AddScriptHelp],$true);($psISE.CurrentPowerShellTab.VerticalAddOnTools | where {$_.Name -eq "Add-ScriptHelp"}).IsVisible=$true')
#endregion

#inline functions 
#region

###ISE Session###
<#
    Modified version of ISE Session Tools Module 1.0
    
    Oisin Grehan (MVP)    
    http://www.nivot.org/
#>
#region
$SCRIPT:defaultSessionFile = "$(Split-Path $profile)\psISE.session.clixml"


$exportISESession = {
    $SaveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
    $SaveFileDialog.Title = "Save PS session file"
    $SaveFileDialog.InitialDirectory = (Split-Path $profile)
    $SaveFileDialog.Filter = "All files (PowerShell session file)| *.session.clixml"
    if ($SaveFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){
        $sessionFile = $SaveFileDialog.FileName        $psise.CurrentPowerShellTab.files | ? { -not $_.IsUntitled } | % {
            $_.save(); $_ } | Export-Clixml -Force $sessionFile
    } 
}

$ImportISESession = {
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Title = "Open PS session file"
    $openFileDialog.InitialDirectory = (Split-Path $profile)
    $openFileDialog.Filter = "All files (PowerShell session file)| *.session.clixml"
    if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){
        $sesionFile = $openFileDialog.FileName
        import-clixml $sessionFile | % {
            try {
                $psise.CurrentPowerShellTab.files.Add($_.fullpath)
            } catch { write-error $_ }
        }
    }
}

Register-ObjectEvent $psise.CurrentPowerShellTab.Files CollectionChanged -Action {
    # files collection
    try {
        $sender | ? {-not $_.IsUntitled} | % { $_.save(); $_ } | Export-Clixml -Force $event.messagedata
    } catch {
        # convert terminating errors to non-terminating
        write-error $_
    }
} -sourceidentifier AutoSaveSession -messagedata $defaultSessionFile > $null


if ((test-path $defaultSessionFile)) {      
    $files = Import-Clixml $defaultSessionFile    
    # only load if we've got something to load       
    if ($files.count -gt 0) {
        # just show first two of the last files in the session as a reminder
        $hint = ($files|select -first 2 -expand displayname) -join ","
            
        # default to YES
        if ($host.ui.PromptForChoice("Session Restore",
            ("Load last session of {0} file(s) into current tab?`n`nHint: {1}, ..." -f $files.count, $hint),
            [Management.Automation.Host.ChoiceDescription[]]@("&Yes", "&No"), 0) -eq 0) {
            Import-CliXML $defaultSessionFile | % {
                try {
                    $psise.CurrentPowerShellTab.files.Add($_.fullpath)
                } catch { write-error $_ }
            }
        }
    }
}

#endregion
$openScriptFolder = { Invoke-Item (Split-Path $psISE.CurrentFile.FullPath) }
$expandZenCode = {
    $currEditor = $psISE.CurrentFile.Editor
    $col = $currEditor.CaretLineText.Length - $currEditor.CaretLineText.TrimStart().Length
    $currEditor.SelectCaretLine()
    $line = $currEditor.CaretLineText.Trim()
    if ($line -like '*|*'){
        $sb = [scriptblock]::Create($line.Insert($line.IndexOf('|') + 2, "zenCode '") + "'")
        $txt = $sb.Invoke()
    }
    else{
        $txt = (zenCode $line)
    }

    $offset = " " * $col 
    $txt = $offset + (($txt-split "`r`n") -join "`r`n" + $offset)
    $currEditor.InsertText($txt)
}   
         
$runLine={
    ([scriptblock]::Create($psISE.CurrentFile.Editor.CaretLineText.Trim())).Invoke()
}

$splitSelectionByLastChar={
    $currEditor = $psISE.CurentFile.Editor
    $currEditor.InsertText($selText.Remove($selText.LastIndexOf($splitChar),1).Split($splitChar) -join "`n")
    $selText = $currEditor.SelectedText
    $splitChar = $selText[-1]
    $currEditor.InsertText($selText.Remove($selText.LastIndexOf($splitChar),1).Split($splitChar) -join "`n")
}

$removeMenu = {
    $menu = $psISE.CurrentPowerShellTab.AddOnsMenu.Submenus | where DisplayName -eq 'ISEUtils'
    [void]$psISE.CurrentPowerShellTab.AddOnsMenu.Submenus.Remove($menu)
    [Microsoft.VisualBasic.Interaction]::Msgbox('To completly remove ISEUtils you will also need to delete the entry from your profile',"Exclamation","")
}

#endregion

#add Menu items
Add-Type -AssemblyName Microsoft.VisualBasic
function Add-SubMenu($menu,$displayName,$code,$shortCut=$null){
    try{
        [void]$menu.Submenus.Add($displayName, $code,  $shortCut)
    }
    catch{
        $shortCut = [Microsoft.VisualBasic.Interaction]::InputBox("The shortcut ($shortCut) is already assigned. Please enter another combination.", "ShortCut", $shortCut)
        [void]$menu.Submenus.Add($displayName, $code,  $shortCut)
    }
}
        
$menu = $psISE.CurrentPowerShellTab.AddOnsMenu.Submenus.Add('ISEUtils', $null, $null)
Add-SubMenu $menu 'Expand ZenCode' $expandZenCode 'CTRL+SHIFT+J'
Add-SubMenu $menu 'Run Line' $runLine 'F2'
Add-SubMenu $menu 'Split Selection by last char' $splitSelectionByLastChar $null
Add-SubMenu $menu 'New-ISESnippet' $newISESnippet $null
Add-SubMenu $menu 'New-ISEMenu' $newISEMenu $null
Add-SubMenu $menu 'FileTree' $fileTree $null
Add-SubMenu $menu 'Add-ScriptHelp' $addScriptHelp $null
Add-SubMenu $menu 'Open-ScriptFolder' $openScriptFolder $null
Add-SubMenu $menu 'Export-ISESession' $exportISESession $null
Add-SubMenu $menu 'Import-ISESession' $importISESession $null
Add-SubMenu $menu 'Remove ISEUtils' $removeMenu $null
Add-SubMenu $menu 'Export-SelectionToRTF' ((Get-Command Export-SelectionToRTF).ScriptBlock) $null
Add-SubMenu $menu 'Export-SelectionToHTML' ((Get-Command Export-SelectionToHTML).ScriptBlock) $null

Export-ModuleMember -Function ("Get-ZenCode","Get-ISEShortCuts","Get-ISESnippet","Remove-ISESnippet","Add-ISESnippet","Get-File","Export-SelectionToHTML","Export-SelectionToRTF") -Alias zenCode


$ExecutionContext.SessionState.Module.OnRemove = {
    Unregister-Event -SourceIdentifier AutoSaveession -ErrorAction silentlycontinue
}

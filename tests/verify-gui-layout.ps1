[CmdletBinding()]
param([string]$SourcePath)
$ErrorActionPreference='Stop'
if(-not $SourcePath){$SourcePath=Join-Path (Split-Path -Parent $PSScriptRoot) 'src\PowerPlanManager.ps1'}
. $SourcePath -LoadOnly
function Assert-Layout([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Create-LayoutHandles($Control){$null=$Control.Handle;foreach($child in $Control.Controls){Create-LayoutHandles $child};$Control.PerformLayout()}
$form=Build-MainForm
try{
    Create-LayoutHandles $form;Refresh-PlanList
    foreach($size in @(@(1180,780),@(1020,700),@(1400,900))){
        $form.Size=New-Object Drawing.Size($size[0],$size[1]);$form.PerformLayout()
        foreach($pageName in @('首页','备份与恢复','外观')){
            Show-MainPage $pageName;$page=$form.Tag.Pages[$pageName];$page.PerformLayout()
            foreach($control in $page.Controls){Assert-Layout ($control.Right -le $page.ClientSize.Width) ($pageName+': content must fit horizontally: '+$control.Text)}
            Assert-Layout ($page.Parent.Right -le $page.Parent.Parent.ClientSize.Width) 'Page must remain within the shell.'
        }
        Show-MainPage '首页'
        $pickerBounds=$script:PlanPicker.Bounds;$useBounds=$script:EnableButton.Bounds;$refreshBounds=$script:RefreshButton.Bounds
        Assert-Layout ($script:PlanPicker.Parent -eq $script:EnableButton.Parent -and [Math]::Abs($pickerBounds.Y-$useBounds.Y) -le 5) 'Plan selector and activation must share a horizontal row.'
        Assert-Layout ($pickerBounds.Right -lt $useBounds.Left -and $useBounds.Right -lt $refreshBounds.Left) 'Plan actions must have non-overlapping gaps.'
        Assert-Layout ($pickerBounds.Width -ge 200) 'Plan picker must remain readable.'
        foreach($button in @($script:EnableButton,$script:EditButton,$script:RefreshButton,$form.Tag.ManagementToggle)){
            Assert-Layout ($button.Width -lt 240 -and $button.Height -ge 36) 'Action buttons must stay compact with adequate hit areas.'
        }
        $commonTable=$form.Tag.CommonHost.Controls[0]
        if($commonTable -is [Windows.Forms.TableLayoutPanel]){
            foreach($rowIndex in 1..($commonTable.RowCount-1)){
                $ac=$commonTable.GetControlFromPosition(1,$rowIndex);$dc=$commonTable.GetControlFromPosition(2,$rowIndex);$edit=$commonTable.GetControlFromPosition(3,$rowIndex)
                Assert-Layout ($ac.Right -lt $dc.Left -and $dc.Right -lt $edit.Left) 'Common AC/DC values and edit buttons occupy distinct columns.'
            }
        }
        Write-Output ('PASS: home, backup and appearance layouts at {0}x{1}; vertical scroll keeps content reachable.' -f $form.Width,$form.Height)
    }
    Assert-Layout ($script:PlanPicker.Items.Count -gt 0) 'Plans loaded.'
    Assert-Layout ((Get-SelectedPlan).Id -in @($script:Plans.Id)) 'Selected plan exists.'
    Assert-Layout ($script:DetailsBox.Text.Contains((Get-SelectedPlan).Id)) 'Technical details match the selected plan.'
    $active=@($script:Plans | Where-Object Id -eq $script:ActivePlanId)[0]
    Assert-Layout ($form.Tag.ActiveLabel.Text.Contains($active.Name)) 'Current plan is identified by name.'
    $editor=Build-EditSettingsDialog -Plan (Get-SelectedPlan) -Settings $form.Tag.HomeSettings
    try{
        Create-LayoutHandles $editor;$editor.Size=New-Object Drawing.Size(1040,740);$editor.PerformLayout()
        foreach($button in @($editor.Tag.ApplyButton,$editor.Tag.CloseButton)){
            $point=$editor.PointToClient($button.Parent.PointToScreen($button.Location))
            Assert-Layout ($point.X -ge 0 -and $point.Y -ge 0 -and $point.X+$button.Width -le $editor.ClientSize.Width -and $point.Y+$button.Height -le $editor.ClientSize.Height) 'Editor actions must be reachable at minimum size.'
        }
        Assert-Layout ($editor.Tag.Grid.Height -ge 100) 'The grid must retain usable height.'
    }finally{$editor.Dispose()}
    $visibility=New-VisibilityDialog (Get-SelectedPlan)
    try{
        Create-LayoutHandles $visibility;$visibility.Size=New-Object Drawing.Size(940,680);$visibility.PerformLayout()
        foreach($button in @($visibility.Tag.Reveal,$visibility.Tag.Restore)){
            $point=$visibility.PointToClient($button.Parent.PointToScreen($button.Location))
            Assert-Layout ($point.Y+$button.Height -le $visibility.ClientSize.Height -and $point.X+$button.Width -le $visibility.ClientSize.Width) 'Visibility actions stay inside minimum-size window.'
        }
    }finally{$visibility.Dispose()}
    Write-Output 'PASS: real read-only startup, selected/current identity and minimum editor layout.'
}finally{$form.Dispose()}

[CmdletBinding()]
param([string]$SourcePath)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($SourcePath)) { $SourcePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\PowerPlanManager.ps1' }
. $SourcePath -LoadOnly

function Assert-Layout {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

# Fail immediately instead of displaying a modal error in unattended checks.
function Show-ErrorMessage {
    param([string]$Message)
    throw $Message
}

# Construct the actual application controls without showing a window or invoking
# any power-setting operation. An error dialog must never count as a passing test.
$testForm = $null
try {
    $testForm = Build-MainForm
    Assert-Layout ($testForm -is [System.Windows.Forms.Form]) 'The application did not build a main form.'
    $splitControl = @($testForm.Controls | Where-Object { $_ -is [System.Windows.Forms.SplitContainer] })
    Assert-Layout ($splitControl.Count -eq 1) 'The main form must contain its split view.'
    $splitControl = $splitControl[0]
    $toolbarControl = @($testForm.Controls | Where-Object { $_ -is [System.Windows.Forms.FlowLayoutPanel] })[0]
    $statusControl = @($testForm.Controls | Where-Object { $_ -is [System.Windows.Forms.StatusStrip] })[0]
    Assert-Layout ($null -ne $script:PlanList -and $null -ne $script:DetailsBox) 'Plan list and details controls must be constructed.'

    foreach ($testSize in @(@(1120, 720), @(900, 560), @(1400, 850))) {
        $testForm.Size = New-Object System.Drawing.Size($testSize[0], $testSize[1])
        $testForm.PerformLayout()
        Assert-Layout ($splitControl.SplitterDistance -ge $splitControl.Panel1MinSize) 'The left panel is below its minimum width.'
        Assert-Layout (($splitControl.Width - $splitControl.SplitterDistance - $splitControl.SplitterWidth) -ge $splitControl.Panel2MinSize) 'The right panel is below its minimum width.'
        Assert-Layout ($splitControl.Top -ge $toolbarControl.Bottom) 'The split view overlaps the toolbar.'
        Assert-Layout ($splitControl.Bottom -le $statusControl.Top) 'The split view overlaps the status bar.'
        foreach ($panel in @($splitControl.Panel1, $splitControl.Panel2)) {
            $heading = @($panel.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] })[0]
            $content = @($panel.Controls | Where-Object { $_.Dock -eq [System.Windows.Forms.DockStyle]::Fill })[0]
            Assert-Layout ($content.Top -ge $heading.Bottom) 'Panel contents overlap their heading.'
        }
        Write-Output ('PASS: main form {0}x{1}; panels {2}/{3}' -f $testForm.Width, $testForm.Height, $splitControl.Panel1.Width, $splitControl.Panel2.Width)
    }

    # Read actual local plans through the same refresh path used by Form.Shown.
    # Create only native handles; do not show a window or change a power plan.
    $null = $testForm.Handle
    $null = $script:PlanList.Handle
    Refresh-PlanList
    Assert-Layout ($script:PlanList.Items.Count -gt 0) 'The startup refresh did not populate the plan list.'
    Assert-Layout ($script:SelectedPlan.Id -in @($script:Plans.Id)) 'Startup did not select an existing plan.'
    Assert-Layout ($script:DetailsBox.Text.Contains($script:SelectedPlan.Id)) 'Startup did not load the selected plan details.'
    Assert-Layout ($script:StatusLabel.Text.Contains($script:ActivePlanId)) 'The status bar did not show the active plan.'
    Write-Output ('PASS: actual startup refresh; {0} plans and selected plan details loaded.' -f $script:PlanList.Items.Count)
} finally {
    if ($null -ne $testForm) { $testForm.Dispose() }
}

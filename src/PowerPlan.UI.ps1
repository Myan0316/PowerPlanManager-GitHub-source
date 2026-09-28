# Presentation only: all system writes remain in PowerPlan.Core.ps1.
$script:AppearancePath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PowerPlanManager\appearance.json'
$script:Appearance = [pscustomobject]@{ Mode='System'; Accent='System' }
$script:ThemeSignature = ''
function Initialize-UiWidgets {
    if ('PowerPlanUi.Button' -as [type]) { return }
    Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -WarningAction SilentlyContinue -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
namespace PowerPlanUi {
    public class SearchBox : TextBox {
        [System.Runtime.InteropServices.DllImport("user32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
        static extern IntPtr SendMessage(IntPtr hwnd, int message, IntPtr wParam, string text);
        protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); SendMessage(Handle,0x1501,new IntPtr(1),"搜索名称、分类或 GUID"); }
    }
    public class Button : System.Windows.Forms.Button {
        bool hover;
        public Button() { SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true); }
        protected override void OnMouseEnter(EventArgs e) { hover=true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover=false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnPaint(PaintEventArgs e) {
            e.Graphics.Clear(Parent == null ? SystemColors.Control : Parent.BackColor);
            e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
            float w=Width-1, h=Height-1, r=12;
            using(var p=new GraphicsPath()) {
                p.AddArc(0,0,r,r,180,90); p.AddArc(w-r,0,r,r,270,90);
                p.AddArc(w-r,h-r,r,r,0,90); p.AddArc(0,h-r,r,r,90,90); p.CloseFigure();
                using(var b=new SolidBrush(hover && Enabled ? FlatAppearance.MouseOverBackColor : BackColor)) e.Graphics.FillPath(b,p);
                if(FlatAppearance.BorderSize>0) using(var pen=new Pen(FlatAppearance.BorderColor)) e.Graphics.DrawPath(pen,p);
            }
            var color=Enabled ? ForeColor : Color.FromArgb((ForeColor.R+BackColor.R)/2,(ForeColor.G+BackColor.G)/2,(ForeColor.B+BackColor.B)/2);
            var bounds=new Rectangle(Padding.Left,Padding.Top,Width-Padding.Horizontal,Height-Padding.Vertical);
            var flags=TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis;
            flags |= TextAlign==ContentAlignment.MiddleLeft ? TextFormatFlags.Left : TextFormatFlags.HorizontalCenter;
            TextRenderer.DrawText(e.Graphics,Text,Font,bounds,color,flags);
            if(Focused && ShowFocusCues) ControlPaint.DrawFocusRectangle(e.Graphics,new Rectangle(4,4,Width-8,Height-8),ForeColor,BackColor);
        }
    }
    public class Form : System.Windows.Forms.Form {
        public Form() { DoubleBuffered=true; SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true); }
    }
    public class FlowLayoutPanel : System.Windows.Forms.FlowLayoutPanel {
        public FlowLayoutPanel() { DoubleBuffered=true; SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true); }
    }
    public class TableLayoutPanel : System.Windows.Forms.TableLayoutPanel {
        public TableLayoutPanel() { DoubleBuffered=true; SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true); }
    }
}
'@
}
$script:AccentChoices = @(
    [pscustomobject]@{Id='System';Name='跟随系统强调色';Hex='#2563EB'},
    [pscustomobject]@{Id='Ocean';Name='海洋蓝';Hex='#2563EB'},
    [pscustomobject]@{Id='Forest';Name='森林绿';Hex='#16805D'},
    [pscustomobject]@{Id='Iris';Name='鸢尾紫';Hex='#7953BF'},
    [pscustomobject]@{Id='Amber';Name='暖琥珀';Hex='#AA630E'},
    [pscustomobject]@{Id='Rose';Name='玫瑰红';Hex='#B54870'},
    [pscustomobject]@{Id='Graphite';Name='石墨灰';Hex='#596579'}
)

function Read-Appearance {
    $script:Appearance = [pscustomobject]@{ Mode='System'; Accent='System' }
    try {
        if (-not [IO.File]::Exists($script:AppearancePath)) { return }
        if ((Get-Item -LiteralPath $script:AppearancePath).Length -gt 4096) { return }
        $saved = [IO.File]::ReadAllText($script:AppearancePath) | ConvertFrom-Json
        if ($saved.Mode -in @('System','Light','Dark') -and $saved.Accent -in @($script:AccentChoices.Id)) {
            $script:Appearance = [pscustomobject]@{ Mode=[string]$saved.Mode; Accent=[string]$saved.Accent }
        }
    } catch { } # Invalid preferences must never prevent the application from opening.
}
function Save-Appearance {
    $folder = [IO.Path]::GetDirectoryName($script:AppearancePath)
    [void][IO.Directory]::CreateDirectory($folder)
    $pending = Join-Path $folder ([guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($pending,($script:Appearance | ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($script:AppearancePath)) { [IO.File]::Replace($pending,$script:AppearancePath,($script:AppearancePath+'.bak')) }
        else { [IO.File]::Move($pending,$script:AppearancePath) }
    } finally { if ([IO.File]::Exists($pending)) { [IO.File]::Delete($pending) } }
}
function Get-SystemAppearance {
    try {
        $null = [Windows.UI.ViewManagement.UISettings,Windows.UI.ViewManagement,ContentType=WindowsRuntime]
        $settings = New-Object Windows.UI.ViewManagement.UISettings
        $foreground = $settings.GetColorValue([Windows.UI.ViewManagement.UIColorType]::Foreground)
        $accent = $settings.GetColorValue([Windows.UI.ViewManagement.UIColorType]::Accent)
        return [pscustomobject]@{ Dark=((5*$foreground.G + 2*$foreground.R + $foreground.B) -gt 1024); Accent=[Drawing.Color]::FromArgb($accent.R,$accent.G,$accent.B) }
    } catch { return [pscustomobject]@{Dark=$false;Accent=[Drawing.SystemColors]::Highlight} }
}
function Mix-UiColor($First,$Second,[double]$Amount) {
    return [Drawing.Color]::FromArgb([int]($First.R*(1-$Amount)+$Second.R*$Amount),[int]($First.G*(1-$Amount)+$Second.G*$Amount),[int]($First.B*(1-$Amount)+$Second.B*$Amount))
}
function Get-UiLuminance($Color) {
    $channels = @($Color.R,$Color.G,$Color.B) | ForEach-Object { $v=$_/255.0; if($v -le 0.04045){$v/12.92}else{[Math]::Pow(($v+0.055)/1.055,2.4)} }
    return (0.2126*$channels[0]+0.7152*$channels[1]+0.0722*$channels[2])
}
function Get-UiPalette {
    if ([Windows.Forms.SystemInformation]::HighContrast) {
        return [pscustomobject]@{Dark=$false;Back=[Drawing.SystemColors]::Window;Surface=[Drawing.SystemColors]::Window;Text=[Drawing.SystemColors]::WindowText;Muted=[Drawing.SystemColors]::WindowText;Border=[Drawing.SystemColors]::WindowText;Accent=[Drawing.SystemColors]::Highlight;OnAccent=[Drawing.SystemColors]::HighlightText;Soft=[Drawing.SystemColors]::Control;HighContrast=$true}
    }
    $system = Get-SystemAppearance
    $dark = $script:Appearance.Mode -eq 'Dark' -or ($script:Appearance.Mode -eq 'System' -and $system.Dark)
    $choice = @($script:AccentChoices | Where-Object Id -eq $script:Appearance.Accent)[0]
    $accent = if ($choice.Id -eq 'System') { $system.Accent } else { [Drawing.ColorTranslator]::FromHtml($choice.Hex) }
    if ($dark) { $accent = Mix-UiColor $accent ([Drawing.Color]::White) 0.30 }
    $base = if($dark){[Drawing.ColorTranslator]::FromHtml('#171B22')}else{[Drawing.ColorTranslator]::FromHtml('#F4F6FA')}
    $surface = if($dark){[Drawing.ColorTranslator]::FromHtml('#222832')}else{[Drawing.Color]::White}
    $onAccent = if ((Get-UiLuminance $accent) -gt 0.179) { [Drawing.Color]::Black } else { [Drawing.Color]::White }
    return [pscustomobject]@{
        Dark=$dark;HighContrast=$false;Back=(Mix-UiColor $base $accent 0.025);Surface=$surface
        Text=$(if($dark){[Drawing.ColorTranslator]::FromHtml('#EDF2F8')}else{[Drawing.ColorTranslator]::FromHtml('#202C3D')})
        Muted=$(if($dark){[Drawing.ColorTranslator]::FromHtml('#BCC7D5')}else{[Drawing.ColorTranslator]::FromHtml('#526176')})
        Border=$(if($dark){[Drawing.ColorTranslator]::FromHtml('#485260')}else{[Drawing.ColorTranslator]::FromHtml('#CBD3DF')})
        Accent=$accent;OnAccent=$onAccent;Soft=(Mix-UiColor $surface $accent 0.12)
    }
}
function Set-ControlPalette($Control,$Palette) {
    $Control.BackColor=$Palette.Surface; $Control.ForeColor=$Palette.Text
    if ($Control -is [Windows.Forms.Form] -or $Control.Name -in @('Shell','TableHeader')) { $Control.BackColor=$Palette.Back }
    if ($Control.Name -eq 'Muted') { $Control.ForeColor=$Palette.Muted }
    if ($Control -is [Windows.Forms.Label] -and $null -ne $Control.Parent) { $Control.BackColor=$Control.Parent.BackColor }
    if ($Control -is [Windows.Forms.Label] -and $Control.Name -eq 'TableHeader') { $Control.BackColor=$Palette.Back;$Control.ForeColor=$Palette.Muted }
    if ($Control -is [Windows.Forms.Button]) {
        $Control.FlatStyle='Flat'; $Control.FlatAppearance.BorderColor=$Palette.Border
        $Control.FlatAppearance.MouseOverBackColor=$Palette.Soft
        $Control.FlatAppearance.BorderSize=1
        if ($Control.Name -eq 'Primary') {
            $Control.BackColor=$Palette.Accent; $Control.ForeColor=$Palette.OnAccent
            $Control.FlatAppearance.MouseOverBackColor=$Palette.Accent
        }
        if ($Control.Name -eq 'SelectedNavigation') { $Control.BackColor=$Palette.Soft;$Control.ForeColor=$Palette.Text;$Control.FlatAppearance.BorderSize=0 }
        if ($Control.Name -eq 'Navigation') { $Control.BackColor=$Palette.Back;$Control.FlatAppearance.BorderSize=0 }
    }
    if ($Control.Name -eq 'Badge') { $Control.BackColor=$Palette.Soft;$Control.ForeColor=$Palette.Text }
    if ($Control -is [Windows.Forms.DataGridView]) {
        $Control.EnableHeadersVisualStyles=$false; $Control.BackgroundColor=$Palette.Surface; $Control.GridColor=$Palette.Border
        $Control.DefaultCellStyle.BackColor=$Palette.Surface; $Control.DefaultCellStyle.ForeColor=$Palette.Text
        $Control.DefaultCellStyle.SelectionBackColor=$Palette.Accent; $Control.DefaultCellStyle.SelectionForeColor=$Palette.OnAccent
        $Control.ColumnHeadersDefaultCellStyle.BackColor=$Palette.Back; $Control.ColumnHeadersDefaultCellStyle.ForeColor=$Palette.Text
        $Control.ColumnHeadersDefaultCellStyle.SelectionBackColor=$Palette.Back
    }
    if ($Control -is [Windows.Forms.StatusStrip]) {
        $Control.BackColor=$Palette.Back
        foreach($item in $Control.Items){$item.BackColor=$Palette.Back;$item.ForeColor=$Palette.Text}
    }
    foreach ($child in $Control.Controls) { Set-ControlPalette $child $Palette }
}
function Set-WindowPalette($Form,$Palette) {
    Set-ControlPalette $Form $Palette
    if ($Form.IsHandleCreated) {
        try {
            if (-not ('PowerPlanThemeNative' -as [type])) {
                Add-Type 'public static class PowerPlanThemeNative { [System.Runtime.InteropServices.DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(System.IntPtr h, int a, ref int v, int n); }'
            }
            $darkValue=[int]$Palette.Dark
            $null=[PowerPlanThemeNative]::DwmSetWindowAttribute($Form.Handle,20,[ref]$darkValue,4)
        } catch { } # Older Windows may not support the title-bar attribute.
    }
}
function Initialize-UiChoice($Control) {
    $Control.DrawMode='OwnerDrawFixed'
    $Control.Font=New-Object Drawing.Font('Microsoft YaHei UI',10)
    $Control.ItemHeight=[int]$Control.Font.GetHeight()+8
    if($Control -is [Windows.Forms.ComboBox]){$Control.FlatStyle='Standard'}
    $Control.Add_DrawItem({param($sender,$eventArgs)
        if($eventArgs.Index -lt 0 -or $eventArgs.Index -ge $sender.Items.Count){return}
        $palette=Get-UiPalette
        $selected=($eventArgs.State -band [Windows.Forms.DrawItemState]::Selected) -ne 0
        $back=if($selected){$palette.Accent}else{$palette.Surface}
        $fore=if($selected){$palette.OnAccent}else{$palette.Text}
        $brush=New-Object Drawing.SolidBrush($back);$textBrush=New-Object Drawing.SolidBrush($fore)
        try{
            $eventArgs.Graphics.FillRectangle($brush,$eventArgs.Bounds)
            $text=$sender.GetItemText($sender.Items[$eventArgs.Index])
            $rect=New-Object Drawing.RectangleF(($eventArgs.Bounds.X+5),($eventArgs.Bounds.Y+3),([Math]::Max(1,$eventArgs.Bounds.Width-10)),($eventArgs.Bounds.Height-3))
            $format=New-Object Drawing.StringFormat;$format.Trimming='EllipsisCharacter';$format.FormatFlags='NoWrap'
            try{$eventArgs.Graphics.DrawString($text,$sender.Font,$textBrush,$rect,$format)}finally{$format.Dispose()}
            $eventArgs.DrawFocusRectangle()
        }finally{$brush.Dispose();$textBrush.Dispose()}
    })
}
function Update-AppTheme([switch]$Force) {
    $palette=Get-UiPalette
    $signature=($palette.Dark.ToString()+'/'+$palette.Accent.ToArgb()+'/'+$palette.HighContrast+'/'+$palette.Text.ToArgb()+'/'+$palette.Back.ToArgb())
    if (-not $Force -and $signature -eq $script:ThemeSignature) { return }
    $script:ThemeSignature=$signature
    foreach($form in @([Windows.Forms.Application]::OpenForms)){Set-WindowPalette $form $palette}
    if ($null -ne $script:MainForm -and -not $script:MainForm.IsDisposed) { Set-WindowPalette $script:MainForm $palette }
}
function New-UiLabel([string]$Text,[int]$Size=10,[switch]$Muted) {
    $label=New-Object Windows.Forms.Label
    $label.Text=$Text;$label.AutoSize=$true;$label.UseMnemonic=$false
    $label.Font=New-Object Drawing.Font('Microsoft YaHei UI',$Size)
    $label.Margin=New-Object Windows.Forms.Padding(0,0,0,12)
    if($Muted){$label.Name='Muted'}
    return $label
}
function New-UiFlow {
    Initialize-UiWidgets
    $flow=New-Object PowerPlanUi.FlowLayoutPanel
    $flow.AutoSize=$true;$flow.AutoSizeMode='GrowAndShrink';$flow.WrapContents=$true
    $flow.Margin=New-Object Windows.Forms.Padding(0,0,0,12)
    return $flow
}
function New-UiButton([string]$Text,[scriptblock]$Action,[switch]$Primary) {
    Initialize-UiWidgets
    $button=New-Object PowerPlanUi.Button
    $button.Text=$Text;$button.AutoSize=$true;$button.MinimumSize=New-Object Drawing.Size(88,38)
    $button.Padding=New-Object Windows.Forms.Padding(12,5,12,5);$button.Margin=New-Object Windows.Forms.Padding(0,0,10,0)
    if($Primary){$button.Name='Primary'}
    $button.Tag=$Action
    if($null -ne $Action){$button.Add_Click({param($sender,$eventArgs) Invoke-UiAction -Owner $sender.FindForm() -Action $sender.Tag})}
    return $button
}
function New-UiPage {
    Initialize-UiWidgets
    $page=New-Object PowerPlanUi.FlowLayoutPanel
    $page.Dock='Fill';$page.FlowDirection='TopDown';$page.WrapContents=$false;$page.AutoScroll=$true
    $page.Padding=New-Object Windows.Forms.Padding(28,24,28,20)
    $page.Add_SizeChanged({param($sender,$eventArgs) Resize-UiPage $sender})
    return $page
}
function New-UiRow([int[]]$Widths) {
    Initialize-UiWidgets
    $row=New-Object PowerPlanUi.TableLayoutPanel
    $row.ColumnCount=$Widths.Count;$row.RowCount=1;$row.AutoSize=$true;$row.AutoSizeMode='GrowAndShrink'
    $row.Margin=New-Object Windows.Forms.Padding(0,0,0,14)
    foreach($width in $Widths){
        $style=if($width -eq 0){New-Object Windows.Forms.ColumnStyle('Percent',100)}else{New-Object Windows.Forms.ColumnStyle('Absolute',$width)}
        [void]$row.ColumnStyles.Add($style)
    }
    return $row
}
function Resize-UiPage($Page) {
    $width=[Math]::Max(100,$Page.ClientSize.Width-$Page.Padding.Horizontal-24)
    foreach($child in $Page.Controls){
        if($child -is [Windows.Forms.Label]){$child.MaximumSize=New-Object Drawing.Size($width,0)}
        elseif($child -is [Windows.Forms.FlowLayoutPanel] -or $child -is [Windows.Forms.TableLayoutPanel]){
            $child.MinimumSize=New-Object Drawing.Size($width,0);$child.MaximumSize=New-Object Drawing.Size($width,0)
        } elseif($child -isnot [Windows.Forms.Button]) {$child.Width=$width}
    }
}
function Get-FriendlySetting($Setting) {
    # Only these documented timeouts have known seconds/zero semantics.
    if ($Setting.GroupId -eq '7516b95f-f776-4464-8c53-06167f40cc99' -and $Setting.SettingId -eq '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e') {
        return [pscustomobject]@{Name='多久后关闭屏幕';Description='无人操作时关闭显示，电脑仍可继续运行。关闭屏幕不等于睡眠。';Time=$true}
    }
    if ($Setting.GroupId -eq '238c9fa8-0aad-41ed-83f4-97be242c8f20' -and $Setting.SettingId -eq '29f6c1db-86da-48c5-9fdb-f2b67b1f44da') {
        return [pscustomobject]@{Name='多久后进入睡眠';Description='无人操作时暂停大部分活动，唤醒后继续使用。实际行为受硬件和系统策略影响。';Time=$true}
    }
    return [pscustomobject]@{Name=$Setting.Name;Description='按本机提供的定义调整。接通电源与使用电池分别保存；不了解用途时，可以保留当前值。';Time=$false}
}
function Format-SettingValue($Setting,$Value) {
    if($null -eq $Value){return '无法读取'}
    $friendly=Get-FriendlySetting $Setting
    if($friendly.Time){
        if([uint64]$Value -eq 0){return '从不'}
        if([uint64]$Value % 60 -eq 0){return ('{0} 分钟' -f ([uint64]$Value/60))}
        return ('{0} 秒' -f $Value)
    }
    $choice=@($Setting.Choices | Where-Object Value -eq $Value)
    if($choice.Count -eq 1){return $choice[0].Name}
    return ('{0} {1}' -f $Value,$Setting.Unit).Trim()
}
function Set-FriendlyTimeInput($InputControl,$Setting,[string]$Value) {
    $InputControl.DropDownStyle='DropDownList';$InputControl.DisplayMember='Name'
    $values=@(0,60,120,300,600,900,1200,1800,3600,7200,14400)
    [uint64]$current=0
    if([uint64]::TryParse($Value,[ref]$current)){$values+= $current}
    foreach($number in @($values | Sort-Object -Unique)){
        if((-not (Test-PowerSettingValue $Setting $number)) -or [string]$number -eq $Value){
            $index=$InputControl.Items.Add([pscustomobject]@{Value=$number;Name=(Format-SettingValue $Setting $number)})
            if([string]$number -eq $Value){$InputControl.SelectedIndex=$index}
        }
    }
    if($InputControl.SelectedIndex -lt 0){
        $InputControl.SelectedIndex=$InputControl.Items.Add([pscustomobject]@{Value=$Value;Name=('未保存输入：'+$Value)})
    }
}
function Show-MainPage([string]$Name) {
    foreach($key in $script:MainForm.Tag.Pages.Keys){$script:MainForm.Tag.Pages[$key].Visible=($key -eq $Name)}
    foreach($button in $script:MainForm.Tag.Navigation){$button.Name=if($button.Text -eq $Name){'SelectedNavigation'}else{'Navigation'}}
    $page=$script:MainForm.Tag.Pages[$Name];$page.BringToFront();Resize-UiPage $page
    Update-AppTheme -Force
}
function Update-HomeSummary {
    param([AllowNull()][object[]]$Settings,[string]$SettingsError='')
    $state=$script:MainForm.Tag;$plan=Get-SelectedPlan
    $active=@($script:Plans | Where-Object Id -eq $script:ActivePlanId)
    $state.ActiveLabel.Text=if($active.Count -eq 1){'正在使用 · '+$active[0].Name}else{'当前计划未知，请刷新'}
    $state.PlanHeading.Text=if($null -ne $plan){'正在查看 · '+$plan.Name}else{'选择一个电源计划'}
    $state.PlanHint.Text=if($null -eq $plan){'请刷新后选择计划。'}elseif($plan.Id -eq $script:ActivePlanId){'这个计划正在使用。调整前会自动备份，保存后重新读取核对。'}else{'正在查看未启用的计划。查看或修改它不会自动切换当前计划。'}
    $state.HomeSettings=@()
    $nextControl=$null;$table=$null
    if($null -eq $plan){$nextControl=New-UiLabel '请刷新后选择计划。' 10 -Muted}
    try{
        if($null -ne $plan -and -not $SettingsError){
            if(-not $PSBoundParameters.ContainsKey('Settings')){$Settings=@(Get-PowerSettings -Plan $plan)}
            $state.HomeSettings=@($Settings)
        }
        if($null -ne $plan -and -not $SettingsError){
        $table=New-UiRow @(0,122,122,88);$table.RowCount=1;$table.Margin=New-Object Windows.Forms.Padding(0)
        $table.Padding=New-Object Windows.Forms.Padding(0);$table.CellBorderStyle='None'
        $table.Add_CellPaint({param($sender,$eventArgs)
            $palette=Get-UiPalette
            if($eventArgs.Row -eq 0){$brush=New-Object Drawing.SolidBrush($palette.Back);try{$eventArgs.Graphics.FillRectangle($brush,$eventArgs.CellBounds)}finally{$brush.Dispose()}}
            $pen=New-Object Drawing.Pen($palette.Border)
            try{$bounds=$eventArgs.CellBounds;$eventArgs.Graphics.DrawLine($pen,$bounds.Left,($bounds.Bottom-1),$bounds.Right,($bounds.Bottom-1))}finally{$pen.Dispose()}
        })
        $column=0
        foreach($text in @('无人操作时','接通电源','使用电池','')){
            $label=New-UiLabel $text 9 -Muted;$label.Name='TableHeader';$label.Margin=New-Object Windows.Forms.Padding(8,10,8,10)
            $table.Controls.Add($label,$column,0);$column++
        }
        [void]$table.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
        foreach($setting in @($Settings | Sort-Object {if($_.SettingId -eq '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e'){0}else{1}})){
            $friendly=Get-FriendlySetting $setting
            if(-not $friendly.Time){continue}
            $card=New-UiFlow;$card.FlowDirection='TopDown';$card.WrapContents=$false;$card.Dock='Fill'
            $card.Margin=New-Object Windows.Forms.Padding(10,16,14,12)
            $title=New-UiLabel $friendly.Name 11
            $description=New-UiLabel $friendly.Description 9 -Muted
            $title.Margin=New-Object Windows.Forms.Padding(0,0,0,6);$description.Margin=New-Object Windows.Forms.Padding(0,0,0,6)
            $card.Controls.AddRange(@($title,$description))
            $card.Add_SizeChanged({param($sender,$eventArgs) foreach($label in $sender.Controls){$label.MaximumSize=New-Object Drawing.Size(([Math]::Max(100,$sender.Width-12)),0)}})
            $ac=New-UiLabel (Format-SettingValue $setting $setting.AcValue) 11
            $dc=New-UiLabel (Format-SettingValue $setting $setting.DcValue) 11
            foreach($value in @($ac,$dc)){$value.Anchor='Left';$value.Margin=New-Object Windows.Forms.Padding(8);$value.MaximumSize=New-Object Drawing.Size(104,0)}
            $edit=New-UiButton '调整'
            $edit.MinimumSize=New-Object Drawing.Size(70,36);$edit.Anchor='None';$edit.Margin=New-Object Windows.Forms.Padding(4)
            $edit.Tag=$setting
            $edit.AccessibleDescription=$setting.SettingId
            $edit.Add_Click({param($sender,$eventArgs)
                $settingId=$sender.AccessibleDescription
                Invoke-UiAction -Owner $sender.FindForm() -Action {Show-CommonSetting -SettingId $settingId}
            })
            $rowIndex=$table.RowCount;$table.RowCount++
            [void]$table.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
            $table.Controls.Add($card,0,$rowIndex);$table.Controls.Add($ac,1,$rowIndex);$table.Controls.Add($dc,2,$rowIndex);$table.Controls.Add($edit,3,$rowIndex)
        }
        if($table.RowCount -gt 1){$nextControl=$table}else{$table.Dispose();$nextControl=New-UiLabel '本机没有提供可识别的屏幕/睡眠常用项。请在高级设置中查看实际项目。' 10 -Muted}
        }
        if($SettingsError){$nextControl=New-UiLabel ('常用设置读取失败：'+$SettingsError) 10 -Muted}
    }catch{
        if($null -ne $table -and -not $table.IsDisposed -and $table -ne $nextControl){$table.Dispose()}
        $nextControl=New-UiLabel ('常用设置读取失败：'+$_.Exception.Message) 10 -Muted
    }
    Set-ControlPalette $nextControl (Get-UiPalette)
    $page=$state.Pages['首页'];$page.SuspendLayout();$state.CommonHost.SuspendLayout()
    try{
        foreach($c in @($state.CommonHost.Controls)){$state.CommonHost.Controls.Remove($c);$c.Dispose()}
        $state.CommonHost.Controls.Add($nextControl)
        Resize-CommonCards
    }finally{$state.CommonHost.ResumeLayout($true);$page.ResumeLayout($true)}
}
function Resize-CommonCards {
    if($null -eq $script:MainForm -or $script:MainForm.IsDisposed){return}
    $hostPanel=$script:MainForm.Tag.CommonHost
    $width=[Math]::Max(100,$hostPanel.ClientSize.Width-8)
    foreach($card in $hostPanel.Controls){
        if($card -is [Windows.Forms.FlowLayoutPanel]){
            $card.MinimumSize=New-Object Drawing.Size($width,0);$card.MaximumSize=New-Object Drawing.Size($width,0)
            foreach($label in $card.Controls | Where-Object {$_ -is [Windows.Forms.Label]}){$label.MaximumSize=New-Object Drawing.Size(([Math]::Max(80,$width-40)),0)}
            foreach($row in $card.Controls | Where-Object {$_ -is [Windows.Forms.FlowLayoutPanel]}){$row.MaximumSize=New-Object Drawing.Size(([Math]::Max(80,$width-40)),0)}
        }else{$card.Width=$width;$card.MinimumSize=New-Object Drawing.Size($width,0);$card.MaximumSize=New-Object Drawing.Size($width,0)}
    }
}
function Show-CommonSetting([string]$SettingId) {
    $plan=Get-SelectedPlan;if($null -eq $plan){return}
    $settings=@(Get-PowerSettings -Plan $plan | Where-Object SettingId -eq $SettingId)
    if($settings.Count -ne 1){throw '该设置已不可用，请刷新。'}
    $dialog=New-PowerEditor -Plan $plan -Settings $settings -Common
    try{[void]$dialog.ShowDialog($script:MainForm)}finally{$dialog.Tag.Closing=$true;$dialog.Dispose()}
    Refresh-PlanList -PreferredId $plan.Id
}
function New-PowerMainForm {
    Initialize-Desktop;Initialize-UiWidgets;Read-Appearance
    $script:Refreshing=$false;$script:UiBusy=$false;$script:ToolbarButtons=@()
    $form=New-Object PowerPlanUi.Form
    $form.Text=$script:AppName;$form.StartPosition='CenterScreen';$form.Font=New-Object Drawing.Font('Microsoft YaHei UI',10)
    $form.AutoScaleMode='Dpi';$form.ClientSize=New-Object Drawing.Size(1180,780);$form.MinimumSize=New-Object Drawing.Size(1020,700)
    $script:MainForm=$form
    $shell=New-Object PowerPlanUi.TableLayoutPanel;$shell.Dock='Fill';$shell.ColumnCount=2;$shell.RowCount=1;$shell.Name='Shell'
    [void]$shell.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',190)));[void]$shell.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
    $nav=New-UiPage;$nav.Name='Shell';$nav.Padding=New-Object Windows.Forms.Padding(16,26,12,16);$nav.Margin=New-Object Windows.Forms.Padding(0)
    $nav.Controls.Add((New-UiLabel '电源计划' 18));$nav.Controls.Add((New-UiLabel '按你的习惯运行' 9 -Muted))
    $content=New-Object Windows.Forms.Panel;$content.Dock='Fill';$content.Margin=New-Object Windows.Forms.Padding(0)
    $pages=@{};$navigation=@()
    foreach($name in @('首页','备份与恢复','外观')){
        $page=New-UiPage;$pages[$name]=$page;$content.Controls.Add($page)
        $button=New-UiButton $name
        $button.AutoSize=$false;$button.Width=160;$button.Height=46;$button.TextAlign='MiddleLeft';$button.Margin=New-Object Windows.Forms.Padding(0,8,0,4)
        $button.Add_Click({param($sender,$eventArgs) Show-MainPage $sender.Text})
        $nav.Controls.Add($button);$navigation+=$button
    }
    $nav.Controls.Add((New-UiLabel "选择计划只会查看。`r`n保存时自动备份。" 9 -Muted))
    $homePage=$pages['首页'];$active=New-UiLabel '正在读取当前计划…' 9;$active.Name='Badge';$active.Padding=New-Object Windows.Forms.Padding(10,7,10,7)
    $active.AutoSize=$false;$active.Dock='Fill';$active.TextAlign='MiddleCenter';$active.AutoEllipsis=$true
    $homePage.Controls.Add((New-UiLabel '我的电源计划' 9 -Muted))
    $header=New-UiRow @(0,200);$title=New-UiLabel '让电脑按你的习惯运行' 21;$title.Dock='Fill';$title.Margin=New-Object Windows.Forms.Padding(0,0,12,4)
    $header.Controls.Add($title,0,0);$header.Controls.Add($active,1,0);$homePage.Controls.Add($header)
    $heading=New-UiLabel '查看或调整计划' 10 -Muted;$homePage.Controls.Add($heading)
    $picker=New-Object Windows.Forms.ComboBox;$picker.DropDownStyle='DropDownList';$picker.DisplayMember='DisplayName';$picker.Margin=New-Object Windows.Forms.Padding(0,0,0,12)
    $picker.AccessibleName='选择要查看的电源计划';$script:PlanPicker=$picker;$picker.Dock='Fill';$picker.Margin=New-Object Windows.Forms.Padding(0,3,14,0)
    Initialize-UiChoice $picker
    $hint=New-UiLabel '选择只会查看，点击“使用这个计划”才会切换。' 9 -Muted
    $actions=New-UiRow @(0,158,98)
    $script:EnableButton=New-UiButton '使用这个计划' {Enable-SelectedPlan} -Primary
    $script:EditButton=New-UiButton '高级设置' {Show-EditSettingsDialog}
    $script:RefreshButton=New-UiButton '刷新' {Refresh-PlanList}
    $actions.Controls.Add($picker,0,0);$actions.Controls.Add($script:EnableButton,1,0);$actions.Controls.Add($script:RefreshButton,2,0);$homePage.Controls.Add($actions);$homePage.Controls.Add($hint)
    $section=New-UiRow @(0,220);$section.Margin=New-Object Windows.Forms.Padding(0,14,0,8)
    $section.Controls.Add((New-UiLabel '常用设置' 15),0,0);$section.Controls.Add((New-UiLabel '插电与电池分别设置' 9 -Muted),1,0);$homePage.Controls.Add($section)
    $common=New-UiFlow;$common.FlowDirection='TopDown';$common.WrapContents=$false;$common.Add_SizeChanged({Resize-CommonCards});$homePage.Controls.Add($common)
    $homePage.Controls.Add((New-UiLabel '电池值是计划中保存的配置；没有电池的设备不代表正在使用它。' 9 -Muted))
    $footer=New-UiRow @(0,140);$footer.Margin=New-Object Windows.Forms.Padding(0,12,0,18)
    $footer.Controls.Add((New-UiLabel '更多参数、隐藏设置与技术详情' 10 -Muted),0,0);$footer.Controls.Add($script:EditButton,1,0);$homePage.Controls.Add($footer)
    $manage=New-UiFlow;$manage.Visible=$false
    $manageToggle=New-UiButton '展开计划管理' { $state=$script:MainForm.Tag;$state.Management.Visible=-not $state.Management.Visible;$state.ManagementToggle.Text=if($state.Management.Visible){'收起计划管理'}else{'展开计划管理'};Resize-UiPage $state.Pages['首页'] }
    $homePage.Controls.Add($manageToggle)
    $script:CreateButton=New-UiButton '复制为新计划' {Create-CopiedPlan}
    $script:RenameButton=New-UiButton '重命名' {Rename-SelectedPlan}
    $script:DeleteButton=New-UiButton '删除计划' {Delete-SelectedPlan}
    $manage.Controls.AddRange(@($script:CreateButton,$script:RenameButton,$script:DeleteButton));$homePage.Controls.Add($manage)
    $technical=New-UiButton '技术详情' {Show-TechnicalDetails};$manage.Controls.Add($technical)
    $details=New-Object Windows.Forms.TextBox;$details.Multiline=$true;$details.ReadOnly=$true;$details.ScrollBars='Both';$details.WordWrap=$false;$script:DetailsBox=$details
    $backup=$pages['备份与恢复'];$backup.Controls.Add((New-UiLabel '备份与恢复' 22))
    $backup.Controls.Add((New-UiLabel '导出当前查看的计划，或从 .pow 文件恢复。恢复会创建一个新计划，由你决定是否启用。' 10 -Muted))
    $backupPlan=New-UiLabel '请先在首页选择计划。' 13;$backup.Controls.Add($backupPlan)
    $backupActions=New-UiFlow
    $script:ExportButton=New-UiButton '导出选中计划' {Export-SelectedPlan} -Primary
    $script:ImportButton=New-UiButton '导入计划文件' {Import-PlanFile}
    $script:RestoreButton=New-UiButton '从备份恢复' {Restore-PlanBackup}
    $backupActions.Controls.AddRange(@($script:ExportButton,$script:ImportButton,$script:RestoreButton));$backup.Controls.Add($backupActions)
    $backup.Controls.Add((New-UiLabel '自动备份位置' 14));$backup.Controls.Add((New-UiLabel (Join-Path $env:LOCALAPPDATA 'PowerPlanManager\Backups') 10 -Muted))
    $backup.Controls.Add((New-UiLabel '修改、改名和删除前先备份。权限不足时请关闭程序，以管理员身份重新运行。' 10 -Muted))
    $script:ControlPanelButton=New-UiButton '打开系统电源选项' {Open-ControlPanel};$backup.Controls.Add($script:ControlPanelButton)
    $appearancePage=$pages['外观'];$appearancePage.Controls.Add((New-UiLabel '让界面更合你的习惯' 22))
    $appearancePage.Controls.Add((New-UiLabel '配色立即预览并自动记住，只影响本程序。跟随系统会读取 Windows 应用明暗模式和强调色。' 10 -Muted))
    $appearancePage.Controls.Add((New-UiLabel '明暗模式' 13))
    $mode=New-Object Windows.Forms.ComboBox;$mode.DropDownStyle='DropDownList';$mode.DisplayMember='Name';$mode.AccessibleName='界面明暗模式'
    foreach($entry in @(@('System','跟随系统'),@('Light','浅色'),@('Dark','深色'))){$i=$mode.Items.Add([pscustomobject]@{Id=$entry[0];Name=$entry[1]});if($entry[0] -eq $script:Appearance.Mode){$mode.SelectedIndex=$i}}
    $appearancePage.Controls.Add($mode);$appearancePage.Controls.Add((New-UiLabel '颜色组合' 13))
    Initialize-UiChoice $mode
    $accent=New-Object Windows.Forms.ComboBox;$accent.DropDownStyle='DropDownList';$accent.DisplayMember='Name';$accent.AccessibleName='界面颜色组合'
    foreach($choice in $script:AccentChoices){$i=$accent.Items.Add($choice);if($choice.Id -eq $script:Appearance.Accent){$accent.SelectedIndex=$i}}
    $appearancePage.Controls.Add($accent)
    Initialize-UiChoice $accent
    $appearancePage.Controls.Add((New-UiLabel '浅色与深色都可搭配六组配色。启用 Windows 高对比度时，优先使用系统颜色。' 10 -Muted))
    $appearancePage.Controls.Add((New-UiLabel '预览：常用设置' 15));$appearancePage.Controls.Add((New-UiLabel '正文与说明、输入框和按钮会一起更新。' 10 -Muted))
    $sample=New-UiButton '这是一颗主要按钮' {Set-Status '配色预览，不会修改电源计划。'} -Primary;$appearancePage.Controls.Add($sample)
    $saveHint=New-UiLabel '外观选择会自动保存。' 10 -Muted;$appearancePage.Controls.Add($saveHint)
    $shell.Controls.Add($nav,0,0);$shell.Controls.Add($content,1,0);$form.Controls.Add($shell)
    $status=New-Object Windows.Forms.StatusStrip;$statusLabel=New-Object Windows.Forms.ToolStripStatusLabel;$statusLabel.Spring=$true;$statusLabel.TextAlign='MiddleLeft'
    $version=New-Object Windows.Forms.ToolStripStatusLabel;$version.Text='0.3.2';[void]$status.Items.Add($statusLabel);[void]$status.Items.Add($version)
    $form.Controls.Add($status);$shell.BringToFront();$script:StatusLabel=$statusLabel
    $timer=New-Object Windows.Forms.Timer;$timer.Interval=1500;$timer.Add_Tick({try{Update-AppTheme}catch{}})
    $form.Tag=[pscustomobject]@{Busy=$false;Pages=$pages;Navigation=$navigation;ActiveLabel=$active;PlanHeading=$heading;PlanHint=$hint;CommonHost=$common;HomeSettings=@();BackupPlan=$backupPlan;ModePicker=$mode;AccentPicker=$accent;AppearanceHint=$saveHint;ThemeTimer=$timer;Management=$manage;ManagementToggle=$manageToggle}
    $script:ToolbarButtons=@($script:EnableButton,$script:EditButton,$script:RefreshButton,$script:CreateButton,$script:RenameButton,$script:DeleteButton,$script:ExportButton,$script:ImportButton,$script:RestoreButton,$script:ControlPanelButton,$technical)
    $picker.Add_SelectedIndexChanged({if(-not $script:Refreshing){try{Update-PlanDetails}catch{Set-Status ('读取失败：'+$_.Exception.Message)}}})
    foreach($combo in @($mode,$accent)){$combo.Add_SelectedIndexChanged({
        $state=$script:MainForm.Tag
        if($null -eq $state.ModePicker.SelectedItem -or $null -eq $state.AccentPicker.SelectedItem){return}
        $script:Appearance.Mode=$state.ModePicker.SelectedItem.Id;$script:Appearance.Accent=$state.AccentPicker.SelectedItem.Id
        Update-AppTheme -Force
        try{Save-Appearance;$state.AppearanceHint.Text='外观已保存，下次打开仍会使用。'}catch{$state.AppearanceHint.Text='本次预览已生效，但保存失败：'+$_.Exception.Message}
    })}
    $form.Add_Shown({param($sender,$eventArgs) Update-AppTheme -Force;$sender.Tag.ThemeTimer.Start();Invoke-UiAction -Owner $sender -Action {Refresh-PlanList}})
    $form.Add_FormClosing({$script:Refreshing=$true})
    $form.Add_Disposed({param($sender,$eventArgs) $sender.Tag.ThemeTimer.Stop();$sender.Tag.ThemeTimer.Dispose();$script:DetailsBox.Dispose()})
    Show-MainPage '首页';Update-PlanButtons
    return $form
}
function Show-TechnicalDetails {
    $dialog=New-Object Windows.Forms.Form;$dialog.Text='技术详情';$dialog.StartPosition='CenterParent';$dialog.ClientSize=New-Object Drawing.Size(820,560)
    $text=New-Object Windows.Forms.TextBox;$text.Multiline=$true;$text.ReadOnly=$true;$text.ScrollBars='Both';$text.WordWrap=$false;$text.Dock='Fill';$text.Text=$script:DetailsBox.Text
    $text.Font=New-Object Drawing.Font('Consolas',10);$dialog.Controls.Add($text)
    Set-WindowPalette $dialog (Get-UiPalette)
    try{[void]$dialog.ShowDialog($script:MainForm)}finally{$dialog.Dispose()}
}
function Update-EditorFilter($Dialog) {
    if($null -eq $Dialog -or $Dialog.Tag.Loading){return}
    $state=$Dialog.Tag;Save-EditorDraft $Dialog;$state.Loading=$true
    try{
        $state.CurrentSetting=$null;$state.Grid.Rows.Clear()
        $category=$state.Categories.SelectedItem
        foreach($setting in $state.AllSettings){
            if($null -ne $category -and $category.Id -ne '' -and $setting.GroupId -ne $category.Id){continue}
            if(-not $state.IncludeHidden.Checked -and -not $state.VisibleKeys.ContainsKey((Get-SettingKey $setting))){continue}
            if($state.Search.Text.Trim() -and ($setting.Name+' '+$setting.GroupName+' '+$setting.SettingId).IndexOf($state.Search.Text.Trim(),[StringComparison]::OrdinalIgnoreCase) -lt 0){continue}
            $index=$state.Grid.Rows.Add([object[]]@((Get-FriendlySetting $setting).Name,$setting.GroupName,(Format-SettingValue $setting $setting.AcValue),(Format-SettingValue $setting $setting.DcValue),$setting.Unit,$setting.SettingId))
            $state.Grid.Rows[$index].Tag=$setting
        }
        if($state.Grid.Rows.Count -gt 0){$state.Grid.Rows[0].Selected=$true}
        $state.CountLabel.Text='共 '+$state.Grid.Rows.Count+' 项 · 保存只应用当前选中项'
    }finally{$state.Loading=$false}
    Update-SettingEditor $Dialog
}
function New-PowerEditor($Plan,[object[]]$Settings,[switch]$Common) {
    Initialize-Desktop;Initialize-UiWidgets
    $dialog=New-Object Windows.Forms.Form;$dialog.Text='高级设置 · '+$Plan.Name;$dialog.StartPosition='CenterParent'
    $dialog.Font=New-Object Drawing.Font('Microsoft YaHei UI',10);$dialog.AutoScaleMode='Dpi';$dialog.ClientSize=New-Object Drawing.Size(1160,790);$dialog.MinimumSize=New-Object Drawing.Size(1040,740)
    $layout=New-Object Windows.Forms.TableLayoutPanel;$layout.Dock='Fill';$layout.ColumnCount=2;$layout.RowCount=1;$layout.Padding=New-Object Windows.Forms.Padding(16)
    [void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',190)));[void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
    $categories=New-Object Windows.Forms.ListBox;$categories.Dock='Fill';$categories.DisplayMember='Name';$categories.IntegralHeight=$false;$categories.AccessibleName='设置分类'
    [void]$categories.Items.Add([pscustomobject]@{Id='';Name='全部设置'})
    foreach($group in @($Settings | Group-Object GroupId)){[void]$categories.Items.Add([pscustomobject]@{Id=$group.Name;Name=$group.Group[0].GroupName})}
    $categories.SelectedIndex=0;$layout.Controls.Add($categories,0,0)
    Initialize-UiChoice $categories
    $categories.BorderStyle='None'
    $right=New-Object Windows.Forms.TableLayoutPanel;$right.Dock='Fill';$right.ColumnCount=1;$right.RowCount=5;$right.Margin=New-Object Windows.Forms.Padding(20,0,0,0)
    [void]$right.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')));[void]$right.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)));[void]$right.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',230)));[void]$right.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')));[void]$right.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
    $top=New-Object Windows.Forms.TableLayoutPanel;$top.Dock='Fill';$top.AutoSize=$true;$top.ColumnCount=1;$top.RowCount=3
    $heading=New-UiLabel ('正在调整：'+$Plan.Name) 18;$heading.Dock='Fill';$top.Controls.Add($heading,0,0)
    $filters=New-UiRow @(0,190);$filters.Dock='Fill';$filters.Margin=New-Object Windows.Forms.Padding(0,0,0,10)
    $search=New-Object PowerPlanUi.SearchBox;$search.Dock='Fill';$search.AccessibleName='搜索设置名称、分类或 GUID';$search.Margin=New-Object Windows.Forms.Padding(0,2,14,0)
    $includeHidden=New-Object Windows.Forms.CheckBox;$includeHidden.Text='包含系统隐藏项';$includeHidden.AutoSize=$true;$includeHidden.Anchor='Left'
    $filters.Controls.Add($search,0,0);$filters.Controls.Add($includeHidden,1,0);$top.Controls.Add($filters,0,1)
    $count=New-UiLabel '搜索名称、分类或 GUID' 9 -Muted;$top.Controls.Add($count,0,2);$right.Controls.Add($top,0,0)
    $grid=New-Object Windows.Forms.DataGridView;$grid.Dock='Fill';$grid.ReadOnly=$true;$grid.AllowUserToAddRows=$false;$grid.AllowUserToDeleteRows=$false;$grid.AllowUserToResizeRows=$false
    $grid.MultiSelect=$false;$grid.SelectionMode='FullRowSelect';$grid.AutoGenerateColumns=$false;$grid.RowHeadersVisible=$false;$grid.AutoSizeRowsMode='AllCells';$grid.ColumnHeadersHeightSizeMode='AutoSize'
    foreach($column in @(@('设置',210),@('分类',100),@('接通电源',120),@('使用电池',120),@('单位',60),@('GUID',220))){$c=New-Object Windows.Forms.DataGridViewTextBoxColumn;$c.HeaderText=$column[0];$c.Width=$column[1];$c.SortMode='NotSortable';[void]$grid.Columns.Add($c)}
    $grid.Columns[0].AutoSizeMode='Fill';$grid.Columns[0].MinimumWidth=140;$grid.Columns[1].Visible=$false;$grid.Columns[5].Visible=$false
    $grid.DefaultCellStyle.WrapMode='True';$grid.DefaultCellStyle.Padding=New-Object Windows.Forms.Padding(8);$grid.BorderStyle='None';$grid.CellBorderStyle='SingleHorizontal';$grid.ColumnHeadersBorderStyle='None';$right.Controls.Add($grid,0,1)
    $inputs=New-Object Windows.Forms.TableLayoutPanel;$inputs.Dock='Fill';$inputs.AutoScroll=$true;$inputs.ColumnCount=2;$inputs.RowCount=6;$inputs.Padding=New-Object Windows.Forms.Padding(0,12,0,0)
    [void]$inputs.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',50)));[void]$inputs.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',50)))
    $info=New-UiLabel '' 10;$info.Dock='Fill';$inputs.Controls.Add($info,0,0);$inputs.SetColumnSpan($info,2)
    $acLabel=New-UiLabel '接通电源' 10;$dcLabel=New-UiLabel '使用电池' 10;$inputs.Controls.Add($acLabel,0,1);$inputs.Controls.Add($dcLabel,1,1)
    $acInput=New-Object Windows.Forms.ComboBox;$dcInput=New-Object Windows.Forms.ComboBox
    $acInput.Dock='Top';$dcInput.Dock='Top';$acInput.AccessibleName='接通电源的设置值';$dcInput.AccessibleName='使用电池的设置值'
    Initialize-UiChoice $acInput;Initialize-UiChoice $dcInput
    $inputs.Controls.Add($acInput,0,2);$inputs.Controls.Add($dcInput,1,2)
    $raw=New-Object Windows.Forms.CheckBox;$raw.Text='使用原始数值输入（时间单位：秒）';$raw.AutoSize=$true;$inputs.Controls.Add($raw,0,3);$inputs.SetColumnSpan($raw,2)
    $range=New-UiLabel '' 9 -Muted;$range.Dock='Fill';$inputs.Controls.Add($range,0,4);$inputs.SetColumnSpan($range,2)
    $ids=New-UiLabel '' 9 -Muted;$ids.Dock='Fill';$inputs.Controls.Add($ids,0,5);$inputs.SetColumnSpan($ids,2)
    foreach($unused in 1..6){[void]$inputs.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))}
    $inputs.Add_SizeChanged({param($sender,$eventArgs) foreach($label in $sender.Controls | Where-Object {$_ -is [Windows.Forms.Label]}){$label.MaximumSize=New-Object Drawing.Size(([Math]::Max(80,$sender.ClientSize.Width-24)),0)}})
    $right.Controls.Add($inputs,0,2)
    $visibility=New-UiFlow;$visibility.Dock='Fill';$visibility.Margin=New-Object Windows.Forms.Padding(0,6,0,12)
    $visibilityButton=New-UiButton '管理 Windows 隐藏项'
    $visibilityButton.Add_Click({param($sender,$eventArgs) $owner=$sender.FindForm();Invoke-UiAction -Owner $owner -Action {Show-VisibilityDialog $owner}})
    $visibility.Controls.Add($visibilityButton);$right.Controls.Add($visibility,0,3)
    $buttons=New-UiFlow;$buttons.Dock='Fill';$buttons.FlowDirection='RightToLeft';$buttons.WrapContents=$false;$buttons.Margin=New-Object Windows.Forms.Padding(0,8,0,0)
    $apply=New-UiButton '预览并保存这一项' -Primary;$close=New-UiButton '关闭';$close.DialogResult='Cancel'
    $buttons.Controls.AddRange(@($apply,$close));$right.Controls.Add($buttons,0,4)
    $layout.Controls.Add($right,1,0);$dialog.Controls.Add($layout);$dialog.CancelButton=$close
    if($Common){
        $dialog.Text='常用设置 · '+$Plan.Name
        $dialog.MinimumSize=New-Object Drawing.Size(760,600);$dialog.ClientSize=New-Object Drawing.Size(760,580)
        $layout.ColumnStyles[0].Width=0;$categories.Visible=$false;$right.Margin=New-Object Windows.Forms.Padding(0)
        $heading.Text=(Get-FriendlySetting $Settings[0]).Name;$filters.Visible=$false;$visibility.Visible=$false
    }
    $visibleKeys=@{};foreach($setting in $Settings){$visibleKeys[(Get-SettingKey $setting)]=$true}
    $dialog.Tag=[pscustomobject]@{Plan=$Plan;Grid=$grid;AcInput=$acInput;DcInput=$dcInput;ApplyButton=$apply;CloseButton=$close;InfoLabel=$info;RangeLabel=$range;IdLabel=$ids;RawToggle=$raw;RawInput=$false;Categories=$categories;AllSettings=$Settings;Busy=$false;Loading=$false;Closing=$false;CurrentSetting=$null;Drafts=@{};Search=$search;IncludeHidden=$includeHidden;VisibleKeys=$visibleKeys;HiddenLoaded=$false;CountLabel=$count;VisibilityButton=$visibilityButton}
    $grid.Add_SelectionChanged({param($sender,$eventArgs) $owner=$sender.FindForm();try{Update-SettingEditor $owner}catch{if($null -ne $owner -and -not $owner.IsDisposed){$owner.Tag.ApplyButton.Enabled=$false;Show-ErrorMessage $_.Exception.Message $owner}}})
    $categories.Add_SelectedIndexChanged({param($sender,$eventArgs) $owner=$sender.FindForm();Invoke-UiAction -Owner $owner -Action {Update-EditorFilter $owner}})
    $search.Add_TextChanged({param($sender,$eventArgs) Update-EditorFilter $sender.FindForm()})
    $includeHidden.Add_CheckedChanged({param($sender,$eventArgs)
        $owner=$sender.FindForm();if($owner.Tag.Loading){return}
        Invoke-UiAction -Owner $owner -Action {
            if($sender.Checked -and -not $owner.Tag.HiddenLoaded){
                try{
                    $all=@(Get-PowerSettings -Plan $owner.Tag.Plan -IncludeHidden)
                    Save-EditorDraft $owner;$owner.Tag.Loading=$true
                    $existing=@{};foreach($setting in $owner.Tag.AllSettings){$existing[(Get-SettingKey $setting)]=$setting}
                    $owner.Tag.AllSettings=@(foreach($setting in $all){$key=Get-SettingKey $setting;if($existing.ContainsKey($key)){$existing[$key]}else{$setting}});$owner.Tag.HiddenLoaded=$true
                    $owner.Tag.Categories.Items.Clear();[void]$owner.Tag.Categories.Items.Add([pscustomobject]@{Id='';Name='全部设置'})
                    foreach($group in @($all | Group-Object GroupId)){[void]$owner.Tag.Categories.Items.Add([pscustomobject]@{Id=$group.Name;Name=$group.Group[0].GroupName})}
                    $owner.Tag.Categories.SelectedIndex=0
                }catch{$owner.Tag.Loading=$true;$sender.Checked=$false;throw}finally{$owner.Tag.Loading=$false}
            }
            Update-EditorFilter $owner
        }
    })
    $raw.Add_CheckedChanged({param($sender,$eventArgs) $owner=$sender.FindForm();if($owner.Tag.Loading){return};Save-EditorDraft $owner;$owner.Tag.RawInput=$sender.Checked;Update-SettingEditor $owner})
    $apply.Add_Click({param($sender,$eventArgs) $owner=$sender.FindForm();Invoke-UiAction -Owner $owner -Action {Apply-EditorSetting $owner}})
    $dialog.Add_FormClosing({param($sender,$eventArgs)
        try{Save-EditorDraft $sender;if($sender.Tag.Drafts.Count -gt 0 -and -not(Confirm-Action -Owner $sender -Message '还有未保存的修改。放弃这些修改并关闭？')){$eventArgs.Cancel=$true;return};$sender.Tag.Closing=$true}catch{$eventArgs.Cancel=$true;Show-ErrorMessage $_.Exception.Message $sender}
    })
    $dialog.Add_Shown({param($sender,$eventArgs) Set-WindowPalette $sender (Get-UiPalette)})
    Update-EditorFilter $dialog;Set-WindowPalette $dialog (Get-UiPalette)
    return $dialog
}

function Get-VisibilityEntries($Plan) {
    $settings=@(Get-PowerSettings -Plan $Plan -IncludeHidden)
    foreach($group in @($settings | Group-Object GroupId)){
        $groupState=$null;$groupError=''
        try{$groupState=Get-PowerAttributeState $group.Name ''}catch{$groupError=$_.Exception.Message}
        $groupName=$group.Group[0].GroupName
        if($group.Name -ne 'fea3413e-7e05-4911-9a71-700331f1c294'){
            [pscustomobject]@{Name=$groupName;GroupName=$groupName;Kind='整个分类';Snapshot=$groupState;ParentHidden=$false;Count=$group.Count;Error=$groupError;Key=($group.Name+'/')}
        }
        foreach($setting in $group.Group){
            $snapshot=$null;$problem=''
            try{$snapshot=Get-PowerAttributeState $setting.GroupId $setting.SettingId}catch{$problem=$_.Exception.Message}
            [pscustomobject]@{Name=$setting.Name;GroupName=$groupName;Kind='单个设置';Snapshot=$snapshot;ParentHidden=($null -ne $groupState -and $groupState.Hidden);Count=1;Error=$problem;Key=(Get-SettingKey $setting)}
        }
    }
}
function Update-VisibilityList($Dialog,[switch]$Reload) {
    $state=$Dialog.Tag
    if($Reload){
        $state.Entries=@(Get-VisibilityEntries $state.Plan);$state.Records=@();$invalid=0
        if([IO.Directory]::Exists($script:VisibilityBackupRoot)){
            foreach($file in @(Get-ChildItem -LiteralPath $script:VisibilityBackupRoot -Filter '*.json' -File)){
                try{$record=Read-VisibilityRecord $file.FullName;if($record.Phase -ne 'Restored'){$state.Records+= [pscustomobject]@{Path=$file.FullName;Data=$record}}}catch{$invalid++}
            }
        }
        $state.Notice.Text=if($invalid){'有 '+$invalid+' 份属性备份损坏或不属于本机，已禁用这些记录的恢复。'}else{'显示标记对本机所有计划共用。解除隐藏后，请重新打开 Windows 的高级电源设置。'}
    }
    $selectedKey=if($state.Grid.SelectedRows.Count -eq 1){$state.Grid.SelectedRows[0].Tag.Key}else{''}
    $state.Loading=$true
    try{
        $state.Grid.Rows.Clear()
        foreach($entry in $state.Entries){
            if($state.Search.Text.Trim() -and ($entry.Name+' '+$entry.GroupName+' '+$entry.Key).IndexOf($state.Search.Text.Trim(),[StringComparison]::OrdinalIgnoreCase) -lt 0){continue}
            $status=if($entry.Error){'无法读取'}elseif($entry.Snapshot.Kind -notin @('Missing','DWord')){'属性类型异常'}elseif($entry.Snapshot.Hidden){'已隐藏'}elseif($entry.ParentHidden){'受分类隐藏影响'}else{'未设置隐藏标记'}
            $index=$state.Grid.Rows.Add([object[]]@($entry.Name,$entry.GroupName,$entry.Kind,$status));$state.Grid.Rows[$index].Tag=$entry
            if($entry.Key -eq $selectedKey){$state.Grid.CurrentCell=$state.Grid.Rows[$index].Cells[0]}
        }
        if($state.Grid.Rows.Count -gt 0 -and $state.Grid.SelectedRows.Count -eq 0){$state.Grid.CurrentCell=$state.Grid.Rows[0].Cells[0];$state.Grid.Rows[0].Selected=$true}
    }finally{$state.Loading=$false}
    Update-VisibilitySelection $Dialog
}
function Update-VisibilitySelection($Dialog) {
    $state=$Dialog.Tag;if($state.Loading){return}
    $state.Reveal.Enabled=$false;$state.Restore.Enabled=$false;$state.RestoreRecord=$null
    if($state.Grid.SelectedRows.Count -ne 1){$state.Detail.Text='选择一项查看影响范围。';return}
    $entry=$state.Grid.SelectedRows[0].Tag
    $state.Reveal.Enabled=($null -ne $entry.Snapshot -and $entry.Snapshot.Hidden -and $entry.Snapshot.Kind -eq 'DWord')
    $record=@($state.Records | Where-Object {($_.Data.GroupId+'/'+$_.Data.SettingId) -eq $entry.Key} | Sort-Object { $_.Data.Created } -Descending | Select-Object -First 1)
    if($record.Count -eq 1){$state.RestoreRecord=$record[0];$state.Restore.Enabled=$true}
    $scope=if($entry.Kind -eq '整个分类'){'分类操作：会改变这个分类的显示入口，涉及 '+$entry.Count+' 个本机参数；每个参数自身的隐藏标记保持原样。'}else{'仅操作这一项的显示标记，参数数值保持原样。'}
    if($entry.ParentHidden){$scope+=' 所属分类也被隐藏，需要另选该分类解除隐藏后，Windows 才可能显示。'}
    $state.Detail.Text=$entry.Name+"`r`n"+$scope+$(if($entry.Error){"`r`n"+$entry.Error}else{''})
}
function Invoke-VisibilityChange($Dialog,[switch]$Restore) {
    $state=$Dialog.Tag
    if($state.Grid.SelectedRows.Count -ne 1){return}
    $entry=$state.Grid.SelectedRows[0].Tag
    if($Restore){
        if($null -eq $state.RestoreRecord){return}
        if(-not(Confirm-Action -Owner $Dialog -Message ('恢复“'+$entry.Name+'”原来的隐藏标记？这只恢复显示属性，不修改电源参数。当前属性与备份不一致时会停止。'))){return}
        Restore-PowerSettingVisibility $state.RestoreRecord.Path
        Show-InfoMessage '原隐藏标记已恢复并读回核对。' $Dialog
    }else{
        if(-not $state.Reveal.Enabled){return}
        $message=$state.Detail.Text+"`r`n`r`n此显示属性对本机所有计划共用。先保存可恢复的原始属性，再清除隐藏标记。是否继续？"
        if(-not(Confirm-Action -Owner $Dialog -Message $message)){return}
        $path=Enable-PowerSettingVisibility $entry.Snapshot $entry.Name
        Show-InfoMessage ('隐藏标记已清除并读回核对。请重新打开 Windows 高级电源设置；硬件和系统策略仍可能限制显示。'+"`r`n属性备份："+$path) $Dialog
    }
    Update-VisibilityList $Dialog -Reload
}
function New-VisibilityDialog($Plan) {
    Initialize-Desktop;Initialize-UiWidgets
    $dialog=New-Object Windows.Forms.Form;$dialog.Text='Windows 隐藏项 · '+$Plan.Name;$dialog.StartPosition='CenterParent'
    $dialog.Font=New-Object Drawing.Font('Microsoft YaHei UI',10);$dialog.AutoScaleMode='Dpi';$dialog.ClientSize=New-Object Drawing.Size(1020,720);$dialog.MinimumSize=New-Object Drawing.Size(940,680)
    $layout=New-Object Windows.Forms.TableLayoutPanel;$layout.Dock='Fill';$layout.Padding=New-Object Windows.Forms.Padding(24);$layout.ColumnCount=1;$layout.RowCount=6
    foreach($style in @('AutoSize','AutoSize','Percent','Absolute','AutoSize','AutoSize')){[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle($style,100)))}
    $layout.RowStyles[3].Height=110
    $layout.Controls.Add((New-UiLabel '选择要在 Windows 中显示的功能' 19),0,0)
    $search=New-Object PowerPlanUi.SearchBox;$search.Dock='Fill';$search.AccessibleName='搜索隐藏设置';$search.Margin=New-Object Windows.Forms.Padding(0,4,0,16);$layout.Controls.Add($search,0,1)
    $grid=New-Object Windows.Forms.DataGridView;$grid.Dock='Fill';$grid.ReadOnly=$true;$grid.AllowUserToAddRows=$false;$grid.AllowUserToDeleteRows=$false;$grid.RowHeadersVisible=$false;$grid.MultiSelect=$false;$grid.SelectionMode='FullRowSelect';$grid.BorderStyle='None';$grid.AutoSizeRowsMode='AllCells';$grid.DefaultCellStyle.WrapMode='True';$grid.DefaultCellStyle.Padding=New-Object Windows.Forms.Padding(6)
    foreach($column in @(@('功能名称',320),@('所属分类',175),@('影响范围',100),@('显示状态',180))){$c=New-Object Windows.Forms.DataGridViewTextBoxColumn;$c.HeaderText=$column[0];$c.Width=$column[1];$c.SortMode='NotSortable';[void]$grid.Columns.Add($c)}
    $grid.Columns[0].AutoSizeMode='Fill';$layout.Controls.Add($grid,0,2)
    $grid.ColumnHeadersHeightSizeMode='AutoSize';$grid.ColumnHeadersBorderStyle='None';$grid.CellBorderStyle='SingleHorizontal'
    $detail=New-UiLabel '' 10;$detail.Dock='Fill';$detail.AutoSize=$false;$detail.Padding=New-Object Windows.Forms.Padding(0,14,0,0);$layout.Controls.Add($detail,0,3)
    $notice=New-UiLabel '' 9 -Muted;$notice.Dock='Fill';$layout.Controls.Add($notice,0,4)
    $buttons=New-UiFlow;$buttons.Dock='Fill';$buttons.FlowDirection='RightToLeft';$buttons.WrapContents=$false
    $reveal=New-UiButton '显示所选项' -Primary;$restore=New-UiButton '恢复原隐藏状态';$close=New-UiButton '关闭';$close.DialogResult='Cancel'
    $refresh=New-UiButton '刷新';$refresh.Add_Click({param($sender,$eventArgs) $owner=$sender.FindForm();Invoke-UiAction -Owner $owner -Action {Update-VisibilityList $owner -Reload}})
    $buttons.Controls.AddRange(@($reveal,$restore,$refresh,$close));$layout.Controls.Add($buttons,0,5);$dialog.Controls.Add($layout);$dialog.CancelButton=$close
    $dialog.Tag=[pscustomobject]@{Plan=$Plan;Busy=$false;Loading=$false;Search=$search;Grid=$grid;Detail=$detail;Notice=$notice;Reveal=$reveal;Restore=$restore;RestoreRecord=$null;Entries=@();Records=@()}
    $search.Add_TextChanged({param($sender,$eventArgs) Update-VisibilityList $sender.FindForm()})
    $grid.Add_SelectionChanged({param($sender,$eventArgs) Update-VisibilitySelection $sender.FindForm()})
    $reveal.Add_Click({param($sender,$eventArgs) $owner=$sender.FindForm();Invoke-UiAction -Owner $owner -Action {Invoke-VisibilityChange $owner}})
    $restore.Add_Click({param($sender,$eventArgs) $owner=$sender.FindForm();Invoke-UiAction -Owner $owner -Action {Invoke-VisibilityChange $owner -Restore}})
    Update-VisibilityList $dialog -Reload;Set-WindowPalette $dialog (Get-UiPalette)
    return $dialog
}
function Show-VisibilityDialog($Owner) {
    $dialog=New-VisibilityDialog $Owner.Tag.Plan
    try{[void]$dialog.ShowDialog($Owner)}finally{$dialog.Dispose()}
}

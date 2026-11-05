$ErrorActionPreference='Stop'
if(Get-Process AceCombat8 -ErrorAction SilentlyContinue){throw 'Close AC8 before changing features.'}
. (Join-Path $PSScriptRoot 'Feature-Settings.ps1')
$file=Join-Path $PSScriptRoot 'features.ini';$previous=Read-FeatureSettings $file
$default=if($previous.MissileMode -eq 'none'){'2'}else{'1'}
Write-Host '1. 飞控 + 导弹模块（比例引导与近炸开关）'
Write-Host '2. 仅鼠标飞控'
while($true){
 $choice=Read-Host "输入 1 或 2（回车保留 $default；Q 取消）"
 if(!$choice){$choice=$default}
 if($choice -in @('1','2')){break}
 if($choice -ieq 'Q'){throw 'Feature selection cancelled.'}
}
$value=if($choice -eq '1'){'guidance'}else{'none'}
Set-Content -LiteralPath $file -Value ('missile_mode='+$value) -Encoding UTF8
Write-Host '已保存，下次启动生效。'

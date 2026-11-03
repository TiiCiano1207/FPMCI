function Read-AC8MissileGuidance([string]$Path) {
 $defaults=[ordered]@{MSL=1.0;QAAM=1.0;SAAM=0.95;'2AAM'=0.95;'4AAM'=0.9;'6AAM'=0.9;HCAA=0.8;HPAA=0.75;HVAA=0.85;LAAM=0.9;SASM=0.9;STORY=1.0;EASY=1.0}
 if(!(Test-Path -LiteralPath $Path -PathType Leaf)){return $defaults}
 $values=[ordered]@{}
 foreach($raw in [IO.File]::ReadAllLines($Path)){
  $line=$raw.Trim().TrimStart([char]0xFEFF)
  if(!$line -or $line.StartsWith(';') -or $line.StartsWith('#')){continue}
  if($line -cnotmatch '^([A-Z0-9]+)\s*=\s*([0-9]+(?:\.[0-9]{1,3})?)$'){throw "Invalid missile guidance setting: $line"}
  $key=$Matches[1];$number=$Matches[2]
  if(!$defaults.Contains($key) -or $values.Contains($key)){throw "Unknown or duplicate missile guidance key: $key"}
  $value=[double]::Parse($number,[Globalization.CultureInfo]::InvariantCulture)
  if([double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt 0 -or $value -gt 1){throw "Missile guidance $key must be between 0 and 1."}
  $values[$key]=$value
 }
 if($values.Count -ne 13){throw 'MissileGuidance.ini must contain all 13 values.'}
 return $values
}
function Write-AC8MissileGuidance($Values,[string]$Path) {
 $lines=@('-- Generated from MissileGuidance.ini at MOD startup.','return {')
 foreach($key in $Values.Keys){$lines+=' ["'+$key+'"]='+$Values[$key].ToString('0.000',[Globalization.CultureInfo]::InvariantCulture)+','}
 $lines+='}'
 [IO.File]::WriteAllLines($Path,$lines,[Text.Encoding]::ASCII)
}

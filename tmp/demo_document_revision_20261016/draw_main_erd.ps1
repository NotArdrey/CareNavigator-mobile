$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$catalog=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../../supabase/baseline/catalog.json') -Encoding UTF8 | ConvertFrom-Json
$entities=@(
 @{name='users';x=40;y=35;fields=@('id','first_name','last_name','email','account_status')},
 @{name='hospitals';x=975;y=35;fields=@('id','hospital_name','address','verification_status')},
 @{name='doctor_schedules';x=1910;y=35;fields=@('id','doctor_id','day_of_week','starts_at','ends_at','slot_minutes','is_active')},
 @{name='patients';x=40;y=595;fields=@('id','user_id','patient_number','profile_status')},
 @{name='doctors';x=975;y=595;fields=@('id','user_id','hospital_id','display_name','specialization')},
 @{name='prescriptions';x=1910;y=595;fields=@('id','order_id','medication_name','dosage','frequency')},
 @{name='consultations';x=40;y=1155;fields=@('id','patient_id','doctor_id','appointment_date','consultation_type','status')},
 @{name='prescription_orders';x=975;y=1155;fields=@('id','consultation_id','issued_at','status')},
 @{name='medical_records';x=1910;y=1155;fields=@('id','consultation_id','title','confirmed_diagnosis','record_date')}
)
$relations=@(
 @{parent='users';child='patients';fk='user_id';points=@(@(365,311),@(365,595));label=@(390,442)},
 @{parent='users';child='doctors';fk='user_id';points=@(@(690,160),@(800,160),@(800,700),@(975,700));label=@(815,438)},
 @{parent='hospitals';child='doctors';fk='hospital_id';points=@(@(1300,267),@(1300,595));label=@(1325,440)},
 @{parent='doctors';child='doctor_schedules';fk='doctor_id';points=@(@(1625,720),@(1790,720),@(1790,180),@(1910,180));label=@(1805,440)},
 @{parent='patients';child='consultations';fk='patient_id';points=@(@(365,827),@(365,1155));label=@(390,997)},
 @{parent='doctors';child='consultations';fk='doctor_id';points=@(@(975,810),@(850,810),@(850,1280),@(690,1280));label=@(705,1050)},
 @{parent='consultations';child='prescription_orders';fk='consultation_id';points=@(@(690,1370),@(975,1370));label=@(710,1324)},
 @{parent='prescription_orders';child='prescriptions';fk='order_id';points=@(@(1300,1155),@(1300,1040),@(2235,1040),@(2235,871));label=@(1780,994)},
 @{parent='consultations';child='medical_records';fk='consultation_id';points=@(@(365,1475),@(365,1540),@(2235,1540),@(2235,1431));label=@(1450,1545)}
)
$map=@{};foreach($entity in $entities){
 $table=@($catalog.tables | Where-Object {$_.schema -eq 'public' -and $_.name -eq $entity.name})
 if($table.Count -ne 1){throw ('Unknown entity '+$entity.name)}
 foreach($field in $entity.fields){if(@($table[0].columns | Where-Object {$_.name -eq $field}).Count -ne 1){throw ('Unknown field '+$entity.name+'.'+$field)}}
 $entity.width=650;$entity.height=56+44*$entity.fields.Count;$map[$entity.name]=$entity
}
foreach($relation in $relations){
 $expected='FOREIGN KEY ('+$relation.fk+') REFERENCES '+$relation.parent+'(id)'
 if(@($catalog.constraints | Where-Object {$_.kind -eq 'f' -and $_.table -eq $relation.child -and $_.definition.StartsWith($expected)}).Count -ne 1){throw ('Unverified relationship '+$expected)}
 $column=@(($catalog.tables | Where-Object {$_.name -eq $relation.child}).columns | Where-Object {$_.name -eq $relation.fk})[0]
 $relation.optional=-not $column.notnull
 $relation.unique=@($catalog.constraints | Where-Object {$_.kind -eq 'u' -and $_.table -eq $relation.child -and $_.definition -eq ('UNIQUE ('+$relation.fk+')')}).Count -eq 1
}
$bitmap=[Drawing.Bitmap]::new(2600,1650);$g=[Drawing.Graphics]::FromImage($bitmap)
$g.Clear([Drawing.Color]::White);$g.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias;$g.TextRenderingHint=[Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$ink=[Drawing.ColorTranslator]::FromHtml('#152D43');$line=[Drawing.ColorTranslator]::FromHtml('#526D82');$fill=[Drawing.ColorTranslator]::FromHtml('#EEF3F7')
$pen=[Drawing.Pen]::new($line,3);$inkBrush=[Drawing.SolidBrush]::new($ink);$white=[Drawing.SolidBrush]::new([Drawing.Color]::White);$fillBrush=[Drawing.SolidBrush]::new($fill)
$bodyFont=[Drawing.Font]::new('Arial',29,[Drawing.FontStyle]::Regular,[Drawing.GraphicsUnit]::Pixel)
$typeFont=[Drawing.Font]::new('Arial',25,[Drawing.FontStyle]::Regular,[Drawing.GraphicsUnit]::Pixel)
$headerFont=[Drawing.Font]::new('Arial',35,[Drawing.FontStyle]::Bold,[Drawing.GraphicsUnit]::Pixel)
$labelFont=[Drawing.Font]::new('Arial',27,[Drawing.FontStyle]::Regular,[Drawing.GraphicsUnit]::Pixel)
function EndMark($endpoint,$inner,[bool]$optional,[bool]$many){
 $dx=[double]$inner[0]-$endpoint[0];$dy=[double]$inner[1]-$endpoint[1];$length=[math]::Sqrt($dx*$dx+$dy*$dy);$dx/=$length;$dy/=$length;$px=-$dy;$py=$dx
 if($many){foreach($offset in @(-12,0,12)){$g.DrawLine($pen,[single]($endpoint[0]+$px*$offset),[single]($endpoint[1]+$py*$offset),[single]($endpoint[0]+$dx*23),[single]($endpoint[1]+$dy*23))}}
 else {$g.DrawLine($pen,[single]($endpoint[0]+$dx*13+$px*12),[single]($endpoint[1]+$dy*13+$py*12),[single]($endpoint[0]+$dx*13-$px*12),[single]($endpoint[1]+$dy*13-$py*12))}
 if($optional){$cx=$endpoint[0]+$dx*37;$cy=$endpoint[1]+$dy*37;$g.FillEllipse($white,[single]($cx-8),[single]($cy-8),16,16);$g.DrawEllipse($pen,[single]($cx-8),[single]($cy-8),16,16)}
 else{$g.DrawLine($pen,[single]($endpoint[0]+$dx*30+$px*12),[single]($endpoint[1]+$dy*30+$py*12),[single]($endpoint[0]+$dx*30-$px*12),[single]($endpoint[1]+$dy*30-$py*12))}
}
foreach($relation in $relations){
 $points=@($relation.points);for($i=0;$i -lt $points.Count-1;$i++){$g.DrawLine($pen,[single]$points[$i][0],[single]$points[$i][1],[single]$points[$i+1][0],[single]$points[$i+1][1])}
 EndMark $points[0] $points[1] $relation.optional $false
 EndMark $points[-1] $points[-2] $true (-not $relation.unique)
 $size=$g.MeasureString($relation.fk,$labelFont);$g.FillRectangle($white,[single]$relation.label[0],[single]$relation.label[1],[single]$size.Width,[single]$size.Height)
 $g.DrawString($relation.fk,$labelFont,$inkBrush,[single]$relation.label[0],[single]$relation.label[1])
}
foreach($entity in $entities){
 $x=[single]$entity.x;$y=[single]$entity.y;$w=[single]$entity.width;$h=[single]$entity.height
 $g.FillRectangle($white,$x,$y,$w,$h);$g.FillRectangle($fillBrush,$x,$y,$w,56);$g.DrawRectangle($pen,$x,$y,$w,$h);$g.DrawLine($pen,$x,($y+56),($x+$w),($y+56))
 $g.DrawString($entity.name,$headerFont,$inkBrush,($x+15),($y+7))
 for($i=0;$i -lt $entity.fields.Count;$i++){
  $field=$entity.fields[$i];$column=@(($catalog.tables | Where-Object {$_.name -eq $entity.name}).columns | Where-Object {$_.name -eq $field})[0]
  $key='';if($field -eq 'id'){$key='PK'};if(@($relations | Where-Object {$_.child -eq $entity.name -and $_.fk -eq $field}).Count){$key='FK'}
  if(@($catalog.constraints | Where-Object {$_.kind -eq 'u' -and $_.table -eq $entity.name -and $_.definition -eq ('UNIQUE ('+$field+')')}).Count){$key=$(if($key){$key+'/UK'}else{'UK'})}
  $type=switch -Regex ($column.type){'^timestamp with time zone$'{'timestamptz';break};'^time without time zone$'{'time';break};'^smallint$'{'int2';break};'^integer$'{'int4';break};'^boolean$'{'bool';break};'^(account_status|verification_status|consultation_type|consultation_status)$'{'enum';break};default{$column.type}}
  $rowY=$y+63+$i*44
  $g.DrawString($key,$typeFont,$inkBrush,($x+12),$rowY);$g.DrawString($field,$bodyFont,$inkBrush,($x+108),$rowY);$g.DrawString($type,$typeFont,$inkBrush,($x+502),($rowY+2))
 }
}
$g.DrawString('PK primary key    FK shown foreign key    UK unique key    Circle optional    Bar one    Crow foot many',$labelFont,$inkBrush,40,1600)
$bitmap.Save((Join-Path $PSScriptRoot 'main_feature_erd.png'),[Drawing.Imaging.ImageFormat]::Png)
@{tables=$entities;relationships=$relations;source='supabase/baseline/catalog.json';scope='Selected columns and nine declared foreign keys; operational, authorization and external platform tables omitted.'}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'main-feature-erd-model.json') -Encoding UTF8
$g.Dispose();$bitmap.Dispose();$pen.Dispose();$inkBrush.Dispose();$white.Dispose();$fillBrush.Dispose();$bodyFont.Dispose();$typeFont.Dispose();$headerFont.Dispose();$labelFont.Dispose()
Write-Output 'Validated and rendered 9 entities and 9 relationships from the baseline catalog.'

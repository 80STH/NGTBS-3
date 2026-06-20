# tools/gen_pngs.ps1
# Generates placeholder PNGs into assets/png/ using GDI+ (no Love2D required).
# Re-run:  powershell -ExecutionPolicy Bypass -File tools/gen_pngs.ps1

Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$out  = Join-Path $root 'assets\png'
New-Item -ItemType Directory -Force -Path $out | Out-Null

function New-Bit($w,$h){ New-Object System.Drawing.Bitmap -ArgumentList ([int]$w),([int]$h) }
function Open-G($b){ $g=[System.Drawing.Graphics]::FromImage($b); $g.SmoothingMode=[System.Drawing.Drawing2D.SmoothingMode]::AntiAlias; $g.TextRenderingHint=[System.Drawing.Text.TextRenderingHint]::AntiAlias; $g.Clear([System.Drawing.Color]::Transparent); return $g }
function C($r,$g,$bl,$a=255){ [System.Drawing.Color]::FromArgb([int]$a,[int]$r,[int]$g,[int]$bl) }
function br($col){ New-Object System.Drawing.SolidBrush($col) }
function pn($col,$w=1){ New-Object System.Drawing.Pen($col,$w) }
function FillEl($g,$b,$x,$y,$w,$h){ $g.FillEllipse($b,$x,$y,$w,$h) }
function DrawEl($g,$p,$x,$y,$w,$h){ $g.DrawEllipse($p,$x,$y,$w,$h) }
function DrawLn($g,$p,$x1,$y1,$x2,$y2){ $g.DrawLine($p,$x1,$y1,$x2,$y2) }
function FillRc($g,$b,$x,$y,$w,$h){ $g.FillRectangle($b,$x,$y,$w,$h) }
function FillPl($g,$b,$pts){ $g.FillPolygon($b,$pts) }
function DrawPl($g,$p,$pts){ $g.DrawPolygon($p,$pts) }
function Save($b,$name){ $p=Join-Path $out ($name+'.png'); $b.Save($p,[System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose(); Write-Output "  $name.png" }

# ---------- creatures ----------
function Draw-Creature($name,$r,$g,$bl,$emblem){
    $S=96; $b=New-Bit $S $S; $gx=Open-G $b
    $cx=$S/2; $cy=$S/2+2; $rad=$S/2-4
    FillEl $gx (br (C 0 0 0 90)) ($cx-$rad*0.8) ($S-7) ($rad*1.6) ($rad*0.5)
    FillEl $gx (br (C ($r*0.6) ($g*0.6) ($bl*0.6))) ($cx-$rad) ($cy-$rad) ($rad*2) ($rad*2)
    FillEl $gx (br (C $r $g $bl)) ($cx-$rad+3) ($cy-$rad+3) ($rad*2-6) ($rad*2-6)
    FillEl $gx (br (C 255 255 255 45)) ($cx-$rad*0.6) ($cy-$rad*0.7) ($rad*0.8) ($rad*0.4)
    DrawEl $gx (pn (C 0 0 0 130) 1.5) ($cx-$rad) ($cy-$rad) ($rad*2) ($rad*2)
    $er=$rad*0.16
    FillEl $gx (br ([System.Drawing.Color]::White)) ($cx-$rad*0.35-$er) ($cy-$rad*0.1-$er) ($er*2) ($er*2)
    FillEl $gx (br ([System.Drawing.Color]::White)) ($cx+$rad*0.35-$er) ($cy-$rad*0.1-$er) ($er*2) ($er*2)
    $pr=$rad*0.07
    FillEl $gx (br ([System.Drawing.Color]::Black)) ($cx-$rad*0.35-$pr) ($cy-$rad*0.08-$pr) ($pr*2) ($pr*2)
    FillEl $gx (br ([System.Drawing.Color]::Black)) ($cx+$rad*0.35-$pr) ($cy-$rad*0.08-$pr) ($pr*2) ($pr*2)
    $ep = pn ([System.Drawing.Color]::White) 2
    if($emblem -eq 'melee'){
        DrawLn $gx $ep ($cx+$rad*0.5) ($cy-$rad*0.7) ($cx+$rad*0.5) ($cy+$rad*0.5)
        DrawLn $gx $ep ($cx+$rad*0.3) ($cy+$rad*0.4) ($cx+$rad*0.7) ($cy+$rad*0.4)
    } elseif($emblem -eq 'ranged'){
        DrawLn $gx $ep ($cx-$rad*0.4) ($cy+$rad*0.5) ($cx+$rad*0.6) ($cy-$rad*0.5)
        DrawLn $gx $ep ($cx+$rad*0.6) ($cy-$rad*0.5) ($cx+$rad*0.2) ($cy-$rad*0.5)
        DrawLn $gx $ep ($cx+$rad*0.6) ($cy-$rad*0.5) ($cx+$rad*0.6) ($cy-$rad*0.1)
    } elseif($emblem -eq 'caster'){
        DrawLn $gx $ep ($cx+$rad*0.5) ($cy-$rad*0.7) ($cx+$rad*0.5) ($cy+$rad*0.5)
        FillEl $gx (br (C 180 130 255)) ($cx+$rad*0.5-6) ($cy-$rad*0.8-6) 12 12
    } elseif($emblem -eq 'rod'){
        DrawLn $gx $ep $cx ($cy-$rad*0.8) $cx ($cy+$rad*0.8)
        FillEl $gx (br (C 220 180 90)) ($cx-7) ($cy-$rad*0.9-7) 14 14
    }
    $gx.Dispose(); Save $b $name
}

$creatures = @(
  @{n='Warrior';r=216;g=89;b=63;e='melee'},    @{n='Puncher';r=63;g=204;b=89;e='melee'},
  @{n='Rogue';r=63;g=128;b=216;e='ranged'},     @{n='Summoner';r=204;g=63;b=204;e='caster'},
  @{n='Summoned';r=153;g=89;b=230;e='caster'},  @{n='Zombie';r=89;g=166;b=63;e='melee'},
  @{n='PoisonousZombie';r=115;g=191;b=76;e='melee'}, @{n='Ghost';r=178;g=115;b=242;e='ranged'},
  @{n='Lich';r=204;g=76;b=204;e='caster'},      @{n='Brute';r=204;g=115;b=51;e='melee'},
  @{n='Lancer';r=140;g=102;b=51;e='melee'},     @{n='BogShaman';r=76;g=128;b=102;e='caster'},
  @{n='Raider';r=178;g=76;b=76;e='melee'},      @{n='Dervish';r=216;g=178;b=63;e='melee'},
  @{n='Crusher';r=127;g=76;b=63;e='melee'},     @{n='SummoningRod';r=166;g=127;b=63;e='rod'},
  @{n='PowerLich';r=76;g=25;b=89;e='caster'}
)
Write-Output "creatures:"
foreach($c in $creatures){ Draw-Creature $c.n $c.r $c.g $c.b $c.e }

# ---------- buildings ----------
function Draw-Building($name,$draw){ $S=96; $b=New-Bit $S $S; $gx=Open-G $b; & $draw $gx $S; $gx.Dispose(); Save $b $name }

Draw-Building 'SuperMountain' { param($gx,$S)
  FillPl $gx (br (C 115 102 89)) @([System.Drawing.PointF]::new(6,$S-6),[System.Drawing.PointF]::new($S/2,8),[System.Drawing.PointF]::new($S-6,$S-6))
  FillPl $gx (br (C 148 133 117)) @([System.Drawing.PointF]::new(6,$S-6),[System.Drawing.PointF]::new($S/2,8),[System.Drawing.PointF]::new($S/2,$S-6))
  FillPl $gx (br (C 242 242 255)) @([System.Drawing.PointF]::new($S/2-6,8),[System.Drawing.PointF]::new($S/2+6,8),[System.Drawing.PointF]::new($S/2,22))
}
Draw-Building 'WeakMountain' { param($gx,$S)
  FillPl $gx (br (C 127 115 89)) @([System.Drawing.PointF]::new(8,$S-8),[System.Drawing.PointF]::new($S/2,14),[System.Drawing.PointF]::new($S-8,$S-8))
  FillPl $gx (br (C 153 140 115)) @([System.Drawing.PointF]::new(8,$S-8),[System.Drawing.PointF]::new($S/2,14),[System.Drawing.PointF]::new($S/2,$S-8))
  FillRc $gx (br (C 89 76 63)) 6 ($S-10) ($S-12) 4
}
Draw-Building 'SmallBuilding' { param($gx,$S)
  FillRc $gx (br (C 178 140 89)) 12 30 ($S-24) ($S-36)
  FillPl $gx (br (C 153 63 38)) @([System.Drawing.PointF]::new(8,30),[System.Drawing.PointF]::new($S/2,16),[System.Drawing.PointF]::new($S-8,30))
  FillRc $gx (br (C 217 230 255)) 20 40 10 12
}
Draw-Building 'BigBuilding' { param($gx,$S)
  FillRc $gx (br (C 127 140 153)) 8 24 ($S-16) ($S-30)
  FillRc $gx (br (C 102 115 127)) 8 20 ($S-16) 8
  for($row=0;$row -lt 2;$row++){ for($col=0;$col -lt 3;$col++){ FillRc $gx (br (C 204 217 255)) (18+$col*20) (36+$row*22) 10 12 } }
}
Draw-Building 'Tower' { param($gx,$S)
  FillRc $gx (br (C 140 127 115)) ($S/4) 20 ($S/2) ($S-26)
  FillRc $gx (br (C 115 102 89)) ($S/4-4) 20 ($S/2+8) 8
  FillRc $gx (br (C 153 140 127)) ($S/4-6) 16 ($S/2+12) 6
  FillEl $gx (br (C 255 178 76)) ($S/2-6) ($S/2-6) 12 12
}
Draw-Building 'Locomotive' { param($gx,$S)
  FillRc $gx (br (C 76 38 25)) 10 30 ($S-20) ($S-40)
  FillRc $gx (br (C 127 51 25)) 10 26 ($S-20) 8
  FillRc $gx (br (C 255 204 51)) ($S/2-10) 38 20 12
  FillEl $gx (br (C 51 51 51)) 13 ($S-19) 14 14
  FillEl $gx (br (C 51 51 51)) ($S-27) ($S-19) 14 14
}
Draw-Building 'TrainCar' { param($gx,$S)
  FillRc $gx (br (C 153 51 38)) 8 30 ($S-16) ($S-40)
  FillRc $gx (br (C 102 30 20)) 6 28 ($S-12) 6
  FillRc $gx (br (C 204 153 102)) 18 40 12 12
  FillRc $gx (br (C 204 153 102)) ($S-30) 40 12 12
  FillEl $gx (br (C 76 25 12)) 12 ($S-18) 12 12
  FillEl $gx (br (C 76 25 12)) ($S-24) ($S-18) 12 12
}

# ---------- terrain (hex-shaped) ----------
$S0=64; $CW=128; $CH=148; $CX=64; $CY=70
function HexPts($size){ $pts=@(); for($i=0;$i -lt 6;$i++){ $a=[Math]::PI/180*(60*$i-30); $pts+=[System.Drawing.PointF]::new(($CX+$size*[Math]::Cos($a)),($CY+$size*[Math]::Sin($a))) }; return $pts }
function Draw-Terrain($id,$r,$g,$bl,$pattern){
    $b=New-Bit $CW $CH; $gx=Open-G $b
    FillPl $gx (br (C $r $g $bl)) (HexPts $S0)
    FillPl $gx (br (C 0 0 0 28)) (HexPts $S0)
    FillPl $gx (br (C ([int][Math]::Min(255,$r+20)) ([int][Math]::Min(255,$g+20)) ([int][Math]::Min(255,$bl+20))) ) (HexPts ($S0*0.6))
    if($pattern -eq 'water'){ $p=pn (C 140 191 255 140) 2; for($i=-2;$i -le 2;$i++){ DrawLn $gx $p ($CX-28) ($CY+$i*14) ($CX+28) ($CY+$i*14+4) } }
    elseif($pattern -eq 'lava'){ $rnd=New-Object System.Random(1); for($i=0;$i -lt 6;$i++){ $a=$rnd.NextDouble()*6.28; $d=$rnd.NextDouble()*38; FillEl $gx (br (C 255 153 25 200)) ($CX+[Math]::Cos($a)*$d-4) ($CY+[Math]::Sin($a)*$d*0.6-4) 8 8 } }
    elseif($pattern -eq 'rail'){ $p=pn (C 51 51 51) 2; DrawLn $gx $p ($CX-30) ($CY-18) ($CX+30) ($CY-18); DrawLn $gx $p ($CX-30) ($CY+18) ($CX+30) ($CY+18); for($i=-2;$i -le 2;$i++){ FillRc $gx (br (C 127 102 76)) ($CX+$i*14-2) ($CY-22) 4 44 } }
    DrawPl $gx (pn (C 0 0 0 90) 1.5) (HexPts $S0)
    $gx.Dispose(); Save $b ("terrain_$id")
}
Write-Output "terrain:"
Draw-Terrain 'grass' 76 140 63 'grass'
Draw-Terrain 'dirt' 115 89 56 'dirt'
Draw-Terrain 'sand' 204 184 115 'sand'
Draw-Terrain 'stone' 127 127 140 'stone'
Draw-Terrain 'snow' 217 224 242 'snow'
Draw-Terrain 'swamp' 76 96 71 'swamp'
Draw-Terrain 'water' 51 102 191 'water'
Draw-Terrain 'underwater_mines' 30 63 115 'water'
Draw-Terrain 'lava' 191 63 25 'lava'
Draw-Terrain 'railway' 89 81 76 'rail'
Draw-Terrain 'emptiness' 12 12 20 'void'

# ---------- status icons ----------
function Draw-Status($name,$draw){ $S=32; $b=New-Bit $S $S; $gx=Open-G $b; & $draw $gx $S; $gx.Dispose(); Save $b ("status_$name") }

Draw-Status 'fire' { param($gx,$S)
  FillPl $gx (br (C 255 102 25)) @([System.Drawing.PointF]::new(16,4),[System.Drawing.PointF]::new(22,24),[System.Drawing.PointF]::new(10,24))
  FillPl $gx (br (C 255 217 51)) @([System.Drawing.PointF]::new(16,10),[System.Drawing.PointF]::new(20,24),[System.Drawing.PointF]::new(12,24))
}
Draw-Status 'acid' { param($gx,$S) FillEl $gx (br (C 127 230 51)) 6 8 20 20; FillEl $gx (br (C 204 255 102)) 10 12 6 6 }
Draw-Status 'decay' { param($gx,$S) for($i=0;$i -lt 5;$i++){ FillEl $gx (br (C 127 76 127)) (8+$i*4) 14 4 4 } }
Draw-Status 'root' { param($gx,$S) FillPl $gx (br (C 115 76 38)) @([System.Drawing.PointF]::new(16,4),[System.Drawing.PointF]::new(14,28),[System.Drawing.PointF]::new(18,28)) }
Draw-Status 'slow' { param($gx,$S) DrawEl $gx (pn (C 76 127 230) 2) 6 6 20 20; DrawLn $gx (pn (C 76 127 230) 2) 16 16 16 10; DrawLn $gx (pn (C 76 127 230) 2) 16 16 21 16 }
Draw-Status 'empowered' { param($gx,$S) FillPl $gx (br (C 255 217 51)) @([System.Drawing.PointF]::new(16,4),[System.Drawing.PointF]::new(19,13),[System.Drawing.PointF]::new(28,16),[System.Drawing.PointF]::new(19,19),[System.Drawing.PointF]::new(16,28),[System.Drawing.PointF]::new(13,19),[System.Drawing.PointF]::new(4,16),[System.Drawing.PointF]::new(13,13)) }
Draw-Status 'dig' { param($gx,$S) FillEl $gx (br (C 102 76 51)) 4 14 24 14; FillEl $gx (br (C 51 38 25)) 8 12 16 8 }
Draw-Status 'heart' { param($gx,$S) FillPl $gx (br (C 255 76 102)) @([System.Drawing.PointF]::new(16,26),[System.Drawing.PointF]::new(6,14),[System.Drawing.PointF]::new(10,8),[System.Drawing.PointF]::new(16,12),[System.Drawing.PointF]::new(22,8),[System.Drawing.PointF]::new(26,14)) }
Draw-Status 'mana' { param($gx,$S) FillPl $gx (br (C 102 153 255)) @([System.Drawing.PointF]::new(16,4),[System.Drawing.PointF]::new(26,26),[System.Drawing.PointF]::new(6,26)) }

Write-Output "done -> $out"


param([string]$PortName,[int]$Baud,[string]$OutputPath,[int]$Seconds)
$enc = [System.Text.Encoding]::GetEncoding('ISO-8859-1')
$port = [System.IO.Ports.SerialPort]::new($PortName,$Baud,[System.IO.Ports.Parity]::None,8,[System.IO.Ports.StopBits]::One)
$port.Handshake=[System.IO.Ports.Handshake]::None
$port.ReadTimeout=200
$port.WriteTimeout=200
$port.DtrEnable=$false
$port.RtsEnable=$false
$bytes=[System.Collections.Generic.List[byte]]::new()
try {
  $port.Open(); $port.DiscardInBuffer(); $port.DiscardOutBuffer()
  $deadline=[DateTime]::UtcNow.AddSeconds($Seconds)
  while([DateTime]::UtcNow -lt $deadline){
    try {
      $avail=$port.BytesToRead
      if($avail -gt 0){
        $chunk=New-Object byte[] $avail
        $read=$port.Read($chunk,0,$avail)
        for($i=0;$i -lt $read;++$i){ [void]$bytes.Add($chunk[$i]) }
      } else { Start-Sleep -Milliseconds 10 }
    } catch [System.TimeoutException] {}
  }
} finally { if($port.IsOpen){$port.Close()}; $port.Dispose() }
[System.IO.File]::WriteAllBytes($OutputPath,$bytes.ToArray())
$ascii=$enc.GetString($bytes.ToArray())
$sampleCount=[Math]::Min($bytes.Count,256)
$printable=0
for($i=0;$i -lt $sampleCount;++$i){ $v=[int]$bytes[$i]; if(($v -eq 9)-or($v -eq 10)-or($v -eq 13)-or(($v -ge 0x20)-and($v -le 0x7E))){$printable++} }
$ratio=if($sampleCount -gt 0){ [double]$printable/[double]$sampleCount } else { 0.0 }
Write-Host ("BAUD={0} BYTES={1} PRINTABLE_RATIO={2:F3} HAS_PROBE={3}" -f $Baud,$bytes.Count,$ratio,$ascii.Contains('UART1_PROBE'))

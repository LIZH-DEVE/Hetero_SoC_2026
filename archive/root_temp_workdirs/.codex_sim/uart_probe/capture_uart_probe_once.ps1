param(
    [string]$PortName,
    [int]$Baud,
    [string]$OutputPath,
    [int]$Seconds = 4
)
$encoding = [System.Text.Encoding]::GetEncoding('ISO-8859-1')
$port = [System.IO.Ports.SerialPort]::new($PortName, $Baud, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$port.Handshake = [System.IO.Ports.Handshake]::None
$port.ReadTimeout = 200
$port.WriteTimeout = 200
$port.DtrEnable = $false
$port.RtsEnable = $false
$port.Encoding = $encoding
$bytes = [System.Collections.Generic.List[byte]]::new()
try {
    $port.Open()
    $port.DiscardInBuffer()
    $port.DiscardOutBuffer()
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $available = $port.BytesToRead
            if ($available -gt 0) {
                $chunk = New-Object byte[] $available
                $read = $port.Read($chunk, 0, $available)
                for ($i = 0; $i -lt $read; ++$i) { [void]$bytes.Add($chunk[$i]) }
            } else {
                Start-Sleep -Milliseconds 25
            }
        } catch [System.TimeoutException] {}
    }
} finally {
    if ($port.IsOpen) { $port.Close() }
    $port.Dispose()
}
[System.IO.File]::WriteAllBytes($OutputPath, $bytes.ToArray())
$ascii = $encoding.GetString($bytes.ToArray())
Write-Host ("CAPTURE_BYTES={0}" -f $bytes.Count)
Write-Host ("CONTAINS_UART0_PROBE={0}" -f $ascii.Contains('UART0_PROBE'))
$preview = if ($ascii.Length -gt 240) { $ascii.Substring(0,240) } else { $ascii }
$preview = $preview -replace "`r", '<CR>' -replace "`n", '<LF>'
Write-Host ("PREVIEW={0}" -f $preview)

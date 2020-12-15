function Invoke-Process
{
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $false, Position = 0)]
        [string]$FileName = "pwsh.exe",
        [Parameter(Mandatory = $false, Position = 1)]
        [string]$Arguments = "",
        [Parameter(Mandatory = $false, Position = 2)]
        [string]$WorkingDirectory = "$(Get-Location)",
        [Parameter(Mandatory = $false, Position = 3)]
        [TimeSpan]$Timeout = [System.TimeSpan]::FromMinutes(2),
        [Parameter(Mandatory = $false, Position = 4)]
        [System.Diagnostics.ProcessPriorityClass]$Priority = [System.Diagnostics.ProcessPriorityClass]::Normal
    )
    end
    {
        try
        {
            # new Process
            $process = NewProcess -FileName $FileName -Arguments $Arguments -WorkingDirectory $WorkingDirectory
            # Event Handler for Output
            $stdout = New-Object -TypeName System.Text.StringBuilder
            $stderr = New-Object -TypeName System.Text.StringBuilder
            $scripBlock = 
            {
                $x = $Event.SourceEventArgs.Data
                if (-not [String]::IsNullOrEmpty($x))
                {
                    [System.Console]::WriteLine($x)
                    $Event.MessageData.AppendLine($x)
                }
            }
            $stdEvent = Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -Action $scripBlock -MessageData $stdout
            $errorEvent = Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action $scripBlock -MessageData $stderr
            # execution
            $process.Start() > $null
            $process.PriorityClass = $Priority
            $process.BeginOutputReadLine()
            $process.BeginErrorReadLine()
            # wait for complete
            "Waiting for command complete. It will Timeout in {0}ms" -f $Timeout.TotalMilliseconds | VerboseOutput
            $isTimeout = $false
            if (-not $Process.WaitForExit($Timeout.TotalMilliseconds))
            {
                $isTimeout = $true
                "Timeout detected for {0}ms. Kill process immediately" -f $Timeout.TotalMilliseconds | VerboseOutput
                $Process.Kill()
            }
            $Process.WaitForExit()
            $Process.CancelOutputRead()
            $Process.CancelErrorRead()
            # verbose Event Result
            $stdEvent, $errorEvent | VerboseOutput
            # Unregister Event to recieve Asynchronous Event output (You should call before process.Dispose())
            Unregister-Event -SourceIdentifier $stdEvent.Name
            Unregister-Event -SourceIdentifier $errorEvent.Name
            # verbose Event Result
            $stdEvent, $errorEvent | VerboseOutput
            # Get Process result
            return GetCommandResult -Process $process -StandardOutput $stdout -StandardError $stderr -IsTimeOut $isTimeout
        }
        finally
        {
            if ($null -ne $process){ $process.Dispose() }
            if ($null -ne $stdEvent){ $stdEvent.StopJob(); $stdEvent.Dispose() }
            if ($null -ne $errorEvent){ $errorEvent.StopJob(); $errorEvent.Dispose() }
        }
    }
    begin
    {
        function NewProcess
        {
            [OutputType([System.Diagnostics.Process])]
            [CmdletBinding()]
            param
            (
                [parameter(Mandatory = $true)]
                [string]$FileName,
                [parameter(Mandatory = $false)]
                [string]$Arguments,
                [parameter(Mandatory = $false)]
                [string]$WorkingDirectory
            )
            "Execute command : '{0} {1}', WorkingSpace '{2}'" -f $FileName, $Arguments, $WorkingDirectory | VerboseOutput
            # ProcessStartInfo
            $psi = New-object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $FileName
            $psi.Arguments += $Arguments
            $psi.WorkingDirectory = $WorkingDirectory
            $psi.CreateNoWindow = $true
            $psi.LoadUserProfile = $true
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            # Set Process
            $process = New-Object System.Diagnostics.Process 
            $process.StartInfo = $psi
            $process.EnableRaisingEvents = $true
            return $process
        }
        function GetCommandResult
        {
            [OutputType([PSCustomObject])]
            [CmdletBinding()]
            param
            (
                [parameter(Mandatory = $true)]
                [System.Diagnostics.Process]$Process,
                [parameter(Mandatory = $true)]
                [System.Text.StringBuilder]$StandardOutput,
                [parameter(Mandatory = $true)]
                [System.Text.StringBuilder]$StandardError,
                [parameter(Mandatory = $true)]
                [Bool]$IsTimeout
            )
            'Get command result string.' | VerboseOutput
            return [PSCustomObject]@{
                ExitCode = $process.ExitCode
                StandardOutput = $StandardOutput.ToString().Trim()
                StandardError = $StandardError.ToString().Trim()
                IsTimeOut = $IsTimeout
            }
        }
        filter VerboseOutput
        {
            $_ | Out-String -Stream | Write-Verbose
        }
    }
}
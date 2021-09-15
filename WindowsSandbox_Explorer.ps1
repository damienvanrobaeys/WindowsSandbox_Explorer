#***************************************************************************************************************
# Author: Damien VAN ROBAEYS
# Website: http://www.systanddeploy.com
# Twitter: https://twitter.com/syst_and_deploy
# GitHub path: https://twitter.com/syst_and_deploy
#***************************************************************************************************************

Param
 (
	[String]$Content_to_add
 )
 
# Check if tool is executed with admin rights
[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | out-null
$Run_As_Admin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
If($Run_As_Admin -eq $False)
	{
		# [System.Windows.Forms.MessageBox]::Show("Please run the tool with admin rights :-)")
		write-warning "Please run the tool with admin rights :-)"	
		break		
	}
Else
	{	 
		# Check if Windows Sandbox feature is installed
		$Is_Sandbox_Installed = (Get-WindowsOptionalFeature -online | where {$_.featurename -eq "Containers-DisposableClientVM"}).state
		If($Is_Sandbox_Installed -eq "Disabled")
			{
				# [System.Windows.Forms.MessageBox]::Show("The feature Windows Sandbox is not installed !!!")	
				write-warning "The feature Windows Sandbox is not installed !!!"					
			}
		Else
			{	
				$Progress_Activity = "Configuring the default Windows Sandbox"
				write-progress -activity $Progress_Activity -percentcomplete 5;	
							
				# Stop the the Container service
				$Check_Service = Get-Service CmService -ea silentlycontinue
				If($Check_Service -ne $null)
					{
						Try
							{
								$Check_Service | stop-service -force
								write-host "Step 1/7: CmService has been stopped"							
							}
						Catch
							{
								write-warning "Step 1/7: Can not stop the service CmService"							
								Break
							}
					}
				Else
					{
						write-warning "Step 1/7: Can not find the service CmService"							
						Break					
					}
					
				write-progress -activity $Progress_Activity  -percentcomplete 20;
					
				# Mount the default Windows Sandbox VHDX file
				$BaseImages_Path = "C:\ProgramData\Microsoft\Windows\Containers\BaseImages"
				If(!(test-path $BaseImages_Path))
					{
						write-warning "Can not find: $BaseImages_Path"							
						Break					
					}
				$Get_BaseImage_Content = Get-Childitem $BaseImages_Path
				$Get_GUID = $Get_BaseImage_Content.Name
				$Get_VHDX_Path = "$BaseImages_Path\$Get_GUID"
				$Baselayer_VHDX = "$Get_VHDX_Path\BaseLayer.vhdx"
				
				Try
					{
						Mount-VHD -Path $Baselayer_VHDX
						# Mount-DiskImage -ImagePath $Baselayer_VHDX						
						write-host "Step 2/7: Default Sandbox has been mounted"					
					}
				Catch
					{
						write-warning "Step 2/7: Default Sandbox has been mounted"
						Break
					}
				
				write-progress -activity $Progress_Activity  -percentcomplete 35;
								
				# Find the mounted VHDX drive letter
				$Get_VHDX_Volume = get-volume | Where {$_.FileSystemLabel -eq "PortableBaseLayer"}

				$Get_Baselayer_Drive = $Get_VHDX_Volume.DriveLetter + ":"
				$Sandbox_Files = "$Get_Baselayer_Drive\Files"
				$Sandbox_Hives = "$Get_Baselayer_Drive\Hives"

				# Check if the parameter Content_to_add is filled
				If($Content_to_add -eq $null)
					{
						write-warning "Parameter Content_to_add is empty"
						write-warning "There is nothing to add in the default Windows Sandbox"
						Break
					}
					
				# Copy explorer content from the path in Content_to_add
				$Get_Explorer_Content = get-childitem $Content_to_add -Recurse | where {$_.Name -ne "Sandbox_registry_content.xml"}
				If($Get_Explorer_Content.count -gt 0)
					{
						copy-item "$Content_to_add\*" $Sandbox_Files -Recurse -Force
						write-host "Step 3/7: Explorer content has been copied"							
					}
				Else
					{
						write-host "Step 3/7: Skipped (nothing to copy)"						
					
					}											
				
				# Add registry content in the Sandbox if needed
				$Registry_content_file = "$Content_to_add\Sandbox_registry_content.xml"
				If(test-path $Registry_content_file)
					{						
						$Sandbox_registry_content = [xml](get-content $Registry_content_file)
						$Get_registry_content = $Sandbox_registry_content.Registry_Keys.Registry_Key
						$Check_Registry_content = $Get_registry_content.Reg_Path
						If($Check_Registry_content -ne $null)
							{
								$WDAGUtilityAccount_NTUser = "$Sandbox_Files\Users\WDAGUtilityAccount\ntuser.dat"
								$Test_Hive = "HKLM\Test"
								
								# Load the Sandbox registry hive												
								Try
									{
										reg load $Test_Hive $WDAGUtilityAccount_NTUser | out-null	
										write-host "Step 4/7: Registry hive has been loaded"				
									}
								Catch
									{
										write-warning "Step 4/7: Can not load the registry hive"
										Break
									}				

								write-progress -activity $Progress_Activity  -percentcomplete 45;

								ForEach($Reg_Key in $Get_registry_content)
									{
										$Get_Reg_Path = $Reg_Key.Reg_Path
										$Get_Reg_PropertyType = $Reg_Key.Reg_PropertyType
										$Get_Reg_Property = $Reg_Key.Reg_Property
										$Get_Reg_Value = $Reg_Key.Reg_Value
										
										If(!(test-path "HKLM:\Test\$Get_Reg_Path"))
											{
												New-Item -Path "HKLM:\test\$Get_Reg_Path" -force | out-null		
											}
										New-ItemProperty -Path "HKLM:\test\$Get_Reg_Path" -Name $Get_Reg_Property -Value $Get_Reg_Value  -PropertyType $Get_Reg_PropertyType -Force | out-null	
									}
								write-host "Step 5/7: Registry content have been added"				
												
								# Unload the Sandbox registry hive												
								write-progress -activity $Progress_Activity  -percentcomplete 70;	
								reg unload $Test_Hive | out-null	
								write-host "Step 6/7: Registry hive has been unloaded"							
							}
						Else
							{
								write-host "Step 4/7: Skipped (no registry content to add)"				
								write-host "Step 5/7: Skipped (no registry content to add)"				
								write-host "Step 6/7: Skipped (no registry content to add)"												
							}
					}
				Else
					{
						write-host "Step 4/7: Skipped (no registry content to add)"				
						write-host "Step 5/7: Skipped (no registry content to add)"				
						write-host "Step 6/7: Skipped (no registry content to add)"												
					}					
	
				write-progress -activity $Progress_Activity  -percentcomplete 90;						
				Dismount-VHD -Path $Baselayer_VHDX | out-null	
				# Dismount-DiskImage -ImagePath $Baselayer_VHDX				
				write-host "Step 7/7: Default Sandbox has been unmounted"								
				write-progress -activity $Progress_Activity  -percentcomplete 100;	
				write-host "You can now use your customized Windows Sandbox :-)"
		}
	}

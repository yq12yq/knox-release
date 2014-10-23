### Licensed to the Apache Software Foundation (ASF) under one or more
### contributor license agreements.  See the NOTICE file distributed with
### this work for additional information regarding copyright ownership.
### The ASF licenses this file to You under the Apache License, Version 2.0
### (the "License"); you may not use this file except in compliance with
### the License.  You may obtain a copy of the License at
###
###     http://www.apache.org/licenses/LICENSE-2.0
###
### Unless required by applicable law or agreed to in writing, software
### distributed under the License is distributed on an "AS IS" BASIS,
### WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
### See the License for the specific language governing permissions and
### limitations under the License.

###
### A set of basic PowerShell routines that can be used to install and
### manage Hadoop services on a single node. For use-case see install.ps1.
###

###
### Global variables
###
$ScriptDir = Resolve-Path (Split-Path $MyInvocation.MyCommand.Path)

$FinalName = "knox-@knox.version@"

###############################################################################
###
### Installs knox.
###
### Arguments:
###     component: Component to be installed, it can be "core, "hdfs" or "mapreduce"
###     nodeInstallRoot: Target install folder (for example "C:\Hadoop")
###     serviceCredential: Credential object used for service creation
###     role: Space separated list of roles that should be installed.
###           (for example, "jobtracker historyserver" for mapreduce)
###
###############################################################################

function Install(
    [String]
    [Parameter( Position=0, Mandatory=$true )]
    $component,
    [String]
    [Parameter( Position=1, Mandatory=$true )]
    $nodeInstallRoot,
    [System.Management.Automation.PSCredential]
    [Parameter( Position=2, Mandatory=$false )]
    $serviceCredential,
    [String]
    [Parameter( Position=3, Mandatory=$false )]
    $roles
    )
{


    if ( $component -eq "knox" )
    {
        $HDP_INSTALL_PATH, $HDP_RESOURCES_DIR = Initialize-InstallationEnv $scriptDir "$FinalName.winpkg.log"
        Write-Log "Checking the JAVA Installation."
        if( -not (Test-Path $ENV:JAVA_HOME\bin\java.exe))
        {
            Write-Log "JAVA_HOME not set properly; $ENV:JAVA_HOME\bin\java.exe does not exist" "Failure"
            throw "Install: JAVA_HOME not set properly; $ENV:JAVA_HOME\bin\java.exe does not exist."
        }

        Write-Log "Checking the Hadoop Installation."
        if( -not (Test-Path $ENV:HADOOP_HOME\bin\winutils.exe))
        {
          Write-Log "HADOOP_HOME not set properly; $ENV:HADOOP_HOME\bin\winutils.exe does not exist" "Failure"
          throw "Install: HADOOP_HOME not set properly; $ENV:HADOOP_HOME\bin\winutils.exe does not exist."
        }

        ### $knoxInstallPath: the name of the folder containing the application, after unzipping
        $knoxInstallPath = Join-Path $nodeInstallRoot $FinalName
        $knoxInstallToBin = Join-Path "$knoxInstallPath" "bin"

	    Write-Log "Installing Apache $FinalName to $knoxInstallPath"

        ### Create Node Install Root directory
        if( -not (Test-Path "$knoxInstallPath"))
        {
            Write-Log "Creating Node Install Root directory: `"$knoxInstallPath`""
            $cmd = "mkdir `"$knoxInstallPath`""
            Invoke-CmdChk $cmd
        }

        #$sourceZip = "$FinalName-bin.zip"

        # Rename zip file and initialize parent directory of $knoxInstallPath
        #Rename-Item "$HDP_RESOURCES_DIR\$sourceZip" "$HDP_RESOURCES_DIR\$FinalName.zip"
        $knoxIntallPathParent = (Get-Item $knoxInstallPath).parent.FullName

        ###
        ###  Unzip knox distribution from compressed archive
        ###

        Write-Log "Extracting $FinalName.zip to $knoxIntallPathParent"
        if ( Test-Path ENV:UNZIP_CMD )
        {
            ### Use external unzip command if given
            $unzipExpr = $ENV:UNZIP_CMD.Replace("@SRC", "`"$HDP_RESOURCES_DIR\$FinalName.zip`"")
            $unzipExpr = $unzipExpr.Replace("@DEST", "`"$knoxIntallPathParent`"")
            ### We ignore the error code of the unzip command for now to be
            ### consistent with prior behavior.
            Invoke-Ps $unzipExpr
        }
        else
        {
            $shellApplication = new-object -com shell.application
            $zipPackage = $shellApplication.NameSpace("$HDP_RESOURCES_DIR\$FinalName.zip")
            $destinationFolder = $shellApplication.NameSpace($knoxInstallPath)
            $destinationFolder.CopyHere($zipPackage.Items(), 20)
        }

        ###
        ### Set knox_HOME environment variable
        ###
        Write-Log "Setting the knox_HOME environment variable at machine scope to `"$knoxInstallPath`""
        [Environment]::SetEnvironmentVariable("knox_HOME", $knoxInstallPath, [EnvironmentVariableTarget]::Machine)
        $ENV:knox_HOME = "$knoxInstallPath"

		if ($roles) {

		###
		### Create knox Windows Services and grant user ACLS to start/stop
		###
		Write-Log "Node knox Role Services: $roles"

		### Verify that roles are in the supported set
		CheckRole $roles @("gateway", "ldap")

        Write-Log "Role : $roles"
        foreach( $service in empty-null ($roles -Split('\s+')))
        {
            CreateAndConfigureHadoopService $service $HDP_RESOURCES_DIR $knoxInstallToBin $serviceCredential
            $cmd="$ENV:WINDIR\system32\sc.exe config $service start= demand"
            Invoke-CmdChk $cmd

            ###
            ### Setup knox service config
            ###

            Write-Log "Creating service config ${knoxInstallToBin}\$service.xml"
            $cmd = "$knoxInstallToBin\$service.cmd --service > `"$knoxInstallToBin\$service.xml`""
            Invoke-CmdChk $cmd
            if ($service -eq "gateway")
            {
                Write-Log "Renaming 'Apache Hadoop gateway' to 'Apache Hadoop Knox Gateway'"
                $cmd="$ENV:WINDIR\system32\sc.exe config $service DisplayName= " +'"Apache Hadoop Knox Gateway"'
                Invoke-CmdChk $cmd
            }
            elseif ($service -eq "ldap")
            {
                Write-Log "Renaming 'Apache Hadoop ldap' to 'Apache Hadoop Knox Test LDAP'"
                $cmd="$ENV:WINDIR\system32\sc.exe config $service DisplayName= " +'"Apache Hadoop Knox Test LDAP"'
                Invoke-CmdChk $cmd
            }

        }

        ### end of roles loop
        }
        Write-Log "Finished installing Apache knox"
    }
    else
    {
        throw "Install: Unsupported component argument."
    }
}


###############################################################################
###
### Uninstalls Hadoop component.
###
### Arguments:
###     component: Component to be uninstalled, it can be "core, "hdfs" or "mapreduce"
###     nodeInstallRoot: Install folder (for example "C:\Hadoop")
###
###############################################################################

function Uninstall(
    [String]
    [Parameter( Position=0, Mandatory=$true )]
    $component,
    [String]
    [Parameter( Position=1, Mandatory=$true )]
    $nodeInstallRoot
    )
{
    if ( $component -eq "knox" )
    {
        $HDP_INSTALL_PATH, $HDP_RESOURCES_DIR = Initialize-InstallationEnv $scriptDir "$FinalName.winpkg.log"

	    Write-Log "Uninstalling Apache knox $FinalName"
	    $knoxInstallPath = Join-Path $nodeInstallRoot $FinalName

        ### If Hadoop Core root does not exist exit early
        if ( -not (Test-Path $knoxInstallPath) )
        {
            return
        }

		### Stop and delete services
        ###
        foreach( $service in ("gateway", "ldap"))
        {
            StopAndDeleteHadoopService $service
        }

	    ###
	    ### Delete install dir
	    ###
	    $cmd = "rd /s /q `"$knoxInstallPath`""
	    Invoke-Cmd $cmd

        ### Removing knox_HOME environment variable
        Write-Log "Removing the knox_HOME environment variable"
        [Environment]::SetEnvironmentVariable( "knox_HOME", $null, [EnvironmentVariableTarget]::Machine )

        Write-Log "Successfully uninstalled knox"

    }
    else
    {
        throw "Uninstall: Unsupported compoment argument."
    }
}

###############################################################################
###
### Start component services.
###
### Arguments:
###     component: Component name
###     roles: List of space separated service to start
###
###############################################################################
function StartService(
    [String]
    [Parameter( Position=0, Mandatory=$true )]
    $component,
    [String]
    [Parameter( Position=1, Mandatory=$true )]
    $roles
    )
{
    Write-Log "Starting `"$component`" `"$roles`" services"

    if ( $component -eq "knox" )
    {
        Write-Log "StartService: knox services"
		CheckRole $roles @("gateway", "ldap")

        foreach ( $role in $roles -Split("\s+") )
        {
            Write-Log "Starting $role service"
            Start-Service $role
        }
    }
    else
    {
        throw "StartService: Unsupported component argument."
    }
}

###############################################################################
###
### Stop component services.
###
### Arguments:
###     component: Component name
###     roles: List of space separated service to stop
###
###############################################################################
function StopService(
    [String]
    [Parameter( Position=0, Mandatory=$true )]
    $component,
    [String]
    [Parameter( Position=1, Mandatory=$true )]
    $roles
    )
{
    Write-Log "Stopping `"$component`" `"$roles`" services"

    if ( $component -eq "knox" )
    {
        ### Verify that roles are in the supported set
        CheckRole $roles @("gateway", "ldap")
        foreach ( $role in $roles -Split("\s+") )
        {
            try
            {
                Write-Log "Stopping $role "
                if (Get-Service "$role" -ErrorAction SilentlyContinue)
                {
                    Write-Log "Service $role exists, stopping it"
                    Stop-Service $role
                }
                else
                {
                    Write-Log "Service $role does not exist, moving to next"
                }
            }
            catch [Exception]
            {
                Write-Host "Can't stop service $role"
            }

        }
    }
    else
    {
        throw "StartService: Unsupported compoment argument."
    }
}

###############################################################################
###
### Alters the configuration of the knox component.
###
### Arguments:
###     component: Component to be configured, it should be "knox"
###     nodeInstallRoot: Target install folder (for example "C:\Hadoop")
###     serviceCredential: Credential object used for service creation
###     configs:
###
###############################################################################
function Configure(
    [String]
    [Parameter( Position=0, Mandatory=$true )]
    $component,
    [String]
    [Parameter( Position=1, Mandatory=$true )]
    $nodeInstallRoot,
    [System.Management.Automation.PSCredential]
    [Parameter( Position=2, Mandatory=$false )]
    $serviceCredential,
    [hashtable]
    [parameter( Position=3 )]
    $configs = @{},
    [bool]
    [parameter( Position=4 )]
    $aclAllFolders = $True
    )
{

    if ( $component -eq "knox" )
    {
        Write-Log "Configuring knox"
        $xmlFile = "$ENV:knox_HOME\conf\topologies\sandbox.xml"
		$knox_config = @{
        "NAMENODE" = "hdfs://"+$ENV:NAMENODE_HOST+":8020";
        "JOBTRACKER" = "rpc://"+$ENV:RESOURCEMANAGER_HOST+":8032";
        "WEBHDFS" = "http://"+$ENV:NAMENODE_HOST+":50070/webhdfs";
        "WEBHCAT" = "http://"+$ENV:WEBHCAT_HOST+":50111/templeton";
        "OOZIE" = "http://"+$ENV:OOZIE_SERVER_HOST+":11000/oozie";
        "HIVE" = "http://"+$ENV:HIVE_SERVER_HOST+":10001/cliservice"}
		if (Test-Path ENV:HBASE_MASTER)
        {
            $knox_config.Add("WEBHBASE", "http://"+$ENV:HBASE_MASTER+":8080")
        }
        UpdateXmlConfig $xmlFile $knox_config
        Write-Log "Creating knox log dir"
        $knoxLogsDir = Join-Path $ENV:HDP_LOG_DIR "knox"
        ###
        ### ACL Knox logs directory such that machine users can write to it
        ###
        if( -not (Test-Path "$knoxLogsDir"))
        {
            Write-Log "Creating Knox logs folder"
            New-Item -Path "$knoxLogsDir" -type directory | Out-Null
        }
        GiveFullPermissions "$knoxLogsDir" "Users"
        Write-Log "Changing *.properties"
        $string = "app.log.dir=$knoxLogsDir".Replace("\","/")
        ReplaceString "$ENV:KNOX_HOME\conf\gateway-log4j.properties" 'app.log.dir=${launcher.dir}/../logs' $string
        ReplaceString "$ENV:KNOX_HOME\conf\knoxcli-log4j.properties" 'app.log.dir=${launcher.dir}/../logs' $string
        ReplaceString "$ENV:KNOX_HOME\conf\ldap-log4j.properties" 'app.log.dir=${launcher.dir}/../logs' $string
        if ((Test-Path ENV:IS_KNOX_HA) -and ($ENV:IS_KNOX_HA -eq "yes"))
        {
            Write-Log "Updating Knox topology with HA settings"
            UpdateHAConfig "$ENV:KNOX_HOME\conf\topologies\sandbox.xml"
        }
           
        UpdateFQDNConfig "$ENV:KNOX_HOME\conf\topologies\sandbox.xml"
        ###
        ### Create master and Cert at installtion of Knox
        ###

        ### Create-master will create master key
        $cmd = "$ENV:KNOX_HOME\bin\knoxcli.cmd create-master --master $ENV:KNOX_MASTER_SECRET --force"
        Write-log "Create-master command executed"
        Invoke-CmdChk $cmd

        ### Create-cert will create the keystore credentials as per the Knox host.
        $cmd = "$ENV:KNOX_HOME\bin\knoxcli.cmd create-cert --hostname $ENV:KNOX_HOST"
        Write-log "Create-cert command executed"
        Invoke-CmdChk $cmd
    }
    else
    {
        throw "Configure: Unsupported compoment argument."
    }
}


### Helper routing that converts a $null object to nothing. Otherwise, iterating over
### a $null object with foreach results in a loop with one $null element.
function empty-null($obj)
{
   if ($obj -ne $null) { $obj }
}

### Gives full permissions on the folder to the given user
function GiveFullPermissions(
    [String]
    [Parameter( Position=0, Mandatory=$true )]
    $folder,
    [String]
    [Parameter( Position=1, Mandatory=$true )]
    $username,
    [bool]
    [Parameter( Position=2, Mandatory=$false )]
    $recursive = $false)
{
    Write-Log "Giving user/group `"$username`" full permissions to `"$folder`""
    $cmd = "icacls `"$folder`" /grant ${username}:(OI)(CI)F"
    if ($recursive) {
        $cmd += " /T"
    }
    Invoke-CmdChk $cmd
}

### Checks if the given space separated roles are in the given array of
### supported roles.
function CheckRole(
    [string]
    [parameter( Position=0, Mandatory=$true )]
    $roles,
    [array]
    [parameter( Position=1, Mandatory=$true )]
    $supportedRoles
    )
{
    foreach ( $role in $roles.Split(" ") )
    {
        if ( -not ( $supportedRoles -contains $role ) )
        {
            throw "CheckRole: Passed in role `"$role`" is outside of the supported set `"$supportedRoles`""
        }
    }
}

### Creates and configures the service.
function CreateAndConfigureHadoopService(
    [String]
    [Parameter( Position=0, Mandatory=$true )]
    $service,
    [String]
    [Parameter( Position=1, Mandatory=$true )]
    $hdpResourcesDir,
    [String]
    [Parameter( Position=2, Mandatory=$true )]
    $serviceBinDir,
    [System.Management.Automation.PSCredential]
    [Parameter( Position=3, Mandatory=$true )]
    $serviceCredential
)
{
    if ( -not ( Get-Service "$service" -ErrorAction SilentlyContinue ) )
    {
		 Write-Log "Creating service `"$service`" as $serviceBinDir\$service.exe"
        $xcopyServiceHost_cmd = "copy /Y `"$HDP_RESOURCES_DIR\serviceHost.exe`" `"$serviceBinDir\$service.exe`""
        Invoke-CmdChk $xcopyServiceHost_cmd

        #Creating the event log needs to be done from an elevated process, so we do it here
        if( -not ([Diagnostics.EventLog]::SourceExists( "$service" )))
        {
            [Diagnostics.EventLog]::CreateEventSource( "$service", "" )
        }

        Write-Log "Adding service $service"
        $s = New-Service -Name "$service" -BinaryPathName "$serviceBinDir\$service.exe" -Credential $serviceCredential -DisplayName "Apache Hadoop $service"
        if ( $s -eq $null )
        {
            throw "CreateAndConfigureHadoopService: Service `"$service`" creation failed"
        }

        $cmd="$ENV:WINDIR\system32\sc.exe failure $service reset= 30 actions= restart/5000"
        Invoke-CmdChk $cmd

        $cmd="$ENV:WINDIR\system32\sc.exe config $service start= disabled"
        Invoke-CmdChk $cmd

        Set-ServiceAcl $service
    }
    else
    {
        Write-Log "Service `"$service`" already exists, Removing `"$service`""
        StopAndDeleteHadoopService $service
        CreateAndConfigureHadoopService $service $hdpResourcesDir $serviceBinDir $serviceCredential
    }
}

### Stops and deletes the Hadoop service.
function StopAndDeleteHadoopService(
    [String]
    [Parameter( Position=0, Mandatory=$true )]
    $service
)
{
    Write-Log "Stopping $service"
    $s = Get-Service $service -ErrorAction SilentlyContinue

    if( $s -ne $null )
    {
        Stop-Service $service
        $cmd = "sc.exe delete $service"
        Invoke-Cmd $cmd
    }
}

### Helper routine that converts a $null object to nothing. Otherwise, iterating over
### a $null object with foreach results in a loop with one $null element.
function empty-null($obj)
{
   if ($obj -ne $null) { $obj }
}

### Helper routine that updates the given fileName XML file with the given
### key/value configuration values. The XML file is expected to be in the
### Hadoop format. For example:
### <configuration>
###   <property>
###     <name.../><value.../>
###   </property>
### </configuration>
function UpdateXmlConfig(
    [string]
    [parameter( Position=0, Mandatory=$true )]
    $fileName,
    [hashtable]
    [parameter( Position=1 )]
    $config = @{} )
{
    $xml = New-Object System.Xml.XmlDocument
    $xml.PreserveWhitespace = $true
    $xml.Load($fileName)

    foreach( $key in empty-null $config.Keys )
    {
        $value = $config[$key]
        $found = $False
        $xml.SelectNodes('/topology/service') | ? { $_.role -eq $key } | % { $_.url = $value; $found = $True }
        if ( -not $found )
        {
            $newItem = $xml.CreateElement("property")
            $newItem.AppendChild($xml.CreateSignificantWhitespace("`r`n    ")) | Out-Null
            $newItem.AppendChild($xml.CreateElement("role")) | Out-Null
            $newItem.AppendChild($xml.CreateSignificantWhitespace("`r`n    ")) | Out-Null
            $newItem.AppendChild($xml.CreateElement("url")) | Out-Null
            $newItem.AppendChild($xml.CreateSignificantWhitespace("`r`n  ")) | Out-Null
            $newItem.name = $key
            $newItem.value = $value
            $xml["configuration"].AppendChild($xml.CreateSignificantWhitespace("`r`n  ")) | Out-Null
            $xml["configuration"].AppendChild($newItem) | Out-Null
            $xml["configuration"].AppendChild($xml.CreateSignificantWhitespace("`r`n")) | Out-Null
        }
    }

    $xml.Save($fileName)
    $xml.ReleasePath
}

### Helper routine that replaces string in file
function ReplaceString($file,$find,$replace)
{
    $content = Get-Content $file
    for ($i=1; $i -le $content.Count; $i++)
    {
        if ($content[$i] -like "*$find*")
        {
            $content[$i] = $content[$i].Replace($find, $replace)
        }
    }
    Set-Content -Value $content -Path $file -Force
}

function UpdateFQDNConfig(
    [string]
    [parameter( Position=0, Mandatory=$true )]
    $fileName)
{
    $xml = [xml] (Get-Content $fileName)
    $keywords = @("*.hosts","*address","*.url","*.hostname")
    $values = $xml.SelectNodes('/topology/gateway/provider/param') 
    foreach( $keyword in $keywords )
    {        
        foreach ($value in $values)
        {
            if ($value.name -like "$keyword" )
            {
                Write-Log $value.name
                switch ($keyword)
                {
                    "*.hostname"
                    {
                        try
                        {
                            $host = [string] (Get-FQDN $value.value)
                        }
                        catch
                        {
                            $host = [string] $value.value
                        }
                        $value.value =  $host
                    }
                    "*.hosts"
                    {
                        try
                        {
                            $host = [string] (Get-FQDN $value.value)
                        }
                        catch
                        {
                            $host = [string] $value.value
                        }
                        $value.value =  $host
                    }
                    "*address"
                    {
                        
                        $split = $value.value -split(':')
                        try
                        {
                            $host = [string] (Get-FQDN $split[0])
                        }
                        catch
                        {
                            $host = [string] $split[0]
                        }
                        if ($split[1] -eq $null)
                        {
                            $value.value = ($host)
                        }
                        else
                        {
                            $value.value = ($host+":"+$split[1])
                        }
                    }
                    "*.url"
                    {
                        try
                        {
                            $url_split = $value.value -split('/')
                            $split = $url_split[2] -split(':')
                            try
                            {
                                $host = [string] (Get-FQDN $split[0])
                            }
                            catch
                            {
                                $host = [string] $split[0]
                            }
                            if ($split[1] -eq $null)
                            {
                                $url_split[2] = ($host)
                            }
                            else
                            {
                                $url_split[2] = ($host+":"+$split[1])
                            }
                            $value.value = $url_split -join '/'
                        }
                        catch{}
                    }
                }
            }
        }
    }
    
    $values = $xml.SelectNodes('/topology/service') 
    foreach ($value in $values)
    {
        Write-Log $value.role
        try
        {
            $url_split = $value.url -split('/')
            $split = $url_split[2] -split(':')
            try
            {
                $host = [string] (Get-FQDN $split[0])
            }
            catch
            {
                $host = [string] $split[0]
            }
            if ($split[1] -eq $null)
            {
                $url_split[2] = ($host)
            }
            else
            {
                $url_split[2] = ($host+":"+$split[1])
            }
            $value.url = $url_split -join '/'
        }
        catch{}
    }
    $xml.Save($fileName)
    $xml.ReleasePath
}

#------------------------------------------------------------------------------
# Get the lowercase FQDN for the current host.
#------------------------------------------------------------------------------
function Get-LocalFQDN() {
  $name = [System.Net.Dns]::GetHostName()
  $entry = [System.Net.Dns]::GetHostEntry( $name )
  $fqdn = $entry.HostName.ToLower()
  return $fqdn
}

#------------------------------------------------------------------------------
# Resolve the name via DNS and then converts result to lower case.
#------------------------------------------------------------------------------
function Get-FQDN( $name ) {
  $entry = [System.Net.Dns]::GetHostEntry( $name )
  $fqdn = $entry.HostName.ToLower()
  return $fqdn
}

function UpdateHAConfig(
    [string]
    [parameter( Position=0, Mandatory=$true )]
    $fileName)
{
    $xml = New-Object System.Xml.XmlDocument
    $xml.PreserveWhitespace = $true
    $xml.Load($fileName)
    $nodes = $xml.SelectSingleNode('/topology/gateway')
     $newItem = $xml.CreateElement("provider")
    $newItem.AppendChild($xml.CreateSignificantWhitespace("`r`n    ")) | Out-Null
    $newItem.AppendChild($xml.CreateElement("role")) | Out-Null
    $newItem.AppendChild($xml.CreateSignificantWhitespace("`r`n    ")) | Out-Null
    $newItem.AppendChild($xml.CreateElement("name")) | Out-Null
    $newItem.AppendChild($xml.CreateSignificantWhitespace("`r`n  ")) | Out-Null
    $newItem.AppendChild($xml.CreateElement("enabled")) | Out-Null
    $newItem.AppendChild($xml.CreateSignificantWhitespace("`r`n  ")) | Out-Null
    $newItem.role = "ha"
    $newItem.name = "HaProvider"
    $newItem.enabled = "true"
    $nodes.AppendChild($xml.CreateSignificantWhitespace("`r`n  ")) | Out-Null
    $nodes.AppendChild($newItem) | Out-Null
    $nodes.AppendChild($xml.CreateSignificantWhitespace("`r`n")) | Out-Null
    $nodes = $xml.SelectNodes('/topology/gateway/provider')
    foreach ($node in $nodes)
    {
        if ($node.role -eq "ha")
        {
            $newItem = $xml.CreateElement("param")
            $newItem.AppendChild($xml.CreateSignificantWhitespace("`r`n    ")) | Out-Null
            $newItem.AppendChild($xml.CreateElement("name")) | Out-Null
            $newItem.AppendChild($xml.CreateSignificantWhitespace("`r`n    ")) | Out-Null
            $newItem.AppendChild($xml.CreateElement("value")) | Out-Null
            $newItem.name = "WEBHDFS"
            $newItem.value = "maxFailoverAttempts=60;failoverSleep=1000;maxRetryAttempts=300;retrySleep=1000;enabled=true"
            $node.AppendChild($xml.CreateSignificantWhitespace("`r`n  ")) | Out-Null
               $node.AppendChild($newItem) | Out-Null
            $node.AppendChild($xml.CreateSignificantWhitespace("`r`n")) | Out-Null
        }
    }
    $nodes = $xml.SelectNodes('/topology/service')
    foreach ($node in $nodes)
    {
        if ($node.role -eq "WEBHDFS")
        {
            $newitem = $xml.CreateElement("url")
            $newitem.InnerText = "http://" +$ENV:NN_HA_STANDBY_NAMENODE_HOST+":50070/webhdfs"
            $node.AppendChild($xml.CreateSignificantWhitespace("`r`n    ")) | Out-Null
            $node.AppendChild($newitem) | Out-Null
        }
    }
    $xml.Save($fileName)
    $xml.ReleasePath
}


###
### Public API
###
Export-ModuleMember -Function Install
Export-ModuleMember -Function Uninstall
Export-ModuleMember -Function Configure
Export-ModuleMember -Function StartService
Export-ModuleMember -Function StopService

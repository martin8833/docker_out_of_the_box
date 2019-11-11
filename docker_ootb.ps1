#Globale Konstanten
$currentLocalLocation = (Get-Location).ToString()
$dockerMasterScriptPath = $(((Get-Location).ToString()) + "\docker_master_script.sh")
$dockerMasterScriptFilename = Split-Path $dockerMasterScriptPath -leaf
$registryServerKeyPath = "./cert.crt"

Function Main 
{
	$registryServerUrl = $null
	$registryServerPassword = $null
	$registryServerKey = $null
	$registryServerPort = $null
	#Der Username des initialen Users, der auf die Registry zugreifen soll
	$registryUserUsername = $null
	#Das Passwort des initialen Users, der auf die Registry zugreifen soll
	$registryUserPassword = $null
	$dockerServerUrls = $null
	$dockerServerPasswordsEncrypted = $null
	$dockerServerKeys = $null
	$dockerServerPorts = $null
	
	# Schritt 0: User über vorarbeiten Informieren
	Write-Host "Dieses Skript installiert eine Docker-Registry und Docker-dockerServer, die mit der Registry integriert sind."
	Write-Host "Hinweis: Beide komponenten sind optional. Wenn sie nicht gewünscht sind, bei den Verbindungsinformationen nichts angeben."
	$preparationComplete = $null
	Prompt_Prep_Complete ([ref]$preparationComplete)
	if($preparationComplete -eq "n") {
		Write-Host "Bitte die Vorarbeiten erledigen und das Skript danach erneut starten."
		Return
	}
	
	# Schritt 1: Informationen über Server für Registry und Docker-Hosts von User abfragen
	Write-Host "Zunächst müssen dazu Verbindungsinformationen zu der Registry und den dockerServern gesammelt werden"

	while($true) {
		# Schritt 1.a Registry-Verbindungsinformationen sammeln  
		Write-Host "Verbindungsinformationen für die Registry werden gesammelt"
		Collect_Registry_Information ([ref]$registryServerUrl) ([ref]$registryServerPassword) ([ref]$registryServerKey) ([ref]$registryServerPort) ([ref]$registryUserUsername) ([ref]$registryUserPassword)
		# Schritt 1.b Server-Informationen sammeln
		Write-Host "Verbindungsinformationen für die Docker-Hosts werden gesammelt"
		Collect_Server_Information ([ref]$dockerServerUrls) ([ref]$dockerServerPasswordsEncrypted) ([ref]$dockerServerKeys) ([ref]$dockerServerPorts)
		# Schritt 1.c User Übersicht geben
		Write-Host "Folgende Daten wurden registriert:"
		Write-Host $dockerServerPorts[0]
		Write_Collected_Info
		# Schritt 1.d User Angaben bestätigen lassen
		#Der User wird gefragt, ob die Informationen vollständig sind
		$collectionComplete = $null
		Prompt_Complete ([ref]$collectionComplete)
		
		if($collectionComplete -eq "y") {
			break;
		} else {
			Write-Host "Bitte die Daten erneut eingeben"
		}
	}
	Write-Host "Die notwendigen Informationen wurden gesammelt"
	# Schritt 2: Registry auf dem angegebenen Server installieren
	if ( [string]::IsNullOrEmpty($registryServerUrl)) {
		Write-Host "Keine Registry angegeben. Deswegen werden jetzt direkt die Testumgebungen initialisiert."
	} else {
		Write-Host "Nun wird die Registry auf dem Server $registryServerUrl installiert."
		Install_Registry
	}
	# Schritt 3: Docker auf den angegebenen Servern installieren
	if ($dockerServerUrls.Length -eq 0) {
		Write-Host "Keine Test-Server angegeben. Deswegen endet das Skript jetzt."
	} else {
		Install_Docker_Hosts
		Write-Host "Die Installation ist abgeschlossen."
	}
}

#Es müssen einige Voraussetzungen erfolgt sein, um das Skript auszuführen. Diese werden hier abgefragt.
Function Prompt_Prep_Complete([ref]$preparationComplete) {
	Write-Host "Folgende Vorarbeiten müssen erledigt sein."
	Write-Host "1. Putty muss installiert sein."
	Write-Host "2. Falls die Server-Authentifizierung über Keys stattfindet, müssen die Keys im .ppk-Format vorliegen."
	Write-Host "Hinweis: Bei der Installation der Docker Registry kann es zu Problemen kommen (Zertifikat nicht akzeptiert), wenn der Server im VPN ist."
	$preparationComplete.value = Read-Host -Prompt "Sind die vorarbeiten erledigt? y/n"
	while("y","n" -notcontains $preparationComplete.value)
	{
		$preparationComplete.value = Read-Host -Prompt "Bitte y/n angeben"
	}
}
#Es wird abgefragt, ob die Angaben in Ordnung sind
Function Prompt_Complete([ref]$collectionComplete) {
	$collectionComplete.value = Read-Host -Prompt "Ist das so ok? y/n"
	while("y","n" -notcontains $collectionComplete.value)
	{
		$collectionComplete.value = Read-Host -Prompt "Bitte y/n angeben"
	}
}

#Es wird eine Übersicht der Infos angegeben
Function Write_Collected_Info {
	Write-Host "Registry-Server mit URL '$registryServerUrl', Key '$registryServerKey' und Port '$registryServerPort'"
	for($i=0; $i -lt $dockerServerUrls.Length; $i++) {
		$currentServerUrl = $dockerServerUrls[$i]
		$currentServerKey = $dockerServerKeys[$i]
		$currentServerPort = $dockerServerPorts[$i]
		$currentNumber = $i + 1
		Write-Host "Test-Server $currentNumber mit URL $currentServerUrl, Key $currentServerKey und Port $currentServerPort"
	}
}

#Die Informationen für die Server, die als Docker-Hosts fungieren sollen, werden gesammelt
Function Collect_Server_Information([ref]$dockerServerUrls, [ref]$dockerServerPasswordsEncrypted, [ref]$dockerServerKeys, [ref]$dockerServerPorts) {
	$numdockerServers = Read-Host -Prompt "Wie viele Test-Server sollen mit Docker bespielt werden? Bitte 0 angeben, wenn kein Test-Server gewünscht"
	if ($numdockerServers -eq 0) {
		Write-Host "Kein Test-Server geünscht."
	}
	$dockerServerUrls.value = [string[]]::new($numdockerServers)
	$dockerServerPasswordsEncrypted.value = [System.Security.SecureString[]]::new($numdockerServers)
	$dockerServerKeys.value = [string[]]::new($numdockerServers)
	$dockerServerPorts.value = [string[]]::new($numdockerServers)

	for($i=0; $i -lt $numdockerServers; $i++) {
		$currentNumber = $i + 1
		$dockerServerUrls.value[$i] = Read-Host -Prompt "Server $currentNumber : Bitte gib Username und Hostname oder IP in folgendem Format an <username>@<Hostname oder IP>"
		$dockerServerPasswordsEncrypted.value[$i] = Read-Host -assecurestring "Password eingeben (leer, wenn kein Passwort erforderlich)"
		$answer = Read-Host -Prompt "Muss für die Verbindung mit dem Server ein Zertifikat angegeben werden: y/n"
		while("y","n" -notcontains $answer)
		{
			$answer = Read-Host -Prompt "Bitte y/n angeben"
		}
		if($answer -eq "y") {
			$dockerServerKeys.value[$i] = Read-Host -Prompt "Bitte gib den Pfad zu dem Zertfikat an"
		}
		$answer = Read-Host -Prompt "Wird als Portnummer der Standard verwendet (Port number:22) : y/n"
		while("y","n" -notcontains $answer)
		{
			$answer = Read-Host -Prompt "Bitte y/n angeben"
		}
		
		if($answer -eq "n") {
			$dockerServerPorts.value[$i] = Read-Host -Prompt "Bitte Portnummer angeben"
		} else {
			$dockerServerPorts.value[$i] = 22
		}
	}
}

#Die Informationen Über den Server, der als Registry fungieren soll, werden gesammelt
Function Collect_Registry_Information ([ref]$registryServerUrl, [ref]$registryServerPassword, [ref]$registryServerKey, [ref]$registryServerPort, [ref]$registryUserUsername, [ref]$registryUserPassword) {
	
	$registryServerUrl.value = Read-Host -Prompt "Bitte gib Username und Hostname oder IP in folgendem Format an <username>@<Hostname oder IP>. Wenn keine Registry gewünscht ist Enter"
	if ( -not ([string]::IsNullOrEmpty($registryServerUrl.value))) {
	
		$registryServerPassword.value = Read-Host -assecurestring "Password eingeben (leer, wenn kein Passwort erforderlich)"
		$answer = Read-Host -Prompt "Muss für die Verbindung mit dem Server ein Key angegeben werden: y/n"
		$registryServerKey.value =

		while("y","n" -notcontains $answer)
		{
			$answer = Read-Host -Prompt "Bitte y/n angeben"
		}

		if($answer -eq "y") {
			$registryServerKey.value = Read-Host -Prompt "Bitte gib den Pfad zu dem Key an"
		}
		$answer = Read-Host -Prompt "Wird als Portnummer der Standard verwendet (Port number:22) : y/n"
		while("y","n" -notcontains $answer)
		{
			$answer = Read-Host -Prompt "Bitte y/n angeben"
		}
		
		if($answer -eq "n") {
			$registryServerPort.value = Read-Host -Prompt "Bitte Portnummer angeben"
		} else {
			$registryServerPort.value = 22
		}
		
		Write-Host "Username und Passwortinormationen für die Registry werden nun gesammelt."
		$registryUserUsername.value = Read-Host -Prompt "Username"
		$registryUserPassword.value = Read-Host -assecurestring "Passwort"

		Write-Host "Folgender Server für die Docker-Registry wurde registriert: '$registryServerUrl.value'"
	} else {
		Write-Host "Keine Registry erwüscht. Deswegen wird direkt mit den Test-Servern fortgefahren."
	}
}

#Installiert die Registry
Function Install_Registry {
	$registryServerKey = (&{If(-not ([string]::IsNullOrEmpty($registryServerKey))) {"$registryServerKey"}})
	$registryUsername = $registryServerUrl.Substring(0, $registryServerUrl.LastIndexOf("@"))
	$registryHostname = $registryServerUrl.Substring($registryServerUrl.LastIndexOf("@") + 1)
	$registryServerPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($registryServerPassword))
	$registryUserPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($registryUserPassword))
	
	Execute_Pscp $registryServerPassword $registryServerKey $registryServerPort "$dockerMasterScriptPath" "$($registryServerUrl):/home/$registryUsername/$dockerMasterScriptFilename"
	# Das Schreiben in einen File geschieht, da die Codierung sonst nicht akzeptiert wird
	"chmod 777 ~/$dockerMasterScriptFilename" | Add-Content registry_commands.txt
	"~/$dockerMasterScriptFilename registry $registryUserUsername $registryUserPassword $registryHostname >registry_install_std.log 2>registry_install_err.log" | Add-Content registry_commands.txt
	Write-Host "Das Installationsskript wird auf dem Server ausgeführt. Die Ausführung kann mehrere Minuten dauern."
	Execute_Plink $registryServerPassword $registryServerKey $registryServerPort $registryServerUrl registry_commands.txt
	
	Execute_Pscp $registryServerPassword $registryServerKey $registryServerPort "$($registryServerUrl):/home/$registryUsername/certs/cert.crt" "$currentLocalLocation\cert.crt"
	Remove-Item registry_commands.txt
}

#Installiert die Docker Hosts
Function Install_Docker_Hosts {
	for($i=0; $i -lt $dockerServerUrls.Length; $i++) {
		$currentServerUrl = $dockerServerUrls[$i]
		$currentServerPw = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($dockerServerPasswordsEncrypted[$i]))
		$currentServerKey = $dockerServerKeys[$i]
		$currentServerPort = $dockerServerPorts[$i]
		$currentServerUsername = $currentServerUrl.Substring(0, $currentServerUrl.LastIndexOf("@"))
		Write-Host "Docker wird nun auf Test-Server $currentServerUrl installiert."
		Install_Docker
	}
}

#Installiert Docker auf einem Server
Function Install_Docker {
	if ( -not ([string]::IsNullOrEmpty($registryServerUrl))) {
		Execute_Pscp $currentServerPw $currentServerKey $currentServerPort "$dockerMasterScriptPath" "$($currentServerUrl):/home/$currentServerUsername"
		Execute_Pscp $currentServerPw $currentServerKey $currentServerPort "$currentLocalLocation\cert.crt" "$($currentServerUrl):/home/$currentServerUsername"
		"cp /home/$currentServerUsername/cert.crt /home/$currentServerUsername/certs/cert.crt" | Add-Content docker_install_commands_1.txt
		Execute_Plink $currentServerPw $currentServerKey $currentServerPort $currentServerUrl "docker_install_commands_1.txt"
		$registryHostname = $registryServerUrl.Substring($registryServerUrl.LastIndexOf("@") + 1)
		$dockerScriptArgs = "/home/$currentServerUsername/certs/cert.crt ${registryHostname}:443"
		Remove-Item docker_install_commands_1.txt
	} else {
		Write-Host "Keine Registry"
		Execute_Pscp $currentServerPw $currentServerKey $currentServerPort "$dockerMasterScriptPath" "$($currentServerUrl):/home/$currentServerUsername/$dockerMasterScriptFilename"
	}
	
	# Das Schreiben in einen File geschieht, da die Codierung sonst nicht akzeptiert wird
	"chmod 777 ~/$dockerMasterScriptFilename" | Add-Content docker_install_commands_2.txt
	"~/$dockerMasterScriptFilename docker $dockerScriptArgs >docker_install_std.log 2>docker_install_err.log" | Add-Content docker_install_commands_2.txt
	Write-Host "Das Installationsskript wird auf dem Server ausgeführt. Die Ausführung kann mehrere Minuten dauern."
	Execute_Plink $currentServerPw $currentServerKey $currentServerPort $currentServerUrl "docker_install_commands_2.txt"
	Remove-Item docker_install_commands_2.txt
}

#Führt einen Plink-Befehl aus
Function Execute_Plink {
	param($serverPassword, $serverKey, $serverPort, $serverUrl, $commandFilePath)
	Execute_Putty_Command plink $serverPassword $serverKey $serverPort $serverUrl $commandFilePath
}

#Führt einen PSCP-Befehl aus
Function Execute_Pscp {
	param($serverPassword, $serverKey, $serverPort, $copySource, $copyTarget)
	Execute_Putty_Command pscp $serverPassword $serverKey $serverPort $null $null $copySource $copyTarget
}

Function Execute_Putty_Command {
	param($type, $serverPassword, $serverKey, $serverPort, $serverUrl, $commandFilePath, $copySource, $copyTarget)
	#-t: Force pseudo-tty allocation (for execution of screen-based program).
	# Die Options -i, -pw und -t lönnen nicht in Kombination mit leeren Strings angeeben werden. Deswegen das folgende Konstrukt.
	if (-not ([string]::IsNullOrEmpty($serverKey))) {
		if (-not ([string]::IsNullOrEmpty($serverPassword))) {
			if ($type -eq "plink") {
				plink -pw $serverPassword -i $serverKey -P $serverPort -t -batch -ssh $serverUrl -m $commandFilePath
			} else {
				pscp -pw $serverPassword -i $serverKey -P $serverPort $copySource $copyTarget
			}
		} else {
			if ($type -eq "plink") {
				plink -i $serverKey -P $serverPort -t -batch -ssh $serverUrl -m $commandFilePath
			} else {
				pscp -i $serverKey -P $serverPort $copySource $copyTarget
			}
		}
	} else {
		if (-not ([string]::IsNullOrEmpty($serverPassword))) {
			if ($type -eq "plink") {
				plink -pw $serverPassword -P $serverPort -t -batch -ssh $serverUrl -m $commandFilePath
			} else {
				pscp -pw $serverPassword -P $serverPort $copySource $copyTarget
			}
		} else {
			if ($type -eq "plink") {
				plink -P $serverPort -t -batch -ssh $serverUrl -m $commandFilePath
			} else {
				pscp -P $serverPort $copySource $copyTarget
			}
		}
	}
}

Main
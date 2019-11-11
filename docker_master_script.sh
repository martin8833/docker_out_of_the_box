init_registry() {
	#This function takes three arguments: $1 registry username (required) $2 registry password (required) $3 hostname (required if $4 and $5 are null) $4 path to registry certificate, #5 path two registry key. $2 and $3 parameters can be null.
	
	if [ -z "$3" ] && [ -z "$4" ] && [ -z "$5" ]; then
		echo "Der Hostname darf nur Null sein, wenn bereits ein Serverzertifikat geliefert wurde."
		exit 1
	elif { [ -z "$4" ] && [ -n "$5" ]; } || { [ -n "$4" ] && [ -z "$5" ]; } ; then
		echo "Es müssen immer Zertifikat und Key zusammen angegeben werden."
		exit 1
	fi

	echo "Falls es bereits eine laufende Registry gibt, wird diese nun gestoppt und entfernt."
	if [ -x "$(command -v docker)" ]; then
		#TODO: suppress output
		sudo docker stop registry
		sudo docker container rm -v registry
	fi

	init_docker
	INIT_DOCKER_RETURN_CODE=$?
	if [ $INIT_DOCKER_RETURN_CODE -eq 1 ]; then
		echo "Es kam zu einem Fehler bei der Initialisierung von Docker. Deswegen wird das Registry-Skript jetzt abgebrochen."
		exit 1
	fi

	if [ -z "$4" ]; then
		echo "Installiere openssl zum Erstellen des Zertifikats."
		if [ $distro_family_ID = fedora ]; then
			echo "Die Distribution $distro_family_ID wurde entdeckt."
			echo "openssl wird nun installiert:"
			sudo yum -y install openssl
		elif [ $distro_family_ID = debian ]; then
			echo "Die Distribution $distro_family_ID wurde entdeckt."
			echo "openssl wird nun installiert:"
			sudo apt-get --assume-yes update
			sudo apt-get --assume-yes install openssl
		else
			echo "Das Betriebssystem ist unbekannt und somit konnte openssl nicht installiert werden. Die Registry wird nun ohne Key eingerichtet."
		fi
		echo "Es wird nun der Key erstellt."
		mkdir -p certs
		key_path="$(pwd)"/certs/key.key
		cert_path="$(pwd)"/certs/cert.crt
		#Die .rnd-Datei muss im Rahmen eines Workaround erstellt werden (Meldung: Can't load /home/<username>/.rnd into RNG 140073889182144:error:2406F079:random number generator:RAND_load_file:Cannot open file:../crypto/rand/randfile.c:88:Filename=/home/<username>/.rnd
		openssl rand -writerand ~/.rnd
		#TODO: CN muss noch gesetzt werden
		openssl req -x509 -newkey rsa:4096 -keyout ${key_path} -out ${cert_path} -nodes -days 365 -subj "/C=DE/L=Ismaning/O=msg systems ag/OU=Org/CN=$3"
	else
		echo "Es wurde bereits ein Zertifikat mit dem Pfad $2, sowie ein Key mit dem Pfad $3 mitgegeben. Diese werden im Folgenden verwendet."
		cert_path=$4
		key_path=$5
	fi

	echo "Richte nun Username und Password für die Registry ein"
	echo "Username: $1 Passwort: $2"
	mkdir -p auth
	sudo docker run \
  		--entrypoint htpasswd \
  		registry:2 -Bbn $1 $2 > auth/htpasswd

	echo "Die Registry wird nun auf Port 443 gestartet."
	sudo systemctl restart docker
	sudo docker run -d \
	  -v "$(pwd)"/auth:/auth \
	  -e "REGISTRY_AUTH=htpasswd" \
  	  -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
  	  -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
  	  -v $(dirname "${cert_path}"):/certs \
	  -e REGISTRY_HTTP_ADDR=0.0.0.0:443 \
	  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/$(basename "${cert_path}") \
	  -e REGISTRY_HTTP_TLS_KEY=/certs/$(basename "${key_path}") \
	  -p 443:443 \
	  --restart=always \
	  --name registry \
	  registry:2

	echo "Das Zertifikat muss nun zu den für Docker bekannten Zertifikaten hinzugefügt werden."
	registry_url="localhost:443"
	init_docker_ca $cert_path $registry_url
}

# Initialisiert Docker in 3 Schritten: 1. Installiert Docker distrospezifisch, 2. Speichert Docker in den Systemstart, 3. Konfiguriert Docker mit einer lokalen Registry
# Nimmt folgende Parameter: $1 (optional) cert_path: der lokale Pfad, auf dem das Registry-Zertifikat liegt; $2 (optional) registry_url: Die URL der Registry
init_docker () {
	get_os

	if [ $distro_family_ID = fedora ]; then
		echo "Die Distribution $distro_family_ID wurde entdeckt."
		echo "Docker wird nun gelöscht, falls es bereits installiert ist."
		sudo yum remove docker \
                  docker-client \
                  docker-client-latest \
                  docker-common \
                  docker-latest \
                  docker-latest-logrotate \
                  docker-logrotate \
                  docker-engine
        sudo rm -rf /var/lib/docker
        sudo yum -y install -y yum-utils \
			device-mapper-persistent-data \
			lvm2
		sudo yum-config-manager \
			--add-repo \
			https://download.docker.com/linux/centos/docker-ce.repo
		if [ $os = rhel ]; then
			sudo yum -y install docker-ce --nobest
		else
			sudo yum -y install docker-ce
		fi
		sudo yum -y install docker-ce-cli containerd.io
	elif [ $distro_family_ID = debian ]; then
		echo "Die Distribution $distro_family_ID wurde entdeckt."
		echo "Docker wird nun gelöscht, falls es bereits installiert ist."
		sudo apt-get --assume-yes purge docker.io
		sudo rm -rf /var/lib/docker
		echo "Docker wird nun neu installiert."
		echo "Zunächst wird das Docker Repository aufgesetzt."
		sudo apt-get --assume-yes  update
		sudo apt-get --assume-yes install \
		apt-transport-https \
		ca-certificates \
		curl \
		gnupg-agent \
		software-properties-common
		curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
		echo "Nun kann die Docker Engine installiert werden"
		sudo apt-get --assume-yes update
		sudo apt --assume-yes install docker.io
		
		echo "In Ubuntu muss momentan der Docker Unit-File demaskiert werden."
		sudo systemctl unmask docker.service
		sudo systemctl unmask docker.socket
		
	else
		echo "Die Distribution $distro_family_ID wird nicht unterstützt."
		echo "Das Skript endet nun."
		return 1
	fi

	if hash docker 2>/dev/null; then
		echo "Docker wurde erfolgreich installiert"
	else
		echo "Die Installation von Docker ist fehlgeschlagen"
		return 1
	fi

	echo "Docker wird nun so eingerichtet, dass es beim Systemstart läuft."
	sudo systemctl start docker
	sudo systemctl enable docker.service
	if systemctl is-enabled docker 2>/dev/null; then
		echo "Docker wurde erfolgreich in den Systemstart eingefügt."
	else
		echo "Docker konnte nicht in den Systemstart eingefügt werden. Das muss noch per Hand nachgezogen werden."
	fi

	if [ ! -z "$1" ]; then
		init_docker_ca $1 $2
	fi 
	
	return 0
}

get_os () {
	distro_family_ID=
	if [ -f /etc/os-release ]; then
		# freedesktop.org and systemd
		. /etc/os-release
		OS=$ID
		VER=$VERSION_ID
		distro_family_ID=$ID_LIKE
	else
		echo "Die Datei /etc/os-release konnte nicht gefunden werden und somit das Betriebssystem nicht ermittelt."
		return 1
	fi
	
	return 0
}

# Fügt das Zertifikat der eigenen Docker-Registry zu den bekannten Docker-Registries hinzu
# Nimmt folgende Parameter: $1 cert_path: der lokale Pfad, auf dem das Zertifikat liegt; $2 registry_url: Die URL der Registry
init_docker_ca () {
	sudo mkdir -p /etc/docker/certs.d/$2
	sudo cp $1 /etc/docker/certs.d/$2/ca.crt
	sudo service docker reload
	echo "Das Zertifikat wurde hinzugefügt."
} 

# Nimmt folgende Parameter: 
# $1 Entweder "docker", um eine Docker-Instanz aufzusetzen oder "registry", um eine Registry aufzusetzen. 
# $2 siehe init_docker() --> Argunment $1 oder init_registry() --> Argument $1
# $3 siehe init_docker() --> Argunment $2 oder init_registry() --> Argument $2
# $4 siehe init_registry() --> Argument $3
main () {
	if [ "$1" = "docker" ]; then
		init_docker $2 $3
	elif [ "$1" = "registry" ]; then
		init_registry $2 $3 $4 $5 $6
	else
		echo "Der Skript-Modus ist unbekannt"
		return 1
	fi
}

main $1 $2 $3 $4 $5 $6
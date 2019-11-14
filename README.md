# docker_out_of_the_box
Die beiden Skripte ermöglichen es, eine Docker Registry auf einem dedizierten Server zu installieren, sowie auf beliebig vielen weiteren Servern Docker zu installieren und die Docker Hosts mit der Registry zu integrieren.

Das Powershell-Skript übernimmt die Sammlung von Verbindungsinformationen der Server und führt dann das Shell-Skript auf den jeweiligen Systemen aus:
![Screenshot](https://github.com/martin8833/docker_out_of_the_box/blob/master/Shell_Skript_Grafik.png?raw=true "Übersicht")
Die Shell-Skript installiert auf einem dedizierten Registry Server die Docker Registry und legt eine initiale Konfiguration an. Das beinhaltet das Anlegen eines Initialusers, das Erstellen eines Self-Signed SSL-Zertifikates, sowie das Festlegen von diversen Laufzeit-Parametern wie z.B. der Port-Nummer (Default: 443). Danach wird auf den restlichen Servern Docker installiert und an die dortigen Docker-Instanzen das gerade erstellte Registry-Zertifikat verteilt.

Um das Skript zu starten, muss man die Dateien docker_ootb.ps1 und docker_master_script.sh in dem selben Ordner speichern (das genaue Verzeichnis kann frei gewählt werden). Danach muss das Skript docker_ootb.ps1 mithilfe von Powershell gestartet werden und den dortigen Anweisungen gefolgt werden. Das Skript kann nur auf Windows ausgeführt werden.

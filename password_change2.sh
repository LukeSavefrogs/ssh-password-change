#!/bin/bash

#************************************************************************
#                                                                       *
# Module Name : password_change.sh										*
# Author      : Luca Salvarani (luca.salvarani@ibm.com)					*
# Description : Questo script si propone di automatizzare il cambio 	*
# 				password in modo Platform Independent tra AIX e RedHat  *                                                                   *
#                                                                       *
# Edit Record (most recent edit at top of list)                         *
# Date          By      CF      Comments                                *
# ---------     ---     ----    --------------------------------------- *
# 
# 12-Ott-19		L.S.			Aggiunto prospetto edit record e ordinato 
# 								codice / documentazione
# 
# 13-Ott-19		L.S.			Ora la password non viene più scritta
#								in chiaro sul file history. Prima veniva 
#								stampata, ora viene usato un file di 
#								appoggio
#
#08-Ott-20		M.N				Aggiunto un piccolo controllo per la conn. sulla porta 22
#************************************************************************
#
# TODOS:
#		- Aggiungere installazione automatica sshpass
#		- Aggiungere controllo raggiungibilità porta 22 (SSH)
#			per evitare timeout inattesi 
#
#************************************************************************


# Per modificare i file: 								sed -i 's/\t/;/g; s/;*$//g' elenco_macchine.txt
# Per prendere le utenze con la password vecchia: 		awk -F"\t" '/Macchina/ { $3 = "";} {if ($3 == "") print; }' elenco_macchine.txt.old
: <<-EOCOMMENT
	https://stackoverflow.com/questions/714915/using-the-passwd-command-from-within-a-shell-script/43793195#43793195

	For those who need to 'run as root' remotely through a script logging into a user account in the sudoers file, I found an evil horrible hack, that is no doubt very insecure:

	sshpass -p 'userpass' ssh -T -p port user@server << EOSSH
	sudo -S su - << RROOT
	userpass
	echo ""
	echo "*** Got Root ***"
	echo ""
	#[root commands go here]
	useradd -m newuser
	echo "newuser:newpass" | chpasswd
	RROOT
	EOSSH
EOCOMMENT


# ------------------------------------		Variabili Globali		------------------------------------
# Flag
is_batch=false;
is_username_specified_manually_batch=false;
enable_pico_username_rule=false;
do_only_check=false;

# Dati per riepilogo
expire_date_list=();
macchine_password_errata=();


# File utilizzati
batch_filename="";
log_filename=./pwd_change_session-$(date +'%Y%m%d_%H.%M.%S').log


# Colori (http://web.theurbanpenguin.com/adding-color-to-your-output-from-c/)
default='\033[0m';
red='\033[31m';
yellow='\033[33m';
green='\033[32m';
light_blue='\033[0;34m';
cyan='\033[0;36m'
underlined='\033[4m';
bold='\033[1m';


# Dimensioni terminale 
terminal_columns=$(tput cols);
terminal_lines=$(tput lines);

# ------------------------------------		Program entry point (C-style)		------------------------------------
main () {
	# Check if needed commands are installed
	checkDependencies "sshpass" "sed" "awk" "ssh" || {
		exit 1;
	}


	# GETOPTS - Analizza tutti i parametri in ingresso allo script
	while getopts ":Pchf:" arg; do
		case $arg in
			P)
				enable_pico_username_rule=true;

				;;
			c)
				do_only_check=true;

				;;
			f)	# Valore del parametro f
				is_batch=true;
				batch_filename="${OPTARG}";
				
				[ ! -f "$batch_filename" ] && {
					printf "${red}ATTENZIONE${default}: File \"${batch_filename}\" non esistente. Procedura terminata\n\n";
					
					exit 1;
				}
				

				;;
			h) # Display help.
				usage;
				
				exit 0;
				;;
			:)	# Argomento mancante per un parametro obbligatorio (seguito nella definizione da :)
				printf "${red}ATTENZIONE${default}: Argomento mancante per il parametro ${OPTARG}\n\n";
				usage;
				
				exit 1;
				;;
			?)	# Parametro sconosciuto
				printf "${red}ATTENZIONE${default}: Parametro non riconosciuto dallo script\n\n";
				usage;
				
				exit 1;
				;;
		esac
	done
	
	# GETOPTS - Rimuove tutti i parametri già elaborati dal GETOPTS
	shift $((OPTIND-1));



	
	if $is_batch; then
		cambio_password_batch || {
			printf "${red}Procedura fallita${default} con modalità batch attivata. Esco\n";
			
			exit 1;
		}

		$do_only_check && {
			(( ${#expire_date_list[@]} != 0 )) && {
				closer_expire_date_ts=$(echo ${expire_date_list[@]} | tr ' ' '\n' | sort -n | sed -n '1p');
				closer_expire_date=$(date +"%d/%m/%Y" -d "@$closer_expire_date_ts" | sed -r 's/\<./\U&/g');

				local timestamp_now=$(date +%s);
				local timestamp_orario=$(date +%s -d"@$closer_expire_date_ts");
				local differenza_in_minuti=$(( (( ${timestamp_orario} - ${timestamp_now}) / 60) ));
				local differenza_in_ore=$(( ( $differenza_in_minuti / 60) ));
				local differenza_in_giorni=$(( ( $differenza_in_ore / 24) ));



				printf -- "\n\n-------------------------------------------------------------------------\n\n";
				printf "${bold}RIEPILOGO:${default}\n\n";
				printf "\t- Scadenza più vicina: %s (tra %s gg)\n\n" "$closer_expire_date" "$differenza_in_giorni"
				printf "\t- Totale macchine con password scaduta o utenza bloccata/inesistente: %d\n" "${#macchine_password_errata[@]}";
				for i in "${macchine_password_errata[@]}"; do printf "\t\t- $i\n"; done
				printf -- "\n\n-------------------------------------------------------------------------\\n";
			}
		}
	else
		# Controllo se i parametri in ingresso sono validi
		if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
			echo -e "${red}ATTENZIONE${default}: Numero di paramteri insufficiente\n";
			usage;

			exit 1;
		fi;
		
		local macchina=${1};
		local username=${2};
		local vecchia_password=${3};
		local nuova_password=${4};
		
		printf "Macchina: $macchina\n";
		printf "Username: $username\n";
		printf "Vecchia Password: $vecchia_password\n";
		printf "Nuova Password: $nuova_password\n\n\n";

		printf "Confermare cambio password? [y/n] ";
		
		user_confirmation || {
			printf "${yellow}Procedura abortita dall'utente${default}. Esco\n";
			
			exit 1;
		}

		cambio_password $macchina $username $vecchia_password $nuova_password || {
			printf "${red}Procedura fallita${default}. Esco\n";

			exit 1;
		}
	fi	
}



# ------------------------------------		Funzione CORE per il cambio		------------------------------------
# 	  
# 	Contiene la logica per il cambio password. Viene utilizzata internamente dalla funzione `cambio_password_batch` 
#		e all'interno del `main` per il cambio password di una macchina singola
# 	  
function cambio_password {
	local macchina="${1}";
	local username="${2}";
	local vecchia_password="${3}";
	local nuova_password="${4}";
	
	local comando_cambio_password="";
	local remote_system_os="";
	
	
	
	check_macchina_raggiungibile "$macchina" || {
		return 1;
	}


	# Controlla se la password inserita è valida e al tempo stesso restituisce il Sistema Operativo della macchina
	printf "Controllo validità password attuale: ";
	remote_system_os=$(sshpass -p $vecchia_password ssh -T -o StrictHostKeyChecking=no -o ConnectTimeout=10 $macchina -l $username 'uname' 2>/dev/null); 
	if [[ $? -eq 0 ]]; then 
		printf "${green}OK${default} - Password valida\n"; 
	else 
		printf "${red}ERRORE${default} - Password errata o scaduta\n";
		macchine_password_errata+=( "${username}@${macchina}" );
		
		return 1;
	fi;

	
	$do_only_check && {
		printf "\n${bold}Controllo scadenza password (chage)${default}\n";

		local chage_result="";

		if [[ "${remote_system_os^^}" =~ AIX ]]; then
			chage_result=$(remote_gio_aix_chage "$username" "$vecchia_password" "$macchina");

		elif [[ "${remote_system_os,,}" =~ linux ]]; then		
			chage_result=$(remote_linux_chage "$username" "$vecchia_password" "$macchina");

		else 
			printf "${red}ERRORE${default}: Sistema non supportato dallo script.\n";


			return 1;
		fi;

		printf "%s" "$chage_result";
		local expire_date_ts=$(date +%s -d "$(echo "$chage_result" | grep 'Password expires' | cut -d: -f2 | sed 's/^\s*//; s/\s*$//')");
		[[ ! -z "$expire_date_ts" ]] && expire_date_list+=( $expire_date_ts );
		
		return 0;
	}
	

	# Carica il file con la vecchia password e il binomio username:nuova_password per il chpasswd
	local remote_temp_file_path="/tmp/$username-$(($(date +%s%N)/1000))-$(echo $RANDOM | md5sum | awk '// { print $1 }')";
	local remote_temp_file_content="$vecchia_password\n${username}:${nuova_password}\n";
	$(printf "$remote_temp_file_content" | sshpass -p $vecchia_password ssh -T -o StrictHostKeyChecking=no $macchina -l $username "cat - > \"$remote_temp_file_path\"" >/dev/null 2>&1) || {
		printf "${red}ERRORE${default} (Errore durante la fase di caricamento password sul server)\n";

		return 1;
	}

	
	# Controlla se si tratta di una macchina AIX e cambia utenza e comando per cambio password
	# 	- AIX: Flag "-c" = Password non deve essere cambiata dall'utente al prossimo login.	(CI SERVE per evitare di doverla cambiare nuovamente manualmente)
	#	- LINUX: Flag "-c" = Formato di crittografia usato per la password passata!!!!
	#
	#	(AIX blocca la lettura della password da STDIN per passwd)
	if [[ "${remote_system_os^^}" =~ AIX ]]; then
		comando_cambio_password="sed -n '2p' \"$remote_temp_file_path\" | chpasswd -c";
	
	elif [[ "${remote_system_os,,}" =~ linux ]]; then		
		comando_cambio_password="sed -n '2p' \"$remote_temp_file_path\" | chpasswd";
		
	else 
		printf "${red}ERRORE${default}: Sistema non supportato dallo script.\n";


		return 1;
	fi;


	# Esegue la sessione remota per il cambio password.
	#
	# - Il flag "-tt" sull'ssh è NECESSARIO in quanto AIX rifiuta connessioni che non abbiano un terminale stdin allocato.
	remote_session=$(
		sshpass -p ${vecchia_password} ssh -tt -o StrictHostKeyChecking=no -o LogLevel=QUIET ${macchina} -l $username <<-END_OF_SCRIPT
			cat $remote_temp_file_path | sed -n '1p' | sudo -S su -; sudo su -;
			${comando_cambio_password};
			exit;
			rm "${remote_temp_file_path}";
			exit;
		END_OF_SCRIPT
	);

	write_to_log "INIZIO SESSIONE\n";
	write_to_log "${remote_session}\n";


	# Controlla se la password è stata cambiata correttamente
	printf "Controllo esito cambio password: ";
	$(sshpass -p $nuova_password ssh -T -o StrictHostKeyChecking=no $macchina -l $username 'echo' >/dev/null 2>&1) && {
		printf "${green}OK${default} (Password cambiata correttamente)\n\n";
		write_to_log "Controllo password: OK";
	} || {
		printf "${red}ERRORE${default} - Errore durante la fase di cambio password\n";
		printf "Risultato terminale:\n";
		printf "$remote_session\n";
		write_to_log "Controllo password: ERRORE\n";
	}
	write_to_log "FINE SESSIONE\n\n\n";


	return 0;
}




# ------------------------------------		Gestore operazione BATCH		------------------------------------
function cambio_password_batch {
	local header_line=$(sed '/^\s*$/d;' "$batch_filename" | sed -n '1p');

	if [[ ! "${header_line,,}" =~ (macchina) ]]; then
		printf "${red}ATTENZIONE${default}: Intestazione dei campi mancante o campo 'macchina' non specificato\n\n";
		usage;

		return 1;
	fi;
	

	local errors_in_row=false;

	local line_macchina="";
	local line_username="";
	local line_vecchia_password="":
	local line_nuova_password="";
	


	local separatore=$(get_separatore "$batch_filename");
	
	[ "$separatore" != "default" ] && IFS=$separatore;
	read -ra header <<< "$(sed -n '1p; q' "$batch_filename" | tr '[:upper:]' '[:lower:]' | sed 's/username/utenza/g; s/vecchia password/password/g; s/nuova password/nuova_password/g')";
	[ "$separatore" != "default" ] && unset IFS;

	position_of_macchine=$(for i in "${!header[@]}"; do [ "${header[$i]}" == "macchina" ] && echo $i; done);
	position_of_username=$(for i in "${!header[@]}"; do [ "${header[$i]}" == "utenza" ] && echo $i; done);
	position_of_vecchia_password=$(for i in "${!header[@]}"; do [ "${header[$i]}" == "password" ] && echo $i; done);
	position_of_nuova_password=$(for i in "${!header[@]}"; do [ "${header[$i]}" == "nuova_password" ] && echo $i; done);
	



	if [ -z "$position_of_username" ]; then
		printf "Non è stata inserita una UTENZA nel file. Inserire di seguito: ";
		while read global_utenza;
		do
			if [ ! -z "$global_utenza" ]; then 
				break; 
			fi;
		done;
		printf "\n\n";

		if $enable_pico_username_rule; then
			printf "${yellow}NOTA BENE${default}: \n\tL'utenza verrà formattata secondo lo standard AIX = UTENZA MAIUSCOLA / Linux = utenza minuscola.\n";
			printf "\tPer fornire una formattazione diversa fornire la colonna necessaria all'interno del file.\n\n";
			printf "\tEsempio:\n"
			printf "\t\t- AIX: ${global_utenza^^}\n"
			printf "\t\t- Linux: ${global_utenza,,}\n\n\n"
			printf "Sei d'accordo? [y/n] ";

			user_confirmation && {
				is_username_specified_manually_batch=true
			} || {
				printf "${yellow}Procedura abortita dall'utente${default}. Esco\n";
				return 1;
			}
		fi;
	fi;
	



	if [ -z "$position_of_vecchia_password" ]; then
		printf "Non è stata inserita una VECCHIA PASSWORD nel file. Inserire di seguito: ";
		while read global_vecchia_password;
		do
			if [ ! -z "$global_vecchia_password" ]; then break; fi;
		done;
		printf "\n\n";
	fi;
	
	if [ -z "$position_of_nuova_password" ] && ! $do_only_check ; then
		printf "Non è stata inserita una NUOVA PASSWORD nel file. Inserire di seguito: ";
		while read global_nuova_password; 
		do
			if [ ! -z "$global_nuova_password" ]; then break; fi;
		done;
		printf "\n\n";
	fi;

	total_rows=$(sed '/^\s*$/d;' "$batch_filename" | sed '1d;' | wc -l);
	current_row=0;
	while IFS=$'\n' read -r -u3 line; 
	do
		errors_in_row=false;
		((current_row++))
		
		[ "$separatore" != "default" ] && IFS=$separatore
		read -ra ARRAY <<< "$line";
		[ "$separatore" != "default" ] && unset IFS;
		
		# Reset variabili
		line_macchina="";
		line_username="":
		line_vecchia_password="":
		line_nuova_password="";
		
		
		# Imposto nuove variabili
		line_macchina="${ARRAY[$position_of_macchine]}";
		
		printf "${yellow}Modalità batch attivata${default} ($current_row su $total_rows)\n";
		printf "Macchina: $line_macchina\n";
		

		
		if [ -z "$position_of_username" ]; then
			line_username="$global_utenza";
		else
			# Se nell'header è stato specificata la presenza di una vecchia password ma questa non viene trovata nella riga
			[ -z "${ARRAY[$position_of_username]}" ] && {
				printf "${red}ERRORE${default}: Utenza NON SPECIFICATA\n";
				errors_in_row=true;
				
			} || {
				line_username="${ARRAY[$position_of_username]}";
				printf "Username: $line_username\n";
			}
		fi;
			
			
			
		if [ -z "$position_of_vecchia_password" ]; then
			line_vecchia_password="$global_vecchia_password";
		else
			# Se nell'header è stato specificata la presenza di una vecchia password ma questa non viene trovata nella riga
			[ -z "${ARRAY[$position_of_vecchia_password]}" ] && {
				printf "${red}ERRORE${default}: Vecchia password NON SPECIFICATA\n";
				errors_in_row=true;
				
			} || {
				line_vecchia_password="${ARRAY[$position_of_vecchia_password]}";
				printf "Vecchia Password: $line_vecchia_password\n";
			}
		fi;
		
		
		
		
		if [ -z "$position_of_nuova_password" ];then
			line_nuova_password="$global_nuova_password";
		else
			# Se nell'header è stato specificata la presenza di una nuova password ma questa non viene trovata nella riga
			[ -z "${ARRAY[$position_of_nuova_password]}" ] && {
				printf "${red}ERRORE${default}: Nuova password NON SPECIFICATA\n\n";
				errors_in_row=true;
				
			} || {
				line_nuova_password="${ARRAY[$position_of_nuova_password]}";
				printf "Nuova Password: $line_nuova_password\n\n\n";
			}
		fi;
		
		
	
	
		# -----------------------	PICO USERNAME CUSTOM RULE	-----------------------
		#
		# 	Nel progetto PICO la nomenclatura dei server rispetta lo standard X = AIX, R = RedHat. In tali server lo username è QUASI sempre: 
		#		- MAIUSCOLO nel caso di AIX e 
		#		- MINUSCOLO nel caso di Linux.
		#
		#	Come specificato nel DISCLAIMER al momento dell'immissione MANUALE dell'utenza, in caso si OMETTA dal file la colonna dedicata allo
		#		username verrà utilizzato come default questo standard.
		#
		$is_username_specified_manually_batch && {
			[[ ! "${line_macchina}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && [[ "${line_macchina^^}" =~ (TRNX|C2CX) ]] && line_username="${line_username^^}" || line_username="${line_username,,}";
		}


		
		# Se ci sono stati errori nella ricerca dei dati -> passa alla macchina successiva
		$errors_in_row && {
			printf "${red}ATTENZIONE${default}: Ci sono errori nel file fornito per la riga corrente. Consultare la sezione help\n\n\n";
		} || {
			cambio_password $line_macchina $line_username $line_vecchia_password $line_nuova_password;
		}
		
		
		printf "\n\n";
	done 3<<< $(sed '/^\s*$/d; /^\s*#/d' "$batch_filename" | sed '1d;');


	return 0;
}





# ------------------------------------		Separatore Header file di Batch		------------------------------------
# 	  
#	Controlla l'header del file usato per il cambio password in modalità batch per determinare il tipo di "separatore" 
#	utilizzato per i vari campi all'interno del file. Viene utilizzata internamente dalla funzione `cambio_password_batch`
#
#	Possibili valori: [TAB/SPACE] [,] [;]
# 	 
function get_separatore {
	local header=$(sed '/^\s*$/d;' "$batch_filename" | sed -n '1p');
	
	if [[ "$header" =~ (,) ]]; then
		printf "," ;
	elif [[ "$header" =~ (;) ]]; then 
		printf ";";
	else
		printf "default";
	fi;

	return 0;
}


# ------------------------------------		Funzione controllo Hostname		------------------------------------
# 	  
# 	Esegue dei controlli incrociati tra file hosts e DNS per verificare che la macchina sia conosciuta e in caso contrario
#	restituire all'utente un errore parlante. Viene utilizzata internamente dalla funzione `cambio_password` 
# 	  
function check_macchina_raggiungibile {
	local macchina="$1";


	# Controlla prima se la macchina passata non è un IP
	if [[ ! "${macchina}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then


		# Controlla se esiste la macchina nel FILE HOSTS
		grep -Pq "(^|\s)${macchina}(?=\s|$)" /etc/hosts || {
			macchine_hosts=$(grep ${macchina} /etc/hosts | awk '{$1=""; print}' | tr -d '\n\r' | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//');


			# Se ha trovato macchine simili ma non quella esatta le mostra a video
			[ ! -z "$macchine_hosts" ] && {
				printf "${red}ERRORE${default} - Macchina ${macchina} non trovata [ ${macchine_hosts} ]\n\n";


				return 1;
			} || {
				# Se trova la macchina nel DNS allora continua ma mostra una INFO a schermo
				host "${macchina}" >/dev/null 2>&1 && {
					printf "${cyan}INFO${default} - Macchina trovata nel DNS\n";


					return 0;
				} || {
					printf "${red}ERRORE${default} - Macchina ${macchina} non censita nel file hosts\n\n";


					return 1;
				}
			}
		}


	fi;

	#Check sulla porta 22 della macchina con un timeout di 3 secondi per vedere se risulta raggiungibile

	$(timeout 3 bash -c 'cat < /dev/null > /dev/tcp/'${macchina}'/22') || { printf "${red}ERRORE${default} - Macchina ${macchina} non raggiungibile sulla porta 22\n\n" && return 1; }


	#From the bash reference:
	#/dev/tcp/host/port
	#If host is a valid hostname or Internet address, and port is an integer
	#port number or service name, Bash attempts to open a TCP connection to the
	#corresponding socket.

	return 0;
}

# ------------------------------------		HELP / USAGE		------------------------------------
# 	  
#	Mostra a video la descrizione e un manuale per il programma 
# 
function usage {
		{
			script_name=$(basename "$0");
			indent_1=$'\t';
			indent_2=$'\t\t';
			indent_3=$'\t\t\t';

			printf "${script_name^^}(1)\t\t\t\t\t\t\tUser Commands\t\t\t\t\t\t\t${script_name^^}(1)\n\n";

			printf "${bold}NAME${default}\n";
			printf "${indent_1}$script_name - Utility per il cambio password automatizzato\n\n";


			printf "${bold}SYNOPSIS${default}\n";
			printf "${indent_1}${yellow}${script_name}${default} ${underlined}MACCHINA${default} ${underlined}USERNAME${default} ${underlined}VECCHIA_PASSWORD${default} ${underlined}NUOVA_PASSWORD${default}\n";
			printf "${indent_1}${yellow}${script_name}${default} -f ${underlined}BATCH_FILE${default} [ -P ] [ -c ] \n";
			printf "${indent_1}${yellow}${script_name}${default} [ -h ]\n\n";


			printf "${bold}DESCRIPTION${default}\n";
			printf "${indent_1}Automatizza controllo e cambio password in modo Platform Independent tra AIX e RedHat.\n\n";
			printf "${indent_1}Per funzionare è NECESSARIO che sia installato sshpass, altrimenti verrà mostrato un\n"; 
			printf "${indent_1}errore a schermo e la procedura terminerà.\n\n";

			printf "${bold}OPTIONS${default}\n";
			printf "${indent_1}-f\t";
			printf "File da utilizzare per cambiare una lista di macchine in modalità batch. Fare riferimento alla Guida sotto.\n\n";
			printf "${indent_1}-P\t";
			printf "Indica allo script di usare lo Standard PICO per le utenze (utenza MAIUSCOLA per AIX e minuscola per Linux)\n\n";
			printf "${indent_1}-c\t";
			printf "Esegue solo un controllo della scadenza delle password (chage -l) su tutte le macchine (compreso AIX) ed esce.\n";
			printf "${indent_2}In questa modalità non vengono cambiate password, anche se specificate. Al termine verrà visualizzata\n";
			printf "${indent_2}una breve schermata con alcune statistiche e dettagli.\n\n";
	

			printf "${bold}GUIDE${default}\n";
			printf "${indent_1}Lo script può essere eseguito in modalità singola (in assenza di flag) o batch:\n\n";
			printf "${indent_1}${bold}Batch - Guida${default}\n";
			printf "${indent_2}Permette il cambio password (o solo controllo se è stato specificato il flag ${underlined}-c${default}) per un elenco di macchine\n";
			printf "${indent_2}definito attraverso un file.\n";
			printf "${indent_2}Tale file deve NECESSARIAMENTE contenere come prima riga un'intestazione contenente il nome\n";
			printf "${indent_2}dei parametri che si intende passare al programma:\n\n";

			printf "${indent_2}- ${yellow}MACCHINA${default}: OBBLIGATORIO, \n";
			printf "${indent_3}identifica la colonna contenente gli Hostname o gli IP delle macchine\n\n";
			printf "${indent_2}- ${yellow}UTENZA${default}: Opzionale, \n";
			printf "${indent_3}se non specificato verrà richiesta all'inizio della procedura.\n";
			printf "${indent_3}Se è stato specificato il flag -P lo username verrà formattato secondo lo ${underlined}standard${default}\n";
			printf "${indent_3}utilizzato nel progetto PICO, altrimenti sarà uguale per tutte le macchine.\n\n";
			printf "${indent_2}- ${yellow}VECCHIA_PASSWORD${default}: Opzionale,\n";
			printf "${indent_3}se non specificata verrà richiesta all'inizio della procedura e sarà la stessa per tutte le macchine.\n\n";
			printf "${indent_2}- ${yellow}NUOVA_PASSWORD${default}: Opzionale,\n";
			printf "${indent_3}se non specificata verrà richiesta all'inizio della procedura e sarà la stessa per tutte le macchine.\n\n";


			printf "${indent_2}E' possibile ${underlined}COMMENTARE${default} una riga nel file escludendola dall'esecuzione dello script ponendo\n"; 
			printf "${indent_2}il carattere '#' all'inizio della riga.\n\n";
			printf "${indent_2}L'${underlined}ORDINE${default} utilizzato nella definizione dei campi dell'intestazione definirà quello che dovrà essere utilizzato\n";
			printf "${indent_2}per tutte le righe del file.\n\n";
			printf "${indent_2}E' possibile inoltre separare i campi con un carattere ${yellow}TAB${default} (ottenuto anche da un copia-incolla da Excel),\n";
			printf "${indent_2}il carattere '${yellow};${default}' e il carattere '${yellow},${default}'.\n";
			printf "${indent_2}Esempi:\n";
			printf "${indent_3}MACCHINA	UTENZA		VECCHIA_PASSWORD\n";
			printf "${indent_3}fsp01trnr	itxxxxxx	miaVecchiaPassword\t<--- ${green}Valido${default}\n\n";
			printf "${indent_3}${yellow}NOTE${default}: All'inizio verra' richiesta la nuova password.\n\n\n"
			printf "${indent_3}MACCHINA;UTENZA;VECCHIA_PASSWORD;NUOVA_PASSWORD\n";
			printf "${indent_3}123.456.789.1;itxxxxxx;miaVecchiaPassword;miaNuovaPassword\t<--- ${green}Valido${default}\n\n\n";
			printf "${indent_3}MACCHINA	UTENZA		VECCHIA_PASSWORD\n";
			printf "${indent_3}123.456.789.1;itxxxxxx;miaVecchiaPassword\t<--- ${red}Errato${default}\n\n";
			printf "${indent_3}${yellow}NOTE${default}: Il separatore e' diverso da quello definito nell'intestazione\n\n\n"
			


			printf "\n";

			printf "${bold}DIAGNOSTICS${default}\n";
			printf "${indent_1}Lo script potrebbe restituire i seguenti errori:\n\n";
			printf "${indent_1}${red}ERRORE${default} - Password errata o scaduta\n";
			printf "${indent_2}Indica che lo USERNAME inserito non è corretto o che la PASSWORD inserita è errata\n";
			printf "${indent_2}Può indicare anche che la connessione ssh è andata in Timeout\n\n";
			printf "${indent_2}In modalità batch il cambio password per la macchina corrente è stato saltato\n\n";
			
			printf "${indent_1}${red}ERRORE${default} - Macchina {macchina} non trovata [ {macchine_simili} ]\n";
			printf "${indent_2}Indica che da una ricerca sul file hosts non è stata trovata una corrispondenza esatta alla macchina cercata.\n";
			printf "${indent_2}Tra le parentesi quadre si indicano le macchine simili trovate.\n\n";
			printf "${indent_2}In modalità batch il cambio password per la macchina corrente è stato saltato\n\n";
			
			printf "${indent_1}${red}ERRORE${default} - Macchina {macchina} non censita nel file hosts\n";
			printf "${indent_2}Indica che da una ricerca sul file hosts non è stata trovata nessuna corrispondenza alla macchina cercata\n";
			printf "${indent_2}e da una ricerca DNS tramite comando 'host' non risulta essere mappata una macchina con tale hostname.\n";
			printf "${indent_2}Procedere ad una conessione con IP o mappare la macchina sul file hosts\n\n";
			printf "${indent_2}In modalità batch il cambio password per la macchina corrente è stato saltato\n\n";
			
			printf "${indent_1}${red}ERRORE${default}: Utenza/Vecchia password/Nuova password NON SPECIFICATA\n";
			printf "${indent_2}Modalità Batch, indica che uno dei parametri riportati nell'errore non è stato trovato nella riga del file.\n";
			printf "${indent_2}Questo può succedere se si è lasciato quel campo vuoto nonostante esso sia stato definito nell'intestazione o\n";
			printf "${indent_2}se il separatore utilizzato in quella riga è diverso da quello utilizzato nell'intestazione.\n\n";
			printf "${indent_2}Il cambio password per la macchina corrente è stato saltato\n\n";
			

			printf "${bold}EXAMPLES${default}\n";
			printf "${indent_1}Controlla quanto manca alla scadenza della password di tutte le macchine salvate nel file\n";
			printf "${indent_1}elenco_macchine.txt usando la regola PICO:\n";
			printf "${indent_2}${yellow}${script_name}${default} -f elenco_macchine.txt -P -c\n\n\n";
			printf "${indent_1}Cambia la password di tutte le macchine salvate nel file elenco_macchine.txt\n";
			printf "${indent_2}${yellow}${script_name}${default} -f elenco_macchine.txt\n\n\n";
			printf "${indent_1}Cambia la password di tutte le macchine salvate nel file elenco_macchine.txt usando la regola PICO:\n";
			printf "${indent_2}${yellow}${script_name}${default} -f elenco_macchine.txt -P\n\n\n";
			printf "${indent_1}Cambia la password di una singola macchina:\n";
			printf "${indent_2}${yellow}${script_name}${default} hostname_macchina my_username my_old_password my_new_password\n\n\n";	


			printf "${bold}AUTHOR${default}\n";
			printf "${indent_1}Luca Salvarani (Email: luca.salvarani@ibm.com - luca.salvarani@re-edit.it)\n";
			printf "\n\n";

			return 0;
		} #| less -R
}

function write_to_log {
	trailing_data="[ $(date "+%d-%m-%Y %H:%M") ]";
	printf "$trailing_data - $@" >> "$log_filename";

	return 0;
}

# ------------------------------------		User Confirmation		------------------------------------
# 	  
#	Snippet per richiesta di conferma all'utente.  
# 
function user_confirmation {
	while read;
	do
		[ -z "$REPLY" ] && continue;

		[[ $REPLY =~ ^[Yy]$ ]] && break;

		return 1;
	done;
	printf "\n\n";

	return 0;
}

# Originale: GioIan 25/05/2017 - aix_chage
# Modficata: Salvarani 30/12/2019 - remote_gio_aix_chage
# Modficata: Salvarani 30/01/2019 - Modificato formato output data e rimosso output Username
#
# Descrizione:
#	Lo script, analizzando i file di sistema, mostra la scadenza della password per l'utenza fornita
function remote_gio_aix_chage {
	local ssh_username="$1";
	local ssh_password="$2";
	local ssh_macchina="$3";

	local search_username="${4:-$1}";
	local unique_session_id="$(echo $RANDOM | md5sum | awk '// { print $1 }')";

	result=$(sshpass -p $ssh_password ssh -o LogLevel=QUIET -tt $ssh_username@$ssh_macchina <<-END_OF_SSH
		printf "$ssh_password\\n" | sudo -S su -; sudo su -

		# Funzioni
		DTCe2h () {
			# Date/Time converter from Epoch to Human
			UnixTime=\$1
			perl -e "
				my \\\$ut = \$UnixTime;
				my @abbr = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
				my (\\\$year,\\\$month,\\\$day,\\\$hour,\\\$min,\\\$sec) = (localtime(\\\$ut))[5,4,3,2,1,0];
				
				# Old format:
				# printf(\\"%04d-%02d-%02d %02d:%02d:%02d\\", \\\$year+1900, \\\$month+1, \\\$day, \\\$hour,\\\$min,\\\$sec);

				printf(\\"%s %02d, %04d\\", \\\$abbr[\\\$month], \\\$day, \\\$year+1900);
			";
		}
		
		utente_da_cercare=$search_username

		main () {
			# Utente conosciuto ?
			if [ \$(cat /etc/passwd | grep "^\$utente_da_cercare:"|wc -l) -eq 0 ]; then
				echo "ERRORE - Lo user \$utente_da_cercare non e' definito a sistema"
				
				return 1;
			fi


			if [ \$(grep -p "\$utente_da_cercare:" /etc/security/passwd | grep lastupdate | wc -l) -eq 0 ]; then
				echo "ERRORE - Lo user \$utente_da_cercare non e' presente nel file /etc/security/passwd"
				
				return 1;
			fi
			
			LastPwChgInSecs=\$(grep -p "\$utente_da_cercare:" /etc/security/passwd | grep lastupdate | sed "s/.*lastupdate = //")
			LastPwChgInDays=\$(expr \$LastPwChgInSecs \\/ 86400 )
			LastPwChg=\$(DTCe2h \$LastPwChgInSecs | sed "s/\\(....\\).\\(..\\).\\(..\\) \\(.*\\)\$/\\3-\\2-\\1 \\4/")
			

			if [ \$(lsuser -a maxage \$utente_da_cercare | wc -l) -eq 0 ]; then
				echo "ERRORE - Lo user \$utente_da_cercare non e' conosciuto dal comando lsuser"
				
				return 1;
			fi
			
			ExpInWks=\$(lsuser -a maxage \$utente_da_cercare | sed "s/.*maxage=//");
			ExpInDays=\$(expr \$ExpInWks \\* 7);
			ExpInSecs=\$(expr \$ExpInDays \\* 86400);

			# Unsuccessful login Count
			UnLgCnt=\$(lsuser -a unsuccessful_login_count \$utente_da_cercare | grep "="|sed "s/^.*=//");
			# Is Account Locked?
			AccLckd=\$(lsuser -a account_locked \$utente_da_cercare | sed "s/^.*=//");

			# Minimum number of days between password change
			MinDaysChange=\$(expr \$(lsuser -a minage \$utente_da_cercare | sed "s/^.*=//") \\* 7);

			# Maximum number of days between password change
			MaxDaysChange=\$(expr \$(lsuser -a maxage \$utente_da_cercare | sed "s/^.*=//") \\* 7);

			# Number of days of warning before password expires
			AccExpires=\$(lsuser -a expires \$utente_da_cercare | sed "s/^.*=//");
			if [ "\$AccExpires" -eq 0 ]; then
				AccExpires="never";
			fi;

			# Number of weeks after maxage. After this period the user cannnot login or change password. Needs help of an Administrator
			InactPwInWeeks=\$(lsuser -a maxexpired \$utente_da_cercare | sed "s/^.*=//");
			if [[ "\$InactPwInWeeks" == -1 ]]; then 
				InactPw="never";
			elif [[ "\$InactPwInWeeks" == 0 ]]; then 
				InactPwInWeeks=\$ExpInWks; 

				InactPwInDays=\$(expr \$InactPwInWeeks \\* 7);
				InactPwInSecs=\$(expr \$InactPwInDays \\* 86400);
				InactDateInSecs=\$(expr \$LastPwChgInSecs \\+ \$InactPwInSecs);
				InactPw=\$(DTCe2h \$InactDateInSecs | sed "s/\\(....\\).\\(..\\).\\(..\\) \\(.*\\)\$/\\3-\\2-\\1 \\4/");
			else 
				InactPwInDays=\$(expr \$InactPwInWeeks \\* 7);
				InactPwInSecs=\$(expr \$InactPwInDays \\* 86400);
				InactDateInSecs=\$(expr \$ExpInSecs \\+ \$InactPwInSecs);
				InactPw=\$(DTCe2h \$InactDateInSecs | sed "s/\\(....\\).\\(..\\).\\(..\\) \\(.*\\)\$/\\3-\\2-\\1 \\4/");
			fi;

			WarnPassExp=\$(lsuser -a pwdwarntime \$utente_da_cercare | sed "s/^.*=//");
			if [ "\$WarnPassExp" -eq 0 ]; then
				WarnPassExp="never"
			fi;
			# Gecos=\$(lsuser -a gecos \$utente_da_cercare | sed "s/^.*=//")
		
			# ExpDateInDays=\$(expr \$LastPwChgInDays \\+ \$ExpInDays)
			ExpDateInSecs=\$(expr \$LastPwChgInSecs \\+ \$ExpInSecs)
			

			# OggiInSecs=\$(date +%s)
			# OggiInDays=\$(expr \$OggiInSecs \\/ 86400 )
			# ScadPwInDays=\$(expr \$ExpDateInDays \\- \$OggiInDays)
			# ScadPwInSecs=\$(expr \$ExpDateInSecs \\- \$OggiInSecs)

			# ScadPw=\$(DTCe2h \$ExpDateInSecs)
			# ScadPw=\$(DTCe2h \$ExpDateInSecs | cut -c 1-10|sed "s/^\\([0-9]*\\)-\\([0-9]*\\)-\\([0-9]*\\)/\\3-\\2-\\1/")
			ScadPw=\$(DTCe2h \$ExpDateInSecs | sed "s/\\(....\\).\\(..\\).\\(..\\) \\(.*\\)\$/\\3-\\2-\\1 \\4/")
			
			# Still have to find how to emulate "Password inactive" and "Account expires" output
			printf "${unique_session_id}%-56s: %s\n"	"Last password change" 									"\$LastPwChg";
			printf "${unique_session_id}%-56s: %s\n" 	"Password expires" 										"\$ScadPw";
			printf "${unique_session_id}%-56s: %s\n" 	"Password inactive"										"\$InactPw";
			printf "${unique_session_id}%-56s: %s\n" 	"Account expires"										"\$AccExpires";
			
			printf "${unique_session_id}%-56s: %s\n" 	"Minimum number of days between password change" 		"\$MinDaysChange";
			printf "${unique_session_id}%-56s: %s\n" 	"Maximum number of days between password change" 		"\$MaxDaysChange";
			printf "${unique_session_id}%-56s: %s\n" 	"Number of days of warning before password expires" 	"\$WarnPassExp";

			# printf "${unique_session_id}%-56s: %s\n" 	"Unsuccessful login count" 								"\$UnLgCnt";
			# printf "${unique_session_id}%-56s: %s\n" 	"Account locked" 										"\$AccLckd";

			# echo "${unique_session_id}Gecos                    : \$Gecos"

			return 0;
		}
		
		main;

		exit 
		exit
	END_OF_SSH
	);

	echo "$result" | grep -E "ERRORE|$unique_session_id" | grep -vE "printf|echo" | sed "s/^$unique_session_id//; /Unsuccessful login count/s/^/\n${bold}Altre informazioni${default}\n/;"
}

function remote_linux_chage {
	local ssh_username="$1";
	local ssh_password="$2";
	local ssh_macchina="$3";

	local search_username="${4:-$1}";
	local unique_session_id="$(echo $RANDOM | md5sum | awk '// { print $1 }')";

	result=$(sshpass -p $ssh_password ssh -o LogLevel=QUIET -tt $ssh_username@$ssh_macchina <<-END_OF_SSH
			printf "$ssh_password\\n" | sudo -S su -; sudo su -
			chage -l $search_username | sed "s/^/${unique_session_id}/"

			exit;
			exit;
		END_OF_SSH
	);

	echo "$result" | grep -E "ERRORE|$unique_session_id" | grep -v "sed" | sed "s/^$unique_session_id//"
}

# Dependencies check function: 
#       Checks if all programs passed as parameters exist. 
#       Prints to stdOut programs that weren't found
# 
#       Usage: 
#           checkDependencies program1 program2 program3 || { list_of_commands; }
# 
function checkDependencies {
	# Colors
	local red='\033[0;31m';
	local green='\033[0;32m';
	local yellow='\033[0;33m';
	local default='\033[0m';
	
	# Declare variables
    local progs="$@";
    local not_found_counter=0; 
    local total_programs=$(echo "$progs" | wc -w); 

	# Check every program
    for p in ${progs}; do
        command -v "$p" >/dev/null 2>&1 || {
            printf "${yellow}WARNING${default} - Program required is not installed: $p\n";

            not_found_counter=$(expr $not_found_counter + 1);
        }
    done

	# Print error
    [[ $not_found_counter -ne 0 ]] && {
        printf "\n"
        printf "${red}ERROR${default} - %d of %d programs were missing. Execution aborted\n" "$not_found_counter" "$total_programs";

        return 1;
    }

    return 0;
}



# Start main function
main "$@"
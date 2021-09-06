#!/usr/bin/env bash
# simple installer
# checks for coreelec host
# exitence of entware environment and needed packages
# copies script to /opt/bin
# copies conky config to ~/.conky/
# C pl groves gmail Nov 2020

  # check whoami, !root
  if [ "$EUID" -eq 0 ]
  then
      echo "Please do not run as root"
      exit 1
  fi

  # check if files exist
    [ -r ./coreelec-conky.sh ] ||
      { echo "Can't find script to install"; exit 1; }
    echo "found script"
    [ -r ./coreelec-conkyrc ] ||
      { echo "Can't find conky config"; exit 1; }
    echo "found conky config"

  if timeout 1 ping -c 1 "$1" >/dev/null 2>&1
  then # argument given then ping to see if it's a host
      HOSTS=("$1")
      n=1
  else

     # find media renders on local network or enter manually
       if command -v gssdp-discover >/dev/null
       then # use gssdp to find media renders
           echo "Searching for kodi"
           MY_INTERFACE=$(awk '/^d/ {print $5;exit}' < <(ip route show))

           KODIS=($(gssdp-discover -i "$MY_INTERFACE" --timeout=3 --target=urn:schemas-upnp-org:device:MediaRenderer:1|grep Location|sed 's:^.*/\([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\).*:\1:'))

           if [ "${#KODIS[@]}" -gt 1 ]
           then echo -e "\n** Select Destination *******"
                for kodi in "${KODIS[@]}"
                do  HOSTS+=($(grep -oP "$kodi[[:space:]]+\K[[:alnum:]]+" /etc/hosts))
                    ((i++))
                    echo "${i}) ${HOSTS[((i-1))]} ${kodi}"
                done
     
                echo
                read -rp "Choose 1 of ($i): " n
                if [[ ! "${n}" =~ ^[0-9]+$ ]]
                then echo "Invalid entry... Goodbye!"; exit 1
                elif [[ "${n}" -lt 1 || "${n}" -gt "${i}" ]]
                then echo "Invalid entry... Goodbye!"; exit
                fi
           else HOSTS=($(grep -oP "${KODIS[0]}[[:space:]]+\K[[:alnum:]]+" /etc/hosts))
                n=1
                echo "${HOSTS[*]} ${KODIS[*]}"
           fi

       else # manual input of host
           echo
           read -rp "enter coreELEC ip address/hostname " ip_host

           re='^(0*(1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))\.){3}'
           re+='0*(1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))$'

           if [[ "${ip_host}" =~ $re ]]
           then timeout 2 ping -c 1 "$ip_host" >/dev/null 2>&1 ||
                { echo "Can't reach ${ip_host} try again"; exit 1; }
           else timeout 2 ping -c 1 "$ip_host" >/dev/null 2>&1 ||
                { echo "Can't reach ${ip_host} try again"; exit 1; }
           fi
           HOSTS=( "${ip_host}" )
           n=1
       fi
  fi
#
  HOST="${HOSTS[((n-1))]}"
  [ -z "${HOST}" ] && HOST="${KODIS[((n-1))]}"

  echo -e "\nChecking ${HOST}"

  # can we ssh with passkey, do we need authentication?
    ssh -vvv -o PasswordAuthentication=no  -o BatchMode=yes root@"${HOST}" 2>&1 exit |
             grep -q "Next authentication method:" 

    case "${PIPESTATUS[0]}" in
        0) # can connect
            case "${PIPESTATUS[1]}" in
                0)
                    echo -e " have passkey\n consider adding socket to ~/.ssh/config"
                  ;;
                1)
                    echo " have socket defined in ~/.ssh/config"
                   ;;
            esac
           ;;
        255)
            echo -e " password required\n http://www.linuxproblem.org/art_9.html"
            exit 255
           ;;
        *)
          echo "do something"
          exit 2
         ;;
    esac

  echo -e "\nInstalling to ${HOST}"
  
  # check for entware and intalled packages
    if ssh root@"${HOST}" '[ -f /storage/.opt/bin/opkg ]'
    then echo -e "\nentware is available"
    else echo -e "\n please install entware\n  https://discourse.coreelec.org/t/what-is-entware-and-how-to-install-uninstall-it/1149"
         exit 1
    fi

  # check for entware packages or install
    install="/opt/bin/opkg install "
    Packages=('bash' 'bind-dig' 'coreutils-date' 'coreutils-df' 'coreutils-sort' 'coreutils-stat' 'procps-ng-top' 'procps-ng-ps')
    mapfile -t Installed < <(ssh root@"${HOST}" /opt/bin/opkg list-installed | awk '{print $1}')
    for package in "${Packages[@]}"; do
     if [[  " ${Installed[@]} " =~ " $package " ]]
     then echo -ne " found ${package} from entware          \r"; sleep 0.5
     else echo -e " ${package} not found ... installing\n"
          ssh root@"${HOST}" "${install} $package" >/dev/null
          echo
     fi
    done
    echo -e "\r All packages installed            \n"

  # we can ssh w/o password, have entware packages installed

  # copy script to /storage/.opt/bin, chmod +x 

  # found existing script
    if ssh root@"${HOST}" '[ -r /storage/.opt/bin/coreelec-conky.sh ]'
    then # file exists
           read -rp "coreelec-conky.sh script exists, replace [y/N] " reply
              case "${reply}" in
                  [yY][eE][sS]|[yY]) 
                      echo "moving script to coreelec-conky.sh.bak"
                      ssh root@"${HOST}" mv /storage/.opt/bin/coreelec-conky.sh /storage/.opt/bin/coreelec-conky.sh.bak
                      ;;
                  *)
                      echo "Overwriting existing coreelec-conky.sh script"
                      ;;
              esac
    fi

 # copy script and make executable 
   echo "copying coreelec-conky.sh and setting execute bit"
   scp ./coreelec-conky.sh  root@"${HOST}":/storage/.opt/bin/
   ssh root@"${HOST}" 'chmod +x /storage/.opt/bin/coreelec-conky.sh'

 # install conkyrc

   # modifying conkyrc with $HOST
     echo -e "\nmodifying coreelec-conkyrc with ${HOST}"
     sed  -i -e "s/<HOST>/${HOST}/g" ./coreelec-conkyrc

   read -rp "Do you wish to install and run conky on this computer?  [y/N] " reply
   case "${reply}" in
        [yY][eE][sS]|[yY])

            # copy conky config to home/.conky
            [ -d ~/.conky ] \
            || { echo "creating directory ~/.conky/"; mkdir ~/.conky; }
            [ -f ~/.conky/coreelec-conkyrc ] \
            || { echo "adding coreelec-conkyrc to ~/.conky/"; cp ./coreelec-conkyrc ~/.conky/; }

            # run conky 
            echo " Now run: conky -c ~/.conky/coreelec-conkyrc"
            conky -c ~/.conky/coreelec-conkyrc
            ;;
        *) exit;;
   esac

  exit 0

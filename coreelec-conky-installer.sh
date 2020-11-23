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

  # argument given then ping to see if it's a host
  if timeout 1 ping -c 1 "$1" >/dev/null 2>&1
  then
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
                echo "${HOSTS[0]} ${KODIS[@]}"
           fi

       else # manual input of host
           echo
           read -rp "enter coreELEC ip address/hostname " ip_host

           re='^(0*(1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))\.){3}'
           re+='0*(1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))$'

           if [[ $ip_host =~ $re ]]
           then timeout 2 ping -c 1 "$ip_host" >/dev/null 2>&1 ||
                { echo "Can't reach ${ip_host} try again"; exit 1; }
           else timeout 2 ping -c 1 "$ip_host" >/dev/null 2>&1 ||
                { echo "Can't reach ${ip_host} try again"; exit 1; }
           fi
           HOSTS=($ip_host)
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
    then echo -e "\n entware is available"
    else echo -e "\n please install entware\n  https://discourse.coreelec.org/t/what-is-entware-and-how-to-install-uninstall-it/1149"
         exit 1
    fi

  # check for entware packages or install
    install="/opt/bin/opkg install "
    Packages=(coreutils-df coreutils-stat bind-dig procps-ng-watch ip-full bash coreutils-sort coreutils-date procps-ng-top)
    mapfile -t Installed < <(ssh root@"${HOST}" /opt/bin/opkg list-installed | awk '{print $1}')
    for package in "${Packages[@]}"; do
     if [[  " ${Installed[@]} " =~ " $package " ]]
     then echo -ne " found ${package} from entware          \r"; sleep 0.5
     else echo -e " ${package} not found ... installing\n"
          ssh root@"${HOST}" "${install} $package" >/dev/null
          echo
     fi
    done
    echo -e "\rAll packages installed            \n"

  # can ssh w/o password, have entware packages installed
   # copy script to /storage/.opt/bin, chmod +x 
    # install conkyrc

  if ssh root@"${HOST}" '[ -r /storage/.opt/bin/coreelec-conky.sh ]'
  then # file exists
         read -rp "file exists, replace [y/N] " reply
         reply=${reply:-N}
         if [[ "${reply}" = +(N*|n*) ]]
         then echo "exiting... Goodbye!"; exit 1
         elif [[ "${reply}" = +(Y*|y*) ]]
         then echo "moving existing script to coreelec-conky.sh.bak"
              ssh root@"${HOST}" mv /storage/.opt/bin/coreelec-conky.sh /storage/.opt/bin/coreelec-conky.sh.bak
         else echo " Invalid reply... Goodbye!"; exit 1
         fi
  else # copy script and make executable 
         echo "copying and chmoding file"
         scp ./coreelec-conky.sh  root@"${HOST}":/storage/.opt/bin/
         ssh root@"${HOST}" 'chmod +x /storage/.opt/bin/coreelec-conky.sh'
  fi

 # copy conky config to home/.conky
   [ -d ~/.conky ] || mkdir ~/.conky
   cp ./coreelec-conkyrc ~/.conky/
 # run conky 
   echo " Now run: conky -c ~/.conky/coreelec-conkyrc"

  exit 0

#!/opt/bin/bash
#   v 0.9.9.1
#  Outputs CoreELEC OS stats in conky printable format
#  uses entware's bash, bind-dig, coreutils-df, coreutils-sort,
#                 coreutils-stat, procps-ng-top
#
#   Usage: SCRIPTNAME -[ocltumeqirxsdfpn]
#          [o] os info <ng>   [c] cpu usage         [l] load average
#          [t] temp cpu & ram [u] uptime            [m] memory
#          [e] network essid  [q] wireless quality  [i] lan address
#          [r] network region [x] public ip         [s] network up/down speed
#          [d] disk i/o       [f] mounted filesystems, free space, & graph of usage
#          [p] processes command pid %cpu %mem (sorted w/ SORT=%CPU|%MEM)
#          [n] now playing
#
#######################
# Ꜿ plgroves gmail nov 2020
#    
#    I really just wanted to monitor my hard drive usage, VPN, and
#    maybe temperatures!?
#    
#    Install entware:
#    https://discourse.coreelec.org/t/what-is-entware-and-how-to-install-uninstall-it/1149
#     
#     bash              full v5 functionality
#     bind-dig          not in busybox
#     coreutils-df      to allow for local-only exclude and fields
#     coreutils-sort    for various sorting methods
#     coreutils-stat    for checking file "creation" time
#     procps-ng-top     with busybox top -b - 'dumb': unknown terminal type
#    
#    Get hack font 
#    https://github.com/source-foundry/Hack
#    
#    ssh login without password
#    http://www.linuxproblem.org/art_9.html
#
#    Reuse ssh connection
#    https://linuxhostsupport.com/blog/speed-up-ssh-connections-in-linux/#
#    
#      nano ~/.ssh/config on computer running conky & add
#    
#           Host coreelec
#           User root
#           Hostname 'from /etc/hosts (e.g. coreelec)'
#           ControlMaster auto
#           ControlPath  ~/.ssh/sockets/master-coreelec
#           ControlPersist 600
#    
#   add 'UseDNS no' to /storage/.cache/services/sshd.conf on CoreELEC
#    
#   prints output in order of options <fewer options faster time / less load>
#   
#   run: time ssh Hostname /path/to/coreelec-conky.sh -[ocltumeqirxsdfpn] >/dev/null
#   to determine 'interval' & add the following to your conkyrc:
#   
#   ${texecpi 'interval' ssh Hostname /path/to/coreelec-conky.sh -[ocltumeqirxsdfpn]}
#   
#   
#   alignment and cpu format can be changed from the command line
#     pass [center|right|horiz] for alternate alignment
#     pass [long|longer|longest] for frequencies|per core|graph
#   
#   to remove all nonindented (debug) lines after this heading
#     sed -i -e '70,$ { /^[^[:blank:]]/d }' /opt/bin/coreelec-conky.sh 
#   
#   http://kfirlavi.herokuapp.com/blog/2012/11/14/defensive-bash-programming/
#       one command/line self documenting thru functions
####
# for benchmarking script
tss=$(/usr/bin/date +%s%N)

    _Usage() {
       echo >&2 " ${BASH_SOURCE##*/}:" "$@"
       sed >&2 -n "1d; /^###/q; /^#/!q; s/^#*//; s/^ //; 
                   s/SCRIPTNAME/${BASH_SOURCE##*/}/; p" \
                  "${BASH_SOURCE%/*}/${BASH_SOURCE##*/}"
    exit 1; }
    [ $# -lt 1 ] && _Usage "$@"
  export LC_ALL=C

  # Default alignment
    ALIGN="left"
  # offset between options
    SPACING=1
  # height of filesystem bar (odd numbers center better)
    BAR_height=11
  # set to 0 for monochromatic data
    UNICOLOR=
  # set to show memory stats as text
    MEM_text=1
  # set for playlist which takes 2/10 of a second
    playlist_max=
  # sort "NPROCS" processes on "SORT" (%CPU or %MEM)
    NPROCS=3
    SORT="%CPU"
  # colors for labels, sublabels, data, & units
    COLOR1="\${color #06939B}"
    COLOR2="\${color #43D3DA}"
    COLOR3="\${color #9FEEF3}"
    COLOR_units="\${color #b3b3b3}"
  # a monospace font found on computer running conky
  # run fc-list :spacing=100 ( n.b some fonts are limited )
    font_family="Hack"
    FONT1="\${font ${font_family}:size=9}"
    FONT2="\${font ${font_family}:size=8}"
    FONT_units="\${font ${font_family}:size=7}"
  # the following work with the included conkyrc and std monospace fonts
  # to alter width run with -w  to determine the next 6 
    LINE_length1=41     # characters per line:
    LINE_length2=48
    CHARACTER_width1=7  # relation between spaces & conky goto|voffset 'x'
    CHARACTER_width2=6
    LINE_height1=15
    LINE_height2=14
  # indent labels one space
    INDENT1="$((CHARACTER_width1*2))"
  # indent data, based on longest label
    INDENT2="$((INDENT1+CHARACTER_width1*5))"
  # allow finer control of postion
    HALFSPACE1="$(((CHARACTER_width1+1)/2))"
    HALFSPACE2="$(((CHARACTER_width2+1)/2))"
  # cascading conky n.b. these include opening '{' don't forget to close '}'
    GOTO="\${goto "
    VOFFSET="\${voffset "
  # hr character since conky can't define hr width
    HR="―"
  # delay for refreshing disk usage to save time
    FS_dt=17
  # the @ character prints below the line
    ASTERISK="\${voffset -1}@\${voffset 1}"
  # for cpu intensive functions
    RENICE='10'

  # allow changing alignment & format from the conky config
    if [[ "$*" =~ left|right|center|horiz ]]
    then ALIGN="${BASH_REMATCH[0]}"; fi
    if [[ "$*" =~ long|longer|longest ]]
    then FORMAT="${BASH_REMATCH[0]}"; fi
  # remove alignment/format from arguments  
    set -- "${@/${ALIGN}/}"
    set -- "${@/${FORMAT}/}"
  # the cheese stands alone
    set -- "${@: -1}"

# passing '-' only uses these defaults
#
if [ ${#1} -eq 1 ]
then # add options after %/
#
if [[ ! "${ALIGN}" =~ ^h ]]
then                                       # CASCADING
#
# OS data - this can add 3/10 of a second
set -- "${@/%/o}"
#
# show now playing - this adds 3/10 of a second
#set -- "${@/%/n}"
#
set -- "${@/%/cltmueqrxsdf}"
#
# show top processes - this adds 3/10 of a second
#set -- "${@/%/p}"
#
# for benchmarking
#set -- "${@/%/v}"
#
#FORMAT=long
#ALIGN=right
#
else                                       # HORIZONTAL #
#
set -- "${@/%/cltumeqirxsd}"
#
set -- "${@/%/f}"
#
#set -- "${@/%/p}"
#
# for benchmarking
#set -- "${@/%/v}"
#
#FORMAT=long
#
fi
#
fi
#
# for benchmarking script
TIME_log="/tmp/time-${ALIGN:0:1}"
#
  # add some space to INDENT2 for left justify
    [[ "${ALIGN}" =~ ^l ]] \
                  && \
                     INDENT2="$((INDENT2+HALFSPACE1*5))"

  # pretty colors for data
    gradient=( '00d4ff' '00e4ff' '00fff4' '00ffd0' '00ffa8' '00ff83' '00ff5c' '00ff36')
    gradient+=('00ff10' '17ff00' '3eff00' '65ff00' '8aff00' 'b0ff00' 'd7ff00' 'fdff00')
    gradient+=('fffa00' 'fff000' 'ffe600' 'ffdc00' 'ffd200' 'ffc800' 'ffbe00' 'ffb400')
    gradient+=('ffaa00' 'ffa000' 'ff9600' 'ff8c00' 'ff8200' 'ff7800' 'ff6e00' 'ff6400')
    gradient+=('ff5a00' 'ff5000' 'ff4600' 'ff3c00' 'ff3200')
    STEPS="${#gradient[@]}"

  function color_() { # Return HEX value from gradient array
      [ "${2:-0}" -eq 0 ] \
                   && \
                      { bash_REMATCH_ "${COLOR3}" '[[:blank:]][#]?([[:alnum:]]+)[[:blank:]]?}$';
                        return 0; }
      local gradient_color

      gradient_color="$(( $1 * STEPS / $2  ))"
      [ $gradient_color -gt 36 ] \
                         && \
                            gradient_color=36
      [ $gradient_color -lt 0 ] \
                         && \
                            gradient_color=0

      echo "${gradient[${gradient_color}]}"
  return 0
 } 
 export -f color_

  function print_RULE_() { # print string of $1, $2 characters long
      local seq
      seq="{1..${2}}"

      for i in $(eval echo "$seq")
      do echo -n "${1}"
      done
  return 0
 }
 export -f print_RULE_

  function is_HORIZ_() {
      [[ "${1}" =~ ^h ]]
 }
 export -f is_HORIZ_

  function is_CASCADING_() {
      [[ ! "${1}" =~ ^h ]]
 }
 export -f is_CASCADING_

  function heading_() { # label align goto position color font spacing
      echo -n  "${3} ${4}}${5}${6}"

      is_CASCADING_ "${2}" \
                    && \
                       echo -n "${VOFFSET} ${7}}${1}"
  return 0
 }
 export -f heading_

  function justify_() { # ALIGN string on line_length
      local string="$2"
      local string length_text padding newline
            # remove any leading & trailing whitespaces
              string="$(/usr/bin/sed -e 's/^[[:space:]]*//;s/}[ \t]*/}/;s/[[:space:]]*$//' \
                                    <<< "${string}")"

      ( renice "${RENICE}" $BASHPID
        case "${1}" in

          r*|c*)
                 # length of string stripped of conky formating
                   length_text="$(("$(/usr/bin/sed  -e "s/[\${][^}]*[}]//g" <<< "${string}" \
                                                 | wc -c)"-1))"

                 # check length of text vs length of line
                   [ "${length_text}" -gt "${3}" ] \
                                       && \
                                          { echo "lgth: ${3} < stng: ${length_text}";
                                            return 2; }

                 # spaces to pad string
                   padding="$(($3-length_text))"
                   [[ "${1}" =~ ^c ]] \
                             && \
                                padding="$(((padding+2/2)/2))"

             ;&
          l*)    # add newline for r|c|l
                   newline=$'\n'
            ;&
          *)     # printf ${padding}${string}${newline}
      printf "%$((padding+${#string}))s" "${string}${newline}"
            ;;

        esac )
    return 0
 }
 export -f justify_

  function bash_REMATCH_() { # Return specific data in matching line of
      local output match     # command output, file, or string
      is_SET_ "$3" \
              && \
                 output="/tmp/${1##*/}-${3}"

      if is_EXECUTABLE_ "${1%% *}"
      then while IFS= read -r line
           do if [[ "${line}" =~ ${2} ]]
              then echo  "${BASH_REMATCH[1]}" \
                      | tee -a "${output:-/dev/null}"
              fi
          done < <(${1})
      elif is_FUNCTION_ "${1}"
      then [[ "${1}" =~ ${2} ]]
           for ((i=1;i<"${#BASH_REMATCH[@]}";i++))
           do  echo "${BASH_REMATCH[${i}]}"
           done
      elif is_READABLE_ "${1}"
      then echo -n "" > "${output:-/dev/null}"
           while IFS= read -r line
           do if [[ "${line}" =~ ${2} ]]
              then echo  "${BASH_REMATCH[1]}" \
                      | tee -a "${output:-/dev/null}"
              fi
           done < "${1}"
      else [[ "${1}" =~ ${2} ]]
           echo "${BASH_REMATCH[1]}"
      fi
  return 0
 }
 export -f bash_REMATCH_

  function created_() {
      /opt/bin/stat -c %Y "${1}" 2>/dev/null \
               || \
               echo $?
      return 0
 }
 export -f created_

  function delay_() {
      local now
      now="$(/usr/bin/date  +%s \
                         | tee "${2:-/dev/null}")"

      echo -n "$((now-${1:-${CURL_dt}}))"
  return 0
 }
 export -f delay_

  function make_ROOM_for_() {
      /usr/bin/mv "${1}" "${1:0: -1}" 2>/dev/null \
               || \
               touch "${1:0: -1}"
  return 0
 }
 export -f make_ROOM_for_

  function is_EMPTY_() {
      [ -z "${1}" ]
 }
 export -f is_EMPTY_

  function is_SET_() {
      [ -n "${1}" ]
 }
 export -f is_SET_

  function is_NOT_file_() {
      [ ! -f "${1}" ]
 }
 export -f is_NOT_file_

  function is_READABLE_() {
      [ -r "${1}" ]
 }
 export -f is_READABLE_

  function is_EXECUTABLE_() {
      command -v "${1}" >/dev/null
 }
 export -f is_EXECUTABLE_

  function is_FUNCTION_() {
       declare -f -F "${1}" > /dev/null
 }
 export -f is_FUNCTION_

    if is_HORIZ_ "${ALIGN}"
    then # keep fonts same, change goto/voffset to offset, indent2 to 0
        GOTO="\${offset "
        VOFFSET="\${offset "
        FONT1="${FONT2}"
        FONT_units="${FONT1}"
        CHARACTER_width1="${CHARACTER_width2}"
        HALFSPACE1="${HALFSPACE2}"
        INDENT2=0
    fi

  if [[ "$*" =~ e|q|i|r|x|s ]]
  then # outputing network information

      # network interfaces
        ACTIVE_iface="$(bash_REMATCH_ "/sbin/ip route show" \
                                      '^d.*[[:space:]]([^[:space:]]+)[[:space:]]$')"
        [[ "$*" =~ e|q|i ]] \
                  && \
                     ACTIVE_wifi="$(bash_REMATCH_ "/sbin/ip addr" \
                                                  '(wlan[[:digit:]]):[[:blank:]]<BR')"

      if [[ "$*" =~ r|x ]]
      then # geoip info

          function check_IP_data_() { # Check if ip data file is/recent or create/update
              local ip_file="$1"
              local stale="$2"
        
              is_READABLE_ "${1}" \
                           && \
                              [ "${stale}" -gt "$(delay_ "$(/opt/bin/stat -c %Y "${ip_file}")")" ] \
                                            && \
                                               return 0

              curl -sf -m 2 ipinfo.io/"$(/opt/bin/dig +short myip.opendns.com @resolver1.opendns.com)" > "${ip_file}" \
              || \
              no_IPINFO_ > "${ip_file}"
          return 0
         }
         export -f check_IP_data_

  function no_IPINFO_() {
    /usr/bin/cat <<- ' EOF'
    "ip": "NO.RE.P.LY"
    "city": "NO"
    "region": "PLACE LIKE"
    "country": "HM"
 EOF
 }
  export -f no_IPINFO_

          # file for public ip data
            IP_data="/tmp/network_DATA"
          # delay for curling ipinfo.co (1,000/day is their max)
            CURL_dt=180
      fi
  fi

  while getopts "ocltmueqxirspfdnwvh" opt
  do
  case "${opt}" in

    c)                               # CPU #
        heading_ "CPU:" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

              function pcpu_() {
                  local align="$1"
                  local file cpu_stats match
                        file=/proc/stat
                        make_ROOM_for_ "${cpu_stats:=/tmp/${file##*/}-${ALIGN}}"
                        bash_match='(^cpu.*)+'
                        # cpu stats collated for later use
                          echo -n "" > "${cpu_stats:0:11}"

                  # if no previous cpu data
                    [ -s /tmp/stat-"${ALIGN:0: -1}" ] \
                      || bash_REMATCH_ "${file}" "${bash_match}" "${ALIGN}" > /tmp/stat-"${ALIGN:0: -1}"

                  ( renice "${RENICE}" "${BASHPID}"
                    while  IFS= read -r a <&3 \
                                 && \
                           IFS= read -r b <&4
                    do echo  "${a} ${b}" \
                                         | tee -a "${cpu_stats:0:11}"
                    done ) \
                           3<"${cpu_stats:0: -1}" \
                           4< <(bash_REMATCH_ "${file}" "${bash_match}" "${ALIGN}") \
                     | \
                    /usr/bin/awk '{if (NR != "")
                                   printf "%5.1f\n",
                                           ($13-$2+$15-$4)*100/($13-$2+$15-$4+$16-$5);
                                   else print 0;}'; }

        mapfile -t core_per100 < <(pcpu_ "${ALIGN}")

        # heterogenous cpu?
          HETEROGENEOUS="$(bash_REMATCH_  '/usr/bin/lscpu' '^So.*([[:alnum:]]+)')"

        case "$FORMAT" in                             # How much data to print

          *st)                                        # cpu graph (pass longest)

               if is_CASCADING_ "${ALIGN}"
               then
        echo -n  "${GOTO} ${INDENT1}}"
        echo -n  "\${voffset $((LINE_height1*1+LINE_height2*1+(SPACING*1)))}"
        echo -n  "${FONT2}"
                   h="$((LINE_height1*2))"
                   w="$(((LINE_length1*CHARACTER_width1-HALFSPACE1*5)))"
                   skip="$((LINE_height1*1+LINE_height2*3))"
               else             # horizontal conky
                   h="$((9*1))"
                   w="$(((CHARACTER_width1*8)))"
               fi
        echo -n  "\${execgraph \"echo ${core_per100[0]%.*}\" ${h},${w} 00FF00 FF0000 -t }"

               # return to CPU: line
                 is_CASCADING_ "${ALIGN}" \
                 && \
        echo -n  "\${voffset -$((LINE_height1*1+LINE_height2+(SPACING*1)))}"

             ;&
          *r)               # print per core percentages (pass longer to script)

               case "${ALIGN}" in
                 h*)
        echo -n "\${offset -$((CHARACTER_width1*2))}"
                    ;;
                 l*)
        echo -n "\${voffset $((LINE_height1))}${FONT2}${GOTO} $((INDENT1+HALFSPACE2*13))}"
                   ;;
                 c*)
        echo -n "\${voffset $((LINE_height1))}${FONT2}${GOTO} $((INDENT1+HALFSPACE2*12))}"
                   ;;
                 *)
        echo -n "\${voffset $((LINE_height1))}${FONT2}${GOTO} $((INDENT1+HALFSPACE2*7))}"
                   ;;
               esac

               # monochrome
                 color=$(bash_REMATCH_ "${COLOR3}" ' [#]?([[:alnum:]]+)[[:blank:]]?}$')

               seq="3 4 5 6 1 2"
               [ "${HETEROGENEOUS}" -eq 1 ] \
                                     && \
                                        seq="{1..$(bash_REMATCH_ /usr/bin/lscpu \
                                                                 '^CPU\(.*([[:digit:]])')}"

        justify_ "${ALIGN}" \
                 "$(for core in $(eval echo "$seq")
                    do echo -n "\${color ${color}}"
                       echo -n "$(printf '%5.1f' "${core_per100[$core]}")"
                       echo -n "${COLOR_units}\${offset 2}%"
                    done)" \
                 "$((LINE_length2-INDENT2/CHARACTER_width2))"

        echo -n "\${offset ${HALFSPACE1}}"
               if is_CASCADING_ "${ALIGN}"
               then # return to previous line
        echo -n  "\${voffset -$((LINE_height1*1+LINE_height2))}"
                   [[ "${FORMAT}" =~ ^longes ]] \
                                  && \
        echo -n "\${voffset -$((LINE_height1*2))}"
                   : "${skip:=$((LINE_height1*1))}"
               fi
             ;&
          l*) # print frequencies, % for big.LITTLE as well (pass long to script)

               function human_FREQUENCY_() { # GHz, MHz units for cpu frequency
                   /usr/bin/awk -v units_style="\${offset 1}${FONT_units}${COLOR_units}" '
                                {if ($1+0>999999)
                                    printf "%5.1f%sGHz\n",
                                    $1/10^6, units_style;
                                 else printf "%5.0f%sMHz\n",
                                 $1/10^3,units_style}' <<< "${1}"
               return 0; }

               function bl_() { # cpu % per side
                   local align="$1"
                   local cpu_stats
                         cpu_stats=/tmp/stat-"${ALIGN:0:1}"

                   while IFS= read -r line
                   do echo "${line}"
                   done  < "${cpu_stats}" \
                      | tee >(/usr/bin/awk \
                              'NR==4||NR==7{S13+=$13;S2+=$2;S15+=$15;S4+=$4;S16+=$16;S5+=$5}
                                END
                              {printf "%5.1f\n",(S13-S2+S15-S4)*100/(S13-S2+S15-S4+S16-S5)}') \
                            >(/usr/bin/awk  \
                              'NR==2||NR==3{S13+=$13;S2+=$2;S15+=$15;S4+=$4;S16+=$16;S5+=$5}
                                END
                               {printf "%5.1f\n",(S13-S2+S15-S4)*100/(S13-S2+S15-S4+S16-S5)}') \
                            >/dev/null; }

               # frequency current, minimum, & maximum
                 mapfile -t fqz < \
                        <(/usr/bin/cat /sys/devices/system/cpu/cpufreq/policy*/scaling_*_freq)

               # add usage & frequency for heterogeneous 'big' side
               if [ "${HETEROGENEOUS}" -eq 2 ]
               then mapfile -t sides < <(bl_ "${ALIGN}")

                    # concatenate line so its closer to 80 columns
                      l_string="\${offset 1}${FONT2}"
                      l_string+="\${color $(color_ "${sides[1]%.*}" "${UNICOLOR:-100}")}"
                      l_string+="${sides[1]}"
                      l_string+="\${offset ${HALFSPACE2}}${COLOR_units}%"
                      l_string+="\${offset ${HALFSPACE2}}${ASTERISK}"
                      l_string+="\${offset -${CHARACTER_width2}}"
                      l_string+="\${color $(color_ "$((fqz[3]-fqz[5]))" "$(((fqz[4]-fqz[5])*${UNICOLOR:-1}))")}"
                      l_string+="$(human_FREQUENCY_ "${fqz[3]}")"
                      l_string+="\${offset ${HALFSPACE2}}${VOFFSET} -1}"
                      l_string+="\${color $(color_ "${sides[0]%.*}" "${UNICOLOR:-100}")}"
                      l_string+="${FONT2}${sides[0]}"
                      l_string+="\${offset 2}${COLOR_units}%\${offset 2}"
               elif [[ "${ALIGN}" =~ ^r ]] # homogeneous cpu, position frequency after cpu%
               then move_to="$((HALFSPACE1*2))"
               fi

               # add frequency for only/'LITLE' side
                 l_string+="${ASTERISK}"
                 l_string+="\${offset -${CHARACTER_width1}}"
                 l_string+="\${color $(color_ "$((fqz[0]-fqz[2]))" "$(((fqz[1]-fqz[2])*${UNICOLOR:-1}))")}"
                 l_string+="$(human_FREQUENCY_ "${fqz[0]}")"

               case "${ALIGN}" in # make room for a long line
                 l*)    move_to="$((INDENT1+CHARACTER_width1*6))";;
                 r*) : "${move_to:=$((HALFSPACE1*6+2))}";;
                 c*) : "${move_to:=$((HALFSPACE1*11))}";;
                 *)     move_to=1;;
               esac

               : "${skip:=$((SPACING-1))}"
            ;&
          *) # print overall percentage

               case "${ALIGN}" in
                 c*) : "${move_to:=$((HALFSPACE1*9))}" ;;
                 r*) : "${move_to:=0}" ;;
                 l*) : "${move_to:=$((INDENT2*1-CHARACTER_width1*0))}" ;;
                 *)  : "${move_to:=$((CHARACTER_width1*2))}"  ;;
               esac

               c_line+="\${color $(color_ "${core_per100[0]%.*}" "${UNICOLOR:-100}")}"
               c_line+="${core_per100[0]}"
               c_line+="\${offset 1}${COLOR_units}%"

        echo -n  "${GOTO} ${move_to}}${FONT1}"
        justify_ "${ALIGN}" \
                 "${c_line}${l_string}" \
                 "${LINE_length1}"

               if is_HORIZ_ "${ALIGN}"
               then
        echo -n "\${offset 1}"
               else : "${skip:=0}"
        echo -n  "\${voffset ${skip}}"
               fi
            ;;
        esac

            if   [[ "${FORMAT}" =~ est ]] \
                                || \
                 [ "$((${core_per100[0]%.*}))" -gt 70 ]
            then         # iowait and softirq for case: longe* or high cpu usage
        echo -n "${FONT2}${COLOR1}"
        /usr/bin/awk 'NR==1||NR==8{start=($2+$3+$4+$5+$6+$7+$8+$9+$10);
                                   end=($13+$14+$15+$16+$17+$18+$19+$20+$21);
                                   iowStart=($6);iowEnd=($17);
                                   sirqStart=($8);sirqEND=($19)}
                       END
                      {printf "\${alignc}iowait: %6.4f%%  softirq: %6.4f%%",
                               (iowEnd-iowStart)*100/(end-start),
                               (sirqEND-sirqStart)*100/(end-start);}' \
                    /tmp/stat-"${ALIGN:0:1}"

                is_CASCADING_ "${ALIGN}" \
                && \
        echo
            fi
      ;;

    l)                             # LOADAVG #
        heading_ "LOAD:" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

            mapfile -d' '  loadavg < /proc/loadavg

            if is_EMPTY_ "${UNICOLOR}"
            then for avg in {0..2}
                do case "${loadavg[${avg}]}" in
                     0*)    load_color+=(00d4ff);;
                     1\.*)  load_color+=(00ff5c);;
                     2*)    load_color+=(8aff00);;
                     3*)    load_color+=(ffe600);;
                     4*)    load_color+=(ffaa00);;
                     5*)    load_color+=(ff6e00);;
                     *)     load_color+=(ff3200);;
                   esac
                done
            else for avg in {0..2}
                 do  load_color+=("$(bash_REMATCH_ "${COLOR3}" \
                                                   ' [#]?([[:alnum:]]+)[[:blank:]]?}$')")
                 done
            fi

            a_line+="\${color ${load_color[0]}}"
            a_line+="$(/usr/bin/sed -e 's/[ \t]*//'  <<< "${loadavg[0]}")"
            a_line+="\${color ${load_color[1]}}"
            a_line+="${loadavg[1]}"
            a_line+="\${color ${load_color[2]}}"
            a_line+="${loadavg[2]}"

        echo -n  "${GOTO} $((INDENT2+0))}"
        justify_ "${ALIGN}" \
                 "${a_line}" \
                 "$((LINE_length1-INDENT2/CHARACTER_width1))"

            if [ "${loadavg[1]%.*}" -ge 4 ]
            then                      # high loadavg can mean blocked processess
                 mapfile -t procs < \
                        <( bash_REMATCH_ /proc/stat '^procs_(.*)+' )
        echo -n  "\${color #ff3200}\${alignc} ${procs[0]} ${procs[1]}"

                 is_CASCADING_ "${ALIGN}" \
                 && \
        echo
            fi
      ;;

    t)                           # TEMPERATURES #
        heading_ "TEMP:" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

            # hot for the cpu/ram
              hot=70

            # read all zones
              mapfile -t temps 2>/dev/null < \
                     <( /usr/bin/cat /sys/class/thermal/thermal_zone*/temp)

            # name thermal zones ( note the space before element 1+n )
              zones=('Cpu:' ' Mem:')
              is_HORIZ_ "${ALIGN}" \
                        && \
                           zones=('C:' "\${offset ${HALFSPACE1}}M:")

            # unicode character ° throws off justify function
              right=0
              if [[ "${ALIGN}" = +(c*|r*) ]]
              then right=2; fi

            if is_EMPTY_ "${UNICOLOR}"
            then for temp in $(seq "${#temps[@]}")
                 do case "${temps[$((temp-1))]}" in
                      2*)  temp_color+=(00d4ff);;
                      3*)  temp_color+=(00ff5c);;
                      4*)  temp_color+=(8aff00);;
                      5*)  temp_color+=(ffe600);;
                      6*)  temp_color+=(ffaa00);;
                      7*)  temp_color+=(ff6e00);;
                      *)   temp_color+=(ff3200);;
                    esac
                done
            else for temp in $(seq "${#temps[@]}")
                 do  temp_color+=("$(bash_REMATCH_ "${COLOR3}" \
                                                   ' [#]?([[:alnum:]]+)[[:blank:]]?}$')")
                 done
            fi

            zone=0
            for temp in "${temps[@]}"
            do t_line+="${COLOR2}${zones[$zone]} "
               t_line+="\${color ${temp_color[${zone}]}}"
               t_line+="$((temp/1000)).${temp:2:1}"
               t_line+="${COLOR_units}°C${COLOR2}"
               ((zone++))
            done

        echo -n  "${GOTO} $((INDENT2))}${COLOR2}"
        justify_ "${ALIGN}" \
                 "${t_line}" \
                 "$((LINE_length1-INDENT2/CHARACTER_width1+right))"

            if [ "$((((temps[0]+(1000/2))/1000)))" -ge "${hot}" ]
            then                       # Hi temp, what process is using most cpu
        echo -n  "\${color #ff3200}${FONT1}"

                is_CASCADING_ "${ALIGN}" \
                && \
        echo -n  "\${voffset ${SPACING}}"

        /usr/bin/awk -v indent="${GOTO} $((INDENT2+0))}" '
                     {if ($1) 
                         printf "%s%-10s%7d%6.1f%%%6.1f%%",indent,$11,$1,$7,$8;
                      else printf $2}' < \
                    <(/opt/bin/top -bn 2 -d 0.01 -c -o +"${SORT}" \
                                 | /usr/bin/sed -e  '/top/d' \
                                              | /usr/bin/tail  -n +11 \
                                                            | /usr/bin/head -1)

                is_CASCADING_ "${ALIGN}" \
                && \
        echo
            fi
      ;;

    u)                             # UPTIME #
        heading_ "UPTIME:" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

            # units
              units=( " day(s)" " hrs" " mins" )
              is_HORIZ_ "${ALIGN}" \
                        && \
                           units=( "d" "h" "m" )

        echo -n  "${GOTO} ${INDENT2}}${COLOR3}"
        justify_ "${ALIGN}" \
                 "$(/usr/bin/awk  -v d="${units[0]}" -v h="${units[1]}" -v m="${units[2]}" \
                                  -F"[ |.]+" '{secs=$1;}END
                                  {printf "%d%s %d%s %d%s",
                                           secs/86400,d,secs%86400/3600,h,secs%3600/60,m;}' \
                                /proc/uptime)" \
                 "$((LINE_length1-INDENT2/CHARACTER_width1))"
      ;;

    m)                             # MEMORY #
        heading_ "" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"
            label='MEM:'

            mapfile -d' ' -t memory < \
                   <(/usr/bin/awk 'NR==2{total=$2;used=$3}END
                                   {printf "%d %d %2.1f",
                                            used,total,(used/total)*100}' < \
                                 <(free -m))

            if is_EMPTY_ "${MEM_text}"
            then #                 memory bar  
        echo -n  "${label}"
                width="$((LINE_length1*CHARACTER_width1-(INDENT1*4+CHARACTER_width1*5)))"
                is_HORIZ_ "${ALIGN}" \
                          && \
                             width="50"
                case "${ALIGN}" in
                  r*) echo -n "\${goto $((LINE_length1*CHARACTER_width1-INDENT1-width+HALFSPACE1))}";;
                  c*) echo -n "\${goto $((LINE_length1*CHARACTER_width1-width-INDENT2/2))}";;
                  *)  echo -n  "${GOTO} ${INDENT2}}";;
                esac

        echo -n  "\${color $(color_ "${memory[2]%.*}" "${UNICOLOR:-100}")}"
        echo -n  "\${execbar $((LINE_height1/3)),${width} echo ${memory[2]%.*}}"

                is_CASCADING_ "${ALIGN}" \
                && \
        echo
            else #                    text
                m_line+="\${color $(color_ "${memory[2]%.*}" "${UNICOLOR:-100}")}"
                m_line+="${memory[2]}%"
                m_line+=" ${memory[0]}${COLOR3}/${memory[1]}"
                m_line+="${FONT_units}${COLOR_units}\${offset 3}MB"

                is_CASCADING_ "${ALIGN}" \
                && \
        echo -n  "${label}"
        
        echo -n  "${GOTO} ${INDENT2}}"
        justify_ "${ALIGN}" \
                 "${m_line}" \
                 "$((LINE_length1-INDENT2/CHARACTER_width1))"
            fi

            if [ "${memory[2]%.*}" -ge  80 ]
            then                      # high memory usage, who's the biggest hog
        echo -n "${GOTO} $((INDENT2+10))}${FONT1}\${color red}"
        /usr/bin/awk '{printf "%-9s %d %2.1f%% %5.1f Mb %5.1f Mb\n",
                               $1,$2,$3,($4/1024),($5/1024^2)}' < \
                    <(/opt/bin/ps  -eo comm,ppid,pmem,rss,vsize \
                                | /opt/bin/sort  -k 3 -n -r \
                                              | /usr/bin/head -1)
            fi
      ;;

    e)                          # NETWORK SSID #
        if is_SET_ "${ACTIVE_wifi}"
        then
        heading_ "ESSID:" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

            line="$(bash_REMATCH_ '/usr/bin/connmanctl services' '^\*AR[[:blank:]]([^[:blank:]]+).*w') "
            # TODO need to fiqure out bitrate speed w/o iwconfig see below
              line+="${COLOR2}"
              line+="$(/usr/bin/awk -v wlan="${ACTIVE_wifi}" \
                                    -F "[. ]+" \
                                    '$0 ~ wlan {print $4}' \
                                    /proc/net/wireless)"
              line+="${COLOR_units}\${offset 1}%"

        echo -n  "${GOTO} ${INDENT2}}${COLOR3}"
        justify_ "${ALIGN}" \
                 "${line}"\
                 "$((LINE_length1-(INDENT2/CHARACTER_width1)))"
        fi
      ;;

    q)                     # Wireless Quality & bitrate #
        if is_SET_ "${ACTIVE_wifi}"
        then # TODO need to fiqure out bitrate speed w/o iwconfig
        #heading_ "LINK:" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

            #match="${ACTIVE_wifi}:[[:blank:]][[:digit:]]+[[:blank:]]*([[:digit:]]+)\."

            sq_line="Speed: ${COLOR3}$(:) " # error in shellcheck to remind me
            #sq_line+="\${offset 3}${COLOR2}Quality: ${COLOR3}"
            #sq_line+="$(/usr/bin/awk -v wlan="${ACTIVE_wifi}" \
                                     #-F "[. ]+" '$0 ~ wlan {print $4}' /proc/net/wireless)"
            #sq_line+="${COLOR_units}\${offset 3}%"

        #echo -n  "${GOTO} ${INDENT2}}${VOFFSET} -1}${COLOR2}${FONT2}"
        #justify_ "${ALIGN}" \
                 #"${sq_line}" \
                 #"$((LINE_length2-(INDENT2/CHARACTER_width2)-1))"
        fi
      ;;

    i)                           # LAN ADDRESS #
        if is_SET_ "${ACTIVE_iface}"
        then match='inet addr:([0-9]+[\.][0-9]+[\.][0-9]+[\.][0-9]+)[[:space:]]'

            if   is_SET_ "${ACTIVE_wifi}" \
                 && \
                 [[ "${ACTIVE_wifi}" != "${ACTIVE_iface}" ]]
            then
        heading_ "${ACTIVE_wifi}:" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

        echo -n  "${GOTO} ${INDENT2}}${COLOR3}"
        justify_ "${ALIGN}" \
                 "$(bash_REMATCH_ "/sbin/ifconfig ${ACTIVE_wifi}" "${match}")" \
                 "$((LINE_length1-(INDENT2/CHARACTER_width1)))"
            fi

        heading_ "" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"
        echo -n  "${ACTIVE_iface}:"

        echo -n  "${GOTO} ${INDENT2}}${COLOR3}"
        justify_ "${ALIGN}" \
                 "$(bash_REMATCH_ "/sbin/ifconfig ${ACTIVE_iface}" "${match}")" \
                 "$((LINE_length1-(INDENT2/CHARACTER_width1)))"
        fi
      ;;

    x)                           # PUBLIC IP ADDRESS #
        if is_SET_ "${ACTIVE_iface}"
        then
        heading_ "IP:" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

            # ipinfo.io limits: 1,000 requests/day
              check_IP_data_ "${IP_data}" "${CURL_dt}"

            match='ip'
            return='[\"].*[\"](.*)[\"]'

        echo -n  "${GOTO} ${INDENT2}}${COLOR3}"
        justify_ "${ALIGN}" \
                 "$(bash_REMATCH_ "${IP_data}" "${match}${return}")" \
                 "$((LINE_length1-(INDENT2/CHARACTER_width1)))"
        fi
      ;;

    r)                          # NETWORK REGION
        if is_SET_ "${ACTIVE_iface}"
        then
        heading_ "GEO:" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

            check_IP_data_ "${IP_data}" "${CURL_dt}"

            matches=( 'city' 'region' 'country' )
            return='[\"].*[\"](.*)[\"]' # everything between 2nd set of "'s

            for match in "${matches[@]}"
            do  ip_data+=( "$(bash_REMATCH_ "${IP_data}" "${match}${return}" )" )
            done

        echo -n  "${GOTO} ${INDENT2}}${COLOR3}"
        justify_ "${ALIGN}" \
                 "${ip_data[0]:0:18}, ${ip_data[1]:0:12} ${ip_data[2]:0:3}" \
                 "$((LINE_length1-(INDENT2/CHARACTER_width1)))"
        fi   
      ;;

    s)                         # NETWORK RX/TX SPEED #
        if [ ! -z "${ACTIVE_iface}" ]
        then
        heading_ "${ACTIVE_iface}:" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

            function human_NETSPEED_() { # https://askubuntu.com/users/307523/wineunuuchs2unix
                local u p_u b d s 
                u="\${offset ${HALFSPACE2}}${COLOR_units}${FONT_units}"
                p_u="\${offset -1}/\${offset -1}s"
                  is_CASCADING_ "${ALIGN}" \
                                && \
                                   p_u+="${VOFFSET} -2}"
                b="${1}"; d=''; s=0; S=(' B' {K,M,G,T,E,P,Y,Z}B)

                while ((b > 1024)); do
                   d="$(printf "%02d" "$((((b%1024*100)+(1024/2))/1024))")"
                   b="$((b / 1024))"
                   ((s++))
                done
                [ "${b}" -gt 0 ] \
                          || \
                             { b=1; d=0; s=0; }
                : "${d:=0}"
                printf "%4d%s%.1s%s" "$b" "." "${d}" "${u}${S[${s}]}${p_u}"
            return 0; }

            # variables for rx/tx stats
              net_stats="/tmp/net_stats-${ALIGN:0:1}"
            # when was last reading based on file creation
              then="$(created_ "${net_stats}")"
            # how long ago was that
              dt="$(delay_ "${then}")"
            # if created_ returned error then net_stats !exist
              [ "${then}" -eq 1 ] \
                           && \
                              { touch "${net_stats}";
                                dt=1; }

            # read network rx,tx stats into array
              mapfile -t rawbytes \
                     < "${net_stats}" 2>/dev/null
              mapfile -t -O "${#rawbytes[@]}" rawbytes < \
                     <(/usr/bin/cat  /sys/class/net/"${ACTIVE_iface}"/statistics/{rx,tx}_bytes \
                                  | tee "${net_stats}")

            if [ "${#rawbytes[@]}" -ne 4 ]
            then rxtx=( '1' '1' )
            else # have enough data to work with
                rxtx=( "$(( ( (rawbytes[2] - rawbytes[0]) + ( ${dt:=1} / 2 )  ) / ${dt:=1} ))" )
                rxtx+=( "$((((rawbytes[3]-rawbytes[1])+dt/2)/dt))" )
            fi

            # to set max upper speed
              speed='/tmp/net-speed'
            # adjust scale for up speed # this returns error on no file, oh well
              hi_up="$(< "${speed}_up")" \
                  || touch "${speed}_up"
              [ "${rxtx[1]}" -gt "${hi_up:=0}" ] \
                                    && \
                                       echo "${rxtx[1]}" > "${speed}_up"
            # adjust scale for down speed
              hi_dn="$(< "${speed}_down")" \
                  || touch "${speed}_down"
              [ "${rxtx[0]}" -gt "${hi_dn:=0}" ] \
                                    && \
                                       echo "${rxtx[0]}" > "${speed}_down"
            # sublabel for conky (left|right|center) || horiz
              sublabel=( 'Up:' 'Dn:' )
              is_HORIZ_ "${ALIGN}" \
                        && \
                           sublabel=( '↑' '↓' )

            s_line+="${COLOR2}${FONT1}${sublabel[0]}"
            s_line+="\${color $(color_ "$((rxtx[1]))" "${UNICOLOR:-${hi_up}}")}"
            s_line+="$(human_NETSPEED_ "${rxtx[1]}")"
            s_line+="${COLOR2}${FONT1} ${sublabel[1]}"
            s_line+="\${color $(color_ " $((rxtx[0]))" "${UNICOLOR:-${hi_dn}}")}"
            s_line+="$(human_NETSPEED_ "${rxtx[0]}")"
              is_CASCADING_ "${ALIGN}" \
                            && \
                               s_line+="${VOFFSET} 1}"

        echo -n  "${GOTO} ${INDENT2}}"

            [[ "${ALIGN}" =~ ^r ]] \
                          && \
        echo -n "\${offset $((HALFSPACE2*2))}"

        justify_ "${ALIGN}" \
                 "${s_line}" \
                 "$((LINE_length1-(INDENT2/CHARACTER_width1)))"
        fi
      ;;

    d)                         # DISK I/O SPEEDS #
        heading_ "DISKS:" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"
            is_HORIZ_ "${ALIGN}" \
            && \
        echo -n "\${offset -7}"

            function diskstats_() {
                local align="$1"
                local file diskstats match
                      file=/proc/diskstats
                      diskstats="${diskstats:=/tmp/${file##*/}-${align}}"
                      then="$(created_ "${diskstats}")"
                      make_ROOM_for_ "${diskstats}"
                      bash_match='(^.*sd[a-z] .*|^.*blk0p2.*)'
                      dt="$(delay_ "${then}")"
                      [ "${then}" -eq 1 ] \
                                   && \
                                      touch "${diskstats}"

                ( renice "${RENICE}"
                  while IFS= read -r a <&3 \
                              && \
                        IFS= read -r b <&4
                  do echo "${a} ${b}"
                  done  3<"${diskstats:0: -1}" \
                        4< <(bash_REMATCH_ "${file}" "${bash_match}" "${ALIGN}") \
                ) \
                  | \
                  /usr/bin/awk -v dt="${dt}" -v read="${read}" -v write="${write}" -v mb="${mb}" \
                               '{read_start+=$6;read_end+=$20;write_start+=$10;write_end+=$24;i++}
                                 END
                                {if (dt > 0 && i >= 2)
                                     printf "%8.3f\n%8.3f\n%.0f\n%.0f",
                                     ((read_end-read_start)/dt)*512/1024^2,
                                     ((write_end-write_start)/dt)*512/1024^2,
                                     (((read_end-read_start)/dt)*512/1024^2)*1000,
                                     (((write_end-write_start)/dt)*512/1024^2)*1000;
                                 else printf "\n";}'; }

            mapfile -t diskio < <(diskstats_ "${ALIGN}")

            # upper speed read/write
              speed='/tmp/disk'
            # get previous highs # this returns error on no file, oh well
              hi_read="$(< "${speed}_read")" \
                      || touch "${speed}_read" # file !exist, create
              hi_write="$(< "${speed}_write")" \
                      || touch "${speed}_write"

            # adjust scale for read/write speed
            # this sets ${diskio[@]} and $hi_read/write if unset
              [ "${diskio[2]:=1}" -gt "${hi_read:=0}" ] \
                                   && \
                                      echo "${diskio[2]}" > "${speed}_read"
              [ "${diskio[3]:=1}" -gt "${hi_write:=1}" ] \
                                   && \
                                      echo "${diskio[3]}" > "${speed}_write"

            # color disk io
              diskio_color=(  "$(color_ "${diskio[2]}" "$((${hi_read:-1} *${UNICOLOR:-1}/4))")" )
              diskio_color+=( "$(color_ "${diskio[3]}" "$((${hi_write:-1}*${UNICOLOR:-1}/4+1))")" )

            # variables for conky
              offset=0
              [[ "${ALIGN}" =~ ^c ]] \
                            && \
                               offset="${CHARACTER_width2}"
              begin="\${offset ${offset}}${COLOR2}${FONT1}"
              read="${begin}R${COLOR3}"
              write="${begin}W${COLOR3}"
              mb="\${offset $((HALFSPACE2*1))}${COLOR_units}${FONT2}"
              mb+="Mb\${offset -2}/\${offset -2}s "
                is_CASCADING_ "${ALIGN}" \
                              && \
                                 mb+="\${voffset -1}"

        echo -n  "${GOTO} ${INDENT2}}"

            [[ "${ALIGN}" =~ ^r ]] \
                          && \
        echo -n "\${offset $((HALFSPACE2*6))}"

        justify_ "${ALIGN}" \
                 "${read}\${color ${diskio_color[0]}}${diskio[0]}${mb}${write}\${color ${diskio_color[1]}}${diskio[1]}${mb}" \
                 "$((LINE_length1-INDENT2/CHARACTER_width1))"
      ;;

    f)                           # DISK USAGE  #
        heading_ "" "${ALIGN}" "${GOTO}" '0' "${COLOR1}" "${FONT1}" "${SPACING}"
            if is_CASCADING_ "${ALIGN}"
            then
        print_RULE_ "${HR}" "$((LINE_length1/2-4))"
        echo -n  "STORAGE"
        echo -n  "\${voffset -1}\${hr}\${voffset $((LINE_height1+4))}"
            else
        echo -n "\${offset 5}"
            fi

            file="/tmp/filesystems-${ALIGN:0:1}"
            then="$(created_ "${file}")"

            # to shorten the list especially for horizontal format
              skip_target=( "flash" "" )
            # ignore sshfs
              local_only=(-l)

            if is_NOT_file_ "${file}" \
               || \
               [ "$(delay_ "${then}" )" -gt "${FS_dt}" ]
            then # read current data and tee to file

                # (width of line in conky 'x') - (location & length of FREE) + space
                  width="$((LINE_length1*CHARACTER_width1-(HALFSPACE1*42)))"
                  [[ "${ALIGN}" =~ ^l ]] \
                                && \
                                   width="$((width-HALFSPACE1*5))"

                { ( renice "${RENICE}" $BASHPID
                    /opt/bin/df   -h "${local_only[@]}" -x tmpfs -x devtmpfs -x squashfs -x iso9660 \
                                --output=target,avail,used,pcent \
                            | tail  -n +2 \
                                 | /opt/bin/sort  -k 4 -i ) \
                                               | \
                  while read -r TARGET AVAIL USED PCENT
                  do
                      target="${TARGET##*/}"   # yes those are "'s in a match
                      [[ " ${skip_target[*]} " =~ " ${target} " ]] \
                                               && \
                                                  continue
     
                      percent="${PCENT%?}"
                      [[ "${percent}" -lt 1 \
                                       || \
                         "${percent}" -gt 100 ]] \
                                       && \
                                          percent=99

                      if is_HORIZ_ "${ALIGN}"
                      then # print linear
        echo -n  "\${offset 0}${COLOR1}"
        echo -n  " ${target:0:8}"
        echo -n  "\${color $(color_ "$((percent))" "${UNICOLOR:-100}")}"
        echo -n  "\${offset ${HALFSPACE1}}$(printf "%5s" "${AVAIL}") "
                      else # print table
        echo -n  "${GOTO} ${INDENT1}}${COLOR1}"
        echo -n  "${target:0:15}"
        echo -n  "${GOTO} ${INDENT2}}${COLOR2}"
        echo -n  "$(printf %14s "${AVAIL}")"
        echo -n  "${GOTO} $((INDENT2+HALFSPACE1*26))}"
        echo -n  "\${color $(color_ "${percent%.*}" "${UNICOLOR:-100}")}"
        echo -n  "\${execbar ${BAR_height},${width} echo \"${percent%.*}\"}"
        echo -n  "${GOTO} $((INDENT2+HALFSPACE1*29+1))}"
        echo -n "\${offset $((width*${percent%.*}/125-HALFSPACE1*5))}"
        echo -n  "\${color $(color_ $((100-${percent%.*})) "$((99*${COLOR:-1}+1))")}$(printf "%4s" "${USED}")"
        echo
                      fi
                  done ## sorted on percent remaining
                } \
                | /usr/bin/head  -c -1 \
                              | tee "${file}"
                ## OR sort on total free space
                #} \
                #| /opt/bin/sort  --human-numeric-sort -k "6" \
                              #| /usr/bin/head  -c -1 \
                                            #| tee "${file}"
            else
        printf   "%s" "$(<"${file}")"
            fi

            is_CASCADING_ "${ALIGN}" \
            && \
        echo
      ;;

    p)                            # PROCESSES #
        if is_CASCADING_ "${ALIGN}"
        then
        heading_ "" "${ALIGN}" "${GOTO}" '0' "${COLOR1}" "${FONT1}" "$((SPACING+2))"
        echo -n  "$(print_RULE_ "${HR}" "$((LINE_length1/2-7))")"
        echo -n  "PROCESSES"
        print_RULE_ "${HR}" 1
        echo -n  "[$(bash_REMATCH_ '/proc/stat' 'running ([[:digit:]]+)')]"
        echo     "\${voffset -1}\${hr}\${voffset $((LINE_height1/3))}"

            # allow some expansion for wider viewport
              fudge="$(((LINE_length1-34)/4))"
              spacing=( "$((HALFSPACE2*28))" "$((HALFSPACE2*fudge))" "$((HALFSPACE2*fudge))" )

        echo -n  "${GOTO} $((INDENT1+CHARACTER_width2))}\${voffset -2}"
        echo -n  "${COLOR_units}${FONT2}"
        echo -n  "Command"
        echo -n  "\${offset ${spacing[0]}}"
        echo -n  "PID"
        echo -n  "\${offset ${spacing[1]}}"
        echo -n  "    %CPU"
        echo -n  "\${offset ${spacing[2]}}"
        echo     "   %MEM"

            # top in batch mode returns a variable number of lines
              list_pad="$ a\\\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n"

        else # printing horizontally, limit # of processes
            NPROCS=1
        fi

            move_to="$((INDENT1+HALFSPACE1*2))"
        echo -n  "${VOFFSET} ${SPACING}}${COLOR3}${FONT1}"
        /usr/bin/awk -v indent="${GOTO} ${move_to}}" -v cpu="\${offset ${spacing[1]}}" \
                     -v mem="\${offset ${spacing[2]}}" \
                     '{if ($1 != 0)
                           printf "%s%-14.14s%7d%s%6.1f%%%s%5.1f%%\n",
                                   indent,$11,$1,cpu,$7,mem,$8;
                       else printf}' < \
                    <(renice "${RENICE}" $BASHPID
                      /opt/bin/top  -bn 2 -d 0.01 -c -o +"${SORT}" \
                                 | /usr/bin/sed  -e "/top/d;${list_pad}"\
                                              | /usr/bin/tail  -n +11 \
                                                            | /usr/bin/head -n "${NPROCS}")
      ;;

    n)
          # credentials for local kodi
            kodi_pass=
            kodi_user=kodi
            kodi_host=localhost
            kodi_port=8080

            function kodi_REQ_ {
                /opt/bin/curl --silent -X POST --header "Content-Type: application/json" -d "$1" http://$kodi_user:$kodi_pass@$kodi_host:$kodi_port/jsonrpc; }
 
            function parse_JSON_ {
                local key=$1
                /usr/bin/awk -F"[,:}]" \
                             '{for(i=1;i<=NF;i++)
                              {if($i~/'"${key}"'\042/)
                                  {print $(i+1)}}}' \
                           | tr -d '"'; }

            function player_INFO_() {
                local match
                      match='^.*playerid":([[:digit:]]).*type":"([[:alpha:]]+)'
                
                [[ $(kodi_REQ_ '{ "jsonrpc":"2.0","method":"Player.GetActivePlayers","id":"99"}') \
                               =~ \
                               ${match} ]] \
                                           && \
                                               PLAYERID="${BASH_REMATCH[1]}"; }
                                               # may need this for audio 
                                                #PLAYERTYPE="${BASH_REMATCH[2]}"; }

            function times_() {
                parse_JSON_ '"hours|"minutes|"seconds' < \
                     <( kodi_REQ_ '{"jsonrpc": "2.0", "method": "Player.GetProperties", "params": { "playerid": '"$PLAYERID"', "properties": ["time","totaltime"] }, "id": 1}') \
                                | tr  '\n' ' ' \
                                   | /usr/bin/awk '{print $1*3600+$2*60+$3,
                                                          $4*3600+$5*60+$6}'; }

            function percentage_() {
                parse_JSON_ 'percentage' < \
                     <( kodi_REQ_ '{"jsonrpc":"2.0","method":"Player.GetProperties","params":{"playerid":1,"properties":["percentage"]},"id":"1"}'); }

        player_INFO_
        if ((PLAYERID))
        then

            times=( $(times_) )
            finish="$( /opt/bin/date -d "+$((times[1]-times[0])) secs" +'%I:%M%P')"

        # print finish time
          heading_ "$(print_RULE_ "${HR}" "$((LINE_length1/2-13))") Now Playing " "${ALIGN}" "${GOTO}" "$((INDENT1*1))" "${COLOR1}" "${FONT1}" "$((SPACING+2))"
          echo -n  "${FONT2}til${COLOR2}\${offset ${HALFSPACE1}}${finish:1: -1} ${COLOR1}${FONT1}"
          print_RULE_ "${HR}" "$((LINE_length1/2-13))"
          echo

            # remove ',' & ':' in titles & labels?
              nowplaying=$(/usr/bin/sed -e 's/,*\([ ]\)/\1/g;s/:*\([ ]\)/\1/g' < \
                         <(kodi_REQ_ \
                           '{"jsonrpc": "2.0","method":"Player.GetItem","params":{"properties":[ "showtitle","title","episode","season"],"playerid":'"$PLAYERID"'},"id":"VideoGetItem"}'))
            type=$(parse_JSON_ type <<< "${nowplaying}")

            case "${type}" in
              e*)
                  series=$(parse_JSON_ showtitle <<< "${nowplaying}")
                  episode_details=( $(parse_JSON_ 'episode|label|season' <<< "${nowplaying}" ) )
                  # picking up 'title'
                    [[ "${episode_details[-1]}" =~ ^[0-9]+$ ]] \
                                                || unset 'episode_details[-1]'
                  episode="${episode_details[0]}"
                  season="${episode_details[-1]}"
                  unset 'episode_details[0]' 'episode_details[-1]'
                  title="${episode_details[*]}"
                  main_line="${title:0:$((LINE_length1-INDENT1*1/CHARACTER_width1))}"
                  series_line="$(printf "%.$((LINE_length1-INDENT1/CHARACTER_width1))s S%02d E%02d" "${series}" "${season}" "${episode}")"
                ;;
              m*)
                  title="$(parse_JSON_ label <<< "${nowplaying}")"
                  main_line="${title:0:$((LINE_length2-INDENT2/CHARACTER_width2-4))}"
                 ;;
              c*)
        echo is channel
                 ;;
              u*)
                  title=$(parse_JSON_ label <<< "${nowplaying}" )
                  main_line="${title:0:$((LINE_length1-INDENT1*3/CHARACTER_width1))}"
                ;;
            esac  

        echo -n  "${GOTO} $((INDENT1+0))}${COLOR3}${FONT1}"
        justify_ "center" \
                 "${main_line}" \
                 "$((LINE_length1-INDENT1/CHARACTER_width1))"

            if is_SET_ "${series_line}"
            then 
        echo -n  "${GOTO} $((INDENT1+CHARACTER_width1*0))}${COLOR2}${FONT2}"
        justify_ "center" \
                 "${series_line}" \
                 "$((LINE_length2-INDENT1/CHARACTER_width2))"
            fi

            if is_SET_ "${playlist_max}"
            then
                function play_list_() {
                    renice "${RENICE}" $BASHPID
                    parse_JSON_ 'label|title' < \
                               <(/usr/bin/sed -e 's/,*\([ ]\)/\1/g;s/:*\([ ]\)/\1/g;s/\(title":"\)"/\1 "/g' < \
                                 <(kodi_REQ_ '{"jsonrpc":"2.0","method":"Playlist.GetItems","params":{"playlistid":'"$PLAYERID"',"properties":["title","showtitle"]},"id":"1"}') \
                                 | \
                                 /usr/bin/awk -F"[}]" '{for(i=1;i<NF;i++){print $i}}' \
                                 | \
                                 /usr/bin/sed '/showtitle/!s/","title.*/","showtitle":" &}/g;' ) \
                                 | \
                                 /usr/bin/sed -e "s/^ $/null/;s/^/\${goto $((INDENT1+1))}/" ;}

                mapfile -t playlist < <(play_list_ )

                # slice array at 'Now Playing'
                  for ((i=0;i<"${#playlist[@]}";i+=3))
                  do if [[ "${playlist[$i]}" =~ ${title:0:8} \
                        || "${playlist[$i]}" =~ "play" ]]
                     then playlist=( "${playlist[@]:$((i+3))}" )
                         break
                     fi
                  done
            
                if [ "${#playlist[@]}" -gt 0 ]
                then
        echo -n  "\${goto $((INDENT1*1))}${COLOR1}\${voffset ${SPACING}}${FONT2}"
        print_RULE_ "${HR}" "$((LINE_length2/2-7))"
        echo -n  " Up Next "
        print_RULE_ "${HR}" "$((LINE_length2/2-5))"
        echo    "${VOFFSET} $((SPACING+0))}"
        echo -n "${FONT2}"

                    [[ "$((playlist_max*3))" -gt "${#playlist[@]}" ]] \
                                              && \
                                  playlist_max=$((${#playlist[@]}/3))

                    for ((i=0;i<"$((playlist_max*3))";i+=3))
                    do text_length=$((LINE_length2+4))
                       if [[ ! "${playlist[$((i+1))]}" =~ null ]]
                       then
                           playlist[$((i+1))]="$(/usr/bin/sed -e "s/[\${][^}]*[}]//g" <<< \
                                                              "${playlist[$((i+1))]}")"
                           text_length=$((text_length-"${#playlist[$((i+1))]}"+1))
                       fi
        echo -n "${COLOR2}$(/usr/bin/sed -e 's/play/yo.tu.be/;s/}[ ]*/}/' <<< \
                                         "${playlist[${i}]:0:${text_length}}${COLOR1}\${alignr}")"
        /usr/bin/sed -e "s/null/ /g" <<< "${playlist[$((i+1))]} "
                    done
                fi
        fi
                is_CASCADING_ "${ALIGN}" \
                && { \
        echo -n  "\${goto $((INDENT1*1))}${COLOR1}\${voffset -2}${FONT2}"
        print_RULE_ "${HR}" "$((LINE_length1*1+6))"
                   }
        echo

        fi
      ;;

    o)                             # OS INFO #
       if is_CASCADING_ "${ALIGN}"
       then # print lots of superfluose data over 1/10 of a second
            # run script with -o & add output to conkyrc from here to # EOO # 
            # then comment out, because it seems like wasted time
        # Heading
        echo -n "${GOTO} 0}${COLOR2}${FONT1}"

        echo    "\${alignc}$(bash_REMATCH_ /etc/issue \
                                           '^(C.*[[:blank:]].*[[:blank:]].*[[:blank:]])')"

              # hardware
        echo -n "${GOTO} 0}${FONT1}"
        echo    "\${alignc}$(bash_REMATCH_ /proc/cpuinfo '^Ha.*:[[:blank:]](.*+)')"

              # model name  
        #echo -n  "${GOTO} 0}${FONT1}"
        #echo "\${alignc}$(bash_REMATCH_ /proc/cpuinfo '^model.*:[[:blank:]](.*+)')"

              UNAME="$(uname -a)"

              # os
        echo -n "${GOTO} 0}${COLOR1}${FONT2}"
        echo    "\${alignc}${UNAME: -17}"

              # kernel
        echo -n  "${GOTO} 0}${COLOR1}${FONT2}"
        echo     "\${alignc}$(echo "${UNAME:0:37}"|tr '#' d)"
        echo -n  "\${voffset -2}"
        echo -n  "\${alignc}${COLOR1}"
        print_RULE_ "${HR}" "39"
        echo
  ## EOO #########################################################################

              # cpu configuration & governor
        echo -n  "${GOTO} ${INDENT2}}\${voffset ${SPACING}}${COLOR1}${FONT2}"
        echo -n  "\${alignc}($(bash_REMATCH_ /usr/bin/lscpu '^CPU\(.*([[:digit:]])'))"
        echo -n  " cores governer: ${COLOR3}"
        echo     "$(</sys/devices/system/cpu/cpufreq/policy0/scaling_governor)"
 
               # entropy available
        echo -n  "${GOTO} ${INDENT1}}${COLOR1}${FONT2}"
        echo -n  "\${alignc}${COLOR1}Random:"
        echo -n  "${COLOR2}pool:${COLOR3}"
        echo -n  "$(</proc/sys/kernel/random/poolsize)"
        echo -n   "${COLOR2} available:${COLOR3}"
        echo     "$(</proc/sys/kernel/random/entropy_avail)"
 
               # roll your own
        #echo -n "${GOTO} ${INDENT1}}${COLOR1}:"
        #echo    "\${alignc}Something interesting"
 
        echo     "\${voffset -3}${COLOR1}\${hr 1}"
 
       else # outputting horizontally
        echo -n  "${GOTO} ${INDENT1}}${COLOR1}${FONT1}Gvn:"
        echo -n  "${COLOR2}"
        echo -n  "$(</sys/devices/system/cpu/cpufreq/policy0/scaling_governor)"
        echo -n  "${GOTO} ${SPACING}}${COLOR1}Rnd:"
        echo -n  "${COLOR3}$(</proc/sys/kernel/random/entropy_avail)"
        echo -n  "${COLOR2}/${COLOR3}$(</proc/sys/kernel/random/poolsize)"
       fi
      ;;

    w) # WINDOW WIDTH AND LINE HEIGHT FONT1 & FONT2
        # To determine width of a character in conky "position 'x'" terms
        # and the height of a line for conky 'voffset'
        # first set line_width[n] to equal 'line length' seen in viewport
        # then set 'character_width' until the second line touches right edge
        # change line_height[n] until lines are evenly spaced

        function line_WIDTH_() {
            local font="$1"
            [[ ! "${font}" =~ font ]] \
                           && \
                              return
            chomp="$2"
            character_width="$3"
            line_height="$4"
            cline_height="${GOTO} $((chomp*character_width-(character_width*2)))}"
            cline_height+="E\${voffset ${line_height}}"
            cline_height+="\${offset -${character_width}}E\${voffset -${line_height}}E"
            a_long_line="123456789112345678921234567893123456789412345678951234567896"
            cline="${a_long_line:0:${chomp}}"
            while read -r num
            do l_line+="${num: -1}"
            done < <(seq 99)
            cline="${l_line:0:${chomp}}"

          echo -n  "${font}\${color grey90}\${voffset ${SPACING}}"
          echo     " font $( [[ "${font}" =~ t[[:space:]](.*+)} ]] \
                                          && \
                                             echo "${BASH_REMATCH[1]}")"
          echo     "${cline}"
          echo     "${cline_height}"
          echo; } 

        if is_CASCADING_
        then
            # big font
              line_WIDTH_ "${FONT1}" "${LINE_length1}" \
                          "${CHARACTER_width1}" "${LINE_height1}"
            # small font
              line_WIDTH_ "${FONT2}" "${LINE_length2}" \
                          "${CHARACTER_width2}" "${LINE_height2}"
        fi
        ;;

v) # FOR BENCHMARKING see heading to delete using sed
if is_CASCADING_ "${ALIGN}"; then
echo -n "\${voffset $((SPACING*1+3))}${COLOR1}${FONT1}"
print_RULE_ "${HR}" "$((LINE_length1/2-6))"
echo "Runtime Stats\${voffset -1}\${hr}"
else
echo -n "${GOTO} $((INDENT1+15))}${COLOR1}${FONT1}"
fi
#
NCORES="$(bash_REMATCH_ /usr/bin/lscpu '^CPU\(.*([[:digit:]])')"
avg_cpu=$(awk '/avg/ {sum+=$(NF-2); count ++}END
{if (count > 0)printf "%5.1f",
(sum/count)}' "${TIME_log}" | /usr/bin/tail -1)
[ -z "${uptime}" ] \
&& uptime=$(cut -d' ' -f1 /proc/uptime)
[ -z "${clock_ticks}" ] \
&& clock_ticks=$(awk '{print$22/'"$(/usr/bin/tail -n 1 /proc/uptime|cut -d. -f1)}" /proc/self/stat)
#
label="CPU avg\${color #C2F3F6}"
newline=$'\n'
is_CASCADING_ "${ALIGN}" \
&& { newline='';
label="\${offset 10}Cpu usage avg\${color #C2F3F6}\${offset 10}"; }
#
# cpu usage avg & current from /proc/$$/stat
awk -v avg="${avg_cpu}" -v ticks="${clock_ticks}" -v uptime="${uptime}" -v ncores="${NCORES}" -v label="${label}" '{total=$14+$15; start_time=$22;}END
{printf "%s%5.1f\${offset 4}\${color #06939B}%%\${offset 5}\${color #06939B} now\${color #C2F3F6} %4.1f \${color #06939B}%%\n",
label,avg, ( ( 100 * ( total / ticks ) / ( uptime - ( start_time / ticks))) );}'  "/proc/$$/stat" \
| tee -a "${TIME_log}" \
| tr -d "${newline}"
#
label="\${offset 5}TIME\${offset 0}\${color #C2F3F6}"
newline=$'\n'
is_CASCADING_ "${ALIGN}" \
&& { newline=$'\n';
label="\${offset 10}Runtime\${offset 4}\${color #C2F3F6}\${offset 55}"; }
#
# runtime avg & current from TIME_log closer to time from remote
awk -v label="${label}" -v runtime="$((($(/usr/bin/date +%s%N)-tss)/1000000))" '/MONITOR/ {sum+=$3; count++}END{if (count > 0)printf "%s%5.2f\${color #06939B}s\${offset 5}\${color #C2F3F6}%7.2f\${color #06939B}s\n",label,((sum / count)/1000),(runtime/1000);}' "${TIME_log}"
;;
    h|*)
        _Usage "$@"
     ;;

  esac
  done
                 is_CASCADING_ "${ALIGN}" \
                 && { \
          echo -n "\${alignc}${COLOR1}";
          print_RULE_ "${HR}" "$((LINE_length1*1+6))"; }

  shift $((OPTIND-1))
# Total time for script
echo "\${goto ${INDENT1}}${COLOR2}${FONT_units}COMMAND: MONITOR $((($(/usr/bin/date +%s%N)-tss)/1000000)) ms" | sed -e "s/[\${][^}]*[}]//g" >> "${TIME_log}"
# Trim to ~ last 5 minutes
[ "$( wc -l < "${TIME_log}" )" -gt 50 ] && ( sed -i  -e :a -e '$q;N;50,$D;ba' "${TIME_log}" )&

 exit 0

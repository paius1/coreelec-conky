#!/opt/bin/bash
#   v 0.9.2
#  Outputs CoreELEC OS stats in conky printable format
#  uses entware's bash, bind-dig, coreutils-df, coreutils-sort,
#                 coreutils-stat, procps-ng-top
#     
#   Usage: SCRIPTNAME -[ocltumeqirxsdfp]
#          [o] os info <ng>   [c] cpu usage         [l] load average
#          [t] temp cpu & ram [u] uptime            [m] memory
#          [e] network essid  [q] wireless quality  [i] lan address
#          [r] network region [x] public ip         [s] network up/down speed
#          [d] disk i/o       [f] mounted filesystems, free space, & graph of usage
#          [p] processes command pid %cpu %mem (sorted w/ SORT=%CPU|%MEM)
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
#    
#   prints output in order of options <fewer options faster time / less load>
#   
#   run: time ssh Hostname /path/to/coreelec-conky.sh -[ocltumeqirxsdfp] >/dev/null
#   to determine 'interval' & add the following to your conkyrc:
#   
#   ${texecpi 'interval' ssh Hostname /path/to/coreelec-conky.sh -[ocltumeqirxsdfp]}
#   
#   add 'UseDNS no' to /storage/.cache/services/sshd.conf on CoreELEC
#   
#   alignment and cpu format can be changed from the command line
#     pass [left|center|right|horiz] for alignment
#     pass [long|longer|longest] for frequency|per core|graph
#   
#   to remove all nonindented (debug) lines after this heading
#     sed -i -e '69,$ { /^[^[:blank:]]/d }' /opt/bin/coreelec-conky.sh 
#   
#   http://kfirlavi.herokuapp.com/blog/2012/11/14/defensive-bash-programming/
#   
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

  # Default alignment
    ALIGN="left"
  # offset between options
    SPACING=4
  # height of filesystem bar (odd numbers center better)
    BAR_height=14
  # set to show memory stats as text
    MEM_text=1
  # sort "NPROCS" processes on "SORT" (%CPU or %MEM)
    NPROCS=4
    SORT="%CPU"
  # Colorize data 1=colorize 0=monochrome
    COLOR=1
  # colors for labels, sublabels,
  #   data, & units
    COLOR1="\${color #06939B}"; COLOR2="\${color #34BDC4}"
      COLOR3="\${color #9FEEF3}"; COLOR_units="\${color grey70}"
  # a monospace font found on computer running conky
  # run fc-list :spacing=100 ( n.b some fonts are limited )
    font_family="Hack"
    FONT1="\${font ${font_family}:size=9}"
    FONT2="\${font ${font_family}:size=8}"
    FONT_units="\${font ${font_family}:size=7}"
  # run with -w  to determine the next 6
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
    HALFSPACE1=$(((CHARACTER_width1+1)/2)); HALFSPACE2=$(((CHARACTER_width2+1)/2))

  # allow changing alignment & format from the conky config
  # arguments at beginning either order
    if [[ "$1" = +(le*|r*|c*|h*) ]];  then ALIGN="$1";  shift; fi
    if [[ "$1" = +(lo*|s*) ]]; then FORMAT="$1"; shift; fi
    if [[ "$1" = +(le*|r*|c*|h*) ]];  then ALIGN="$1";  shift; fi
  # arguments at end either order
    if [[ "${@: -1}" == +(lo*|s*) ]]; then FORMAT="${@: -1}"; set -- "${@:1:$(($#-1))}"; fi
    if [[ "${@: -1}" == +(le*|r*|c*|h*) ]]; then ALIGN="${@: -1}"; set -- "${@:1:$(($#-1))}"; fi
    if [[ "${@: -1}" == +(lo*|s*) ]]; then FORMAT="${@: -1}"; set -- "${@:1:$(($#-1))}"; fi
#
# add options in conkyrc to skip these defaults
#
if [[ ${#1} -eq 1 ]]
then # add options after %/

if [[ ! "${ALIGN}" =~ ^h ]]
then # cascading
set -- "${@/%/ocltumeqirxsdfp}"
# for benchmarking
#set -- "${@/%/v}"
FORMAT=long
ALIGN=left

else # horizontal
set -- "${@/%/cltumeqirxsfd}"
FORMAT=long

fi

fi
#
# for benchmarking script
TIME_log="/tmp/time-${ALIGN:0:1}"
#
  # add some space to INDENT2 for left justify
    [[ "${ALIGN}" =~ ^l ]] && INDENT2=$((INDENT2+HALFSPACE1*5))
  # cascading conky
    GOTO="\${goto "
    VOFFSET="\${voffset "
  # left hr since conky can't define hr width
  # character is unicode, so cut at multiples of 3 e.g. ${HR:0:9}
    while read -r num; do HR+="―"; done < <(seq "$((LINE_length2))")
     export LC_ALL=C
  # delay for refreshing disk usage to save cpu time
    FS_dt=16
  # the @ character prints below the line
    ASTERISK="\${voffset -1}@\${voffset 1}"
#

  function gradient_() { # Pretty colors for data
    cat <<- ' EOg'
    ff3200
    ff3c00
    ff4600
    ff5000
    ff5a00
    ff6400
    ff6e00
    ff7800
    ff8200
    ff8c00
    ff9600
    ffa000
    ffaa00
    ffb400
    ffbe00
    ffc800
    ffd200
    ffdc00
    ffe600
    fff000
    fffa00
    fdff00
    d7ff00
    b0ff00
    8aff00
    65ff00
    3eff00
    17ff00
    00ff10
    00ff36
    00ff5c
    00ff83
    00ffa8
    00ffd0
    00fff4
    00e4ff
    00d4ff
 EOg
    return 0
 }
  export -f gradient_
    STEPS=$(wc -l < <(gradient_))

  function color_() { # Return HEX color code from gradient function
      local current=$1
      local maximum=$2
      is_EMPTY_ "$maximum" || [[ "$maximum" = "0" ]] \
                          && { echo "${COLOR3:8:-1}"
                               return 1; }
      local color

      color=$(((current*STEPS+maximum/2)/maximum+1))
      [[ "${color#-}" -ge 1 && "${color#-}" -lt 38 ]] \
          || color=37
      [ "${color#-}" -eq 0 ] \
          && color=1
      /usr/bin/tail -n "${color#-}" < <(gradient_) \
                    | /usr/bin/head -1
  return 0
 } 
 export -f color_

  function is_HORIZ_() {
      local align=$1
      [[ "${align}" =~ ^h ]]
 }
 export -f is_HORIZ_

  function is_CASCADING_() {
      local align=$1

      [[ ! "${align}" =~ ^h ]]
 }
 export -f is_CASCADING_

  function heading_() {
      local label=$1
      local align=$2
      local conky_object=$3
      local position=$4
      local color=$5
      local font=$6
      local spacing=$7

      echo -n  "${conky_object} ${position}}${color}${font}"
      is_CASCADING_ "${align}" \
      && echo -n "\${voffset ${spacing}}${label}"
  return 0      
 }
 export -f heading_

  function justify_() { # ALIGN string on line_length
                        # print newline if !horizontal
     local align="$1"
      local string="$2"
      local line_length="$3"
      local length_text padding newline
      
      case "${align}" in

          r*|c*)
                 # remove any leading & trailing whitespaces
                   string=$(sed -e 's/}[ \t]*/}/' -e 's/^[[:space:]]*//' \
                                -e 's/[[:space:]]*$//' <<< "${string}")

                 # length of string stripped of conky formating
                   length_text=$(($(sed -e "s/[\${][^}]*[}]//g" <<< \
                                        "${string}" | wc -c)-1))

                 # check length of line v length of text
                   [[ "${length_text}" -gt "${line_length}" ]] \
                                        && { echo "length: ${line_length} < string: ${length_text}";
                        return 2; }

                 # spaces to pad string
                   padding=$((line_length-length_text))
                   [[ "${align}" =~ ^c ]] \
                                 && padding=$(((padding+2/2)/2+1))

             ;&
          l*)    # Just add newline to printf
                   newline=$'\n'
            ;&
          *)     # printf ${padding}${string}${newline}
                 # remove any leading & trailing whitespaces for horizontal
                   string=$(sed -e 's/^[[:space:]]*//' \
                                -e 's/[[:space:]]*$//' <<< "${string}")
                   printf "%$((padding+${#string}))s%s" "${string}" "${newline}"
            ;;

        esac
    return 0
 }
 export -f justify_

  function bash_REMATCH_() { # Return specific data in matching line of file
      local output           # or command output; no '(capture)+' to count match lines
      local file_comm="$1"
      local pattern="$2"
      is_NOT_empty_ "$3" \
      && output="/tmp/${1##*/}-${ALIGN}"

      if [[ "${file_comm}" =~ ip|if|con ]]
      then # $1 is a command
          while IFS= read -r line
          do if [[ "${line}" =~ ${pattern} ]]
             then echo "${BASH_REMATCH[1]}" \
                       | tee -a "${output:-/dev/null}"
             fi
          done < <(${file_comm})
      else # $1 is a file clear to allow use of append
          echo -n "" > "${output:-/dev/null}"
          while IFS= read -r line
          do if [[ "${line}" =~ ${pattern} ]]
             then echo "${BASH_REMATCH[1]}" \
                       | tee -a "${output:-/dev/null}"
             fi
          done < "${file_comm}"
      fi
  return 0
 }
 export -f bash_REMATCH_

  function interval_() {
      local then=$1
      local file=$2
      local now
      now=$(/usr/bin/date +%s \
                                | tee "${file:-/dev/null}")
      echo $((now-then)) 
  return 0
 }
 export -f interval_

  function check_IP_data_() { # Check if ip data file is/recent or create/update
        { is_READABLE_ "${1}" \
          && [ "$(($(/usr/bin/date +%s)-$(/opt/bin/stat -c %Y "${1}")))" -le "${CURL_dt}" ]; } \
               && return 0

      curl -sf -m 2 ipinfo.io/"$(/opt/bin/dig +short myip.opendns.com @resolver1.opendns.com)" > "${1}" \
          || echo -e "{\n\"ip\": \"NO.RE.P.LY\"
             \"city\": \"NO\"
             \"region\": \"PLACE LIKE\"
             \"country\": \"HM\"
             }" > "${1}"
  return 0
 }
 export -f check_IP_data_

  function is_EMPTY_() {
      local var=$1

      [[ -z $var ]]
 }
 export -f is_EMPTY_

  function is_NOT_empty_() {
      local var=$1

      [[ -n $var ]]
 }
 export -f is_NOT_empty_

  function is_NOT_file_() {
      local file=$1

      [[ ! -f $file ]]
 }
 export -f is_NOT_file_

  function is_READABLE_() {
      local file=$1

      [[ -r $file ]]
 }
 export -f is_READABLE_

  # horizontal conky
    if is_HORIZ_ "${ALIGN}"
    then # keep fonts same, change goto to offset, & drop labels
       GOTO="\${offset "
       VOFFSET="\${offset "
       FONT1="${FONT2}"
       FONT_units="${FONT1}"
       CHARACTER_width1="${CHARACTER_width2}"
       HALFSPACE1="${HALFSPACE2}"
       # this becomes the spacing between options
         INDENT2="${SPACING}"
    fi

  if [[ "${@}" =~ (e|q|i|r|x|s) ]]
  then # outputing network information
     # Network interfaces
       ACTIVE_iface=$(bash_REMATCH_ "/sbin/ip route show" \
                                    '^d.*[[:space:]]([^[:space:]]+)[[:space:]]$')
       ACTIVE_wifi=$(bash_REMATCH_ "/sbin/ip addr" '(wlan[[:digit:]]):[[:blank:]]<BR')
     # file for public ip data
       IP_data="/tmp/network_DATA"
     # delay for curling ipinfo.co (1,000/day is their max)
       CURL_dt=180
  fi

  # number of cpu cores
    NCORES=$(bash_REMATCH_ /proc/cpuinfo '^processor' | wc -l)

  while getopts "ocltmueqxirspfdhwv" opt
  do
  case "${opt}" in

    c)                               # CPU #
        heading_ "CPU:" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

              function core_PER100() { # Get cpu stats
                  renice -15 $BASHPID
                  local cpu_usage=("$@")
                  local ncores
                  ncores="$(((${#cpu_usage[@]}-2)/2))"
                  for ((core=0;core<="${ncores}";core++))
                  do awk '{S13+=$13;S2+=$2;S15+=$15;S4+=$4;S16+=$16;S5+=$5}END
                         {printf "%6.1f\n",
                                  (S13-S2+S15-S4)*100/(S13-S2+S15-S4+S16-S5);}' < \
                         <(printf '%s %s\n' \
                                  "${cpu_usage[$core]}" "${cpu_usage[$((core+ncores+1))]}")
                          done
              return 0; }

        # Get cpu stats
        # variables for bash_REMATCH_
          file='/proc/stat'
          cpu_stats="/tmp/${file##*/}-${ALIGN}"
 
        # make room for current reading
          mv "${cpu_stats}" "${cpu_stats:0: -1}" 2>/dev/null \
              || touch "${cpu_stats:0: -1}" # create

        # array of previous & current cpu stats 
          mapfile -t cpu_usage 2>/dev/null < \
                 <(cat "${cpu_stats:0: -1}"  2>/dev/null \
                 <(bash_REMATCH_ "${file}" '(^cpu.*)+' 'save' ))

        # total and per core %
          mapfile -t core_per100 < <(core_PER100 "${cpu_usage[@]}")

        # heterogenous cpu?
          HETEROGENEOUS="$(bash_REMATCH_   '/proc/cpuinfo' '^CPU p.*x([[:alnum:]]+)' \
                                         | uniq \
                                         | wc -l)"

        case "$FORMAT" in # How much data to print

          *st)    # Cpu graph (pass longest)

              if is_CASCADING_ "${ALIGN}"
              then
        echo -n  "${GOTO} ${INDENT1}}"
        echo -n  "\${voffset $((LINE_height1*1+LINE_height2*1+(SPACING*1)))}"
        echo -n  "${FONT2}"
                 h="$((LINE_height1*2))"
                 w="$(((LINE_length1*CHARACTER_width1-HALFSPACE1*5)))"
                 skip=$((LINE_height1*1+LINE_height2*3))
              else # horizontal conky
                 h="$((9*1))"
                 w="$(((CHARACTER_width1*8)))"
              fi
        echo -n  "\${execgraph \"echo ${core_per100[0]%.*}\" ${h},${w} 00FF00 FF0000 -t }"

              # return to CPU: line
                is_CASCADING_ "${ALIGN}" \
                && \
        echo -n  "\${voffset -$((LINE_height1*1+LINE_height2+(SPACING*1)))}"
             ;&
          *r)     # Print per core percentages (pass longer to script)

              # skip color gradient to save time
                oCOLOR=$COLOR; COLOR=0

              case "${ALIGN}" in
                h*)
        echo -n "\${offset -$((CHARACTER_width1*2))}"
                   ;;
                l*)
        echo -n "\${voffset $((LINE_height1))}${FONT2}${GOTO} $((INDENT1+HALFSPACE2*5))}"
                  ;;
                *)
        echo -n "\${voffset $((LINE_height1))}${FONT2}${GOTO} $((INDENT1+HALFSPACE2*7))}"
                  ;;
              esac

              case "${HETEROGENEOUS}" in

                2) # print per core in big.Little order
        justify_ "${ALIGN}" \
                 "$(for core in 3 4 5 6 1 2
                    do echo -n "\${color $(color_ "${core_per100[$core]%.*}" "$((100*COLOR))")}"
                       echo -n "$(printf '%6.1f' "${core_per100[$core]}")"
                       echo -n "${COLOR_units}\${offset 2}%\${color}"
                    done)" \
                 "$((LINE_length2-INDENT2/CHARACTER_width2))"
                  ;;

                *) # OR cores in numeric order
        justify_ "${ALIGN}" \
                 "$(for ((core=1;core<="${NCORES}";core++))
                    do echo -n "\${color $(color_ "${core_per100[$core]%.*}" "$((100*COLOR))")}"
                       echo -n "${core_per100[$core]}"
                       echo -n "${COLOR_units}\${offset 2}%\${color}"
                    done)" \
                 "$((LINE_length2-INDENT2/CHARACTER_width2))"
                  ;;
              esac

              if is_CASCADING_ "${ALIGN}"
              then # return to previous line
        echo -n  "\${voffset -$((LINE_height1*1+LINE_height2))}"
                  [[ "${FORMAT}" =~ ^longes ]] &&
        echo -n "\${voffset -$((LINE_height1*2))}"
                  ((skip)) \
                     || skip=$((LINE_height1*1))
              fi

                 # return to color scheme
                   is_EMPTY_ "${oCOLOR}" \
                            || COLOR="${oCOLOR}"
             ;&
          l*)     # Print frequencies, % for big.LITTLE as well

              function human_FREQUENCY_() { # GHz, MHz units for cpu frequency
                  awk -v units_style="\${offset 1}${FONT_units}${COLOR_units}" '
                      {if ($1+0>999999)
                          printf "%5.1f%sGHz\n",
                          $1/10^6, units_style;
                       else printf "%5.0f%sMHz\n",
                       $1/10^3,units_style}' <<< "${1}"
              return 0; }

              function core_bL_() { # get usage for a range of cores
                  awk '{sum13+=$13;sum2+=$2;sum15+=$15;sum4+=$4;sum16+=$16;sum5+=$5}END
                       {printf "%6.1f",
                        (sum13-sum2+sum15-sum4)*100/(sum13-sum2+sum15-sum4+sum16-sum5);}'  < \
                      <(for ((core="${1}";core<="${2}";core++))
                         do printf '%s %s\n' "${cpu_usage[$core]}" "${cpu_usage[$((core+NCORES+1))]}"
                         done)
              return 0; }

              # Current frequency minimum and maximum
                mapfile -t fqz < \
                       <(cat /sys/devices/system/cpu/cpufreq/policy*/scaling_*_freq)

              case "${HETEROGENEOUS}" in

                2) # add usage & frequency for heterogeneous 'big' cores
                    big_perc="$(core_bL_ 3 6)"
                    LITTLE_perc="$(core_bL_ 1 2)"

                   # concatenate line so its closer to 80 columns
                     l_string="\${offset 1}${FONT2}"
                     l_string+="\${color $(color_ "${big_perc%.*}" "$((100*COLOR))")}"
                     l_string+="${big_perc}"
                     l_string+="\${offset ${HALFSPACE2}}${COLOR_units}%"
                     l_string+="\${offset ${HALFSPACE2}}${ASTERISK}"
                     l_string+="\${offset -${CHARACTER_width2}}"
                     l_string+="\${color $(color_ "$((fqz[3]-fqz[5]))" "$(((fqz[4]-fqz[5])*COLOR))")}"
                     l_string+="$(human_FREQUENCY_ "${fqz[3]}")"
                     l_string+="\${offset ${HALFSPACE2}}${VOFFSET} -1}"
                     l_string+="\${color $(color_ "${LITTLE_perc%.*}" "$((100*COLOR))")}"
                     l_string+="${FONT2}${LITTLE_perc}"
                     l_string+="\${offset 2}${COLOR_units}%\${offset 2}"
                  ;;

                *) # homogeneous cpu, position current frequency after cpu%
                    [[ "${ALIGN}" =~ ^r ]] \
                                          && move_to="$((HALFSPACE1*2))"
                  ;;
              esac

              # add frequency for only/'LITLE' cores
                l_string+="${ASTERISK}"
                l_string+="\${offset -${CHARACTER_width1}}"
                l_string+="\${color $(color_ "$((fqz[0]-fqz[2]))" "$(((fqz[1]-fqz[2])*COLOR))")}"
                l_string+="$(human_FREQUENCY_ "${fqz[0]}")"

                 case "${ALIGN}" in
                   c*) move_to="$((HALFSPACE1*7))";;
                   r*) is_EMPTY_ "${move_to}" && move_to="$((HALFSPACE1*7))";;
                   l*) move_to="$((INDENT1+CHARACTER_width1*5))";;
                   *)  move_to=1
                 esac

               ((skip)) \
                    || skip="$((SPACING-3))"
            ;&
          *) # print overall percentage

               if is_EMPTY_  "${move_to}"
               then case "${ALIGN}" in
                     c*) move_to="$((HALFSPACE1*9))";;
                     r*) move_to=0;;
                     l*) move_to="$((INDENT2*1-CHARACTER_width1))";;
                     *)  move_to="$((CHARACTER_width1*2))";;
               esac
               fi

              c_line+="\${color $(color_ "${core_per100[0]%.*}" "$((100*COLOR))")}"
              c_line+="${core_per100[0]}"
              c_line+="\${offset 1}${COLOR_units}%"

        echo -n  "${GOTO} ${move_to}}${FONT1}"
        justify_ "${ALIGN}" \
                 "${c_line}${l_string}" \
                 "${LINE_length1}"

              case "${ALIGN}" in
              h*)
        echo -n "\${offset 5}";;
              *) ((skip)) || skip=0
        echo -n  "\${voffset ${skip}}";;
              esac    
            ;;
        esac

                if [[ "${FORMAT}" =~ ^longe \
                   || "${core_per100[0]%.*}" -gt 70 ]]
                then # iowait and softirq for case: longe* or high cpu usage
        echo -n "${FONT2}${COLOR1}"
        awk '{start=($2+$3+$4+$5+$6+$7+$8+$9+$10);
              end=($13+$14+$15+$16+$17+$18+$19+$20+$21);
              iowStart=($6);iowEnd=($17);
              sirqStart=($8);sirqEND=($19)}END
             {printf "\${alignc}iowait: %6.4f%%  softirq: %6.4f%%",
                      (iowEnd-iowStart)*100/(end-start),
                      (sirqEND-sirqStart)*100/(end-start);}'  < \
           <(printf "%s %s\n" "${cpu_usage[0]}" "${cpu_usage[$((NCORES+1))]}")
            is_CASCADING_ "${ALIGN}" \
        && echo
                fi
      ;;

    l)                             # LOADAVG #
        heading_ "LOAD:" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

            mapfile -d' '  loadavg < /proc/loadavg

            for avg in {0..2}
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

            a_line+="\${color ${load_color[0]}}"
            a_line+="$(sed -e 's/[ \t]*//'  <<< "${loadavg[0]}")"
            a_line+="\${color ${load_color[1]}}"
            a_line+="${loadavg[1]}"
            a_line+="\${color ${load_color[2]}}"
            a_line+="${loadavg[2]}"

        echo -n  "${GOTO} $((INDENT2+0))}"
        justify_ "${ALIGN}" \
                 "${a_line}" \
                 "$((LINE_length1-INDENT2/CHARACTER_width1))"

            if [[ "${loadavg[1]%.*}" -ge 5 ]]
            then # high load average can mean blocked processess
                 mapfile -t procs < \
                        <( bash_REMATCH_ /proc/stat '^procs_(.*)+' )

        echo -n  "\${color #ff3200}\${alignc} ${procs[0]} ${procs[1]}"
            is_CASCADING_ "${ALIGN}" \
        && echo
            fi
      ;;

    t)                           # TEMPERATURES #
        heading_ "TEMP:" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

            # hot for the cpu/ram
              hot=70

            # name thermal zones ( note the space before element 1 )
              zones=('Cpu:' ' Mem:')
              is_HORIZ_ "${ALIGN}" \
                        && zones=('C:' ' M:')

            # read all zones
              mapfile -t temps 2>/dev/null < \
                     <( cat /sys/class/thermal/thermal_zone*/temp)

            # unicode character ° throws off justify function
              case "${ALIGN}" in
                c*|r*) right=2;;
                *)     right=0;;
              esac

            for temp in $(seq "${#temps[@]}")
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

            if [[ "$((((temps[0]+(1000/2))/1000)))" -ge "${hot}" ]]
            then # Hi temp, what process is using most cpu
            is_CASCADING_ "${ALIGN}" \
        && echo -n  "\${voffset ${SPACING}}"
        echo -n  "\${color #ff3200}${FONT1}"
        awk -v indent="${GOTO} $((INDENT2+0))}" '
            {if ($1) printf "%s%-10s%7d%6.1f%%%6.1f%%",indent,$11,$1,$7,$8;
             else printf $2}' < <(/opt/bin/top -bn 2 -d 0.01 -c -o +"${SORT}" | 
             sed -e '/top/d' | /usr/bin/tail -n +11 | /usr/bin/head -1)
            is_CASCADING_ "${ALIGN}" \
        && echo
            fi
      ;;

    u)                             # UPTIME #
        heading_ "UPTIME:" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

            # units
              u=( " days" " hrs" " mins" )
              is_HORIZ_ "${ALIGN}" \
                            && u=( "d" "h" "m" )

        echo -n  "${GOTO} ${INDENT2}}${COLOR3}"
        justify_ "${ALIGN}" \
                 "$(awk -v d="${u[0]}" -v h="${u[1]}" -v m="${u[2]}" \
                        -F"[ |.]+" '{secs=$1;}END
                        {printf "%2d%s %2d%s %2d%s",
                         secs/86400,d,secs%86400/3600,h,secs%3600/60,m;}' \
                    /proc/uptime)" \
                 "$((LINE_length1-INDENT2/CHARACTER_width1))"
      ;;

    m)                             # MEMORY #
        heading_ "" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"
              label='MEM:'

            # Mem:used MemTotal - 
            # match='^[B|C|M|S][e|u|a|l].*:[[:blank:]]*([[:digit:]]+)[[:blank:]]'
            # Mem:used MemTotal - MemAvailable - Buffers
            # match='^[M|B][e|u].*:[[:blank:]]*([[:digit:]]+)[[:blank:]]'
            mapfile -t memory < \
                   <(bash_REMATCH_ /proc/meminfo \
                                   '^[M|B][e|u].*:[[:blank:]]*([[:digit:]]+)[[:blank:]]')

              mem_used=$((memory[0]-memory[2]-memory[3]))
              mem_perc=$(printf "%4.1f\n" "$((10**11 * mem_used/memory[0]))e-9")

            if is_EMPTY_ "${MEM_text}"
            then #               memory bar  
        echo -n  "${label}"
        echo -n  "${GOTO} ${INDENT2}}" #\${voffset 1}"

                width="$((CHARACTER_width1*LINE_length1-(INDENT2)))"
                is_HORIZ_ "${ALIGN}" \
                              && width="60"

        echo -n  "\${color $(color_ "${mem_perc%.*}" "$((100*COLOR))")}"
        echo -n  "\${execbar $((LINE_height1/3)),${width} echo ${mem_perc%.*}}"
                 is_CASCADING_ "${ALIGN}" \
                 && echo

            else #                  text
                is_CASCADING_ "${ALIGN}" \
                   && echo -n  "${label}"
                m_line+="\${color $(color_ "${mem_perc%.*}" "$((100*COLOR))")}"
                m_line+="${mem_perc}%"
                m_line+=" $((mem_used/1024))${COLOR3}/$((memory[0]/1024))"
                m_line+="${FONT_units}${COLOR_units}\${offset 3}MB"

        echo -n  "${GOTO} ${INDENT2}}"
        justify_ "${ALIGN}" \
                 "${m_line}" \
                 "$((LINE_length1-INDENT2/CHARACTER_width1))"
            fi

            if [ "${mem_perc%.*}" -ge  '80' ]
            then # high memory usage, who's the biggest hog
        echo -n "${GOTO} $((INDENT2+10))}${FONT1}\${color red}"
        awk '{printf "%-9s %d %2.1f%% %5.1f Mb %5.1f Mb\n",
                     $1,$2,$3,($4/1024),($5/1024^2)}' < \
           <(/opt/bin/ps -eo comm,ppid,pmem,rss,vsize | /opt/bin/sort -k 3 -n -r | /usr/bin/head -1)
            fi
      ;;

    e)                          # NETWORK SSID #
        if is_NOT_empty_ "${ACTIVE_wifi}"
        then
        heading_ "ESSID:" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

              match="${ACTIVE_wifi}:[[:blank:]][[:digit:]]+[[:blank:]]*([[:digit:]]+)\."

              line="$(bash_REMATCH_ 'connmanctl services' '^\*AR[[:blank:]]([^[:blank:]]+).*w')"
              line+="${COLOR2} $(bash_REMATCH_ /proc/net/wireless "${match}")%"

          echo -n  "${GOTO} ${INDENT2}}${COLOR3}"
          justify_ "${ALIGN}" \
                   "${line}"\
                   "$((LINE_length1-(INDENT2/CHARACTER_width1)))"
        fi
      ;;

    q)                     # Wireless Quality & bitrate #
        if is_NOT_empty_ "${ACTIVE_wifi}"
        then                # TODO need to fiqure out bitrate speed w/o iwconfig
        #heading_ "LINK:" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

            match="${ACTIVE_wifi}:[[:blank:]][[:digit:]]+[[:blank:]]*([[:digit:]]+)\."

            #sq_line="Speed: ${COLOR3}$(:) "
            #sq_line+="\${offset 3}${COLOR2}Quality: ${COLOR3}"
            #sq_line+="$(bash_REMATCH_ /proc/net/wireless "${match}")"
            #sq_line+="${COLOR_units}\${offset 3}%"

        #echo -n  "${GOTO} ${INDENT2}}${VOFFSET} -1}${COLOR2}${FONT2}"
        #justify_ "${ALIGN}" \
                 #"${sq_line}" \
                 #"$((LINE_length2-(INDENT2/CHARACTER_width2)-1))"
        fi
      ;;

    i)                           # LAN ADDRESS #
        if is_NOT_empty_ "${ACTIVE_iface}"
        then match='inet addr:([0-9]+[\.][0-9]+[\.][0-9]+[\.][0-9]+)[[:space:]]'

            if is_NOT_empty_ "${ACTIVE_wifi}" && [[ "${ACTIVE_wifi}" != "${ACTIVE_iface}" ]]
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
        if is_NOT_empty_ "${ACTIVE_iface}"
        then
        heading_ "IP:" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

            # ipinfo.io limits: 1,000 requests/day
              check_IP_data_ "${IP_data}"

            match='ip'
            return='[\"].*[\"](.*)[\"]'

        echo -n  "${GOTO} ${INDENT2}}${COLOR3}"
        justify_ "${ALIGN}" \
                 "$(bash_REMATCH_ "${IP_data}" "${match}${return}")" \
                 "$((LINE_length1-(INDENT2/CHARACTER_width1)))"
        fi
      ;;

    r)                          # NETWORK REGION
        if is_NOT_empty_ "${ACTIVE_iface}"
        then
        heading_ "GEO:" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

              check_IP_data_ "${IP_data}"

            matches=( 'city' 'region' 'country' )
            return='[\"].*[\"](.*)[\"]' # everything between 2nd set of "'s

            for match in "${matches[@]}"
            do  ip_data+=("$(bash_REMATCH_ "${IP_data}" "${match}${return}" )")
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
                && p_u+="\${voffset -2}"
                b=${1}; d=''; s=0; S=(' B' {K,M,G,T,E,P,Y,Z}B)

                while ((b > 1024)); do
                   d="$(printf "%02d" $((((b%1024*100)+(1024/2))/1024)))"
                   b=$((b / 1024))
                   ((s++))
                done
                [[ "${b}" -gt 0 ]] \
                           || { b=1; d=0; s=0; }
                is_EMPTY_ "${d}" && d='0'
                printf "%4d%s%.3s%s" "$b" "." "${d}" "${u}${S[${s}]}${p_u}"
            return 0; }

            # variables for stats
              net_stats="/tmp/net_stats-${ALIGN:0:1}"
              net_time="${net_stats}_time"

            # previous read time or invalidate net_stats
              { is_READABLE_ "${net_time}" \
                && last_TIME=$(<"${net_time}"); } \
                || echo -n "" > "${net_stats}"

            # time interval
              dt=$(interval_ "${last_TIME}" "${net_time}")
              [[ "${dt}" -eq 0 ]] \
                         && dt=1

            # read network rx,tx stats into array
              mapfile -t rawbytes < \
                     <(cat "${net_stats}" 2>/dev/null \
                     <(cat /sys/class/net/"${ACTIVE_iface}"/statistics/{rx,tx}_bytes \
                           | tee "${net_stats}"))

            rxtx=(  $((((rawbytes[2]-rawbytes[0])+(dt/2))/dt)) )
            rxtx+=( $((((rawbytes[3]-rawbytes[1])+(dt/2))/dt)) )

            # to set max upper speed
              speed='/tmp/net-speed'
            # adjust scale for up speed
              hi_up=$(< "${speed}_up") \
                    || hi_up=1000
              [[ "${rxtx[1]}" -gt "${hi_up}" ]] \
                               && echo "${rxtx[1]}">"${speed}_up"
            # adjust scale for down speed
              hi_dn=$(< "${speed}_down") \
                    || hi_dn=1000
              [[ "${rxtx[0]}" -gt "${hi_dn}" ]] \
                               && echo "${rxtx[0]}">"${speed}_down"

            # sublabel for conky (left|right|center) || horiz
              sublabel=( 'Up:' 'Dn:' )
              is_HORIZ_ "${ALIGN}" \
                        && sublabel=( '↑' '↓' )

            s_line+="${COLOR2}${FONT1}${sublabel[0]}"
            s_line+="\${color $(color_ "$((rxtx[1]))" "$((hi_up*COLOR))")}"
            s_line+="$(human_NETSPEED_ "${rxtx[1]}")"
            s_line+="${COLOR2}${FONT1} ${sublabel[1]}"
            s_line+="\${color $(color_ " $((rxtx[0]))" "$((hi_dn*COLOR))")}"
            s_line+="$(human_NETSPEED_ "${rxtx[0]}")"
            is_CASCADING_ "${ALIGN}" \
            && s_line+="\${voffset 1}"

        echo -n  "${GOTO} ${INDENT2}}"
        [[ "${ALIGN}" =~ ^r ]] \
                      && echo -n "\${offset $((HALFSPACE2*2))}"
        justify_ "${ALIGN}" \
                 "${s_line}" \
                 "$((LINE_length1-(INDENT2/CHARACTER_width1)))"
        fi
      ;;

    d)                         # DISK I/O SPEEDS #
        heading_ "DISKS:" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

            function diskstats_() {
              renice -15 $BASHPID
              local align=$1
              local file stats match
                    file=/proc/diskstats
                    stats="/tmp/diskstats-${ALIGN}"
                    bash_match='(^.*sd[a-z] .*|^.*blk0p2.*)'

              is_READABLE_ "${stats}_time" \
                  || { touch "${stats}_time";
                      echo -n "" >  "${stats}"; }

              mv "${stats}" "${stats:0: -1}" 2>/dev/null \
                 || touch "${stats:0: -1}"

              dt=$(interval_ "$(<"${stats}_time")" "${stats}_time")

              (while IFS= read -r a <&3 && IFS= read -r b <&4
               do echo "${a} ${b}"
               done ) 3<"${stats:0: -1}"  4< <(bash_REMATCH_ "${file}" "${bash_match}" 'save') \
               | awk -v dt="${dt}" -v read="${read}" -v write="${write}" -v mb="${mb}" \
                     '{read_start+=$6;read_end+=$20;write_start+=$10;write_end+=$24;i++}
                       END
                      {if (dt > 0 && i >= 2)
                           printf "%8.3f \n%8.3f",
                                  ((read_end-read_start)/dt)*512/1024^2,
                                  ((write_end-write_start)/dt)*512/1024^2;
                       else printf "\n";}'
            }
 
            mapfile -t diskio < <(diskstats_ "${ALIGN}")

            # variables for conky
              offset=0
              [[ "${ALIGN}" =~ ^c ]] \
                            && offset="${CHARACTER_width2}"
              begin="\${offset ${offset}}${COLOR2}${FONT1}"
              write="${begin}W${COLOR3}"
              read="${begin}R${COLOR3}"
              mb="\${offset $((HALFSPACE2*1))}${COLOR_units}${FONT2}"
              mb+="Mb\${offset -2}/\${offset -2}s "
              is_CASCADING_ "${ALIGN}" \
                 && mb+="\${voffset -1}"

        echo -n  "${GOTO} ${INDENT2}}"
        [[ "${ALIGN}" =~ ^r ]] \
                      && echo -n "\${offset $((HALFSPACE2*6))}"
        justify_ "${ALIGN}" \
                 "${read}${diskio[0]}${mb}${write}${diskio[1]}${mb}" \
                 "$((LINE_length1-INDENT2/CHARACTER_width1))"
      ;;

    f)                           # DISK USAGE  #
        heading_ "" "${ALIGN}" "${GOTO}" '0' "${COLOR1}" "${FONT1}" "${SPACING}"
        is_CASCADING_ "${ALIGN}" \
        && { echo -n  "${HR:0:$(((LINE_length1/2-3)*3))}STORAGE";
             echo -n  "\${voffset -1}\${hr}\${voffset $((LINE_height1+4))}"; }

            file="/tmp/filesystem-${ALIGN:0:1}"
            fs_data_age=$(/opt/bin/stat -c %Y "${file}" 2>/dev/null) \
                        || fs_data_age=$((now+FS_dt+1))

            # to shorten the list especially for horizontal format
              skip_target=( "flash" "" )
#              skip_target=( "flash" "NEW_STUFF" "MOVIE+TV" )

            if [[ "$(interval_ "${fs_data_age}" )" -gt "${FS_dt}" \
               || $(is_NOT_file_ "${file}") ]]
            then # read current data and tee to file

                # (width of line in conky 'x') - (location & length of FREE) + space
                  width=$((LINE_length1*CHARACTER_width1-INDENT1-(HALFSPACE1*47)))
                  [[ "${ALIGN}" =~ ^l ]] && width=$((width-HALFSPACE1*5))
                { /opt/bin/df   -lh -x tmpfs -x devtmpfs -x squashfs -x iso9660 \
                                --output=target,avail,used,pcent \
                              | tail -n +2 \
                  | while read -r TARGET AVAIL USED PCENT
                    do
                        target="${TARGET##*/}"
                        [[ " ${skip_target[*]} " =~ " ${target} " ]] \
                                                 && continue
       
                        percent="${PCENT%?}"
                        [[ "${percent}" -lt 1 \
                        || "${percent}" -gt 100 ]] \
                                         && percent=99
       
                        if is_HORIZ_ "${ALIGN}"
                        then # print linear
        echo -n  "\${offset 6}${COLOR1}"
        echo -n  "${target:0:8}"
        echo -n  "\${color $(color_ "$((percent))" "$((100*COLOR))")}"
        echo -n  "\${offset ${HALFSPACE1}}$(printf "%5s" "${AVAIL}") "
                        else # print table
        echo -n  "${GOTO} $((INDENT1+(HALFSPACE1*3)))}${COLOR2}"
        echo -n  "${target:0:15}"
        echo -n  "${GOTO} ${INDENT2}}${COLOR3}"
        echo -n  "$(printf %18s "${AVAIL}")"
        echo -n  "${GOTO} $((INDENT2+19*CHARACTER_width1))}"
        echo -n  "\${color $(color_ "$((percent))" "$((100*COLOR))")}"
        echo -n  "\${execbar ${BAR_height},${width} echo ${percent%.*}}"
        echo -n  "${GOTO} $((INDENT2+18*CHARACTER_width1))}"
        echo -n "\${offset $((width*${percent%.*}/110-HALFSPACE1*3))}"
        echo -n  "\${color $(color_ $((100-${percent%.*})) '100')}$(printf "%4s" "${USED}")"
        echo
                        fi
                     done ## sort on percent remaining
                    } \
                      |  /opt/bin/sort -k "10" \
                      | /usr/bin/head -c -1 \
                      | tee "${file}"
                    ## OR sort on total free space
                    #} \
                      #| /opt/bin/sort --human-numeric-sort -k "6" \
                      #| /usr/bin/head -c -1 \
                      #| tee "${file}"
            else
        printf   "%s" "$(<"${file}")"
            fi

            is_CASCADING_ "${ALIGN}" \
            && echo
      ;;

    p)                            # PROCESSES #
        if is_CASCADING_ "${ALIGN}"
        then
        heading_ "" "${ALIGN}" "${GOTO}" '0' "${COLOR1}" "${FONT1}" "$((SPACING+2))"
        echo -n  "${HR:0:$(((LINE_length1/2-7)*3))}PROCESSES${HR:0:3}"
        echo -n  "[$(bash_REMATCH_ '/proc/stat' 'running ([[:digit:]]+)')]"
        echo     "\${voffset -1}\${hr}\${voffset $((LINE_height1/3))}"

            # allow some expansion for wider viewport
              fudge=$(((LINE_length1-33)/4))
              spacing=( "$((HALFSPACE2*28))" "$((HALFSPACE2*fudge))" "$((HALFSPACE2*fudge))" )

        echo -n  "${GOTO} $((INDENT1+CHARACTER_width2))}\${voffset -2}"
        echo -n  "${COLOR_units}${FONT2}"
        echo -n  "Command"
        echo -n  "\${offset ${spacing[0]}}"
        echo -n  "PID"
        echo -n  "\${offset ${spacing[1]}}"
        echo -n  "     %CPU"
        echo -n  "\${offset ${spacing[2]}}"
        echo     "   %MEM"

            # top in batch mode returns a variable number of lines
              list_pad="$ a\\\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n"

        else # printing horizontally limit # of processes
            NPROCS=1
        fi

            move_to="$((INDENT1+HALFSPACE1*4))"
        echo -n  "${VOFFSET} ${SPACING}}${COLOR3}${FONT1}"
        awk -v indent="${GOTO} ${move_to}}" \
            -v cpu="\${offset ${spacing[1]}}" -v mem="\${offset ${spacing[2]}}" '
            {if ($1 != 0)
                 printf "%s%-14.14s%7d%s%6.1f%%%s%5.1f%%\n",
                      indent,$11,$1,cpu,$7,mem,$8;
              else printf}' < \
           <(/opt/bin/top -bn 2 -d 0.01 -c -o +"${SORT}" \
                          | sed -e '/top/d' \
                          | sed "${list_pad}" \
                          | /usr/bin/tail -n +11 \
                          | /usr/bin/head -n "${NPROCS}")
      ;;

    o)                             # OS INFO #
       if is_CASCADING_ "${ALIGN}"
       then # print lots of superfluose data over 1/10 of a second
            # run script with -o & add output to conkyrc from here to # EOO # 
            # then comment out, because it seems like wasted time
        # Heading
           echo -n  "${GOTO} 0}${COLOR2}${FONT1}"

           echo     "\${alignc}$(bash_REMATCH_ /etc/os-release '^PR.*"(.*+)"') "

              # hardware
          echo -n  "${GOTO} 0}${FONT1}"
          echo "\${alignc}$(bash_REMATCH_ /proc/cpuinfo '^Ha.*:[[:blank:]](.*+)')"

              # model name  
          #echo -n  "${GOTO} 0}${FONT1}"
          #echo "\${alignc}$(bash_REMATCH_ /proc/cpuinfo '^model.*:[[:blank:]](.*+)')"

              UNAME="$(uname -a)"

              # os
          echo -n  "${GOTO} 0}${COLOR1}${FONT2}"
          echo       "\${alignc}${UNAME: -17}"

              # kernel
          echo -n  "${GOTO} 0}${COLOR1}${FONT2}"
          echo     "\${alignc}$(echo "${UNAME:0:37}"|tr '#' d)"
          echo -n  "\${voffset -2}"
          echo     "\${alignc}${COLOR1}${HR:0:117}"
  ## EOO #########################################################################

              # cpu configuration & governor
          echo -n  "${GOTO} ${INDENT2}}\${voffset ${SPACING}}${COLOR1}${FONT2}"
          echo -n  "\${alignc}(${NCORES})"
          echo -n  " cores governer: ${COLOR3}"
          echo     "$(</sys/devices/system/cpu/cpufreq/policy0/scaling_governor)"


              # entropy available
          echo -n  "${GOTO} ${INDENT1}}${COLOR1}${FONT2}"
          echo -n  "\${alignc}${COLOR1}Random:"
          echo -n  "${COLOR2}pool:${COLOR3}"
          echo -n  "$(</proc/sys/kernel/random/poolsize)"
          echo -n  "${COLOR2} available:${COLOR3}"
          echo     "$(</proc/sys/kernel/random/entropy_avail)"

              # roll your own
          #echo -n  "${GOTO} ${INDENT1}}${COLOR1}:"
          #echo     "\${alignc}Something interesting"

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
               && return
            chomp="$2"
            character_width="$3"
            line_height="$4"
            cline_height="${GOTO} $((chomp*character_width-(character_width*2)))}"
            cline_height+="E\${voffset ${line_height}}"
            cline_height+="\${offset -${character_width}}E\${voffset -${line_height}}E"
            a_long_line="123456789112345678921234567893123456789412345678951234567896"
            cline="${a_long_line:0:${chomp}}"
            while read -r num; do l_line+="${num: -1}"; done < <(seq 99)
            cline="${l_line:0:${chomp}}"

          echo -n  "${font}\${color grey90}\${voffset ${SPACING}}"
          echo     " font $( [[ "${font}" =~ t[[:space:]](.*+)} ]] && echo "${BASH_REMATCH[1]}")"
          echo     "${cline}"
          echo     "${cline_height}"
          echo
 } 
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
echo -n "\${voffset $((SPACING*1+3))}${COLOR1}"
echo    "${HR:0:$(((LINE_length1/2-6)*3))}Runtime Stats\${voffset -1}\${hr}"
else
echo -n "${GOTO} $((INDENT1+15))}${COLOR1}"
fi
#
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
awk -v avg="${avg_cpu}" -v ticks="${clock_ticks}" -v uptime="${uptime}" -v ncores="${NCORES}" -v label="${label}" '{total=$14+$15+$16+$17; start_time=$22;}END
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
    h|\?)
#    h)
        _Usage "$@"
     ;;
  esac
  done
          is_HORIZ_ "${ALIGN}" \
             || echo     "\${alignc}${COLOR1}${HR:0:$((LINE_length1*3))}"

  shift $((OPTIND-1))
# Total time for script
echo "\${goto ${INDENT1}}${COLOR2}${FONT_units}COMMAND: MONITOR $((($(/usr/bin/date +%s%N)-tss)/1000000)) ms" | sed -e "s/[\${][^}]*[}]//g" >> "${TIME_log}"
# Trim to ~ last 5 minutes
[ "$( wc -l < "${TIME_log}" )" -gt 50 ] && ( sed -i  -e :a -e '$q;N;50,$D;ba' "${TIME_log}" )&

 exit 0

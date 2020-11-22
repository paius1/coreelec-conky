#!/opt/bin/bash
#   v 0.9.2
#  Outputs CoreELEC OS stats in conky printable format
#  using entware's bash, procps-ng-top, coreutils-sort, net-tools,
#                  coreutils-df, bind-dig
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
#    Get hack font 
#    https://github.com/source-foundry/Hack
#    
#    Ssh login without password
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
#   to determine 'interval' & add the following to your conky config:
#   
#   ${texecpi 'interval' ssh Hostname /path/to/coreelec-conky.sh -[ocltumeqirxsdfp]}
#   
#   add 'UseDNS no' to /storage/.cache/services/sshd.conf on CoreELEC
#   
#   alignment and cpu format can be changed from the command line
#     pass [left|center|right|horiz] for alignment
#     pass [long|longer|longest] for frequency, per core, and a graph
#   
#   to remove all nonindented (debug) lines after this heading
#     sed -i -e '61,$ { /^[^[:blank:]]/d }' /opt/bin/coreelec-conky.sh 
#   
#   
#   
####
# for benchmarking script
tss=$(date +%s%N)

    _Usage() {
       echo >&2 " ${BASH_SOURCE##*/}:" "$@"
       sed >&2 -n "1d; /^###/q; /^#/!q; s/^#*//; s/^ //; 
                   s/SCRIPTNAME/${BASH_SOURCE##*/}/; p" \
                  "${BASH_SOURCE%/*}/${BASH_SOURCE##*/}"
    exit 1;
 }
  [ $# -lt 1 ] && _Usage "$@"

  # Default alignment left: |c[enter]|r[ight]|h[orizontal] can be used as arguments
  # as can long, longer, and longest for cpu output
    ALIGN="left"
  # vertical offset between options
    SPACING=4
  # height of filesystem bar (odd numbers center better)
    BAR_height=5
  # set to show memory stats as text
    MEM_text=1
  # sort "NPROCS" processes on "SORT" (%CPU or %MEM)
    NPROCS=4
    SORT="%CPU"
  # Colorize data 1=colorize 0=monochrome
    COLORIZE=1
  # colors for labels, sublabels,
  #   data, & units
    COLOR1="\${color #06939B}"; COLOR2="\${color #34BDC4}"
      COLOR3="\${color #9FEEF3}"; COLOR_units="\${color grey70}"
  # a monospace font found on computer running conky
  # run fc-list :spacing=100 n.b some balk @ some unicode characters
    font_family="Hack"
    FONT1="\${font ${font_family}:size=9}"
    FONT2="\${font ${font_family}:size=8}"
    FONT_units="\${font ${font_family}:size=7}"
  # use /path/to/coreelec-conky.sh -w  to determine the next 6
  # characters per line:
    LINE_length1=41
    LINE_length2=48
  # relation between spaces & conky goto 'x', & voffset 'x'
    CHARACTER_width1=7
    CHARACTER_width2=6
    LINE_height1=15
    LINE_height2=14
#
# for transmission conky
LINE_length1=49
LINE_length2=57
#
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
#
# pass at least one parameter in conky config & add parameters below for debugging
# once your conky config is set, delete. see note at top on how
if [[ ${#1} -eq 2 && "${1}" != "-h" ]]
then
#
if [[ ! "${ALIGN}" =~ ^h ]]
then # vertical

# change these, when done transfer to conky config
set -- "${@/%/umr}"
#
else # horizontal

set -- "${@/%/ltsdf}"
fi
#
fi
#
#[[ $ALIGN =~ ^h ]] && ALIGN=center
FORMAT=long
#
#
  # add some space to INDENT2 for left justify and misc variables
    [[ "${ALIGN}" =~ ^l ]] && INDENT2=$((INDENT2+HALFSPACE1*5))
    LONG_labels=1; GOTO="goto"; VOFFSET="voffset"
  # changes for horizontal conky
    if [[ "${ALIGN}" =~ ^h ]]
    then # hoizontal keep fonts same, change goto to offset, & drop labels
       GOTO="offset"; VOFFSET="offset"
       FONT2="${FONT1}" FONT_units="${FONT1}"
       LONG_labels=0
       # this becomes the spacing between options
         INDENT2=1
    fi
  # left hr since conky can't define hr width
  # character is unicode, so cut at multiples of 3 e.g. ${HR:0:9}
    while read -r num; do HR+="―"; done < <(seq "$((LINE_length2))")
  # make sure /opt is in path
    PATH=/opt/bin:/opt/sbin:"${PATH}"
     export LC_ALL=C
  # delay for refreshing disk usage to save cpu time
    FS_dt=16
  # the @ character prints below the line
    ASTERISK="\${voffset -1}@\${voffset 1}"
#
# for benchmarking script
TIME_log="/tmp/time-${ALIGN:0:1}"

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

  function COLOR_() { # given current value $1 and max value $2
                      # Return HEX color code from gradient function
                      # if $2 = 0 return $COLOR3 value
      [[ -z "$2" || "$2" = "0" ]]  && { echo "${COLOR3:8:-1}"; return 1; }
      local tailend

      tailend=$((($1*STEPS+($2/2))/$2+1))
      [[ "${tailend#-}" -ge 1 && "${tailend#-}" -lt 38 ]] || tailend=37
      [[ "${tailend#-}" -eq 0 ]] && tailend=1
      tail -n "${tailend#-}" < <(gradient_) | head -1
  return 0
 } 
 export -f COLOR_

  function justify_() { # Pad text ($1) to ALIGN ($2) on line_length ($3)
                        # print newline if !horizontal
      local string length_text padding newline
      string="$2"

      case "${1}" in

          r*|c*) # Pad string to justify
                 # remove any leading & trailing whitespaces
                   string=$(sed -e 's/}[ \t]*/}/' -e 's/^[[:space:]]*//' \
                                -e 's/[[:space:]]*$//' <<< "${2}")

                 # length of string striped of conky formating
                   length_text=$(($(sed -e "s/[\${][^}]*[}]//g" <<< \
                                        "${string}" | wc -c)-1))

                 # check length
                   [[ "${length_text}" -gt "${3}" ]] && 
                    { echo "ln: ${3} < ${length_text}"; return 2; }

                 # spaces to add to beginning of string
                   padding=$(($3-length_text)) # half for center pad
                   [[ "${1}" =~ ^c ]] && padding=$(((padding+2/2)/2+1))

             ;&
          l*)    # Just add newline to printf
                   newline=$'\n'
            ;&
          *)     # print string at width $padding and newline
                 # remove any leading & trailing whitespaces for horizontal
                   string=$(sed -e 's/^[[:space:]]*//' \
                                -e 's/[[:space:]]*$//' <<< "${string}")
                   printf "%$((padding+${#string}))s%s" "${string}" "${newline}"
            ;;

        esac
    return 0
 }
 export -f justify_

  function check_IP_data_() { # Check if ip data file is/recent or create/update
        { [ -r "${1}" ] &&
          [ "$(($(date +%s)-$(stat -c %Y "${1}")))" -le "${CURL_dt}" ]; }  &&
          return 0

      curl -sf -m 2 ipinfo.io/$(dig +short myip.opendns.com @resolver1.opendns.com) > "${1}" || 
           echo -e "{\n\"ip\": \"NO.RE.P.LY\"
           \"city\": \"NO\"
           \"region\": \"PLACE LIKE\"
           \"country\": \"HM\"
           }" > "${1}"
  return 0
 }
 export -f check_IP_data_

  function bash_REMATCH_() { # Return specific data in matching line of file
      local output           # or command output; pass no '(capture)+' to count # of matches
      output="/tmp/${1##*/}-${ALIGN:0:1}"

      if [[ "${1}" =~ (ip|if) ]]
      then # $1 is a command
         while IFS= read -r line; do
            if [[ "${line}" =~ ${2} ]]; then
               echo "${BASH_REMATCH[1]}" | tee -a "${1}"
            fi
         done < <(${1})
      else # $1 is a file
         # clear file to allow using tee append
           echo -n "" > "${output}"
         while IFS= read -r line; do
            if [[ "${line}" =~ ${2} ]]; then
               echo "${BASH_REMATCH[1]}" | tee -a "${output}"
            fi
          done < "${1}"
      fi
  return 0
 }
 export -f bash_REMATCH_

  # heterogenous cpu?
     match='^CPU p[[:alpha:]]+[[:blank:]]*.*0x([[:alnum:]]+)'
     HETEROGENEOUS=$( bash_REMATCH_ /proc/cpuinfo "${match}" | uniq | wc -l)

  # number of cpu cores
    NCORES=$(bash_REMATCH_ /proc/cpuinfo '^processor' | wc -l)

   # outputing network information?
     if [[ "${@}" =~ (e|q|i|r|x|s) ]]
     then 
        # Network interfaces
          match='^d.*[[:space:]]([^[:space:]]+)([[:space:]]*)$'
          ACTIVE_iface=$(bash_REMATCH_ "ip route show" "${match}")
          match='^[[:digit:]]:.*(wlan[[:digit:]]+).*state[[:space:]]UP'
          ACTIVE_wifi=$(bash_REMATCH_ "ip addr" "${match}")
        # file for public ip data
          IP_data="/tmp/network_DATA"
        # delay for curling ipinfo.co (1,000/day is their max)
          CURL_dt=180
     fi

  # possible opt: ocltmueqxirspfdhwv

  while getopts "ocltmueqxirspfdhwv" opt
  do
  case "${opt}" in

    c)                               # CPU #
        # Heading
          echo -n  "\${${GOTO} ${INDENT1}}${COLOR1}${FONT1}"
          # if printing vertically allow change in line spacing
            [[ "${ALIGN}" =~ ^h ]] || echo -n "\${voffset ${SPACING}}"
          # if printing horizontally skip labels
            ((LONG_labels)) && echo -n "CPU:"

        # Get cpu stats

        # variables for bash_REMATCH_
          file='/proc/stat'; match='(^cpu.*)+'
          cpu_stats="/tmp/${file##*/}-${ALIGN:0:1}"

        # if /tmp/stat-? exists then mv to allow for current reading
          mv "${cpu_stats}" "${cpu_stats:0: -1}" 2>/dev/null ||
                  touch "${cpu_stats:0: -1}"

        # read previous & current cpu stats 
          mapfile -t cpu_usage 2>/dev/null < \
                 <(cat "${cpu_stats:0: -1}"  2>/dev/null \
                 <(bash_REMATCH_ "${file}" "${match}" ))

        # calculate cpu usage since last run
          mapfile -t pcpu < \
                 <(for ((core=0;core<="${NCORES}";core++))
                   do
                      awk '{S13+=$13;S2+=$2;S15+=$15;S4+=$4;S16+=$16;S5+=$5}END
                           {printf "%6.1f\n",
                            (S13-S2+S15-S4)*100/(S13-S2+S15-S4+S16-S5);}' < \
                          <(printf '%s %s\n' \
                            "${cpu_usage[$core]}" "${cpu_usage[$((core+NCORES+1))]}")
                   done)

        case "$FORMAT" in # How much data to print

          *st) # Add cpu graph (pass longest to script)

              if [[ ! "${ALIGN}" =~ ^h ]]
              then
          echo -n  "\${goto ${INDENT1}}"
          echo -n  "\${voffset $((LINE_height1*1+LINE_height2*1+(SPACING*1)))}"
          echo -n  "${FONT2}"
                 h="$((LINE_height1*2))"
                 w="$(((LINE_length1*CHARACTER_width1-INDENT1)))"
          echo -n  "\${execgraph \" echo ${pcpu[0]%.*} \" ${h},${w} 00FF00 FF0000 -t }"

                 # return to CPU: line
          echo -n  "\${voffset -$((LINE_height1*1+LINE_height2+(SPACING*1)))}"
                   skip=$((LINE_height1*1+LINE_height2*3))
              else # horizontal conky
                 height="$((9*1))"
                 width="$(((CHARACTER_width1*8)))"
          echo -n  "\${execgraph \"echo ${pcpu[0]%.*}\" ${height},${width} 00FF00 FF0000 -t }"
              fi
                 ;&
          *r) # Print per core percentages (pass longer to script)

                 # skip color gradient to save time
                   oCOLORIZE=$COLORIZE; COLORIZE=0

                 [[ "${ALIGN}" =~ ^h ]] ||
          echo -n "\${${GOTO} 0}\${voffset $((LINE_height1))}${FONT2}"

              case "${HETEROGENEOUS}" in
                2) # print per core in big.Little order
                     CORES=" 3 4 5 6 1 2 "
          justify_ "${ALIGN}" \
                   "$(for core in $(echo "${CORES}")
                      do 
                        echo -n "\${color $(COLOR_ "${pcpu[$core]%.*}" "$((100*COLORIZE))")}"
                        echo -n "$(printf '%6.1f' "${pcpu[$core]}")"
                        echo -n "${COLOR_units}\${offset 2}%\${color}"
                      done)" \
                   "$((LINE_length2-2))"
                  ;;
                *) # OR cores in numeric order
          justify_ "${ALIGN}" \
                   "$(for core in $(seq "${NCORES}")
                      do 
                        echo -n "\${color $(COLOR_ "${pcpu[$core]%.*}" "$((100*COLORIZE))")}"
                        echo -n "${pcpu[$core]}"
                        echo -n "${COLOR_units}\${offset 2}%\${color}"
                      done)" \
                   "$((LINE_length2-2))"
                  ;;
              esac

              if [[ ! "${ALIGN}" =~ ^h ]]
              then # return to previous line
          echo -n  "\${voffset -$((LINE_height1*1+LINE_height2))}"
                 [[ "${FORMAT}" =~ ^longes ]] && 
                   echo -n "\${voffset -$((LINE_height1*2))}"
                 ((skip)) || skip=$((LINE_height1*1))
              fi

                 # return to color scheme
                   [ "${oCOLORIZE+x}" ] && COLORIZE="${oCOLORIZE}"
             ;&
          l*) # Print frequencies, % for big.LITTLE as well (pass long to script)

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
                         do
                           printf '%s %s\n' "${cpu_usage[$core]}" "${cpu_usage[$((core+NCORES+1))]}"
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
                     l_string+="\${color $(COLOR_ "${big_perc%.*}" "$((100*COLORIZE))")}"
                     l_string+="${big_perc}"
                     l_string+="\${offset ${HALFSPACE2}}${COLOR_units}%"
                     l_string+="\${offset ${HALFSPACE2}}${ASTERISK}"
                     l_string+="\${offset -${CHARACTER_width2}}"
                     l_string+="\${color $(COLOR_ "$((fqz[3]-fqz[5]))" "$(((fqz[4]-fqz[5])*COLORIZE))")}"
                     l_string+="$(human_FREQUENCY_ "${fqz[3]}")"
                     l_string+="\${offset ${HALFSPACE2}}\${${VOFFSET} -1}"
                     l_string+="\${color $(COLOR_ "${LITTLE_perc%.*}" "$((100*COLORIZE))")}"
                     l_string+="${FONT2}${LITTLE_perc}"
                     l_string+="\${offset 2}${COLOR_units}%\${offset 2}"
                  ;;
                *) # homogeneous cpu, position current frequency after cpu%
                    [ "${ALIGN}" = "right" ] && move_to="$((HALFSPACE1*6))"
                  ;;
              esac

              # add frequency for only/'LITLE' cores
                l_string+="${ASTERISK}"
                l_string+="\${offset -${CHARACTER_width1}}"
                l_string+="\${color $(COLOR_ "$((fqz[0]-fqz[2]))" "$(((fqz[1]-fqz[2])*COLORIZE))")}"
                l_string+="$(human_FREQUENCY_ "${fqz[0]}")"

              if [[ ! "${ALIGN}" =~ ^h ]]
              then # adjust for differing font sizes & unmeasured offsets
                 case "${ALIGN}" in
                   c*) move_to="$((HALFSPACE1*8))";;
                   r*) move_to="$((HALFSPACE1*10))";;
                   *)  move_to="$((INDENT2-CHARACTER_width1*2))";;
                 esac
               fi

               ((skip)) || skip="$((SPACING*1))"
            ;&
          *) # print overall percentage

              if [[ ! "${ALIGN}" =~ ^h && -z "${move_to}" ]]
              then
                 case "${ALIGN}" in
                   c*) move_to="$((HALFSPACE1*9))";;
                   r*) move_to='0';;
                   *)  move_to="$((INDENT2*1-CHARACTER_width1))";;
                 esac
              else
                 [[ "${ALIGN}" =~ ^h ]] && move_to="$((CHARACTER_width1*2))"
              fi

              c_line+="\${color $(COLOR_ "${pcpu[0]%.*}" "$((100*COLORIZE))")}"
              c_line+="${pcpu[0]}"
              c_line+="\${offset 1}${COLOR_units}%"

          echo -n  "\${${GOTO} ${move_to}}${FONT1}"
          justify_ "${ALIGN}" \
                   "${c_line}${l_string}" \
                   "${LINE_length1}"

              if [[ ! "${ALIGN}" =~ ^h ]]
              then # move to next line
                 ((skip)) || skip=0
          echo -n  "\${voffset ${skip}}"
              else
          echo -n "\${offset 5}"
              fi
            ;;
        esac

              # print iowait and softirq for case: longe* or high cpu usage
                if [[ "${FORMAT}" =~ ^longe || "${pcpu[0]%.*}" -gt 70 ]]
                then
          echo -n "${FONT2}${COLOR1}"
          awk '{start=($2+$3+$4+$5+$6+$7+$8+$9+$10);
                end=($13+$14+$15+$16+$17+$18+$19+$20+$21);
                iowStart=($6);iowEnd=($17);
                sirqStart=($8);sirqEND=($19)}END
               {printf "\${alignc}iowait: %6.4f%%  softirq: %6.4f%%",
                        (iowEnd-iowStart)*100/(end-start),
                        (sirqEND-sirqStart)*100/(end-start);}'  < \
             <(printf "%s %s\n" "${cpu_usage[0]}" "${cpu_usage[$((NCORES+1))]}")
                [[ ! "${ALIGN}" =~ ^h ]] && echo
                fi
      ;;

    l)                             # LOADAVG #
        # Heading
          echo -n  "\${${GOTO} ${INDENT1}}${COLOR1}${FONT1}"
          [[ "${ALIGN}" =~ ^h ]] || echo -n "\${voffset ${SPACING}}"
          ((LONG_labels)) && echo -n "LOAD:"

              mapfile -d' '  loadavg < /proc/loadavg

              for avg in {0..2}; do
                 case "${loadavg[${avg}]}" in
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

          echo -n  "\${${GOTO} $((INDENT2+0))}"
          justify_ "${ALIGN}" \
                   "${a_line}" \
                   "$((LINE_length1-INDENT2/CHARACTER_width1))"

              if [[ "${loadavg[0]%.*}" -ge 5 ]]
              then # high load average can mean blocked processess
                   # can't use bash_REMATCH_ it overwrites /tmp/stat-
                 pat='^procs_([^[:blank:]]*[[:blank:]]*[[:digit:]]*)+'
                 mapfile -t procs < \
                        <( while IFS= read -r line; do
                              { [[ "${line}" =~ $pat ]] && printf ' %s' "${BASH_REMATCH[1]}"; }
                           done < /proc/stat)
          echo -n  "\${${GOTO} ${INDENT2}}\${color #ff3200}"
          echo -n  "${procs[0]} ${procs[1]}"
          [[ ! "${ALIGN}" =~ ^h ]] && echo
              fi
      ;;

    t)                           # TEMPERATURES #
        # Heading
          echo -n  "\${${GOTO} ${INDENT1}}${COLOR1}${FONT1}"
          [[ "${ALIGN}" =~ ^h ]] || echo -n "\${voffset ${SPACING}}"
          ((LONG_labels)) && echo -n "TEMP:"

              # hot for the cpu/ram
                hot=60

              # names for thermal zones ( note the space before element 1 )
                zones=('Cpu:' ' Mem:')
                [[ "${ALIGN}" =~ ^h ]] && zones=('C:' ' M:')

              # read all zones
                mapfile -t temps 2>/dev/null < \
                       <( cat /sys/class/thermal/thermal_zone*/temp)

              # unicode character ° throws off justify function
                case "${ALIGN}" in
                  c*|r*) right=2;;
                  *)     right=0;;
                esac

              for temp in $(seq "${#temps[@]}"); do
                 case "${temps[$((temp-1))]}" in
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
              do
                 t_line+="${COLOR2}${zones[$zone]} "
                 t_line+="\${color ${temp_color[${zone}]}}"
                 t_line+="$((temp/1000)).${temp:2:1}"
                 t_line+="${COLOR_units}°C${COLOR2}"
                 ((zone++))
              done

          echo -n  "\${${GOTO} $((INDENT2))}${COLOR2}"
          justify_ "${ALIGN}" \
                   "${t_line}" \
                   "$((LINE_length1-INDENT2/CHARACTER_width1+right))"

              if [[ "$((((temps[0]+(1000/2))/1000)))" -ge "${hot}" ]]
              then # Hi temp what process is using most cpu
          [[ ! "${ALIGN}" =~ ^h ]] && echo -n  "\${voffset ${SPACING}}"
          echo -n  "\${color #ff3200}${FONT1}"
          awk -v indent="\${${GOTO} $((INDENT2+0))}" '
              {if ($1) printf "%s%-10s%7d%6.1f%%%6.1f%%",indent,$11,$1,$7,$8;
               else printf $2}' < <(top -bn 1 -d 0.01 -c -o +"${SORT}" | 
               sed -e '/top/d' | tail -n +11 | head -1)
          [[ ! "${ALIGN}" =~ ^h ]] && echo
              fi
      ;;

    u)                             # UPTIME #
        # Heading
          echo -n  "\${${GOTO} ${INDENT1}}${COLOR1}${FONT1}"
          [[ "${ALIGN}" =~ ^h ]] || echo -n "\${voffset ${SPACING}}"
          ((LONG_labels)) && echo -n "UP:"

              # shorten units for horizontal
                u=( " days" " hrs" " mins" )
                [[ "${ALIGN}" =~ ^h ]] && u=( "d" "h" "m" )

          echo -n  "\${${GOTO} ${INDENT2}}${COLOR3}"
          justify_ "${ALIGN}" \
                   "$(awk -v d="${u[0]}" -v h="${u[1]}" -v m="${u[2]}" \
                          -F"[ |.]+" '{secs=$1;}END
                          {printf "%2d%s %2d%s %2d%s",
                           secs/86400,d,secs%86400/3600,h,secs%3600/60,m;}' \
                      /proc/uptime)" \
                   "$((LINE_length1-INDENT2/CHARACTER_width1))"
      ;;

    m)                             # MEMORY #
        # Heading
          echo -n  "\${${GOTO} ${INDENT1}}${COLOR1}${FONT1}"
          [[ "${ALIGN}" =~ ^h ]] || echo -n "\${voffset ${SPACING}}"

              mapfile -d' ' -t memory < \
                     <(awk 'NR==2{total=$2;used=$3}END
                            {printf "%d %d %2.1f",used,total,(used/total)*100}' < \
                          <(free -m))

              if [ -z "${MEM_text}" ]
              then #            memory bar  
          echo -n  "MEM:"
          echo -n  "\${${GOTO} ${INDENT2}}\${voffset 1}"

                 width="$((CHARACTER_width1*LINE_length1-(INDENT2)))"
                 [[ "${ALIGN}" =~ ^h ]] && width="60"

          echo -n  "\${color $(COLOR_ "${memory[2]%.*}" "$((100*COLORIZE))")}"
          echo -n  "\${execbar ${BAR_height},${width} echo ${memory[2]%.*}}"
                   [[ ! "${ALIGN}" =~ ^h ]] && echo
              else #                text
                 ((LONG_labels)) && echo -n  "MEM:"
                 m_line+="\${color $(COLOR_ "${memory[2]%.*}" "$((100*COLORIZE))")}"
                 m_line+="${memory[2]}% ${memory[0]}${COLOR3}/${memory[1]}"
                 m_line+="${FONT_units}${COLOR_units}\${offset 3}MB"

          echo -n  "\${${GOTO} ${INDENT2}}"
          justify_ "${ALIGN}" \
                   "${m_line}" \
                   "$((LINE_length1-INDENT2/CHARACTER_width1))"
              fi

              if [ "${memory[2]%.*}" -ge  '80' ]
              then # high memory usage who's the biggest hog
          echo -n "\${${GOTO} $((INDENT2+10))}${FONT1}\${color red}"
          awk '{printf "%-9s %d %2.1f%% %5.1f Mb %5.1f Mb\n",
                       $1,$2,$3,($4/1024),($5/1024^2)}' < \
             <(ps -eo comm,ppid,pmem,rss,vsize | sort -k 3 -n -r | head -1)
              fi
      ;;

    e)  if [ ! -z "${ACTIVE_wifi}" ] # NETWORK SSID
        then
        # Heading
          echo -n  "\${${GOTO} ${INDENT1}}${COLOR1}${FONT1}"
          [[ "${ALIGN}" =~ ^h ]] || echo -n "\${voffset ${SPACING}}"
          ((LONG_labels)) && echo -n "SSID:"

          echo -n  "\${${GOTO} ${INDENT2}}${COLOR3}"
          justify_ "${ALIGN}" \
                   "$(connmanctl services | awk '/AR.*wifi/ {print $2}')"\
                   "$((LINE_length1-(INDENT2/CHARACTER_width1)))"
        fi
      ;;

    q)  if [ ! -z "${ACTIVE_wifi}" ] # Wireless Quality & bitrate
        then
        # Heading
          echo -n  "\${${GOTO} ${INDENT1}}${COLOR1}${FONT1}"
          [[ "${ALIGN}" =~ ^h ]] || echo -n "\${voffset ${SPACING}}"
          ((LONG_labels)) && echo -n "LINK:"

              match="${ACTIVE_wifi}:[[:blank:]][[:digit:]]+[[:blank:]]*([[:digit:]]+)\."

 # need to fiqure out Speed w/o iwconfig

              sq_line="Speed: ${COLOR3}$(:) "
              sq_line+="\${offset 3}${COLOR2}Quality: ${COLOR3}"
              sq_line+="$(bash_REMATCH_ /proc/net/wireless "${match}")"
              sq_line+="${COLOR_units}\${offset 3}%"

          echo -n  "\${${GOTO} ${INDENT2}}\${${VOFFSET} -1}${COLOR2}${FONT2}"
          justify_ "${ALIGN}" \
                   "${sq_line}" \
                   "$((LINE_length2-(INDENT2/CHARACTER_width2)-1))"
        fi
      ;;

    i)  if [ ! -z "${ACTIVE_iface}" ] # LAN ADDRESS
        then
           match='inet addr:([0-9]+[\.][0-9]+[\.][0-9]+[\.][0-9]+)[[:space:]]'
           if [[ ! -z "${ACTIVE_wifi}" && "${ACTIVE_iface}" != "${ACTIVE_wifi}" ]]
           then
        # Heading
          echo -n  "\${${GOTO} ${INDENT1}}${COLOR1}${FONT1}"
          [[ "${ALIGN}" =~ ^h ]] || echo -n "\${voffset ${SPACING}}"
          echo -n  "${ACTIVE_wifi}:"

          echo -n  "\${${GOTO} ${INDENT2}}${COLOR3}"
          justify_ "${ALIGN}" \
                   "$(bash_REMATCH_ "ifconfig ${ACTIVE_wifi}" "${match}")" \
                   "$((LINE_length1-(INDENT2/CHARACTER_width1)))"
           fi

        # Heading
          echo -n  "\${${GOTO} ${INDENT1}}${COLOR1}${FONT1}"
          [[ "${ALIGN}" =~ ^h ]] || echo -n "\${voffset ${SPACING}}"
          echo -n  "${ACTIVE_iface}:"

          echo -n  "\${${GOTO} ${INDENT2}}${COLOR3}"
          justify_ "${ALIGN}" \
                   "$(bash_REMATCH_ "ifconfig ${ACTIVE_iface}" "${match}")" \
                   "$((LINE_length1-(INDENT2/CHARACTER_width1)))"
        fi
      ;;

    x)  if [ ! -z "${ACTIVE_iface}" ] # PUBLIC IP ADDRESS
        then
        # Heading
          echo -n  "\${${GOTO} ${INDENT1}}${COLOR1}${FONT1}"
          [[ "${ALIGN}" =~ ^h ]] || echo -n "\${voffset ${SPACING}}"
          ((LONG_labels)) && echo -n "IP:"

              # ipinfo.io limits: 1,000 requests/day
                check_IP_data_ "${IP_data}"
  
              return='[\"].*[\"](.*)[\"]'
          echo -n  "\${${GOTO} ${INDENT2}}${COLOR3}"
          justify_ "${ALIGN}" \
                   "$(bash_REMATCH_ "${IP_data}" "ip${return}")" \
                   "$((LINE_length1-(INDENT2/CHARACTER_width1)))"
        fi
      ;;

    r)  if [ ! -z "${ACTIVE_iface}" ] # NETWORK REGION
        then
        # Heading
          echo -n  "\${${GOTO} ${INDENT1}}${COLOR1}${FONT1}"
          [[ "${ALIGN}" =~ ^h ]] || echo -n "\${voffset ${SPACING}}"
          ((LONG_labels)) && echo -n "GEO:"

                check_IP_data_ "${IP_data}"

              return='[\"].*[\"](.*)[\"]' # everything between 2nd set of "'s following match
              city=$(bash_REMATCH_ "${IP_data}" "city${return}" )
              region=$(bash_REMATCH_ "${IP_data}" "region${return}" )
              country=$(bash_REMATCH_ "${IP_data}" "country${return}" )

          echo -n  "\${${GOTO} ${INDENT2}}${COLOR3}"
          justify_ "${ALIGN}" \
                   "${city:0:18}, ${region:0:12} ${country:0:3}" \
                   "$((LINE_length1-(INDENT2/CHARACTER_width1)))"
        fi   
      ;;

    s)  if [ ! -z "${ACTIVE_iface}" ] # NETWORK RX/TX SPEED
        then
        # Heading
          echo -n  "\${${GOTO} ${INDENT1}}${COLOR1}${FONT1}"
          [[ "${ALIGN}" =~ ^h ]] || echo -n "\${voffset ${SPACING}}"
          ((LONG_labels)) && echo -n "${ACTIVE_iface}:"

              function human_NETSPEED_() { # https://askubuntu.com/users/307523/wineunuuchs2unix
                  local u p_u b d s 
                  u="\${offset ${HALFSPACE2}}${COLOR_units}${FONT_units}"
                  p_u="\${offset -1}/\${offset -1}s"
                  [[ ! "${ALIGN}" =~ ^h ]] && p_u+="\${voffset -2}"
                  b=${1}; d=''; s=0; S=(B {K,M,G,T,E,P,Y,Z}B)

                  while ((b > 1024)); do
                     d="$(printf "%02d" $((((b%1024*100)+(1024/2))/1024)))"
                     b=$((b / 1024))
                     ((s++))
                  done
                  [[ "${b}" -gt 0 ]] || { b=1; d=0; s=0; }
                  printf "%4d%s%.3s%s" "$b" "." "${d}" "${u}${S[${s}]}${p_u}"
              return 0; }
 
              # variables for cat
                net_stats="/tmp/net_stats-${ALIGN:0:1}"
                net_time="${net_stats}_time"

              # previous read time or invalidate net_stats
                { [ -r "${net_time}" ] && last_TIME=$(<"${net_time}"); } ||
                       echo -n "" > "${net_stats}"

                now=$(date +%s | tee "${net_time}")
              # time interval
                dt=$((now-last_TIME)); [[ "${dt}" -eq 0 ]] && dt=1

              # read network rx,tx stats into array
                mapfile -t rawbytes < \
                       <(cat "${net_stats}" 2>/dev/null \
                       <(cat  /sys/class/net/"${ACTIVE_iface}"/statistics/{rx,tx}_bytes |
                       tee "${net_stats}"))

              rxtx=(  $((((rawbytes[2]-rawbytes[0])+(dt/2))/dt)) )
              rxtx+=( $((((rawbytes[3]-rawbytes[1])+(dt/2))/dt)) )

              # to set max upper speed
                net_up=/tmp/net_up net_down=/tmp/net_down
              # adjust scale for up speed
                hi_up=$(< "${net_up}") || hi_up=1000
                [[ "${rxtx[1]}" -gt "${hi_up}" ]] && echo "${rxtx[1]}">"${net_up}"
              # adjust scale for down speed
                hi_dn=$(< "${net_down}") || hi_dn=1000
                [[ "${rxtx[0]}" -gt "${hi_dn}" ]] && echo "${rxtx[0]}">"${net_down}"

              # sublabel for conky (left|right|center) || horiz
                sublabel=( 'Up:' 'Dn:' )
                [[ "${ALIGN}" =~ ^h ]] && sublabel=( '↑' '↓' )

              s_line+="${COLOR2}${FONT1}${sublabel[0]}"
              s_line+="\${color $(COLOR_ "$((rxtx[1]))" "$((hi_up*COLORIZE))")}"
              s_line+="$(human_NETSPEED_ "${rxtx[1]}")"
              s_line+="${COLOR2}${FONT1} ${sublabel[1]}"
              s_line+="\${color $(COLOR_ " $((rxtx[0]))" "$((hi_dn*COLORIZE))")}"
              s_line+="$(human_NETSPEED_ "${rxtx[0]}")"
              [[ ! "${ALIGN}" =~ ^h ]] && s_line+="\${voffset 1}"

          echo -n  "\${${GOTO} ${INDENT2}}"
            [[ "${ALIGN}" =~ ^r ]] &&
          echo -n "\${offset $((HALFSPACE2*2))}"
          justify_ "${ALIGN}" \
                   "${s_line}" \
                   "$((LINE_length1-(INDENT2/CHARACTER_width1)))"
        fi
      ;;

    d)                         # DISK I/O SPEEDS #
        # Heading
          echo -n  "\${${GOTO} ${INDENT1}}${COLOR1}${FONT1}"
          [[ "${ALIGN}" =~ ^h ]] || echo -n "\${voffset ${SPACING}}"
          ((LONG_labels)) && echo -n  "DISKS:"

              # variables for bash_REMATCH
                file=/proc/diskstats
                diskstats="/tmp/${file##*/}-${ALIGN:0:1}"
                match='(^.*sd[a-z] .*|^.*blk0p2.*)'
                diskstats_time="${diskstats}_time"

              # variables for conky
                offset=0; [[ "${ALIGN}" =~ ^c ]] && offset="${CHARACTER_width2}"
                read="\${offset ${offset}}${COLOR2}${FONT1}"
                write="${read}W${COLOR3}"
                read+="R${COLOR3}"
                mb="\${offset $((HALFSPACE2*1))}${COLOR_units}${FONT2}"
                mb+="Mb\${offset -2}/\${offset -2}s "
                # font size change
                  [[ ! "${ALIGN}" =~ ^h ]] && mb+="\${voffset -1}"

              # previous read time or invalidate diskstats
                { [ -r "${diskstats_time}" ] && 
                   last_TIME=$(<"${diskstats_time}"); } || 
                     rm "${diskstats}" 2>/dev/null

              # if /tmp/diskstats exists then mv to allow for current reading
                mv "${diskstats}" "${diskstats:0: -1}" 2>/dev/null ||
                  touch "${diskstats:0: -1}"

                now=$( date +%s | tee "${diskstats_time}")
              # time interval
                dt=$((now-last_TIME))

          echo -n  "\${${GOTO} ${INDENT2}}"
            [[ "${ALIGN}" =~ ^r ]] &&
          echo -n "\${offset $((HALFSPACE2*6))}"
          justify_ "${ALIGN}" \
                   "$( (while IFS= read -r a <&3 && IFS= read -r b <&4
                        do
                           echo "${a} ${b}"
                        done) 3<"${diskstats:0: -1}" \
                             4< <(bash_REMATCH_ "${file}" "${match}") |
                      awk -v dt="${dt}" -v read="${read}" -v write="${write}" -v mb="${mb}" '
                      {read_start+=$6;read_end+=$20;write_start+=$10;write_end+=$24;i++}
                      END
                      {if (dt > 0 && i >= 2)printf "%s%8.3f%s%s%8.3f%s",
                       read,((read_end-read_start)/dt)*512/1024^2,mb,
                       write,((write_end-write_start)/dt)*512/1024^2,mb;
                       else printf "\n";}')" \
                   "$((LINE_length1-INDENT2/CHARACTER_width1))"
      ;;

    f)                           # DISK USAGE  #
        # Heading
          echo -n  "\${${GOTO} 0}${COLOR1}${FONT1}"
          [[ "${ALIGN}" =~ ^h ]] || { echo -n "\${voffset $((SPACING+2))}";
          echo -n  "${HR:0:$(((LINE_length1/2-3)*3))}STORAGE";
          echo -n  "\${voffset -1}\${hr}\${voffset $((LINE_height1+4))}"; }

              file="/tmp/filesystem-${ALIGN:0:1}"
              now=$( date +%s )
              fs_data_age=$(stat -c %Y "${file}" 2>/dev/null) ||
                fs_data_age=$((now+FS_dt+1))

              # to shorten the list especially for horizontal format
                skip_fs=( "flash" "" )
skip_fs=( "flash" "150G-Storage" "NEW_STUFF"  )

        if [[ "$((now-fs_data_age))" -gt "${FS_dt}" || ! -f "${file}" ]]
        then # read current data and write to file

              # width of line in conky 'x' - location & length of FREE + space
                width=$((LINE_length1*CHARACTER_width1-INDENT1-(HALFSPACE1*47)))

           {  df -lh | /usr/bin/grep -E '^/dev/[s|m]' | 
              while read -r DEVICE SIZE USED FREE USE MOUNT
              do
                 filesystem="${MOUNT##*/}"
                 [[ " ${skip_fs[*]} " =~ " ${filesystem} " ]] && continue

                 percent="${USE%?}"
                 [[ "${percent}" -lt 1 || "${percent}" -gt 100 ]] && percent=100

               # short filesystem name percent free, colored coded bar &
                 if [[ ! "${ALIGN}" =~ ^h ]]
                 then # print a table
          echo -n  "\${goto $((INDENT1+(HALFSPACE1*3)))}${COLOR2}"
          echo -n  "${filesystem:0:15}"
          echo -n  "\${goto ${INDENT2}}${COLOR3}"
          echo -n  "$(printf %18s "${FREE}") "
          echo -n  "\${goto $((INDENT2+19*CHARACTER_width1))}"
          echo -n  "\${color $(COLOR_ "$((percent))" "$((100*COLORIZE))")}"
          echo -n  "\${execbar ${BAR_height},${width} echo ${percent%.*}}"
                    # filesystem size
          echo -n  "\${goto $((LINE_length1*CHARACTER_width1-HALFSPACE1*17))}"
          echo -n  "\${color white}$(printf "%5s" "${SIZE}")"
          echo
                 else # ALIGN =~ ^h print in a line & trim names to fit
          echo -n  "\${offset 5}${COLOR1}"
          echo -n  "${filesystem:0:8}"
          echo -n  "\${color $(COLOR_ "$((percent))" "$((100*COLORIZE))")}"
          echo -n  "\${offset ${HALFSPACE1}}$(printf "%5s" "${FREE}") "
                 fi
              done # sort on percent remaining
           } |  sort -k "10" | head -c -1 | tee "${file}"
              # OR sort on total free space
           #} | sort --human-numeric-sort -k "6" | head -c -1 | tee "${file}"
           [[ ! "${ALIGN}" =~ ^h ]] && echo
        else
          printf   "%s" "$(<"${file}")"
          [[ "${ALIGN}" =~ ^h ]] || echo
        fi
      ;;

    p)                            # PROCESSES #
        # Heading
          if [[ ! "${ALIGN}" =~ ^h ]]
          then
             match='running[[:blank:]]([[:digit:]]+)'
          echo -n  "\${${GOTO} 0}${COLOR1}${FONT1}\${voffset $((SPACING+2))}"
          echo -n  "${HR:0:$(((LINE_length1/2-7)*3))}"
          echo -n  "PROCESSES${HR:0:3}"
          echo -n  "[$(while IFS= read -r line; do
                         { [[ "${line}" =~ $match ]] &&
                           printf '%s' "${BASH_REMATCH[1]}"; }
                       done < /proc/stat)]"
          echo     "\${voffset -1}\${hr}\${voffset $((LINE_height1/3))}"

              spacing=( '28' '9' '9' )
              move_to="$((INDENT1+HALFSPACE1*4))"

          echo -n  "\${goto $((move_to-CHARACTER_width2))}\${voffset -2}"
          echo -n  "${COLOR_units}${FONT2}"
          echo -n  "Command"
          echo -n  "\${offset $((HALFSPACE2*spacing[0]))}"
          echo -n  "PID"
          echo -n  "\${offset $((HALFSPACE2*spacing[1]))}"
          echo -n  "%CPU"
          echo -n  "\${offset $((HALFSPACE2*spacing[2]))}"
          echo     "%MEM"

              # top in batch mode returns a variable number of lines
                list_pad="$ a\\\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n"

          else # printing horizontally limit # of processes
              NPROCS=1
          fi

          echo -n  "\${${VOFFSET} ${SPACING}}${COLOR3}${FONT1}"
          awk -v indent="\${${GOTO} ${move_to}}" '
              {if ($1 != 0) printf "%s%-15s%6d%6.1f%%%6.1f%%\n",
                  indent, $11,$1, $7 , $8;
               else printf}' < \
             <(top -bn 2 -d 0.01 -c -o +"${SORT}" | 
               sed -e '/top/d' | sed "${list_pad}" |
               tail -n +11 | head -n "${NPROCS}")
      ;;

    o)                             # OS INFO #
       if [[ ! "${ALIGN}" =~ ^h ]]
       then # print lots of superfluose data if not outputing horizontally
            # run script with -o & add output to conkyrc from here to # EOO # 
            # then comment out, because it seems like wasted time
        # Heading
           echo -n  "\${${GOTO} 0}${COLOR2}${FONT1}"

           echo     "\${alignc}$(grep -F "PRETTY" /etc/os-release |
                                  cut -d'"' -f2 | sed -e s'/(/[/' -e s'/)/]/' ) "

              # hardware
                match='^Ha.*:[[:blank:]](.*+)'
          echo -n  "\${goto 0}${FONT1}"
          echo "\${alignc}$(bash_REMATCH_ /proc/cpuinfo "${match}")"

              # model name  
                match='^model.*:[[:blank:]](.*+)'
          echo -n  "\${goto 0}${FONT1}"
          echo "\${alignc}$(bash_REMATCH_ /proc/cpuinfo "${match}")"

              mapfile UNAME 2>/dev/null < <(uname -a)

              # os
          echo -n  "\${goto 0}${COLOR1}${FONT2}"
          echo     "\${alignc}$(cut -d' ' -f13,14 <<< "${UNAME[@]}")"

              # kernel
          echo -n  "\${goto 0}${COLOR1}${FONT2}"
          echo     "\${alignc}$(cut -c -37 <<< "${UNAME[@]}"| tr '#' -d)"
          echo -n  "\${voffset -2}"

          echo     "\${alignc}${COLOR1}${HR:0:$(($(cut -c -37 <<< "${UNAME[@]}"|
                                                    tr '#' d | wc -c)*3))}\${voffset -2}"
  ## EOO #########################################################################

              # cpu configuration & governor
          echo -n  "\${goto ${INDENT2}}\${voffset ${SPACING}}${COLOR1}${FONT2}"
          echo -n  "\${alignc}(${NCORES})"
          echo -n  " cores governer: ${COLOR3}"
          echo     "$(</sys/devices/system/cpu/cpufreq/policy0/scaling_governor)"


              # entropy available
          echo -n  "\${goto ${INDENT1}}${COLOR1}${FONT2}"
          echo -n  "\${alignc}${COLOR1}Random:"
          echo -n  "${COLOR2}pool:${COLOR3}"
          echo -n  "$(</proc/sys/kernel/random/poolsize)"
          echo -n  "${COLOR2} available:${COLOR3}"
          echo     "$(</proc/sys/kernel/random/entropy_avail)"

              # roll your own
          #echo -n  "\${goto ${INDENT1}}${COLOR1}:"
          #echo     "\${alignc}Something interesting"

          echo     "\${voffset -3}${COLOR1}\${hr 1}"

        else # outputting horizontally
          echo -n  "\${${GOTO} ${INDENT1}}${COLOR1}${FONT1}Gvn: "
          echo -n  "${COLOR2}"
          echo -n  "$(</sys/devices/system/cpu/cpufreq/policy0/scaling_governor)"
          echo -n  "\${${GOTO} ${INDENT1}}${COLOR1}Rnd: "
          echo -n  "${COLOR3}$(</proc/sys/kernel/random/entropy_avail)"
          echo -n  "${COLOR2} /${COLOR3}$(</proc/sys/kernel/random/poolsize)"
       fi
      ;;

    w) # WINDOW WIDTH AND LINE HEIGHT FONT1 & FONT2
        # To determine width of a character in conky "position 'x'" terms
        # and the height of a line for conky 'voffset'
        # first set line_width[n] to equal 'line length' seen in viewport
        # then set 'character_width' until the second line touches right edge
        # change line_height[n] until lines are evenly spaced

        function line_WIDTH_() {
            local font="$1"; [[ ! "${font}" =~ font ]] && return
            chomp="$2"
            character_width="$3"
            line_height="$4"
            cline_height="\${goto $((chomp*character_width-(character_width*2)))}"
            cline_height+="E\${voffset ${line_height}}"
            cline_height+="\${offset -${character_width}}E\${voffset -${line_height}}E"
            a_long_line="123456789112345678921234567893123456789412345678951234567896"
            cline="${a_long_line:0:${chomp}}"
            while read -r num; do l_line+="${num: -1}"; done < <(seq 99)
            cline="${l_line:0:${chomp}}"

          echo -n  "${font}\${color grey90}\${voffset ${SPACING}}"
          echo     " font $( grep -oP '(?<=font ).*(?=})' <<< "${font}" )"
          echo     "${cline}"
          echo     "${cline_height}"
          echo
 } 

        # big font
          line_WIDTH_ "${FONT1}" "${LINE_length1}" \
                      "${CHARACTER_width1}" "${LINE_height1}"
        # small font
          line_WIDTH_ "${FONT2}" "${LINE_length2}" \
                      "${CHARACTER_width2}" "${LINE_height2}"
         ;;

v) # FOR BENCHMARKING see heading to delete using sed
if [[ ! "${ALIGN}" =~ ^h ]]; then
echo -n "\${voffset $((SPACING*1+3))}${COLOR1}"
echo    "${HR:0:$(((LINE_length1/2-6)*3))}Runtime Stats\${voffset -1}\${hr}"
else
echo -n "\${${GOTO} $((INDENT1+15))}${COLOR1}"
fi
#
avg_cpu=$(awk '/usage / {sum+=$13; count ++}END
{if (count > 0)printf "%5.1f",
(sum/count)}' "${TIME_log}" | tail -1)
[ -z "${uptime}" ] && uptime=$(cut -d' ' -f1 /proc/uptime)
[ -z "${clock_ticks}" ] &&
clock_ticks=$(awk '{print$22/'$(tail -n 1 /proc/uptime|cut -d. -f1)"}" /proc/self/stat)
#
# cpu usage avg & current from /proc/$$/stat
awk -v avg="${avg_cpu}" -v ticks="${clock_ticks}" -v uptime="${uptime}" -v ncores="${NCORES}" '{total=$14+$15+$16+$17; start_time=$22;}END{printf "\${offset 20}Cpu usage avg\${color #C2F3F6}%5.1f\${offset 4}\${color #06939B}%%\${offset 5}\${color #06939B} current\${color #C2F3F6} %4.1f \${color #06939B}%%\n", avg, ( ( 100 * ( total / ticks ) / ( uptime - ( start_time / ticks))) );}'  "/proc/$$/stat" | tee -a "${TIME_log}"
#
# runtime avg & current from TIME_log closer to time from remote
awk -v runtime="$((($(date +%s%N)-tss)/1000000))" '/MONITOR/ {sum+=$3; count++}END{if (count > 0)printf "\${offset 20}Runtime\${offset 49}\${color #C2F3F6}%5.2f\${color #06939B}s\${offset 51}\${color #C2F3F6}%7.2f\${color #06939B}s\n",((sum / count)/1000),(runtime/1000);}' "${TIME_log}"
;;
    h|\?)
#    h)
        _Usage "$@"
     ;;
  esac
  done

  shift $((OPTIND-1))
# Total time for script
echo "\${goto ${INDENT1}}${COLOR2}${FONT_units}COMMAND: MONITOR $((($(date +%s%N)-tss)/1000000)) ms" | sed -e "s/[\${][^}]*[}]//g" >> "${TIME_log}"

 exit 0

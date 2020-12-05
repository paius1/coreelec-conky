#!/opt/bin/bash
#   v 0.9.8
#  Outputs CoreELEC OS stats in conky printable format
#  uses entware's bash, bind-dig, coreutils-df, coreutils-sort,
#                 coreutils-stat, procps-ng-top
#     
#   Usage: SCRIPTNAME -[ocltmueqirxsdfp]
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
#   run: time ssh Hostname /path/to/coreelec-conky.sh -[ocltmueqirxsdfp] >/dev/null
#   to determine 'interval' & add the following to your conkyrc:
#   
#   ${texecpi 'interval' ssh Hostname /path/to/coreelec-conky.sh -[ocltmueqirxsdfp]}
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

 export LC_ALL=C
 # SETUP ENVIRONMENT
  # Default alignment
    ALIGN="left"
  # offset between options
    readonly SPACING=1
  # height of filesystem bar (odd numbers center better)
    readonly BAR_height=5
  # set to 0 for monochromatic data (can be changed)
    COLOR=
  # set to show memory stats as text
    readonly MEM_text=1
  # sort "NPROCS" processes on "SORT" (%CPU or %MEM)
    NPROCS=3
    readonly SORT="%CPU"
  # colors for labels, sublabels, data, & units
    readonly COLOR1="\${color #06939B}"
    readonly COLOR2="\${color #43D3DA}"
    readonly COLOR3="\${color #9FEEF3}"
    readonly COLOR_units="\${color #b3b3b3}"
  # a monospace font found on computer running conky
  # run fc-list :spacing=100 ( n.b some fonts are limited )
    readonly font_family="Hack"
    FONT1="\${font ${font_family}:size=9}"
    FONT2="\${font ${font_family}:size=8}"
    FONT_units="\${font ${font_family}:size=7}"
  # the following work with the included conkyrc and std monospace fonts
  # to alter width run with -w  to determine the next 6 
    readonly LINE_length1=41     # characters per line:
    readonly LINE_length2=48
    readonly LINE_height1=15
    readonly LINE_height2=14
    CHARACTER_width1=7  # relation between spaces & conky goto|voffset 'x'
    CHARACTER_width2=6
  # indent labels one space
    readonly INDENT1="$((CHARACTER_width1*2))"
  # indent data, based on longest label changed for horizontal
    INDENT2="$((INDENT1+CHARACTER_width1*5))"
  # allow finer control of postion
    HALFSPACE1="$(((CHARACTER_width1+1)/2))"
    HALFSPACE2="$(((CHARACTER_width2+1)/2))"
  # cascading conky n.b. these include opening '{' don't forget to close '}'
    GOTO="\${goto "
    VOFFSET="\${voffset "
  # left hr since conky can't define hr width
    while read -r num; do HR+="―"; done < <(seq "$((LINE_length2))")
  # delay for refreshing disk usage to save time
    readonly FS_dt=20
  # the @ character prints below the line
    readonly ASTERISK="\${voffset -1}@\${voffset 1}"

  function _gradient() { # Pretty colors for data
    cat <<- EOg
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
  export -f _gradient
    STEPS="$(wc -l < <(_gradient))"

  function _color() { # Return HEX value from _gradient function
      [ "${2:-0}" -eq 0 ] \
                   && \
                      { _bash_REMATCH "${COLOR3}" ' [#]?([[:alnum:]]+)[[:blank:]]?}$';
                        return 1; }
      local current="$1"
      local maximum="$2"
      local color

      color="$((( current*STEPS + maximum / 2 ) / maximum ))"
      [ "${color#-}" -ge 1 ] \
                      || \
                         color=1
      /usr/bin/tail  -n "${color#-}" < <(_gradient) \
                  | /usr/bin/head -1
  return 0
 } 
 export -f _color
 
  function _print_RULE() { # conky hr has no width modifier
      local hr="$1"
      local length="$2"
      until ((length%3==0))
      do ((length++))
      done

      echo -n "${hr:0:${length}}"
  return 0
 }
 export -f _print_RULE

  function _is_HORIZ() { # are we printing a bar
      local align="$1"
      [[ "${align}" =~ ^h ]]
 }
 export -f _is_HORIZ

  function _set_HORIZ() { # if printing horizontally change some globals
          export GOTO="\${offset "
          export VOFFSET="\${offset "
          export FONT1="${FONT2}"
          export FONT_units="${FONT1}"
          export CHARACTER_width1="${CHARACTER_width2}"
          export HALFSPACE1="${HALFSPACE2}"
          export INDENT2="${SPACING}"
          export NPROCS=1
  return 0
 }
 export -f _set_HORIZ

  function _is_CASCADING() {
      local align="$1"
      [[ ! "${align}" =~ ^h ]]
 }
 export -f _is_CASCADING

  function _heading() { # start of option print label and space if cascading
      local label="$1"
      local align="$2"
      local conky_object="$3"
      local position="$4"
      local color="$5"
      local font="$6"
      local spacing="$7"

      echo -n  "${conky_object} ${position}}${color}${font}"
          _is_CASCADING "${align}" \
          && \
      echo -n "\${voffset ${spacing}}${label}"
  return 0      
 }
 export -f _heading

  function _justify() { # ALIGN string on line_length
      local align="$1"  # print newline if !horizontal
      local string="$2"
      local line_length="$3"
      local length_text padding newline
      
      case "${align}" in

          r*|c*)
                 # remove any leading & trailing whitespaces
                   string="$(sed -e 's/}[ \t]*/}/' -e 's/^[[:space:]]*//' \
                                 -e 's/[[:space:]]*$//' <<< "${string}")"

                 # length of string stripped of conky formating
                   length_text="$(("$(sed  -e "s/[\${][^}]*[}]//g" <<< "${string}" \
                                        | wc -c)"-1))"

                 # check length of text v length of line
                   [ "${length_text}" -gt "${line_length}" ] \
                                       && \
                                          { echo "lgth: ${line_length} < stng: ${length_text}";
                                            return 2; }

                 # spaces to pad string
                   padding="$((line_length-length_text))"
                   [[ "${align}" =~ ^c ]] \
                                 && \
                                    padding="$(((padding+2/2)/2))"

             ;&
          l*)    # Just add newline to printf
                   newline=$'\n'
            ;&
          *)     # printf ${padding}${string}${newline}
                 # remove any leading & trailing whitespaces for horizontal
                   _is_HORIZ "${align}" \
                             && \
                                string="$(sed -e 's/^[ \t]*//' -e 's/}[ \t]*/}/' \
                                              -e 's/[[:space:]]*$//' <<< "${string}")"

                 printf "%$((padding+${#string}))s" "${string}${newline}"
            ;;

        esac
    return 0
 }
 export -f _justify

  function _bash_REMATCH() { # Return specific data in matching line of
      local output           # command output, file, or string
      local source="$1"
      local pattern="$2"
      _is_SET "$3" \
              && \
                 output="/tmp/${source##*/}-${3}"

      if _is_EXECUTABLE "${source%% *}"
      then while IFS= read -r line
           do if [[ "${line}" =~ ${pattern} ]]
              then echo  "${BASH_REMATCH[1]}" \
                      | tee -a "${output:-/dev/null}"
              fi
          done < <(${source})
      elif _is_READABLE "${source}"
      then echo -n "" > "${output:-/dev/null}"
           while IFS= read -r line
           do if [[ "${line}" =~ ${pattern} ]]
              then echo  "${BASH_REMATCH[1]}" \
                      | tee -a "${output:-/dev/null}"
              fi
           done < "${source}"
      else [[ "${source}" =~ ${pattern} ]]
           echo "${BASH_REMATCH[1]}"
      fi
  return 0
 }
 export -f _bash_REMATCH

  function _no_IPINFO() { # if no return from ipinfo.io 
    cat <<- EOF
    "ip": "NO.RE.P.LY"
    "city": "NO"
    "region": "PLACE LIKE"
    "country": "HM"
EOF
 }
 export -f _no_IPINFO

  function _check_IP_data() { # Check if ip data file is/recent or create/update
      local ip_file="$1"
      local stale="$2"

      _is_READABLE "${1}" \
                   && \
                      [ "${stale}" -gt "$(_delay "$(/opt/bin/stat -c %Y "${ip_file}")")" ] \
                                    && \
                                       return 0

      curl -sf -m 2 ipinfo.io/"$(/opt/bin/dig +short myip.opendns.com @resolver1.opendns.com)" > "${ip_file}" \
      || \
      _no_IPINFO > "${ip_file}"
  return 0
 }
 export -f _check_IP_data

  function _created() { # creation time of file
      local file="$1"

      /opt/bin/stat -c %Y "${file}" 2>/dev/null \
      || \
      echo $?
      return 0
 }
 export -f _created

  function _delay() { # interval of time
      local then="$1"
      local file="$2"
      local now
      now="$(/usr/bin/date  +%s \
                         | tee "${file:-/dev/null}")"

      echo -n "$((now-${then:-946706401}))"
  return 0
 }
 export -f _delay

  function _make_ROOM_for() { # move file for new readings
      local file="$1"

      mv "${file}" "${file:0: -1}" 2>/dev/null \
      || \
      touch "${file:0: -1}"
  return 0
 }
 export -f _make_ROOM_for

  function _is_EMPTY() { # variable unset 
      local variable="$1"
      [ -z "${variable}" ]
 }
 export -f _is_EMPTY

  function _is_SET() { # variable set
      local variable="$1"
      [ -n "${variable}" ]
 }
 export -f _is_SET

  function _is_NOT_file() { # file doesn't exist
      local file="$1"
      [ ! -f "${file}" ]
 }
 export -f _is_NOT_file

  function _is_READABLE() { # file is readable
      local file="$1"
      [ -r "${file}" ]
 }
 export -f _is_READABLE

  function _is_EXECUTABLE() {
      local file="$1"
      [ -x "${file}" ]
 }
 export -f _is_EXECUTABLE

  function _network_INFO { # if printing network data get relavant interfaces
      # network interfaces
        ACTIVE_iface="$(_bash_REMATCH "/sbin/ip route show" \
                                      '^d.*[[:space:]]([^[:space:]]+)[[:space:]]$')"
        export readonly ACTIVE_iface
        ACTIVE_wifi="$(_bash_REMATCH "/sbin/ip addr" \
                                     '(wlan[[:digit:]]):[[:blank:]]<BR')"
        export readonly ACTIVE_wifi

      # file for public ip data
        export readonly IP_data="/tmp/network_DATA"
      # delay for curling ipinfo.co (1,000/day is their max)
        export readonly CURL_dt=180
 }
 export -f _network_INFO

  function _cpu() {
      local align="$1"
      local format="$2"
      local indent2="$3"
      local heterogeneous move_to skip
      declare -a core_per100
      declare -a fqz
      declare -a sides

           function _pcpu() {
               local align="$1"
               local file cpu_stats match
                     file=/proc/stat
                     _make_ROOM_for "${cpu_stats:=/tmp/${file##*/}-${align}}"
                     bash_match='(^cpu.*)+'
                     echo -n "" > /tmp/cpu_stats-"${align:0:1}"

               ( while  IFS= read -r a <&3 \
                              && \
                        IFS= read -r b <&4
                 do     echo  "${a} ${b}" \
                           | tee -a /tmp/cpu_stats-"${align:0:1}"
                 done ) \
                        3<"${cpu_stats:0: -1}" \
                        4< <(_bash_REMATCH "${file}" "${bash_match}" "${align}") \
                    | \
                 awk '{if (NR != "")
                       printf "%6.1f\n",
                               ($13-$2+$15-$4)*100/($13-$2+$15-$4+$16-$5);
                          else print 0;}'; }

      mapfile -t core_per100 < <(_pcpu "${align}")

        # heterogenous cpu?
          heterogeneous="$(_bash_REMATCH  '/usr/bin/lscpu' '^So.*([[:alnum:]]+)')"

      _heading "CPU:" "${ALIGN}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"
      case "$format" in # How much data to print

        *st) # cpu graph (pass longest)

             if _is_CASCADING "${align}"
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
               _is_CASCADING "${align}" \
               && \
      echo -n  "\${voffset -$((LINE_height1*1+LINE_height2+(SPACING*1)))}"

           ;&
        *r) # print per core percentages (pass longer to script)

             case "${align}" in
               h*)
      echo -n "\${offset -$((CHARACTER_width1*2))}"
                  ;;
               l*)
      echo -n "\${voffset $((LINE_height1))}${FONT2}${GOTO} $((INDENT1+HALFSPACE2*13))}"
                 ;;
               *)
      echo -n "\${voffset $((LINE_height1))}${FONT2}${GOTO} $((INDENT1+HALFSPACE2*2))}"
                 ;;
             esac

             # monochrome
               color=$(_bash_REMATCH "${COLOR3}" ' [#]?([[:alnum:]]+)[[:blank:]]?}$')

             seq="3 4 5 6 1 2"
             [ "${heterogeneous}" -eq 1 ] \
                                   && \
                                      seq="{1..$(_bash_REMATCH /usr/bin/lscpu \
                                                               '^CPU\(.*([[:digit:]])')}"

      _justify "${align}" \
               "$(for core in $(eval echo "$seq")
                  do echo -n "\${color ${color}}"
                     echo -n "$(printf '%5.1f' "${core_per100[$core]}")"
                     echo -n "${COLOR_units}\${offset 2}%"
                  done)" \
               "$((LINE_length2-indent2/CHARACTER_width2))"

      echo -n "\${offset ${HALFSPACE1}}"
             if _is_CASCADING "${align}"
             then # return to previous line
      echo -n  "\${voffset -$((LINE_height1*1+LINE_height2))}"
                 [[ "${format}" =~ ^longes ]] \
                                && \
      echo -n "\${voffset -$((LINE_height1*2))}"
                 : "${skip:=$((LINE_height1*1))}"
             fi
           ;&
        l*) # print frequencies, % for big.LITTLE as well (pass long to script)

             function _human_FREQUENCY() { # GHz, MHz units for cpu frequency
                 awk -v units_style="\${offset 1}${FONT_units}${COLOR_units}" '
                     {if ($1+0>999999)
                         printf "%5.1f%sGHz\n",
                         $1/10^6, units_style;
                      else printf "%5.0f%sMHz\n",
                      $1/10^3,units_style}' <<< "${1}"; }

             function bl_() {
                 local align="$1"
                 local cpu_stats line
                       cpu_stats="/tmp/stat-${align}"

                 while IFS= read -r line
                 do echo "${line}"
                 done  < /tmp/cpu_stats-"${align:0:1}" \
                    | tee >(awk 'NR==4||NR==7{S13+=$13;S2+=$2;S15+=$15;S4+=$4;S16+=$16;S5+=$5}
                                  END
                                 {if ($2 != 0 && $15 != 0)
                                     printf "%6.1f\n",(S13-S2+S15-S4)*100/(S13-S2+S15-S4+S16-S5)}') \
                          >(awk 'NR==2||NR==3{S13+=$13;S2+=$2;S15+=$15;S4+=$4;S16+=$16;S5+=$5}
                                  END
                                 {if ($2 != 0 && $15 != 0)
                                     printf "%6.1f\n",(S13-S2+S15-S4)*100/(S13-S2+S15-S4+S16-S5)}') \
                          >/dev/null; }

             # frequency current, minimum, & maximum
               mapfile -t fqz < \
                      <(cat /sys/devices/system/cpu/cpufreq/policy*/scaling_*_freq)

             if [ "${heterogeneous}" -eq 2 ] # add usage & frequency for heterogeneous 'big' cores
             then mapfile -t sides < <(bl_ "${align}")

                 # concatenate line so its closer to 80 columns
                   l_string="\${offset 1}${FONT2}"
                   l_string+="\${color $(_color "${sides[1]%.*}" "${COLOR:-100}")}"
                   l_string+="${sides[1]}"
                   l_string+="\${offset ${HALFSPACE2}}${COLOR_units}%"
                   l_string+="\${offset ${HALFSPACE2}}${ASTERISK}"
                   l_string+="\${offset -${CHARACTER_width2}}"
                   l_string+="\${color $(_color "$((fqz[3]-fqz[5]))" "$(((fqz[4]-fqz[5])*${COLOR:-1}))")}"
                   l_string+="$(_human_FREQUENCY "${fqz[3]}")"
                   l_string+="\${offset ${HALFSPACE2}}${VOFFSET} -1}"
                   l_string+="\${color $(_color "${sides[0]%.*}" "${COLOR:-100}")}"
                   l_string+="${FONT2}${sides[0]}"
                   l_string+="\${offset 2}${COLOR_units}%\${offset 2}"
             elif [[ "${align}" =~ ^r ]] # homogeneous cpu, position frequency after cpu%
             then move_to="$((HALFSPACE1*2))"
             fi

             # add frequency for only/'LITLE' cores
               l_string+="${ASTERISK}"
               l_string+="\${offset -${CHARACTER_width1}}"
               l_string+="\${color $(_color "$((fqz[0]-fqz[2]))" "$(((fqz[1]-fqz[2])*${COLOR:-1}))")}"
               l_string+="$(_human_FREQUENCY "${fqz[0]}")"

             case "${align}" in # make room for a long line
               l*)    move_to="$((INDENT1+CHARACTER_width1*4))";;
               r*) : "${move_to:=$((HALFSPACE1*7))}";;
               c*) : "${move_to:=$((HALFSPACE1*11))}";;
               *)     move_to=1;;
             esac

             : "${skip:=$((SPACING-1))}"
          ;&
        *) # print overall percentage

           case "${align}" in
             c*) : "${move_to:=$((HALFSPACE1*9))}" ;;
             r*) : "${move_to:=0}" ;;
             l*) : "${move_to:=$((indent2*1-CHARACTER_width1))}" ;;
             *)  : "${move_to:=$((CHARACTER_width1*2))}"  ;;
           esac
  
           c_line+="\${color $(_color "${core_per100[0]%.*}" "${COLOR:-100}")}"
           c_line+="${core_per100[0]}"
           c_line+="\${offset 1}${COLOR_units}%"

      echo -n  "${GOTO} ${move_to}}${FONT1}"
      _justify "${align}" \
               "${c_line}${l_string}" \
               "${LINE_length1}"

           if _is_HORIZ "${align}"
           then
      echo -n "\${offset 2}"
           else : "${skip:=0}"
      echo -n  "\${voffset ${skip}}"
           fi
          ;;
      esac

           if   [[ "${format}" =~ ^longe ]] \
                               || \
                [ "$((core_per100[0]%.*))" -gt 70 ]
           then # iowait and softirq for case: longe* or high cpu usage
      echo -n "${FONT2}${COLOR1}"
      awk 'NR==1||NR==8{start=($2+$3+$4+$5+$6+$7+$8+$9+$10);
           end=($13+$14+$15+$16+$17+$18+$19+$20+$21);
           iowStart=($6);iowEnd=($17);
           sirqStart=($8);sirqEND=($19)}
           END
           {printf "\${alignc}iowait: %6.4f%%  softirq: %6.4f%%",
                    (iowEnd-iowStart)*100/(end-start),
                    (sirqEND-sirqStart)*100/(end-start);}' \
           /tmp/cpu_stats-"${align:0:1}"

              _is_CASCADING "${align}" \
              && \
      echo
           fi
 }
 export -f _cpu

  function _loadavg() {
      local align="$1"
      local indent2="$2"

      _heading "LOAD:" "${align}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

      mapfile -d' '  loadavg < /proc/loadavg

      if _is_EMPTY "${COLOR}"
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
           do  load_color+=("$(_bash_REMATCH "${COLOR3}" \
                                             ' [#]?([[:alnum:]]+)[[:blank:]]?}$')")
           done
      fi

      a_line+="\${color ${load_color[0]}}"
      a_line+="$(sed -e 's/[ \t]*//'  <<< "${loadavg[0]}")"
      a_line+="\${color ${load_color[1]}}"
      a_line+="${loadavg[1]}"
      a_line+="\${color ${load_color[2]}}"
      a_line+="${loadavg[2]}"

      echo -n  "${GOTO} $((indent2+0))}"
      _justify "${align}" \
               "${a_line}" \
               "$((LINE_length1-indent2/CHARACTER_width1))"

          if [ "${loadavg[1]%.*}" -ge 4 ]
          then # high load average can mean blocked processess
               mapfile -t procs < \
                      <( _bash_REMATCH /proc/stat '^procs_(.*)+' )
      echo -n  "\${color #ff3200}\${alignc} ${procs[0]} ${procs[1]}"

               _is_CASCADING "${align}" \
               && \
      echo
            fi
 }
 export -f _loadavg

  function _temperature() {
      local align="$1"
      local indent2="$2"

        _heading "TEMP:" "${align}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

      # hot for the cpu/ram
        hot=70

      # read all zones
        mapfile -t temps 2>/dev/null < \
               <( cat /sys/class/thermal/thermal_zone*/temp)

      # name thermal zones ( note the space before element n+1 )
        zones=('Cpu:' ' Mem:')
        _is_HORIZ "${align}" \
                  && \
                     zones=('C:' "\${offset ${HALFSPACE1}}M:")

      # unicode character ° throws off justify function
        right=0
        if [[ "${align}" = +(c*|r*) ]]
        then right=2
        fi

      if _is_EMPTY "${COLOR}"
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
           do  temp_color+=("$(_bash_REMATCH "${COLOR3}" \
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

      echo -n  "${GOTO} $((indent2))}${COLOR2}"
      _justify "${align}" \
               "${t_line}" \
               "$((LINE_length1-indent2/CHARACTER_width1+right))"

          if [ "$((((temps[0]+(1000/2))/1000)))" -ge "${hot}" ]
          then          # Hi temp, what process is using most cpu
      echo -n  "\${color #ff3200}${FONT1}"

              _is_CASCADING "${align}" \
              && \
      echo -n  "\${voffset ${SPACING}}"

      awk -v indent="${GOTO} $((indent2+0))}" '
          {if ($1) printf "%s%-10s%7d%6.1f%%%6.1f%%",indent,$11,$1,$7,$8;
           else printf $2}' < \
          <(/opt/bin/top -bn 2 -d 0.01 -c -o +"${SORT}" \
                       | sed -e  '/top/d' \
                           | /usr/bin/tail  -n +11 \
                                         | /usr/bin/head -1)

              _is_CASCADING "${align}" \
              && \
      echo
          fi
 }
  export -f _temperature

  function _uptime() {
      local align="$1"
      local indent2="$2"

      _heading "UPTIME:" "${align}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

      units=( " day(s)" " hrs" " mins" )
      _is_HORIZ "${align}" \
                && \
                   units=( "d" "h" "m" )

      echo -n  "${GOTO} ${indent2}}${COLOR3}"
      _justify "${align}" \
               "$(awk  -v d="${units[0]}" -v h="${units[1]}" -v m="${units[2]}" \
                       -F"[ |.]+" '{secs=$1;}END
                       {printf "%d%s %d%s %d%s",
                                secs/86400,d,secs%86400/3600,h,secs%3600/60,m;}' \
                      /proc/uptime)" \
               "$((LINE_length1-indent2/CHARACTER_width1))"
 }
  export -f _uptime

  function _memory() {
      local align="$1"
      local indent2="$2"

      _heading "" "${align}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"
          label='MEM:'

          mapfile -d' ' -t memory < \
                 <(awk 'NR==2{total=$2;used=$3}END
                        {printf "%d %d %2.1f",used,total,(used/total)*100}' < \
                       <(free -m))

      if _is_EMPTY "${MEM_text}"
      then #                 memory bar  
      echo -n  "${label}"
      echo -n  "${GOTO} ${indent2}}"

          width="$((LINE_length1*CHARACTER_width1-(indent2+INDENT1)))"
          _is_HORIZ "${align}" \
                    && \
                       width="60"

      echo -n  "\${color $(_color "${memory[2]%.*}" "${COLOR:-100}")}"
      echo -n  "\${execbar $((LINE_height1/3)),${width} echo ${memory[2]%.*}}"

          _is_CASCADING "${align}" \
          && \
      echo
      else #                    text
          m_line+="\${color $(_color "${memory[2]%.*}" "${COLOR:-100}")}"
          m_line+="${memory[2]}%"
          m_line+=" ${memory[0]}${COLOR3}/${memory[1]}"
          m_line+="${FONT_units}${COLOR_units}\${offset 3}MB"

          _is_CASCADING "${align}" \
          && \
      echo -n  "${label}"
      
      echo -n  "${GOTO} ${indent2}}"
      _justify "${align}" \
               "${m_line}" \
               "$((LINE_length1-indent2/CHARACTER_width1))"
      fi

      if [ "${memory[2]%.*}" -ge  80 ]
      then # high memory usage, who's the biggest hog
      echo -n "${GOTO} $((indent2+10))}${FONT1}\${color red}"
      awk '{printf "%-9s %d %2.1f%% %5.1f Mb %5.1f Mb\n",
                    $1,$2,$3,($4/1024),($5/1024^2)}' < \
          <(/opt/bin/ps  -eo comm,ppid,pmem,rss,vsize \
                      | /opt/bin/sort  -k 3 -n -r \
                                    | /usr/bin/head -1)
      fi
 }
  export -f _memory

  function _essid() {
      local align="$1"
      local indent2="$2"

      _heading "ESSID:" "${align}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

      line="$(_bash_REMATCH '/usr/bin/connmanctl services' '^\*AR[[:blank:]]([^[:blank:]]+).*w') "
      # TODO need to fiqure out bitrate speed w/o iwconfig see below
        line+="${COLOR2}"
        line+="$(/usr/bin/awk -v wlan="${ACTIVE_wifi}" \
                              -F "[. ]+" '$0 ~ wlan {print $4}' /proc/net/wireless)"
        line+="${COLOR_units}\${offset 2}%"

      echo -n  "${GOTO} ${indent2}}${COLOR3}"
      _justify "${align}" \
               "${line}"\
               "$((LINE_length1-(indent2/CHARACTER_width1)))"
 }
  export -f _essid

  function _network_QUALITY() {
      local align="$1"
      local indent2="$2"

      #_heading "LINK:" "${align}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"
      
      #match="${ACTIVE_wifi}:[[:blank:]][[:digit:]]+[[:blank:]]*([[:digit:]]+)\."
      
      sq_line="Speed: ${COLOR3}$(:) "
      #sq_line+="\${offset 3}${COLOR2}Quality: ${COLOR3}"
      #sq_line+="$(/usr/bin/awk -v wlan="${ACTIVE_wifi}" \
                                #-F "[. ]+" '$0 ~ wlan {print $4}' /proc/net/wireless)"
      #sq_line+="${COLOR_units}\${offset 3}%"
      
      #echo -n  "${GOTO} ${indent2}}${VOFFSET} -1}${COLOR2}${FONT2}"
      #_justify "${align}" \
               #"${sq_line}" \
               #"$((LINE_length2-(indent2/CHARACTER_width2)-1))"
 }
  export -f _network_QUALITY

  function _lan_IP() {
      local align="$1"
      local indent2="$2"

      match='inet addr:([0-9]+[\.][0-9]+[\.][0-9]+[\.][0-9]+)[[:space:]]'

          if   _is_SET "${ACTIVE_wifi}" \
               && \
               [[ "${ACTIVE_wifi}" != "${ACTIVE_iface}" ]]
          then
      _heading "${ACTIVE_wifi}:" "${align}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

      echo -n  "${GOTO} ${indent2}}${COLOR3}"
      _justify "${align}" \
               "$(_bash_REMATCH "/sbin/ifconfig ${ACTIVE_wifi}" "${match}")" \
               "$((LINE_length1-(indent2/CHARACTER_width1)))"
          fi

      _heading "" "${align}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"
      echo -n  "${ACTIVE_iface}:"

      echo -n  "${GOTO} ${indent2}}${COLOR3}"
      _justify "${align}" \
               "$(_bash_REMATCH "/sbin/ifconfig ${ACTIVE_iface}" "${match}")" \
               "$((LINE_length1-(indent2/CHARACTER_width1)))"
 }
  export -f _lan_IP

  function _public_IP() {
      local align="$1"
      local indent2="$2"

      _heading "IP:" "${align}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

          # ipinfo.io limits: 1,000 requests/day
            _check_IP_data "${IP_data}" "${CURL_dt}"

          match='ip'
          return='[\"].*[\"](.*)[\"]'

      echo -n  "${GOTO} ${indent2}}${COLOR3}"
      _justify "${align}" \
               "$(_bash_REMATCH "${IP_data}" "${match}${return}")" \
               "$((LINE_length1-(indent2/CHARACTER_width1)))"
 }
  export -f _public_IP

  function _geo_IP() {
      local align="$1"
      local indent2="$2"

      _heading "GEO:" "${align}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

            _check_IP_data "${IP_data}" "${CURL_dt}"

          matches=( 'city' 'region' 'country' )
          return='[\"].*[\"](.*)[\"]' # everything between 2nd set of "'s

          for match in "${matches[@]}"
          do  ip_data+=("$(_bash_REMATCH "${IP_data}" "${match}${return}" )")
          done

      echo -n  "${GOTO} ${indent2}}${COLOR3}"
      _justify "${align}" \
               "${ip_data[0]:0:18}, ${ip_data[1]:0:12} ${ip_data[2]:0:3}" \
               "$((LINE_length1-(indent2/CHARACTER_width1)))"
 }
  export -f _geo_IP

  function _network_SPEED() {
      local align="$1"
      local indent2="$2"

      _heading "${ACTIVE_iface}:" "${align}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"

          function _human_NETSPEED() { # https://askubuntu.com/users/307523/wineunuuchs2unix
              local u p_u b d s 
              u="\${offset ${HALFSPACE2}}${COLOR_units}${FONT_units}"
              p_u="\${offset -1}/\${offset -1}s"
                _is_CASCADING "${align}" \
                              && \
                                 p_u+="${VOFFSET} -2}"
              b="${1}"; d=''; s=0; S=(' B' {K,M,G,T,E,P,Y,Z}B)

              while ((b > 1024))
              do
                 d="$(printf "%02d" "$((((b%1024*100)+(1024/2))/1024))")"
                 b="$((b / 1024))"
                 ((s++))
              done
              [ "${b}" -gt 0 ] \
                        || \
                           { b=1; d=0; s=0; }
              : "${d:=0}"
              printf "%4d%s%.1s%s" "$b" "." "${d}" "${u}${S[${s}]}${p_u}"; }

      # variables for stats
        net_stats="/tmp/net_stats-${align:0:1}"
        then="$(_created "${net_stats}")"
        dt="$(_delay "${then}")"
        [ "${then}" -eq 1 ] \
                     && \
                        echo -n "" > "${net_stats}"

      # read network rx,tx stats into array
        mapfile -t rawbytes < \
               <(cat "${net_stats}" 2>/dev/null \
               <(cat  /sys/class/net/"${ACTIVE_iface}"/statistics/{rx,tx}_bytes \
                   | tee "${net_stats}"))

      rxtx=(  "$(( ( (rawbytes[2] - rawbytes[0]) + ( ${dt:=1} / 2 )  ) / dt ))" )
      rxtx+=( "$((((rawbytes[3]-rawbytes[1])+dt/2)/dt))" )

      # to set max upper speed
        speed='/tmp/net-speed'
      # adjust scale for up speed # this returns error on no file, oh well
        hi_up="$(< "${speed}_up")" \
                  || touch "${speed}_up"
        [ "${rxtx[1]:=1000}" -gt "${hi_up:=1000}" ] \
                              && \
                                 echo "${rxtx[1]}" > "${speed}_up"
      # adjust scale for down speed
        hi_dn="$(< "${speed}_down")" \
                  || touch "${speed}_down"
        [ "${rxtx[0]:=1000}" -gt "${hi_dn:=1000}" ] \
                              && \
                                 echo "${rxtx[0]}" > "${speed}_down"

      # sublabel for conky (left|right|center) || horiz
        sublabel=( 'Up:' 'Dn:' )
        _is_HORIZ "${align}" \
                  && \
                     sublabel=( '↑' '↓' )

      s_line+="${COLOR2}${FONT1}${sublabel[0]}"
      s_line+="\${color $(_color "$((rxtx[1]))" "${COLOR:-${hi_up}}")}"
      s_line+="$(_human_NETSPEED "${rxtx[1]}")"
      s_line+="${COLOR2}${FONT1} ${sublabel[1]}"
      s_line+="\${color $(_color " $((rxtx[0]))" "${COLOR:-${hi_dn}}")}"
      s_line+="$(_human_NETSPEED "${rxtx[0]}")"
        _is_CASCADING "${align}" \
                      && \
                         s_line+="${VOFFSET} 1}"

      echo -n  "${GOTO} ${indent2}}"

      [[ "${align}" =~ ^r ]] \
                    && \
      echo -n "\${offset $((HALFSPACE2*2))}"

      _justify "${align}" \
               "${s_line}" \
               "$((LINE_length1-(indent2/CHARACTER_width1)))"
 }
  export -f _network_SPEED

  function _diskio() {
      local align="$1"
      local indent2="$2"

      _heading "DISKS:" "${align}" "${GOTO}" "${INDENT1}" "${COLOR1}" "${FONT1}" "${SPACING}"
          _is_HORIZ "${align}" \
          && \
      echo -n "\${offset -7}"

          function _diskstats() {
              local align="$1"
              local file diskstats match
                    file=/proc/diskstats
                    then="$(_created "${diskstats:=/tmp/${file##*/}-${align}}")"
                    _make_ROOM_for "${diskstats:=/tmp/${file##*/}-${align}}"
                    bash_match='(^.*sd[a-z] .*|^.*blk0p2.*)'
                    dt="$(_delay "${then}")"
                    [ "${then}" -eq 1 ] \
                                 && \
                                    echo -n "" > "${diskstats}"

              ( renice -10
                while IFS= read -r a <&3 \
                            && \
                      IFS= read -r b <&4
                do echo "${a} ${b}"
                done ) 3<"${diskstats:0: -1}" \
                       4< <(_bash_REMATCH "${file}" "${bash_match}" "${align}") \
                   | \
                awk -v dt="${dt}" -v read="${read}" -v write="${write}" -v mb="${mb}" \
                    '{read_start+=$6;read_end+=$20;write_start+=$10;write_end+=$24;i++}
                      END
                     {if (dt > 0 && i >= 2)
                          printf "%9.3f\n%9.3f\n%.0f\n%.0f",
                          ((read_end-read_start)/dt)*512/1024^2,
                          ((write_end-write_start)/dt)*512/1024^2,
                          (((read_end-read_start)/dt)*512/1024^2)*1000,
                          (((write_end-write_start)/dt)*512/1024^2)*1000;
                      else printf "\n";}'; }

          mapfile -t diskio < <(_diskstats "${align}")

          # upper speed read/write
            speed='/tmp/disk'
            _is_READABLE "${speed}_read" \
                         || \
                            echo '1000' > "${speed}_read"
            _is_READABLE "${speed}_write" \
                         || \
                            echo '1000' > "${speed}_write"

            hi_read="$(<  "${speed}_read")"
            hi_write="$(< "${speed}_write")"

          # adjust scale for read/write speed
            [ "${diskio[2]:=1}" -gt "${hi_read:=100}" ] \
                                 && \
                                    echo "${diskio[2]}" > "${speed}_read"
                               

            [ "${diskio[3]:=1}" -gt "${hi_write:=100}" ] \
                                 && \
                                    echo "${diskio[3]}" > "${speed}_write"

          # color disk io
            colors=(  "$(_color "${diskio[2]}" "$((${hi_read:-1} *${COLOR:-1}/4))")" )
            colors+=( "$(_color "${diskio[3]}" "$((${hi_write:-1}*${COLOR:-1}/4))")" )

          # variables for conky
            offset=0
            [[ "${align}" =~ ^c ]] \
                          && \
                             offset="${CHARACTER_width2}"
            begin="\${offset ${offset}}${COLOR2}${FONT1}"
            read="${begin}R${COLOR3}"
            write="${begin}W${COLOR3}"
            mb="\${offset $((HALFSPACE2*1))}${COLOR_units}${FONT2}"
            mb+="Mb\${offset -2}/\${offset -2}s "
              _is_CASCADING "${align}" \
                            && \
                               mb+="\${voffset -1}"

      echo -n  "${GOTO} ${indent2}}"

      [[ "${align}" =~ ^r ]] \
                    && \
      echo -n "\${offset $((HALFSPACE2*6))}"

      _justify "${align}" \
               "${read}\${color ${colors[0]}}${diskio[0]}${mb}${write}\${color ${colors[1]}}${diskio[1]}${mb}" \
               "$((LINE_length1-indent2/CHARACTER_width1))"
 }
 export -f _diskio

  function _filesystems() {
      local align="$1"
      local indent2="$2"

      _heading "" "${align}" "${GOTO}" '0' "${COLOR1}" "${FONT1}" "${SPACING}"
      if _is_CASCADING "${align}"
      then
      echo -n  "$(_print_RULE "${HR}" "$(((LINE_length1/2-3)*3))")"
      echo -n  "STORAGE"
      echo -n  "\${voffset -1}\${hr}\${voffset $((LINE_height1+4))}"
      else
      echo -n "\${offset 5}"
      fi

      file="/tmp/filesystem-${align:0:1}"
      then="$(_created "${file}")"

      # to shorten the list especially for horizontal format
        skip_target=( "flash" "" )
      # ignore sshfs & smb
         local_only=(-l)

      if   _is_NOT_file "${file}" \
                        || \
           [ "$(_delay "${then}" )" -gt "${FS_dt}" ]
      then # read current data and tee to file

          # (width of line in conky 'x') - (location & length of FREE) + space
            width="$((LINE_length1*CHARACTER_width1-(HALFSPACE1*41)))"
            [[ "${align}" =~ ^l ]] \
                          && \
                             width="$((width-HALFSPACE1*5))"

          { /opt/bin/df   -h "${local_only[@]}" -x tmpfs -x devtmpfs -x squashfs -x iso9660 \
                          --output=target,avail,used,pcent \
                      | tail  -n +2 \
                           | /opt/bin/sort  -k 4 -i \
                      | \
            while read -r TARGET AVAIL USED PCENT
            do target="${TARGET##*/}"   # yes those are "'s in a match
               [[ " ${skip_target[*]} " =~ " ${target} " ]] \
                                        && \
                                           continue
  
               percent="${PCENT%?}"
               [[ "${percent}" -lt 1 \
                                || \
                  "${percent}" -gt 100 ]] \
                                && \
                                   percent=99

               if _is_HORIZ "${align}"
               then # print linear
      echo -n  "\${offset 0}${COLOR1}"
      echo -n  " ${target:0:8}"
      echo -n  "\${color $(_color "$((percent))" "${COLOR:-100}")}"
      echo -n  "\${offset ${HALFSPACE1}}$(printf "%5s" "${AVAIL}") "
               else # print table
      echo -n  "${GOTO} ${INDENT1}}${COLOR1}"
      echo -n  "${target:0:15}"
      echo -n  "${GOTO} ${indent2}}${COLOR2}"
      echo -n  "$(printf %14s "${AVAIL}")"
      echo -n  "${GOTO} $((indent2+CHARACTER_width1*15))}"
      echo -n  "\${color $(_color "$((percent))" "${COLOR:-100}")}"
      echo -n  "\${execbar ${BAR_height},${width} echo \"${percent%.*}\"}"
      echo -n  "${GOTO} $((indent2+HALFSPACE1*29))}"
      echo -n "\${offset $((width*${percent%.*}/115-HALFSPACE1*5))}"
      echo -n  "\${color $(_color $((100-${percent%.*})) "$((99*${COLOR:-1}+1))")}$(printf "%4s" "${USED}")"
      echo
               fi
            done ## sorted on percent remaining
          } \
          | \
            /usr/bin/head  -c -1 \
                        | tee "${file}"
              # OR sort on total free space
          #} \
          #| /opt/bin/sort  --human-numeric-sort -k "6" \
                        #| /usr/bin/head  -c -1 \
                                      #| tee "${file}"
      else
      printf   "%s" "$(<"${file}")"
      fi

      _is_CASCADING "${align}" \
      && \
      echo
 }
 export -f _filesystems

  function _processes() {
      local align="$1"
      local indent2="$2"

      if _is_CASCADING "${align}"
      then _heading "" "${align}" "${GOTO}" '0' "${COLOR1}" "${FONT1}" "$((SPACING+2))"
      echo -n  "$(_print_RULE "${HR}" "$(((LINE_length1/2-7)*3))")"
      echo -n  "STORAGE"
      echo -n  "$(_print_RULE "${HR}" "3")"

      echo -n  "[$(_bash_REMATCH '/proc/stat' 'running ([[:digit:]]+)')]"
      echo     "\${voffset -1}\${hr}\${voffset $((LINE_height1/3))}"

          # allow some expansion for wider viewport
            fudge="$(((LINE_length1-33)/4))"
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
      fi

          move_to="$((INDENT1+HALFSPACE1*4))"
      echo -n  "${VOFFSET} ${SPACING}}${COLOR3}${FONT1}"
      awk -v indent="${GOTO} ${move_to}}" -v cpu="\${offset ${spacing[1]}}" \
          -v mem="\${offset ${spacing[2]}}" \
          '{if ($1 != 0)
               printf "%s%-14.14s%7d%s%6.1f%%%s%5.1f%%\n",
                       indent,$11,$1,cpu,$7,mem,$8;
            else printf}' < \
          <( renice -10 $BASHPID
            /opt/bin/top  -bn 2 -d 0.01 -c -o +"${SORT}" \
                       | sed  -e '/top/d' -e "${list_pad}"\
                           | /usr/bin/tail  -n +11 \
                                         | /usr/bin/head -n "${NPROCS}")
 }
  export -f _processes

  function _os_INFO() {
      local align="$1"
      local indent2="$2"

      if _is_CASCADING "${align}"
      then # print lots of superfluose data over 1/10 of a second
           # run script with -o & add output to conkyrc from here
           # to ## EOO ##...
           # then comment out, because it seems like wasted time
      echo -n "${GOTO} 0}${COLOR2}${FONT1}"
      echo    "\${alignc}$(_bash_REMATCH /etc/os-release '^PR.*"(.*+)"') "

           # hardware
      echo -n "${GOTO} 0}${FONT1}"
      echo    "\${alignc}$(_bash_REMATCH /proc/cpuinfo '^Ha.*:[[:blank:]](.*+)')"

           # model name  
      echo -n  "${GOTO} 0}${FONT1}"
      echo "\${alignc}$(_bash_REMATCH /proc/cpuinfo '^model.*:[[:blank:]](.*+)')"

           UNAME="$(uname -a)"

           # os
      echo -n "${GOTO} 0}${COLOR1}${FONT2}"
      echo    "\${alignc}${UNAME: -17}"

           # kernel
      echo -n  "${GOTO} 0}${COLOR1}${FONT2}"
      echo     "\${alignc}$(echo "${UNAME:0:37}"|tr '#' d)"
      echo -n  "\${voffset -2}"
      echo     "\${alignc}${COLOR1}$(_print_RULE "${HR}" "117")"
  ## EOO #########################################################################

           # cpu configuration & governor
      echo -n  "${GOTO} ${indent2}}\${voffset ${SPACING}}${COLOR1}${FONT2}"
      echo -n  "\${alignc}($(_bash_REMATCH /usr/bin/lscpu '^CPU\(.*([[:digit:]])'))"
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
 }
  export -f _os_INFO

  function _line_WxH() {
      local align="$1"
      local indent2="$2"

      # To determine width of a character in conky "position 'x'" terms
      # and the height of a line for conky 'voffset'
      # first set line_width[n] to equal 'line length' seen in viewport
      # then set 'character_width' until the second line touches right edge
      # change line_height[n] until lines are evenly spaced

          function _line_WIDTH() {
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
              while read -r num; do l_line+="${num: -1}"; done < <(seq 99)
              cline="${l_line:0:${chomp}}"
   
            echo -n  "${font}\${color grey90}\${voffset ${SPACING}}"
            echo     " font $( [[ "${font}" =~ t[[:space:]](.*+)} ]] \
                                            && \
                                               echo "${BASH_REMATCH[1]}")"
            echo     "${cline}"
            echo     "${cline_height}"
            echo; } 

        if _is_CASCADING
        then # big font
            _line_WIDTH "${FONT1}" "${LINE_length1}" \
                        "${CHARACTER_width1}" "${LINE_height1}"
             # small font
            _line_WIDTH "${FONT2}" "${LINE_length2}" \
                        "${CHARACTER_width2}" "${LINE_height2}"
        fi
 }
 export -f _line_WxH

function _benchmarks() {
local align="$1"
local indent2="$2"
if _is_CASCADING "${align}"; then
echo -n "\${voffset $((SPACING*1+3))}${COLOR1}${FONT1}"
echo -n  "$(_print_RULE "${HR}" "$(((LINE_length1/2-6)*3))")Runtime Stats\${voffset -1}\${hr}"
echo
else
echo -n "${GOTO} $((INDENT1+15))}${COLOR1}${FONT1}"
fi
#
NCORES="$(_bash_REMATCH /usr/bin/lscpu '^CPU\(.*([[:digit:]])')"
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
_is_CASCADING "${align}" \
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
_is_CASCADING "${align}" \
&& { newline=$'\n';
label="\${offset 10}Runtime\${offset 4}\${color #C2F3F6}\${offset 55}"; }
#
# runtime avg & current from TIME_log closer to time from remote
awk -v label="${label}" -v runtime="$((($(/usr/bin/date +%s%N)-tss)/1000000))" '/MONITOR/ {sum+=$3; count++}END{if (count > 0)printf "%s%5.2f\${color #06939B}s\${offset 5}\${color #C2F3F6}%7.2f\${color #06939B}s\n",label,((sum / count)/1000),(runtime/1000);}' "${TIME_log}"
}
export -f _benchmarks

  function _main() {

      [[ "${@}" =~ e|q|i|r|x|s ]] \
                && \
                   _network_INFO

      while getopts "ocltmueqirxspfdwvh" opt
      do case "${opt}" in
           o)    #
                 _os_INFO "${ALIGN}" "${INDENT2}"

             ;;
           c)    #
                 _cpu "${ALIGN}" "${FORMAT}" "${INDENT2}"

             ;;
           l)    #
                 _loadavg "${ALIGN}" "${INDENT2}"

             ;;
           t)    #
                 _temperature "${ALIGN}" "${INDENT2}"

             ;;
           m)    #
                 _memory "${ALIGN}" "${INDENT2}"

             ;;
           u)    #
                 _uptime "${ALIGN}" "${INDENT2}"

             ;;
           e)    #
                            _is_SET "${ACTIVE_wifi}" \
                         && \
                 _essid "${ALIGN}" "${INDENT2}"

             ;;
           q)    #
                            _is_SET "${ACTIVE_wifi}" \
                         && \
                 _network_QUALITY "${ALIGN}" "${INDENT2}"

             ;;
           i)    #
                            _is_SET "${ACTIVE_iface}" \
                         && \
                 _lan_IP "${ALIGN}" "${INDENT2}"

             ;;
           r)    #
                            _is_SET "${ACTIVE_iface}" \
                         && \
                 _geo_IP "${ALIGN}" "${INDENT2}"

             ;;
           x)    #
                            _is_SET "${ACTIVE_iface}" \
                         && \
                 _public_IP "${ALIGN}" "${INDENT2}"

             ;;
           s)    #
                            _is_SET "${ACTIVE_iface}" \
                         && \
                 _network_SPEED "${ALIGN}" "${INDENT2}"

             ;;
           d)    #
                 _diskio "${ALIGN}" "${INDENT2}"

             ;;
           f)    #
                 _filesystems "${ALIGN}" "${INDENT2}"

             ;;
           p)    
                 _processes "${ALIGN}" "${INDENT2}"

             ;;
           w)    #
                 _line_WxH "${ALIGN}" "${INDENT2}"

             ;;
v)    #
_benchmarks "${ALIGN}" "${INDENT2}"
;;
           *|h)  #
                 _Usage "${@}"
             ;;
         esac
         shift $((OPTIND-1))
      done
 }

  # allow changing alignment & format from the conky config
  # arguments at beginning either order
    if [[ "$1" == +(le*|r*|c*|h*) ]];  then ALIGN="$1";  shift; fi
    if [[ "$1" == +(lo*|s*) ]]; then FORMAT="$1"; shift; fi
    if [[ "$1" == +(le*|r*|c*|h*) ]];  then ALIGN="$1";  shift; fi
  # arguments at end either order
    if [[ "${@: -1}" == +(lo*|s*) ]]; then FORMAT="${@: -1}"; set -- "${@:1:$(($#-1))}"; fi
    if [[ "${@: -1}" == +(le*|r*|c*|h*) ]]; then ALIGN="${@: -1}"; set -- "${@:1:$(($#-1))}"; fi
    if [[ "${@: -1}" == +(lo*|s*) ]]; then FORMAT="${@: -1}"; set -- "${@:1:$(($#-1))}"; fi
#
# add options in conkyrc to skip these defaults
#
if [ ${#1} -eq 1 ]
then # add options after %/
#
if [[ ! "${ALIGN}" =~ ^h ]]
then                           # CASCADING #
#
set -- "${@/%/ocltmueqirxsdf}"
#
set -- "${@/%/p}"
#
# for benchmarking
set -- "${@/%/v}"
#
#FORMAT=long
#ALIGN=center
#
else    # HORIZONTAL #
#
set -- "${@/%/cltumesrfd}"
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
# log for benchmarking script
TIME_log="/tmp/time-${ALIGN:0:1}"
_is_NOT_file "${TIME_log}" \
             && \
                touch "${TIME_log}"
#
  # add some space to INDENT2 for left justify
    [[ "${ALIGN}" =~ ^l ]] \
                  && \
                     INDENT2="$((INDENT2+HALFSPACE1*5))"

  # change formatting for horizontal
    _is_HORIZ "${ALIGN}" \
              && \
                 _set_HORIZ

  #readonly ALIGN # MAKE THIS & INDENT2 CHANGABLE
  #readonly INDENT2
  readonly FONT1
  readonly FONT2
  readonly FONT_units
  readonly CHARACTER_width1
  readonly HALFSPACE1
  readonly NPROCS
  readonly GOTO
  readonly VOFFSET

  _main "${@}"

  # print closing line
    _is_CASCADING "${ALIGN}" \
    && \
    echo "\${alignc}${COLOR1}$(_print_RULE "${HR}" "$((LINE_length1*3))")"

# Total time for script
echo "\${goto ${INDENT1}}${COLOR2}${FONT_units}COMMAND: MONITOR $((($(/usr/bin/date +%s%N)-tss)/1000000)) ms" | sed -e "s/[\${][^}]*[}]//g" >> "${TIME_log}"
# Trim to ~ last 5 minutes
[ "$( wc -l < "${TIME_log}" )" -gt 50 ] && ( sed -i  -e :a -e '$q;N;50,$D;ba' "${TIME_log}" )&

 exit 0

 coreelec-conky
Remotely Monitor coreELEC via Conky

   v 0.9.2
  Outputs CoreELEC OS stats in conky printable format
  using entware's bash, procps-ng-top, coreutils-sort, net-tools,
                  coreutils-df, bind-dig

   Usage: SCRIPTNAME -[ocltumeqirxsdfp]
          [o] os info <ng>   [c] cpu usage         [l] load average
          [t] temp cpu & ram [u] uptime            [m] memory
          [e] network essid  [q] wireless quality  [i] lan address
          [r] network region [x] public ip         [s] network up/down speed
          [d] disk i/o       [f] mounted filesystems, free space, & graph of usage
          [p] processes pid %cpu %mem command (sorted w/ SORT=pcpu|pmem)

 Ꜿ plgroves gmail nov 2020
    
    I really just wanted to monitor my hard drive usage, VPN, and
    maybe temperatures!?
    
    Install entware:
    https://discourse.coreelec.org/t/what-is-entware-and-how-to-install-uninstall-it/1149
    
    Get hack font 
    https://github.com/source-foundry/Hack
    
    Ssh login without password
    http://www.linuxproblem.org/art_9.html

    Reuse ssh connection
    https://linuxhostsupport.com/blog/speed-up-ssh-connections-in-linux/#
    
      nano ~/.ssh/config on computer running conky & add
    
           Host coreelec
           User root
           Hostname 'from /etc/hosts (e.g. coreelec)'
           ControlMaster auto
           ControlPath  ~/.ssh/sockets/master-coreelec
           ControlPersist 600
    
    
   prints output in order of options <fewer options faster time / less load>
   
   run: time ssh Hostname /path/to/coreelec-conky.sh -[ocltumeqirxsdfp] >/dev/null
   to determine 'interval' & add the following to your conky config:
   
   ${texecpi 'interval' ssh Hostname /path/to/coreelec-conky.sh -[ocltumeqirxsdfp]}
   
   add 'UseDNS no' to /storage/.cache/services/sshd.conf on CoreELEC
   
   alignment and cpu format can be changed from the command line
     pass [left|center|right|horiz] for alignment
     pass [long|longer|longest] for frequency, per core, and a graph
   
   to remove all nonindented (debug) lines after this heading
     sed -i -e '61,$ { /^[^[:blank:]]/d }' /opt/bin/coreelec-conky.sh 

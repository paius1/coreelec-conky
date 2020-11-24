 coreelec-conky
Remotely Monitor coreELEC via Conky

  Outputs CoreELEC OS stats in conky printable format
  using entware's bash, bind-dig, coreutils-df, coreutils-sort, 
                  coreutils-stat, procps-ng-top
     
   Usage:
   
     /opt/bin/coreelec-conky.sh -[ocltumeqirxsdfp]
          [o] os info <ng>   [c] cpu usage         [l] load average
          [t] temp cpu & ram [u] uptime            [m] memory
          [e] network essid  [q] wireless quality  [i] lan address
          [r] network region [x] public ip         [s] network up/down speed
          [d] disk i/o       [f] mounted filesystems, free space, & graph of usage
          [p] processes command pid %cpu %mem (sorted w/ SORT=%CPU|%MEM)

 Ꜿ plgroves gmail nov 2020
    
  I really just wanted to monitor my hard drive usage, VPN, and
    maybe temperatures!?
    
   Install entware:
    https://discourse.coreelec.org/t/what-is-entware-and-how-to-install-uninstall-it/1149
   
    
   Get hack font 
    https://github.com/source-foundry/Hack
    
   ssh login without password
    http://www.linuxproblem.org/art_9.html

   Reuse ssh connection
    https://linuxhostsupport.com/blog/speed-up-ssh-connections-in-linux/#
    
   TLDR: nano ~/.ssh/config on computer running conky & add
    
           Host coreelec
           User root
           Hostname local ip or name from /etc/hosts (e.g. 192.168.x.x or coreelec)
           ControlMaster auto
           ControlPath  ~/.ssh/sockets/master-coreelec
           ControlPersist 600
   
   add 'UseDNS no' to /storage/.cache/services/sshd.conf on CoreELEC
    
   
   run installer to copy conky script to coreELEC and coreelec-conkyrc to ~/.conky/
   
    ./coreelec-conky-installer.sh
    
   prints output in order of options <fewer options faster time / less load>
   
   run: 

    time ssh Hostname /opt/bin/coreelec-conky.sh -[ocltumeqirxsdfp] >/dev/null
      
   to determine 'interval' & add the following to your conky config:
   
    ${texecpi 'interval' ssh Hostname /opt/bin/coreelec-conky.sh -[ocltumeqirxsdfp]}
      
   alignment and cpu format can be changed from the command line
     
     [left|center|right|horiz] for alignment
     
     [long|longer|longest] for frequency, per core, and a graph
   
     e.g coreelec-conky.sh right longest -ocltumeqirxsdfp
   
   to remove all nonindented (debug) lines
     
     sed -i -e '61,$ { /^[^[:blank:]]/d }' /opt/bin/coreelec-conky.sh 

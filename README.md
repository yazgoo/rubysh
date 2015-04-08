# Tutorial

## You can use shell

    $ pwd
    /home/yazgoo/dev/rsh

    $ ls
    README.md
    rsh

## But you also have access to a ruby interprete

    $ @myvar = 42
    => 42
    $ @myvar ** @myvar
    => 150130937545296572356771972164254457814047970568738777235893533016064

## And you can mix boths

    $ ps(ax).select { |x| x.match(".*dhclient.*") }
    28067 ?        S      0:00 /sbin/dhclient -d -sf /usr/lib/NetworkManager/nm-dhcp-client.action 

    $ ps(ax).select { |x| x.match(".*dhclient.*") }.collect { |x| x.split.first }
    28067

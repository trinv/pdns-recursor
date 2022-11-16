#!/usr/bin/perl -w
#
# Copyright (c) 2020 Mathieu Roy <yeupou--gnu.org>
#      http://yeupou.wordpress.com
#
#   This program is free software; you can redistribute it and/or modify it
#   under the terms of the GNU General Public License as published by the
#   Free Software Foundation; either version 2, or (at your option) any
#   later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

use strict;
use Fcntl ':flock';

my $spooflist = "redirect-spooflist.conf";
my $ads_lua = "redirect-ads.lua";
my $ads_pl = "redirect-ads-rebuild.pl";
my $main_lua = "redirect.lua";

# disallow concurrent run
open(LOCK, "< $0") or die "Failed to ask lock. Exiting";
flock(LOCK, LOCK_EX | LOCK_NB) or die "Unable to lock. This daemon is already alive. Exiting";

# first check if we have a ads list to block
# if not, run the local script to build izt
unless (-e $ads_lua) {
    print "$ads_lua missing\n";
    print "run $ads_pl\n" and do "./$ads_pl" if -x $ads_pl;
}

my %cache;
# read conf
open(LIST, "< $spooflist");
while (<LIST>) {
    next if /^#/;
    next unless s/^(.*?):\s*//;
    $cache{$1} = [ split ];
}
close(LIST);

# build lua
open(NEWCONF, "> $main_lua");
printf NEWCONF ("-- Generated on %s by $0\n", scalar localtime);
print NEWCONF '-- IPv4 only script

-- ads kill list
ads = newDS()
adsdest = "127.0.0.1"
ads:add(dofile("/etc/powerdns/redirect-ads.lua"))

-- spoof lists
';

foreach my $ip (keys %cache) {
    # special handling of IP+, + meaning we spoof even to the destination host
    my $name = $ip;
    $name =~ s/(\.|\+)//g;  
    print NEWCONF "spoof$name = newDS()\n";
    print NEWCONF "spoof$name:add{", join(", ", map "\"$_\"", sort@{$cache{$ip}}), "}\n";
    $ip =~ s/(\+)//g;
    print NEWCONF "spoofdest$name = \"$ip\"\n";
}

print NEWCONF '
function preresolve(dq)
   -- DEBUG
   --pdnslog("Got question for "..dq.qname:toString().." from "..dq.remoteaddr:toString().." to "..dq.localaddr:toString(), pdns.loglevels.Error)
   
   -- spam/ads domains
   if(ads:check(dq.qname)) then
     if(dq.qtype == pdns.A) then
       dq:addAnswer(dq.qtype, adsdest)
       return true
     end
   end
    ';

foreach my $ip (keys %cache) {
    my $always = 0;
    $always = 1 if ($ip =~ s/(\+)//g);     # + along with IP means always spoof no matter who is asking
    my $name = $ip;
    $name =~ s/\.//g;

    print NEWCONF '
   -- domains spoofed to '.$ip.'
   if(spoof'.$name.':check(dq.qname)) then';
    print NEWCONF '
     dq.variable = true
     if(dq.remoteaddr:equal(newCA(spoofdest'.$name.'))) then
       -- request coming from the spoof/cache IP itself, no spoofing
       return false
     end' unless $always;
    print NEWCONF '   
     if(dq.qtype == pdns.A) then
       -- redirect to the spoof/cache IP
       dq:addAnswer(dq.qtype, spoofdest'.$name.')
       return true
     end
   end
	';
}

print NEWCONF '
   return false
end
';
close(NEWCONF);


# EOF

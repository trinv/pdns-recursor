-- Generated on Thu Mar 11 00:28:15 2021 by ./redirect-rebuild.pl
-- IPv4 only script

-- ads kill list
ads = newDS()
adsdest = "127.0.0.1"
ads:add(dofile("/etc/powerdns/redirect-ads.lua"))

-- spoof lists
spoof19216801 = newDS()
spoof19216801:add{"thisdomain.lan", "thisother.lan"}
spoofdest19216801 = "192.168.0.1"
spoof10001 = newDS()
spoof10001:add{"anotherthisdomain.lan", "anotherthisother.lan"}
spoofdest10001 = "10.0.0.1"

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
    
   -- domains spoofed to 192.168.0.1
   if(spoof19216801:check(dq.qname)) then
     dq.variable = true
     if(dq.remoteaddr:equal(newCA(spoofdest19216801))) then
       -- request coming from the spoof/cache IP itself, no spoofing
       return false
     end   
     if(dq.qtype == pdns.A) then
       -- redirect to the spoof/cache IP
       dq:addAnswer(dq.qtype, spoofdest19216801)
       return true
     end
   end
	
   -- domains spoofed to 10.0.0.1
   if(spoof10001:check(dq.qname)) then   
     if(dq.qtype == pdns.A) then
       -- redirect to the spoof/cache IP
       dq:addAnswer(dq.qtype, spoofdest10001)
       return true
     end
   end
	
   return false
end

// discord webhook URL. Acquired by right clicking a discord channel > Edit > Integrations
string WEBHOOK_URL     = "";

//should the pinger update the message with number of raiders during the raid?
integer update = 1;
float updatetime = 120; // How often should the update check fire off?
integer active = FALSE; // Is a raid currently happening? if so locks out further pings, checks for hostile party to drop to 0

// Minimum number of 'raiders' required to allow alerts
integer MIN_PARTY_SIZE = 3;

// Time in seconds to wait before allowing another ping after successfully posting alert via webhook
integer PING_COOLDOWN  = 1800; 

// Enable or Disable the group blacklist. Useful for keeping your own group from pinging
integer USE_BLACKLIST  = TRUE;
list BLACKLIST = [""];

integer busy;
integer lastPing;
string requestType;
key httpRequest;
key agentKey;
string message_id;
string agentName;
string group;
string groupname;
integer count;
integer friendlies;
integer lastcount;
integer lastfriend;

resetState()
{
    busy = FALSE;
    active = FALSE;
    requestType = "";
    httpRequest = NULL_KEY;
    message_id = "";
    lastcount=0;
    lastfriend=0;
    llSetTimerEvent(0.0);
    llSetLinkPrimitiveParamsFast(LINK_SET, [PRIM_TEXT, "Looking for combat?\nClick to ping our Discord server", <1,1,1>, 1]);
}

string getGroup(key id)
{
    list attachedList = llGetAttachedList(id);
    return llList2String(llGetObjectDetails(llList2Key(attachedList, 0), [OBJECT_GROUP]), 0);
}

default
{
    state_entry()
    {
        resetState();
    }

    touch_start(integer total_number)
    {
        if(busy) return;
        if(active) return;

        integer timeRemaining = PING_COOLDOWN - (llGetUnixTime() - lastPing);
        if(timeRemaining > 0)
        {
            llRegionSayTo(llDetectedKey(0), 0, "Ping board is on cooldown. Try again in " + (string)(timeRemaining / 60) + " minutes.");
            return;
        }

        busy = TRUE;
        llSetLinkPrimitiveParamsFast(LINK_THIS, [PRIM_TEXT, "Busy...", <1,0,0>, 1]);

        agentKey = llDetectedKey(0);
        agentName = llKey2Name(agentKey);
        group = getGroup(agentKey);

        if((key)group == NULL_KEY || group == "")
        {
            llRegionSayTo(agentKey, 0, "Could not determine your active group. Please try again.");
            resetState();
            return;
        }

        if(USE_BLACKLIST && llListFindList(BLACKLIST, [group]) != -1) 
        {
            llRegionSayTo(agentKey, 0, "no.");
            resetState();
            return;
        }

        list agentList = llGetAgentList(AGENT_LIST_REGION, []);
        integer n = llGetListLength(agentList);
        count = 0;
        friendlies=0;

        while(n--)
        {
            string theirgroup=getGroup(llList2Key(agentList, n));
            if(theirgroup == group) count++;
            else if(llListFindList(BLACKLIST,[(string)theirgroup])>-1)friendlies++;
        }

        if(count >= MIN_PARTY_SIZE)
        {
            // Set safety timer in case world.secondlife.com or Discord stalls
            llSetTimerEvent(10.0);
            requestType = "groupname";
            httpRequest = llHTTPRequest("http://world.secondlife.com/group/" + group, [], "");
        }
        else
        {
            llRegionSayTo(agentKey, 0, "Party size too small (" + (string)count + "/" + (string)MIN_PARTY_SIZE + "). Alert cancelled.");
            resetState();
        }
    }

    http_response(key id, integer status, list meta, string body)
    {
        if(id != httpRequest) return;

        if(requestType == "groupname")
        {
            groupname = "";

            if(status == 200)
            {
                list parsed = llParseString2List(body, ["<title>", "</title>"], []);
                groupname = llList2String(parsed, 1);
            }

            // Fallback in case the web scrape fails or throttles
            if(groupname == "")
            {
                groupname = "Group UUID: " + group;
            }
            
            string message = "ALERT: " + agentName + " [" + groupname + "] wants to raid " + llGetRegionName() + " with a party of " + (string)count + " or more to "+(string)friendlies+" defenders. @here";
            
            requestType = "discord";
            string TEMP_URL = WEBHOOK_URL;
            if(update)TEMP_URL+="?wait=true";
            httpRequest = llHTTPRequest(TEMP_URL, [HTTP_METHOD, "POST", HTTP_MIMETYPE, "application/json"], llList2Json(JSON_OBJECT, ["content", message]));
        }
        else if(requestType == "discord")
        {
            if(status == 200 || status == 204)
            {
                lastPing = llGetUnixTime();
                llRegionSayTo(agentKey, 0, "Discord alert sent.");
                if(!update)resetState();
                else
                {
                    message_id = llJsonGetValue(body,["id"]);
                    active = TRUE;
                    llSetTimerEvent(updatetime);
                    llSetLinkPrimitiveParamsFast(LINK_THIS, [PRIM_TEXT, "Raid Ongoing!\n"+groupname+" with "+(string)count+" raiders!", <1,0,0>, 1]);
                }
            }
            else 
            {
                llRegionSayTo(agentKey, 0, "Error sending Discord alert (HTTP " + (string)status + ").\n" + body);
                resetState();
            }
        }        
        else if(requestType == "update")
        {
            if(status == 200 || status == 204)
            {
                message_id = llJsonGetValue(body,["id"]);
                active = TRUE;
            }
        }
    }

    timer()
    {
        if(active)
        {
            list agentList = llGetAgentList(AGENT_LIST_REGION, []);
            integer n = llGetListLength(agentList);
            count = 0;
            friendlies=0;
            while(n--)
            {
                string theirgroup=getGroup(llList2Key(agentList, n));
                if(theirgroup == group) count++;
                else if(llListFindList(BLACKLIST,[(string)theirgroup])>-1)friendlies++;
            }
            if(count<MIN_PARTY_SIZE)resetState();
            else
            {
                if(count>=lastcount||friendlies>=lastfriend)
                {
                    lastcount=count;
                    lastfriend=friendlies;
                    string message = "ALERT: " + agentName + " [" + groupname + "] wants to raid " + llGetRegionName() + " with a party of " + (string)count + " or more to "+(string)friendlies+" defenders. @here";
                    requestType = "update";
                    string TEMP_URL = WEBHOOK_URL;
                    if(update)TEMP_URL+="/messages/"+message_id;
                    httpRequest = llHTTPRequest(TEMP_URL, [HTTP_METHOD, "PATCH", HTTP_MIMETYPE, "application/json"], llList2Json(JSON_OBJECT, ["content", message]));
                    llSetLinkPrimitiveParamsFast(LINK_THIS, [PRIM_TEXT, "Raid Ongoing!\n"+groupname+" with "+(string)count+" raiders!", <1,0,0>, 1]);
                }
            }
        }
        else
        {
            llRegionSayTo(agentKey, 0, "Web request timed out. Please try again.");
            resetState();
        }
    }
}

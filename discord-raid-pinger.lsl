// discord webhook URL. Acquired by right clicking a discord channel > Edit > Integrations
string WEBHOOK_URL     = "";

// Minimum number of 'raiders' required to allow alerts
integer MIN_PARTY_SIZE = 3;

// Time in seconds to wait before allowing another ping after successfully posting alert via webhook
integer PING_COOLDOWN  = 1800; 

// Enable or Disable the group blacklist. Useful for keeping your own group from pinging
integer USE_BLACKLIST  = FALSE;
list BLACKLIST = [];

integer busy;
integer lastPing;
string requestType;
key httpRequest;
key agentKey;
string agentName;
string group;
integer count;

resetState()
{
    busy = FALSE;
    requestType = "";
    httpRequest = NULL_KEY;
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

        integer timeRemaining = PING_COOLDOWN - (llGetUnixTime() - lastPing);
        if(timeRemaining > 0)
        {
            llRegionSayTo(llDetectedKey(0), 0, "Ping board is on cooldown. Try again in " + (string)(timeRemaining / 60) + " minutes.");
            return;
        }

        busy = TRUE;
        llSetLinkPrimitiveParamsFast(LINK_SET, [PRIM_TEXT, "Busy...", <1,0,0>, 1]);

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

        while(n--)
        {
            if(getGroup(llList2Key(agentList, n)) == group) count++;
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
            string groupname = "";

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
            
            string message = "ALERT: " + agentName + " [" + groupname + "] wants to raid " + llGetRegionName() + " with a party of " + (string)count + " or more. @here";
            
            requestType = "discord";
            httpRequest = llHTTPRequest(WEBHOOK_URL, [HTTP_METHOD, "POST", HTTP_MIMETYPE, "application/json"], llList2Json(JSON_OBJECT, ["content", message]));
        }
        else if(requestType == "discord")
        {
            if(status == 200 || status == 204)
            {
                lastPing = llGetUnixTime();
                llRegionSayTo(agentKey, 0, "Discord alert sent.");
            }
            else 
            {
                llRegionSayTo(agentKey, 0, "Error sending Discord alert (HTTP " + (string)status + ").\n" + body);
            }
            resetState();
        }
    }

    timer()
    {
        llRegionSayTo(agentKey, 0, "Web request timed out. Please try again.");
        resetState();
    }
}

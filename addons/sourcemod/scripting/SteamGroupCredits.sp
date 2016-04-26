#pragma semicolon 1
#define DEBUG
#include <sourcemod>
#include <sdktools>
#include <SteamWorks>
#include <store>
#include <multicolors>
// Global Database Handle
Handle g_DB;
int credit_amount = 200;
bool g_IsInGroup[MAXPLAYERS + 1];
public Plugin myinfo = 
{
    name = "SteamGroup Credits", 
    author = "Totenfluch", 
    description = "Gives your Credits when you are in the Steam Group", 
    version = "2.0", 
    url = "http://ggc-base.de"
};
public void OnPluginStart()
{
    RegConsoleCmd("sm_claim", ClaimCredits, "Claims the credits for joining the group");
}
public Action:ClaimCredits(client, args){
    SteamWorks_GetUserGroupStatus(client, 103582791435943299);
}
public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max) {
    // Connect to the MySQL
    g_DB = SQL_Connect("steamgroup", true, error, err_max);
    SQL_SetCharset(g_DB, "utf8");
    decl String:querry[512];
    Format(querry, sizeof(querry), "CREATE TABLE IF NOT EXISTS `SteamGroupCredits` (`thekey` bigint(20) NOT NULL AUTO_INCREMENT, `timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP, `playerid` varchar(20) NOT NULL, `amount` int(11) NOT NULL, PRIMARY KEY (`thekey`)) ENGINE=InnoDB AUTO_INCREMENT=75 DEFAULT CHARSET=latin1;");
    decl String:error2[255];
    if (!SQL_FastQuery(g_DB, querry))
    {
        SQL_GetError(g_DB, error2, sizeof(error2));
        PrintToServer("Failed to query (error: %s)", error2);
    }
}
public void OnClientPutInServer(int client)
{
    SteamWorks_GetUserGroupStatus(client, 103582791435943299);
}
public OnClientDisconnect(int client){
    g_IsInGroup[client] = false;
}
public int SteamWorks_OnClientGroupStatus(int authid, int groupid, bool isMember, bool isOfficer)
{
    int client = GetUserFromAuthID(authid);
    if (isMember || isOfficer)
    {
        g_IsInGroup = true;
        //PrintToServer("In der Grp. Checkm8");
        if (IsValidClient(client)) {
            if (IsClientInGame(client) && !IsFakeClient(client)) {
                //PrintToChat(client, "Checking your grp!");
                
                decl String:querry[255];
                decl String:error[255];
                decl String:client_id[20];
                GetClientAuthId(client, AuthId_Steam2, client_id, sizeof(client_id));
                //PrintToChat(client, "Checking you!");
                Format(querry, sizeof(querry), "SELECT COUNT(*) FROM SteamGroupCredits WHERE playerid = '%s'", client_id);
                
                DBResultSet rs;
                if ((rs = SQL_Query(g_DB, querry)) == null)
                {
                    SQL_GetError(g_DB, error, sizeof(error));
                    PrintToServer("Failed to query (error: %s)", error);
                    decl String:logfile[128];
                    BuildPath(Path_SM, logfile, sizeof(logfile), "logs/GiveCreditsSteamGroup.txt");
                    LogToFile(logfile, "SQL Error: %s", error);
                } else {
                    while (rs.FetchRow()) {
                        int grp = rs.FetchInt(0);
                        //PrintToChatAll("this %i", grp);
                        if (grp > 0) {
                            return -1;
                        }
                    }
                    
                    Store_SetClientCredits(client, Store_GetClientCredits(client) + credit_amount);
                    CPrintToChat(client, "{green}[{purple}PLG{green}]{orange} Du hast {green}%i{orange} Credits bekommen, da du unserer Steam Gruppe beigetreten bist!", credit_amount);
                    
                    Format(querry, sizeof(querry), "INSERT INTO `SteamGroupCredits` (`thekey`, `timestamp`, `playerid`, `amount`) VALUES (NULL, CURRENT_TIMESTAMP, '%s', '%i')", client_id, credit_amount);
                    SQL_FastQuery(g_DB, querry);
                }
            }
        }
    }
    return 0;
}
int GetUserFromAuthID(int authid) {
    for (int i = 1; i < MAXPLAYERS + 1; i++) {
        if (IsValidClient(i)) {
            char authstring[50];
            GetClientAuthId(i, AuthId_Steam3, authstring, sizeof(authstring));
            
            char authstring2[50];
            IntToString(authid, authstring2, sizeof(authstring2));
            
            if (StrContains(authstring, authstring2) != -1)
            {
                return i;
            }
        }
    }
    
    return -1;
}
public IsValidClient(client)
{
    if (!(1 <= client <= MaxClients) || !IsClientInGame(client))
        return false;
    
    return true;
}
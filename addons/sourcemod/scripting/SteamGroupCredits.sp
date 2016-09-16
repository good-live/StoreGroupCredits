#pragma semicolon 1
#define DEBUG
#include <sourcemod>
#include <sdktools>
#include <SteamWorks>
#include <store>
#include <multicolors>
#include <logdebug>

public Plugin myinfo = 
{
	name = "SteamGroup Credits", 
	author = "Totenfluch", 
	description = "Gives your Credits when you are in the Steam Group", 
	version = "2.0", 
	url = "http://ggc-base.de"
};

Database g_hDB;
bool g_bIsInGroup[MAXPLAYERS + 1];
bool g_bDB_Connected = false;
Handle g_hTimer[MAXPLAYERS + 1] = {INVALID_HANDLE, ...};
ConVar g_fCooldown;
ConVar g_iAmount;

public void OnPluginStart()
{
	InitDebugLog("steamgroup_debug", "SGC", ADMFLAG_ROOT);
	RegConsoleCmd("sm_claim", ClaimCredits, "Claims the credits for joining the group");

	g_fCooldown = CreateConVar("sgc_cooldown", "10.0", "The command cooldown");
	g_iAmount = CreateConVar("sgc_amount", "250", "The amount of credits a player get");
	
	AutoExecConfig(true);

	if (!SQL_CheckConfig("steamgroup"))
	{
		LogDebug("Could not find the steamgroup Database entry");
		SetFailState("Couldn't find the database entry 'steamgroup'!");
	} else {
		LogDebug("Trying to connect to the database");
		Database.Connect(DBConnect_Callback, "steamgroup");
	}
	
	LoadTranslations("steamgroup.phrases");
}

public Action ClaimCredits(client, args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;

	if(g_fCooldown.FloatValue > 0.0)
	{
		if(g_hTimer[client] != INVALID_HANDLE)
		{
			CPrintToChat(client, "%t" , "Cooldown", client);
			return Plugin_Handled;
		}else{
			g_hTimer[client] = CreateTimer(g_fCooldown.FloatValue, Timer_Cooldown, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		}
	}

	LogDebug("Trying to lookup Client: %i Database connected: %b", client, g_bDB_Connected);
	
	if (g_bDB_Connected)
		SteamWorks_GetUserGroupStatus(client, 103582791429521979);
	else
		CPrintToChat(client, "%t", "No Connection");
	
	return Plugin_Handled;
}

public Action Timer_Cooldown(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if(g_hTimer[client] != INVALID_HANDLE)
		g_hTimer[client] = INVALID_HANDLE;
	return Plugin_Stop;
}


public OnClientDisconnect(int client)
{
	g_bIsInGroup[client] = false;
}

public int SteamWorks_OnClientGroupStatus(int authid, int groupid, bool isMember, bool isOfficer)
{
	LogDebug("Trying to lookup client: %i", authid);
	int client = GetUserFromAuthID(authid);
	if (isMember || isOfficer)
	{
		g_bIsInGroup[client] = true;
		LogDebug("%i is in the Steamgroup", client);
		if (IsValidClient(client)) {
			if (!IsFakeClient(client)) {
				LogDebug("Checking %i", client);
				
				char sQuery[255];
				char sClient_id[21];
				
				if (!GetClientAuthId(client, AuthId_Steam2, sClient_id, sizeof(sClient_id)))
				{
					LogDebug("Failed to retrieve AuthId of %i", client);
					return 0;
				}
				
				int iUserid = GetClientUserId(client);
				
				Format(sQuery, sizeof(sQuery), "SELECT timestamp FROM SteamGroupCredits WHERE playerid = '%s'", sClient_id);
				LogDebug("%s", sQuery);
				g_hDB.Query(DBCheck_Callback, sQuery, iUserid);
				
			}
		}
	}
	else{
		CPrintToChat(client, "%t", "You are not in the Group");
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

public void DBConnect_Callback(Database db, const char[] error, any data)
{
	if (db == INVALID_HANDLE) {
		LogDebug("Database Connection Failed: %s . Unloading ...", error);
		SetFailState("Database connection failed!: %s", error);
		return;
	}
	
	LogDebug("Database Connect was succesfull");
	
	g_hDB = db;
	
	g_hDB.SetCharset("utf8mb4");
	
	LogDebug("Trying to Create Tables");
	
	char sQuery[512];
	
	Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS `SteamGroupCredits` (`thekey` bigint(20) NOT NULL, `timestamp` int(11) DEFAULT '0', `playerid` varchar(20) NOT NULL, `amount` int(11) NOT NULL, PRIMARY KEY (`thekey`))");
	g_hDB.Query(DBCreateTable_Callback, sQuery);
}

public void DBCreateTable_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if (strlen(error) > 0 || results == INVALID_HANDLE) {
		LogDebug("Table Creation failed: %s. Unloading ...", error);
		SetFailState("Table creation failed: %s", error);
	}
	
	g_bDB_Connected = true;
	
	LogDebug("Table Creation succesfull");
}

public void DBCheck_Callback(Database db, DBResultSet results, const char[] error, any userid)
{
	if (db == INVALID_HANDLE || results == INVALID_HANDLE)
	{
		LogDebug("Query failed: %s. Unloading ...)", error);
		return;
	}
	
	int client = GetClientOfUserId(userid);
	if (!IsValidClient(client))
		return;
	
	results.FetchRow();
	
	LogDebug("Checking if client is in Database.");
	
	if (!results.RowCount)
	{
		LogDebug("He is not in the Database");
		char sAuthID[21];
		char sQuery[512];
		
		if (!GetClientAuthId(client, AuthId_Steam2, sAuthID, sizeof(sAuthID)))
			return;
		
		Store_SetClientCredits(client, Store_GetClientCredits(client) + g_iAmount.IntValue);
		CPrintToChat(client, "%t", "Credits Recieved", g_iAmount.IntValue);
		
		Format(sQuery, sizeof(sQuery), "INSERT INTO `SteamGroupCredits` (`thekey`, `timestamp`, `playerid`, `amount`) VALUES (NULL, '%i', '%s', '%i')", GetTime(), sAuthID, g_iAmount.IntValue);
		LogDebug("%s", sQuery);
		g_hDB.Query(DBQuery_Callback, sQuery);
	}else{
		int timestamp = results.FetchInt(0);
		if(timestamp == 2016)
		{
			CPrintToChat(client, "%T", "Date Uknown", client);
		}else{
			char sDate[64];
			FormatTime(sDate, sizeof(sDate), "%m.%d.%Y - %T", timestamp);
			CPrintToChat(client, "%t", "Already Recieved", sDate);
		}
	}
}

public void DBQuery_Callback(Database db, DBResultSet results, const char[] error, any userid)
{
	if (db == INVALID_HANDLE || results == INVALID_HANDLE)
	{
		LogDebug("Query failed: %s. Unloading ...)", error);
		return;
	}
}
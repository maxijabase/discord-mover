/* Dependencies */

#include <sourcemod>
#include <tf2_stocks>
#include <ripext>
#include <multicolors>
#include <autoexecconfig>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "2020.10.24"
#define MIN_CELL_LEN 32
#define PREFIX "{green}[Discord Mover]{default}"
#define DEBUG 0

public Plugin myinfo =  {
	
	name = "Discord Mover", 
	author = "ampere", 
	description = "Moves users from a Discord channel to another based on their team.", 
	version = PLUGIN_VERSION, 
	url = "https://legacyhub.xyz"
	
};

/* Global */

JSONObject teams;
JSONArray RED;
JSONArray BLU;

JSONObject pregame;
JSONObject user;

Database g_Database;

int intg;
ConVar cvShouldKick, cvCooldown;
bool g_bCommandEnabled = true;

enum struct Arrays {
	
	ArrayList BLU;
	ArrayList RED;
	
}

Arrays arr;

/* Start */

public void OnPluginStart() {
	
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetFile("DiscordMover");
	
	cvShouldKick = AutoExecConfig_CreateConVar("sm_dmover_kick", "1", "Kick?", FCVAR_NOTIFY);
	cvCooldown = AutoExecConfig_CreateConVar("sm_dmover_cooldown", "30", "Command Cooldown.", FCVAR_NOTIFY);
	
	RegAdminCmd("sm_move", CMD_Move, ADMFLAG_GENERIC, "Move command.");
	
	Database.Connect(SQL_ConnectCallback, "whois");
	
	LoadTranslations("discordmover.phrases");
	LoadTranslations("common.phrases");
	
	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();
	
}

public void OnMapStart() {
	
	char map[32];
	GetCurrentMap(map, sizeof(map));
	
	if (StrContains(map, "mge_") != -1 || StrContains(map, "ultiduo_") != -1) {
		
		SetFailState("[Discord Mover] Map not supported! Disabling plugin.");
		
	}
	
}

/* Kick if not in the database */

public void OnClientAuthorized(int client, const char[] auth) {
	
	if (IsClientSourceTV(client) || IsFakeClient(client) || !cvShouldKick.BoolValue) {
		
		return;
		
	}
	
	int userid = GetClientUserId(client);
	
	char authID[32];
	GetClientAuthId(client, AuthId_SteamID64, authID, sizeof(authID));
	
	char query[128];
	Format(query, sizeof(query), "SELECT steam_id FROM discordmover WHERE steam_id='%s';", authID);
	
	g_Database.Query(SQL_CheckClientCallback, query, userid);
	
}

public void SQL_CheckClientCallback(Database db, DBResultSet results, const char[] error, int userid) {
	
	if (db == null || results == null) {
		
		ThrowError("[Discord Mover] %s", error);
		delete results;
		return;
		
	}
	
	if (!results.FetchRow()) {
		
		KickClient(GetClientOfUserId(userid), "%t", "Kick");
		
	}
	
	delete results;
	
}

/* Database */

public void SQL_ConnectCallback(Database db, const char[] error, any data) {
	
	if (db == null) {
		
		ThrowError("[Discord Mover] %s", error);
		return;
		
	}
	
	g_Database = db;
	CreateTable();
	
}

void CreateTable() {
	
	char query[256];
	Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS discordmover(steam_id VARCHAR(32) NOT NULL UNIQUE, discord_id VARCHAR(32) NOT NULL UNIQUE);");
	
	g_Database.Query(SQL_TablesCallback, query);
	
}

public void SQL_TablesCallback(Database db, DBResultSet results, const char[] error, any data) {
	
	if (db == null || results == null) {
		
		ThrowError("[Discord Mover] %s", error);
		
	}
	
	delete results;
	
}

/* Command */

public Action CMD_Move(int client, int args) {
	
	char arg1[16]; char arg2[16];
	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));
	
	if (!args) {
		
		CReplyToCommand(client, "%s %t", PREFIX, "Command Usage");
		return Plugin_Handled;
		
	}
	
	if (!g_bCommandEnabled) {
		
		CReplyToCommand(client, "%s %t", PREFIX, "Command Blocked", cvCooldown.IntValue);
		return Plugin_Handled;
		
	}
	
	if (StrEqual(arg1, "teams")) {
		
		CReplyToCommand(client, "%s %t", PREFIX, "Moving Teams");
		g_bCommandEnabled = false;
		CreateTimer(cvCooldown.FloatValue, EnableCommand);
		MoveTeams();
		return Plugin_Handled;
		
	}
	
	if (StrEqual(arg1, "pregame")) {
		
		CReplyToCommand(client, "%s %t", PREFIX, "Moving Pregame");
		g_bCommandEnabled = false;
		CreateTimer(cvCooldown.FloatValue, EnableCommand);
		MovePregame();
		return Plugin_Handled;
		
	}
	
	int target = FindTarget(client, arg1, true, false);
	
	if (target == -1) {
		
		return Plugin_Handled;
		
	}
	
	int userid = GetClientUserId(target);
	
	if (!StrEqual(arg2, "red") && !StrEqual(arg2, "blu") && !StrEqual(arg2, "pregame")) {
		
		CReplyToCommand(client, "%s %t", PREFIX, "Command Usage");
		return Plugin_Handled;
		
	}
	
	char name[32], team[16];
	GetClientName(target, name, sizeof(name));
	
	switch (arg2[0]) {
		
		case 'b':Format(team, sizeof(team), "BLU");
		case 'r':Format(team, sizeof(team), "RED");
		case 'p':Format(team, sizeof(team), "Pre-game");
		
	}
	
	CReplyToCommand(client, "%s %t", PREFIX, "Moving User", name, team);
	MoveUser(userid, arg2);
	
	return Plugin_Handled;
	
}

public Action EnableCommand(Handle timer) {
	
	g_bCommandEnabled = true;
	return Plugin_Handled;
	
}

/* Move Teams */

void MoveTeams() {
	
	teams = new JSONObject();
	RED = new JSONArray();
	BLU = new JSONArray();
	
	arr.RED = new ArrayList(ByteCountToCells(MIN_CELL_LEN));
	arr.BLU = new ArrayList(ByteCountToCells(MIN_CELL_LEN));
	
	char steamid[32];
	
	for (int i = 1; i < MaxClients; i++) {
		
		if (IsClientInGame(i) && !IsFakeClient(i)) {
			
			TFTeam team = TF2_GetClientTeam(i);
			if (team != TFTeam_Spectator && team != TFTeam_Unassigned) {
				
				GetClientAuthId(i, AuthId_SteamID64, steamid, sizeof(steamid));
				team == TFTeam_Red ? arr.RED.PushString(steamid) : arr.BLU.PushString(steamid);
				
			}
			
		}
		
	}
	
	FormatTeamsQueries();
	
}

void FormatTeamsQueries() {
	
	char REDquery[512], BLUquery[512], first1[32], first2[32], buf1[32], buf2[32];
	
	if (arr.RED.Length != 0) {
		
		arr.RED.GetString(0, first1, sizeof(first1));
		
	}
	
	if (arr.BLU.Length != 0) {
		
		arr.BLU.GetString(0, first2, sizeof(first2));
		
	}
	
	Format(REDquery, sizeof(REDquery), "SELECT discord_id FROM discordmover WHERE steam_id IN ('%s'", first1);
	Format(BLUquery, sizeof(BLUquery), "SELECT discord_id FROM discordmover WHERE steam_id IN ('%s'", first2);
	
	for (int i = 1; i < arr.RED.Length; i++) {
		
		arr.RED.GetString(i, buf2, sizeof(buf2));
		Format(buf1, sizeof(buf1), ", '%s'", buf2);
		StrCat(REDquery, sizeof(REDquery), buf1);
		
	}
	
	for (int i = 1; i < arr.BLU.Length; i++) {
		
		arr.BLU.GetString(i, buf2, sizeof(buf2));
		Format(buf1, sizeof(buf1), ", '%s'", buf2);
		StrCat(BLUquery, sizeof(BLUquery), buf1);
		
	}
	
	StrCat(REDquery, sizeof(REDquery), ");");
	StrCat(BLUquery, sizeof(BLUquery), ");");
	
	g_Database.Query(SQL_REDCallback, REDquery);
	g_Database.Query(SQL_BLUCallback, BLUquery);
	
	delete arr.RED;
	delete arr.BLU;
	
}

public void SQL_REDCallback(Database db, DBResultSet results, const char[] error, any data) {
	
	if (db == null || results == null) {
		
		ThrowError("[Discord Mover] %s", error);
		delete results;
		return;
		
	}
	
	if (!results.FetchRow()) {
		
		delete results;
		intg++;
		PrepareJSON();
		return;
		
	}
	
	char discordID[32];
	int discordIDCol;
	
	do {
		
		results.FieldNameToNum("discord_id", discordIDCol);
		results.FetchString(discordIDCol, discordID, sizeof(discordID));
		
		RED.PushString(discordID);
		
	} while (results.FetchRow());
	
	intg++;
	PrepareJSON();
	delete results;
	
}

public void SQL_BLUCallback(Database db, DBResultSet results, const char[] error, any data) {
	
	if (db == null || results == null) {
		
		ThrowError("[Discord Mover] %s", error);
		delete results;
		return;
		
	}
	
	if (!results.FetchRow()) {
		
		delete results;
		intg++;
		PrepareJSON();
		return;
		
	}
	
	char discordID[32];
	int discordIDCol;
	
	do {
		
		results.FieldNameToNum("discord_id", discordIDCol);
		results.FetchString(discordIDCol, discordID, sizeof(discordID));
		
		BLU.PushString(discordID);
		
	} while (results.FetchRow());
	
	intg++;
	PrepareJSON();
	delete results;
	
}

public Action PrepareJSON() {
	
	if (intg == 2) {
		
		teams.Set("RED", RED);
		teams.Set("BLU", BLU);
		teams.SetString("instruction", "teams");
		
		SendJSON(teams);
		
		delete teams;
		delete RED;
		delete BLU;
		
		intg = 0;
		
	}
	
}

/* Move Pregame */

void MovePregame() {
	
	pregame = new JSONObject();
	pregame.SetString("instruction", "pregame");
	
	SendJSON(pregame);
	delete pregame;
	
}

/* Move User */

void MoveUser(int userid, char[] arg2) {
	
	user = new JSONObject();
	
	int client = GetClientOfUserId(userid);
	
	char steamid[32];
	GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));
	
	DataPack pack = new DataPack();
	pack.WriteString(arg2);
	
	char query[256];
	Format(query, sizeof(query), "SELECT discord_id FROM discordmover WHERE steam_id='%s';", steamid);
	g_Database.Query(SQL_MoveUserCallback, query, pack);
	
}

public void SQL_MoveUserCallback(Database db, DBResultSet results, const char[] error, DataPack pack) {
	
	pack.Reset();
	char channel[16];
	pack.ReadString(channel, sizeof(channel));
	delete pack;
	
	if (db == null || results == null) {
		
		ThrowError("[Discord Mover] %s", error);
		delete results;
		return;
		
	}
	
	if (!results.FetchRow()) {
		
		delete results;
		return;
		
	}
	
	char discordID[32];
	int discordIDCol;
	
	results.FieldNameToNum("discord_id", discordIDCol);
	results.FetchString(discordIDCol, discordID, sizeof(discordID));
	
	user.SetString("user", discordID);
	user.SetString("team", channel);
	user.SetString("instruction", "user");
	
	SendJSON(user);
	
	delete results;
	delete user;
	
}

public void SendJSON(JSONObject obj) {
	
	HTTPClient http = new HTTPClient("http://186.158.115.92:3000");
	http.SetHeader("Accept", "application/json");
	http.SetHeader("Content-Type", "application/json");
	
	http.Post("teams", obj, OnJSONReceived);
	
	delete http;
	
}

void OnJSONReceived(HTTPResponse response, any data) {
	
	if (response.Status != HTTPStatus_OK || response.Data == null) {
		
		CPrintToChatAll("%s %t", PREFIX, "JSON Error");
		PrintToServer("[Discord Mover] Failed to send JSON.");
		return;
		
	}
	
} 
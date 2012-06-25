/*****************************************************************


C O M P I L E   O P T I O N S


*****************************************************************/
// enforce semicolons after each code statement
#pragma semicolon 1

/*****************************************************************


P L U G I N   I N C L U D E S


*****************************************************************/
#include <sourcemod>
#include <sdktools>
#include <smlib>
#include <smlib/pluginmanager>

/*****************************************************************


P L U G I N   I N F O


*****************************************************************/
public Plugin:myinfo = {
	name 						= "Adv Status",
	author 						= "Chanz",
	description 				= "Fixes the basic status command for players and extends it for admins.",
	version 					= "1.0",
	url 						= "http://bcserv.eu/"
}

/*****************************************************************


		P L U G I N   D E F I N E S


*****************************************************************/
#define MAX_CLIENT_DATA 		50
#define MAX_REASON_LENGTH 		255
#define MAX_NETWORKID_LENGTH 	16
#define MAX_IP_LENGTH 			21
#define SPERATOR 				"--------------------------------------------------------------------------------------------------------------------------------------"

/*****************************************************************


		G L O B A L   V A R S


*****************************************************************/
//Use a good notation, constants for arrays, initialize everything that has nothing to do with clients!
//If you use something which requires client index init it within the function Client_InitVars (look below)
//Example: Bad: "decl servertime" Good: "new g_iServerTime = 0"
//Example client settings: Bad: "decl saveclientname[33][32] Good: "new g_szClientName[MAXPLAYERS+1][MAX_NAME_LENGTH];" -> later in Client_InitVars: GetClientName(client,g_szClientName,sizeof(g_szClientName));

//CVar
new Handle:g_cvarNeededFlagForCommand 	= INVALID_HANDLE;

//Foreign Cvar
new Handle:g_cvarNextMap 				= INVALID_HANDLE;
new Handle:g_cvarFloodTime 				= INVALID_HANDLE;

//Cvar Runtime optimizer
new g_iPlugin_NeededFlagForCommand = ADMFLAG_ROOT;
new Float:g_fPlugin_FloodTime = 0.0;

//Clients
enum ClientData {
	
	ClientData_UserId,
	bool:ClientData_IsFakeClient,
	String:ClientData_Name[MAX_NAME_LENGTH],
	String:ClientData_Auth[MAX_STEAMAUTH_LENGTH],
	String:ClientData_IP[MAX_IP_LENGTH],
	String:ClientData_Reason[MAX_REASON_LENGTH],
	String:ClientData_NetworkId[MAX_NETWORKID_LENGTH]
};

new g_cdClients[MAX_CLIENT_DATA][ClientData];
new g_iClientData_Pos = 0;

new g_cdClientsLive[MAXPLAYERS+1][ClientData];

new String:g_szClients_NameChangeHistory[10][128];

//Server
new Float:g_fLastCommand = 0.0;

/*****************************************************************


		F O R W A R D   P U B L I C S


*****************************************************************/
public OnPluginStart() {
	
	//Init for smlib
	PluginManager_Initialize("advstatus","[AdvStatus] ",false);
	
	//Other translations
	LoadTranslations("common.phrases");
	
	//Command Hooks (AddCommandListener) (If the command already exists, like the command kill, then hook it!)
	//AddCommandListener(Command_Status,"status");
	
	//Register New Commands (RegConsoleCmd) (If the command doesn't exist, hook it here)
	PluginManager_RegConsoleCmd("sm_status",Command_Status,"Fixed and improved status command");
	
	//Register Admin Commands (RegAdminCmd)
	
	
	//Cvars: Create a global handle variable.
	//Example: g_cvarEnable = CreateConVarEx("enable","1","example ConVar");
	g_cvarNeededFlagForCommand = PluginManager_CreateConvar("neededflag","z","Needed AdminFlag to see IPs in output of command 'sm_status'",FCVAR_PLUGIN);
	
	//Native Convars
	g_cvarNextMap = PluginManager_FindConVar("sm_nextmap", false);
	
	//Event Hooks
	PluginManager_HookEvent("player_disconnect", Event_Player_Disconnect);
	PluginManager_HookEvent("player_changename", Event_Player_Changename);
}

public OnMapStart() {
	
	// hax against valvefail (thx psychonic for fix)
	if(GuessSDKVersion() == SOURCE_SDK_EPISODE2VALVE){
		SetConVarString(Plugin_VersionCvar, Plugin_Version);
	}
	
	g_fLastCommand = GetGameTime();
}

public OnConfigsExecuted(){
	
	//Set your ConVar runtime optimizers here
	//Example: g_iPlugin_Enable = GetConVarInt(g_cvarEnable);
	new String:cvar[11];
	new AdminFlag:flag = Admin_Root;
	GetConVarString(g_cvarNeededFlagForCommand,cvar,sizeof(cvar));
	FindFlagByChar(cvar[0],flag);
	g_iPlugin_NeededFlagForCommand = FlagToBit(flag);
	
	g_cvarFloodTime = FindConVar("sm_flood_time");
	g_fPlugin_FloodTime = GetConVarFloat(g_cvarFloodTime);
	
	//Hook ConVar Change
	HookConVarChange(g_cvarFloodTime,ConVarChange_FloodTime);
	HookConVarChange(g_cvarNeededFlagForCommand,ConVarChange_NeededFlag);
	
	//Mind: this is only here for late load, since on map change or server start, there isn't any client.
	//Remove it if you don't need it.
	Client_InitializeAll();
}

public OnClientConnected(client){
	
	Client_Initialize(client);
}

public OnClientPostAdminCheck(client){
	
	Client_Initialize(client);
}

/****************************************************************


		C A L L B A C K   F U N C T I O N S


****************************************************************/
public Action:Event_Player_Disconnect(Handle:event, const String:name[], bool:dontBroadcast){
	
	if(g_iClientData_Pos < MAX_CLIENT_DATA-1){
		g_iClientData_Pos++;
	}
	else {
		g_iClientData_Pos = 0;
	}
	
	g_cdClients[g_iClientData_Pos][ClientData_UserId] = GetEventInt(event,"userid");
	GetEventString(event,"name",g_cdClients[g_iClientData_Pos][ClientData_Name],MAX_NAME_LENGTH);
	GetEventString(event,"reason",g_cdClients[g_iClientData_Pos][ClientData_Reason],MAX_REASON_LENGTH);
	GetEventString(event,"networkid",g_cdClients[g_iClientData_Pos][ClientData_NetworkId],MAX_NETWORKID_LENGTH);
	
	LOOP_CLIENTS(client,CLIENTFILTER_ALL){
		
		if(g_cdClientsLive[client][ClientData_UserId] == g_cdClients[g_iClientData_Pos][ClientData_UserId]){
			
			if(g_cdClientsLive[client][ClientData_IsFakeClient]){
				
				strcopy(g_cdClients[g_iClientData_Pos][ClientData_Auth],MAX_STEAMAUTH_LENGTH,"(Bot)");
				strcopy(g_cdClients[g_iClientData_Pos][ClientData_IP],MAX_IP_LENGTH,"localhost");
			}
			else {
				
				strcopy(g_cdClients[g_iClientData_Pos][ClientData_Auth],MAX_STEAMAUTH_LENGTH,g_cdClientsLive[client][ClientData_Auth]);
				strcopy(g_cdClients[g_iClientData_Pos][ClientData_IP],MAX_IP_LENGTH,g_cdClientsLive[client][ClientData_IP]);
			}
			break;
		}
	}
	return Plugin_Continue;
}

public Action:Event_Player_Changename(Handle:event, const String:name[], bool:dontBroadcast){
	
	new clientUserId = GetEventInt(event,"userid");
	
	if(clientUserId == -1){
		return Plugin_Continue;
	}
	
	new client = GetClientOfUserId(clientUserId);
	
	if(!Client_IsValid(client)){
		return Plugin_Continue;
	}
	
	//shift
	for(new i=sizeof(g_szClients_NameChangeHistory)-1;i>0;i--){
		
		strcopy(g_szClients_NameChangeHistory[i],sizeof(g_szClients_NameChangeHistory[]),g_szClients_NameChangeHistory[i-1]);
	}
	
	new String:steamId[MAX_STEAMAUTH_LENGTH];
	GetClientAuthString(client,steamId,sizeof(steamId));
	
	new String:oldName[MAX_NAME_LENGTH];
	new String:newName[MAX_NAME_LENGTH];
	GetEventString(event,"oldname",oldName,sizeof(oldName));
	GetEventString(event,"newname",newName,sizeof(newName));
	
	Format(g_szClients_NameChangeHistory[0],sizeof(g_szClients_NameChangeHistory[]),"  # %6.6d | %-21.21s | %32.32s   ->   %s",clientUserId,steamId,oldName,newName);
	
	return Plugin_Continue;
}


public ConVarChange_NeededFlag(Handle:cvar, const String:oldVal[], const String:newVal[]){
	
	new AdminFlag:flag = Admin_Root;
	
	if(!FindFlagByChar(newVal[0],flag)){
		
		LogError("'%s' isn't a flag",newVal);
	}
	else {
		
		g_iPlugin_NeededFlagForCommand = FlagToBit(flag);
	}
}

public ConVarChange_FloodTime(Handle:cvar, const String:oldVal[], const String:newVal[]){
	g_fPlugin_FloodTime = StringToFloat(newVal);
}

//public Action:Command_Status(client, const String:command[], argc){
public Action:Command_Status(client, argc){
	
	if(g_fLastCommand > GetGameTime()){
		
		Client_Reply(client,"[SM] %t","Flooding the server");
		return Plugin_Handled;
	}
	
	if(g_cvarFloodTime != INVALID_HANDLE){
		
		g_fLastCommand = GetGameTime() + g_fPlugin_FloodTime;
	}
	else {
		
		g_fLastCommand = GetGameTime() + 0.75;
	}
	
	
	Client_Print(client,ClientHudPrint_Console, "\n\n");
	Server_PrintStatus(client);
	
	new bool:isAdmin = ((client == 0) ? true : Client_HasAdminFlags(client,g_iPlugin_NeededFlagForCommand));
	
	if(argc != 0){
		
		new target = -1;
		
		new String:argString[MAX_TARGET_LENGTH];
		GetCmdArgString(argString,sizeof(argString));
		target = FindTarget(client,argString);
		
		Client_PrintLatestNameChanges(client);
		
		Client_PrintPlayers(client,target,isAdmin);
	}
	else {
		
		if(isAdmin){
			
			Client_PrintDisconectedPlayers(client,MAX_CLIENT_DATA,true);
		}
		else {
			
			Client_PrintDisconectedPlayers(client,10,false);
		}
		
		Client_PrintLatestNameChanges(client);
		
		Client_PrintPlayers(client,-1,isAdmin);
	}
	
	return Plugin_Handled;
}

/*****************************************************************


		P L U G I N   F U N C T I O N S


*****************************************************************/
stock Client_PrintLatestNameChanges(client,ClientHudPrint:destination=ClientHudPrint_Console){
	
	Client_Print(client,destination, "[%s]",SPERATOR);
	Client_Print(client,ClientHudPrint_Console,"  L a t e s t   n a m e   c h a n g e s");
	Client_Print(client,destination, "[%s]",SPERATOR);
	
	Client_Print(client,destination,"  # UserId | SteamId               | Old name                           ->   New name");
	
	for(new i=0;i<sizeof(g_szClients_NameChangeHistory);i++){
		
		if(g_szClients_NameChangeHistory[i][0] == '\0'){
			continue;
		}
		Client_Print(client,destination,g_szClients_NameChangeHistory[i]);
	}
	Client_Print(client,destination, "\n");
}


stock Client_PrintDisconectedPlayers(client,num,bool:showIPs=false,ClientHudPrint:destination=ClientHudPrint_Console){
	
	Client_Print(client,destination, "[%s]",SPERATOR);
	Client_Print(client,ClientHudPrint_Console,"  D i s c o n n e c t e d   u s e r s");
	Client_Print(client,destination, "[%s]",SPERATOR);
	
	new pos = g_iClientData_Pos;
	if(g_cdClients[pos][ClientData_UserId] == 0){
		Client_Print(client,destination,"  -List Empty-");
	}
	else {
		
		if(showIPs){
			
			Client_Print(client,destination,"  # UserId | SteamId               | IP              | # UserId | Name");
			
			for(new count=0;count<MAX_CLIENT_DATA;count++){
				
				if(pos < MAX_CLIENT_DATA-1){
					pos++;
				}
				else {
					pos = 0;
				}
				
				if(g_cdClients[pos][ClientData_UserId] == 0){
					continue;
				}
				
				Client_Print(
					client,
					destination,
					"  # %6.6d | %-21.21s | %-15.15s | # %6.6d | %s",
					g_cdClients[pos][ClientData_UserId],
					g_cdClients[pos][ClientData_Auth],
					g_cdClients[pos][ClientData_IP],
					g_cdClients[pos][ClientData_UserId],
					g_cdClients[pos][ClientData_Name]
				);
			}
		}
		else {
			
			Client_Print(client,destination,"  # UserId | SteamId               | # UserId | Name");
			
			for(new count=0;count<MAX_CLIENT_DATA;count++){
				
				if(pos < MAX_CLIENT_DATA-1){
					pos++;
				}
				else {
					pos = 0;
				}
				
				if(g_cdClients[pos][ClientData_UserId] == 0){
					continue;
				}
				
				Client_Print(
					client,
					destination,
					"  # %6.6d | %-21.21s | # %6.6d | %s",
					g_cdClients[pos][ClientData_UserId],
					g_cdClients[pos][ClientData_Auth],
					g_cdClients[pos][ClientData_UserId],
					g_cdClients[pos][ClientData_Name]
				);
			}
		}
	}
	Client_Print(client,destination, "\n");
}

Client_PrintPlayers(client,target=-1,bool:showIPs=false,ClientHudPrint:destination=ClientHudPrint_Console){
	
	Client_Print(client,destination, "[%s]",SPERATOR);
	Client_Print(client,ClientHudPrint_Console,"  C o n n e c t e d   u s e r s");
	Client_Print(client,destination, "[%s]",SPERATOR);
	
	if(showIPs){
		Client_Print(client,destination,"  # UserId | SteamId               | IP              | Rate   | Cmdrate | Updaterate | Interp  | Choke  | # UserId | Name");
	}
	else {
		Client_Print(client,destination,"  # UserId | SteamId               | Rate   | Cmdrate | Updaterate | Interp  | Choke  | # UserId | Name");
	}
	
	if(target == -1){
		
		LOOP_CLIENTS(player,CLIENTFILTER_INGAMEAUTH){
			
			Client_PrintStatus(client,player,showIPs,destination);
		}
	}
	else {
		
		Client_PrintStatus(client,target,showIPs,destination);
	}
	Client_Print(client,destination, "\n");
}


stock Client_PrintStatus(client,target,bool:showIPs=false,ClientHudPrint:destination=ClientHudPrint_Console){
	
	new targetUserId = GetClientUserId(target);
	new String:targetName[32];
	GetClientName(target,targetName,sizeof(targetName));
	new String:targetSteamId[MAX_STEAMAUTH_LENGTH];
	new String:targetIP[21];
	new String:interp[10],String:update[10],String:cmd[10],String:rate[10];
	new Float:choke = -1.0;
	if(IsFakeClient(target)){
		
		strcopy(targetSteamId,sizeof(targetSteamId),"(Bot)");
		strcopy(targetIP,sizeof(targetIP),"localhost");
		strcopy(rate,sizeof(rate),"N/A");
		strcopy(cmd,sizeof(cmd),"N/A");
		strcopy(update,sizeof(update),"N/A");
		strcopy(interp,sizeof(interp),"N/A");
		choke = 0.0;
	}
	else {
		
		GetClientAuthString(target,targetSteamId,sizeof(targetSteamId));
		GetClientIP(target,targetIP,sizeof(targetIP));
		GetClientInfo(target, "rate", rate, 9);
		GetClientInfo(target, "cl_cmdrate",cmd, 9);
		GetClientInfo(target, "cl_updaterate", update, 9);
		GetClientInfo(target, "cl_interp", interp, 9);
		choke = GetClientAvgChoke(target,NetFlow_Both)*100.0;
	}
	
	if(showIPs){
		
		Client_Print(client,destination,"  # %6.6d | %-21.21s | %-15.15s | %6.6d | %7.7d | %10.10d | %6.5f | %6.2f | # %6.6d | %s",
			targetUserId,
			targetSteamId,
			targetIP,
			StringToInt(rate),
			StringToInt(cmd),
			StringToInt(update),
			StringToFloat(interp),
			choke,
			targetUserId,
			targetName
		);
	}
	else {
		Client_Print(client,destination,"  # %6.6d | %-21.21s | %6.6d | %7.7d | %10.10d | %6.5f | %6.2f | # %6.6d | %s",
			targetUserId,
			targetSteamId,
			StringToInt(rate),
			StringToInt(cmd),
			StringToInt(update),
			StringToFloat(interp),
			choke,
			targetUserId,
			targetName
		);
	}
}

stock Server_PrintStatus(client,ClientHudPrint:destination=ClientHudPrint_Console){
	
	Client_Print(client,destination, "[%s]",SPERATOR);
	Client_Print(client,ClientHudPrint_Console,"  S e r v e r   i n f o r m a t i o n");
	Client_Print(client,destination, "[%s]",SPERATOR);
	
	new String:hostname[256];
	Server_GetHostName(hostname,sizeof(hostname));
	
	new playersOnline = GetClientCount();
	new playersConnecting = GetClientCount(false);
	playersConnecting -= playersOnline;
	
	new String:currentMap[64];
	GetCurrentMap(currentMap, sizeof(currentMap));
	
	new String:nextMap[128] = "N/A";
	if(g_cvarNextMap != INVALID_HANDLE){
		GetConVarString(g_cvarNextMap, nextMap, sizeof(nextMap));
	}
	
	new String:ip[20];
	Server_GetIPString(ip,sizeof(ip),true);
	
	Client_Print(client,destination, "  Hostname:   %s",hostname);
	Client_Print(client,destination, "  UDP/IP:     %s:%d",ip,Server_GetPort());
	Client_Print(client,destination, "  Players:    %d/%d (%d connecting) Total: %d",playersOnline,MaxClients,playersConnecting,Server_GetTotalPlayers());
	Client_Print(client,destination, "  CurrentMap: '%s' (Next: '%s')",currentMap,nextMap);
	
	Client_Print(client,destination, "\n");
}


stock Server_GetStats(
	&Float:cpuUsage=0.0,
	&Float:in=0.0,
	&Float:out=0.0,
	&uptime=0,
	&users=0,
	&Float:fps=0.0,
	&players=0
) {
	decl String:buffer[150];
	ServerCommandEx(buffer, sizeof(buffer), "stats");
	
	strcopy(buffer, sizeof(buffer), buffer[FindCharInString(buffer, '\n')+1]);
	
	decl String:part[16];

	new pos, index, count=0;
	do {
		
		index = SplitString(buffer[pos], " ", part, sizeof(part));
		
		if (index == -1) {
			strcopy(part, sizeof(part), buffer[pos]);
		}
		
		pos += index;
		
		if (part[0] == '\0') {
			continue;
		}
		
		switch (count) {
			
			case 0:cpuUsage 	= StringToFloat	(part);
			case 1:in 			= StringToFloat	(part);
			case 2:out			= StringToFloat	(part);
			case 3:uptime 		= StringToInt	(part);
			case 4:users 		= StringToInt	(part);
			case 5:fps 			= StringToFloat	(part);
			case 6:players 		= StringToInt	(part);
		}
		
		count++;
		
	} while (index != -1);
}

stock Server_GetTotalPlayers(){
	
	new totalPlayers = 0;
	new usrIDTemp = -1;
	LOOP_CLIENTS(client,CLIENTFILTER_INGAME){
		
		usrIDTemp = GetClientUserId(client);
		if (usrIDTemp > totalPlayers){
			
			totalPlayers = usrIDTemp;
		}
	}
	for(new i=0;i<MAX_CLIENT_DATA;i++){
		
		if (g_cdClients[i][ClientData_UserId] > totalPlayers){
			
			totalPlayers = g_cdClients[i][ClientData_UserId];
		}
	}
	return totalPlayers;
}

stock Client_InitializeAll(){
	
	for(new client=1;client<=MaxClients;client++){
		
		Client_Initialize(client);
	}
}

stock Client_Initialize(client){
	
	//Variables
	Client_InitializeVariables(client);
	
	
	//Functions
	
	
	//Functions where the player needs to be in game
	if(!IsClientInGame(client) || !IsClientAuthorized(client)){
		return;
	}
	
	g_cdClientsLive[client][ClientData_UserId] = GetClientUserId(client);
	g_cdClientsLive[client][ClientData_IsFakeClient] = IsFakeClient(client);
	GetClientIP(client,g_cdClientsLive[client][ClientData_IP],MAX_IP_LENGTH);
	GetClientAuthString(client,g_cdClientsLive[client][ClientData_Auth],MAX_STEAMAUTH_LENGTH);
}

stock Client_InitializeVariables(client){
	
	//Plugin Client Vars
	
}



#include <amxmodx>
#include <reapi>

#define PLUGIN  "Pug Mod"
#define VERSION "2.0"
#define AUTHOR  "Sugisaki"

#define SND_COUNTER_BEEP "UI/buttonrollover.wav"
#define SND_STINGER = "pug/cs_stinger.wav"

#define TASK_READY	451
#define TASK_VOTE 	452
#define TASK_INTERMISSION 453

#define task_remove(%0) if(task_exists(%0)) { remove_task(%0); }

#define SetReadyBit(%1)      (g_bReady |= (1<<(%1&31)))
#define ClearReadyBit(%1)    (g_bReady &= ~(1 <<(%1&31)))
#define IsReadyBit(%1)    (g_bReady & (1<<(%1&31)))
#define CleanBit(%1) %1 = 0

new Array:g_maps
new Trie:g_commands
new Trie:g_votes
new HookChain:PreThink
new HookChain:g_MakeBomber
new bool:is_intermission = false
new bool:overtime = false
new WinStatus:g_tPugWin
new Array:g_aRegisterVotes = Invalid_Array

enum _:REGISTER_VOTES
{
	FUNC,
	VOTENAME[32],
	Array:OPTIONS,
	PLID
}

new g_iMapType
new g_iLegacyChat
new g_iMaxPlayers
new g_pPlayers
new g_iReadyCount
new g_iHalfRoundNum
new g_pVoteCount
new g_pVoteMap
new g_pMaxSpeed
new g_pIntermissionCountdown
new g_pMaxRounds
new g_pOverTime
new g_pOverTimeMaxRounds
new g_menu
new g_iCountDown
new g_pOverTimeMoney
new g_pOverTimeIntermissionCD
new g_iCurrentVote = 0

new Sync1
new Sync2
new Sync3
new Sync4
new g_bReady
enum _:CVARS
{
	NAME[40],
	VALUE[10]
}
new cvar_warmup[][CVARS] = 
{
	{"sv_allowspectators", "1"},
	{"mp_forcerespawn", "1"},
	{"mp_auto_reload_weapons", "1"},
	{"mp_auto_join_team", "0"},
	{"mp_autoteambalance", "0"},
	{"mp_limitteams", "0"},
	{"mp_freezetime", "0"},
	{"mp_timelimit", "0"},
	{"mp_refill_bpammo_weapons", "3"},
	{"mp_startmoney", "16000"},
	{"sv_alltalk", "1"},
	{"mp_buytime", "-1"},
	{"mp_consistency", "1"},
	{"mp_flashlight", "0"},
	{"mp_forcechasecam", "0"},
	{"mp_forcecamera", "0"},
	{"mp_roundtime", "0"},
	{"mp_friendlyfire", "0"},
	{"sv_timeout", "20"},
	{"mp_roundrespawn_time", "0"},
	{"mp_item_staytime", "0"},
	{"mp_respawn_immunitytime", "5"},
	{"sv_rehlds_stringcmdrate_burst_punish", "-1"},
	{"sv_rehlds_stringcmdrate_avg_punish ", "-1"},
	{"sv_rehlds_movecmdrate_burst_punish", "-1"},
	{"sv_rehlds_movecmdrate_avg_punish", "-1"},
	{"sv_maxspeed", "320"},
	{"mp_round_infinite", "acdefg"},
	{"sv_rehlds_force_dlmax", "1"}
}
new cvar_pug[][CVARS] = 
{
	{"mp_round_infinite", "0"},
	{"mp_forcerespawn", "0"},
	{"mp_startmoney", "800"},
	{"mp_limitteams", "0"},
	{"mp_refill_bpammo_weapons", "0"},
	{"mp_buytime", "0.25"},
	{"sv_maxspeed", "320"},
	{"mp_forcechasecam", "2"},
	{"mp_forcecamera", "2"},
	{"mp_freezetime", "15"},
	{"mp_roundtime", "1.75"},
	{"mp_auto_join_team", "0"},
	{"mp_roundrespawn_time", "10"},
	{"mp_item_staytime", "300"},
	{"mp_respawn_immunitytime", "0"}
}

native PugRegisterCommand(name[], fwd[]);
enum PUG_STATE
{
	NO_ALIVE = 0,
	VOTING,
	COMMENCING,
	ALIVE,
	ENDING
}
new PUG_STATE:pug_state = NO_ALIVE
public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	DisableHookChain((PreThink = RegisterHookChain(RG_CBasePlayer_PreThink, "OnPlayerThink", 1)))
	DisableHookChain((g_MakeBomber = RegisterHookChain(RG_CBasePlayer_MakeBomber, "OnMakeBomber", 0)))
	RegisterHookChain(RG_CSGameRules_RestartRound, "OnStartRound", 0)
	RegisterHookChain(RG_CSGameRules_RestartRound, "OnStartRoundPost", 1)
	RegisterHookChain(RG_RoundEnd, "OnRoundEndPre", 0)
	RegisterHookChain(RG_HandleMenu_ChooseTeam, "OnChooseTeam")

	RegisterCvars()
	LoadMaps()

	PugRegisterCommand("listo", "OnSetReady")
	PugRegisterCommand("ready", "OnSetReady")
	PugRegisterCommand("unready", "OnUnReady")
	PugRegisterCommand("nolisto", "OnUnReady")
}
public plugin_natives()
{
	register_native("PugRegisterCommand", "_register_command")
	register_native("PugRegisterVote", "_register_vote")
	register_native("PugRegisterVoteOption", "_register_vote_option")
	register_native("PugNextVote", "NextVote")
}
public plugin_precache()
{
	precache_sound(SND_COUNTER_BEEP)
}
public _register_vote(pl, pr)
{
	new name[32], fwd[32]
	get_string(1, name, charsmax(name))
	get_string(2, fwd, charsmax(fwd))
	trim(name)
	trim(fwd)
	if(!name[0] || !fwd[0])
	{
		new pluginname[32]
		get_plugin(pl, pluginname, charsmax(pluginname))
		log_amx("[%s] No se pudo registrar una votacion [%s]", PLUGIN, pluginname)
		return;
	}
	if(get_func_id(fwd, pl) == -1)
	{
		new pluginname[32]
		get_plugin(pl, pluginname, charsmax(pluginname))
		log_amx("[%s] Funcion %s no existe [%s]", PLUGIN, fwd, pluginname)
		return
	}
	if(g_aRegisterVotes == Invalid_Array)
	{
		g_aRegisterVotes = ArrayCreate(REGISTER_VOTES)
	}
	new array[REGISTER_VOTES]
	array[FUNC] = CreateOneForward(pl, fwd, FP_CELL);
	array[OPTIONS] = Invalid_Array
	copy(array[VOTENAME], charsmax(array[VOTENAME]), name)
	ArrayPushArray(g_aRegisterVotes, array)
}
public _register_vote_option(pl, pr)
{
	new option[32], array[REGISTER_VOTES]
	if(!ArraySize(g_aRegisterVotes))
	{
		log_amx("[%s] No hay votaciones registradas", PLUGIN)
		return
	}
	get_string(1, option, charsmax(option))
	trim(option)
	if(!option[0])
	{
		log_amx("[%s] Opcion vacia", PLUGIN)
		return;
	}
	new id = ArraySize(g_aRegisterVotes) - 1
	ArrayGetArray(g_aRegisterVotes, id, array)
	if(array[OPTIONS] == Invalid_Array)
	{
		array[OPTIONS] = ArrayCreate(32)
	}
	ArrayPushString(array[OPTIONS], option)
	ArraySetArray(g_aRegisterVotes, id, array)
}
public _register_command(pl, pr)
{
	new name[32], fwd[32]
	get_string(1, name, charsmax(name))
	get_string(2, fwd, charsmax(fwd))
	trim(name)
	trim(fwd)
	if(!name[0] || !fwd[0])
	{
		return;
	}
	format(name, charsmax(name), ".%s", name)
	if(get_pcvar_num(g_iLegacyChat))
	{
		register_clcmd(fmt("say %s", name), fwd)
	}
	else
	{
		if(!g_commands)
		{
			g_commands = TrieCreate()
		}
		if(TrieKeyExists(g_commands, name))
		{
			log_amx("[%s] Comando %s ya existe", PLUGIN, name)
			return;
		}
		TrieSetCell(g_commands, name, CreateOneForward(pl, fwd, FP_CELL))
	}
}
public OnConfigsExecuted()
{
	StartPregame()
}
RegisterCvars()
{
	g_iMaxPlayers					=		get_maxplayers()
	g_iMapType						=		register_cvar("pug_maptype", "1")
	g_iLegacyChat					=		register_cvar("pug_legacychat", "0")
	g_pPlayers						=		register_cvar("pug_players", "10")
	g_pVoteCount					=		register_cvar("pug_vote_countdown", "15")
	g_pVoteMap						=		register_cvar("pug_vote_map", "1")
	g_pMaxRounds					=		register_cvar("pug_maxrounds", "30")
	g_pMaxRounds					=		register_cvar("pug_maxrounds", "30")
	g_pOverTime						=		register_cvar("pug_overtime", "0")
	g_pOverTimeMaxRounds			=		register_cvar("pug_overtime_rounds", "6")
	g_pIntermissionCountdown		=		register_cvar("pug_intermission_countdown", "15")
	g_pOverTimeIntermissionCD		=		register_cvar("pug_overtime_intermission_cd", "10")
	g_pMaxSpeed						=		get_cvar_pointer("sv_maxspeed");
	g_pOverTimeMoney				=		register_cvar("pug_overtime_money", "10000")

	Sync1 = CreateHudSyncObj()
	Sync2 = CreateHudSyncObj()
	Sync3 = CreateHudSyncObj()
	Sync4 = CreateHudSyncObj()

	if(!get_pcvar_num(g_iLegacyChat))
	{
		register_clcmd("say", "OnSay")
		register_clcmd("say_team", "OnSay")
	}
}
LoadMaps()
{
	new currentmap[32]
	get_mapname(currentmap, charsmax(currentmap))
	if(!g_maps)
	{
		g_maps = ArrayCreate(32)
		ArrayPushString(g_maps, "Mantener Este Mapa")
	}
	if(get_pcvar_num(g_iMapType) > 0)
	{
		new fh;
		switch(get_pcvar_num(g_iMapType))
		{
			case 1 :
			{
				new configsdir[128]
				get_localinfo("amxx_configsdir", configsdir, charsmax(configsdir))
				add(configsdir, charsmax(configsdir), "/maps.ini");
				fh = fopen(configsdir, "r")
			}
			case 2: fh = fopen("mapcycle.txt", "r")
		}
		if(!fh)
		{
			set_pcvar_num(g_iMapType, 0);
			server_print("[%s] No se pudo abrir el archivo de mapas. Leyendo el directorio de mapas", PLUGIN)
			LoadMaps();
			return
		}
		new Line[32]
		while(!feof(fh))
		{
			fgets(fh, Line, charsmax(Line))
			replace(Line, charsmax(Line), ".bsp", "");
			trim(Line);
			if(!Line[0] || Line[0] == ';' || (Line[0] == '/' && Line[1] == '/') || Line[0] == '#' || !is_map_valid(Line) || equali(currentmap, Line))
			{
				continue;
			}
			ArrayPushString(g_maps, Line)
		}
		fclose(fh);
	}
	else
	{
		new file[32]
		new dh = open_dir("maps", file, charsmax(file))
		while(dh)
		{
			if((!equal(file, ".") || !equal(file, "..")))
			{
				if(strlen(file) > 4)
				{
					strtolower(file)
					if(equal(file[strlen(file) - 4], ".bsp"))
					{
						replace(file, charsmax(file), ".bsp", "");
						if(equali(currentmap, file))
						{
							continue;
						}
						ArrayPushString(g_maps, file);
					}
				}
			}
			if(!next_file(dh, file, charsmax(file)))
			{
				close_dir(dh)
				dh = false
				break;
			}
		}
	}
	server_print("[%s] %i Mapas cargados %s", PLUGIN, ArraySize(g_maps) - 1, get_pcvar_num(g_iMapType) == 0 ? "del directorio" : "del archivo");
}
StartPregame()
{
	pug_state = NO_ALIVE;
	task_remove(TASK_READY)
	task_remove(TASK_VOTE)
	task_remove(TASK_INTERMISSION)
	is_intermission = false
	g_iReadyCount = 0
	g_tPugWin = WINSTATUS_NONE;
	CleanBit(g_bReady)
	set_task(1.0, "OnUpdateHudReady", TASK_READY, _, _, "b")
	for(new i = 0 ; i < sizeof(cvar_warmup) ; i++)
	{
		set_cvar_string(cvar_warmup[i][NAME], cvar_warmup[i][VALUE])
	}
	rg_round_end(0.1, WINSTATUS_DRAW, ROUND_GAME_COMMENCE)
	set_member_game(m_bCompleteReset, true)
	EnableHookChain(g_MakeBomber)
}
stock rh_client_cmd(id, cmd[], any:...)
{
	new temp[128]
	vformat(temp, charsmax(temp), cmd, 3);
	message_begin(id > 0 ? MSG_ONE : MSG_ALL, SVC_DIRECTOR, _, id > 0 ? id : 0)
	write_byte(strlen(temp) + 2)
	write_byte(10)
	write_string(temp)
	message_end()
}
public OnSay(id)
{
	// type[4] == 't'
	static said[256], name[32], type[9], szMsg[32], team, i, bType
	read_argv(0, type, charsmax(type))
	read_args(said, charsmax(said))
	remove_quotes(said)
	
	trim(said)
	if(!said[0])
	{
		return PLUGIN_HANDLED
	}

	if(said[0] == '.')
	{
		read_argv(1, name, charsmax(name))
		strtolower(name)
		static fwd
		if(TrieGetCell(g_commands, name, fwd))
		{
			ExecuteForward(fwd, _, id)
		}
		else
		{
			client_print(id, print_chat, "[%s] Comando Invalido (%s)", PLUGIN, name)
		}
	}
	get_user_name(id, name, charsmax(name))
	team = get_member(i, m_iTeam)
	if(equal(type, "say_team"))
	{
		bType = true
	}
	else
	{
		bType = false
	}
	switch(team)
	{
		case 1:
		{
			if(is_user_alive(id))
			{
				if(bType)
				{
					copy(szMsg, charsmax(szMsg), "#Cstrike_Chat_T")
				}
				else
				{
					copy(szMsg, charsmax(szMsg), "#Cstrike_Chat_All")
				}
			}
			else
			{
				if(bType)
				{
					copy(szMsg, charsmax(szMsg), "#Cstrike_Chat_T_Dead")
				}
				else
				{
					copy(szMsg, charsmax(szMsg), "#Cstrike_Chat_AllDead")
				}
			}
		}
		case 2:
		{
			if(is_user_alive(id))
			{
				if(bType)
				{
					copy(szMsg, charsmax(szMsg), "#Cstrike_Chat_CT")
				}
				else
				{
					copy(szMsg, charsmax(szMsg), "#Cstrike_Chat_All")
				}
			}
			else
			{
				if(bType)
				{
					copy(szMsg, charsmax(szMsg), "#Cstrike_Chat_CT_Dead")
				}
				else
				{
					copy(szMsg, charsmax(szMsg), "#Cstrike_Chat_AllDead")
				}
			}
		}
		default:
		{
			copy(szMsg, charsmax(szMsg), "#Cstrike_Chat_AllSpec")
		}
	}
	if(bType)
	{
		for(i = 1 ; i <= g_iMaxPlayers ; i++)
		{
			if(!is_user_connected(i))
			{
				continue
			}
			if(get_member(i, m_iTeam) == team)
			{
				SendChat(i, id, szMsg, name, said)
			}
		}
	}
	else
	{
		SendChat(0, id, szMsg, name, said)
	}
	said[0] = EOS
	szMsg[0] = EOS
	name[0] = EOS
	return PLUGIN_HANDLED_MAIN
}
SendChat(id, sender, msg[], name[], said[])
{
	static msg_type
	if(!msg_type)
	{
		msg_type = get_user_msgid("SayText");
	}
	message_begin(id == 0 ? MSG_BROADCAST : MSG_ONE_UNRELIABLE, msg_type, _, id)
	write_byte(sender)
	write_string(msg)
	write_string(name)
	write_string(said)
	message_end()
}
public OnUpdateHudReady()
{
	if(pug_state != NO_ALIVE)
	{
		return
	}
	static i, count, len, Hud[32 * 15], name[15]
	for(i = 1 ; i <= g_iMaxPlayers ; i++)
	{
		if(!is_user_connected(i) || !(1<=get_user_team(i)<=2) || IsReadyBit(i))
		{
			continue;
		}
		get_user_name(i, name, charsmax(name))
		len += formatex(Hud[len], charsmax(Hud), "%s^n", name)
		count += 1;
	}
	set_hudmessage(255, 0, 0, 0.8, 0.07, 0, 1.0, 1.0)
	ShowSyncHudMsg(0, Sync1, "No listo: %i", count)
	set_hudmessage(255, 255, 255, 0.8, 0.1, 0, 1.0, 1.0)
	ShowSyncHudMsg(0, Sync2, Hud)
	len = 0;
	count = EOS
	Hud[0] = EOS
	for(i = 1 ; i <= g_iMaxPlayers ; i++)
	{
		if(!is_user_connected(i) || !(1<=get_user_team(i)<=2) || !IsReadyBit(i))
		{
			continue;
		}
		get_user_name(i, name, charsmax(name))
		len += formatex(Hud[len], charsmax(Hud), "%s^n", name)
	}
	set_hudmessage(0, 255, 0, 0.8, 0.5, 0, 1.0, 1.0)
	ShowSyncHudMsg(0, Sync3, "Listos: %i/%i", g_iReadyCount, get_pcvar_num(g_pPlayers))
	set_hudmessage(255, 255, 255, 0.8, 0.53, 0, 1.0, 1.0)
	ShowSyncHudMsg(0, Sync4, Hud)
	update_scoreboard();
	Hud[0] = EOS;
	len = EOS;
	name[0] = EOS
}
public OnSetReady(id)
{
	if(pug_state != NO_ALIVE)
	{
		client_print(id, print_chat, "[%s] No puedes usar este comando en este momento", PLUGIN)
		return
	}
	if(IsReadyBit(id))
	{
		client_print(id, print_chat, "[%s] Ya estas listo", PLUGIN)
		return 
	}
	SetReadyBit(id)
	g_iReadyCount += 1;
	OnUpdateHudReady()
	if(g_iReadyCount >= get_pcvar_num(g_pPlayers))
	{
		StartVoting()
	}
	return 
}
public OnUnReady(id)
{
	if(pug_state != NO_ALIVE)
	{
		client_print(id, print_chat, "[%s] No puedes usar este comando en este momento", PLUGIN)
		return
	}
	if(!IsReadyBit(id))
	{
		client_print(id, print_chat, "[%s] No estas listo", PLUGIN)
		return 
	}
	ClearReadyBit(id)
	g_iReadyCount -= 1;
	OnUpdateHudReady()
	return 
}
StartVoting()
{
	remove_task(TASK_READY);
	if(!g_votes)
	{
		g_votes = TrieCreate()
	}
	TrieClear(g_votes)
	g_iCurrentVote = -1;
	pug_state = VOTING;
	if(get_pcvar_num(g_pVoteMap))
	{
		StartVoteMap()
	}
	else
	{
		NextVote()
	}
}
public NextVote()
{
	if(pug_state != VOTING)
	{
		return;
	}
	g_iCurrentVote += 1;
	if(g_iCurrentVote >= ArraySize(g_aRegisterVotes))
	{
		StartPugPre()
		return;
	}
	set_task(0.1, "NextVotePost")
}
public NextVotePost()
{
	if(g_menu)
	{
		menu_destroy(g_menu)
		g_menu = 0;
	}
	TrieClear(g_votes)
	new array[REGISTER_VOTES], i
	ArrayGetArray(g_aRegisterVotes, g_iCurrentVote, array)
	g_iCountDown = get_pcvar_num(g_pVoteCount);
	g_menu = menu_create(array[VOTENAME], "mh_voteglobal")
	set_task(1.0, "VoteGlobalCountDown", TASK_VOTE, _, _, "a", g_iCountDown)
	for( i = 0 ; i < ArraySize(array[OPTIONS]) ; i++)
	{
		menu_additem(g_menu, fmt("%a", ArrayGetStringHandle(array[OPTIONS], i)))
	}
	menu_setprop(g_menu, MPROP_EXIT, MEXIT_NEVER)
	for( i = 1 ; i <= g_iMaxPlayers ; i++)
	{
		if(!is_user_connected(i) || !(1<=get_user_team(i)<=2))
		{
			continue;
		}
		menu_display(i, g_menu, 0, g_iCountDown)
	}
}
public mh_voteglobal(id, menu, item)
{
	if(item == MENU_EXIT)
	{
		return
	}
	new num[3], vote
	num_to_str(item, num, charsmax(num))
	if(!TrieGetCell(g_votes, num, vote))
	{
		vote = 0;
	}
	vote += 1;
	TrieSetCell(g_votes, num, vote)
	UpdatehudVoteGlobal()
}
public VoteGlobalCountDown(task)
{
	new i, num[4], vote
	if(--g_iCountDown > 0)
	{
		UpdatehudVoteGlobal()
	}
	else
	{
		remove_task(task)
		new win, votes, array[REGISTER_VOTES]
		ArrayGetArray(g_aRegisterVotes, g_iCurrentVote, array)
		for(i = 0 ; i < ArraySize(array[OPTIONS]) ; i++)
		{
			num_to_str(i, num, charsmax(num))
			TrieGetCell(g_votes, num, vote)
			
			if(vote > votes)
			{
				win = i;
				votes = vote
			}	
		}
		for(i = 1 ; i <= g_iMaxPlayers ; i++)
		{
			if(is_user_connected(i))
			{
				menu_cancel(i);
			}
		}
		menu_destroy(g_menu)
		ExecuteForward(array[FUNC], _, win)
	}
}
public client_disconnected(id)
{
	if(IsReadyBit(id))
	{
		ClearReadyBit(id)
		g_iReadyCount -= 1;
	}
}
UpdatehudVoteGlobal()
{
	new num[4], vote, array[REGISTER_VOTES], allvotes
	ArrayGetArray(g_aRegisterVotes, g_iCurrentVote, array)
	MakeTitleHud("%s: (%02i)", array[VOTENAME], g_iCountDown)
	for(new i = 0 ; i < ArraySize(array[OPTIONS]) ; i++)
	{
		num_to_str(i, num, charsmax(num))
		if(TrieGetCell(g_votes, num, vote))
		{
			MakeBodyHud(true, "%a %i Voto%s^n", ArrayGetStringHandle(array[OPTIONS], i), vote, vote == 1 ? "" : "s")
			allvotes += vote;
		}
	}
	if(allvotes >= get_pcvar_num(g_pPlayers))
	{
		g_iCountDown = 0;
	}
	MakeBodyHud();
}
MakeTitleHud(msg[], any:...)
{
	static temp[50]
	vformat(temp, charsmax(temp), msg, 2)
	set_hudmessage(0, 255, 0, -1.0, 0.0, 0, 1.0, 1.1)
	ShowSyncHudMsg(0, Sync1, temp)
	temp[0] = EOS
}
MakeBodyHud(bool:add=false, msg[]="", any:...)
{
	static temp[512], len
	if(add)
	{
		len+=vformat(temp[len], charsmax(temp), msg, 3)
	}
	else
	{
		if(!len)
		{
			vformat(temp, charsmax(temp), msg, 3)
		}
		set_hudmessage(255, 255, 255, -1.0, 0.03, 0, 1.0, 1.1)
		ShowSyncHudMsg(0, Sync2, temp)
		temp[0] = EOS
		len = EOS
	}
}
StartVoteMap()
{
	
	new i;
	g_iCountDown = get_pcvar_num(g_pVoteCount);
	set_task(1.0, "VoteMapCountDown", TASK_VOTE, _, _, "a", g_iCountDown)
	g_menu = menu_create("Votacion de Mapa", "mh_votemap")
	for(i = 0 ; i < ArraySize(g_maps) ; i++)
	{
		menu_additem(g_menu, fmt("%a", ArrayGetStringHandle(g_maps, i)))
	}
	menu_setprop(g_menu, MPROP_EXIT, MEXIT_NEVER)
	for( i = 1 ; i <= g_iMaxPlayers ; i++)
	{
		if(!is_user_connected(i) || !(1<=get_user_team(i)<=2))
		{
			continue;
		}
		menu_display(i, g_menu, 0, g_iCountDown)
	}
}
public mh_votemap(id, menu, item)
{
	if(item == MENU_EXIT)
	{
		return;
	}
	new num[4], votes
	num_to_str(item, num, charsmax(num))
	TrieGetCell(g_votes, num, votes)
	votes += 1;
	TrieSetCell(g_votes, num, votes)
	UpdateHudVoteMap()
}
UpdateHudVoteMap()
{
	new num[4], vote, allvotes
	MakeTitleHud("Votacion de Mapa: (%02i)", g_iCountDown)
	for(new i = 0 ; i < ArraySize(g_maps) ; i++)
	{
		num_to_str(i, num, charsmax(num))
		if(TrieGetCell(g_votes, num, vote))
		{
			allvotes += vote;
			MakeBodyHud(true, "%a %i Voto%s^n", ArrayGetStringHandle(g_maps, i), vote, vote == 1 ? "" : "s")
		}
	}
	if(allvotes >= get_pcvar_num(g_pPlayers))
	{
		g_iCountDown = 0;
	}
	MakeBodyHud()
}
public VoteMapCountDown(task)
{
	new i, num[4], vote
	if(--g_iCountDown > 0)
	{
		UpdateHudVoteMap()
	}
	else
	{
		remove_task(task)
		new win, votes
		for(i = 0 ; i < ArraySize(g_maps) ; i++)
		{
			num_to_str(i, num, charsmax(num))
			TrieGetCell(g_votes, num, vote)
			if(vote > votes)
			{
				win = i;
				votes = vote;
			}
		}
		TrieClear(g_votes)
		for(i = 1 ; i <= g_iMaxPlayers ; i++)
		{
			if(is_user_connected(i))
			{
				menu_cancel(i);
			}
		}
		menu_destroy(g_menu)
		if(!win)
		{
			client_print(0, print_chat, "[%s] Se decidio %a", PLUGIN, ArrayGetStringHandle(g_maps, win))
			NextVote()
		}
		else
		{
			set_pcvar_num(g_pVoteMap, 0);
			server_cmd("changelevel %a", ArrayGetStringHandle(g_maps, win))
		}
	}
}
StartPugPre()
{
	pug_state = COMMENCING
	set_pcvar_num(g_pMaxSpeed, 0);
	EnableHookChain(PreThink)
	g_iCountDown = 5
	StartPugCountDown(TASK_INTERMISSION)
	rg_round_end(float(g_iCountDown)+0.1, WINSTATUS_DRAW, ROUND_GAME_COMMENCE, "", "");
	set_member_game(m_bCompleteReset, true)
	set_task(1.0, "StartPugCountDown", TASK_INTERMISSION, _,_,"a",g_iCountDown)
}
public OnPlayerThink(id)
{
	if(pug_state == COMMENCING || is_intermission)
	{
		client_cmd(id, "+strafe%s", is_intermission ? ";+showscores" : "")
		static item
		item = get_member(id, m_pActiveItem);
		if(!is_nullent(item))
		{
			set_member(item, m_Weapon_flNextPrimaryAttack, 0.1)
			set_member(item, m_Weapon_flNextSecondaryAttack, 0.1)
		}
	}
	else
	{
		client_cmd(0, "-strafe;-showscores")
		DisableHookChain(PreThink)
	}
}
public StartPugCountDown(task)
{
	if(--g_iCountDown > 0)
	{
		client_print(0, print_center, "Empezando Partida: %i", g_iCountDown)
		client_cmd(0, "spk ^"%s^"", SND_COUNTER_BEEP)
	}
	else
	{
		remove_task(task)
		if(get_pcvar_num(g_iLegacyChat))
		{
			set_cvar_num("sv_alltalk", 0)
		}
		else
		{
			set_cvar_num("sv_alltalk", 2)
		}
	}
}
public OnStartRound()
{
	if(pug_state != COMMENCING && pug_state != ALIVE)
	{
		return
	}
	else if(pug_state == COMMENCING || is_intermission)
	{
		if(pug_state == COMMENCING)
		{
			g_iHalfRoundNum = (get_pcvar_num(g_pMaxRounds) / 2)
			for(new i = 0 ; i < sizeof(cvar_pug) ; i++)
			{
				set_cvar_string(cvar_pug[i][NAME], cvar_pug[i][VALUE])
			}
		}
		if(is_intermission)
		{			
			rg_swap_all_players()
			for(new i = 1 ; i <= g_iMaxPlayers ; i++)
			{
				if(!is_user_connected(i))
				{
					continue;
				}
				if(is_user_alive(i))
				{
					rg_give_default_items(i)
					rg_set_user_armor(i, 0, ARMOR_NONE)
				}
			}
		}
		pug_state = ALIVE
		set_pcvar_num(g_pMaxSpeed, 320)
		DisableHookChain(g_MakeBomber)
	}
	client_cmd(0, "-strafe;-showscores")

}
public OnMakeBomber()
{
	if(pug_state == ALIVE)
	{
		DisableHookChain(g_MakeBomber)
		return HC_CONTINUE
	}
	SetHookChainReturn(ATYPE_INTEGER, 0)
	return HC_SUPERCEDE
}
stock get_rounds()
{
	return (get_member_game(m_iTotalRoundsPlayed)+1)
}
stock get_ct_round_win()
{
	return(get_member_game(m_iNumCTWins))
}
stock get_tt_round_win()
{
	return(get_member_game(m_iNumTerroristWins))
}
stock send_scoreboard_msg(const msg[], any:...)
{
	static scoreboard[33], gMsgServerName, gMsgScoreInfo
	if(!gMsgServerName)
	{
		gMsgServerName= get_user_msgid("ServerName")
		gMsgScoreInfo= get_user_msgid("ScoreInfo")
	}
	vformat(scoreboard, charsmax(scoreboard), msg, 2)

	message_begin(MSG_ALL, gMsgServerName)
	write_string(scoreboard)
	message_end()
	message_begin(MSG_ALL, gMsgScoreInfo)
	write_byte(33)
	write_short(0)
	write_short(0)
	write_short(0)
	write_short(0)
	message_end()
}
public OnStartRoundPost()
{
	if(pug_state != ALIVE)
	{
		return;
	}
	if(is_intermission)
	{
		is_intermission = false
		for(new i = 1 ; i<=g_iMaxPlayers ; i++)
		{
			if(!is_user_connected(i))
			{
				continue;
			}
			if(overtime)
			{
				rg_add_account(i, get_pcvar_num(g_pOverTimeMoney), AS_SET)
			}
			else
			{
				rg_add_account(i, 800, AS_SET)
			}
		}
	}
	rh_client_cmd(0, "cd fadeout")
	update_scoreboard()
}
public update_scoreboard()
{
	if(pug_state == NO_ALIVE)
	{
		send_scoreboard_msg("Esperando Jugadores")
	}
	else if(pug_state == ALIVE)
	{
		if(overtime)
		{
			send_scoreboard_msg("R: %i | OT:%i/%i | CT:%i | TT:%i", get_rounds(), get_rounds() - (g_iHalfRoundNum - (get_pcvar_num(g_pOverTimeMaxRounds) / 2)), get_pcvar_num(g_pOverTimeMaxRounds), get_ct_round_win(), get_tt_round_win())
		}
		else
		{
			send_scoreboard_msg("Ronda: %i | CT: %i | TT: %i", get_rounds(), get_ct_round_win(), get_tt_round_win())
		}
	}
}
public StartIntermission()
{
	is_intermission = true
	EnableHookChain(PreThink)
	if(overtime)
	{
		g_iCountDown = get_pcvar_num(g_pOverTimeIntermissionCD)
	}
	else
	{
		g_iCountDown = get_pcvar_num(g_pIntermissionCountdown)
	}
	set_pcvar_num(g_pMaxSpeed, 0)
	set_task(1.0, "IntermissionCountDown", TASK_INTERMISSION, _, _, "a", g_iCountDown)
}
public IntermissionCountDown(task)
{
	if(--g_iCountDown > 0)
	{
		if(pug_state == ENDING)
		{
			if(g_tPugWin == WINSTATUS_DRAW)
			{
				send_scoreboard_msg("EMPATE!!! %02i:%02i", g_iCountDown / 60 , g_iCountDown % 60)
			}
			else
			{
				send_scoreboard_msg("Los %s Ganan %02i:%02i", g_tPugWin == WINSTATUS_TERRORISTS ? "Terroristas" : "AntiTerroristas", g_iCountDown / 60 , g_iCountDown % 60)
			}
		}
		else
		{
			send_scoreboard_msg("Medio Tiempo: %02i:%02i", g_iCountDown / 60 , g_iCountDown % 60)
		}
		
	}
	else
	{
		if(pug_state == ENDING)
		{
			StartPregame()
		}
		remove_task(task)
	}
}
public OnRoundEndPre(WinStatus:status, ScenarioEventEndRound:event, Float:tmDelay)
{
	if(status == WINSTATUS_DRAW || event == ROUND_GAME_COMMENCE)
	{
		SetHookChainArg(3, ATYPE_FLOAT, 0.1)
		StartPregame()
		return;
	}
	if(pug_state != ALIVE)
	{
		return
	}

	if(get_rounds() == g_iHalfRoundNum)
	{
		StartIntermission()
		SetHookChainArg(3, ATYPE_FLOAT, float(g_iCountDown))
		return
	}

	if(get_rounds()>g_iHalfRoundNum)
	{
		new bool:end = false
		new roundswin
		new maxrounds
		new roundstowin
		switch(status)
		{
			case WINSTATUS_TERRORISTS :
			{
				roundswin = get_tt_round_win()
			}
			case WINSTATUS_CTS :
			{
				roundswin = get_ct_round_win()
			}
			default : return
		}
		if(overtime)
		{
			maxrounds = g_iHalfRoundNum + (get_pcvar_num(g_pOverTimeMaxRounds)  / 2 );
		}
		else
		{
			maxrounds = get_pcvar_num(g_pMaxRounds)
		}
		roundstowin = maxrounds / 2

		if(roundswin + 1 > roundstowin)
		{
			end = true
			overtime = false
			pug_state = ENDING
			g_tPugWin = status
		}
		else if( maxrounds == get_rounds())
		{
			end = true
			g_tPugWin = WINSTATUS_DRAW
			if(get_pcvar_num(g_pOverTime) > 0)
			{
				overtime = true
				g_iHalfRoundNum = (get_pcvar_num(g_pOverTimeMaxRounds)  / 2 ) + get_rounds();
			}
		}
		if(end)
		{
			if(!overtime)
			{
				pug_state = ENDING
				set_member_game(m_bCompleteReset, true)
			}
			StartIntermission();
			SetHookChainArg(3, ATYPE_FLOAT, float(g_iCountDown))
			return
		}
	}
	set_task(0.1, "update_scoreboard")
}
public OnChooseTeam(id, any:slot)
{
	static maxplayers
	if(!maxplayers)
	{
		maxplayers = get_pcvar_num(g_pPlayers) / 2
	}
	if(!(MenuChoose_T<=slot<=MenuChoose_CT))
	{
		if(slot == MenuChoose_Spec && is_user_admin(id))
		{
			return HC_CONTINUE
		}
		if(slot == MenuChoose_AutoSelect)
		{
			if(CountTeam(TEAM_TERRORIST) >= maxplayers)
			{
				if(CountTeam(TEAM_CT) >= maxplayers)
				{
					SetHookChainReturn(ATYPE_INTEGER, 0)
					return HC_SUPERCEDE
				}
				else
				{
					SetHookChainArg(2, ATYPE_INTEGER, MenuChoose_CT)
					return HC_CONTINUE
				}
			}
			else
			{
				SetHookChainArg(2, ATYPE_INTEGER, MenuChoose_T)
				return HC_CONTINUE
			}
		}
		SetHookChainReturn(ATYPE_INTEGER, 0)
		return HC_SUPERCEDE
	}
	if(CountTeam(slot) >= maxplayers)
	{
		SetHookChainReturn(ATYPE_INTEGER, 0)
		return HC_SUPERCEDE
	}
	return HC_CONTINUE
}
CountTeam(any:team)
{
	new count = 0;
	for(new i = 1 ; i <= g_iMaxPlayers ; i++)
	{
		if(!is_user_connected(i) || get_member(i, m_iTeam) != team)
		{
			continue
		}
		count += 1;
	}
	return count
}
stock is_user_admin(id)
{
	new __flags = get_user_flags(id);
	return (__flags > 0 && !(__flags & ADMIN_USER));
}

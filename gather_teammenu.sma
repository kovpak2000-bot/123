/*
	1.1 - Добавлены квары gather_tt_access_flag и gather_ct_access_flag
	1.2 - Фикс 'set_member_s: invalid or uninitialized entity' в clcmd_Chooseteam()
	1.3 - Добавлен квар gather_max_spectators; В lang/gather.txt добавлен ключ GATHER__SPEC_SLOTS_BUSY
	1.4 (14.11.2023 by mx?!):
		* Добавлен фовард gather_teammenu_team_full для предстоящего плагина gather_teamfull_info.sma
	1.5 (18.02.2024) by mx?!:
		* Подключён форвард gather_blt_player_ban из плагина gather_ban_looser_team.sma
*/

new const PLUGIN_VERSION[] = "1.5"

#include <amxmodx>
#include <reapi>
#include <gather>

#define chx charsmax
#define IsInGame(%0) (TEAM_SPECTATOR > get_member(%0, m_iTeam) > TEAM_UNASSIGNED)
#define rg_get_user_team(%0) get_member(%0, m_iTeam)

enum ( += MAX_PLAYERS + 1 ) {
	TASKID__AUTOKICK = 1337
}

enum _:PCVAR_ENUM {
	PCVAR__AUTOKICK_TIME
}

enum _:CVAR_ENUM {
	Float:CVAR_F__AUTOKICK_TIME,
	CVAR__ALLOW_SPECTATORS,
	CVAR__TT_ACCESS_FLAG[32],
	CVAR__CT_ACCESS_FLAG[32],
	CVAR__MAX_SPECTATORS
}

new g_pCvar[PCVAR_ENUM]
new g_eCvar[CVAR_ENUM]
new bool:g_bJustConnected[MAX_PLAYERS + 1]
new HookChain:g_hShowVGUIPost
new g_fwdTeamFull
new bool:g_bPlayerBan[MAX_PLAYERS + 1]

public plugin_init() {
	register_plugin("Gather TeamMenu", PLUGIN_VERSION, "mx?!")

	func_RegCvars()

	g_fwdTeamFull = CreateMultiForward("gather_teammenu_team_full", ET_IGNORE, FP_CELL)

	register_clcmd("chooseteam", "clcmd_Chooseteam")
	register_clcmd("jointeam", "clcmd_Block")
	register_clcmd("joinclass", "clcmd_Block")

	RegisterHookChain(RG_HandleMenu_ChooseTeam, "HandleMenu_ChooseTeam_Pre")
	RegisterHookChain(RG_HandleMenu_ChooseAppearance, "HandleMenu_ChooseAppearance_Pre")

	RegisterHookChain(RG_ShowVGUIMenu, "ShowVGUIMenu_Pre")
	g_hShowVGUIPost = RegisterHookChain(RG_ShowVGUIMenu, "ShowVGUIMenu_Post", true)
	DisableHookChain(g_hShowVGUIPost)
}

func_RegCvars() {
	g_pCvar[PCVAR__AUTOKICK_TIME] = create_cvar("gather_autokick_time", "")
	bind_pcvar_float(g_pCvar[PCVAR__AUTOKICK_TIME], g_eCvar[CVAR_F__AUTOKICK_TIME])

	bind_pcvar_num(get_cvar_pointer("allow_spectators"), g_eCvar[CVAR__ALLOW_SPECTATORS])

	bind_cvar_string( "gather_tt_access_flag", "",
		.bind = g_eCvar[CVAR__TT_ACCESS_FLAG], .maxlen = chx(g_eCvar[CVAR__TT_ACCESS_FLAG]) );

	bind_cvar_string( "gather_ct_access_flag", "",
		.bind = g_eCvar[CVAR__CT_ACCESS_FLAG], .maxlen = chx(g_eCvar[CVAR__CT_ACCESS_FLAG]) );

	bind_cvar_num("gather_max_spectators", "32", .bind = g_eCvar[CVAR__MAX_SPECTATORS]);
}

public client_putinserver(pPlayer) {
	if(is_user_bot(pPlayer) || is_user_hltv(pPlayer)) {
		return
	}

	if(gather_get_match_state() != MATCH_OVER) {
		func_SetAutoKick(pPlayer)
	}

	/*if(!is_user_authorized(pPlayer)) {
		server_cmd("kick #%i ^"%L^"", get_user_userid(pPlayer), pPlayer, "GATHER__AUTH_FAILED")
		return
	}*/

	g_bJustConnected[pPlayer] = true // далее см. ShowVGUIMenu_Pre()
}

public client_disconnected(pPlayer) {
	g_bPlayerBan[pPlayer] = false
	//g_bJustConnected[pPlayer] = false // TODO: 18.02.2024 по хорошему надо сделать с логированием, проверить не триггерится ли (true в этом фоварде)
	func_RemoveAutoKick(pPlayer)
}

public gather_player_leave(pPlayer) {
	if(gather_get_match_state() != MATCH_OVER) {
		client_print_color(0, pPlayer, "%L", LANG_PLAYER, "GATHER__PLAYER_LEAVE", pPlayer)
	}
}

public ShowVGUIMenu_Pre(pPlayer, VGUIMenu:iMenuID, iKeys, szOldMenu[]) {
	if(!is_user_connected(pPlayer) || is_user_bot(pPlayer) || is_user_hltv(pPlayer)) {
		return HC_CONTINUE
	}

	switch(iMenuID) {
		case VGUI_Menu_Team, VGUI_Menu_Class_T, VGUI_Menu_Class_CT: {
			set_member(pPlayer, m_bForceShowMenu, true) // форсим oldstyle-меню
		}
	}

	if(iMenuID != VGUI_Menu_Team) {
		return HC_CONTINUE
	}

	if(g_bJustConnected[pPlayer]) {
		g_bJustConnected[pPlayer] = false
		EnableHookChain(g_hShowVGUIPost)
		// Без задержки плеер остаётся висеть как зритель (даже в пост)
		// Лень разбираться с m_iJoiningState, оставляю костыль-задержку
		RequestFrame("func_InitPlayer", pPlayer)
		return HC_SUPERCEDE
	}

	if(!gather_is_player_in_match(pPlayer) || (gather_can_player_spectate(pPlayer) && !IsInGame(pPlayer))) {
		return HC_CONTINUE
	}

	if(gather_get_match_state() != MATCH_GATHERING) {
		EnableHookChain(g_hShowVGUIPost)
		return HC_SUPERCEDE
	}

	return HC_CONTINUE
}

public ShowVGUIMenu_Post(pPlayer, VGUIMenu:iMenuID, iKeys, szOldMenu[]) {
	DisableHookChain(g_hShowVGUIPost)

	if(is_user_connected(pPlayer) && !is_user_bot(pPlayer) && !is_user_hltv(pPlayer)) {
		set_member(pPlayer, m_iMenu, Menu_OFF)
	}
}

public func_InitPlayer(pPlayer) {
	if(!is_user_connected(pPlayer) || is_user_bot(pPlayer) || is_user_hltv(pPlayer)) {
		return
	}

	if(gather_try_restore_player(pPlayer)) {
		func_RemoveAutoKick(pPlayer)

		if(gather_get_match_state() != MATCH_OVER) {
			client_print_color(0, pPlayer, "%L", LANG_PLAYER, "GATHER__PLAYER_RETURNED", pPlayer)
		}

		return
	}

	// вернёт нас в ShowVGUIMenu_Pre() где мы сможем руками выбрать команду (меню) т.к. сработает тамошнее
	// условие '!gather_is_player_in_match(pPlayer)'
	engclient_cmd(pPlayer, "chooseteam")

	/*if(gather_can_player_spectate(pPlayer)) {
		engclient_cmd(pPlayer, "chooseteam")
		return
	}

	if(gather_try_find_slot(pPlayer, .bSkipJoin = false, .iForceTeam = TEAM_UNASSIGNED)) {
		if(gather_get_match_state() != MATCH_OVER) {
			client_print_color(0, pPlayer, "%L", LANG_PLAYER, "GATHER__PLAYER_JOINED", pPlayer)
		}
	}
	else {
		func_KickPlayer(pPlayer)
	}*/
}

/*func_KickPlayer(pPlayer) {
	server_cmd("kick #%i ^"%L^"", get_user_userid(pPlayer), pPlayer, "GATHER__NO_FREE_SLOTS")
}*/

public gather_blt_player_ban(pPlayer) {
	g_bPlayerBan[pPlayer] = true
}

// RG_ShowVGUIMenu -> RG_HandleMenu_ChooseTeam
public HandleMenu_ChooseTeam_Pre(const index, const MenuChooseTeam:slot) {
	if(is_user_bot(index) || is_user_hltv(index)) {
		return HC_CONTINUE
	}

	if(g_bPlayerBan[index]) {
		SetHookChainArg(2, ATYPE_INTEGER, 10) // сводим нажатие в пустоту (выход)
		SetHookChainReturn(ATYPE_INTEGER, 0)
		return HC_SUPERCEDE
	}

	// https://github.com/s1lentq/ReGameDLL_CS/blob/efb06a7a201829bdbe13218bc5f5342e1f2ed8f1/regamedll/dlls/client.cpp#L1991
	if(get_member(index, m_bTeamChanged) && !is_user_alive(index)) {
		return HC_CONTINUE
	}

	switch(slot) {
		case MenuChoose_T, MenuChoose_CT: {
			new TeamName:iTeam = (slot == MenuChoose_T) ? TEAM_TERRORIST : TEAM_CT;

			if(iTeam == rg_get_user_team(index)) {
				func_OverrideMenu(index)
				return HC_SUPERCEDE
			}

			if(IsTeamNoAccess(index, iTeam)) {
				client_print(index, print_center, "%l", "GATHER__TEAM_NO_ACCESS")
				func_OverrideMenu(index)
				return HC_SUPERCEDE
			}

			if(IsTeamFull(iTeam)) {
				client_print(index, print_center, "%l", "GATHER__TEAM_FULL")
				func_OverrideMenu(index)
				ExecuteForward(g_fwdTeamFull, _, index)
				return HC_SUPERCEDE
			}

			new iIsInMatch = gather_is_player_in_match(index)

			if(!gather_try_find_slot(index, .bSkipJoin = true, .iForceTeam = iTeam)) {
				client_print(index, print_center, "%l", "GATHER__SLOT_RESERVED")
				func_OverrideMenu(index)
				return HC_SUPERCEDE
			}

			if(!iIsInMatch && gather_get_match_state() != MATCH_OVER) {
				client_print_color( 0, (iTeam == TEAM_CT) ? print_team_blue : print_team_red,
					"%L", LANG_PLAYER, "GATHER__PLAYER_JOINED", index );
			}

			// Чтобы игрок не абузил висением в меню выбора скина
			// Таск снимается в HandleMenu_ChooseAppearance_Pre()
			func_SetAutoKick(index)
			return HC_CONTINUE
		}
		case MenuChoose_Spec: {
			if(!g_eCvar[CVAR__ALLOW_SPECTATORS] || !g_eCvar[CVAR__MAX_SPECTATORS]) {
				client_print(index, print_center, "%l", "GATHER__SPEC_NOT_ALLOWED")
				func_OverrideMenu(index)
				return HC_SUPERCEDE
			}

			if(get_member(index, m_iTeam) != TEAM_SPECTATOR) {
				new pPlayers[MAX_PLAYERS], iPlCount
				get_players(pPlayers, iPlCount, "che", "SPECTATOR")

				if(iPlCount > g_eCvar[CVAR__MAX_SPECTATORS]) {
					client_print(index, print_center, "%l", "GATHER__SPEC_SLOTS_BUSY")
					func_OverrideMenu(index)
					return HC_SUPERCEDE
				}
			}

			// проверка gather_is_player_in_match() как временный быстрофикс отсутствия учёта
			// ухода в спектры в режиме MATCH_GATHERING, когда игрок уже побывал в команде ТТ/КТ,
			// т.е. попал в плеердату и значится игроком. В идеале надо расписать освобождение слота
			// уходящим в спек игроком, если он этот самый слот занимает (gather_is_player_in_match())
			if(!gather_can_player_spectate(index) || gather_is_player_in_match(index)) {
				client_print(index, print_center, "%l", "GATHER__CANT_SPEC")
				func_OverrideMenu(index)
				return HC_SUPERCEDE
			}

			func_RemoveAutoKick(index)
			return HC_CONTINUE
		}
		default: { // MenuChoose_VIP, MenuChoose_AutoSelect, external (jointeam + some key like 8, 9...)
			func_OverrideMenu(index)
			return HC_SUPERCEDE
		}
	}

	return HC_CONTINUE
}

bool:IsTeamNoAccess(pPlayer, TeamName:iTeam) {
	new bitFlags = read_flags(g_eCvar[ (iTeam == TEAM_CT) ? CVAR__CT_ACCESS_FLAG : CVAR__TT_ACCESS_FLAG ])
	return (bitFlags && !(get_user_flags(pPlayer) & bitFlags))
}

bool:IsTeamFull(TeamName:iTeam) {
	new pPlayers[MAX_PLAYERS], iPlCount, iInTeam[TeamName], pPlayer
	get_players(pPlayers, iPlCount, "ch") // не учитываем ботов - их слоты в потенциале можно занять (если нет резерва)

	for(new i; i < iPlCount; i++) {
		pPlayer = pPlayers[i]

		if(gather_is_player_in_match(pPlayer)) {
			iInTeam[ rg_get_user_team(pPlayer) ] ++
		}
	}

	return ( iInTeam[iTeam] >= (gather_get_maxplayers() / 2) )
}

func_OverrideMenu(index) {
	RequestFrame("func_ForceMenu", index) // пост хук не работает, лень разбираться.
	SetHookChainArg(2, ATYPE_INTEGER, 10) // сводим нажатие в пустоту (выход)
	SetHookChainReturn(ATYPE_INTEGER, 0)
}

public func_ForceMenu(index) {
	if(is_user_connected(index) && !is_user_bot(index)) {
		engclient_cmd(index, "chooseteam")
	}
}

public HandleMenu_ChooseAppearance_Pre(const index, const slot) {
	func_RemoveAutoKick(index)
}

func_SetAutoKick(pPlayer) {
	if(!task_exists(TASKID__AUTOKICK + pPlayer)) {
		set_task(g_eCvar[CVAR_F__AUTOKICK_TIME], "task_AutoKick", TASKID__AUTOKICK + pPlayer)
	}
}

func_RemoveAutoKick(pPlayer) {
	remove_task(TASKID__AUTOKICK + pPlayer)
}

public task_AutoKick(pPlayer) {
	pPlayer -= TASKID__AUTOKICK
	server_cmd("kick #%i ^"%L^"", get_user_userid(pPlayer), pPlayer, "GATHER__AFK_KICK")
}

public clcmd_Chooseteam(pPlayer) {
	if(is_entity(pPlayer)) {
		set_member(pPlayer, m_bTeamChanged, false)
	}

	return PLUGIN_CONTINUE
}

public clcmd_Block(pPlayer) {
	return PLUGIN_HANDLED
}

stock bind_cvar_string(const cvar[], const value[], flags = FCVAR_NONE, const desc[] = "", bool:has_min = false, Float:min_val = 0.0, bool:has_max = false, Float:max_val = 0.0, bind[], maxlen) {
	bind_pcvar_string(create_cvar(cvar, value, flags, desc, has_min, min_val, has_max, max_val), bind, maxlen)
}

stock bind_cvar_num(const cvar[], const value[], flags = FCVAR_NONE, const desc[] = "", bool:has_min = false, Float:min_val = 0.0, bool:has_max = false, Float:max_val = 0.0, &bind) {
	bind_pcvar_num(create_cvar(cvar, value, flags, desc, has_min, min_val, has_max, max_val), bind);
}
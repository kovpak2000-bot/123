/* 1.1:
		* Улучшения и исправления логики, связанной с паузой
	1.2 (18.03.2024):
		* Добавлен квар 'gather_give_up_score_diff', позволяющий задать разницу очков, при которой проигрывающая сторона может сдаться
		* Добавлен квар 'gather_give_up_min_round', позволяющий задать минимальный live-раунд для возможности сдаться
		* Добавлена возможность отключить возможность сдаваться (новое значение "0" для квара 'gather_give_up_votes')
	1.3 (30.04.2024 by mx?!):
		* Добавлен натив gather_gamemenu_try_set_timeout()
		* В словарь amxmodx/data/lang/gather.txt добавлены языковые ключи:
			GATHER__ADM_TIMEOUT_REQUEST
			GATHER__TIMEOUT_ADM_SET_CHAT
			GATHER__TIMEOUT_ADM_EXT_CHAT
			GATHER__TIMEOUT_ADM_HUD
	1.4 (28.02.2025 by mx?!):
		* Квару "gather_gamemenu_hud" добавлена возможность задать пустое значение для отключения HUD в принципе.
			Теперь можно либо вообще убрать HUD, изменив значение этого квара в gather_main.cfg, либо отключать
			HUD уже во время live-стадии, вписав квар с пустым значением в подходящий конфиг стадии игры в 
			amxmodx/configs/gather (в gather_warmup.cfg, или в gather_knife_round.cfg, или в gather_live.cfg)
*/

new const PLUGIN_VERSION[] = "1.4"

#include <amxmodx>
#include <reapi>
#include <gather>

// Список команд открывающих главное меню
new const MENU_CLCMDS[][] = {
	"say /ready", // Первый пункт выводится в HUD, см. ключ словаря 'GATHER__GAMEMENU_INFO'
	"say_team /ready",
	"say !ready",
	"say_team !ready",
	"say !r",
	"say_team !r",
	"say .ready",
	"say_team .ready",
	"say .r",
	"say_team .r",
	"nightvision" // Кнопка 'N' по-умолчанию
}

#define chx charsmax
#define chx_len(%0) charsmax(%0) - iLen
#define rg_get_user_team(%0) get_member(%0, m_iTeam)
#define IsInGame(%0) (TEAM_SPECTATOR > get_member(%0, m_iTeam) > TEAM_UNASSIGNED)
#define ALL_KEYS 1023
#define MAX_MENU_LENGTH 512

enum { _KEY1_, _KEY2_, _KEY3_, _KEY4_, _KEY5_, _KEY6_, _KEY7_, _KEY8_, _KEY9_, _KEY0_ }

enum { _PAGE1_, _PAGE2_, _PAGE3_, _PAGE4_, _PAGE5_, _PAGE6_, _PAGE7_, _PAGE8_, _PAGE9_, _PAGE10_ }

new const MENU_IDENT_STRING[] = "GatherGameMenu"

enum ( += MAX_PLAYERS + 1 ) {
	TASKID__HUD = 1337,
	TASKID__TIMEOUT_HUD
}

enum _:PCVAR_ENUM {
	PCVAR__PAUSE_VOTES,
	PCVAR__PAUSE_TIME,
	PCVAR__PAUSES_PER_TEAM,
	PCVAR__GAMEMENU_HUD,
	PCVAR__GIVE_UP_VOTES,
	PCVAR__FREEZETIME,
	PCVAR__TIMEOUT_HUD,
	PCVAR__VOTEBAN_VOTES,
	PCVAR__VOTEBAN_CMD,
	PCVAR__VOTEKICK_VOTES,
	PCVAR__VOTEKICK_CMD
}

enum _:CVAR_ENUM {
	CVAR__PAUSE_VOTES,
	CVAR__PAUSE_TIME,
	CVAR__PAUSES_PER_TEAM,
	CVAR__GAMEMENU_HUD_R,
	CVAR__GAMEMENU_HUD_G,
	CVAR__GAMEMENU_HUD_B,
	Float:CVAR_F__GAMEMENU_HUD_X,
	Float:CVAR_F__GAMEMENU_HUD_Y,
	CVAR__GIVE_UP_VOTES,
	CVAR__TIMEOUT_HUD_R,
	CVAR__TIMEOUT_HUD_G,
	CVAR__TIMEOUT_HUD_B,
	Float:CVAR_F__TIMEOUT_HUD_X,
	Float:CVAR_F__TIMEOUT_HUD_Y,
	CVAR__VOTEBAN_VOTES,
	CVAR__VOTEBAN_CMD[128],
	CVAR__VOTEKICK_VOTES,
	CVAR__VOTEKICK_CMD[128],
	CVAR__GIVE_UP_SCORE_DIFF,
	CVAR__GIVE_UP_MIN_ROUND
}

enum {
	MENU_MODE__MAIN,
	MENU_MODE__VOTEBAN_MENU,
	MENU_MODE__VOTEKICK_MENU
}

new g_pCvar[PCVAR_ENUM]
new g_eCvar[CVAR_ENUM]
new g_szMenu[MAX_MENU_LENGTH]
new g_iMenuID
new bool:g_bMenuHided[MAX_PLAYERS + 1]
new g_hHudSyncObj[GATHER_SYNCOBJ_ENUM]
new g_iUsedPauses[TeamName]
new TeamName:g_iTimeOutTeam
new g_iTimeout
new TeamName:g_iCurrTimeOutTeam
new g_iCurrTimeOut
new bool:g_bGiveUp[MAX_PLAYERS + 1]
new g_iMenuMode[MAX_PLAYERS + 1]
new bool:g_bPunished[MAX_PLAYERS + 1]
new g_iTargetUserIDs[MAX_PLAYERS + 1][MAX_PLAYERS]
new g_iMenuPage[MAX_PLAYERS + 1]
new bool:g_bVoteBan[MAX_PLAYERS + 1][MAX_PLAYERS + 1]
new bool:g_bVoteKick[MAX_PLAYERS + 1][MAX_PLAYERS + 1]
new bool:g_bPause[MAX_PLAYERS + 1]
new Float:g_fOldBuyTime, Float:g_fOldAutokickTimeout, Float:g_fOldMaxIdlePeriod
const PAUSE_CVAR_VALUE = 999999
new g_pPauseAdminUserId

public plugin_init() {
	register_plugin("Gather GameMenu", PLUGIN_VERSION, "mx?!")

	func_RegCvars()

	for(new i; i < sizeof(MENU_CLCMDS); i++) {
		register_clcmd(MENU_CLCMDS[i], "clcmd_OpenMenu")
	}

	g_iMenuID = register_menu_ex(MENU_IDENT_STRING, ALL_KEYS, "func_Menu_Handler")
}

func_RegCvars() {
	g_pCvar[PCVAR__PAUSE_VOTES] = create_cvar("gather_pause_votes", "")
	bind_pcvar_num(g_pCvar[PCVAR__PAUSE_VOTES], g_eCvar[CVAR__PAUSE_VOTES])

	g_pCvar[PCVAR__PAUSE_TIME] = create_cvar("gather_pause_time", "", .has_min = true, .min_val = 0.0)
	bind_pcvar_num(g_pCvar[PCVAR__PAUSE_TIME], g_eCvar[CVAR__PAUSE_TIME])

	g_pCvar[PCVAR__PAUSES_PER_TEAM] = create_cvar("gather_pauses_per_team", "")
	bind_pcvar_num(g_pCvar[PCVAR__PAUSES_PER_TEAM], g_eCvar[CVAR__PAUSES_PER_TEAM])

	g_pCvar[PCVAR__GAMEMENU_HUD] = create_cvar("gather_gamemenu_hud", "")
	set_pcvar_string(g_pCvar[PCVAR__GAMEMENU_HUD], "") // Обеспечиваем вызов квархука значением из конфига
	hook_cvar_change(g_pCvar[PCVAR__GAMEMENU_HUD], "hook_CvarChange")

	g_pCvar[PCVAR__GIVE_UP_VOTES] = create_cvar("gather_give_up_votes", "")
	bind_pcvar_num(g_pCvar[PCVAR__GIVE_UP_VOTES], g_eCvar[CVAR__GIVE_UP_VOTES])

	g_pCvar[PCVAR__FREEZETIME] = get_cvar_pointer("mp_freezetime")

	g_pCvar[PCVAR__TIMEOUT_HUD] = create_cvar("gather_timeout_hud", "")
	set_pcvar_string(g_pCvar[PCVAR__TIMEOUT_HUD], "") // Обеспечиваем вызов квархука значением из конфига
	hook_cvar_change(g_pCvar[PCVAR__TIMEOUT_HUD], "hook_CvarChange")

	g_pCvar[PCVAR__VOTEBAN_VOTES] = create_cvar("gather_voteban_votes", "")
	bind_pcvar_num(g_pCvar[PCVAR__VOTEBAN_VOTES], g_eCvar[CVAR__VOTEBAN_VOTES])

	g_pCvar[PCVAR__VOTEBAN_CMD] = create_cvar("gather_voteban_cmd", "")
	bind_pcvar_string(g_pCvar[PCVAR__VOTEBAN_CMD], g_eCvar[CVAR__VOTEBAN_CMD], chx(g_eCvar[CVAR__VOTEBAN_CMD]))

	g_pCvar[PCVAR__VOTEKICK_VOTES] = create_cvar("gather_votekick_votes", "")
	bind_pcvar_num(g_pCvar[PCVAR__VOTEKICK_VOTES], g_eCvar[CVAR__VOTEKICK_VOTES])

	g_pCvar[PCVAR__VOTEKICK_CMD] = create_cvar("gather_votekick_cmd", "")
	bind_pcvar_string(g_pCvar[PCVAR__VOTEKICK_CMD], g_eCvar[CVAR__VOTEKICK_CMD], chx(g_eCvar[CVAR__VOTEKICK_CMD]))

	bind_pcvar_num(create_cvar("gather_give_up_score_diff", ""), g_eCvar[CVAR__GIVE_UP_SCORE_DIFF])

	bind_pcvar_num(create_cvar("gather_give_up_min_round", ""), g_eCvar[CVAR__GIVE_UP_MIN_ROUND])
}

public hook_CvarChange(pCvar, const szOldVal[], const szNewVal[]) {
	new szColor[3][5], szPos[2][8]

	parse( szNewVal,
		szColor[0], chx(szColor[]),
		szColor[1], chx(szColor[]),
		szColor[2], chx(szColor[]),
		szPos[0], chx(szPos[]),
		szPos[1], chx(szPos[])
	);

	if(pCvar == g_pCvar[PCVAR__GAMEMENU_HUD]) {
		g_eCvar[CVAR__GAMEMENU_HUD_R] = str_to_num(szColor[0])
		g_eCvar[CVAR__GAMEMENU_HUD_G] = str_to_num(szColor[1])
		g_eCvar[CVAR__GAMEMENU_HUD_B] = str_to_num(szColor[2])
		g_eCvar[CVAR_F__GAMEMENU_HUD_X] = str_to_float(szPos[0])
		g_eCvar[CVAR_F__GAMEMENU_HUD_Y] = str_to_float(szPos[1])
	}
	else if(pCvar == g_pCvar[PCVAR__TIMEOUT_HUD]) {
		g_eCvar[CVAR__TIMEOUT_HUD_R] = str_to_num(szColor[0])
		g_eCvar[CVAR__TIMEOUT_HUD_G] = str_to_num(szColor[1])
		g_eCvar[CVAR__TIMEOUT_HUD_B] = str_to_num(szColor[2])
		g_eCvar[CVAR_F__TIMEOUT_HUD_X] = str_to_float(szPos[0])
		g_eCvar[CVAR_F__TIMEOUT_HUD_Y] = str_to_float(szPos[1])
	}
}

public gather_synchud_announce(const hHudSyncObj[GATHER_SYNCOBJ_ENUM]) {
	g_hHudSyncObj = hHudSyncObj
}

public gather_configured() {
	set_task(1.0, "task_ShowHUD", TASKID__HUD, .flags = "b")
}

public task_ShowHUD() {
	if(!g_eCvar[CVAR__GAMEMENU_HUD_R] && !g_eCvar[CVAR__GAMEMENU_HUD_G] && !g_eCvar[CVAR__GAMEMENU_HUD_B]) {
		return
	}
	
	set_hudmessage( g_eCvar[CVAR__GAMEMENU_HUD_R], g_eCvar[CVAR__GAMEMENU_HUD_G], g_eCvar[CVAR__GAMEMENU_HUD_B],
		g_eCvar[CVAR_F__GAMEMENU_HUD_X], g_eCvar[CVAR_F__GAMEMENU_HUD_Y], 0, 0.0, 1.0, 0.1, 0.1 );

	new pPlayers[MAX_PLAYERS], iPlCount, pPlayer
	get_players(pPlayers, iPlCount, "ch")

	for(new i; i < iPlCount; i++) {
		pPlayer = pPlayers[i]

		if(g_bMenuHided[pPlayer]) {
			continue
		}

		ShowSyncHudMsg(pPlayer, g_hHudSyncObj[_HUDOBJ_GAMEMENU_INFO], "%l", "GATHER__GAMEMENU_INFO", MENU_CLCMDS[0])
	}
}

public client_putinserver(pPlayer) {
	g_bMenuHided[pPlayer] = false
}

public clcmd_OpenMenu(pPlayer) {
	if(!is_user_connected(pPlayer)) {
		return PLUGIN_HANDLED
	}

	if(check_menu_by_menuid(pPlayer, g_iMenuID)) {
		close_menu(pPlayer)
		return PLUGIN_HANDLED
	}

	func_MainMenu(pPlayer)

	return PLUGIN_HANDLED
}

bool:CanReady(pPlayer, iInMatch, GatherMatchState:iMatchState) {
	return (iInMatch && !gather_is_player_ready(pPlayer) && IsInGame(pPlayer) && iMatchState == MATCH_GATHERING)
}

bool:CanUnReady(pPlayer, iInMatch, GatherMatchState:iMatchState) {
	return (iInMatch && gather_is_player_ready(pPlayer) && IsInGame(pPlayer) && iMatchState == MATCH_GATHERING)
}

bool:CanPause(pPlayer, iInMatch, GatherMatchState:iMatchState, bool:bCheckUsage) {
	if(
		!iInMatch
			||
		!IsInGame(pPlayer)
			||
		!IsMatchStatePausable(iMatchState)
			||
		!g_eCvar[CVAR__PAUSE_TIME]
			||
		(bCheckUsage && g_bPause[pPlayer])
	) {
		return false
	}

	return (g_iUsedPauses[ rg_get_user_team(pPlayer) ] < g_eCvar[CVAR__PAUSES_PER_TEAM])
}

bool:CanGiveUp(pPlayer, iInMatch, GatherMatchState:iMatchState, bool:bCheckUsage) {
	const GIVE_UP_STATES_BITS = BIT(_:MATCH_ACTIVE_1ST)|BIT(_:MATCH_ACTIVE_2ST)|BIT(_:MATCH_OVERTIME)

	if(
		!iInMatch
			||
		!g_eCvar[CVAR__GIVE_UP_VOTES]
			||
		!IsInGame(pPlayer)
			||
		!(GIVE_UP_STATES_BITS & BIT(_:iMatchState))
			||
		(bCheckUsage && g_bGiveUp[pPlayer])
	) {
		return false
	}

	if(gather_get_current_round() < g_eCvar[CVAR__GIVE_UP_MIN_ROUND]) {
		return false
	}

	if(g_eCvar[CVAR__GIVE_UP_SCORE_DIFF]) {
		new TeamName:iTeam = get_member(pPlayer, m_iTeam)
		new TeamName:iOppositeTeam = (iTeam == TEAM_CT) ? TEAM_TERRORIST : TEAM_CT;

		new iScore[TeamName]
		iScore[TEAM_TERRORIST] = get_member_game(m_iNumTerroristWins)
		iScore[TEAM_CT] = get_member_game(m_iNumCTWins)

		if(iScore[iTeam] >= iScore[iOppositeTeam]) { //  команда игрока не проигрывает
			return false
		}

		if(iScore[iOppositeTeam] - iScore[iTeam] < g_eCvar[CVAR__GIVE_UP_SCORE_DIFF]) { // команда игрок проигрывает меньше очков, чем пороговое значение
			return false
		}
	}

	return true
}

bool:CanVoteBan(pPlayer, iInMatch, GatherMatchState:iMatchState) {
	const VOTEBAN_STATES_BITS = BIT(_:MATCH_ACTIVE_1ST)|BIT(_:MATCH_ACTIVE_2ST)|BIT(_:MATCH_OVERTIME)

	if(
		!iInMatch
			||
		!IsInGame(pPlayer)
			||
		!(VOTEBAN_STATES_BITS & BIT(_:iMatchState))
	) {
		return false
	}

	return true
}

bool:CanVoteKick(pPlayer, iInMatch, GatherMatchState:iMatchState) {
	const VOTEKICK_STATES_BITS = BIT(_:MATCH_ACTIVE_1ST)|BIT(_:MATCH_ACTIVE_2ST)|BIT(_:MATCH_OVERTIME)

	if(
		!iInMatch
			||
		!IsInGame(pPlayer)
			||
		!(VOTEKICK_STATES_BITS & BIT(_:iMatchState))
	) {
		return false
	}

	return true
}

func_MainMenu(pPlayer) {
	new iInMatch = gather_is_player_in_match(pPlayer)
	new GatherMatchState:iMatchState = gather_get_match_state()

	new iReadyNum = 'r', iReadyChar = 'w'

	if(!CanReady(pPlayer, iInMatch, iMatchState)) {
		iReadyNum = iReadyChar = 'd'
	}

	new iUnReadyNum = 'r', iUnReadyChar = 'w'

	if(!CanUnReady(pPlayer, iInMatch, iMatchState)) {
		iUnReadyNum = iUnReadyChar = 'd'
	}

	new iPauseNum = 'r', iPauseChar = 'w'

	if(!CanPause(pPlayer, iInMatch, iMatchState, .bCheckUsage = true)) {
		iPauseNum = iPauseChar = 'd'
	}

	new iNeedPause = g_eCvar[CVAR__PAUSE_VOTES]

	new iGiveUpNum = 'r', iGiveUpChar = 'w'

	if(!CanGiveUp(pPlayer, iInMatch, iMatchState, .bCheckUsage = true)) {
		iGiveUpNum = iGiveUpChar = 'd'
	}

	new iVoteBanNum = 'r', iVoteBanChar = 'w'

	if(!CanVoteBan(pPlayer, iInMatch, iMatchState)) {
		iVoteBanNum = iVoteBanChar = 'd'
	}

	new iVoteKickNum = 'r', iVoteKickChar = 'w'

	if(!CanVoteKick(pPlayer, iInMatch, iMatchState)) {
		iVoteKickNum = iVoteKickChar = 'd'
	}

	new iNeedGiveUp = g_eCvar[CVAR__GIVE_UP_VOTES]

	SetGlobalTransTarget(pPlayer)

	new szPauseAdd[64]

	if(g_eCvar[CVAR__PAUSE_TIME]) {
		formatex(szPauseAdd, chx(szPauseAdd), " %l", "GATHER__PAUSE_ADD", g_eCvar[CVAR__PAUSE_TIME])
	}

	formatex( g_szMenu, chx(g_szMenu),
		"\y%l^n\
		^n\
		\%c1. \%c%l^n\
		\%c2. \%c%l^n\
		\%c3. \%c%l%s%s^n\
		\%c4. \%c%l%s^n\
		\%c5. \%c%l^n\
		\%c6. \%c%l^n\
		\r7. \w%l: %l^n\
		^n\
		\r0. \w%l",

		"GATHER__MAIN_MENU_TITLE",

		iReadyNum, iReadyChar, "GATHER__MENU_READY",
		iUnReadyNum, iUnReadyChar, "GATHER__MENU_NOT_READY",
		iPauseNum, iPauseChar, "GATHER__MENU_PAUSE", szPauseAdd, fmt(CanPause(pPlayer, iInMatch, iMatchState, .bCheckUsage = false) ? " \y[%i/%i]" : "", GetPause(pPlayer), iNeedPause),
		iGiveUpNum, iGiveUpChar, "GATHER__MENU_GIVE_UP", fmt(CanGiveUp(pPlayer, iInMatch, iMatchState, .bCheckUsage = false) ? " \y[%i/%i]" : "", GetGiveUp(pPlayer), iNeedGiveUp),
		iVoteBanNum, iVoteBanChar, "GATHER__MENU_VOTEBAN",
		iVoteKickNum, iVoteKickChar, "GATHER__MENU_VOTEKICK",
		"GATHER__GAMEMENU_HUD", g_bMenuHided[pPlayer] ? "GATHER__MENU_NO" : "GATHER__MENU_YES",

		"GATHER__EXIT"
	);

	const MENU_KEYS = MENU_KEY_1|MENU_KEY_2|MENU_KEY_3|MENU_KEY_4|MENU_KEY_5|MENU_KEY_6|MENU_KEY_7|MENU_KEY_0

	func_ShowMenu(pPlayer, MENU_KEYS, MENU_MODE__MAIN)
}

GetPause(pPlayer) {
	new TeamName:iTeam = rg_get_user_team(pPlayer)

	new pPlayers[MAX_PLAYERS], iPlCount, pGamer, iCount
	get_players(pPlayers, iPlCount, "ch")

	for(new i; i < iPlCount; i++) {
		pGamer = pPlayers[i]

		if(g_bPause[pGamer] && rg_get_user_team(pGamer) == iTeam) {
			iCount++
		}
	}

	return iCount
}

GetGiveUp(pPlayer) {
	new TeamName:iTeam = rg_get_user_team(pPlayer)

	new pPlayers[MAX_PLAYERS], iPlCount, pGamer, iCount
	get_players(pPlayers, iPlCount, "ch")

	for(new i; i < iPlCount; i++) {
		pGamer = pPlayers[i]

		if(g_bGiveUp[pGamer] && rg_get_user_team(pGamer) == iTeam) {
			iCount++
		}
	}

	return iCount
}

public func_Menu_Handler(pPlayer, iKey) {
	switch(g_iMenuMode[pPlayer]) {
		case MENU_MODE__MAIN: func_MainMenu_SubHandler(pPlayer, iKey)
		case MENU_MODE__VOTEBAN_MENU: func_VoteBanMenu_SubHandler(pPlayer, iKey)
		case MENU_MODE__VOTEKICK_MENU: func_VoteKickMenu_SubHandler(pPlayer, iKey)
	}

	return PLUGIN_HANDLED
}

func_MainMenu_SubHandler(pPlayer, iKey) {
	new iInMatch = gather_is_player_in_match(pPlayer)
	new GatherMatchState:iMatchState = gather_get_match_state()

	switch(iKey) {
		case _KEY1_: {
			if(!CanReady(pPlayer, iInMatch, iMatchState)) {
				func_MainMenu(pPlayer)
				return
			}

			gather_set_player_ready(pPlayer, .bReady = true)

			new pPlayers[MAX_PLAYERS], iPlCount, pPlayer, iReadyCount
			get_players(pPlayers, iPlCount, "ch") // exclude bots and hltv

			for(new i; i < iPlCount; i++) {
				pPlayer = pPlayers[i]

				if(gather_is_player_in_match(pPlayer) && gather_is_player_ready(pPlayer)) {
					iReadyCount++
				}
			}

			if(iReadyCount == gather_get_maxplayers()) {
				gather_set_match_state(MATCH_INIT)
			}
		}
		case _KEY2_: {
			if(!CanUnReady(pPlayer, iInMatch, iMatchState)) {
				func_MainMenu(pPlayer)
				return
			}

			gather_set_player_ready(pPlayer, .bReady = false)
		}
		case _KEY3_: {
			if(!CanPause(pPlayer, iInMatch, iMatchState, .bCheckUsage = true)) {
				func_MainMenu(pPlayer)
				return
			}

			if(g_iTimeout) {
				rg_send_audio(pPlayer, SOUND__ERROR)
				client_print_color(pPlayer, print_team_red, "%l", "GATHER__ALREADY_TIMEOUT")
				func_MainMenu(pPlayer)
				return
			}

			new any:iTeam = rg_get_user_team(pPlayer)
			new iNeedPause = g_eCvar[CVAR__PAUSE_VOTES]
			g_bPause[pPlayer] = true

			new iPauseCount = GetPause(pPlayer)

			if(iPauseCount < iNeedPause) {
				client_print_color( 0, pPlayer, "%L", LANG_PLAYER, "GATHER__PAUSE_VOTE",
					pPlayer, iPauseCount, iNeedPause );
			}
			else {
				rg_send_audio(0, SOUND__BELL1)

				arrayset(g_bPause, false, sizeof(g_bPause))

				g_iTimeOutTeam = iTeam
				g_iUsedPauses[iTeam]++

				client_print_color(0, pPlayer, "%L", LANG_PLAYER, "GATHER__TIMEOUT_REQUEST", pPlayer, g_eCvar[CVAR__PAUSE_TIME])

				if(!get_member_game(m_bFreezePeriod)) {
					g_iTimeout = g_eCvar[CVAR__PAUSE_TIME]
				}
				else {
					g_iCurrTimeOutTeam = iTeam
					g_iCurrTimeOut += g_eCvar[CVAR__PAUSE_TIME]
					set_member_game(m_iRoundTimeSecs, get_member_game(m_iRoundTimeSecs) + g_eCvar[CVAR__PAUSE_TIME])

					new Float:tmRemaining = float(get_member_game(m_iRoundTimeSecs)) - (get_gametime() - Float:get_member_game(m_fRoundStartTime))

					message_begin(MSG_BROADCAST, get_user_msgid("RoundTime"))
					write_short(floatround(tmRemaining))
					message_end()

					client_print_color( 0, (g_iCurrTimeOutTeam == TEAM_CT) ? print_team_blue : print_team_red,
						"%L", LANG_PLAYER, task_exists(TASKID__TIMEOUT_HUD) ? "GATHER__TIMEOUT_EXT_CHAT" : "GATHER__TIMEOUT_SET_CHAT",
						LANG_PLAYER, (g_iCurrTimeOutTeam == TEAM_CT) ? "GATHER__TIMEOUT_SET_CT" : "GATHER__TIMEOUT_SET_TT", g_eCvar[CVAR__PAUSE_TIME] );

					func_PauseAction()
				}
			}
		}
		case _KEY4_: {
			if(!CanGiveUp(pPlayer, iInMatch, iMatchState, .bCheckUsage = true)) {
				func_MainMenu(pPlayer)
				return
			}

			new any:iTeam = rg_get_user_team(pPlayer)
			new iNeedGiveUp = g_eCvar[CVAR__GIVE_UP_VOTES]
			g_bGiveUp[pPlayer] = true

			new iGiveUpCount = GetGiveUp(pPlayer)

			client_print_color( 0, pPlayer, "%L", LANG_PLAYER, "GATHER__GIVE_UP_VOTE",
				pPlayer, iGiveUpCount, iNeedGiveUp );

			if(iGiveUpCount >= iNeedGiveUp) {
				rg_send_audio(0, SOUND__BELL1)

				client_print_color( 0, (iTeam == TEAM_CT) ? print_team_blue : print_team_red, "%L",
					LANG_PLAYER, "GATHER__GIVE_UP_INFO",
					LANG_PLAYER, (iTeam == TEAM_CT) ? "GATHER__GIVE_UP_CT" : "GATHER__GIVE_UP_TT",
					get_member_game(m_iNumTerroristWins), get_member_game(m_iNumCTWins)
				);

				gather_set_match_winner(iTeam == TEAM_CT ? TEAM_TERRORIST : TEAM_CT)

				gather_set_match_state(MATCH_OVER)

				if(!get_member_game(m_bRoundTerminating)) {
					rg_round_end(0.0, WINSTATUS_DRAW, ROUND_END_DRAW, .message = "", .sentence = "", .trigger = true)
				}
			}
		}
		case _KEY5_: {
			if(!CanVoteBan(pPlayer, iInMatch, iMatchState)) {
				func_MainMenu(pPlayer)
				return
			}

			func_VoteBanMenu(pPlayer, _PAGE1_)
		}
		case _KEY6_: {
			if(!CanVoteKick(pPlayer, iInMatch, iMatchState)) {
				func_MainMenu(pPlayer)
				return
			}

			func_VoteKickMenu(pPlayer, _PAGE1_)
		}
		case _KEY7_: {
			g_bMenuHided[pPlayer] = !g_bMenuHided[pPlayer]
		}
	}
}

// Свапаем счётчик пауз при пересменке. Так же свапаем команду-заказчик паузы. Этот форвард срабатывает ДО
//	gather_check_timeout_rules(), смотри gather_live.sma -> gather_call_timeout_forward()
public gather_match_state_changed(GatherMatchState:iNewMatchState) {
	if(iNewMatchState == MATCH_ACTIVE_2ST) {
		new iUsedTT = g_iUsedPauses[TEAM_TERRORIST]
		new iUsedCT = g_iUsedPauses[TEAM_CT]

		g_iUsedPauses[TEAM_TERRORIST] = iUsedCT
		g_iUsedPauses[TEAM_CT] = iUsedTT

		if(g_iTimeOutTeam != TEAM_UNASSIGNED) {
			g_iTimeOutTeam = (g_iTimeOutTeam == TEAM_CT) ? TEAM_TERRORIST : TEAM_CT;
		}
	}
}

// gather_live.sma в RestartRound Pre вызывает натив ядра gather_call_timeout_forward(),
// а натив уже вызывает данный форвард
public gather_check_timeout_rules() {
	if(!g_iTimeout) {
		return
	}

	new iOldFreezeTime = get_pcvar_num(g_pCvar[PCVAR__FREEZETIME])
	set_pcvar_num(g_pCvar[PCVAR__FREEZETIME], g_iTimeout)

	g_iCurrTimeOutTeam = g_iTimeOutTeam
	g_iCurrTimeOut = g_iTimeout - 1

	new iData[3]
	iData[0] = iOldFreezeTime
	iData[1] = g_iTimeout
	iData[2] = g_pPauseAdminUserId
	set_task(0.2, "task_ResetFreezetime", 0, iData, sizeof(iData))

	g_iTimeout = 0
}

public CSGameRules_RestartRound_Pre() {
	if(task_exists(TASKID__TIMEOUT_HUD)) {
		func_EndTimeout()
	}
}

func_EndTimeout() {
	remove_task(TASKID__TIMEOUT_HUD)
	g_iCurrTimeOut = 0

	if(get_cvar_num("mp_buytime") == PAUSE_CVAR_VALUE) {
		set_cvar_float("mp_buytime", g_fOldBuyTime)
	}

	if(get_cvar_num("mp_autokick_timeout") == PAUSE_CVAR_VALUE) {
		new pPlayers[MAX_PLAYERS], iPlCount, Float:fGameTime = get_gametime()
		get_players(pPlayers, iPlCount, "ch")

		for(new i; i < iPlCount; i++) {
			set_member(pPlayers[i], m_fLastMovement, fGameTime)
		}

		set_member_game(m_fMaxIdlePeriod, g_fOldMaxIdlePeriod)
		set_cvar_float("mp_autokick_timeout", g_fOldAutokickTimeout)
	}
}

public task_ResetFreezetime(const iData[]) {
	set_pcvar_num(g_pCvar[PCVAR__FREEZETIME], iData[0])

	if(g_iCurrTimeOutTeam == TEAM_UNASSIGNED) {
		new pAdmin = find_player("k", iData[2])
		client_print_color(0, GetAdminMsgColor(pAdmin), "%l", "GATHER__TIMEOUT_ADM_SET_CHAT", pAdmin, iData[1])
	}
	else {
		client_print_color( 0, (g_iCurrTimeOutTeam == TEAM_CT) ? print_team_blue : print_team_red,
			"%L", LANG_PLAYER, "GATHER__TIMEOUT_SET_CHAT",
			LANG_PLAYER, (g_iCurrTimeOutTeam == TEAM_CT) ? "GATHER__TIMEOUT_SET_CT" : "GATHER__TIMEOUT_SET_TT", iData[1] );
	}

	func_PauseAction()
}

func_PauseAction() {
	static HookChain:hRestartRound

	if(!hRestartRound) {
		hRestartRound = RegisterHookChain(RG_CSGameRules_RestartRound, "CSGameRules_RestartRound_Pre")
	}

	if(!task_exists(TASKID__TIMEOUT_HUD)) {
		set_task(1.0, "task_TimeOutHud", TASKID__TIMEOUT_HUD, .flags = "b")
		task_TimeOutHud()

		// https://github.com/s1lentq/ReGameDLL_CS/blob/c002edd5b18a8408e299bc6cccfec2c7de56ba3d/regamedll/dlls/player.cpp#L4357
		g_fOldBuyTime = get_cvar_float("mp_buytime")
		set_cvar_num("mp_buytime", PAUSE_CVAR_VALUE)

		// https://github.com/s1lentq/ReGameDLL_CS/blob/dd243eaa0b5befb96bab8f113f43bc79e9bba098/regamedll/dlls/multiplay_gamerules.cpp#L467
		g_fOldMaxIdlePeriod = get_member_game(m_fMaxIdlePeriod)
		g_fOldAutokickTimeout = get_cvar_float("mp_autokick_timeout")
		set_cvar_num("mp_autokick_timeout", PAUSE_CVAR_VALUE)
		set_member_game(m_fMaxIdlePeriod, float(PAUSE_CVAR_VALUE))
	}
}

public task_TimeOutHud() {
	if(!g_iCurrTimeOut) {
		func_EndTimeout()
		return
	}

	set_hudmessage( g_eCvar[CVAR__TIMEOUT_HUD_R], g_eCvar[CVAR__TIMEOUT_HUD_G], g_eCvar[CVAR__TIMEOUT_HUD_B],
		g_eCvar[CVAR_F__TIMEOUT_HUD_X], g_eCvar[CVAR_F__TIMEOUT_HUD_Y], 0, 0.0, 1.0, 0.1, 0.1 );

	if(g_iCurrTimeOutTeam == TEAM_UNASSIGNED) {
		ShowSyncHudMsg(0, g_hHudSyncObj[_HUDOBJ_TIMEOUT_INFO], "%L", LANG_PLAYER, "GATHER__TIMEOUT_ADM_HUD", g_iCurrTimeOut)
	}
	else {
		ShowSyncHudMsg( 0, g_hHudSyncObj[_HUDOBJ_TIMEOUT_INFO], "%L", LANG_PLAYER, "GATHER__TIMEOUT_SET_HUD",
			LANG_PLAYER, (g_iCurrTimeOutTeam == TEAM_CT) ? "GATHER__TIMEOUT_SET_CT" : "GATHER__TIMEOUT_SET_TT", g_iCurrTimeOut );
	}

	g_iCurrTimeOut--
}

func_ShowMenu(pPlayer, iKeys, iMenuMode) {
	g_iMenuMode[pPlayer] = iMenuMode
	show_menu(pPlayer, iKeys, g_szMenu, -1, MENU_IDENT_STRING)
}

const ITEMS_PER_PAGE__VOTEBAN_MENU = 7

func_VoteBanMenu(pPlayer, iPage) {
	new pPlayers[MAX_PLAYERS], iPlCount, pGamer, iRealCount, iTeam = rg_get_user_team(pPlayer)
	get_players(pPlayers, iPlCount, "ch")

	for(new i; i < iPlCount; i++) {
		pGamer = pPlayers[i]

		if(rg_get_user_team(pGamer) != iTeam || pGamer == pPlayer || g_bPunished[pGamer]) {
			continue
		}

		pPlayers[iRealCount] = pGamer
		g_iTargetUserIDs[pPlayer][iRealCount] = get_user_userid(pGamer)
		iRealCount++
	}

	/* --- */

	new i = min(iPage * ITEMS_PER_PAGE__VOTEBAN_MENU, iRealCount)
	new iStart = i - (i % ITEMS_PER_PAGE__VOTEBAN_MENU)
	new iEnd = min(iStart + ITEMS_PER_PAGE__VOTEBAN_MENU, iRealCount)

	g_iMenuPage[pPlayer] = iPage = iStart / ITEMS_PER_PAGE__VOTEBAN_MENU

	new iMenuItem, iKeys = MENU_KEY_0,
		iPagesNum = max(1, (iRealCount / ITEMS_PER_PAGE__VOTEBAN_MENU + ((iRealCount % ITEMS_PER_PAGE__VOTEBAN_MENU) ? 1 : 0)));

	/* --- */

	SetGlobalTransTarget(pPlayer)

	new iLen = formatex(g_szMenu, chx(g_szMenu), "\y%l^n^n", "GATHER__PLAYERS_MENU_TITLE", iPage + 1, iPagesNum)

	/* --- */

	for(i = iStart; i < iEnd; i++) {
		iKeys |= (1 << iMenuItem)

		pGamer = pPlayers[i]

		iLen += formatex( g_szMenu[iLen], chx_len(g_szMenu), "\r%i. \%c%n^n",
			++iMenuItem, g_bVoteBan[pPlayer][pGamer] ? 'r' : 'w', pGamer );
	}

	/* --- */

	if(!iMenuItem) {
		if(iPage) {
			func_VoteBanMenu(pPlayer, iPage - 1)
			return
		}
		else {
			iKeys |= MENU_KEY_1
			iLen += formatex(g_szMenu[iLen], chx_len(g_szMenu), "\r1. %l^n", "GATHER__NO_MENU_ITEMS")
			g_iTargetUserIDs[pPlayer][0] = 0
		}
	}

	if(iPage) {
		iKeys |= MENU_KEY_8
		iLen += formatex(g_szMenu[iLen], chx_len(g_szMenu), "^n\r8. \w%l", "GATHER__BACK")
	}

	if(iEnd < iRealCount) {
		iKeys |= MENU_KEY_9
		iLen += formatex(g_szMenu[iLen], chx_len(g_szMenu), "^n\r9. \w%l", "GATHER__NEXT")
	}

	formatex( g_szMenu[iLen], chx_len(g_szMenu), "%s^n\r0. \w%l",
		(iKeys & (MENU_KEY_8|MENU_KEY_9)) ? "^n" : "", "GATHER__EXIT" );

	func_ShowMenu(pPlayer, iKeys, MENU_MODE__VOTEBAN_MENU)
}

func_VoteBanMenu_SubHandler(pPlayer, iKey) {
	if(!CanVoteBan(pPlayer, gather_is_player_in_match(pPlayer), gather_get_match_state())) {
		return
	}

	new iMenuPage = g_iMenuPage[pPlayer]

	switch(iKey) {
		case _KEY8_: func_VoteBanMenu(pPlayer, iMenuPage - 1)
		case _KEY9_: func_VoteBanMenu(pPlayer, iMenuPage + 1)
		case _KEY0_: func_MainMenu(pPlayer)
		default: {
			new iPos = (iMenuPage * ITEMS_PER_PAGE__VOTEBAN_MENU) + iKey

			new pTarget = find_player("k", g_iTargetUserIDs[pPlayer][iPos])

			if(
				!pTarget
					||
				g_bVoteBan[pPlayer][pTarget]
					||
				g_bPunished[pTarget]
				/* || rg_get_user_team(pTarget) != rg_get_user_team(pPlayer)*/
			) {
				func_VoteBanMenu(pPlayer, iMenuPage)
				return
			}

			g_bVoteBan[pPlayer][pTarget] = true

			new pPlayers[MAX_PLAYERS], iPlCount, pGamer, iTeam = rg_get_user_team(pPlayer)
			get_players(pPlayers, iPlCount, "c")

			new iVotes

			for(new i; i < iPlCount; i++) {
				pGamer = pPlayers[i]

				if(g_bVoteBan[pGamer][pTarget]) {
					iVotes++
				}

				if(
					( rg_get_user_team(pGamer) != iTeam && !gather_can_player_spectate(pGamer))
						||
					pGamer == pTarget
				) {
					continue
				}

				client_print_color(pGamer, pPlayer, "%l", "GATHER__VOTEBAN_VOTED", pPlayer, pTarget)
			}

			if(iVotes >= g_eCvar[CVAR__VOTEBAN_VOTES]) {
				client_print_color(0, pTarget, "%L", LANG_PLAYER, "GATHER__VOTEBAN_BANNED", pTarget)

				new szBanCmd[ sizeof(g_eCvar[CVAR__VOTEBAN_CMD]) ]
				copy(szBanCmd, chx(szBanCmd), g_eCvar[CVAR__VOTEBAN_CMD])

				new szAuthID[MAX_AUTHID_LENGTH], szIP[MAX_IP_LENGTH]
				get_user_authid(pTarget, szAuthID, chx(szAuthID))
				get_user_ip(pTarget, szIP, chx(szIP), .without_port = 1)

				replace_string(szBanCmd, chx(szBanCmd), "%id%", fmt("%i", pTarget))
				replace_string(szBanCmd, chx(szBanCmd), "%userid%", fmt("%i", get_user_userid(pTarget)))
				replace_string(szBanCmd, chx(szBanCmd), "%steamid%", szAuthID)
				replace_string(szBanCmd, chx(szBanCmd), "%ip%", szIP)

				g_bPunished[pTarget] = true

				server_cmd(szBanCmd)
			}
		}
	}
}

const ITEMS_PER_PAGE__VOTEKICK_MENU = 7

func_VoteKickMenu(pPlayer, iPage) {
	new pPlayers[MAX_PLAYERS], iPlCount, pGamer, iRealCount, iTeam = rg_get_user_team(pPlayer)
	get_players(pPlayers, iPlCount, "ch")

	for(new i; i < iPlCount; i++) {
		pGamer = pPlayers[i]

		if(rg_get_user_team(pGamer) != iTeam || pGamer == pPlayer || g_bPunished[pGamer]) {
			continue
		}

		pPlayers[iRealCount] = pGamer
		g_iTargetUserIDs[pPlayer][iRealCount] = get_user_userid(pGamer)
		iRealCount++
	}

	/* --- */

	new i = min(iPage * ITEMS_PER_PAGE__VOTEKICK_MENU, iRealCount)
	new iStart = i - (i % ITEMS_PER_PAGE__VOTEKICK_MENU)
	new iEnd = min(iStart + ITEMS_PER_PAGE__VOTEKICK_MENU, iRealCount)

	g_iMenuPage[pPlayer] = iPage = iStart / ITEMS_PER_PAGE__VOTEKICK_MENU

	new iMenuItem, iKeys = MENU_KEY_0,
		iPagesNum = max(1, (iRealCount / ITEMS_PER_PAGE__VOTEKICK_MENU + ((iRealCount % ITEMS_PER_PAGE__VOTEKICK_MENU) ? 1 : 0)));

	/* --- */

	SetGlobalTransTarget(pPlayer)

	new iLen = formatex(g_szMenu, chx(g_szMenu), "\y%l^n^n", "GATHER__PLAYERS_MENU_TITLE", iPage + 1, iPagesNum)

	/* --- */

	for(i = iStart; i < iEnd; i++) {
		iKeys |= (1 << iMenuItem)

		pGamer = pPlayers[i]

		iLen += formatex( g_szMenu[iLen], chx_len(g_szMenu), "\r%i. \%c%n^n",
			++iMenuItem, g_bVoteKick[pPlayer][pGamer] ? 'r' : 'w', pGamer );
	}

	/* --- */

	if(!iMenuItem) {
		if(iPage) {
			func_VoteKickMenu(pPlayer, iPage - 1)
			return
		}
		else {
			iKeys |= MENU_KEY_1
			iLen += formatex(g_szMenu[iLen], chx_len(g_szMenu), "\r1. %l^n", "GATHER__NO_MENU_ITEMS")
			g_iTargetUserIDs[pPlayer][0] = 0
		}
	}

	if(iPage) {
		iKeys |= MENU_KEY_8
		iLen += formatex(g_szMenu[iLen], chx_len(g_szMenu), "^n\r8. \w%l", "GATHER__BACK")
	}

	if(iEnd < iRealCount) {
		iKeys |= MENU_KEY_9
		iLen += formatex(g_szMenu[iLen], chx_len(g_szMenu), "^n\r9. \w%l", "GATHER__NEXT")
	}

	formatex( g_szMenu[iLen], chx_len(g_szMenu), "%s^n\r0. \w%l",
		(iKeys & (MENU_KEY_8|MENU_KEY_9)) ? "^n" : "", "GATHER__EXIT" );

	func_ShowMenu(pPlayer, iKeys, MENU_MODE__VOTEKICK_MENU)
}

func_VoteKickMenu_SubHandler(pPlayer, iKey) {
	if(!CanVoteKick(pPlayer, gather_is_player_in_match(pPlayer), gather_get_match_state())) {
		return
	}

	new iMenuPage = g_iMenuPage[pPlayer]

	switch(iKey) {
		case _KEY8_: func_VoteKickMenu(pPlayer, iMenuPage - 1)
		case _KEY9_: func_VoteKickMenu(pPlayer, iMenuPage + 1)
		case _KEY0_: func_MainMenu(pPlayer)
		default: {
			new iPos = (iMenuPage * ITEMS_PER_PAGE__VOTEKICK_MENU) + iKey

			new pTarget = find_player("k", g_iTargetUserIDs[pPlayer][iPos])

			if(
				!pTarget
					||
				g_bVoteKick[pPlayer][pTarget]
					||
				g_bPunished[pTarget]
				/* || rg_get_user_team(pTarget) != rg_get_user_team(pPlayer)*/
			) {
				func_VoteKickMenu(pPlayer, iMenuPage)
				return
			}

			g_bVoteKick[pPlayer][pTarget] = true

			new pPlayers[MAX_PLAYERS], iPlCount, pGamer, iTeam = rg_get_user_team(pPlayer)
			get_players(pPlayers, iPlCount, "c")

			new iVotes

			for(new i; i < iPlCount; i++) {
				pGamer = pPlayers[i]

				if(g_bVoteKick[pGamer][pTarget]) {
					iVotes++
				}

				if(
					( rg_get_user_team(pGamer) != iTeam && !gather_can_player_spectate(pGamer))
						||
					pGamer == pTarget
				) {
					continue
				}

				client_print_color(pGamer, pPlayer, "%l", "GATHER__VOTEKICK_VOTED", pPlayer, pTarget)
			}

			if(iVotes >= g_eCvar[CVAR__VOTEKICK_VOTES]) {
				client_print_color(0, pTarget, "%L", LANG_PLAYER, "GATHER__VOTEKICK_KICKED", pTarget)

				new szKickCmd[ sizeof(g_eCvar[CVAR__VOTEKICK_CMD]) ]
				copy(szKickCmd, chx(szKickCmd), g_eCvar[CVAR__VOTEKICK_CMD])

				new szAuthID[MAX_AUTHID_LENGTH], szIP[MAX_IP_LENGTH]
				get_user_authid(pTarget, szAuthID, chx(szAuthID))
				get_user_ip(pTarget, szIP, chx(szIP), .without_port = 1)

				replace_string(szKickCmd, chx(szKickCmd), "%id%", fmt("%i", pTarget))
				replace_string(szKickCmd, chx(szKickCmd), "%userid%", fmt("%i", get_user_userid(pTarget)))
				replace_string(szKickCmd, chx(szKickCmd), "%steamid%", szAuthID)
				replace_string(szKickCmd, chx(szKickCmd), "%ip%", szIP)

				g_bPunished[pTarget] = true

				server_cmd(szKickCmd)
			}
		}
	}
}

stock register_menu_ex(const title[], keys, const function[], outside = 0) {
	new iMenuID = register_menuid(title, outside)
	register_menucmd(iMenuID, keys, function)
	return iMenuID
}

stock bool:check_menu_by_menuid(pPlayer, iMenuIdToCheck) {
	new iMenuID, iKeys
	get_user_menu(pPlayer, iMenuID, iKeys)
	return (iMenuID == iMenuIdToCheck)
}

stock close_menu(pPlayer) {
	show_menu(pPlayer, 0, "", 0)
}

public client_disconnected(pPlayer) {
	g_bPunished[pPlayer] = false
	g_bGiveUp[pPlayer] = false
	g_bPause[pPlayer] = false

	arrayset(g_bVoteBan[pPlayer], false, sizeof(g_bVoteBan[]))
	arrayset(g_bVoteKick[pPlayer], false, sizeof(g_bVoteKick[]))

	for(new i = 1; i <= MaxClients; i++) {
		g_bVoteBan[i][pPlayer] = false
		g_bVoteKick[i][pPlayer] = false
	}
}

public plugin_natives() {
	register_native("gather_gamemenu_try_set_timeout", "_gather_gamemenu_try_set_timeout")
}

bool:IsMatchStatePausable(GatherMatchState:iMatchState) {
	const PAUSABLE_STATES_BITS = BIT(_:MATCH_ACTIVE_1ST)|BIT(_:MATCH_ACTIVE_2ST)|BIT(_:MATCH_OVERTIME)

	if(PAUSABLE_STATES_BITS & BIT(_:iMatchState)) {
		return true
	}

	return false
}

public TrySetTimeoutStates:_gather_gamemenu_try_set_timeout() {
	enum { arg_player = 1, arg_seconds }

	new GatherMatchState:iMatchState = gather_get_match_state()

	if(!IsMatchStatePausable(iMatchState)) {
		return TrySetTimeout__MatchStateNotPausable
	}

	if(g_iTimeout) {
		return TrySetTimeout__AlreadySet
	}

	new iSeconds = get_param(arg_seconds)

	if(!iSeconds) {
		iSeconds = g_eCvar[CVAR__PAUSE_TIME]

		if(!iSeconds) {
			iSeconds = 60 // default 'gather_pause_time' cvar value
		}
	}

	new pPlayer = get_param(arg_player)

	rg_send_audio(0, SOUND__BELL1)

	arrayset(g_bPause, false, sizeof(g_bPause))

	g_iTimeOutTeam = TEAM_UNASSIGNED

	if(!get_member_game(m_bFreezePeriod)) {
		g_pPauseAdminUserId = get_user_userid(pPlayer)
		client_print_color(0, GetAdminMsgColor(pPlayer), "%l", "GATHER__ADM_TIMEOUT_REQUEST", pPlayer, iSeconds)
		g_iTimeout = iSeconds
		return TrySetTimeout__TimeoutPlanned
	}

	g_iCurrTimeOutTeam = TEAM_UNASSIGNED
	g_iCurrTimeOut += iSeconds
	set_member_game(m_iRoundTimeSecs, get_member_game(m_iRoundTimeSecs) + iSeconds)

	new Float:tmRemaining = float(get_member_game(m_iRoundTimeSecs)) - (get_gametime() - Float:get_member_game(m_fRoundStartTime))

	message_begin(MSG_BROADCAST, get_user_msgid("RoundTime"))
	write_short(floatround(tmRemaining))
	message_end()

	client_print_color(0, GetAdminMsgColor(pPlayer), "%l", task_exists(TASKID__TIMEOUT_HUD) ? "GATHER__TIMEOUT_ADM_EXT_CHAT" : "GATHER__TIMEOUT_ADM_SET_CHAT", pPlayer, iSeconds)

	new bool:bTaskExists = bool:task_exists(TASKID__TIMEOUT_HUD)

	func_PauseAction()

	return bTaskExists ? TrySetTimeout__TimeoutExtended : TrySetTimeout__TimeoutSet;
}

GetAdminMsgColor(pPlayer) {
	if(pPlayer > 0) {
		return pPlayer
	}

	return print_team_grey
}
global function _CustomTDM_Init
global function _RegisterLocation


enum eTDMState
{
	IN_PROGRESS = 0
	WINNER_DECIDED = 1
}

struct {
    int tdmState = eTDMState.IN_PROGRESS
    array<entity> playerSpawnedProps
    LocationSettings& selectedLocation

    array<LocationSettings> locationSettings
} file;


void function _CustomTDM_Init()
{
	SetGameState( eGameState.WaitingForPlayers )

    AddCallback_OnPlayerKilled(void function(entity victim, entity attacker, var damageInfo) {thread SV_OnPlayerDied(victim, attacker, damageInfo)})
    AddCallback_OnClientConnected( void function(entity player) { thread SV_OnPlayerConnected(player) } )
    AddClientCommandCallback("next_round", ClientCommand_NextRound)
        
    thread RunTDM()
}

void function DEBUG_TestSpawnLocs(entity player)
{
    foreach(locationSetting in file.locationSettings)
    {
        foreach(teamSpawnsArray in locationSetting.spawns)
        {
            foreach(spawn in teamSpawnsArray)
            {
                player.SetOrigin(OriginToGround(spawn.origin))
                player.SetAngles(spawn.angles)
                wait 2
                if(!IsAlive(player)) {
                    WaitForever()
                    DoRespawnPlayer(player, null)
                }
            }
        }
    }
}

void function _RegisterLocation(LocationSettings locationSettings)
{
    file.locationSettings.append(locationSettings)
}

LocPair function SV_GetVotingLocation()
{
    switch(GetMapName())
    {
        case "mp_rr_canyonlands_64k_x_64k":
            return NewLocPair(<-6252, -16500, 3296>, <0, 0, 0>)
        case "mp_rr_desertlands_64k_x_64k":
            return NewLocPair(<1763, 5463, -3145>, <5, -95, 0>)
        default:
            Assert(false, "No voting location for the map!")
    }
    unreachable
}

void function SV_OnPropDynamicSpawned(entity prop)
{
    file.playerSpawnedProps.append(prop)
    
}
void function RunTDM()
{
    WaitPrematch()
    AddSpawnCallback("prop_dynamic", SV_OnPropDynamicSpawned)
    wait 5
    for(; ; )
    {
        VotingPhase();
        StartRound();
    }
    WaitForever()
}

void function DestroyPlayerProps()
{
    foreach(prop in file.playerSpawnedProps)
    {
        if(IsValid(prop))
            prop.Destroy()
    }
    file.playerSpawnedProps.clear()
}

void function WaitPrematch() 
{
    array<entity> players = GetPlayerArray()
    while(players.len() < MIN_NUMBER_OF_PLAYERS)
    {
        players = GetPlayerArray()
        wait 0.5
    }
}


void function VotingPhase()
{
    DestroyPlayerProps();
    SetGameState(eGameState.MapVoting)
    
    //Reset scores
    GameRules_SetTeamScore(TEAM_IMC, 0)
    GameRules_SetTeamScore(TEAM_MILITIA, 0)
    
    foreach(player in GetPlayerArray()) 
    {
        if(!IsValid(player)) continue;
        if(!IsAlive(player))
        {
            DoRespawnPlayer(player, null)
        }
        MakeInvincible(player)
		HolsterAndDisableWeapons( player )
        player.ForceStand()
        player.SetHealth( 100 )
        Remote_CallFunction_NonReplay(player, "ServerCallback_TDM_DoAnnouncement", 2, eTDMAnnounce.VOTING_PHASE)
        TpPlayerToSpawnPoint(player)
    }
    wait VOTING_TIME

    int choice = RandomIntRangeInclusive(0, file.locationSettings.len() - 1)

    file.selectedLocation = file.locationSettings[choice]
    
    foreach(player in GetPlayerArray())
    {
        Remote_CallFunction_NonReplay(player, "ServerCallback_TDM_SetSelectedLocation", choice)
    }
}

void function StartRound() 
{
    SetGameState(eGameState.Playing)

    foreach(player in GetPlayerArray())
    {
        Remote_CallFunction_NonReplay(player, "ServerCallback_TDM_DoLocationIntroCutscene")
        thread ScreenFadeToFromBlack(player)
    }
    wait 1
    foreach(player in GetPlayerArray())
    {
        if(!IsAlive(player))
        {
            DoRespawnPlayer(player, null)
            player.SetHealth( 100 )
        }
        TpPlayerToSpawnPoint(player)
        
    }
    foreach(player in GetPlayerArray())
    {
        Remote_CallFunction_NonReplay(player, "ServerCallback_TDM_DoAnnouncement", 4, eTDMAnnounce.MAP_FLYOVER)
    }
    wait LOCATION_CUTSCENE_DURATION
    // foreach(player in GetPlayerArray())
    // {
    //     thread ScreenFadeToFromBlack(player)
    // }
    wait 2
    foreach(player in GetPlayerArray())
    {
        Remote_CallFunction_NonReplay(player, "ServerCallback_TDM_DoAnnouncement", 5, eTDMAnnounce.ROUND_START)
        ClearInvincible(player)
        DeployAndEnableWeapons(player)
        player.UnforceStand()
        
    }
    float endTime = Time() + ROUND_TIME
    while( Time() <= endTime )
	{
        if(file.tdmState == eTDMState.WINNER_DECIDED)
            break
		WaitFrame()
	}
    file.tdmState = eTDMState.IN_PROGRESS
}


void function ScreenFadeToFromBlack(entity player, float fadeTime = 1, float holdTime = 1)
{
    ScreenFadeToBlack(player, fadeTime / 2, holdTime / 2)
    wait fadeTime
    ScreenFadeFromBlack(player, fadeTime / 2, holdTime / 2)
}

bool function ClientCommand_NextRound(entity player, array<string> args)
{
    file.tdmState = eTDMState.WINNER_DECIDED
    return true
}


void function FillPlayerToNeedyTeam(entity player)
{
    Assert(teams.len() > 0, "You need to define at least one team!")
    int minTeam = teams[0]
    int minPlayersOfTeam = GetPlayerArrayOfTeam(minTeam).len()
    
    foreach(team in teams)
    {
        printt("TEAM ", team, ": ")
        foreach(pl in GetPlayerArrayOfTeam(team))
            printt(pl, ", ")

        print("\n")
        int playersOfTeam = GetPlayerArrayOfTeam(team).len()
        if(playersOfTeam < minPlayersOfTeam)
        {
            minPlayersOfTeam = playersOfTeam
            minTeam = team
        }
    }
    SetTeam(player, minTeam)
}

void function SV_OnPlayerConnected(entity player)
{
    wait 1.5
    // set index of team
    int index = GetPlayerArrayOfTeam(player.GetTeam()).len() - 1
    player.SetTeamMemberIndex(index)

    player.SetPlayerSettingsWithMods($"settings/player/mp/pilot_survival_firesupport.rpak", [])
    player.GiveWeapon("mp_weapon_melee_survival", OFFHAND_MELEE )
    //Give passive regen (pilot blood)
    GivePassive(player, ePassives.PAS_PILOT_BLOOD)

    DoRespawnPlayer(player, null)
    SetPlayerSettings(player, TDM_PLAYER_SETTINGS)
    PlayerRestoreHP(player, 100, 65)
    TpPlayerToSpawnPoint(player)


    switch(GetGameState())
    {
    case eGameState.Playing:
        Remote_CallFunction_NonReplay(player, "ServerCallback_TDM_DoAnnouncement", 5, eTDMAnnounce.ROUND_START)

        break

    default: 
        break
    }
}



void function SV_OnPlayerDied(entity victim, entity attacker, var damageInfo) 
{
    switch(GetGameState())
    {
    case eGameState.Playing:

        if(IsValid(victim) && !IsAlive(victim))
        {
            array<entity> weapons = GetPrimaryWeapons(victim)
            array<WeaponKit> weaponNames = []

            foreach(weapon in weapons)
            {
                weaponNames.push(NewWeaponKit(weapon.GetWeaponClassName(), weapon.GetMods(), WEAPON_INVENTORY_SLOT_ANY))
            }

            entity offhand = victim.GetOffhandWeapon(OFFHAND_SPECIAL)

            if(offhand)
                weaponNames.push(NewWeaponKit(offhand.GetWeaponClassName(), offhand.GetMods(), OFFHAND_SPECIAL))
            
            wait 1.5
            
            DoRespawnPlayer(victim, null)
            SetPlayerSettings(victim, TDM_PLAYER_SETTINGS)
            PlayerRestoreHP(victim, 100, 100)
            

            TpPlayerToSpawnPoint(victim)
            PlayerRestoreWeapons(victim, weaponNames)
            thread GrantSpawnImmunity(victim, 3)
        }

        if(attacker.IsPlayer() && IsAlive(attacker) && attacker != victim)
        {
            int score = GameRules_GetTeamScore(attacker.GetTeam());
            score++;
            GameRules_SetTeamScore(attacker.GetTeam(), score);
            if(score >= SCORE_GOAL_TO_WIN)
            {
                foreach( entity player in GetPlayerArray() )
                {
                    thread EmitSoundOnEntityOnlyToPlayer( player, player, "diag_ap_aiNotify_winnerFound" )
                }
                file.tdmState = eTDMState.WINNER_DECIDED
            }
            PlayerRestoreHP(attacker, 100, 100)
        }
        
        //Tell each player to update their Score RUI
        foreach(player in GetPlayerArray())
        {
            Remote_CallFunction_NonReplay(player, "ServerCallback_TDM_PlayerKilled")
        }
        break
    default:

    }
}

void function PlayerRestoreHP(entity player, float health, float shields)
{
    player.SetHealth( health )
    Inventory_SetPlayerEquipment(player, "helmet_pickup_lv4_abilities", "helmet")

    if(shields == 0) return;
    else if(shields <= 50)
        Inventory_SetPlayerEquipment(player, "armor_pickup_lv1", "armor")
    else if(shields <= 75)
        Inventory_SetPlayerEquipment(player, "armor_pickup_lv2", "armor")
    else if(shields <= 100)
        Inventory_SetPlayerEquipment(player, "armor_pickup_lv3", "armor")
    player.SetShieldHealth( shields )

}
void function PlayerRestoreWeapons(entity player, array<WeaponKit> weaponKits = [])
{
    foreach(weaponKit in weaponKits)
    {
        switch(weaponKit.slot)
        {
            case OFFHAND_SPECIAL:
            case OFFHAND_INVENTORY:
            
            player.GiveOffhandWeapon(weaponKit.weapon, weaponKit.slot, weaponKit.mods)
            break;

            case WEAPON_INVENTORY_SLOT_ANY:
            default:
            player.GiveWeapon(weaponKit.weapon, weaponKit.slot, weaponKit.mods)
        }
        
    }
}

void function GrantSpawnImmunity(entity player, float duration)
{
    if(!IsValid(player)) return;
    MakeInvincible(player)
    wait duration
    if(!IsValid(player)) return;
    ClearInvincible(player)
}


LocPair function SV_GetAppropriateSpawnLocation(entity player)
{
    int ourTeam = player.GetTeam()

    LocPair selectedSpawn

    switch(GetGameState())
    {
    case eGameState.MapVoting:
        selectedSpawn = SV_GetVotingLocation()
        break
    case eGameState.Playing:
        float maxDistToEnemy = 0
        foreach(spawn in file.selectedLocation.spawns[ourTeam])
        {
            vector enemyOrigin = GetClosestEnemyToOrigin(spawn.origin, ourTeam)
            float distToEnemy = Length2D(spawn.origin - enemyOrigin)

            if(distToEnemy > maxDistToEnemy)
            {
                maxDistToEnemy = distToEnemy
                selectedSpawn = spawn
            }
        }
        break

    }
    return selectedSpawn
}

vector function GetClosestEnemyToOrigin(vector origin, int ourTeam)
{
    float minDist = -1
    vector enemyOrigin = <0, 0, 0>

    foreach(team in teams)
    {
        if(ourTeam == team) continue;

        foreach(player in GetPlayerArrayOfTeam(team))
        {
            float dist = Length2D(player.GetOrigin() - origin)
            if(dist < minDist || minDist < 0)
            {
                minDist = dist
                enemyOrigin = player.GetOrigin()
            }
        }
    }

    return enemyOrigin
}

void function TpPlayerToSpawnPoint(entity player)
{
	
	LocPair loc = SV_GetAppropriateSpawnLocation(player)

    player.SetOrigin(loc.origin)
    player.SetAngles(loc.angles)

    
    PutEntityInSafeSpot( player, null, null, player.GetOrigin() + <0,0,128>, player.GetOrigin() )
}

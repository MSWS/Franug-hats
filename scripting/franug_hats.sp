/*  SM Franug Hats
 *
 *  Copyright (C) 2017-2019 Francisco 'Franc1sco' García
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see http://www.gnu.org/licenses/.
 */

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <smartdm>
#include <dhooks>
#include <multicolors>

#pragma newdecls required // let's go new syntax!
#pragma semicolon 1

#define HIDE_CROSSHAIR_CSGO 1 << 8
#define HIDE_RADAR_CSGO     1 << 12

enum struct Hat {
    char Name[64];
    char szModel[PLATFORM_MAX_PATH];
    char szAttachment[64];
    float fPosition[3];
    float fAngles[3];
    bool bBonemerge;
    bool bHide;
    char flag[8];
}

enum struct Hat2 {
    char Name[64];
    char szAttachment[64];
    float fPosition[3];
    float fAngles[3];
}

bool viendo[MAXPLAYERS + 1];

Hat g_eHats[1024];
int g_Elegido[MAXPLAYERS + 1], g_hats, g_Hat[MAXPLAYERS + 1];
Handle g_mHats[1024];

// new Handle:g_hLookupAttachment = INVALID_HANDLE;

char sConfig[PLATFORM_MAX_PATH];

Handle c_GameSprays, kv, hSetModel, mp_forcecamera;

Menu menu_hats, menu_editor, menu_editor2;

// ConVars
ConVar g_hThirdPerson, g_bAllowMovement, g_bAllowMidair;

Handle timers[MAXPLAYERS + 1];

// ConVar Values
bool g_bThirdPerson;

#define DATA "3.4"

public Plugin myinfo =
{
    name        = "SM Franug Hats",
    author      = "Franc1sco franug",
    description = "Hats",
    version     = DATA,
    url         = "http://steamcommunity.com/id/franug"
};

public void OnPluginStart() {
    mp_forcecamera = FindConVar("mp_forcecamera");
    CreateConVar("sm_franughats_version", DATA, "", FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY);

    c_GameSprays = RegClientCookie("Hats", "Hats", CookieAccess_Private);

    // ConVars
    g_hThirdPerson   = CreateConVar("sm_franughats_thirdperson", "1", "Enable/Disable third-person view.", _, true, 0.0, true, 1.0);
    g_bAllowMovement = CreateConVar("sm_franughats_allowmovement", "0", "Enable/Disable moving while selecting hats.", _, true, 0.0, true, 1.0);
    g_bAllowMidair   = CreateConVar("sm_franughats_allowmidair", "1", "Enable/Disable picking hats while in midair.", _, true, 0.0, true, 1.0);

    RegConsoleCmd("sm_hats", Command_Hats);

    // ConVar Changes.
    HookConVarChange(g_hThirdPerson, CVarChanged);

    HookEvent("player_death", PlayerDeath, EventHookMode_Pre);
    HookEvent("player_team", PlayerDeath, EventHookMode_Pre);

    Handle hGameConf;

    hGameConf = LoadGameConfigFile("sdktools.games");
    if (hGameConf == INVALID_HANDLE)
        SetFailState("Gamedata file sdktools.games.txt is missing.");
    int iOffset = GameConfGetOffset(hGameConf, "SetEntityModel");
    CloseHandle(hGameConf);
    if (iOffset == -1)
        SetFailState("Gamedata is missing the \"SetEntityModel\" offset.");

    hSetModel = DHookCreate(iOffset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity, SetModel);
    DHookAddParam(hSetModel, HookParamType_CharPtr);

    HookEvent("player_spawn", Event_PlayerSpawn);

    RegAdminCmd("sm_editor", DOMenu, ADMFLAG_ROOT, "Opens hats editor.");
    RegAdminCmd("sm_reloadhats", Reload, ADMFLAG_ROOT, "Reload hats configuration.");

    LoadHats();

    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i) && AreClientCookiesCached(i)) {
            OnClientCookiesCached(i);
            OnClientPutInServer(i);
        }

    // Load Translations.
    LoadTranslations("franug_hats.phrases.txt");

    // Auto-load the config.
    AutoExecConfig(true, "plugin.franughats");
}

public void CVarChanged(Handle hConvar, char[] oldV, char[] newV) {
    OnConfigsExecuted();
}

public void OnConfigsExecuted() {
    // Get the values.
    g_bThirdPerson = GetConVarBool(g_hThirdPerson);
}

public void OnClientPutInServer(int client) {
    if (IsFakeClient(client))
        return;

    DHookEntity(hSetModel, true, client);
}

public MRESReturn SetModel(int client, Handle hParams) {
    if (timers[client] != INVALID_HANDLE) {
        return MRES_Ignored;
    } else
        timers[client] = CreateTimer(2.5, ReHats, client);

    return MRES_Ignored;
}

public Action ReHats(Handle timer, int client) {
    if (IsClientInGame(client)) {
        RemoveHat(client);
        CreateHat(client);
    }

    timers[client] = INVALID_HANDLE;
    return Plugin_Handled;
}

public void OnPluginEnd() {
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i))
            OnClientDisconnect(i);
}

public Action Event_PlayerSpawn(Handle event, char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    if (IsFakeClient(client))
        return Plugin_Continue;
    viendo[client] = false;
    timers[client] = CreateTimer(2.5, ReHats, client);
    return Plugin_Continue;
}

public Action Command_Hats(int client, int args) {
    if (!CheckCommandAccess(client, "sm_hats_flag", ADMFLAG_CUSTOM6)) {
        CPrintToChat(client, " {darkred}[f-Hats] %T", "NoAccessCommand", client);
        return Plugin_Handled;
    }
    if (!(GetEntityFlags(client) & FL_ONGROUND) && !g_bAllowMidair.BoolValue) {
        CPrintToChat(client, " {darkred}[f-Hats] %T", "MidAirBlocked", client);
        return Plugin_Handled;
    }
    Showmenuh(client, 0);
    return Plugin_Handled;
}

public Action Reload(int client, int args) {
    LoadHats();
    CPrintToChat(client, " {darkred}[f-Hats] %T", "ConfigReloaded", client);
    return Plugin_Handled;
}

void Showmenuh(int client, int item2) {
    SetMenuTitle(menu_hats, "%T", "HatsMenu", client);
    DisplayMenuAtItem(menu_hats, client, item2, 0);

    viendo[client] = true;
    SetThirdPersonView(client, true);
}

public int DIDMenuHandler(Menu menu, MenuAction action, int client, int itemNum) {
    if (action == MenuAction_Select) {
        char info[4];

        GetMenuItem(menu, itemNum, info, sizeof(info));
        int index = StringToInt(info);
        if (!HasPermission(client, g_eHats[index].flag)) {
            CPrintToChat(client, " {darkred}[f-Hats] %T", "NoAccess", client);
            Showmenuh(client, GetMenuSelectionPosition());
            return 0;
        }
        RemoveHat(client);
        g_Elegido[client] = index;
        CPrintToChat(client, " {darkred}[f-Hats] %T", "Chosen", client, g_eHats[g_Elegido[client]].Name);
        CreateHat(client);
        Showmenuh(client, GetMenuSelectionPosition());
    } else if (action == MenuAction_Cancel) {
        viendo[client] = false;
        SetThirdPersonView(client, false);
    }
    return 0;
}

public void LoadHats() {
    for (int i = 0; i < g_hats; ++i) {
        if (g_mHats[g_hats] != INVALID_HANDLE) {
            CloseHandle(g_mHats[g_hats]);
            g_mHats[g_hats] = INVALID_HANDLE;
        }
    }
    g_hats = 0;
    BuildPath(Path_SM, sConfig, PLATFORM_MAX_PATH, "configs/franug_hats.txt");

    if (kv != INVALID_HANDLE)
        CloseHandle(kv);

    kv = CreateKeyValues("Hats");
    FileToKeyValues(kv, sConfig);

    Hat2 g_array;
    if (KvGotoFirstSubKey(kv)) {
        do {
            float m_fTemp[3];
            KvGetSectionName(kv, g_eHats[g_hats].Name, 64);
            KvGetString(kv, "model", g_eHats[g_hats].szModel, PLATFORM_MAX_PATH);
            KvGetVector(kv, "position", m_fTemp);
            g_eHats[g_hats].fPosition = m_fTemp;
            KvGetVector(kv, "angles", m_fTemp);
            g_eHats[g_hats].fAngles    = m_fTemp;
            g_eHats[g_hats].bBonemerge = (KvGetNum(kv, "bonemerge", 0) ? true : false);
            g_eHats[g_hats].bHide      = (KvGetNum(kv, "hide", 1) ? true : false);
            KvGetString(kv, "attachment", g_eHats[g_hats].szAttachment, 64, "facemask");
            KvGetString(kv, "flag", g_eHats[g_hats].flag, 8, "");

            if (KvJumpToKey(kv, "playermodels")) {
                g_mHats[g_hats] = CreateArray(sizeof(Hat2));

                if (KvGotoFirstSubKey(kv)) {
                    do {
                        KvGetSectionName(kv, g_array.Name, 64);
                        ReplaceString(g_array.Name, 64, "&", "/");
                        KvGetVector(kv, "position", m_fTemp);
                        g_array.fPosition = m_fTemp;
                        KvGetVector(kv, "angles", m_fTemp);
                        g_array.fAngles = m_fTemp;
                        KvGetString(kv, "attachment", g_array.szAttachment, 64, "facemask");

                        PushArrayArray(g_mHats[g_hats], g_array);

                    } while (KvGotoNextKey(kv));
                }
                KvGoBack(kv);
                KvGoBack(kv);
            }
            ++g_hats;
        } while (KvGotoNextKey(kv));
    }
    KvRewind(kv);

    if (menu_hats != INVALID_HANDLE)
        CloseHandle(menu_hats);

    menu_hats = new Menu(DIDMenuHandler);
    SetMenuTitle(menu_hats, "Choose Hat");
    char item[4];
    for (int i = 0; i < g_hats; ++i) {
        Format(item, 4, "%i", i);
        AddMenuItem(menu_hats, item, g_eHats[i].Name);
    }
    SetMenuExitButton(menu_hats, true);

    if (menu_editor != INVALID_HANDLE)
        CloseHandle(menu_editor);

    menu_editor = new Menu(DIDMenuHandler2);
    SetMenuTitle(menu_editor, "Hats Editor");

    AddMenuItem(menu_editor, "Position X+0.5", "Position X + 0.5");
    AddMenuItem(menu_editor, "Position X-0.5", "Position X - 0.5");
    AddMenuItem(menu_editor, "Position Y+0.5", "Position Y + 0.5");
    AddMenuItem(menu_editor, "Position Y-0.5", "Position Y - 0.5");
    AddMenuItem(menu_editor, "Position Z+0.5", "Position Z + 0.5");
    AddMenuItem(menu_editor, "Position Z-0.5", "Position Z - 0.5");
    AddMenuItem(menu_editor, "Angle X+0.5", "Angle X + 0.5");
    AddMenuItem(menu_editor, "Angle X-0.5", "Angle X - 0.5");
    AddMenuItem(menu_editor, "Angle Y+0.5", "Angle Y + 0.5");
    AddMenuItem(menu_editor, "Angle Y-0.5", "Angle Y - 0.5");
    AddMenuItem(menu_editor, "Angle Z+0.5", "Angle Z + 0.5");
    AddMenuItem(menu_editor, "Angle Z-0.5", "Angle Z - 0.5");
    AddMenuItem(menu_editor, "save", "Save");
    SetMenuExitBackButton(menu_editor, true);

    menu_editor2 = new Menu(DIDMenuHandler3);
    SetMenuTitle(menu_editor2, "Hats Editor");

    AddMenuItem(menu_editor2, "Position X+0.5", "Position X + 0.5");
    AddMenuItem(menu_editor2, "Position X-0.5", "Position X - 0.5");
    AddMenuItem(menu_editor2, "Position Y+0.5", "Position Y + 0.5");
    AddMenuItem(menu_editor2, "Position Y-0.5", "Position Y - 0.5");
    AddMenuItem(menu_editor2, "Position Z+0.5", "Position Z + 0.5");
    AddMenuItem(menu_editor2, "Position Z-0.5", "Position Z - 0.5");
    AddMenuItem(menu_editor2, "Angle X+0.5", "Angle X + 0.5");
    AddMenuItem(menu_editor2, "Angle X-0.5", "Angle X - 0.5");
    AddMenuItem(menu_editor2, "Angle Y+0.5", "Angle Y + 0.5");
    AddMenuItem(menu_editor2, "Angle Y-0.5", "Angle Y - 0.5");
    AddMenuItem(menu_editor2, "Angle Z+0.5", "Angle Z + 0.5");
    AddMenuItem(menu_editor2, "Angle Z-0.5", "Angle Z - 0.5");
    AddMenuItem(menu_editor2, "save", "Save");
    SetMenuExitBackButton(menu_editor2, true);
}

public void OnMapStart() {
    for (int i = 0; i < g_hats; ++i) {
        if (!StrEqual(g_eHats[i].szModel, "none") && strcmp(g_eHats[i].szModel, "") != 0) {
            PrecacheModel(g_eHats[i].szModel, true);
            Downloader_AddFileToDownloadsTable(g_eHats[i].szModel);
        }
    }
}

void CreateHat(int client) {
    if (!IsPlayerAlive(client) || GetClientTeam(client) < 2 || IsFakeClient(client))
        return;

    if (StrEqual(g_eHats[g_Elegido[client]].szModel, "none"))
        return;

    if (!HasPermission(client, g_eHats[g_Elegido[client]].flag)) {
        g_Elegido[client] = 0;
        return;
    }

    // CreateHats code taken from https://forums.alliedmods.net/showthread.php?t=208125

    // Calculate the final position and angles for the hat
    float m_fHatOrigin[3], m_fHatAngles[3], m_fForward[3], m_fRight[3], m_fUp[3], m_fOffset[3];

    GetClientAbsOrigin(client, m_fHatOrigin);
    GetClientAbsAngles(client, m_fHatAngles);

    bool found = false;
    Hat2 Items;
    if (g_mHats[g_Elegido[client]] != INVALID_HANDLE) {

        char buscado[64];
        GetClientModel(client, buscado, 64);

        for (int i = 0; i < GetArraySize(g_mHats[g_Elegido[client]]); ++i) {
            GetArrayArray(g_mHats[g_Elegido[client]], i, Items);
            if (StrEqual(Items.Name, buscado)) {
                m_fHatAngles[0] += Items.fAngles[0];
                m_fHatAngles[1] += Items.fAngles[1];
                m_fHatAngles[2] += Items.fAngles[2];

                m_fOffset[0] = Items.fPosition[0];
                m_fOffset[1] = Items.fPosition[1];
                m_fOffset[2] = Items.fPosition[2];
                found        = true;

                break;
            }
        }
    }

    if (!found) {
        m_fHatAngles[0] += g_eHats[g_Elegido[client]].fAngles[0];
        m_fHatAngles[1] += g_eHats[g_Elegido[client]].fAngles[1];
        m_fHatAngles[2] += g_eHats[g_Elegido[client]].fAngles[2];

        m_fOffset[0] = g_eHats[g_Elegido[client]].fPosition[0];
        m_fOffset[1] = g_eHats[g_Elegido[client]].fPosition[1];
        m_fOffset[2] = g_eHats[g_Elegido[client]].fPosition[2];
    }

    GetAngleVectors(m_fHatAngles, m_fForward, m_fRight, m_fUp);

    m_fHatOrigin[0] += m_fRight[0] * m_fOffset[0] + m_fForward[0] * m_fOffset[1] + m_fUp[0] * m_fOffset[2];
    m_fHatOrigin[1] += m_fRight[1] * m_fOffset[0] + m_fForward[1] * m_fOffset[1] + m_fUp[1] * m_fOffset[2];
    m_fHatOrigin[2] += m_fRight[2] * m_fOffset[0] + m_fForward[2] * m_fOffset[1] + m_fUp[2] * m_fOffset[2];

    // Create the hat entity
    int m_iEnt = CreateEntityByName("prop_dynamic_override");
    DispatchKeyValue(m_iEnt, "model", g_eHats[g_Elegido[client]].szModel);
    DispatchKeyValue(m_iEnt, "spawnflags", "256");
    DispatchKeyValue(m_iEnt, "solid", "0");
    SetEntPropEnt(m_iEnt, Prop_Send, "m_hOwnerEntity", client);

    if (g_eHats[g_Elegido[client]].bBonemerge)
        Bonemerge(m_iEnt);

    DispatchSpawn(m_iEnt);
    AcceptEntityInput(m_iEnt, "TurnOn", m_iEnt, m_iEnt, 0);

    // Save the entity index
    g_Hat[client] = EntIndexToEntRef(m_iEnt);

    // We don't want the client to see his own hat
    if (g_eHats[g_Elegido[client]].bHide)
        SDKHook(m_iEnt, SDKHook_SetTransmit, ShouldHide);

    // Teleport the hat to the right position and attach it
    TeleportEntity(m_iEnt, m_fHatOrigin, m_fHatAngles, NULL_VECTOR);

    SetVariantString("!activator");
    AcceptEntityInput(m_iEnt, "SetParent", client, m_iEnt, 0);

    if (!found)
        SetVariantString(g_eHats[g_Elegido[client]].szAttachment);
    else
        SetVariantString(Items.szAttachment);
    AcceptEntityInput(m_iEnt, "SetParentAttachmentMaintainOffset", m_iEnt, m_iEnt, 0);
}

public void Bonemerge(int ent) {
    int m_iEntEffects = GetEntProp(ent, Prop_Send, "m_fEffects");
    m_iEntEffects &= ~32;
    m_iEntEffects |= 1;
    m_iEntEffects |= 128;
    SetEntProp(ent, Prop_Send, "m_fEffects", m_iEntEffects);
}

public Action PlayerDeath(Handle event, char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    if (IsFakeClient(client))
        return Plugin_Continue;
    if (timers[client] != INVALID_HANDLE) {
        KillTimer(timers[client]);
        timers[client] = INVALID_HANDLE;
    }
    if (viendo[client]) {
        viendo[client] = false;
        SetThirdPersonView(client, false);
    }
    RemoveHat(client);
    return Plugin_Continue;
}

public void OnClientCookiesCached(int client) {
    char SprayString[12];
    GetClientCookie(client, c_GameSprays, SprayString, sizeof(SprayString));
    g_Elegido[client] = StringToInt(SprayString);
    if (g_hats <= g_Elegido[client])
        g_Elegido[client] = 0;

    g_Hat[client] = INVALID_ENT_REFERENCE;
}

public void OnClientDisconnect(int client) {
    if (IsFakeClient(client))
        return;
    if (AreClientCookiesCached(client)) {
        char SprayString[12];
        Format(SprayString, sizeof(SprayString), "%i", g_Elegido[client]);
        SetClientCookie(client, c_GameSprays, SprayString);
    }
    if (timers[client] != INVALID_HANDLE) {
        KillTimer(timers[client]);
        timers[client] = INVALID_HANDLE;
    }
    RemoveHat(client);
}

public Action ShouldHide(int ent, int client) {
    int owner = GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity");
    if (owner == client) {
        if (viendo[client])
            return Plugin_Continue;

        return Plugin_Handled;
    }

    if (GetEntProp(client, Prop_Send, "m_iObserverMode") == 4) {
        if (owner == GetEntPropEnt(client, Prop_Send, "m_hObserverTarget")) {
            return Plugin_Handled;
        }
    }

    if (IsClientSourceTV(client))
        return Plugin_Handled; // hide hats in demos

    return Plugin_Continue;
}

public void RemoveHat(int client) {
    int entity = EntRefToEntIndex(g_Hat[client]);
    if (entity != INVALID_ENT_REFERENCE && IsValidEdict(entity) && entity != 0) {
        if (g_eHats[g_Elegido[client]].bHide)
            SDKUnhook(entity, SDKHook_SetTransmit, ShouldHide);
        AcceptEntityInput(entity, "Kill");
        g_Hat[client] = INVALID_ENT_REFERENCE;
    }
}

stock void SetThirdPersonView(int client, bool third) {
    if (!g_bThirdPerson || !IsPlayerAlive(client))
        return;

    if (third) {
        SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", 0);
        SetEntProp(client, Prop_Send, "m_iObserverMode", 1);
        SetEntProp(client, Prop_Send, "m_bDrawViewmodel", 0);
        SetEntProp(client, Prop_Send, "m_iFOV", 120);
        SendConVarValue(client, mp_forcecamera, "1");
        if (!g_bAllowMovement.BoolValue)
            SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 0.0);

        SetEntProp(client, Prop_Send, "m_iHideHUD", GetEntProp(client, Prop_Send, "m_iHideHUD") | HIDE_RADAR_CSGO);
        SetEntProp(client, Prop_Send, "m_iHideHUD", GetEntProp(client, Prop_Send, "m_iHideHUD") | HIDE_CROSSHAIR_CSGO);
        return;
    }
    SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", -1);
    SetEntProp(client, Prop_Send, "m_iObserverMode", 0);
    SetEntProp(client, Prop_Send, "m_bDrawViewmodel", 1);
    SetEntProp(client, Prop_Send, "m_iFOV", 90);
    char valor[6];
    GetConVarString(mp_forcecamera, valor, 6);
    SendConVarValue(client, mp_forcecamera, valor);
    if (!g_bAllowMovement.BoolValue)
        SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0);

    SetEntProp(client, Prop_Send, "m_iHideHUD", GetEntProp(client, Prop_Send, "m_iHideHUD") & ~HIDE_RADAR_CSGO);
    SetEntProp(client, Prop_Send, "m_iHideHUD", GetEntProp(client, Prop_Send, "m_iHideHUD") & ~HIDE_CROSSHAIR_CSGO);
}

public Action DOMenu(int client, int args) {
    if (StrEqual(g_eHats[g_Elegido[client]].szModel, "none")) {
        CPrintToChat(client, " {darkred}[f-Hats] %T", "FirstChoose", client);
        return Plugin_Handled;
    }

    Menu menu_editor_init = new Menu(DIDMenuHandler_init);
    char itemmenu[64];
    SetMenuTitle(menu_editor_init, "%T", "EditorMenu", client);

    Format(itemmenu, 64, "%T", "Edit default hat position", client);
    AddMenuItem(menu_editor_init, "default", itemmenu);
    Format(itemmenu, 64, "%T", "Edit hat positions for this model", client);
    AddMenuItem(menu_editor_init, "model", itemmenu);

    SetMenuExitButton(menu_editor_init, true);
    DisplayMenu(menu_editor_init, client, 0);

    return Plugin_Handled;
}

public int DIDMenuHandler_init(Menu menu, MenuAction action, int client, int itemNum) {
    if (action == MenuAction_Select) {
        char info[32];

        GetMenuItem(menu, itemNum, info, sizeof(info));

        if (strcmp(info, "default") == 0)
            ShowMenu(client, 0);
        else if (strcmp(info, "model") == 0)
            ShowMenu2(client, 0);

    } else if (action == MenuAction_End) {
        delete menu;
    }
    return 0;
}

void ShowMenu(int client, int item) {
    SetMenuTitle(menu_editor, "%T", "EditorMenu", client);
    DisplayMenuAtItem(menu_editor, client, item, 0);

    viendo[client] = true;
    SetThirdPersonView(client, true);
}

void ShowMenu2(int client, int item) {
    SetMenuTitle(menu_editor2, "%T", "EditorMenu", client);
    DisplayMenuAtItem(menu_editor2, client, item, 0);

    viendo[client] = true;
    SetThirdPersonView(client, true);
}

public int DIDMenuHandler2(Menu menu, MenuAction action, int client, int itemNum) {
    if (action == MenuAction_Select) {
        char info[32];

        GetMenuItem(menu, itemNum, info, sizeof(info));
        int numero;
        float posicion;
        if (StrContains(info, "Position", false) != -1) {
            ReplaceString(info, 32, "Position", "", false);
            if (StrContains(info, "X", false) != -1) {
                numero = 0;
                ReplaceString(info, 32, "X", "", false);
            } else if (StrContains(info, "Y", false) != -1) {
                numero = 1;
                ReplaceString(info, 32, "Y", "", false);
            } else if (StrContains(info, "Z", false) != -1) {
                numero = 2;
                ReplaceString(info, 32, "Z", "", false);
            }

            posicion = StringToFloat(info);

            g_eHats[g_Elegido[client]].fPosition[numero] += posicion;
            RemoveHat(client);
            CreateHat(client);

        } else if (StrContains(info, "Angle", false) != -1) {
            ReplaceString(info, 32, "Angle", "", false);
            if (StrContains(info, "X", false) != -1) {
                numero = 0;
                ReplaceString(info, 32, "X", "", false);
            } else if (StrContains(info, "Y", false) != -1) {
                numero = 1;
                ReplaceString(info, 32, "Y", "", false);
            } else if (StrContains(info, "Z", false) != -1) {
                numero = 2;
                ReplaceString(info, 32, "Z", "", false);
            }

            posicion = StringToFloat(info);

            g_eHats[g_Elegido[client]].fAngles[numero] += posicion;
            RemoveHat(client);
            CreateHat(client);

        } else if (StrContains(info, "Save", false) != -1) {

            KvJumpToKey(kv, g_eHats[g_Elegido[client]].Name);
            float m_fTemp[3];
            m_fTemp[0] = g_eHats[g_Elegido[client]].fPosition[0];
            m_fTemp[1] = g_eHats[g_Elegido[client]].fPosition[1];
            m_fTemp[2] = g_eHats[g_Elegido[client]].fPosition[2];
            KvSetVector(kv, "position", m_fTemp);
            m_fTemp[0] = g_eHats[g_Elegido[client]].fAngles[0];
            m_fTemp[1] = g_eHats[g_Elegido[client]].fAngles[1];
            m_fTemp[2] = g_eHats[g_Elegido[client]].fAngles[2];
            KvSetVector(kv, "angles", m_fTemp);
            KvRewind(kv);
            KeyValuesToFile(kv, sConfig);

            CPrintToChat(client, " {darkred}[f-Hats] %T", "ConfigSaved", client);
        }
        ShowMenu(client, GetMenuSelectionPosition());
    } else if (action == MenuAction_Cancel) {
        if (IsClientInGame(client) && viendo[client]) {
            viendo[client] = false;
            SetThirdPersonView(client, false);
        }
        if (itemNum == MenuCancel_ExitBack) {
            DOMenu(client, 0);
        }
    }
    return 0;
}

public int DIDMenuHandler3(Menu menu, MenuAction action, int client, int itemNum) {
    if (action == MenuAction_Select) {
        char info[32];

        GetMenuItem(menu, itemNum, info, sizeof(info));
        int numero;
        float posicion;
        if (StrContains(info, "Position", false) != -1) {
            ReplaceString(info, 32, "Position", "", false);
            if (StrContains(info, "X", false) != -1) {
                numero = 0;
                ReplaceString(info, 32, "X", "", false);
            } else if (StrContains(info, "Y", false) != -1) {
                numero = 1;
                ReplaceString(info, 32, "Y", "", false);
            } else if (StrContains(info, "Z", false) != -1) {
                numero = 2;
                ReplaceString(info, 32, "Z", "", false);
            }

            posicion = StringToFloat(info);

            Hat2 Items;
            char buscado[64];

            GetClientModel(client, buscado, 64);
            bool found = false;
            int index;
            if (g_mHats[g_Elegido[client]] == INVALID_HANDLE) {
                g_mHats[g_Elegido[client]] = CreateArray(134);
                Items.fPosition            = g_eHats[g_Elegido[client]].fPosition;
                Items.fAngles              = g_eHats[g_Elegido[client]].fAngles;
                Format(Items.szAttachment, 64, "facemask");
                Format(Items.Name, 64, buscado);

                index = PushArrayArray(g_mHats[g_Elegido[client]], Items);
                found = true;
            }

            if (!found) {
                for (int i = 0; i < GetArraySize(g_mHats[g_Elegido[client]]); ++i) {
                    GetArrayArray(g_mHats[g_Elegido[client]], i, Items);
                    if (StrEqual(Items.Name, buscado)) {
                        found = true;
                        index = i;
                        break;
                    }
                }
            }

            if (!found) {
                Items.fPosition = g_eHats[g_Elegido[client]].fPosition;
                Items.fAngles   = g_eHats[g_Elegido[client]].fAngles;
                Items.fPosition[numero] += posicion;
                Format(Items.szAttachment, 64, "facemask");
                Format(Items.Name, 64, buscado);

                PushArrayArray(g_mHats[g_Elegido[client]], Items);
            } else {
                Items.fPosition[numero] += posicion;
                SetArrayArray(g_mHats[g_Elegido[client]], index, Items);
            }
            RemoveHat(client);
            CreateHat(client);

        } else if (StrContains(info, "Angle", false) != -1) {
            ReplaceString(info, 32, "Angle", "", false);
            if (StrContains(info, "X", false) != -1) {
                numero = 0;
                ReplaceString(info, 32, "X", "", false);
            } else if (StrContains(info, "Y", false) != -1) {
                numero = 1;
                ReplaceString(info, 32, "Y", "", false);
            } else if (StrContains(info, "Z", false) != -1) {
                numero = 2;
                ReplaceString(info, 32, "Z", "", false);
            }

            posicion = StringToFloat(info);

            Hat2 Items;
            char buscado[64];

            GetClientModel(client, buscado, 64);
            bool found = false;
            int index;
            if (g_mHats[g_Elegido[client]] == INVALID_HANDLE) {
                g_mHats[g_Elegido[client]] = CreateArray(134);

                Items.fPosition = g_eHats[g_Elegido[client]].fPosition;
                Items.fAngles   = g_eHats[g_Elegido[client]].fAngles;
                Format(Items.szAttachment, 64, "facemask");
                Format(Items.Name, 64, buscado);

                index = PushArrayArray(g_mHats[g_Elegido[client]], Items);
                found = true;
            }

            if (!found) {
                for (int i = 0; i < GetArraySize(g_mHats[g_Elegido[client]]); ++i) {
                    GetArrayArray(g_mHats[g_Elegido[client]], i, Items);
                    if (StrEqual(Items.Name, buscado)) {
                        found = true;
                        index = i;
                        break;
                    }
                }
            }

            if (!found) {
                Items.fPosition = g_eHats[g_Elegido[client]].fPosition;
                Items.fAngles   = g_eHats[g_Elegido[client]].fAngles;
                Items.fAngles[numero] += posicion;
                Format(Items.szAttachment, 64, "facemask");
                Format(Items.Name, 64, buscado);

                PushArrayArray(g_mHats[g_Elegido[client]], Items);
            } else {
                Items.fAngles[numero] += posicion;
                SetArrayArray(g_mHats[g_Elegido[client]], index, Items);
            }
            RemoveHat(client);
            CreateHat(client);

        } else if (StrContains(info, "Save", false) != -1) {
            Hat2 Items;
            char buscado[64], temp[64];
            float m_fTemp[3];
            GetClientModel(client, buscado, 64);
            bool found = false;
            if (g_mHats[g_Elegido[client]] == INVALID_HANDLE) {
                g_mHats[g_Elegido[client]] = CreateArray(134);
                KvJumpToKey(kv, g_eHats[g_Elegido[client]].Name);
                KvJumpToKey(kv, "playermodels", true);
                // KvGotoFirstSubKey(kv);

                Format(temp, 64, buscado);
                ReplaceString(temp, 64, "/", "&");
                KvJumpToKey(kv, temp, true);
                // ReplaceString(temp, 64, "&","/");
                // KvSetSectionName(kv, temp);

                m_fTemp[0] = g_eHats[g_Elegido[client]].fPosition[0];
                m_fTemp[1] = g_eHats[g_Elegido[client]].fPosition[1];
                m_fTemp[2] = g_eHats[g_Elegido[client]].fPosition[2];
                KvSetVector(kv, "position", m_fTemp);
                m_fTemp[0] = g_eHats[g_Elegido[client]].fAngles[0];
                m_fTemp[1] = g_eHats[g_Elegido[client]].fAngles[1];
                m_fTemp[2] = g_eHats[g_Elegido[client]].fAngles[2];
                KvSetVector(kv, "angles", m_fTemp);
                Items.fPosition = g_eHats[g_Elegido[client]].fPosition;
                Items.fAngles   = g_eHats[g_Elegido[client]].fAngles;
                Format(Items.szAttachment, 64, "facemask");
                Format(Items.Name, 64, buscado);

                PushArrayArray(g_mHats[g_Elegido[client]], Items);
                found = true;
                KvRewind(kv);
                KeyValuesToFile(kv, sConfig);

                CPrintToChat(client, " {darkred}[f-Hats] %T", "ConfigSaved", client);

                ShowMenu2(client, GetMenuSelectionPosition());
                return 0;
            }

            if (!found) {
                for (int i = 0; i < GetArraySize(g_mHats[g_Elegido[client]]); ++i) {
                    GetArrayArray(g_mHats[g_Elegido[client]], i, Items);
                    if (StrEqual(Items.Name, buscado)) {
                        found = true;
                        break;
                    }
                }
            }

            if (!found) {
                KvJumpToKey(kv, g_eHats[g_Elegido[client]].Name);
                KvJumpToKey(kv, "playermodels", true);
                // KvGotoFirstSubKey(kv);

                Format(temp, 64, buscado);
                ReplaceString(temp, 64, "/", "&");
                KvJumpToKey(kv, temp, true);
                // ReplaceString(temp, 64, "&","/");
                // KvSetSectionName(kv, temp);

                m_fTemp[0] = g_eHats[g_Elegido[client]].fPosition[0];
                m_fTemp[1] = g_eHats[g_Elegido[client]].fPosition[1];
                m_fTemp[2] = g_eHats[g_Elegido[client]].fPosition[2];
                KvSetVector(kv, "position", m_fTemp);
                m_fTemp[0] = g_eHats[g_Elegido[client]].fAngles[0];
                m_fTemp[1] = g_eHats[g_Elegido[client]].fAngles[1];
                m_fTemp[2] = g_eHats[g_Elegido[client]].fAngles[2];
                KvSetVector(kv, "angles", m_fTemp);
                Items.fPosition = g_eHats[g_Elegido[client]].fPosition;
                Items.fAngles   = g_eHats[g_Elegido[client]].fAngles;
                Format(Items.szAttachment, 64, "facemask");
                Format(Items.Name, 64, buscado);

                PushArrayArray(g_mHats[g_Elegido[client]], Items);
                KvRewind(kv);
                KeyValuesToFile(kv, sConfig);
            } else {
                KvJumpToKey(kv, g_eHats[g_Elegido[client]].Name);
                KvJumpToKey(kv, "playermodels", true);
                // KvGotoFirstSubKey(kv);
                ReplaceString(buscado, 64, "/", "&");
                if (!KvJumpToKey(kv, buscado)) {
                    KvJumpToKey(kv, buscado, true);
                    // ReplaceString(temp, 64, "&","/");
                    // KvSetSectionName(kv, temp);

                    // PrintToChatAll("no existe");
                }

                m_fTemp[0] = Items.fPosition[0];
                m_fTemp[1] = Items.fPosition[1];
                m_fTemp[2] = Items.fPosition[2];
                KvSetVector(kv, "position", m_fTemp);
                m_fTemp[0] = Items.fAngles[0];
                m_fTemp[1] = Items.fAngles[1];
                m_fTemp[2] = Items.fAngles[2];
                KvSetVector(kv, "angles", m_fTemp);
                KvRewind(kv);
                KeyValuesToFile(kv, sConfig);
            }

            CPrintToChat(client, " {darkred}[f-Hats] %T", "ConfigSaved", client);
        }
        ShowMenu2(client, GetMenuSelectionPosition());
    } else if (action == MenuAction_Cancel) {
        if (IsClientInGame(client) && viendo[client]) {
            viendo[client] = false;
            SetThirdPersonView(client, false);
        }
        if (itemNum == MenuCancel_ExitBack) {
            DOMenu(client, 0);
        }
    }
    return 0;
}

// Just a quick function.
stock bool HasPermission(int iClient, char[] flagString) {
    if (StrEqual(flagString, ""))
        return true;

    AdminId admin = GetUserAdmin(iClient);
    if (admin == INVALID_ADMIN_ID)
        return false;
    int count, found, flags = ReadFlagString(flagString);
    for (int i = 0; i <= 20; i++) {
        if (flags & (1 << i)) {
            count++;
            if (GetAdminFlag(admin, view_as<AdminFlag>(i)))
                found++;
        }
    }
    return count == found;
}

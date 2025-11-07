#pragma semicolon 1
#pragma newdecls required

#include <tf2_stocks>
#include <tf2attributes>
#include <virtual_address>

#define LogPrefix "[TF2Attributes Test] "
#define LogPrefixFail LogPrefix ... "***FAILED*** "
#define LogPrefixWarn LogPrefix ... "**WARNING** "
#define LogPrefixInfo LogPrefix ... "--- "


#define ATTR_CUSTOM_NAME_ATTR 500 // ""custom_name_attr"
#define ATTR_HEALTH_REGEN 57 // "health regen"

#define ATTR_MAJOR_MOVE_SPEED_BONUS 442 // "major move speed bonus"
#define MAJOR_MOVE_SPEED_BONUS_VALUE 3.0

#define ATTR_DAMAGE_CAUSES_AIRBLAST 522
#define ATTR_DAMAGE_CAUSES_AIRBLAST_VALUE 1

// items_game.txt: "stored_as_integer"	"1"
static const char g_sTestAttribNameInt[] = "damage causes airblast";
static const char g_sTestAttribClassInt[] = "damage_causes_airblast";
const int g_iTestAttribDefIndexInt = ATTR_DAMAGE_CAUSES_AIRBLAST;
const int g_iTestAttribValue = ATTR_DAMAGE_CAUSES_AIRBLAST_VALUE;

// items_game.txt: "stored_as_integer"	"0"
static const char g_sTestAttribNameFloat[] = "major move speed bonus";
static const char g_sTestAttribClassFloat[] = "mult_player_movespeed"; // Needs to be multiplicative for test to pass
const int g_iTestAttribDefIndexFloat = ATTR_MAJOR_MOVE_SPEED_BONUS;
const float g_fTestAttribValue = MAJOR_MOVE_SPEED_BONUS_VALUE;
char g_sTestAttribValue[18];

static const char g_sTestAttribNameString[] = "start drop date"; // items_game.txt: "attribute_type"	"string"

public void OnPluginStart()
{
	FloatToString(g_fTestAttribValue, g_sTestAttribValue, sizeof(g_sTestAttribValue));

	RegAdminCmd("sm_test_tf2attributes", Command_TestTF2Attributes, ADMFLAG_ROOT, "Full automated test. Equip name tagged primary weapon if possible.");
}

Action Command_TestTF2Attributes(int client, int args)
{
	// Untested scenarios: reading static or SOC attribute string values

	if (!client || !IsPlayerAlive(client))
	{
		ReplyToCommand(client, "You must be alive to run this command.");
		return Plugin_Handled;
	}

	int iWeapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);

	if (iWeapon == -1)
	{
		ReplyToCommand(client, "You must have a primary weapon to run this command.");
		return Plugin_Handled;
	}

	Test_TF2Attrib_IsValidAttributeName(); // TF2Attrib_IsValidAttributeName
	Test_TF2Attrib_IsIntegerValue(); // TF2Attrib_IsIntegerValue
	Test_TF2Attrib_SetByName(iWeapon); // TF2Attrib_SetByName, TF2Attrib_GetByName, TF2Attrib_GetValue, TF2Attrib_RemoveByName
	Test_TF2Attrib_SetByDefIndex(iWeapon); // TF2Attrib_SetByDefIndex, TF2Attrib_GetByDefIndex, TF2Attrib_ListDefIndices, TF2Attrib_RemoveByDefIndex
	Test_TF2Attrib_GetStaticAttribs(iWeapon); // TF2Attrib_GetStaticAttribs
	Test_TF2Attrib_GetSOCAttribs(iWeapon); // TF2Attrib_GetSOCAttribs
	Test_TF2Attrib_AddCustomPlayerAttribute(client); // TF2Attrib_AddCustomPlayerAttribute, TF2Attrib_RemoveCustomPlayerAttribute
	Test_TF2Attrib_HookValueFloat(iWeapon); // TF2Attrib_HookValueFloat
	Test_TF2Attrib_HookValueInt(iWeapon); // TF2Attrib_HookValueInt
	Test_TF2Attrib_HookValueString(iWeapon); // TF2Attrib_HookValueString
	Test_TF2Attrib_SetFromStringValue(iWeapon); // TF2Attrib_SetFromStringValue, TF2Attrib_UnsafeGetStringValue
	Test_TF2Attrib_SetRefundableCurrency(iWeapon); // TF2Attrib_SetRefundableCurrency, TF2Attrib_GetRefundableCurrency
	Test_TF2Attrib_SetGet_ClearCache(iWeapon); // TF2Attrib_SetDefIndex, TF2Attrib_GetDefIndex, TF2Attrib_SetValue, TF2Attrib_ClearCache
	Test_TF2Attrib_RemoveAll(iWeapon); // TF2Attrib_RemoveAll

	LogToGame(LogPrefix ... "All tests completed.");
	ReplyToCommand(client, "All tests completed. Check server console/logs for details.");

	return Plugin_Handled;
}

void Test_TF2Attrib_IsValidAttributeName()
{
	char sTest[] = "TF2Attrib_IsValidAttributeName";
	LogTestStart(sTest);

	if (!TF2Attrib_IsValidAttributeName(g_sTestAttribNameFloat))
	{
		LogError(LogPrefixFail ... "TF2Attrib_IsValidAttributeName returned false for valid attribute name '%s'", g_sTestAttribNameFloat);
		return;
	}

	LogTestPassed(sTest);
}

void Test_TF2Attrib_IsIntegerValue()
{
	char sTest[] = "TF2Attrib_IsIntegerValue";
	LogTestStart(sTest);

	bool bIsIntTestFloat = TF2Attrib_IsIntegerValue(g_iTestAttribDefIndexFloat);
	bool bIsIntTestInt = TF2Attrib_IsIntegerValue(g_iTestAttribDefIndexInt);

	if (bIsIntTestFloat || !bIsIntTestInt)
	{
		LogError(LogPrefixFail ... "TF2Attrib_IsIntegerValue returned incorrect values: major move speed bonus = %d(expected 0), energy weapon penetration = %d(expected 1)", bIsIntTestFloat, bIsIntTestInt);
		return;
	}

	LogTestPassed(sTest);
}

void Test_TF2Attrib_SetByName(int entity)
{
	char sTest[] = "TF2Attrib_SetByName, TF2Attrib_GetByName, TF2Attrib_GetValue, TF2Attrib_RemoveByName";
	LogTestStart(sTest);

	LogToGame(LogPrefixInfo ... "TF2Attrib_SetByName '%s' to value %f", g_sTestAttribNameFloat, g_fTestAttribValue);
	if (!TF2Attrib_SetByName(entity, g_sTestAttribNameFloat, g_fTestAttribValue))
	{
		LogError(LogPrefixFail ... "TF2Attrib_SetByName");
		return;
	}

	LogToGame(LogPrefixInfo ... "TF2Attrib_GetByName '%s'", g_sTestAttribNameFloat);
	Address pCEconItemAttribute = TF2Attrib_GetByName(entity, g_sTestAttribNameFloat);

	if (!pCEconItemAttribute)
	{
		LogError(LogPrefixFail ... "TF2Attrib_GetByName returned Address_Null");
		return;
	}

	LogToGame(LogPrefixInfo ... "TF2Attrib_GetValue virtual address %u", pCEconItemAttribute);
	float fValue = TF2Attrib_GetValue(pCEconItemAttribute);

	if (fValue != g_fTestAttribValue)
	{
		LogError(LogPrefixFail ... "TF2Attrib_GetValue returned %f, expected %f", fValue, g_fTestAttribValue);
		return;
	}

	LogToGame(LogPrefixInfo ... "TF2Attrib_RemoveByName '%s'", g_sTestAttribNameFloat);
	if (!TF2Attrib_RemoveByName(entity, g_sTestAttribNameFloat))
	{
		LogError(LogPrefixFail ... "TF2Attrib_RemoveByName returned false");
		return;
	}

	pCEconItemAttribute = TF2Attrib_GetByName(entity, g_sTestAttribNameFloat);

	if (pCEconItemAttribute)
	{
		LogError(LogPrefixFail ... "TF2Attrib_RemoveByName failed, attribute still present");
		return;
	}

	LogTestPassed(sTest);
}

void Test_TF2Attrib_SetByDefIndex(int entity)
{
	char sTest[] = "TF2Attrib_SetByDefIndex, TF2Attrib_GetByDefIndex, TF2Attrib_ListDefIndices, TF2Attrib_RemoveByDefIndex";
	LogTestStart(sTest);

	LogToGame(LogPrefixInfo ... "TF2Attrib_SetByDefIndex %d to value %f", g_iTestAttribDefIndexFloat, g_fTestAttribValue);
	if (!TF2Attrib_SetByDefIndex(entity, g_iTestAttribDefIndexFloat, g_fTestAttribValue))
	{
		LogError(LogPrefixFail ... "TF2Attrib_SetByDefIndex");
		return;
	}

	LogToGame(LogPrefixInfo ... "TF2Attrib_GetByDefIndex %d", g_iTestAttribDefIndexFloat);
	Address pCEconItemAttribute = TF2Attrib_GetByDefIndex(entity, g_iTestAttribDefIndexFloat);

	if (!pCEconItemAttribute)
	{
		LogError(LogPrefixFail ... "TF2Attrib_GetByDefIndex returned Address_Null");
		return;
	}

	LogToGame(LogPrefixInfo ... "TF2Attrib_GetValue virtual address %u", pCEconItemAttribute);
	float fValue = TF2Attrib_GetValue(pCEconItemAttribute);

	if (fValue != g_fTestAttribValue)
	{
		LogError(LogPrefixFail ... "TF2Attrib_GetValue returned %f, expected %f", fValue, g_fTestAttribValue);
		return;
	}

	LogToGame(LogPrefixInfo ... "TF2Attrib_ListDefIndices entity %d", entity);
	int iAttribIndices[20];
	int iNumAttr = TF2Attrib_ListDefIndices(entity, iAttribIndices);

	if (iNumAttr <= 0)
	{
		if (iNumAttr == -1)
			LogError(LogPrefixFail ... "TF2Attrib_ListDefIndices failed with return -1");
		else
			LogError(LogPrefixFail ... "TF2Attrib_ListDefIndices returned 0 attributes, should have at least the current test attribute");
	}
	else
	{
		LogToGame(LogPrefixInfo ... "TF2Attrib_ListDefIndices iNumAttr: %d", iNumAttr);
		bool bHasTestAttrib;

		for (int i = 0; i < iNumAttr; i++)
		{
			LogToGame(LogPrefixInfo ... "TF2Attrib_ListDefIndices Attrib %d: %d", i, iAttribIndices[i]);

			if (iAttribIndices[i] == g_iTestAttribDefIndexFloat)
				bHasTestAttrib = true;
		}

		if (!bHasTestAttrib)
			LogError(LogPrefixFail ... "TF2Attrib_ListDefIndices did not find the current test attribute");
	}

	LogToGame(LogPrefixInfo ... "TF2Attrib_RemoveByDefIndex %d", g_iTestAttribDefIndexFloat);
	if (!TF2Attrib_RemoveByDefIndex(entity, g_iTestAttribDefIndexFloat))
	{
		LogError(LogPrefixFail ... "TF2Attrib_RemoveByDefIndex failed, further tests will be tainted");
		return;
	}

	LogToGame(LogPrefixInfo ... "TF2Attrib_GetByDefIndex %d", g_iTestAttribDefIndexFloat);
	pCEconItemAttribute = TF2Attrib_GetByDefIndex(entity, g_iTestAttribDefIndexFloat);

	if (pCEconItemAttribute)
	{
		LogError(LogPrefixFail ... "TF2Attrib_RemoveByDefIndex failed, attribute still present");
		return;
	}

	LogTestPassed(sTest);
}

void Test_TF2Attrib_GetStaticAttribs(int iWeapon)
{
	char sTest[] = "TF2Attrib_GetStaticAttribs";
	LogTestStart(sTest);

	int iItemDef = GetEntProp(iWeapon, Prop_Send, "m_iItemDefinitionIndex");

	int iAttribIndices[16];
	float fAttribValues[16];

	LogToGame(LogPrefixInfo ... "TF2Attrib_GetStaticAttribs on iItemDef %d", iItemDef);
	int iNumAttr = TF2Attrib_GetStaticAttribs(iItemDef, iAttribIndices, fAttribValues);

	if (iNumAttr <= 0)
	{
		if (iNumAttr == -1)
			LogError(LogPrefixFail ... "TF2Attrib_GetStaticAttribs returned -1: no schema or item definition found");
		else
			LogError(LogPrefixFail ... "TF2Attrib_GetStaticAttribs returned 0 attributes", iNumAttr);

		return;
	}

	LogToGame(LogPrefixInfo ... "TF2Attrib_GetStaticAttribs iNumAttr: %d", iNumAttr);

	for (int i = 0; i < iNumAttr; i++)
	{
		LogToGame(LogPrefixInfo ... "TF2Attrib_GetStaticAttribs Attrib %d: %d = %f", i, iAttribIndices[i], fAttribValues[i]);
	}

	LogTestPassed(sTest);
}

void Test_TF2Attrib_GetSOCAttribs(int iWeapon)
{
	char sTest[] = "TF2Attrib_GetSOCAttribs";
	LogTestStart(sTest);

	int iAttribIndices[16];
	float fAttribValues[16];

	int iNumAttr = TF2Attrib_GetSOCAttribs(iWeapon, iAttribIndices, fAttribValues);

	if (iNumAttr <= 0)
	{
		if (iNumAttr == -1)
			LogError(LogPrefixFail ... "TF2Attrib_GetSOCAttribs returned error, attributes = -1");
		else
			LogError(LogPrefixFail ... "TF2Attrib_GetSOCAttribs returned 0 attributes. This test expects the tested weapon to have come from item server. " ...
				"Treat as hard failure if it was. TF2Attrib_HookValueString will have a warning.");
		return;
	}

	LogToGame(LogPrefixInfo ... "TF2Attrib_GetSOCAttribs iNumAttr: %d", iNumAttr);

	bool bHasCustomNameAttr;

	for (int i = 0; i < iNumAttr; i++)
	{
		LogToGame(LogPrefix ... "TF2Attrib_GetSOCAttribs Attrib %d: %d = %f", i, iAttribIndices[i], fAttribValues[i]);

		if (iAttribIndices[i] == ATTR_CUSTOM_NAME_ATTR)
			bHasCustomNameAttr = true;
	}

	if (!bHasCustomNameAttr)
		LogToGame(LogPrefix ... "**Warning**: Tested item does not have 'custom_name_attr' attribute (name tag). " ...
			"TF2Attrib_HookValueString will have a warning.");

	LogTestPassed(sTest);
}

void Test_TF2Attrib_AddCustomPlayerAttribute(int client)
{
	char sTest[] = "TF2Attrib_AddCustomPlayerAttribute, TF2Attrib_RemoveCustomPlayerAttribute (Duration not automatically tested)";
	LogTestStart(sTest);

	LogToGame(LogPrefixInfo ... "TF2Attrib_AddCustomPlayerAttribute '%s' to value %f", g_sTestAttribNameFloat, g_fTestAttribValue);
	TF2Attrib_AddCustomPlayerAttribute(client, g_sTestAttribNameFloat, g_fTestAttribValue, 4.0);

	Address pCEconItemAttribute = TF2Attrib_GetByName(client, g_sTestAttribNameFloat);

	if (!pCEconItemAttribute)
	{
		LogError(LogPrefixFail ... "TF2Attrib_GetByName returned Address_Null");
		return;
	}

	float fValue = TF2Attrib_GetValue(pCEconItemAttribute);

	if (fValue != g_fTestAttribValue)
	{
		LogError(LogPrefixFail ... "TF2Attrib_GetValue returned %f, expected %f", fValue, g_fTestAttribValue);
		return;
	}

	LogToGame(LogPrefixInfo ... "TF2Attrib_RemoveCustomPlayerAttribute '%s'", g_sTestAttribNameFloat);
	TF2Attrib_RemoveCustomPlayerAttribute(client, g_sTestAttribNameFloat);

	pCEconItemAttribute = TF2Attrib_GetByName(client, g_sTestAttribNameFloat);

	if (pCEconItemAttribute)
	{
		LogError(LogPrefixFail ... "TF2Attrib_RemoveCustomPlayerAttribute failed, attribute still present");
		return;
	}

	LogTestPassed(sTest);
}

void Test_TF2Attrib_HookValueFloat(int entity)
{
	char sTest[] = "TF2Attrib_HookValueFloat";
	LogTestStart(sTest);

	if (!TF2Attrib_SetByName(entity, g_sTestAttribNameFloat, g_fTestAttribValue))
	{
		LogError(LogPrefixFail ... "TF2Attrib_SetByName returned false");
		return;
	}

	LogToGame(LogPrefixInfo ... "TF2Attrib_HookValueFloat on attribute_class '%s'", g_sTestAttribClassFloat);
	float fInitial = 2.0; // Actually 1.0, but 2.0 tests better
	float fValue = TF2Attrib_HookValueFloat(fInitial, g_sTestAttribClassFloat, entity);

	if (!TF2Attrib_RemoveByName(entity, g_sTestAttribNameFloat))
	{
		LogError(LogPrefixFail ... "TF2Attrib_RemoveByName returned false");
		return;
	}

	float fExpected = fInitial * g_fTestAttribValue;

	if (fValue != fExpected)
	{
		LogError(LogPrefixFail ... "TF2Attrib_HookValueFloat returned %f, expected %f", fValue, fExpected);
		return;
	}

	LogTestPassed(sTest);
}

void Test_TF2Attrib_HookValueInt(int entity)
{
	char sTest[] = "TF2Attrib_HookValueInt";
	LogTestStart(sTest);

	if (!TF2Attrib_SetByName(entity, g_sTestAttribNameInt, view_as<float>(g_iTestAttribValue)))
	{
		LogError(LogPrefixFail ... "TF2Attrib_SetByName");
		return;
	}

	LogToGame(LogPrefixInfo ... "TF2Attrib_HookValueInt on attribute_class '%s'", g_sTestAttribClassInt);
	int iInitial = 1;
	int iValue = TF2Attrib_HookValueInt(iInitial, g_sTestAttribClassInt, entity);

	if (!TF2Attrib_RemoveByName(entity, g_sTestAttribNameInt))
	{
		LogError(LogPrefixFail ... "TF2Attrib_RemoveByName");
		return;
	}

	if (iValue != g_iTestAttribValue)
	{
		LogError(LogPrefixFail ... "TF2Attrib_HookValueInt returned %d, expected %d", iValue, g_iTestAttribValue);
		return;
	}

	LogTestPassed(sTest);
}

void Test_TF2Attrib_HookValueString(int iWeapon)
{
	char sTest[] = "TF2Attrib_HookValueString";
	LogTestStart(sTest);

	char sInitial[] = " yip!";

	LogToGame(LogPrefixInfo ... "TF2Attrib_HookValueString on 'custom_name_attr'", sInitial);
	char sNameTag[64];
	int iLen = TF2Attrib_HookValueString(sInitial, "custom_name_attr", iWeapon, sNameTag, sizeof(sNameTag));

	if (!iLen)
	{
		LogError(LogPrefixFail ... "TF2Attrib_HookValueString failed, returned length 0. " ...
			"Should at least return sInitial length(%d) if tested on item without 'custom_name_attr' attribute (name tag)", sizeof(sInitial) - 1);
		return;
	}

	if (!strncmp(sNameTag, sInitial, sizeof(sInitial) - 1))
	{
		LogToGame(LogPrefix ... "**Warning**: TF2Attrib_HookValueString output matches initial string. " ...
			"This should only happen if tested on an item without 'custom_name_attr' attribute (name tag), probably fine though if no crash", sNameTag, sInitial);
	}
	else
	{
		LogToGame(LogPrefixInfo ... "TF2Attrib_HookValueString returned name tag '%s'", sNameTag);
	}

	LogTestPassed(sTest);
}

void Test_TF2Attrib_SetRefundableCurrency(int entity)
{
	char sTest[] = "TF2Attrib_SetRefundableCurrency, TF2Attrib_GetRefundableCurrency";
	LogTestStart(sTest);

	if (!TF2Attrib_SetByDefIndex(entity, g_iTestAttribDefIndexFloat, g_fTestAttribValue))
	{
		LogError(LogPrefixFail ... "TF2Attrib_SetByDefIndex");
		return;
	}

	Address pCEconItemAttribute = TF2Attrib_GetByDefIndex(entity, g_iTestAttribDefIndexFloat);

	if (!pCEconItemAttribute)
	{
		LogError(LogPrefixFail ... "TF2Attrib_GetByDefIndex returned Address_Null");
		return;
	}

	int iSetCurrency = 150;

	LogToGame(LogPrefixInfo ... "TF2Attrib_SetRefundableCurrency to %d", iSetCurrency);
	TF2Attrib_SetRefundableCurrency(pCEconItemAttribute, iSetCurrency);

	LogToGame(LogPrefixInfo ... "TF2Attrib_GetRefundableCurrency on virtual address %u", pCEconItemAttribute);
	int iCurrency = TF2Attrib_GetRefundableCurrency(pCEconItemAttribute);

	if (iCurrency != iSetCurrency)
	{
		LogError(LogPrefixFail ... "TF2Attrib_GetRefundableCurrency returned %d, expected %d", iCurrency, iSetCurrency);
		return;
	}

	LogTestPassed(sTest);
}

void Test_TF2Attrib_SetGet_ClearCache(int entity)
{
	char sTest[] = "TF2Attrib_SetDefIndex, TF2Attrib_GetDefIndex, TF2Attrib_SetValue, TF2Attrib_ClearCache";
	LogTestStart(sTest);

	if (!TF2Attrib_SetByDefIndex(entity, g_iTestAttribDefIndexFloat, g_fTestAttribValue))
	{
		LogError(LogPrefixFail ... "TF2Attrib_SetByDefIndex");
		return;
	}

	Address pCEconItemAttribute = TF2Attrib_GetByDefIndex(entity, g_iTestAttribDefIndexFloat);

	if (!pCEconItemAttribute)
	{
		LogError(LogPrefixFail ... "TF2Attrib_GetByDefIndex returned Address_Null");
		return;
	}

	LogToGame(LogPrefixInfo ... "TF2Attrib_GetDefIndex virtual address %u", pCEconItemAttribute);
	int iDefIndex = TF2Attrib_GetDefIndex(pCEconItemAttribute);

	if (iDefIndex != g_iTestAttribDefIndexFloat)
	{
		LogError(LogPrefixFail ... "TF2Attrib_GetDefIndex returned %d, expected %d", iDefIndex, g_iTestAttribDefIndexFloat);
		return;
	}

	int iNewDefIndex = ATTR_HEALTH_REGEN;

	LogToGame(LogPrefixInfo ... "TF2Attrib_SetDefIndex to %d", iNewDefIndex);
	TF2Attrib_SetDefIndex(pCEconItemAttribute, iNewDefIndex);
	iDefIndex = TF2Attrib_GetDefIndex(pCEconItemAttribute);

	if (iDefIndex != iNewDefIndex)
	{
		LogError(LogPrefixFail ... "TF2Attrib_SetDefIndex failed, expected %d but got %d", iNewDefIndex, iDefIndex);
		return;
	}

	float fSetValue = 10.0;
	TF2Attrib_SetValue(pCEconItemAttribute, fSetValue);
	float fGetValue = TF2Attrib_GetValue(pCEconItemAttribute);

	if (fGetValue != fSetValue)
	{
		LogError(LogPrefixFail ... "TF2Attrib_SetValue/GetValue returned %f, expected %f", fGetValue, fSetValue);
		return;
	}

	LogToGame(LogPrefixInfo ... "TF2Attrib_ClearCache");
	if (!TF2Attrib_ClearCache(entity))
	{
		LogError(LogPrefixFail ... "TF2Attrib_ClearCache returned false, entity had invalid address or m_AttributeList missing");
		return;
	}

	if (!TF2Attrib_RemoveByDefIndex(entity, iNewDefIndex))
	{
		LogError(LogPrefixFail ... "TF2Attrib_RemoveByDefIndex failed, further tests will be tainted");
		return;
	}

	LogTestPassed(sTest);
}

void Test_TF2Attrib_SetFromStringValue(int entity)
{
	char sTest[] = "TF2Attrib_SetFromStringValue, TF2Attrib_UnsafeGetStringValue";
	LogTestStart(sTest);

	LogToGame(LogPrefixInfo ... "TF2Attrib_SetFromStringValue networked '%s' to value '%s'", g_sTestAttribNameFloat, g_sTestAttribValue);
	if (!TF2Attrib_SetFromStringValue(entity, g_sTestAttribNameFloat, g_sTestAttribValue))
	{
		LogError(LogPrefixFail ... "TF2Attrib_SetFromStringValue returned false for float attribute");
		return;
	}

	Address pCEconItemAttribute = TF2Attrib_GetByName(entity, g_sTestAttribNameFloat);

	if (!pCEconItemAttribute)
	{
		LogError(LogPrefixFail ... "TF2Attrib_GetByName returned Address_Null");
		return;
	}

	float fValue = TF2Attrib_GetValue(pCEconItemAttribute);

	if (fValue != g_fTestAttribValue)
	{
		LogError(LogPrefixFail ... "TF2Attrib_SetFromStringValue resulted in value %f, expected %f", fValue, g_fTestAttribValue);
		return;
	}

	if (!TF2Attrib_RemoveByName(entity, g_sTestAttribNameFloat))
	{
		LogError(LogPrefixFail ... "TF2Attrib_RemoveByName failed");
		return;
	}

	char sTestStringValue[] = "2007-10-10 21:09:46";
	char sSValue[sizeof(sTestStringValue)];

	LogToGame(LogPrefixInfo ... "TF2Attrib_SetFromStringValue non-networked '%s' to value '%s'", g_sTestAttribNameString, sTestStringValue);
	if (!TF2Attrib_SetFromStringValue(entity, g_sTestAttribNameString, sTestStringValue))
	{
		LogError(LogPrefixFail ... "TF2Attrib_SetFromStringValue returned false for string attribute");
		return;
	}

	pCEconItemAttribute = TF2Attrib_GetByName(entity, g_sTestAttribNameString);

	if (!pCEconItemAttribute)
	{
		LogError(LogPrefixFail ... "TF2Attrib_GetByName returned Address_Null for string attribute");
		return;
	}

	fValue = TF2Attrib_GetValue(pCEconItemAttribute);
	LogToGame(LogPrefixInfo ... "TF2Attrib_UnsafeGetStringValue on runtime m_flValue, which is storing virtual address %u", fValue);
	TF2Attrib_UnsafeGetStringValue(fValue, sSValue, sizeof(sSValue));

	if (strncmp(sSValue, sTestStringValue, sizeof(sTestStringValue)) != 0)
	{
		LogError(LogPrefixFail ... "TF2Attrib_SetFromStringValue resulted in string value '%s', expected '%s'", sSValue, sTestStringValue);
		return;
	}

	TF2Attrib_SetFromStringValue(entity, g_sTestAttribNameString, "");

	LogTestPassed(sTest);
}

void Test_TF2Attrib_RemoveAll(int entity)
{
	char sTest[] = "TF2Attrib_RemoveAll";
	LogTestStart(sTest);

	if (!TF2Attrib_SetByDefIndex(entity, g_iTestAttribDefIndexFloat, g_fTestAttribValue))
	{
		LogError(LogPrefixFail ... "TF2Attrib_SetByDefIndex");
		return;
	}

	TF2Attrib_RemoveAll(entity);

	Address pCEconItemAttribute = TF2Attrib_GetByDefIndex(entity, g_iTestAttribDefIndexFloat);

	if (pCEconItemAttribute)
	{
		LogError(LogPrefixFail ... "TF2Attrib_RemoveAll failed, test attribute still present");
		return;
	}

	LogTestPassed(sTest);
}

void LogTestStart(const char[] sTest)
{
	char sFormat[] = LogPrefix ... "Starting: %s";
	LogToGame(sFormat, sTest);
}

void LogTestPassed(const char[] sTest)
{
	char sFormat[] = LogPrefix ... "Passed: %s";
	LogToGame(sFormat, sTest);
}
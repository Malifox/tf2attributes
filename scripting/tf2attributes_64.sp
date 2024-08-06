#pragma semicolon 1
#pragma newdecls required

#include <sdktools>
//#define DEBUG
#include <port64>

#define PLUGIN_NAME		"[TF2] TF2Attributes"
#define PLUGIN_AUTHOR		"FlaminSarge, Malifox(x64 port)"
#define PLUGIN_VERSION		"1.8.0"
#define PLUGIN_CONTACT		"http://forums.alliedmods.net/showthread.php?t=210221"
#define PLUGIN_DESCRIPTION	"Functions to add/get attributes for TF2 players/items"

public Plugin myinfo = {
	name		= PLUGIN_NAME,
	author		= PLUGIN_AUTHOR,
	description	= PLUGIN_DESCRIPTION,
	version		= PLUGIN_VERSION,
	url		= PLUGIN_CONTACT
};

//CUtlVector offsets
enum m_Attributes_m_Memory //CUtlVector<CEconItemAttribute>
{
	Attributes_m_Memory_AttrIndex =	8,	//0x08
	Attributes_m_Memory_sizeof =	24,	//0x18
}

enum static_attrib_t64 //CUtlVector<static_attrib_t>
{
	StaticAttrib_iDefIndex =	0,	//0x00 // typedef uint16 item_definition_index_t
	StaticAttrib_m_value =		8,	//0x08 // attribute_data_union_t
	StaticAttrib_sizeof =		16,	//0x10
}

//CAttributeList offsets
enum CAttributeList64
{
	AL_CUtlVector_m_Attributes_m_Memory = 	8,	//0x08, CAttributeList.m_Attributes.m_Memory.m_pMemory
	AL_CUtlVector_m_Size =					24,	//0x18, 4 bytes padding after this
	AL_CUtlVector_pAttrElement =			32,	//0x20
	AL_m_pAttributeManager =				40,	//0x28
}
//CEconItemAttribute offsets
enum CEconItemAttribute64
{
	Attr_m_iAttributeDefinitionIndex =	8,	//0x08
	Attr_m_flValue =					12,	//0x0C
	Attr_m_nRefundableCurrency =		16,	//0x10
}

//CEconItemAttributeDefinition offsets
enum CEconItemAttributeDefinition64
{
	AttrDef_m_nDefIndex =			8,	//0x08 // u32
	AttrDef_m_pAttrType =			16,	//0x10, ISchemaAttributeType*
	AttrDef_m_bStoredAsInteger =	26,	//0x1A
	AttrDef_m_pszAttributeName =	0x48,
}

//CEconItemDefinition offsets
enum CEconItemDefinition64 //fox, doesn't match source code(source is maybe missing values added afterward)
{
	ItemDef_m_vecStaticAttributes		= 48,	//0x30, CUtlVector<static_attrib_t> //8 bytes more than expected
	ItemDef_m_vecStaticAttributes_iSize = 56,	//0x38 // 16 bytes more than expected
}

//CEconItem offsets
enum CEconItem64
{
	CEconItem_m_dirtyBits =						47,	//0x2F
	CEconItem_m_CustomAttribSingleton_index =	56,	//0x38 // attrib_definition_index_t m_unDefinitionIndex
	CEconItem_m_CustomAttribSingleton_value =	64,	//0x40 // attribute_data_union_t m_value
	//CEconItem_m_pCustomData =					72,	//0x48,
	CEconItem_m_pCustomData =					80,	//0x50, CEconItemCustomData*, fox, 8 bytes more than expected
}

// "counts as assister is some kind of pet this update is going to be awesome" is 73 characters. Valve... Valve.
#define MAX_ATTRIBUTE_NAME_LENGTH 128
#define MAX_ATTRIBUTE_VALUE_LENGTH PLATFORM_MAX_PATH

Handle hSDKGetItemDefinition;
Handle hSDKGetSOCData;
Handle hSDKSchema;
Handle hSDKGetAttributeDef;
Handle hSDKGetAttributeDefByName;
Handle hSDKSetRuntimeValue;
Handle hSDKGetAttributeByID;
Handle hSDKOnAttribValuesChanged;
Handle hSDKRemoveAttribute;
Handle hSDKDestroyAllAttributes;
Handle hSDKAddCustomAttribute;
Handle hSDKRemoveCustomAttribute;
Handle hSDKAttributeHookFloat, hSDKAttributeHookFloat64;
Handle hSDKAttributeHookInt;

// these two are mutually exclusive
Handle hSDKAttributeApplyStringWrapperWindows;
Handle hSDKAttributeApplyStringWrapperLinux;

Handle hSDKAttributeValueInitialize;
Handle hSDKAttributeTypeCanBeNetworked;
Handle hSDKAttributeValueFromString;
Handle hSDKAttributeValueUnload;
Handle hSDKAttributeValueUnloadByRef;
Handle hSDKCopyStringAttributeToCharPointer;

// caches attribute name to definition instance
StringMap g_AttributeDefinitionMapping;

// caches string_t instances from AllocPooledString
StringMap g_AllocPooledStringCache;

enum struct CAttributeList
{
	int low;
	int high;

	/**
	 * Sets this to entity address + the m_AttributeList offset.  This does not correspond to the CUtlVector instance
	 * (which is offset by 0x08).
	 */
	void GetEntityAttributeList(int entity)
	{
		int offsAttributeList = GetEntSendPropOffs(entity, "m_AttributeList", true);

		if (offsAttributeList <= 0)
			return;

		Port64_GetEntityAddress(entity, this, offsAttributeList);
	}

	any Load(CAttributeList64 offset, NumberType numberType)
	{
		any value[2];
		Port64_LoadFromAddress(this, view_as<int>(offset), numberType, value);

		return value[0];
	}

	void DereferencePointer(CAttributeList64 offset, any output[2])
	{
		Port64_LoadFromAddress(this, view_as<int>(offset), NumberType_Int64, output);
	}

	void AssertValid(int iMinValid = 0x10000)
	{
		if (!this.low && !this.high)
		{
			ThrowError("Received invalid address (NULL)");
		}
		if (!this.high)
		{
			if ((this.low >>> 31) == (iMinValid >>> 31) && ((this.low & 0x7FFFFFFF) < (iMinValid & 0x7FFFFFFF))
			|| (this.low >>> 31) < (iMinValid >>> 31))
				ThrowError("Received invalid address (0x%08X%08X), minimum = 0x%08X", this.high, this.low, iMinValid);
		}
	}

	void Add(int a)
	{
		int iBuffer[2];
		iBuffer[0] = a;

		Port64_Add(this, iBuffer, this);
	}

	bool IsNull()
	{
		return !this.low && !this.high;
	}
}

enum struct CEconItemAttributeDefinition
{
	int low;
	int high;

	void GetByID(int id)
	{
		Address64 pSchema;
		GetItemSchema(pSchema);

		if (pSchema.IsNull())
			return;

		SDKCall(hSDKGetAttributeDef, pSchema, this, id);
	}

	void GetByName(const char[] name)
	{
		if (g_AttributeDefinitionMapping.GetArray(name, this, sizeof(Address64))) {
			return;
		}

		Address64 pSchema;
		GetItemSchema(pSchema);

		if (pSchema.IsNull())
			return;

		SDKCall(hSDKGetAttributeDefByName, pSchema, this, name);
		g_AttributeDefinitionMapping.SetArray(name, this, sizeof(Address64));
	}

	void DereferencePointer(CEconItemAttributeDefinition64 offset, any output[2])
	{
		Port64_LoadFromAddress(this, view_as<int>(offset), NumberType_Int64, output);
	}

	any Load(CEconItemAttributeDefinition64 offset, NumberType numberType)
	{
		any value[2];
		Port64_LoadFromAddress(this, view_as<int>(offset), numberType, value);

		return value[0];
	}

	int LoadStringPointer(CEconItemAttributeDefinition64 offset, char[] buffer, int maxlen) {
		Address64 p;
		p.Set(this);
		
		Address64 pstr;
		p.DereferencePointer(view_as<int>(offset), pstr);
		return pstr.LoadString(buffer, maxlen);
	}

	bool Equals(CEconItemAttributeDefinition other)
	{
		return this.low == other.low && this.high == other.high;
	}

	bool IsNull()
	{
		return !this.low && !this.high;
	}
}

/**
 * since the game doesn't free heap-allocated non-GC attributes, we're taking on that
 * responsibility
 */
enum struct HeapAttributeValue
{
	Address64 m_pAttributeValue; // attribute_data_union_t
	int m_iAttributeDefinitionIndex;

	void Destroy()
	{
		CEconItemAttributeDefinition pEconItemAttributeDefinition;
		pEconItemAttributeDefinition.GetByID(this.m_iAttributeDefinitionIndex);

		UnloadAttributeRawValue(pEconItemAttributeDefinition, this.m_pAttributeValue);
	}
}
ArrayList g_ManagedAllocatedValues;

static bool g_bPluginReady = false;
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	char game[8];
	GetGameFolderName(game, sizeof(game));

	if (strncmp(game, "tf", 2, false) != 0) {
		strcopy(error, err_max, "Plugin only available for TF2 and possibly TF2Beta");
		return APLRes_Failure;
	}

	CreateNative("TF2Attrib_SetByName", Native_SetAttrib);
	CreateNative("TF2Attrib_SetByDefIndex", Native_SetAttribByID);
	CreateNative("TF2Attrib_SetFromStringValue", Native_SetAttribStringByName);
	CreateNative("TF2Attrib_GetByName", Native_GetAttrib);
	CreateNative("TF2Attrib_GetByDefIndex", Native_GetAttribByID);
	CreateNative("TF2Attrib_RemoveByName", Native_Remove);
	CreateNative("TF2Attrib_RemoveByDefIndex", Native_RemoveByID);
	CreateNative("TF2Attrib_RemoveAll", Native_RemoveAll);
	CreateNative("TF2Attrib_SetDefIndex", Native_SetID);
	CreateNative("TF2Attrib_GetDefIndex", Native_GetID);
	CreateNative("TF2Attrib_SetValue", Native_SetVal);
	CreateNative("TF2Attrib_GetValue", Native_GetVal);
	CreateNative("TF2Attrib_UnsafeGetStringValue", Native_GetStringVal);
	CreateNative("TF2Attrib_SetRefundableCurrency", Native_SetCurrency);
	CreateNative("TF2Attrib_GetRefundableCurrency", Native_GetCurrency);
	CreateNative("TF2Attrib_ClearCache", Native_ClearCache);
	CreateNative("TF2Attrib_ListDefIndices", Native_ListIDs);
	CreateNative("TF2Attrib_GetStaticAttribs", Native_GetStaticAttribs);
	CreateNative("TF2Attrib_GetSOCAttribs", Native_GetSOCAttribs);
	CreateNative("TF2Attrib_IsIntegerValue", Native_IsIntegerValue);
	CreateNative("TF2Attrib_IsValidAttributeName", Native_IsValidAttributeName);
	CreateNative("TF2Attrib_AddCustomPlayerAttribute", Native_AddCustomAttribute);
	CreateNative("TF2Attrib_RemoveCustomPlayerAttribute", Native_RemoveCustomAttribute);
	CreateNative("TF2Attrib_HookValueFloat", Native_HookValueFloat);
	CreateNative("TF2Attrib_HookValueInt", Native_HookValueInt);
	CreateNative("TF2Attrib_HookValueString", Native_HookValueString);
	CreateNative("TF2Attrib_IsReady", Native_IsReady);

	//unused, backcompat I guess?
	CreateNative("TF2Attrib_SetInitialValue", Native_DeprecatedPropertyAccess);
	CreateNative("TF2Attrib_GetInitialValue", Native_DeprecatedPropertyAccess);
	CreateNative("TF2Attrib_SetIsSetBonus", Native_DeprecatedPropertyAccess);
	CreateNative("TF2Attrib_GetIsSetBonus", Native_DeprecatedPropertyAccess);

	RegPluginLibrary("tf2attributes");
	return APLRes_Success;
}

public int Native_IsReady(Handle plugin, int numParams)
{
	return g_bPluginReady;
}

public void OnPluginStart()
{
	GameData gamedata = new GameData("tf2.attributes");
	if (!gamedata) {
		SetFailState("Could not locate gamedata file tf2.attributes.txt for TF2Attributes, pausing plugin");
	}

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CEconItemSchema::GetItemDefinition");
	PrepSDKCall_SetReturnInfo(SDKType_Pointer, SDKPass_Plain);	//Returns address of CEconItemDefinition
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	hSDKGetItemDefinition = EndPrepSDKCall();
	if (!hSDKGetItemDefinition) {
		SetFailState("Could not initialize call to CEconItemSchema::GetItemDefinition");
	}

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CEconItemView::GetSOCData");
	PrepSDKCall_SetReturnInfo(SDKType_Pointer, SDKPass_Plain);	//Returns address of CEconItem
	hSDKGetSOCData = EndPrepSDKCall();
	if (!hSDKGetSOCData) {
		SetFailState("Could not initialize call to CEconItemView::GetSOCData");
	}

	StartPrepSDKCall(SDKCall_Static);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "GEconItemSchema");
	PrepSDKCall_SetReturnInfo(SDKType_Pointer, SDKPass_Plain);	//Returns address of CEconItemSchema
	hSDKSchema = EndPrepSDKCall();
	if (!hSDKSchema) {
		SetFailState("Could not initialize call to GEconItemSchema");
	}

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CEconItemSchema::GetAttributeDefinition");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_Pointer, SDKPass_Plain);	//Returns address of a CEconItemAttributeDefinition
	hSDKGetAttributeDef = EndPrepSDKCall();
	if (!hSDKGetAttributeDef) {
		SetFailState("Could not initialize call to CEconItemSchema::GetAttributeDefinition");
	}

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CEconItemSchema::GetAttributeDefinitionByName");
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_Pointer, SDKPass_Plain);	//Returns address of a CEconItemAttributeDefinition
	hSDKGetAttributeDefByName = EndPrepSDKCall();
	if (!hSDKGetAttributeDefByName) {
		SetFailState("Could not initialize call to CEconItemSchema::GetAttributeDefinitionByName");
	}

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CAttributeList::RemoveAttribute");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	//PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);	//not a clue what this return is
	PrepSDKCall_SetReturnInfo(SDKType_Pointer, SDKPass_Plain);
	hSDKRemoveAttribute = EndPrepSDKCall();
	if (!hSDKRemoveAttribute) {
		LogMessage("Could not initialize call to CAttributeList::RemoveAttribute; using vscript fallback");
	}

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CAttributeList::SetRuntimeAttributeValue");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	//PrepSDKCall_SetReturnInfo(SDKType_Pointer, SDKPass_Plain); //Is now SDKType_Pointer, but was ignored before, so keep ignoring it
	//Apparently there's no return, so avoid setting return info, but the 'return' is nonzero if the attribute is added successfully
	//Just a note, the above SDKCall returns ((entindex + 4) * 4) | 0xA000), and you can AND it with 0x1FFF to get back the entindex if you want, though it's pointless)
	//I don't know any other specifics, such as if the highest 3 bits actually matter
	//And I don't know what happens when you hit ent index 2047

	hSDKSetRuntimeValue = EndPrepSDKCall();
	if (!hSDKSetRuntimeValue) {
		LogMessage("Could not initialize call to CAttributeList::SetRuntimeAttributeValue; using vscript fallback");
	}

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CAttributeList::DestroyAllAttributes");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain); //return is actually SDKType_Pointer, but we ignore the return
	hSDKDestroyAllAttributes = EndPrepSDKCall();
	if (!hSDKDestroyAllAttributes) {
		SetFailState("Could not initialize call to CAttributeList::DestroyAllAttributes");
	}

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CAttributeList::GetAttributeByID");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_Pointer, SDKPass_Plain);	//Returns address of a CEconItemAttribute
	hSDKGetAttributeByID = EndPrepSDKCall();
	if (!hSDKGetAttributeByID) {
		SetFailState("Could not initialize call to CAttributeList::GetAttributeByID");
	}

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CAttributeManager::OnAttributeValuesChanged");
	hSDKOnAttribValuesChanged = EndPrepSDKCall();
	if (!hSDKOnAttribValuesChanged) {
		SetFailState("Could not initialize call to CAttributeManager::OnAttributeValuesChanged");
	}

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFPlayer::AddCustomAttribute");
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	hSDKAddCustomAttribute = EndPrepSDKCall();
	if (!hSDKAddCustomAttribute) {
		SetFailState("Could not initialize call to CTFPlayer::AddCustomAttribute");
	}

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFPlayer::RemoveCustomAttribute");
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	hSDKRemoveCustomAttribute = EndPrepSDKCall();
	if (!hSDKRemoveCustomAttribute) {
		SetFailState("Could not initialize call to CTFPlayer::RemoveCustomAttribute");
	}

	StartPrepSDKCall(SDKCall_Static);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CAttributeManager::AttribHookValue<float>");
	PrepSDKCall_SetReturnInfo(SDKType_Float, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer); // attribute class
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer); // CBaseEntity* entity
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // CUtlVector<CBaseEntity*>, set to nullptr
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain); // bool const_string
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain); // initial value. fox, Is now the last parameter for some reason
	hSDKAttributeHookFloat = EndPrepSDKCall();
	if (!hSDKAttributeHookFloat) {
		// hack for port64, float parameter still first on win64
		StartPrepSDKCall(SDKCall_Static);
		PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CAttributeManager::AttribHookValue<float>_port64");
		PrepSDKCall_SetReturnInfo(SDKType_Float, SDKPass_Plain);
		PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer); // attribute class
		PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer); // CBaseEntity* entity
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // CUtlVector<CBaseEntity*>, set to nullptr
		PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain); // bool const_string
		hSDKAttributeHookFloat = EndPrepSDKCall();
	}
	
	if (!hSDKAttributeHookFloat && !hSDKAttributeHookFloat64) {
		SetFailState("Could not initialize call to CAttributeManager::AttribHookValue<float>");
	}

	StartPrepSDKCall(SDKCall_Static);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CAttributeManager::AttribHookValue<int>");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // initial value
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer); // attribute class
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer); // CBaseEntity* entity
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // CUtlVector<CBaseEntity*>, set to nullptr
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain); // bool const_string
	hSDKAttributeHookInt = EndPrepSDKCall();
	if (!hSDKAttributeHookInt) {
		SetFailState("Could not initialize call to CAttributeManager::AttribHookValue<int>");
	}

	// linux signature. this uses a hidden pointer passed in before `this` on the stack
	// so we'll do our best with static since SM doesn't support that calling convention
	// no subclasses override this virtual function so we'll just call it directly
	StartPrepSDKCall(SDKCall_Static);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CAttributeManager::ApplyAttributeStringWrapper");
	PrepSDKCall_SetReturnInfo(SDKType_Pointer, SDKPass_Plain); // return string_t
	//PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // return value. fox, calling convention changed in x64 so don't use this
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // thisptr
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // string_t initial value
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer); // initator entity (should contain thisptr)
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // string_t attribute class
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // CUtlVector<CBaseEntity*>, set to nullptr
	hSDKAttributeApplyStringWrapperLinux = EndPrepSDKCall();

	if (!hSDKAttributeApplyStringWrapperLinux) {
		// windows vcall. this one also uses a hidden pointer, but it's passed as the first param
		// `this` remains unchanged so we can still use a vcall
		StartPrepSDKCall(SDKCall_Raw);
		PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CAttributeManager::ApplyAttributeStringWrapper");
		PrepSDKCall_SetReturnInfo(SDKType_Pointer, SDKPass_Plain); // return string_t
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Pointer); // return value too
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // string_t initial value
		PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer); // CBaseEntity* entity
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // string_t attribute class
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // CUtlVector<CBaseEntity*>, set to nullptr
		hSDKAttributeApplyStringWrapperWindows = EndPrepSDKCall();
	}

	if (!hSDKAttributeApplyStringWrapperWindows && !hSDKAttributeApplyStringWrapperLinux) {
		SetFailState("Could not initialize call to CAttributeManager::ApplyAttributeStringWrapper");
	}

	StartPrepSDKCall(SDKCall_Raw); // CEconItemAttribute*
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual,
			"ISchemaAttributeTypeBase::InitializeNewEconAttributeValue");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Pointer, .encflags = VENCODE_FLAG_COPYBACK); // CAttributeDefinition*
	hSDKAttributeValueInitialize = EndPrepSDKCall();
	if (!hSDKAttributeValueInitialize) {
		SetFailState("Could not initialize call to ISchemaAttributeTypeBase::InitializeNewEconAttributeValue");
	}

	StartPrepSDKCall(SDKCall_Raw); // attr_type
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual,
			"ISchemaAttributeTypeBase::BSupportsGame..."); // 64 chars ought to be enough for anyone -- dvander, probably
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	hSDKAttributeTypeCanBeNetworked = EndPrepSDKCall();
	if (!hSDKAttributeTypeCanBeNetworked) {
		SetFailState("Could not initialize call to ISchemaAttributeTypeBase::BSupportsGameplayModificationAndNetworking");
	}

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual,
			"ISchemaAttributeTypeBase::BConvertStringToEconAttributeValue");
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Pointer, .encflags = VENCODE_FLAG_COPYBACK);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	hSDKAttributeValueFromString = EndPrepSDKCall();
	if (!hSDKAttributeValueFromString) {
		SetFailState("Could not initialize call to ISchemaAttributeTypeBase::BConvertStringToEconAttributeValue");
	}

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual,
			"ISchemaAttributeTypeBase::UnloadEconAttributeValue");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	hSDKAttributeValueUnload = EndPrepSDKCall();
	if (!hSDKAttributeValueUnload) {
		SetFailState("Could not initialize call to ISchemaAttributeTypeBase::UnloadEconAttributeValue");
	}

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual,
			"ISchemaAttributeTypeBase::UnloadEconAttributeValue");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Pointer);
	hSDKAttributeValueUnloadByRef = EndPrepSDKCall();
	if (!hSDKAttributeValueUnloadByRef) {
		SetFailState("Could not initialize call to ISchemaAttributeTypeBase::UnloadEconAttributeValue");
	}

	StartPrepSDKCall(SDKCall_Static);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature,
			"CopyStringAttributeValueToCharPointerOutput");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL, VENCODE_FLAG_COPYBACK); // char**, variable contains char* on return
	hSDKCopyStringAttributeToCharPointer = EndPrepSDKCall();
	if (!hSDKCopyStringAttributeToCharPointer) {
		SetFailState("Could not initialize call to CopyStringAttributeValueToCharPointerOutput");
	}

	CreateConVar("tf2attributes_version", PLUGIN_VERSION, "TF2Attributes version number", FCVAR_NOTIFY);

	g_bPluginReady = true;

	delete gamedata;

	g_ManagedAllocatedValues = new ArrayList(sizeof(HeapAttributeValue));
	g_AttributeDefinitionMapping = new StringMap();

	g_AllocPooledStringCache = new StringMap();
}

public void OnPluginEnd() {
	/**
	 * We don't need to do remove-on-entities on map end since their runtime lists will be gone,
	 * but we do need to remove them when the plugin is unloaded / reloaded, since we manage
	 * runtime non-networked attributes ourselves and they don't outlive the plugin.
	 */
	RemoveNonNetworkedRuntimeAttributesOnEntities();
	DestroyManagedAllocatedValues();
}

/**
 * Free up all attribute values that we allocated ourselves.
 */
public void OnMapEnd()
{
	DestroyManagedAllocatedValues();

	// because attribute injection's a thing now, we invalidate our internal mappings
	// in case everything changes during the next map
	g_AttributeDefinitionMapping.Clear();

	// pooled strings might get purged only between map changes
	g_AllocPooledStringCache.Clear();
}

/* native bool TF2Attrib_IsIntegerValue(int iDefIndex); */
public int Native_IsIntegerValue(Handle plugin, int numParams)
{
	int iDefIndex = GetNativeCell(1);

	CEconItemAttributeDefinition pEconItemAttributeDefinition;
	pEconItemAttributeDefinition.GetByID(iDefIndex);

	if (pEconItemAttributeDefinition.IsNull()) {
		return ThrowNativeError(1, "Attribute index %d is invalid", iDefIndex);
	}

	return pEconItemAttributeDefinition.Load(AttrDef_m_bStoredAsInteger, NumberType_Int8);
}

static int GetStaticAttribs(Address64 pItemDef, int[] iAttribIndices, int[] iAttribValues, int size = 16)
{
	pItemDef.AssertValid();

	//0x30(48) = CEconItemDefinition.m_Attributes (type CUtlVector<static_attrib_t>)
	//0x30(48) = (...) m_Attributes.m_Memory.m_pMemory (m_Attributes + 0x00)
	//0x38(56) = (...) m_Attributes.m_Size (m_Attributes + 0x0C)

	int iNumAttribs = pItemDef.Load(view_as<int>(ItemDef_m_vecStaticAttributes_iSize), NumberType_Int32);

	Address64 pAttribList;
	pItemDef.DereferencePointer(view_as<int>(ItemDef_m_vecStaticAttributes), pAttribList);

	// Read static_attrib_t (size 0x10) entries from contiguous block of memory
	for (int i = 0; i < iNumAttribs && i < size; i++)
	{
		if (i > 0)
			pAttribList.Add(view_as<int>(StaticAttrib_sizeof));

		iAttribIndices[i] = pAttribList.Load(view_as<int>(StaticAttrib_iDefIndex), NumberType_Int16);
		iAttribValues[i] = pAttribList.Load(view_as<int>(StaticAttrib_m_value), NumberType_Int32);
	}
	return iNumAttribs;
}

/* native int TF2Attrib_GetStaticAttribs(int iItemDefIndex, int[] iAttribIndices, float[] flAttribValues, int iMaxLen=16); */
public int Native_GetStaticAttribs(Handle plugin, int numParams)
{
	int iItemDefIndex = GetNativeCell(1);
	int size = 16;

	if (numParams >= 4) {
		size = GetNativeCell(4);
	}

	if (size <= 0) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Array size must be greater than 0 (currently %d)", size);
	}

	Address64 pSchema;
	GetItemSchema(pSchema);
	if (pSchema.IsNull()) {
		return -1;
	}

	Address64 pItemDef;
	SDKCall(hSDKGetItemDefinition, pSchema, pItemDef, iItemDefIndex);
	pItemDef.AssertValid();

	int[] iAttribIndices = new int[size];
	int[] iAttribValues = new int[size];
	int iCount = GetStaticAttribs(pItemDef, iAttribIndices, iAttribValues, size);

	SetNativeArray(2, iAttribIndices, size);
	SetNativeArray(3, iAttribValues, size);	//cast to float on inc side

	return iCount;
}

static int GetSOCAttribs(int iEntity, int[] iAttribIndices, int[] iAttribValues, int size = 16)
{
	if (size <= 0) {
		return -1;
	}
	Address64 pEconItemView;
	GetEntityEconItemView(iEntity, pEconItemView);
	if (pEconItemView.IsNull()) {
		return -1;
	}

	// pEconItem may be null if the item doesn't have SOC data (i.e., not from the item server)
	Address64 pEconItem;
	SDKCall(hSDKGetSOCData, pEconItemView, pEconItem);
	if (pEconItem.IsNull()) {
		return 0;
	}

	//80 (0x50) = CEconItem.m_pAttributes (type CUtlVector<static_attrib_t>*, possibly null)

	Address64 pCustomData;
	pEconItem.DereferencePointer(view_as<int>(CEconItem_m_pCustomData), pCustomData);

	if (pCustomData.low || pCustomData.high)
	{
		pCustomData.AssertValid();

		// 0x10 = (...) m_pAttributes->m_Size (m_pAttributes + 0x0C)
		// 0x00 = (...) m_pAttributes->m_Memory.m_pMemory (m_pAttributes + 0x00)

		int iCount = pCustomData.Load(view_as<int>(StaticAttrib_sizeof), NumberType_Int32);

		if (!iCount) {
			// abort early if the attribute list is empty -- we might deref garbage otherwise
			return 0;
		}

		Address64 pCustomDataArray;
		pCustomData.DereferencePointer(0, pCustomDataArray);

		// Read static_attrib_t (size 0x10) entries from contiguous block of memory
		for (int i = 0; i < iCount && i < size; ++i)
		{
			if (i > 0)
				pCustomDataArray.Add(view_as<int>(StaticAttrib_sizeof));

			iAttribIndices[i] = pCustomDataArray.Load(view_as<int>(StaticAttrib_iDefIndex), NumberType_Int16);
			iAttribValues[i] = pCustomDataArray.Load(view_as<int>(StaticAttrib_m_value), NumberType_Int32);
		}

		return iCount;
	}

	//(CEconItem+0x2F & 0b100 & 0xFF) != 0
	bool hasInternalAttribute = !!(pEconItem.Load(view_as<int>(CEconItem_m_dirtyBits), NumberType_Int8) & 0b100); //m_dirtyBits

	if (hasInternalAttribute)
	{
		iAttribIndices[0] = pEconItem.Load(view_as<int>(CEconItem_m_CustomAttribSingleton_index), NumberType_Int16); //attribute_t m_CustomAttribSingleton
		iAttribValues[0] = pEconItem.Load(view_as<int>(CEconItem_m_CustomAttribSingleton_value), NumberType_Int32); //attribute_t m_CustomAttribSingleton + 2 + 6(padding)

		return 1;
	}

	return 0;
}

/* native int TF2Attrib_GetSOCAttribs(int iEntity, int[] iAttribIndices, float[] flAttribValues, int iMaxLen=16); */
public int Native_GetSOCAttribs(Handle plugin, int numParams)
{
	int iEntity = GetNativeCell(1);
	int size = 16;

	if (numParams >= 4) {
		size = GetNativeCell(4);
	}

	if (size <= 0) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Array size must be greater than 0 (currently %d)", size);
	}

	if (!IsValidEntity(iEntity)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Entity %d (%d) is invalid", EntIndexToEntRef(iEntity), iEntity);
	}

	//maybe move some address stuff to here from the stock, but for now it's okay
	int[] iAttribIndices = new int[size]; int[] iAttribValues = new int[size];
	int iCount = GetSOCAttribs(iEntity, iAttribIndices, iAttribValues, size);

	SetNativeArray(2, iAttribIndices, size);
	SetNativeArray(3, iAttribValues, size);	//cast to float on inc side

	return iCount;
}

/* native bool TF2Attrib_SetByName(int iEntity, char[] strAttrib, float flValue); */
public int Native_SetAttrib(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);
	if (!IsValidEntity(entity)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Entity %d (%d) is invalid", EntIndexToEntRef(entity), entity);
	}

	char strAttrib[MAX_ATTRIBUTE_NAME_LENGTH];
	GetNativeString(2, strAttrib, sizeof(strAttrib));
	float flVal = GetNativeCell(3);

	CAttributeList pEntAttributeList;
	pEntAttributeList.GetEntityAttributeList(entity);

	if (pEntAttributeList.IsNull()) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Entity %d (%d) does not have property m_AttributeList", EntIndexToEntRef(entity), entity);
	}

	CEconItemAttributeDefinition pEconItemAttributeDefinition;
	pEconItemAttributeDefinition.GetByName(strAttrib);

	if (pEconItemAttributeDefinition.IsNull()) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Attribute name '%s' is invalid", strAttrib);
	}

	if (hSDKSetRuntimeValue) {
		SDKCall(hSDKSetRuntimeValue, pEntAttributeList, pEconItemAttributeDefinition, flVal);
	} else {
		// ensure we get exact representations of the original input value
		char script[192];
		Format(script, sizeof(script), "self.AddAttribute(\"%s\", casti2f(%d), 0)", strAttrib,
				view_as<int>(flVal));
		SetVariantString(script);
		AcceptEntityInput(entity, "RunScriptCode");
	}
	return true;
}

/* native bool TF2Attrib_SetByDefIndex(int iEntity, int iDefIndex, float flValue); */
public int Native_SetAttribByID(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);
	if (!IsValidEntity(entity)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Entity %d (%d) is invalid", EntIndexToEntRef(entity), entity);
	}

	int iAttrib = GetNativeCell(2);
	float flVal = GetNativeCell(3);

	CAttributeList pEntAttributeList;
	pEntAttributeList.GetEntityAttributeList(entity);

	if (pEntAttributeList.IsNull()) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Entity %d (%d) does not have property m_AttributeList", EntIndexToEntRef(entity), entity);
	}

	CEconItemAttributeDefinition pEconItemAttributeDefinition;
	pEconItemAttributeDefinition.GetByID(iAttrib);

	if (pEconItemAttributeDefinition.IsNull()) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Attribute index %d is invalid", iAttrib);
	}
	
	if (hSDKSetRuntimeValue) {
		SDKCall(hSDKSetRuntimeValue, pEntAttributeList, pEconItemAttributeDefinition, flVal);
	} else {
		char strAttrib[128];
		pEconItemAttributeDefinition.LoadStringPointer(AttrDef_m_pszAttributeName, strAttrib, sizeof(strAttrib));
		
		// ensure we get exact representations of the original input value
		char script[192];
		Format(script, sizeof(script), "self.AddAttribute(\"%s\", casti2f(%d), 0)", strAttrib,
				view_as<int>(flVal));
		SetVariantString(script);
		AcceptEntityInput(entity, "RunScriptCode");
	}
	return true;
}

/* native bool TF2Attrib_SetFromStringValue(int iEntity, const char[] strAttrib, const char[] strValue); */
public int Native_SetAttribStringByName(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);
	if (!IsValidEntity(entity)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Entity %d (%d) is invalid", EntIndexToEntRef(entity), entity);
	}

	CAttributeList pEntAttributeList;
	pEntAttributeList.GetEntityAttributeList(entity);

	if (pEntAttributeList.IsNull()) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Entity %d (%d) does not have property m_AttributeList", EntIndexToEntRef(entity), entity);
	}

	char strAttrib[MAX_ATTRIBUTE_NAME_LENGTH], strAttribVal[MAX_ATTRIBUTE_VALUE_LENGTH];
	GetNativeString(2, strAttrib, sizeof(strAttrib));
	GetNativeString(3, strAttribVal, sizeof(strAttribVal));

	int attrdef;
	if (!GetAttributeDefIndexByName(strAttrib, attrdef)) {
		// we don't throw on nonexistent attributes here; we return false and let the caller handle that
		return false;
	}

	// allocate a CEconItemAttribute instance in an entity's runtime attribute list
	if (!InitializeAttributeValue(pEntAttributeList, attrdef, strAttribVal)) {
		return false;
	}

	return true;
}

/* native Address TF2Attrib_GetByName(int iEntity, char[] strAttrib, Address64 pAttrib); */
int Native_GetAttrib(Handle plugin, int numParams)
{
	// There is a CAttributeList::GetByName, wonder why this is being done instead...
	int entity = GetNativeCell(1);
	if (!IsValidEntity(entity)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Entity %d (%d) is invalid", EntIndexToEntRef(entity), entity);
	}

	char strAttrib[MAX_ATTRIBUTE_NAME_LENGTH];
	GetNativeString(2, strAttrib, sizeof(strAttrib));

	CAttributeList pEntAttributeList;
	pEntAttributeList.GetEntityAttributeList(entity);

	if (pEntAttributeList.IsNull()) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Entity %d (%d) does not have property m_AttributeList", EntIndexToEntRef(entity), entity);
	}

	int iDefIndex;
	if (!GetAttributeDefIndexByName(strAttrib, iDefIndex)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Attribute name '%s' is invalid", strAttrib);
	}

	int pCEconItemAttribute[2];
	SDKCall(hSDKGetAttributeByID, pEntAttributeList, pCEconItemAttribute, iDefIndex);

	SetNativeArray(3, pCEconItemAttribute, sizeof(pCEconItemAttribute));

	return 0;
}

/* native Address TF2Attrib_GetByDefIndex(int iEntity, int iDefIndex, Address64 pAttrib); */
public int Native_GetAttribByID(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);
	if (!IsValidEntity(entity)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Entity %d (%d) is invalid", EntIndexToEntRef(entity), entity);
	}

	int iDefIndex = GetNativeCell(2);

	CAttributeList pEntAttributeList;
	pEntAttributeList.GetEntityAttributeList(entity);

	if (pEntAttributeList.IsNull()) {
		return 0;
	}

	int pAttrib[2];
	SDKCall(hSDKGetAttributeByID, pEntAttributeList, pAttrib, iDefIndex);

	SetNativeArray(3, pAttrib, sizeof(pAttrib));

	return 0;
}

/* native bool TF2Attrib_RemoveByName(int iEntity, char[] strAttrib); */
public int Native_Remove(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);
	if (!IsValidEntity(entity)){
		return ThrowNativeError(SP_ERROR_NATIVE, "Entity %d (%d) is invalid", EntIndexToEntRef(entity), entity);
	}

	char strAttrib[MAX_ATTRIBUTE_NAME_LENGTH];
	GetNativeString(2, strAttrib, sizeof(strAttrib));

	CAttributeList pEntAttributeList;
	pEntAttributeList.GetEntityAttributeList(entity);

	if (pEntAttributeList.IsNull()) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Entity %d (%d) does not have property m_AttributeList", EntIndexToEntRef(entity), entity);
	}

	CEconItemAttributeDefinition pEconItemAttributeDefinition;
	pEconItemAttributeDefinition.GetByName(strAttrib);

	if (pEconItemAttributeDefinition.IsNull()) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Attribute name '%s' is invalid", strAttrib);
	}

	Address64 uselessReturn;

	if (hSDKRemoveAttribute) {
		SDKCall(hSDKRemoveAttribute, pEntAttributeList, uselessReturn, pEconItemAttributeDefinition);	//Not a clue what the return is here, but it's probably a clone of the attrib being removed
	} else {
		// ensure we get exact representations of the original input value
		char script[192];
		Format(script, sizeof(script), "self.RemoveAttribute(\"%s\")", strAttrib);
		SetVariantString(script);
		AcceptEntityInput(entity, "RunScriptCode");
	}
	return true;
}

/* native bool TF2Attrib_RemoveByDefIndex(int iEntity, int iDefIndex); */
public int Native_RemoveByID(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);
	if (!IsValidEntity(entity)){
		return ThrowNativeError(SP_ERROR_NATIVE, "Entity %d (%d) is invalid", EntIndexToEntRef(entity), entity);
	}

	int iAttrib = GetNativeCell(2);

	CAttributeList pEntAttributeList;
	pEntAttributeList.GetEntityAttributeList(entity);

	if (pEntAttributeList.IsNull()){
		return ThrowNativeError(SP_ERROR_NATIVE, "Entity %d (%d) does not have property m_AttributeList", EntIndexToEntRef(entity), entity);
	}

	CEconItemAttributeDefinition pEconItemAttributeDefinition;
	pEconItemAttributeDefinition.GetByID(iAttrib);

	if (pEconItemAttributeDefinition.IsNull()){
		return ThrowNativeError(SP_ERROR_NATIVE, "Attribute index %d is invalid", iAttrib);
	}

	Address64 uselessReturn;

	if (hSDKRemoveAttribute) {
		SDKCall(hSDKRemoveAttribute, pEntAttributeList, uselessReturn, pEconItemAttributeDefinition);	//Not a clue what the return is here, but it's probably a clone of the attrib being removed
	} else {
		char strAttrib[128];
		pEconItemAttributeDefinition.LoadStringPointer(AttrDef_m_pszAttributeName, strAttrib, sizeof(strAttrib));
		
		// ensure we get exact representations of the original input value
		char script[192];
		Format(script, sizeof(script), "self.RemoveAttribute(\"%s\")", strAttrib);
		SetVariantString(script);
		AcceptEntityInput(entity, "RunScriptCode");
	}
	return true;
}

/* native bool TF2Attrib_RemoveAll(int iEntity); */
public int Native_RemoveAll(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);
	if (!IsValidEntity(entity)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Entity %d (%d) is invalid", EntIndexToEntRef(entity), entity);
	}

	CAttributeList pEntAttributeList;
	pEntAttributeList.GetEntityAttributeList(entity);

	if (pEntAttributeList.IsNull()) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Entity %d (%d) does not have property m_AttributeList", EntIndexToEntRef(entity), entity);
	}

	SDKCall(hSDKDestroyAllAttributes, pEntAttributeList);	//disregard the return (Valve does!)
	return true;
}

/* native void TF2Attrib_SetDefIndex(Address64 pAttrib, int iDefIndex); */
public void Native_SetID(Handle plugin, int numParams)
{
	Address64 pAttrib;
	GetNativeArray(1, pAttrib, sizeof(Address64));
	int iDefIndex = GetNativeCell(2);

	pAttrib.Store(view_as<int>(Attr_m_iAttributeDefinitionIndex), iDefIndex, NumberType_Int16);
}

/* native int TF2Attrib_GetDefIndex(Address64 pAttrib); */
public int Native_GetID(Handle plugin, int numParams)
{
	Address64 pAttrib;
	GetNativeArray(1, pAttrib, sizeof(Address64));

	return pAttrib.Load(view_as<int>(Attr_m_iAttributeDefinitionIndex), NumberType_Int16);
}

/* native void TF2Attrib_SetValue(Address pAttrib, float flValue); */
public void Native_SetVal(Handle plugin, int numParams)
{
	Address64 pAttrib;
	GetNativeArray(1, pAttrib, sizeof(Address64));
	float flVal = GetNativeCell(2);

	pAttrib.Store(view_as<int>(Attr_m_flValue), flVal, NumberType_Int32);
}

/* native float TF2Attrib_GetValue(Address64 pAttrib); */
public int Native_GetVal(Handle plugin, int numParams)
{
	Address64 pAttrib;
	GetNativeArray(1, pAttrib, sizeof(Address64));

	return pAttrib.Load(view_as<int>(Attr_m_flValue), NumberType_Int32);
}

/* TF2Attrib_UnsafeGetStringValue(any pRawValue, char[] buffer, int maxlen); */
public int Native_GetStringVal(Handle plugin, int numParams)
{
	Address64 pRawValue;
	GetNativeArray(1, pRawValue, 2);

	int maxlen = GetNativeCell(3), length;
	char[] buffer = new char[maxlen];

	ReadStringAttributeValue(pRawValue, buffer, maxlen);
	SetNativeString(2, buffer, maxlen, .bytes = length);

	return length;
}

/* native void TF2Attrib_SetRefundableCurrency(Address pAttrib, int nCurrency); */
public int Native_SetCurrency(Handle plugin, int numParams)
{
	Address64 pAttrib;
	GetNativeArray(1, pAttrib, 2);
	int nCurrency = GetNativeCell(2);

	pAttrib.Store(view_as<int>(Attr_m_nRefundableCurrency), nCurrency, NumberType_Int32);

	return nCurrency;
}

/* native int TF2Attrib_GetRefundableCurrency(Address pAttrib); */
public int Native_GetCurrency(Handle plugin, int numParams)
{
	Address64 pAttrib;
	GetNativeArray(1, pAttrib, 2);

	return pAttrib.Load(view_as<int>(Attr_m_nRefundableCurrency), NumberType_Int32);
}

public int Native_DeprecatedPropertyAccess(Handle plugin, int numParams)
{
	return ThrowNativeError(SP_ERROR_NATIVE, "Property associated with native function no longer exists");
}

static bool ClearAttributeCache(int entity)
{
	if (entity <= 0 || !IsValidEntity(entity)) {
		return false;
	}

	Address64 pAttributeManager;
	GetEntityAttributeManager(entity, pAttributeManager);
	if (pAttributeManager.IsNull()) {
		return false;
	}

	SDKCall(hSDKOnAttribValuesChanged, pAttributeManager);
	return true;
}

/* native bool TF2Attrib_ClearCache(int iEntity); */
public int Native_ClearCache(Handle plugin, int numParams) {
	int entity = GetNativeCell(1);
	if (!IsValidEntity(entity)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Entity %d (%d) is invalid", EntIndexToEntRef(entity), entity);
	}

	return ClearAttributeCache(entity);
}

/* native int TF2Attrib_ListDefIndices(int iEntity, int[] iDefIndices, int iMaxLen=20); */
public int Native_ListIDs(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);
	int size = 20;
	if (numParams >= 3) {
		size = GetNativeCell(3);
	}

	if (size <= 0) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Array size must be greater than 0 (currently %d)", size);
	}

	if (!IsValidEntity(entity)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Entity %d (%d) is invalid", EntIndexToEntRef(entity), entity);
	}

	CAttributeList pAttributeList;
	pAttributeList.GetEntityAttributeList(entity);

	if (pAttributeList.IsNull()) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Entity %d (%d) does not have property m_AttributeList", EntIndexToEntRef(entity), entity);
	}

	// 0x18 = CAttributeList.m_Attributes.m_Size (m_Attributes + 0x10)

	int iNumAttribs = pAttributeList.Load(AL_CUtlVector_m_Size, NumberType_Int32);
	if (!iNumAttribs) {
		return 0;
	}

	// 0x08 = CAttributeList.m_Attributes (type CUtlVector<CEconItemAttribute>)
	// 0x08 = CAttributeList.m_Attributes.m_Memory.m_pMemory

	Address64 pAttribListData;
	pAttributeList.DereferencePointer(AL_CUtlVector_m_Attributes_m_Memory, pAttribListData);
	pAttribListData.AssertValid();

	int[] iAttribIndices = new int[size];

	// Read CEconItemAttribute (size 0x18) entries from contiguous block of memory
	for (int i = 0; i < iNumAttribs && i < size; i++)
	{
		if (i > 0)
			pAttribListData.Add(view_as<int>(Attributes_m_Memory_sizeof));

		iAttribIndices[i] = pAttribListData.Load(view_as<int>(Attributes_m_Memory_AttrIndex), NumberType_Int16);
	}
	SetNativeArray(2, iAttribIndices, size);

	return iNumAttribs;
}

/* native bool TF2Attrib_IsValidAttributeName(const char[] strAttrib); */
public int Native_IsValidAttributeName(Handle plugin, int numParams)
{
	char strAttrib[MAX_ATTRIBUTE_NAME_LENGTH];
	GetNativeString(1, strAttrib, sizeof(strAttrib));

	CEconItemAttributeDefinition pEconItemAttributeDefinition;
	pEconItemAttributeDefinition.GetByName(strAttrib);

	return  pEconItemAttributeDefinition.low || pEconItemAttributeDefinition.high;
}

/* native void TF2Attrib_AddCustomPlayerAttribute(int client, const char[] strAttrib, float flValue, float flDuration = -1.0); */
public int Native_AddCustomAttribute(Handle plugin, int numParams)
{
	char strAttrib[MAX_ATTRIBUTE_NAME_LENGTH];

	int client = GetNativeCell(1);
	GetNativeString(2, strAttrib, sizeof(strAttrib));

	CEconItemAttributeDefinition pEconItemAttributeDefinition;
	pEconItemAttributeDefinition.GetByName(strAttrib);

	if (pEconItemAttributeDefinition.IsNull()) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Attribute name '%s' is invalid", strAttrib);
	}

	float flValue = GetNativeCell(3);
	float flDuration = GetNativeCell(4);

	SDKCall(hSDKAddCustomAttribute, client, strAttrib, flValue, flDuration);
	return 0;
}

public int Native_RemoveCustomAttribute(Handle plugin, int numParams)
{
	char strAttrib[MAX_ATTRIBUTE_NAME_LENGTH];

	int client = GetNativeCell(1);
	GetNativeString(2, strAttrib, sizeof(strAttrib));

	CEconItemAttributeDefinition pEconItemAttributeDefinition;
	pEconItemAttributeDefinition.GetByName(strAttrib);

	if (pEconItemAttributeDefinition.IsNull()) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Attribute name '%s' is invalid", strAttrib);
	}

	SDKCall(hSDKRemoveCustomAttribute, client, strAttrib);
	return 0;
}

/* native float TF2Attrib_HookValueFloat(float flInitial, const char[] attrClass, int iEntity); */
public int Native_HookValueFloat(Handle plugin, int numParams)
{
	/**
	 * CAttributeManager::AttribHookValue<float>(float value, string_t attr_class,
	 *         CBaseEntity const* entity, CUtlVector<CBaseEntity*> reentrantList,
	 *         bool is_const_str);
	 *
	 * `value` is the value that is returned after modifiers based on `attr_class`.
	 * `reentrantList` seems to be a list of entities to ignore?
	 * `is_const_str` is true iff the `attr_class` is hardcoded
	 *     (i.e., it's at a fixed location) -- this is never true from a plugin
	 *     This determines if the game uses AllocPooledString_StaticConstantStringPointer
	 *     (when is_const_str == true) or AllocPooledString (false).
	 */
	float initial = GetNativeCell(1);

	int buflen;
	GetNativeStringLength(2, buflen);
	char[] attrClass = new char[++buflen];
	GetNativeString(2, attrClass, buflen);

	int entity = GetNativeCell(3);

	if (hSDKAttributeHookFloat) {
		return SDKCall(hSDKAttributeHookFloat, attrClass, entity, Address64_Null, false, initial);
	} else if (hSDKAttributeHookFloat64) {
		return SDKCall(hSDKAttributeHookFloat, initial, attrClass, entity, Address64_Null, false);
	}
	// we should never reach this
	ThrowError("No available SDKCall for CAttributeManager::AttribHookValue<float>");
	return 0;
}

/* native float TF2Attrib_HookValueInt(int nInitial, const char[] attrClass, int iEntity); */
public int Native_HookValueInt(Handle plugin, int numParams)
{
	int initial = GetNativeCell(1);

	int buflen;
	GetNativeStringLength(2, buflen);
	char[] attrClass = new char[++buflen];
	GetNativeString(2, attrClass, buflen);

	int entity = GetNativeCell(3);

	return SDKCall(hSDKAttributeHookInt, initial, attrClass, entity, Address64_Null, false);
}

/* native void TF2Attrib_HookValueString(const char[] initial, const char[] attrClass,
		int iEntity, char[] buffer, int maxlen); */
public int Native_HookValueString(Handle plugin, int numParams)
{
	int buflen;

	GetNativeStringLength(1, buflen);
	char[] inputValue = new char[++buflen];
	GetNativeString(1, inputValue, buflen);

	GetNativeStringLength(2, buflen);
	char[] attrClass = new char[++buflen];
	GetNativeString(2, attrClass, buflen);

	int entity = GetNativeCell(3);

	Address64 pInput;
	Address64 pAttrClass;
	Address64 pAttributeManager;

	// string needs to be pooled for caching purposes
	AllocPooledString(inputValue, pInput);
	AllocPooledString(attrClass, pAttrClass);
	GetEntityAttributeManager(entity, pAttributeManager);

	buflen = GetNativeCell(5);
	char[] output = new char[buflen];

	Address64 pOutput;
	if (hSDKAttributeApplyStringWrapperWindows)
	{
		/* // windows version; hidden ptr pushes params, `this` still in correct register
		Address result;
		pOutput = SDKCall(hSDKAttributeApplyStringWrapperWindows,
				GetEntityAttributeManager(entity), result, pInput, entity, pAttrClass,
				Address_Null); */

		return ThrowNativeError(SP_ERROR_NATIVE, "TF2Attrib_HookValueString is not yet implemented on Windows");
	}
	else if (hSDKAttributeApplyStringWrapperLinux)
	{
		// linux version; hidden ptr moves the stack and this forward. fox, no longer true, calling convention changed.
		//Address result;

		// pOutput = SDKCall(hSDKAttributeApplyStringWrapperLinux, result,
		// 		GetEntityAttributeManager(entity), pInput, entity, pAttrClass, Address_Null);

		SDKCall(hSDKAttributeApplyStringWrapperLinux, pOutput, pAttributeManager, pInput, entity, pAttrClass, Address64_Null);
	}

	pOutput.LoadString(output, buflen);

	int written;
	SetNativeString(4, output, buflen, .bytes = written);
	return written;
}

/* helper functions */

void GetItemSchema(Address64 pSchema)
{
	SDKCall(hSDKSchema, pSchema);
}

void GetEntityEconItemView(int entity, Address64 result)
{
	int iCEIVOffset = GetEntSendPropOffs(entity, "m_Item", true);
	if (iCEIVOffset > 0) {
		result.GetEntityAddress(entity, .offset = iCEIVOffset);
	}
}

/**
 * Returns true if an attribute with the specified name exists, storing the definition index
 * to the given by-ref `iDefIndex` argument.
 */
static bool GetAttributeDefIndexByName(const char[] name, int &iDefIndex)
{
	CEconItemAttributeDefinition pEconItemAttributeDefinition;
	pEconItemAttributeDefinition.GetByName(name);
	if (pEconItemAttributeDefinition.IsNull()) {
		return false;
	}

	iDefIndex = pEconItemAttributeDefinition.Load(AttrDef_m_nDefIndex, NumberType_Int16);
	return true;
}

void GetEntityAttributeManager(int entity, Address64 pAttributeManager)
{
	CAttributeList pEntAttributeList;
	pEntAttributeList.GetEntityAttributeList(entity);

	if (pEntAttributeList.IsNull())
		return;

	pEntAttributeList.DereferencePointer(AL_m_pAttributeManager, pAttributeManager);
	pAttributeManager.AssertValid();
}

/**
 * Initializes the space occupied by a given CEconItemAttribute pointer, parsing and allocating
 * the raw value based on the attribute's underlying type.  This should correctly parse numeric
 * and string values.
 */
static bool InitializeAttributeValue(CAttributeList pAttributeList, int attrdef, const char[] value)
{
	CEconItemAttributeDefinition pEconItemAttributeDefinition;
	pEconItemAttributeDefinition.GetByID(attrdef);
	if (pEconItemAttributeDefinition.IsNull()) {
		return false;
	}

	Address64 pDefType;
	pEconItemAttributeDefinition.DereferencePointer(AttrDef_m_pAttrType, pDefType);

	bool networked = IsNetworkedRuntimeAttribute(pDefType);

	if (!networked)
	{
		// reusing any existing matching attribute value strings
		Address64 rawAttributeValue;
		GetHeapManagedAttributeString(attrdef, value, rawAttributeValue);

		if (rawAttributeValue.low || rawAttributeValue.high)
		{
			SDKCall(hSDKSetRuntimeValue, pAttributeList, pEconItemAttributeDefinition, view_as<float>(rawAttributeValue.low));
			return true;
		}
	}

	// since attribute value is a union of 32 bit types, this is okay
	//int attributeValue = 0;

	/**
	 * initialize raw value; any existing values present in the CEconItemAttribute* are trashed
	 *
	 * that is okay -- tf2attributes is the only one managing heap-allocated values, and
	 * it holds its own reference to the value for freeing later
	 *
	 * we don't attempt to free any existing attribute value mid-game as we don't know if
	 * the value is present in multiple places (no refcounts!)
	 */

	Address64 attributeValue;
	SDKCall(hSDKAttributeValueInitialize, pDefType, attributeValue);

	if (!SDKCall(hSDKAttributeValueFromString, pDefType, pEconItemAttributeDefinition, value, attributeValue, true)) {
		// in case AttributeValueInitialize created a pointer, unload it
		UnloadAttributeRawValue(pEconItemAttributeDefinition, attributeValue);
		// we couldn't parse the attribute value, abort
		return false;
	}

	SDKCall(hSDKSetRuntimeValue, pAttributeList, pEconItemAttributeDefinition, view_as<float>(attributeValue.low));

	if (!networked) {
		// add to our managed values
		// this definitely works for heap, not sure if it works for inline
		HeapAttributeValue attribute;
		attribute.m_iAttributeDefinitionIndex = attrdef;
		attribute.m_pAttributeValue = attributeValue;

		g_ManagedAllocatedValues.PushArray(attribute);
	}

	return true;
}

/**
 * Returns the address of an existing instance for the given attribute definition and string
 * value, if it exists.
 */
void GetHeapManagedAttributeString(int attrdef, const char[] value, Address64 result)
{
	/**
	 * we restrict it to strings as we don't have a way to determine equality on non-string
	 * attributes.
	 */
	if (!IsAttributeString(attrdef)) {
		return;
	}

	for (int i, n = g_ManagedAllocatedValues.Length; i < n; i++)
	{
		HeapAttributeValue existingAttribute;
		g_ManagedAllocatedValues.GetArray(i, existingAttribute, sizeof(existingAttribute));

		if (existingAttribute.m_iAttributeDefinitionIndex != attrdef) {
			continue;
		}

		char attributeString[PLATFORM_MAX_PATH];

		ReadStringAttributeValue(existingAttribute.m_pAttributeValue, attributeString, sizeof(attributeString));
		if (StrEqual(attributeString, value)) {
			result.Set(existingAttribute.m_pAttributeValue);
		}
	}
}

/**
 * Returns true if the given attribute type can (normally) be networked.
 * We make the assumption that non-networked attributes have to be heap / inline allocated.
 */
static bool IsNetworkedRuntimeAttribute(Address64 pDefType)
{
	return SDKCall(hSDKAttributeTypeCanBeNetworked, pDefType);
}

/**
 * Unloads the attribute in a given CEconItemAttribute instance.
 */
#pragma unused UnloadAttributeValue
void UnloadAttributeValue(CEconItemAttributeDefinition pAttrDef, Address64 pEconItemAttribute)
{
	Address64 pDefType;
	pAttrDef.DereferencePointer(AttrDef_m_pAttrType, pDefType);

	Address64 pAttributeValue;
	pAttributeValue = pEconItemAttribute;
	pAttributeValue.Add(view_as<int>(Attr_m_flValue));

	SDKCall(hSDKAttributeValueUnload, pDefType, pAttributeValue);
}

/**
 * Unloads the given raw attribute value.
 */
static void UnloadAttributeRawValue(CEconItemAttributeDefinition pAttrDef, Address64 pAttributeValue)
{
	Address64 pDefType;
	pAttrDef.DereferencePointer(AttrDef_m_pAttrType, pDefType);

	SDKCall(hSDKAttributeValueUnloadByRef, pDefType, pAttributeValue); //pAttributeValue = pAttributeDataUnion
}

/**
 * Returns true if the given attribute definition index is a string.
 */
static bool IsAttributeString(int attrdef)
{
	CEconItemAttributeDefinition pEconItemAttributeDefinition;
	CEconItemAttributeDefinition pKnownStringAttribDef;

	pEconItemAttributeDefinition.GetByID(attrdef);
	pKnownStringAttribDef.GetByName("cosmetic taunt sound");

	pEconItemAttributeDefinition.DereferencePointer(AttrDef_m_pAttrType, pEconItemAttributeDefinition);
	pKnownStringAttribDef.DereferencePointer(AttrDef_m_pAttrType, pKnownStringAttribDef);

	return (pEconItemAttributeDefinition.high || pEconItemAttributeDefinition.low)
		&& (pKnownStringAttribDef.high || pKnownStringAttribDef.low) && pEconItemAttributeDefinition.Equals(pKnownStringAttribDef);
}

/**
 * Reads the contents of a CAttribute_String raw value.
 */
static int ReadStringAttributeValue(Address64 pRawValue, char[] buffer, int maxlen)
{
	/**
	 * Linux, Windows, and Mac differ slightly on how the std::string is laid out.
	 *
	 * For the Linux binary, the first member is a char* containing the contents of the string.
	 * Deref that and call it a day.
	 *
	 * Windows implements it as a union where it's either a `char[16]` or a `char*, size_t @ 0x14`.
	 * Check if the size_t is less than 16, then read the inline string or deref the char* depending on the results.
	 *
	 * Mac implements it as either a `bool, char[]` or `bool, char* @ 0x8`.
	 *
	 * I'm too lazy to reimplement the platform-specific bits; we're going to use sigs for this.
	 */
	Address64 pString;
	SDKCall(hSDKCopyStringAttributeToCharPointer, pRawValue, pString);

	return pString.LoadString(buffer, maxlen);
}

/**
 * Iterates over entities and removes any attributes that aren't networked (that is,
 * allocated on the heap).
 *
 * We must do this before we unload ourselves, otherwise the game will crash trying to look up
 * the heap runtime attributes we managed.
 */
static void RemoveNonNetworkedRuntimeAttributesOnEntities()
{
	// remove heap-based attributes from any existing entities so they don't use-after-free
	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "*")) != -1) {
		// iterate runtime attribute list and remove string attributes
		// implementation straight from TF2Attrib_ListDefIndices, go over there for details

		CAttributeList pAttributeList;
		pAttributeList.GetEntityAttributeList(entity);

		if (pAttributeList.IsNull()) {
			continue;
		}
	#if defined DEBUG
		PrintToChatAll("RemoveNonNetworkedRuntimeAttributesOnEntities: entity = %d, pAttributeList = %X %X", entity, pAttributeList.low, pAttributeList.high);
		LogToGame("RemoveNonNetworkedRuntimeAttributesOnEntities: entity = %d, pAttributeList = %X %X", entity, pAttributeList.low, pAttributeList.high);
	#endif

		// hold attribute defs pointing to heaped attributes so we don't mutate the runtime
		// attribute list while we iterate over it - according to the CUtlVector docs the list
		// can be realloc'd when an element is removed

		// the runtime attribute list can be any size, the current limit of 20 is on networked
		ArrayList heapedAttribDefs = new ArrayList();

		int iNumAttribs = pAttributeList.Load(AL_CUtlVector_m_Size, NumberType_Int32);
		if (!iNumAttribs) {
			continue;
		}

	#if defined DEBUG
		PrintToChatAll("RemoveNonNetworkedRuntimeAttributesOnEntities: entity = %d, iNumAttribs = %d", entity, iNumAttribs);
	#endif

		Address64 pAttribListData;

		pAttributeList.DereferencePointer(AL_CUtlVector_m_Attributes_m_Memory, pAttribListData);

		// we know there are attributes; make sure our contiguous memory is valid
		//AssertValidAddress(pAttribListData);
		pAttribListData.AssertValid();

		//Address64 pAttributeEntry;
		Address64 pDefType;

		for (int i = 0; i < iNumAttribs; i++) {
			if (i > 0)
				pAttribListData.Add(view_as<int>(Attributes_m_Memory_sizeof)); //pAttributeEntry

			int attrdef = pAttribListData.Load(view_as<int>(Attr_m_iAttributeDefinitionIndex), NumberType_Int16);

			CEconItemAttributeDefinition pEconItemAttributeDefinition;
			pEconItemAttributeDefinition.GetByID(attrdef);

			if (pEconItemAttributeDefinition.IsNull()) {
				// this shouldn't happen, but just in case
				continue;
			}

			pEconItemAttributeDefinition.DereferencePointer(AttrDef_m_pAttrType, pDefType);
			if (IsNetworkedRuntimeAttribute(pDefType)) {
				continue;
			}

			Address64 rawValue;
			pAttribListData.DereferencePointer(view_as<int>(Attr_m_flValue), rawValue);

			// allow plugins to `TF2Attrib_Set*()` their own instances undisturbed by only
			// processing attributes that we're aware of
			if (IsAttributeValueInHeap(rawValue)) {
				// we should be passing around pEconItemAttributeDefinition instead,
				// but I want the nice display printout
			#if defined DEBUG
				PrintToChatAll("RemoveNonNetworkedRuntimeAttributesOnEntities: attrdef = %d, rawValue = %1.1f, pAttribListData = %X %X", attrdef, rawValue, pAttribListData.low, pAttribListData.high);
			#endif
				heapedAttribDefs.Push(attrdef);
			}
		}

		while (heapedAttribDefs.Length) {
			int attrdef = heapedAttribDefs.Get(0);
			heapedAttribDefs.Erase(0);

			CEconItemAttributeDefinition pEconItemAttributeDefinition;
			pEconItemAttributeDefinition.GetByID(attrdef);

			PrintToServer("[tf2attributes] "
					... "Removing heap-allocated attribute index %d from entity %d",
					attrdef, entity);

			SDKCall(hSDKRemoveAttribute, pAttributeList, pEconItemAttributeDefinition);
		}
		delete heapedAttribDefs;

		ClearAttributeCache(entity);
	}
}

/**
 * Frees our heap-allocated managed attribute values so they don't leak.
 * This happens on map change (where runtime attributes are invalidated) and when the plugin is
 * unloaded.
 */
void DestroyManagedAllocatedValues()
{
	while (g_ManagedAllocatedValues.Length)
	{
		HeapAttributeValue attribute;
		g_ManagedAllocatedValues.GetArray(0, attribute, sizeof(attribute));

		attribute.Destroy();
		g_ManagedAllocatedValues.Erase(0);
	}
}

bool IsAttributeValueInHeap(Address64 rawValue)
{
	for (int i, n = g_ManagedAllocatedValues.Length; i < n; i++)
	{
		HeapAttributeValue a;
		g_ManagedAllocatedValues.GetArray(i, a, sizeof(a));

		if (a.m_pAttributeValue.Equals(rawValue)) {
			return true;
		}
	}

	return false;
}

/**
 * Inserts a string into the game's string pool.  This uses the same implementation that is in
 * SourceMod's core:
 *
 * https://github.com/alliedmodders/sourcemod/blob/b14c18ee64fc822dd6b0f5baea87226d59707d5a/core/HalfLife2.cpp#L1415-L1423
 */
void AllocPooledString(const char[] value, Address64 result) //fox, GetEntData and SetEntData don't support reading 8 bytes.
{
	if (g_AllocPooledStringCache.GetArray(value, result, sizeof(Address64))) {
		return;
	}

	int ent = FindEntityByClassname(-1, "worldspawn");
	if (ent == -1) {
		return;
	}

	int offset = FindDataMapInfo(ent, "m_iName");
	if (offset <= 0) {
		return;
	}

	// Address pOrig = view_as<Address>(GetEntData(ent, offset));
	// DispatchKeyValue(ent, "targetname", value);
	// pValue = view_as<Address>(GetEntData(ent, offset));
	// SetEntData(ent, offset, pOrig);

	// g_AllocPooledStringCache.SetValue(value, pValue);
	// return pValue;

	Address64 pOrig;
	Address64 pOrigValue;

	pOrig.GetEntityAddress(ent);
	pOrig.DereferencePointer(offset, pOrigValue);

	DispatchKeyValue(ent, "targetname", value);

	pOrig.DereferencePointer(offset, result);
	pOrig.StorePointer(offset, pOrigValue);

	//SetEdictFlags(ent, (GetEdictFlags(ent) | FL_EDICT_CHANGED));

	g_AllocPooledStringCache.SetArray(value, result, sizeof(Address64));
}

/**
 * Runtime assertion that we're receiving valid addresses.
 * If we're not, something has gone terribly wrong and we might need to update.
 */
/* stock void AssertValidAddress(Address pAddress) {
	static Address Address_MinimumValid = view_as<Address>(0x10000);
	if (pAddress == Address_Null) {
		ThrowError("Received invalid address (NULL)");
	}
	if (unsigned_compare(view_as<int>(pAddress), view_as<int>(Address_MinimumValid)) < 0) {
		ThrowError("Received invalid address (%08x)", pAddress);
	}
} */

/* stock int unsigned_compare(int a, int b) {
	if (a == b) {
		return 0;
	}
	if ((a >>> 31) == (b >>> 31)) {
		return ((a & 0x7FFFFFFF) > (b & 0x7FFFFFFF)) ? 1 : -1;
	}
	return ((a >>> 31) > (b >>> 31)) ? 1 : -1;
} */
/*
struct CEconItemAttributeDefinition
{
	WORD index,						//4
	WORD blank,
	DWORD type,						//8
	BYTE hidden,					//12
	BYTE force_output_description,	//13
	BYTE stored_as_integer,			//14
	BYTE instance_data,				//15
	BYTE is_set_bonus,				//16
	BYTE blank,
	BYTE blank,
	BYTE blank,
	DWORD is_user_generated,		//20
	DWORD effect_type,				//24
	DWORD description_format,		//28
	DWORD description_string,		//32
	DWORD armory_desc,				//36
	DWORD name,						//40
	DWORD attribute_class,			//44
	BYTE can_affect_market_name,	//48
	BYTE can_affect_recipe_component_name,	//49
	BYTE blank,
	BYTE blank,
	DWORD apply_tag_to_item_definition,	//52
	DWORD unknown

};*/
/*class CEconItemAttribute
{
public:
	void *m_pVTable; //0

	uint16 m_iAttributeDefinitionIndex; //4
	float m_flValue; //8
	int32 m_nRefundableCurrency; //12
-----removed	float m_flInitialValue; //12
-----removed	bool m_bSetBonus; //20
};
and +24 is still attribute manager
*/

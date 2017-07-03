--About ALMA_NCIP_Lending_Client 1.7
--
--Author:  Bill Jones III, SUNY Geneseo, IDS Project, jonesw@geneseo.edu
--Modified by: Kurt Munson, Northwestern University, kmunson@northwestern.edu
--Modified further by: Matt Niehoff, Minitex - University of Minnesota, nieho003@umn.edu
--System Addon used for ILLiad to communicate with Alma through the NCIP protocol to move
--Lending requests into the resource sharing libary in Alma when updated to filled and
--to return items to thier perment location upon return.
--
--Description of Registered Event Handlers for ILLiad
--
--LendingRequestCheckOut
--This will trigger whenever a transaction is processed from the Lending Update Stacks Searching form
--using the Mark Found or Mark Found Scan Now buttons. This will also work on the Lending Processing ribbon
--of the Request form for the Mark Found and Mark Found Scan Now buttons.
--
--LendingRequestCheckIn
--This will trigger whenever a transaction is processed from the Lending Returns batch processing form.
--
--Queue names have a limit of 40 characters (including spaces).


local Settings = {};

--NCIP Responder URL
Settings.NCIP_Responder_URL = GetSetting("NCIP_Responder_URL");

--NCIP Error Status Changes
Settings.LendingCheckOutItemFailQueue = GetSetting("LendingCheckOutItemFailQueue");
Settings.LendingCheckInItemFailQueue = GetSetting("LendingCheckInItemFailQueue");

--acceptItem settings
Settings.acceptItem_from_uniqueAgency_value = GetSetting("acceptItem_from_uniqueAgency_value");
Settings.acceptItem_Transaction_Prefix = GetSetting("checkInItem_Transaction_Prefix");

--checkInItem settings
Settings.ApplicationProfileType = GetSetting("ApplicationProfileType");
Settings.checkInItem_Transaction_Prefix = GetSetting("checkInItem_Transaction_Prefix");

--checkOutItem settings
Settings.checkOutItem_RequestIdentifierValue_Prefix = GetSetting("checkOutItem_RequestIdentifierValue_Prefix");

function Init()	
	LogDebug("DEBUG -- In INIT");
	RegisterSystemEventHandler("LendingRequestCheckOut", "LendingCheckOutItem");
	RegisterSystemEventHandler("LendingRequestCheckIn", "LendingCheckInItem");
end

-- Method adapted from http://www.programming-idioms.org/idiom/110/check-if-string-is-blank/1667/lua
-- Linked method works opposite what i'd expect. returns true if there is anything
function hasValue(s)
	return s ~= nil and s:match("%S") ~= nil
end

--Lending Functions
function LendingCheckOutItem(transactionProcessedEventArgs)
	LogDebug("DEBUG -- LendingCheckOutItem - start");
	luanet.load_assembly("System");
	local ncipAddress = Settings.NCIP_Responder_URL;

	local currentTN = GetFieldValue("Transaction", "TransactionNumber");
	local refnumber = GetFieldValue("Transaction", "ItemInfo4");

	if not hasValue(refnumber) then
			LogDebug("No Barcode Error: ReRouting Transaction");
			ExecuteCommand("Route", {currentTN, "NCIP Error: LCheckOut-User Ineligible"});
			LogDebug("Adding Note to Transaction with NCIP Client Error");
			ExecuteCommand("AddNote", {currentTN, "No barcode added to ItemInfo4 before checkout. Not checked out in Alma."});
			LogDebug("No value in NCIP Barcode Field, NCIP not executed on CheckOut throw to Error.");
			SaveDataSource("Transaction");
		do return end
	end
	
		for barcode in refnumber:gmatch("%S+") do

			local LCOImessage = buildCheckOutItem(barcode);
			LogDebug("creating LendingCheckOutItem message[" .. LCOImessage .. "]");
			local WebClient = luanet.import_type("System.Net.WebClient");
			local myWebClient = WebClient();
			LogDebug("WebClient Created");
			LogDebug("Adding Header");
			myWebClient.Headers:Add("Content-Type", "text/xml; charset=UTF-8");
			LogDebug("Setting Upload String");
			local LCOIresponseArray = myWebClient:UploadString(ncipAddress, LCOImessage);
			LogDebug("Upload response was[" .. LCOIresponseArray .. "]");

			LogDebug("Starting error catch");		

			if string.find(LCOIresponseArray, "Apply to circulation desk - Loan cannot be renewed (no change in due date)") then
			LogDebug("NCIP Error: ReRouting Transaction");
			ExecuteCommand("Route", {currentTN, "NCIP Error: LCheckOut-No Change Due Date"});
			LogDebug("Adding Note to Transaction with NCIP Client Error");
			ExecuteCommand("AddNote", {currentTN, barcode .. " gave an NCIP error: " .. LCOIresponseArray});
			SaveDataSource("Transaction");
			do return end

			elseif string.find(LCOIresponseArray, "User Ineligible To Check Out This Item") then
			LogDebug("NCIP Error: ReRouting Transaction");
			ExecuteCommand("Route", {currentTN, "NCIP Error: LCheckOut-User Ineligible"});
			LogDebug("Adding Note to Transaction with NCIP Client Error");
			ExecuteCommand("AddNote", {currentTN, barcode .. " gave an NCIP error: " .. LCOIresponseArray});
			SaveDataSource("Transaction");
			do return end

			elseif string.find(LCOIresponseArray, "User Unknown") then
			LogDebug("NCIP Error: ReRouting Transaction");
			ExecuteCommand("Route", {currentTN, "NCIP Error: LCheckOut-User Unknown"});
			LogDebug("Adding Note to Transaction with NCIP Client Error");
			ExecuteCommand("AddNote", {currentTN, barcode .. " gave an NCIP error: " .. LCOIresponseArray});
			SaveDataSource("Transaction");
			do return end

			elseif string.find(LCOIresponseArray, "Problem") then
			LogDebug("NCIP Error: ReRouting Transaction");
			ExecuteCommand("Route", {currentTN, Settings.LendingCheckOutItemFailQueue});
			LogDebug("Adding Note to Transaction with NCIP Client Error");
			ExecuteCommand("AddNote", {currentTN, barcode .. " gave an NCIP error: " .. LCOIresponseArray});
			SaveDataSource("Transaction");
			do return end
			end

		end

	
	LogDebug("No Problems found in NCIP Response.")
	ExecuteCommand("AddNote", {currentTN, "NCIP Response for LendingCheckOutItem received successfully"});
    SaveDataSource("Transaction");	
end

function LendingCheckInItem(transactionProcessedEventArgs)
	LogDebug("LendingCheckInItem - start");
	luanet.load_assembly("System");
	local ncipAddress = Settings.NCIP_Responder_URL;
	
	LogDebug("Checking for no barcode");
	local currentTN = GetFieldValue("Transaction", "TransactionNumber");
	local refnumber = GetFieldValue("Transaction", "ItemInfo4");
	if not hasValue(refnumber) then
		ExecuteCommand("AddNote", {currentTN, "No value in NCIP Barcode Field, NCIP not executed on CheckIn."});
		LogDebug("No value in NCIP Barcode Field, NCIP not executed on CheckIn.");
		SaveDataSource("Transaction");
		do return end
	end

	for barcode in refnumber:gmatch("%S+") do

		local LCIImessage = buildCheckInItemLending(barcode);
		LogDebug("creating LendingCheckInItem message[" .. LCIImessage .. "]");
		local WebClient = luanet.import_type("System.Net.WebClient");
		local myWebClient = WebClient();
		LogDebug("WebClient Created");
		LogDebug("Adding Header");
		myWebClient.Headers:Add("Content-Type", "text/xml; charset=UTF-8");
		LogDebug("Setting Upload String");
		local LCIIresponseArray = myWebClient:UploadString(ncipAddress, LCIImessage);
		LogDebug("Upload response was[" .. LCIIresponseArray .. "]");

		LogDebug("Starting error catch")
		

		if string.find(LCIIresponseArray, "Unknown Item") then
		LogDebug("NCIP Error: ReRouting Transaction");
		ExecuteCommand("Route", {currentTN, "NCIP Error: LCheckIn-Unknown Item"});
		LogDebug("Adding Note to Transaction with NCIP Client Error");
		ExecuteCommand("AddNote", {currentTN, barcode .. " gave an NCIP error: " .. LCIIresponseArray});
		SaveDataSource("Transaction");
		do return end

		elseif string.find(LCIIresponseArray, "Item Not Checked Out") then
		LogDebug("NCIP Error: ReRouting Transaction");
		ExecuteCommand("Route", {currentTN, "NCIP Error: LCheckIn-Not Checked Out"});
		LogDebug("Adding Note to Transaction with NCIP Client Error");
		ExecuteCommand("AddNote", {currentTN, barcode .. " gave an NCIP error: " .. LCIIresponseArray});
		SaveDataSource("Transaction");
		do return end

		elseif string.find(LCIIresponseArray, "Problem") then
		LogDebug("NCIP Error: ReRouting Transaction");
		ExecuteCommand("Route", {currentTN, Settings.LendingCheckInItemFailQueue});
		LogDebug("Adding Note to Transaction with NCIP Client Error");
		ExecuteCommand("AddNote", {currentTN, barcode .. " gave an NCIP error: " .. LCIIresponseArray});
		SaveDataSource("Transaction");
		do return end
		end
	end
	
	LogDebug("No Problems found in NCIP Response.")
	ExecuteCommand("AddNote", {currentTN, "NCIP Response for LendingCheckInItem received successfully"});
    SaveDataSource("Transaction");	
end

--ReturnedItem XML Builder for Lending (Library Returns)
function buildCheckInItemLending()
local ttype = "";
local user = GetFieldValue("Transaction", "Username");
local refnumber = GetFieldValue("Transaction", "ItemInfo4");
local trantype = GetFieldValue("Transaction", "ProcessType");
	if trantype == "Borrowing" then
		ttype = Settings.checkInItem_Transaction_Prefix .. GetFieldValue("Transaction", "TransactionNumber");
	elseif trantype == "Lending" then
		ttype = GetFieldValue("Transaction", "ItemInfo4");
	else
		ttype = Settings.checkInItem_Transaction_Prefix .. GetFieldValue("Transaction", "TransactionNumber");
	end

local cil = '';
    cil = cil .. '<?xml version="1.0" encoding="ISO-8859-1"?>'
	cil = cil .. '<NCIPMessage xmlns="http://www.niso.org/2008/ncip" version="http://www.niso.org/schemas/ncip/v2_02/ncip_v2_02.xsd">'
	cil = cil .. '<CheckInItem>'
	cil = cil .. '<InitiationHeader>'
	cil = cil .. '<FromAgencyId>'
	cil = cil .. '<AgencyId>' .. Settings.acceptItem_from_uniqueAgency_value .. '</AgencyId>'
	cil = cil .. '</FromAgencyId>'
	cil = cil .. '<ToAgencyId>'
	cil = cil .. '<AgencyId>' .. Settings.acceptItem_from_uniqueAgency_value .. '</AgencyId>'
	cil = cil .. '</ToAgencyId>'
	cil = cil .. '<ApplicationProfileType>' .. Settings.ApplicationProfileType .. '</ApplicationProfileType>'
	cil = cil .. '</InitiationHeader>'
	cil = cil .. '<UserId>'
	cil = cil .. '<UserIdentifierValue>' .. user .. '</UserIdentifierValue>'
	cil = cil .. '</UserId>'
	cil = cil .. '<ItemId>'
	cil = cil .. '<AgencyId>' .. Settings.acceptItem_from_uniqueAgency_value .. '</AgencyId>'
	cil = cil .. '<ItemIdentifierValue>' .. refnumber .. '</ItemIdentifierValue>'
	cil = cil .. '</ItemId>'
	cil = cil .. '<RequestId>'
	cil = cil .. '<AgencyId>' .. Settings.acceptItem_from_uniqueAgency_value .. '</AgencyId>'
	cil = cil .. '<RequestIdentifierValue>' .. ttype .. '</RequestIdentifierValue>'
	cil = cil .. '</RequestId>'
	cil = cil .. '</CheckInItem>'
	cil = cil .. '</NCIPMessage>'
	return cil;
end

--ReturnedItem XML Builder for Lending with barcode parameter (Library Returns)
function buildCheckInItemLending(barcode)
LogDebug("In buildCheckInItemLending(barcode) " .. barcode)
local ttype = "";
local user = GetFieldValue("Transaction", "Username");
--local refnumber = GetFieldValue("Transaction", "ItemInfo4");
local trantype = GetFieldValue("Transaction", "ProcessType");
	if trantype == "Borrowing" then
		ttype = Settings.checkInItem_Transaction_Prefix .. GetFieldValue("Transaction", "TransactionNumber");
	elseif trantype == "Lending" then
		ttype = barcode
	else
		ttype = Settings.checkInItem_Transaction_Prefix .. GetFieldValue("Transaction", "TransactionNumber");
	end

local cil = '';
    cil = cil .. '<?xml version="1.0" encoding="ISO-8859-1"?>'
	cil = cil .. '<NCIPMessage xmlns="http://www.niso.org/2008/ncip" version="http://www.niso.org/schemas/ncip/v2_02/ncip_v2_02.xsd">'
	cil = cil .. '<CheckInItem>'
	cil = cil .. '<InitiationHeader>'
	cil = cil .. '<FromAgencyId>'
	cil = cil .. '<AgencyId>' .. Settings.acceptItem_from_uniqueAgency_value .. '</AgencyId>'
	cil = cil .. '</FromAgencyId>'
	cil = cil .. '<ToAgencyId>'
	cil = cil .. '<AgencyId>' .. Settings.acceptItem_from_uniqueAgency_value .. '</AgencyId>'
	cil = cil .. '</ToAgencyId>'
	cil = cil .. '<ApplicationProfileType>' .. Settings.ApplicationProfileType .. '</ApplicationProfileType>'
	cil = cil .. '</InitiationHeader>'
	cil = cil .. '<UserId>'
	cil = cil .. '<UserIdentifierValue>' .. user .. '</UserIdentifierValue>'
	cil = cil .. '</UserId>'
	cil = cil .. '<ItemId>'
	cil = cil .. '<AgencyId>' .. Settings.acceptItem_from_uniqueAgency_value .. '</AgencyId>'
	cil = cil .. '<ItemIdentifierValue>' .. barcode .. '</ItemIdentifierValue>'
	cil = cil .. '</ItemId>'
	cil = cil .. '<RequestId>'
	cil = cil .. '<AgencyId>' .. Settings.acceptItem_from_uniqueAgency_value .. '</AgencyId>'
	cil = cil .. '<RequestIdentifierValue>' .. ttype .. '</RequestIdentifierValue>'
	cil = cil .. '</RequestId>'
	cil = cil .. '</CheckInItem>'
	cil = cil .. '</NCIPMessage>'
	return cil;
end



--CheckOutItem XML Builder for Lending
function buildCheckOutItem()
local dr = tostring(GetFieldValue("Transaction", "DueDate"));
local df = string.match(dr, "%d+\/%d+\/%d+");
local mn, dy, yr = string.match(df, "(%d+)/(%d+)/(%d+)");
local mnt = string.format("%02d",mn);
local dya = string.format("%02d",dy);
local pseudopatron = 'pseudopatron';
local refnumber = GetFieldValue("Transaction", "ItemInfo4");
LogDebug("Barcode = " .. refnumber)
local tn = Settings.checkOutItem_RequestIdentifierValue_Prefix .. GetFieldValue("Transaction", "TransactionNumber");
local coi = '';
    coi = coi .. '<?xml version="1.0" encoding="ISO-8859-1"?>'
	coi = coi .. '<NCIPMessage xmlns="http://www.niso.org/2008/ncip" version="http://www.niso.org/schemas/ncip/v2_02/ncip_v2_02.xsd">'
	coi = coi .. '<CheckOutItem>'
	coi = coi .. '<InitiationHeader>'
	coi = coi .. '<FromAgencyId>'
	coi = coi .. '<AgencyId>' .. Settings.acceptItem_from_uniqueAgency_value .. '</AgencyId>'
	coi = coi .. '</FromAgencyId>'
	coi = coi .. '<ToAgencyId>'
	coi = coi .. '<AgencyId>' .. Settings.acceptItem_from_uniqueAgency_value .. '</AgencyId>'
	coi = coi .. '</ToAgencyId>'
	coi = coi .. '<ApplicationProfileType>' .. Settings.ApplicationProfileType .. '</ApplicationProfileType>'
	coi = coi .. '</InitiationHeader>'
	coi = coi .. '<UserId>'
	coi = coi .. '<UserIdentifierValue>' .. pseudopatron .. '</UserIdentifierValue>'
	coi = coi .. '</UserId>'
	coi = coi .. '<ItemId>'
	coi = coi .. '<AgencyId>' .. Settings.acceptItem_from_uniqueAgency_value .. '</AgencyId>'
	coi = coi .. '<ItemIdentifierValue>' .. refnumber .. '</ItemIdentifierValue>'
	coi = coi .. '</ItemId>'
	coi = coi .. '<RequestId>'
	coi = coi .. '<AgencyId>' .. Settings.acceptItem_from_uniqueAgency_value .. '</AgencyId>'
	coi = coi .. '<RequestIdentifierValue>' .. tn .. '</RequestIdentifierValue>'
	coi = coi .. '</RequestId>'
	coi = coi .. '<DesiredDateDue>' .. yr .. '-' .. mnt .. '-' .. dya .. 'T23:59:00' .. '</DesiredDateDue>'
	coi = coi .. '</CheckOutItem>'
	coi = coi .. '</NCIPMessage>'
	return coi;
end

--CheckOutItem XML Builder for Lending with barcode parameter
function buildCheckOutItem(barcode)
LogDebug("In buildCheckOutItem(barcode) " .. barcode);
local dr = tostring(GetFieldValue("Transaction", "DueDate"));
local df = string.match(dr, "%d+\/%d+\/%d+");
local mn, dy, yr = string.match(df, "(%d+)/(%d+)/(%d+)");
local mnt = string.format("%02d",mn);
local dya = string.format("%02d",dy);
local pseudopatron = 'pseudopatron';
--local refnumber = GetFieldValue("Transaction", "ItemInfo4");
LogDebug("Barcode = " .. barcode)
local tn = Settings.checkOutItem_RequestIdentifierValue_Prefix .. GetFieldValue("Transaction", "TransactionNumber");
local coi = '';
    coi = coi .. '<?xml version="1.0" encoding="ISO-8859-1"?>'
	coi = coi .. '<NCIPMessage xmlns="http://www.niso.org/2008/ncip" version="http://www.niso.org/schemas/ncip/v2_02/ncip_v2_02.xsd">'
	coi = coi .. '<CheckOutItem>'
	coi = coi .. '<InitiationHeader>'
	coi = coi .. '<FromAgencyId>'
	coi = coi .. '<AgencyId>' .. Settings.acceptItem_from_uniqueAgency_value .. '</AgencyId>'
	coi = coi .. '</FromAgencyId>'
	coi = coi .. '<ToAgencyId>'
	coi = coi .. '<AgencyId>' .. Settings.acceptItem_from_uniqueAgency_value .. '</AgencyId>'
	coi = coi .. '</ToAgencyId>'
	coi = coi .. '<ApplicationProfileType>' .. Settings.ApplicationProfileType .. '</ApplicationProfileType>'
	coi = coi .. '</InitiationHeader>'
	coi = coi .. '<UserId>'
	coi = coi .. '<UserIdentifierValue>' .. pseudopatron .. '</UserIdentifierValue>'
	coi = coi .. '</UserId>'
	coi = coi .. '<ItemId>'
	coi = coi .. '<AgencyId>' .. Settings.acceptItem_from_uniqueAgency_value .. '</AgencyId>'
	coi = coi .. '<ItemIdentifierValue>' .. barcode .. '</ItemIdentifierValue>'
	coi = coi .. '</ItemId>'
	coi = coi .. '<RequestId>'
	coi = coi .. '<AgencyId>' .. Settings.acceptItem_from_uniqueAgency_value .. '</AgencyId>'
	coi = coi .. '<RequestIdentifierValue>' .. tn .. '</RequestIdentifierValue>'
	coi = coi .. '</RequestId>'
	coi = coi .. '<DesiredDateDue>' .. yr .. '-' .. mnt .. '-' .. dya .. 'T23:59:00' .. '</DesiredDateDue>'
	coi = coi .. '</CheckOutItem>'
	coi = coi .. '</NCIPMessage>'
	return coi;
end

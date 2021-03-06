------------------------------------------------------------------------------
--                                                                          --
--                                 GUV                                      --
--                                                                          --
--                                                                          --
--         Copyright (C) 2017 - 2021 Mario Blunk, Blunk electronic          --
--                                                                          --
--    This program is free software: you can redistribute it and/or modify  --
--    it under the terms of the GNU General Public License as published by  --
--    the Free Software Foundation, either version 3 of the License, or     --
--    (at your option) any later version.                                   --
--                                                                          --
--    This program is distributed in the hope that it will be useful,       --
--    but WITHOUT ANY WARRANTY; without even the implied warranty of        --
--    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         --
--    GNU General Public License for more details.                          --
--                                                                          --
--    You should have received a copy of the GNU General Public License     --
--    along with this program.  If not, see <http://www.gnu.org/licenses/>. --
------------------------------------------------------------------------------

--   Please send your questions and comments to:
--
--   info@blunk-electronic.de
--   or visit <http://www.blunk-electronic.de> for more contact data
--
--   history of changes:
--	 - report generation can be provided with the quarter number
--	 - help function improved via help file in directory .guv/
-- 	 to do:
-- 	 sort takings and expenses
--	 check takings and expenses file


with ada.text_io;				use ada.text_io;
with ada.characters.handling;	use ada.characters.handling;
with ada.strings.maps;	 		use ada.strings.maps;

with ada.strings.unbounded; 	use ada.strings.unbounded;
with ada.strings.bounded; 		use ada.strings.bounded;
with ada.strings.fixed; 		use ada.strings.fixed;
with ada.strings; 				use ada.strings;

with ada.strings.unbounded.text_io;	use ada.strings.unbounded.text_io;

with ada.exceptions; 				use ada.exceptions;
 
with gnat.os_lib;   			use gnat.os_lib;
with ada.command_line;			use ada.command_line;
with ada.directories;			use ada.directories;
 
with ada.calendar;				use ada.calendar;
with ada.calendar.formatting;	use ada.calendar.formatting;
with ada.calendar.time_zones;	use ada.calendar.time_zones;

with ada.containers.generic_array_sort;
with ada.containers.generic_constrained_array_sort;

with ada.environment_variables; --use ada.environment_variables;

with guv_string_processing;		use guv_string_processing;
with guv_csv;					use guv_csv;

procedure guv is

	version			: constant string (1..3) := "012";

	now				: time;

	arg_scratch		: unbounded_string;
	arg_ct			: natural := 0;
	arg_pt			: natural := 0;

	result			: natural;

	take_action		: boolean := false;
	expense_action	: boolean := false;
	create_action 	: boolean := false;
	report_action	: boolean := false;

	file_name_length	: constant natural := 40; -- CS: consider in length of bakup file names
	package file_name_type is new generic_bounded_length(file_name_length); use file_name_type;

	tax_id_given	: string (1..13) := "xxx/yyy/zzzzz";
	vat_id_given	: string (1..11) := "xx000000000";

	takings_csv		: file_name_type.bounded_string := to_bounded_string("einnahmen.csv");
	expenses_csv	: file_name_type.bounded_string := to_bounded_string("ausgaben.csv");
	report_csv		: file_name_type.bounded_string;

	takings_file	: ada.text_io.file_type;
	expenses_file	: ada.text_io.file_type;
	report_file		: ada.text_io.file_type;

	prog_position	: string (1..4) := "----";

	line			: unbounded_string;
	ifs				: constant character := ';';	-- default csv file separator is semicolon
	
	entries_ct_takings	: natural := 0;
	entries_ct_expenses	: natural := 0;

	type money is delta 0.01 digits 14;
	--type money is delta 0.001 digits 14;
	type money_positive is new money range 0.00 .. money'last;

	
	subtype vat_key_type is natural range 0..2;
	
	vat_1				: constant money_positive := 0.19;
	--vat_1				: constant money_positive := 0.16;
	
	vat_2				: constant money_positive := 0.07;
	--vat_2				: constant money_positive := 0.05;
	
	vat_calculated		: money_positive;

	yes_no_type 				: constant character_set := to_set("jn");
	number_type 				: constant character_set := to_set("0123456789");
	report_rv_figures			: boolean := false; -- by default rv is suppressed in report.
	rv_pflichtig_yes_no_given	: character := 'n';
	rv_anteilig_yes_no_given	: character := 'n';
	rv_vollst_yes_no_given		: character := 'n';

	keyboard_key				: character := 'n';

	amount_given		: money_positive := 0.00;
	date_given			: string (1..10) := "JJJJ-MM-TT";
	date_given_ok 		: boolean := false;

	fiscal_year_given	: string (1..4) := "JJJJ";

	subtype quarter_type is natural range 0..4;
	quarter_given		: quarter_type := 0;

	subtype month_type is natural range 0..12;
	month_given			: month_type := 0;

	home_length			: natural := 6+32+1; -- /home/ + 32 + /, according to man page useradd command
	name_length			: natural := 20;
	customer_length		: natural := 30;
	subject_length		: natural := 40;
	remark_length		: natural := 50;
	package home_type 			is new generic_bounded_length(home_length); use home_type;
	package name_type 			is new generic_bounded_length(name_length); use name_type;
	package customer_type 		is new generic_bounded_length(customer_length); use customer_type;
	package subject_type 		is new generic_bounded_length(subject_length); use subject_type;
	package remarks_type 		is new generic_bounded_length(remark_length); use remarks_type;

	home_directory			: home_type.bounded_string;
	conf_directory			: constant string (1..5) := ".guv/";
	conf_file_name			: constant string (1..8) := "guv.conf";
	help_file_name_german	: constant string (1..15) := "help_german.txt";

	name_given			: name_type.bounded_string;
	name_given_ok		: boolean := false;
	receipient_given	: customer_type.bounded_string;
	receipient_given_ok	: boolean := false;
	customer_given		: customer_type.bounded_string;
	customer_given_ok	: boolean := false;
	subject_given	: subject_type.bounded_string;
	subject_given_ok	: boolean := false;
	remark_given		: remarks_type.bounded_string := to_bounded_string("keine");

	vat_key_given		: vat_key_type := 1;

	type entry_taking is -- fields separated by ";" , text delimited by "
		record
			amount			: money_positive := 0.00;
			date			: string (1..10) := "JJJJ-MM-TT";
			customer		: customer_type.bounded_string;
			subject			: subject_type.bounded_string;
			vat_key			: vat_key_type := 1;
			vat				: money_positive := 0.00;
			rv_pflichtig	: string (1..1) := "n";
			rv       		: money_positive := 0.00;
			remarks			: remarks_type.bounded_string;
			processed		: boolean := false;
		end record;
	type takings is array (natural range <>) of entry_taking;

	type entry_expense is -- fields separated by ";" , text delimited by "
		record
			amount			: money_positive := 0.00;
			date			: string (1..10) := "JJJJ-MM-TT";
			receipient		: customer_type.bounded_string;
			subject			: subject_type.bounded_string;
			vat_key			: vat_key_type := 1;
			vat				: money_positive := 0.00;
			rv_anteilig		: string (1..1) := "n";
			rv_vollst  		: string (1..1) := "n";
			rv				: money_positive := 0.00;
			remarks			: remarks_type.bounded_string;
			processed		: boolean := false;
		end record;
	type expenses is array (natural range <>) of entry_expense;


---------------------------------------------

	function check_space_semicolon	-- returns given string unchanged if ok, raises constraint_error on occurence of space or semicolon
		( test_string	: string) 
		return string is
		begin
			--prog_position := "SPSE";
			if Ada.Strings.Fixed.count(test_string," ") > 0 then
				put_line("FEHLER : Leerzeichen sind nicht erlaubt !");
				raise constraint_error;
				return "---"; -- not really important
			end if;

			if Ada.Strings.Fixed.count(test_string,";") > 0 then
				put_line("FEHLER : Semikolons (;) sind nicht erlaubt !");
				raise constraint_error;
				return "---"; -- not really important
			end if;
			return test_string;
		end check_space_semicolon;

	function check_semicolon	-- returns given string unchanged if ok, raises constraint_error on occurence of semicolon
		( test_string	: string) 
		return string is
		begin
			--prog_position := "SEMI";

			if Ada.Strings.Fixed.count(test_string,";") > 0 then
				put_line("FEHLER : Semikolons (;) sind nicht erlaubt !");
				raise constraint_error;
				return "---"; -- not really important
			end if;
			return test_string;
		end check_semicolon;

	function check_date	-- returns given string unchanged if ok, raises constraint_error on occurence of space or semicolon
		( date_test	: string) 
		return string is
		scratch	: string (1..date_given'length);
	begin
		prog_position := "CHDT";
		--scratch := tax_id_test;

		scratch := check_space_semicolon(date_test);
		--put_line(scratch);

		for i in 1..date_given'length
		loop
			case i is
				when 1 => 
					if scratch(i) /= '2' then
						put_line("FEHLER : Ungültiges Format für Datum. Beispiel: 2014-21-12 (JJJJ-MM-TT) ");
						raise constraint_error;
					end if;

				when 2 => 
					if scratch(i) /= '0' then
						put_line("FEHLER : Ungültiges Format für Datum. Beispiel: 2014-21-12 (JJJJ-MM-TT) ");
						raise constraint_error;
					end if;

				when 3|4| 6|7| 9|10 => 
					if not is_in(scratch(i),number_type) then
						put_line("FEHLER : Ungültiges Format für Datum. Beispiel: 2014-21-12 (JJJJ-MM-TT) ");
						raise constraint_error;
					end if;
				when others =>
					if scratch(i) /= '-' then
						put_line("FEHLER : Ungültiges Format für Datum. Beispiel: 2014-21-12 (JJJJ-MM-TT) ");
						raise constraint_error;
					end if;
			end case;
		end loop;
		return scratch;
	end check_date;


	function check_year	-- returns given string unchanged if ok, raises constraint_error on occurence of space or semicolon
		( date_test	: string) 
		return string is
		scratch	: string (1..4);
	begin
		--prog_position := "CHYT";
		--scratch := tax_id_test;

		scratch := check_space_semicolon(date_test);
		--put_line(scratch);

		for i in 1..4
		loop
			case i is
				when 1 => 
					if scratch(i) /= '2' then
						put_line("FEHLER : Ungültiges Format für Wirtschaftsjahr. Beispiel: 2014 (JJJJ) ");
						raise constraint_error;
					end if;

				when 2 => 
					if scratch(i) /= '0' then
						put_line("FEHLER : Ungültiges Format für Wirtschaftsjahr. Beispiel: 2014 (JJJJ) ");
						raise constraint_error;
					end if;

				when 3|4 => 
					if not is_in(scratch(i),number_type) then
						put_line("FEHLER : Ungültiges Format für Wirtschaftsjahr. Beispiel: 2014 (JJJJ) ");
						raise constraint_error;
					end if;
			end case;
		end loop;
		return scratch;
	end check_year;



	function check_tax_id	-- returns given string unchanged if ok, raises constraint_error on occurence of space or semicolon
		( tax_id_test	: string) 
		return string is
		scratch	: string (1..tax_id_given'length);
		begin
			--prog_position := "CHTX";
			scratch := check_space_semicolon(tax_id_test);
			for i in 1..tax_id_given'length
			loop
				case i is
					when 1|2|3| 5|6|7| 9|10|11|12|13 => 
						if not is_in(scratch(i),number_type) then
							put_line("FEHLER : Ungültiges Format für Steuernummer. Beispiel: 123/456/78901 ");
							raise constraint_error;
						end if;
					when others =>
						if scratch(i) /= '/' then
							put_line("FEHLER : Ungültiges Format für Steuernummer. Beispiel: 123/456/78901 ");
							raise constraint_error;
						end if;
				end case;
			end loop;
			return scratch;
		end check_tax_id;


	function check_vat_id	-- returns given string unchanged if ok, raises constraint_error on occurence of space or semicolon
		( vat_id_test	: string) 
		return string is
		scratch	: string (1..vat_id_given'length);
		begin
			--prog_position := "VTTX";
			scratch := check_space_semicolon(vat_id_test);
			for i in 1..vat_id_given'length
			loop
				case i is
					when 1..2 => 
						if not is_upper(scratch(i)) then
							put_line("FEHLER : Ungültiges Format für USt-IdNr. Beispiel: DE123456789");
							raise constraint_error;
						end if;
					when 3..11 => 
						if not is_in(scratch(i),number_type) then
							put_line("FEHLER : Ungültiges Format für USt-IdNr. Beispiel: DE123456789");
							raise constraint_error;
						end if;
					when others =>
						if scratch(i) /= '/' then
							put_line("FEHLER : Ungültiges Format für USt-IdNr. Beispiel: DE123456789");
							raise constraint_error;
						end if;
				end case;
			end loop;
			return scratch;
		end check_vat_id;


	function replace_dot_by_comma
		-- for german finacial calculations only:
		-- replaces dot by comma in money numbers such as 7.89 and renders them to 7,89 
		(
		text : string
		) return string
		is
		package money_type is new generic_bounded_length(14); use money_type;
		money	: money_type.bounded_string;

		text_length			: natural;
		comma_position		: natural := 0;
		begin
			text_length := text'length;
			comma_position := text_length -2;
			money := to_bounded_string
				(replace_slice
					(
					text,
					comma_position,
					comma_position,
					","
					)
				);

			-- insert thousands separator

			-- for positive numbers incl. zero without heading minus sign
			if text(text'first) /= '-' then

				-- insert dots for numbers greater 999.99, 999999.99
				if text_length >= 7 then insert(money,text_length-5,"."); end if; -- for numbers greater 999,99 EUR
				if text_length >= 10 then insert(money,text_length-8,"."); end if; -- for numbers greater 999.999.999,99 EUR

			else -- it is a negative number

				-- insert dots for numbers less than -999.99 , -999999.99
				if text_length >= 8 then insert(money,text_length-5,"."); end if; -- for numbers greater 999,99 EUR
				if text_length >= 11 then insert(money,text_length-8,"."); end if; -- for numbers greater 999.999.999,99 EUR

			end if;

			return to_string(money);
	end replace_dot_by_comma;


	function make_filename_by_date
		(
		file_name	: string
		) return string is
		now		: time := clock;
		package file_date_type is new generic_bounded_length(24); use file_date_type; -- BAK_YYYY-MM-DD_HH-MM-SS_
		file_date	: file_date_type.bounded_string;
		package scratch_type is new generic_bounded_length(40); use scratch_type; -- max length of the name of the bakup file is 40 characters
		scratch		: scratch_type.bounded_string;
		begin
			prog_position := "MKFD";
			scratch := to_bounded_string( image(now, time_zone => UTC_Time_Offset(now) ) );
			replace_element(scratch,11,'_');
			replace_element(scratch,14,'-');
			replace_element(scratch,17,'-');
			scratch := "BAK_" & scratch & "__" & file_name;
			return to_string(scratch);
		end make_filename_by_date;



	function count_bookings
		return natural is
		ct 							: natural := 0;
		line						: unbounded_string;
		scratch						: unbounded_string;
		bookings_section_entered 	: boolean := false;
	begin
		prog_position := "CTBK";
		while not End_Of_File
			loop
				line:=get_line;
					if bookings_section_entered then
						ct := ct + 1; -- count bookings
					end if;

					if guv_csv.get_field(line,1) = "BUCHUNG_NR." then -- set bookings_section_entered flag upon passing the "DATUM" field
						bookings_section_entered := true;
					end if;
			end loop;
		return ct; -- return total number of bookings
	end count_bookings;



	procedure create is
	begin
		prog_position := "CR01";
		if to_string(name_given)'length = 0 then
			put_line("FEHLER : Bitte Name des anzulegenden Mandanten mit Option '-man' spezifizieren !");
			put_line("         Beispiel: guv -neu -man firma_xyz");
			raise constraint_error;
		end if;

		prog_position := "CR02";
		if tax_id_given = "xxx/yyy/zzzzz" then
			put_line("FEHLER : Bitte Steuernummer des anzulegenden Mandanten mit Option '-stnr' spezifizieren !");
			put_line("         Beispiel: guv -neu -man firma_xyz -stnr 123/456/78901");
			raise constraint_error;
		end if;

		prog_position := "CR03";
		if vat_id_given = "xx000000000" then
			put_line("FEHLER : Bitte USt.-IdNr. des anzulegenden Mandanten mit Option '-ui' spezifizieren !");
			put_line("         Beispiel: guv -neu -man firma_xyz -stnr 123/456/78901 -ui DE123456789");
			raise constraint_error;
		end if;

		prog_position := "CR04";
		if fiscal_year_given = "JJJJ" then
			put_line("FEHLER : Bitte Wirtschaftsjahr mit Option '-wj' spezifizieren !");
			put_line("         Beispiel: guv -neu -man firma_xyz -stnr 123/456/78901 -ui DE123456789 -wj 2014");
			raise constraint_error;
		end if;

		new_line;
		put_line("NEUEN MANDANTEN ANLEGEN");
		put_line("-------------------------------------------------------------------");	

		-- recreate an empty bak directory
		prog_position := "CRBK";
		if exists ("bak") then 
			put_line("WARNUNG ! Backup-Verzeichnis 'bak' existiert bereits.");
			     put("          Löschen und neu anlegen ? (j/n) "); Get(keyboard_key); new_line;
			if to_lower(keyboard_key) = 'j' then 
				prog_position := "CBK1";
				Delete_Tree("bak"); 
			else
				prog_position := "NCBK";
				raise constraint_error;
			end if;
		end if;
		Create_Directory("bak");
		Create_Directory("bak/in");
		Create_Directory("bak/out");
		Create_Directory("bak/reports");

		put_line("Name / Firma           : " & to_string(name_given));
		put_line("Steuernummer           : " & tax_id_given);
		put_line("USt.IdNr.              : " & vat_id_given);
		put_line("Wirtschaftsjahr        : " & fiscal_year_given);
		put_line("Datei Einnahmen        : " & to_string(takings_csv));
		put_line("Datei Ausgaben         : " & to_string(expenses_csv));


		prog_position := "CR10";
			new_line;
			put("ANGABEN KORREKT ? (j/n) "); Get(keyboard_key); new_line;
				if to_lower(keyboard_key) = 'j' then
					null;
				else
					prog_position := "NMAN";
					raise constraint_error;
				end if;

			prog_position := "CRTK";
			if exists (to_string(takings_csv)) then 
				put("WARNUNG ! Einnahmen-Datei '" & to_string(takings_csv) & "' existiert bereits. Überschreiben ? (j/n) "); Get(keyboard_key); new_line;
				if to_lower(keyboard_key) = 'j' then
					Create( takings_file, Name => to_string(takings_csv)); Close(takings_file);
				else
					prog_position := "NCRT";
					raise constraint_error;
				end if;
			end if;
			Create( takings_file, Name => to_string(takings_csv)); Close(takings_file);

			if exists (to_string(expenses_csv)) then 
				put("WARNUNG ! Ausgaben-Datei '" & to_string(expenses_csv) & "' existiert bereits. Überschreiben ? (j/n) "); Get(keyboard_key); new_line;
				if to_lower(keyboard_key) = 'j' then
					Create( expenses_file, Name => to_string(expenses_csv)); Close(expenses_file);
				else
					prog_position := "NCRE";
					raise constraint_error;
				end if;
			end if;
			Create( expenses_file, Name => to_string(expenses_csv)); Close(expenses_file);



			prog_position := "WRTH";
			Open( 
				File => takings_file,
				Mode => out_file,
				Name => to_string(takings_csv)
				);

			put_line(takings_file, ascii.quotation & "EINNAHMEN" & ascii.quotation);
			put_line(takings_file, ascii.quotation & "FIRMA :" & ascii.quotation & ifs & ascii.quotation & to_string(name_given) & ascii.quotation);
			put_line(takings_file, ascii.quotation & "STEUERNUMMER :" & ascii.quotation & ifs & ascii.quotation & tax_id_given & ascii.quotation);
			put_field(takings_file,"USt.-IdNr :"); put_field(takings_file,vat_id_given); 
			put_lf(takings_file);
			put_field(takings_file,"WIRTSCHAFTSJAHR :"); put_field(takings_file,fiscal_year_given); put_lf(takings_file);
			put_line(takings_file,
					  ascii.quotation & "BUCHUNG_NR." & ascii.quotation &
				ifs & ascii.quotation & "DATUM" & ascii.quotation &
				ifs & ascii.quotation & "BETRAG" & ascii.quotation &
				ifs & ascii.quotation & "ST_SCHL." & ascii.quotation &
				ifs & ascii.quotation & "MWST" & ascii.quotation &
				ifs & ascii.quotation & "KUNDE" & ascii.quotation &
				ifs & ascii.quotation & "BETREFF" & ascii.quotation &
				ifs & ascii.quotation & "RV_PFLICHTIG" & ascii.quotation &
				ifs & ascii.quotation & "BEMERKUNG" & ascii.quotation
				);
			close(takings_file);


		prog_position := "CREX";

			Open( 
				File => expenses_file,
				Mode => out_file,
				Name => to_string(expenses_csv)
				);

			put_line(expenses_file, ascii.quotation & "AUSGABEN" & ascii.quotation);
			put_line(expenses_file, ascii.quotation & "FIRMA :" & ascii.quotation & ifs & ascii.quotation & to_string(name_given) & ascii.quotation);
			put_line(expenses_file, ascii.quotation & "STEUERNUMMER :" & ascii.quotation & ifs & ascii.quotation & tax_id_given & ascii.quotation);
			put_field(expenses_file,"USt.-IdNr :"); put_field(expenses_file,vat_id_given);
			put_lf(expenses_file);
			put_field(expenses_file,"WIRTSCHAFTSJAHR :"); put_field(expenses_file,fiscal_year_given); put_lf(expenses_file);

			put_line(expenses_file,
					ascii.quotation & "BUCHUNG_NR." & ascii.quotation &
				ifs & ascii.quotation & "DATUM" & ascii.quotation &
				ifs & ascii.quotation & "BETRAG" & ascii.quotation &
				ifs & ascii.quotation & "ST_SCHL" & ascii.quotation &
				ifs & ascii.quotation & "MWST" & ascii.quotation &
				ifs & ascii.quotation & "EMPFÄNGER" & ascii.quotation &
				ifs & ascii.quotation & "BETREFF" & ascii.quotation &
				ifs & ascii.quotation & "RV_ANTEILIG" & ascii.quotation &
				ifs & ascii.quotation & "RV_VOLLST." & ascii.quotation &
				ifs & ascii.quotation & "BEMERKUNG" & ascii.quotation
				);
			close(expenses_file);
	end create;




	procedure take_expense_action is
		bookings_ct	: natural := 0;

	begin
		prog_position := "DA10";
		if date_given_ok = false then
			put_line("WARNUNG ! Kein Datum angegeben ! (evtl. Option '-datum' vergessen ?)");
			put     ("          Buchung fortsetzen ? (j/n) "); Get(keyboard_key); new_line;
			if to_lower(keyboard_key) = 'j' then null; 
			else 
				prog_position := "DA11";
				raise constraint_error;
			end if;
		end if; 

		prog_position := "AMT1";
		if amount_given = 0.00 then
			put_line("WARNUNG ! Eingebener Betrag ist NULL ! (evtl. Option '-betrag' vergessen ?)");
			put     ("          Buchung fortsetzen ? (j/n) "); Get(keyboard_key); new_line;
			if to_lower(keyboard_key) = 'j' then null; 
			else 
				prog_position := "AMT2";
				raise constraint_error;
			end if;
		end if;

		if take_action and expense_action then
			prog_position := "TAEX";
			put_line("FEHLER : Einnahmen und Ausgaben können nicht gleichzeitig gebucht werden !");
			raise constraint_error;
		end if;

		if not take_action and not expense_action then
			prog_position := "NOAC";
			put_line("FEHLER : Bitte Buchung von Einnahmen / Ausgaben mit Option '-ein' / '-aus' spezifizieren !");
			raise constraint_error;
		end if;

		-- display parameters specified for user confirmation
		prog_position := "CHTF";
		if take_action then 
			if not exists (to_string(takings_csv)) then 
				put_line("FEHLER : Einnahmen-Datei " & to_string(takings_csv) & " existiert nicht ! (evtl. Option '-ed datei.csv' vergessen ?)");
				raise constraint_error;
			end if;
			put_line("Einnahmen Datei     : " & to_string(takings_csv));
		end if;

		prog_position := "CHEF";
		if expense_action then 
			if not exists (to_string(expenses_csv)) then 
				put_line("FEHLER : Ausgaben-Datei " & to_string(expenses_csv) & " existiert nicht ! (evtl. Option '-ad datei.csv' vergessen ?)");
				raise constraint_error;
			end if;
			put_line("Ausgaben Datei      : " & to_string(expenses_csv));
		end if;

		put_line("Datum der Zahlung   : " & date_given);

		put_line("Betrag Netto        : " & trim(money_positive'image(amount_given),left));

		prog_position := "VK10";
		put_line("MwSt. Schlüssel     : " & trim(natural'image(vat_key_given),left));
			case vat_key_given is
				when 1 =>
					vat_calculated := money_positive'round(amount_given * vat_1);
					put_line("zzgl. MwSt.         : " & trim(money_positive'image(vat_calculated),left) &
							" (" & trim(money_positive'image(vat_1*100),left) &
							"% auf " & trim(money_positive'image( amount_given ),left) &
							" -> Brutto : " & trim(money_positive'image( amount_given + vat_calculated),left) & ")"
							);

				when 2 =>
					vat_calculated := money_positive'round(amount_given * vat_2);
					put_line("zzgl. MwSt.         : " & trim(money_positive'image(vat_calculated),left) &
							" (" & trim(money_positive'image(vat_2*100),left) &
							"% auf " & trim(money_positive'image( amount_given ),left) & 
							" -> Brutto : " & trim(money_positive'image( amount_given + vat_calculated),left) & ")"
							);
				when 0 =>
					vat_calculated := 0.00;
					put_line("zzgl. MwSt.         : " & trim(money_positive'image(vat_calculated),left) &
					(" (steuerfrei)"));

				when others => raise constraint_error;
			end case;

		if take_action then 
			prog_position := "CU01";
			if customer_given_ok = false then
				new_line;
				put_line("FEHLER ! Name des Kunden fehlt ! (evtl. Option '-kunde' vergessen ?)");
				raise constraint_error;
			end if;
			put_line("Kunde               : " & to_string(customer_given)); 
		end if;

		if expense_action then
			prog_position := "RC01";
			if receipient_given_ok = false then
				new_line;
				put_line("FEHLER ! Empfänger fehlt ! (evtl. Option '-empfaenger' vergessen ?)");
				raise constraint_error;
			end if;
			put_line("Empfänger           : " & to_string(receipient_given)); 
		end if;

		prog_position := "SU01";
		if subject_given_ok = false then
			new_line;
			put_line("FEHLER ! Betreff fehlt ! (evtl. Option '-betreff' vergessen ?)");
			raise constraint_error;
		end if;
		put_line("Betreff             : " & to_string(subject_given));

		if take_action then put_line("RV pflichtig        : " & rv_pflichtig_yes_no_given); end if;
		if expense_action then 
			if rv_anteilig_yes_no_given = 'j' and rv_vollst_yes_no_given = 'j' then
				prog_position := "RVTV";
				put_line("FEHLER : Ausgabe kann nicht RV_vollstaending und RV_anteilig gleichzeitig sein !");
				raise constraint_error;
			end if;
			if rv_anteilig_yes_no_given = 'j' then
				put_line("RV anteilig         : " & rv_anteilig_yes_no_given);
			end if;
			if rv_vollst_yes_no_given = 'j' then
				put_line("RV vollst.          : " & rv_vollst_yes_no_given);
			end if;
		end if;

		put_line("Bemerkungen         : " & to_string(remark_given));


		-- request user confirmation
		new_line;
		put("BUCHUNG DURCHFUEHREN ? (j/n) "); get(keyboard_key);
		if to_lower(keyboard_key) = 'j' then null;
		else
			prog_position := "NBKG";
			raise constraint_error;
		end if;


		if take_action then
			prog_position := "TAKF";

			-- make backup of takings_file in directory bak/in
			copy_file( to_string(takings_csv), "bak/in/" & make_filename_by_date(to_string(takings_csv)) );

			-- count number of bookings
			prog_position := "TKF1";
			Open( 
				File => takings_file,
				Mode => in_File,
				Name => to_string(takings_csv)
				);
			set_input(takings_file);
			bookings_ct := count_bookings + 1;
			close(takings_file);

			Open( 
				File => takings_file,
				Mode => append_File,
				Name => to_string(takings_csv)
				);

			put_line(takings_file,
						  ascii.quotation & trim(natural'image(bookings_ct),left) & ascii.quotation &
					ifs & ascii.quotation & date_given & ascii.quotation &
					ifs & ascii.quotation & trim(money_positive'image(amount_given),left) & ascii.quotation &
					ifs & ascii.quotation & trim(natural'image(vat_key_given),left) & ascii.quotation &
					ifs & ascii.quotation & trim(money_positive'image(vat_calculated),left) & ascii.quotation &
					ifs & ascii.quotation & to_string(customer_given) & ascii.quotation &
					ifs & ascii.quotation & to_string(subject_given) & ascii.quotation &
					ifs & ascii.quotation & rv_pflichtig_yes_no_given & ascii.quotation &
					ifs & ascii.quotation & to_string(remark_given) & ascii.quotation
					);
			close(takings_file);

			-- CS: sort takings
		end if;


		if expense_action then
			prog_position := "EXPF";

			-- make backup of takings_file in directory bak/out
			copy_file( to_string(expenses_csv), "bak/out/" & make_filename_by_date(to_string(expenses_csv)) );

			-- count number of bookings
			Open( 
				File => expenses_file,
				Mode => in_File,
				Name => to_string(expenses_csv)
				);
			set_input(expenses_file);
			bookings_ct := count_bookings + 1;
			close(expenses_file);

			Open( 
				File => expenses_file,
				Mode => append_File,
				Name => to_string(expenses_csv)
				);

			put_line(expenses_file,
						ascii.quotation & trim(natural'image(bookings_ct),left) & ascii.quotation &
					ifs & ascii.quotation & date_given & ascii.quotation &
					ifs & ascii.quotation & trim(money_positive'image(amount_given),left) & ascii.quotation &
					ifs & ascii.quotation & trim(natural'image(vat_key_given),left) & ascii.quotation &
					ifs & ascii.quotation & trim(money_positive'image(vat_calculated),left) & ascii.quotation &
					ifs & ascii.quotation & to_string(receipient_given) & ascii.quotation &
					ifs & ascii.quotation & to_string(subject_given) & ascii.quotation &
					ifs & ascii.quotation & rv_anteilig_yes_no_given & ascii.quotation &
					ifs & ascii.quotation & rv_vollst_yes_no_given & ascii.quotation &
					ifs & ascii.quotation & to_string(remark_given) & ascii.quotation
					);
			close(expenses_file);

			-- CS: sort expenses
		end if;

	end take_expense_action;


	procedure report is
		bookings_ct			: natural := 0;
		takings_total		: money_positive := 0.00;
		takings_vat_1		: money_positive := 0.00;
		takings_vat_2		: money_positive := 0.00;
		takings_rv			: money_positive := 0.00;

		--ratio_rv_turnover	: money_positive := 0.00;
		type ratio is delta 0.0001 digits 5;
		ratio_rv_turnover	: ratio := 0.0000; -- defaults to 0, mod v008

		expenses_total		: money_positive := 0.00;
		expenses_vat		: money_positive := 0.00;
		expenses_rv 		: money_positive := 0.00;

		yield				: money := 0.00;
		yield_rv			: money := 0.00;
		vat_excess			: money := 0.00;

		--date_given			: string (1..10) := "JJJJ-MM-TT";
		date_of_booking		: string (1..10) := "JJJJ-MM-TT";
		natural_date		: natural := 0;
		earliest_date		: natural;
		latest_date			: natural;

		function date_in_range
			(
			date	: natural
			)
			return boolean is
			begin
				if date < earliest_date then return false;
				elsif date > latest_date then return false;
				end if;
				return true;
			end date_in_range;

		procedure read_takings is
			subtype takings_sized_type is takings (1..bookings_ct);
			takings_sized				: takings_sized_type;
			bookings_section_entered	: boolean := false;
			booking_pt					: natural := 0;


			procedure sort_takings
				is
				subtype bookings_index_type is natural range 1 .. bookings_ct; 
				--type takings_test is array(bookings_index_type) of entry_taking;
				subtype takings_type is takings (bookings_index_type);  

				function "<" (L, R : entry_taking) return Boolean is
				begin
					return L.date < R.date;
				end "<";
 				
-- for debug only
-- 				procedure put_booking (C : entry_taking) is
-- 				begin
-- 					Put_Line (C.date & " " & to_string(C.subject));
-- 					null;
-- 				end put_booking;
		
 				procedure Sort is new Ada.Containers.Generic_Constrained_Array_Sort (
  					array_type => takings_type,
 					element_type => entry_taking, 
  					index_type => bookings_index_type
  					);

				scratch : takings_type := takings_sized; --(array_to_sort);
	
			begin
				Sort (scratch);
-- for debug only
--  	 			for i in 1..takings_sized'last loop
--  	 				put_line(standard_output,scratch(i).date);
--  	 			end loop;
				takings_sized := scratch;
			end sort_takings;



		begin
			prog_position := "RTA1";
			while not End_Of_File -- read takings_csv file
			loop
				line:=get_line;
					if bookings_section_entered then
					--if bookings_section_entered and guv_csv.get_field_count(line) > 0 then
						prog_position := "RT09";
						booking_pt := booking_pt + 1;
						--put_line(natural'image(booking_pt));
						--put_line(line);

 						takings_sized(booking_pt).date   			:= guv_csv.get_field(line,2);
 						takings_sized(booking_pt).amount 			:= money_positive'value(guv_csv.get_field(line,3));
 						takings_sized(booking_pt).vat_key			:= natural'value(guv_csv.get_field(line,4));
 						takings_sized(booking_pt).vat				:= money_positive'value(guv_csv.get_field(line,5));
 						takings_sized(booking_pt).customer			:= to_bounded_string(guv_csv.get_field(line,6));
 						takings_sized(booking_pt).subject			:= to_bounded_string(guv_csv.get_field(line,7));
 						takings_sized(booking_pt).rv_pflichtig		:= guv_csv.get_field(line,8);
 						takings_sized(booking_pt).remarks			:= to_bounded_string(guv_csv.get_field(line,9));

					else -- bookings_section not entered yet 
						if guv_csv.get_field(line,1) = "FIRMA :" then
							prog_position := "RTA2";
							name_given := to_bounded_string(guv_csv.get_field(line,2));
							--put_line("test");
						end if;

						if guv_csv.get_field(line,1) = "STEUERNUMMER :" then
							prog_position := "RTA3";
							tax_id_given := guv_csv.get_field(line,2);
							--put_line("test");
						end if;

						if guv_csv.get_field(line,1) = "USt.-IdNr :" then
							prog_position := "RTA9";
							vat_id_given := guv_csv.get_field(line,2);
							--put_line("test");
						end if;

						if guv_csv.get_field(line,1) = "BUCHUNG_NR." then -- set bookings_section_entered flag upon passing the "DATUM" field
							prog_position := "RTA4";
							bookings_section_entered := true;
						end if;

						if guv_csv.get_field(line,1) = "WIRTSCHAFTSJAHR :" then
							prog_position := "RT10";
							fiscal_year_given := guv_csv.get_field(line,2);
							--put_line(fiscal_year_given);
						end if;
					end if;
			end loop;

			-- calculate total of takings and vat

			-- calculate date range by given quarter
			--put(natural'value(fiscal_year_given) * 10000); -- make from 2012 a 20120000
			case quarter_given is
				-- whole year
				when 0 => 	earliest_date := (natural'value(fiscal_year_given) * 10000) + 0101; -- make a 20120101 from fiscal_year_given and january 1st
							latest_date :=  (natural'value(fiscal_year_given) * 10000)  + 1231;  -- make a 20121231 from fiscal_year_given and december 31st

				-- quarter 1 : jan, feb, march
				when 1 => 	earliest_date := (natural'value(fiscal_year_given) * 10000) + 0101; 
							latest_date :=  (natural'value(fiscal_year_given) * 10000)  + 0331;  -- to make things easy, all months have 31 days

				-- quarter 2 : apr, may, jun
				when 2 => 	earliest_date := (natural'value(fiscal_year_given) * 10000) + 0401; 
							latest_date :=  (natural'value(fiscal_year_given) * 10000)  + 0631;  

				-- quarter 3 : jul, aug, sep
				when 3 => 	earliest_date := (natural'value(fiscal_year_given) * 10000) + 0701; 
							latest_date :=  (natural'value(fiscal_year_given) * 10000)  + 0931;  

				-- quarter 4 : oct, nov, dec
				when 4 => 	earliest_date := (natural'value(fiscal_year_given) * 10000) + 1001; 
							latest_date :=  (natural'value(fiscal_year_given) * 10000)  + 1231;  

				when others => raise constraint_error;
			end case;
			--put(earliest_date); put("  .."); put(latest_date); new_line;

			-- calculate date range by given month
			-- if month is given, the date ranges calculated above (quarter_given) will be overwritten
			case month_given is
				when 0 => null; -- leave ranges as they are
				when others => 
					earliest_date := (natural'value(fiscal_year_given) * 10000) + (month_given * 100) + 01; 
					latest_date   := (natural'value(fiscal_year_given) * 10000) + (month_given * 100) + 31;  -- to make things easy, all months have 31 days
			end case;	

			prog_position := "RTA5";
			if bookings_ct > 0 then -- only if there are bookings at all
				for booking_pt in 1..bookings_ct
				loop

					prog_position := "RGC1";
					natural_date := date_to_natural(takings_sized(booking_pt).date);

					if date_in_range(natural_date) 
						then 
						--put(natural_date); new_line;
						case takings_sized(booking_pt).vat_key is
							when 1 => takings_vat_1 := takings_vat_1 + takings_sized(booking_pt).vat; -- steuereinahmen summieren
							when 2 => takings_vat_2 := takings_vat_2 + takings_sized(booking_pt).vat; -- steuereinahmen summieren
							when 0 => null;
						end case;

						takings_total := takings_total + takings_sized(booking_pt).amount; -- einnahmen (netto) summieren
						if takings_sized(booking_pt).rv_pflichtig = "j" then -- wenn rv pflichtige einnahme
							takings_sized(booking_pt).rv := takings_sized(booking_pt).amount; -- einnahme_rv = einnahme
							takings_rv := takings_rv + takings_sized(booking_pt).rv; -- einnahmen_rv summieren
						end if;

					end if;
				end loop;
			end if;

			-- write report file header
			prog_position := "RTA6";
			--put_line(report_file, ascii.quotation & "GEWINN-UND-VERLUST-RECHNUNG" & ascii.quotation);

			guv_csv.put_field(report_file,"GEWINN-UND-VERLUST-RECHNUNG"); guv_csv.put_lf(report_file);
			guv_csv.put_field(report_file,"----------------------------------------------------------"); guv_csv.put_lf(report_file);
			put_line(report_file, ascii.quotation & "FIRMA :" & ascii.quotation & ifs & ascii.quotation & to_string(name_given) & ascii.quotation);
			put_line(report_file, ascii.quotation & "STEUERNUMMER :" & ascii.quotation & ifs & ascii.quotation & tax_id_given & ascii.quotation);
			put_field(report_file,"USt.-IdNr :"); put_field(report_file,vat_id_given); guv_csv.put_lf(report_file);
			put_field(report_file,"WIRTSCHAFTSJAHR :");put_field(report_file,fiscal_year_given); put_lf(report_file);

			if month_given /= 0 then
				put_field(report_file,"MONAT :");put_field(report_file,trim(natural'image(month_given),left)); put_lf(report_file);
			else
				if quarter_given = 0 then
					put_field(report_file,"QUARTAL :");put_field(report_file,"1..4"); put_lf(report_file);
				else
					put_field(report_file,"QUARTAL :");put_field(report_file,trim(natural'image(quarter_given),left)); put_lf(report_file);
				end if;
			end if;

			--new_line(report_file);
			now := clock;
			put_line(report_file, ascii.quotation & "DATUM (JJJJ-MM-TT) :" & ascii.quotation & ifs & ascii.quotation & image(now, time_zone => UTC_Time_Offset(now)) & ascii.quotation);
			new_line(report_file);

			put_field(report_file,"MwSt. Schlüssel 1 : "); put_field(report_file,trim(money_positive'image(100*vat_1),left) & " %"); put_lf(report_file);
			put_field(report_file,"MwSt. Schlüssel 2 : "); put_field(report_file,trim(money_positive'image(100*vat_2),left) & " %"); put_lf(report_file);
			put_lf(report_file); put_lf(report_file);

			put_line(report_file, ascii.quotation & "1. EINNAHMEN" & ascii.quotation);
			put_line(report_file, ascii.quotation & "-------------" & ascii.quotation);
			put_line(report_file, ascii.quotation & "aus Datei :" & ascii.quotation & ifs & ascii.quotation & to_string(takings_csv) & ascii.quotation);
			new_line(report_file);

			put_field(report_file,"BUCHUNG_NR.");
			put_field(report_file,"DATUM");
			put_field(report_file,"UMSATZ");
			put_field(report_file,"ST_SCHL.");
			put_field(report_file,"MWST_1");
			put_field(report_file,"MWST_2");
			put_field(report_file,"KUNDE");
			put_field(report_file,"BETREFF");
			if report_rv_figures = true then -- if rv figures required, put them here. otherwise skip putting them
				put_field(report_file,"RV_PFLICHTIG");
				put_field(report_file,"BETRAG_RV");
				put_field(report_file);
			end if;
			put_field(report_file,"BEMERKUNG");
			put_lf(report_file,2);

			-- write takings in report file
			prog_position := "RTA7";
			if bookings_ct > 0 then -- only if there are bookings at all
				sort_takings;
		--		put_line("test");
				for booking_pt in 1..bookings_ct
					loop
						prog_position := "RGC2";
						natural_date := date_to_natural(takings_sized(booking_pt).date);

						if date_in_range(natural_date) 
							then 
							--put(natural_date); new_line;
							--put_line(natural'image(booking_pt)); -- debug

							put_field(report_file,trim(natural'image(booking_pt),left));
							put_field(report_file,takings_sized(booking_pt).date);

							put_field
								(
								report_file,
								replace_dot_by_comma(trim(money_positive'image(takings_sized(booking_pt).amount),left))
								);

							put_field(report_file,trim(natural'image(takings_sized(booking_pt).vat_key),left));

							case takings_sized(booking_pt).vat_key is

								when 0 => 	put_field(report_file,replace_dot_by_comma(trim(money_positive'image(0.00),left)));
											put_field(report_file,replace_dot_by_comma(trim(money_positive'image(0.00),left)));
								when 1 => 	put_field(report_file,replace_dot_by_comma(trim(money_positive'image(takings_sized(booking_pt).vat),left)));
											put_field(report_file,replace_dot_by_comma(trim(money_positive'image(0.00),left)));
								when 2 =>	put_field(report_file,replace_dot_by_comma(trim(money_positive'image(0.00),left)));
											put_field(report_file,replace_dot_by_comma(trim(money_positive'image(takings_sized(booking_pt).vat),left)));
							end case;
		
							put_field(report_file,to_string(takings_sized(booking_pt).customer));
							put_field(report_file,to_string(takings_sized(booking_pt).subject));

							-- skip putting rv figures if not required
							if report_rv_figures = true then
								put_field(report_file,takings_sized(booking_pt).rv_pflichtig);
								put_field(report_file,replace_dot_by_comma(trim(money_positive'image(takings_sized(booking_pt).rv),left)));
								put_field(report_file);
							end if;
							put_field(report_file,to_string(takings_sized(booking_pt).remarks));
							put_lf(report_file);
						end if;
					end loop;
			end if;


			put_field(report_file,"--------------");
			put_field(report_file,"--------------");
			put_field(report_file,"--------------");
			put_field(report_file,"-------");
			put_field(report_file,"--------------");
			put_field(report_file,"--------------");
			put_field(report_file,"-------------------------");
			put_field(report_file,"-------------------------");
			-- skip putting rv figures if not required
			if report_rv_figures = true then
				put_field(report_file,"--------------");
				put_field(report_file,"-------");
				put_field(report_file,"-------");
			end if;
			put_field(report_file,"--------------");
			put_lf(report_file);

			prog_position := "RTA8";
			if bookings_ct > 0 then 
				if takings_total = 0.00 then
					put_line("INFO : Im angegebenen Zeitraum gibt es keine Einnahmen !");
					-- ratio_rv_turnover will be left untouched (zero) if no takings
				else
					-- if there are takings, update ratio_rv_turnover
					ratio_rv_turnover := ratio'round(takings_rv/takings_total);
				end if;
				--put_line(ratio'image(ratio_rv_turnover));

				put_field(report_file,"SUMME");
				put_field(report_file);
				put_field(report_file, replace_dot_by_comma(trim(money_positive'image(takings_total),left)) );
				put_field(report_file);
				put_field(report_file, replace_dot_by_comma(trim(money_positive'image(takings_vat_1),left)) );
				put_field(report_file, replace_dot_by_comma(trim(money_positive'image(takings_vat_2),left)) );
				put_field(report_file);
				put_field(report_file);
				if report_rv_figures = true then
					put_field(report_file);
					put_field(report_file, replace_dot_by_comma(trim(money_positive'image(takings_rv),left)) );
					put_field(report_file, "enspr. " & replace_dot_by_comma(trim(money_positive'image( ratio_rv_turnover*100.0) ,left)) & "% vom Gesamtumsatz" );
				end if;
				put_lf(report_file);

			end if;
--			put_line("davon RV pflichtig gesamt :" & money_positive'image(takings_rv));
		end read_takings;



		procedure read_expenses is
			subtype expenses_sized_type is expenses (1..bookings_ct);
			expenses_sized				: expenses_sized_type;
			bookings_section_entered	: boolean := false;
			booking_pt					: natural := 0;

			procedure sort_expenses
				is
				subtype bookings_index_type is natural range 1 .. bookings_ct; 
				subtype expenses_type is expenses (bookings_index_type);  

				function "<" (L, R : entry_expense) return Boolean is
				begin
					return L.date < R.date;
				end "<";
 				
-- for debug only
-- 				procedure put_booking (C : entry_taking) is
-- 				begin
-- 					Put_Line (C.date & " " & to_string(C.subject));
-- 					null;
-- 				end put_booking;
		
 				procedure Sort is new Ada.Containers.Generic_Constrained_Array_Sort (
  					array_type => expenses_type,
 					element_type => entry_expense, 
  					index_type => bookings_index_type
  					);

				scratch : expenses_type := expenses_sized;
	
			begin
				Sort (scratch);
-- for debug only
-- 	 			for i in 1..takings_sized'last loop
-- 	 				put_booking ( a(i));
-- 	 			end loop;
				expenses_sized := scratch;
			end sort_expenses;



		begin
			prog_position := "EXP1";
			while not End_Of_File -- read expenses_csv file
			loop
				line:=get_line;
					-- CS: ignore empty lines , this also applies for reading takings
					if bookings_section_entered then
						prog_position := "EX03";
						booking_pt := booking_pt + 1;
						--put_line(natural'image(booking_pt));
						--put_line(line);

 						expenses_sized(booking_pt).date   			:= guv_csv.get_field(line,2);
 						expenses_sized(booking_pt).amount 			:= money_positive'value(guv_csv.get_field(line,3));
 						expenses_sized(booking_pt).vat_key			:= natural'value(guv_csv.get_field(line,4));
 						expenses_sized(booking_pt).vat				:= money_positive'value(guv_csv.get_field(line,5));
 						expenses_sized(booking_pt).receipient		:= to_bounded_string(guv_csv.get_field(line,6));
 						expenses_sized(booking_pt).subject			:= to_bounded_string(guv_csv.get_field(line,7));
 						expenses_sized(booking_pt).rv_anteilig		:= guv_csv.get_field(line,8);
 						expenses_sized(booking_pt).rv_vollst		:= guv_csv.get_field(line,9);
						prog_position := "EX04";
 						expenses_sized(booking_pt).remarks			:= to_bounded_string(guv_csv.get_field(line,10));

					else -- bookings_section not entered yet 
						-- CS: verify name here with name in takings file
						--if strip_text_delimiters(guv_csv.get_field(line,1)) = "FIRMA :" then
						--	name_given := to_bounded_string(strip_text_delimiters(guv_csv.get_field(line,2)));
							--put_line("test");
						--end if;

						-- CS: verify tax id here with tax id in takings file
						--if strip_text_delimiters(guv_csv.get_field(line,1)) = "STEUERNUMMER :" then
						--	tax_id_given := to_bounded_string(strip_text_delimiters(guv_csv.get_field(line,2)));
							--put_line("test");
						--end if;

						-- CS: verify vat id here with vat id in takings file

						if guv_csv.get_field(line,1) = "BUCHUNG_NR." then -- set bookings_section_entered flag upon passing the "DATUM" field
							bookings_section_entered := true;
						end if;
					end if;
			end loop;


			-- calculate total of expenses and vat
			prog_position := "EXP2";
			--put(bookings_ct);
			if bookings_ct > 0 then
				for booking_pt in 1..bookings_ct
				loop
					prog_position := "RGC3";
					natural_date := date_to_natural(expenses_sized(booking_pt).date);
					if date_in_range(natural_date) 
						then 
						--put(natural_date); new_line;
							expenses_vat := expenses_vat + expenses_sized(booking_pt).vat; -- steuerausgaben summieren
							expenses_total := expenses_total + expenses_sized(booking_pt).amount; -- ausgaben summieren
							if expenses_sized(booking_pt).rv_vollst = "j" then -- wenn vollst. rv pflichtige ausgabe
								expenses_sized(booking_pt).rv := expenses_sized(booking_pt).amount; -- ausgabe rv gleich einnahme
							end if;

							if expenses_sized(booking_pt).rv_anteilig = "j" then -- wenn anteilig rv pflichtige ausgabe
								expenses_sized(booking_pt).rv := money_positive'round( expenses_sized(booking_pt).amount * ratio_rv_turnover ); -- ausgabe mal anteil rv vom umsatz
							end if;
							expenses_rv := expenses_rv + expenses_sized(booking_pt).rv; -- rv-ausgaben summieren
					end if;
				end loop;
			end if;

			prog_position := "EXP3";
			new_line(report_file,3);
			put_line(report_file, ascii.quotation & "2. AUSGABEN " & ascii.quotation);
			put_line(report_file, ascii.quotation & "-------------" & ascii.quotation);
			put_line(report_file, ascii.quotation & "aus Datei :" & ascii.quotation & ifs & ascii.quotation & to_string(expenses_csv) & ascii.quotation);
			new_line(report_file);

			put_field(report_file,"BUCHUNG_NR.");
			put_field(report_file,"DATUM");
			put_field(report_file,"BETRAG");
			put_field(report_file,"ST_SCHL.");
			put_field(report_file);
			put_field(report_file,"MWST");
			put_field(report_file,"EMPFÄNGER");
			put_field(report_file,"BETREFF");
			if report_rv_figures = true then -- put rv figures if required
				put_field(report_file,"RV_ANTEILIG");
				put_field(report_file,"RV_VOLLST.");
				put_field(report_file,"RV");
			end if;
			put_field(report_file,"BEMERKUNG");
			put_lf(report_file,2);

			-- write expenses in report file
			prog_position := "EXP4";
			if bookings_ct > 0 then
				sort_expenses;
				for booking_pt in 1..bookings_ct
				loop
					prog_position := "RGC4";
					natural_date := date_to_natural(expenses_sized(booking_pt).date);
					if date_in_range(natural_date) 
						then 
							put_field(report_file, trim(natural'image(booking_pt),left) );
							put_field(report_file, expenses_sized(booking_pt).date );
							put_field(report_file, replace_dot_by_comma(trim(money_positive'image(expenses_sized(booking_pt).amount),left)) );
							put_field(report_file, trim(natural'image(expenses_sized(booking_pt).vat_key),left) );
							put_field(report_file);
							put_field(report_file, replace_dot_by_comma(trim(money_positive'image(expenses_sized(booking_pt).vat),left)) );
							put_field(report_file, to_string(expenses_sized(booking_pt).receipient) );
							put_field(report_file, to_string(expenses_sized(booking_pt).subject) );
							if report_rv_figures = true then -- skip rv figures if not required
								put_field(report_file, expenses_sized(booking_pt).rv_anteilig );
								put_field(report_file, expenses_sized(booking_pt).rv_vollst );
								put_field(report_file, replace_dot_by_comma(trim(money_positive'image(expenses_sized(booking_pt).rv),left)) );
							end if;
							put_field(report_file, to_string(expenses_sized(booking_pt).remarks) );
							put_lf(report_file);

						end if;
				end loop;
			end if;

			put_field(report_file, "--------------");
			put_field(report_file, "--------------");
			put_field(report_file, "--------------");
			put_field(report_file, "-------");
			put_field(report_file, "-------");
			put_field(report_file, "--------------");
			put_field(report_file, "-----------------------");
			put_field(report_file, "-----------------------");
			if report_rv_figures = true then -- skip rv figures if not required
				put_field(report_file, "-----------");
				put_field(report_file, "-----------");
				put_field(report_file, "--------------");
			end if;
			put_field(report_file, "--------------");
			put_lf(report_file);


			prog_position := "EXP5";
			if bookings_ct > 0 then
				put_field(report_file,"SUMME");
				put_field(report_file);
				put_field(report_file, replace_dot_by_comma(trim(money_positive'image(expenses_total),left)) );
				put_field(report_file);
				put_field(report_file);
				put_field(report_file, replace_dot_by_comma(trim(money_positive'image(expenses_vat),left)) );
				put_field(report_file);
				put_field(report_file);
				if report_rv_figures = true then -- skip rv figures if not required
					put_field(report_file);
					put_field(report_file);
					put_field(report_file, replace_dot_by_comma(trim(money_positive'image(expenses_rv),left)) );
				end if;
				put_field(report_file);
				put_lf(report_file);
			end if;
		end read_expenses;




	begin
		prog_position := "RPT1";

		-- if report file exists, make backup of report_file in directory bak/report
		if exists ( to_string(report_csv) ) then
			copy_file( to_string(report_csv), "bak/reports/" & make_filename_by_date(to_string(report_csv)) );
		end if;

		-- create report file
		prog_position := "RP11";
		Create( report_file, Name => to_string(report_csv)); Close(report_file); -- CS: datum im namen des reports unterbringen ?
		Open( 
			File => report_file,
			Mode => out_file,
			Name => to_string(report_csv)
			);

		-- count number of takings
		if not exists(to_string(takings_csv)) then
			put_line("FEHLER : Einnahmen-Datei '" & to_string(takings_csv) & "' existiert nicht !");
			raise constraint_error;
		end if;

		prog_position := "RP12";
		Open( 
			File => takings_file,
			Mode => in_File,
			Name => to_string(takings_csv)
			);
		set_input(takings_file);
		bookings_ct := count_bookings;
		reset(takings_file);
		--put_line("bookings in " & natural'image(bookings_ct));

		prog_position := "RPT2";
		read_takings;
		close(takings_file);


		-- count number of expenses
		prog_position := "RPT3";
		if not exists(to_string(expenses_csv)) then
			put_line("FEHLER : Ausgaben-Datei '" & to_string(expenses_csv) & "' existiert nicht !");
			raise constraint_error;
		end if;

		Open( 
			File => expenses_file,
			Mode => in_File,
			Name => to_string(expenses_csv)
			);
		set_input(expenses_file);
		bookings_ct := count_bookings;
		reset(expenses_file);
		--put_line("bookings out " & natural'image(bookings_ct));

		read_expenses;
		close(expenses_file);

		yield		:= money(takings_total) - money(expenses_total);
		vat_excess 	:= money(takings_vat_1 + takings_vat_2) - money(expenses_vat);
		yield_rv	:= money(takings_rv) - money(expenses_rv);

		--write summary in report file
 		new_line(report_file,3);
 		put_line(report_file, ascii.quotation & "3. ABSCHLUSS" & ascii.quotation);
 		put_line(report_file, ascii.quotation & "-------------" & ascii.quotation);
 		new_line(report_file,1);

		put_lf(report_file);
 		put_field(report_file,"UMSATZ GESAMT :");
		put_field(report_file,replace_dot_by_comma(trim(money_positive'image(takings_total),left)));
		put_lf(report_file);

		-- put rv figures if required
		if report_rv_figures = true then
			put_lf(report_file);
			put_field(report_file,"GEWINN FREIBERUF :");
			put_field(report_file,replace_dot_by_comma(trim(money'image(yield - yield_rv),left)));
			put_lf(report_file);

			put_lf(report_file);
			put_field(report_file,"GEWINN RV PFLICHTIG :"); 
			put_field(report_file,replace_dot_by_comma(trim(money'image(yield_rv),left))); put_field(report_file,"-> x % abzuführen an RV");
			put_field(report_file,"  (Dozenten"); put_field(report_file,"-und"); put_field(report_file," Schulungstätigkeit)");
			put_lf(report_file);
		end if;

		put_lf(report_file);
 		put_field(report_file,"GEWINN GESAMT :");
		put_field(report_file,replace_dot_by_comma(trim(money'image(yield),left))); put_lf(report_file);
		put_lf(report_file);

 		put_field(report_file,"STEUEREINNAHMEN :");
		put_field(report_file,replace_dot_by_comma(trim(money_positive'image(takings_vat_1 + takings_vat_2),left)));
		put_field(report_file,"(eingen. MwSt.)"); put_lf(report_file);
		put_lf(report_file);

 		put_field(report_file,"VORSTEUER :");
		put_field(report_file,replace_dot_by_comma(trim(money_positive'image(expenses_vat),left)));
		put_field(report_file,"(ausgegebene MwSt.)"); put_lf(report_file);
		put_lf(report_file);

 		put_field(report_file,"MwSt. ÜBERSCHUSS :");
		put_field(report_file,replace_dot_by_comma(trim(money'image(vat_excess),left))); put_field(report_file,"-> abzuführen an FA");
		put_field(report_file,"  (eingen."); put_field(report_file," MwSt."); put_field(report_file," - ausgeg. MwSt.)"); put_lf(report_file);
		put_lf(report_file);

		close(report_file);

	end report;



	procedure print_help_general is
	begin
		new_line;
		put_line("GUV Assistent Version "& version);

		prog_position := "HLP0";
 		spawn 
 			(  
 			program_name           => "/bin/cat",
 			args                   => 	(
 										1=> new string'(to_string(home_directory) & conf_directory & help_file_name_german)
 										),
 			output_file_descriptor => standout,
 			return_code            => result
 			);
 		if 
 			result /= 0 then raise constraint_error;
 		end if;
	end print_help_general;

	procedure check_environment is

	begin
		-- get home variable
		prog_position := "ENV0";
		if not ada.environment_variables.exists("HOME") then
			raise constraint_error;
		else
			-- compose home directory name
			home_directory := to_bounded_string(ada.environment_variables.value("HOME") & "/"); -- this is the absolute path of the home directory
			--put_line(to_string(home_directory));
		end if;

		-- check if conf file exists	
		prog_position := "ENV1";
		if not exists ( to_string(home_directory) & conf_directory & conf_file_name ) then 
			raise constraint_error;
		end if;

		-- check if help file exists	
		prog_position := "ENV2";
		if not exists ( to_string(home_directory) & conf_directory & help_file_name_german ) then 
			raise constraint_error;
		end if;
	end;


-------- MAIN PROGRAM ------------------------------------------------------------------------------------

begin
	prog_position := "INIT";

	--check environment
	check_environment;


	prog_position := "ARCT";

	arg_ct := argument_count;
	--put_line("argument_count : " & natural'image(arg_ct));

	if arg_ct = 0 then
		print_help_general;
	else

		prog_position := "RDAR";
		for arg_pt in 1..arg_ct
		loop

-- 			if argument(arg_pt) = "-info" then
-- 				print_help_general;
-- 			end if;
-- 
-- 			if argument(arg_pt) = "-hilfe" then
-- 				print_help_general;
-- 			end if;
-- 
-- 			if argument(arg_pt) = "-hilfe_ein" then
-- 				print_help_in;
-- 			end if;
-- 
-- 			if argument(arg_pt) = "-hilfe_aus" then
-- 				print_help_out;
-- 			end if;
-- 
-- 			if argument(arg_pt) = "-hilfe_neu" then
-- 				print_help_neu;
-- 			end if;
-- 
-- 			if argument(arg_pt) = "-hilfe_report" then
-- 				print_help_rep;
-- 			end if;

			if argument(arg_pt) = "-neu" then
				create_action := true;
			end if;

			if argument(arg_pt) = "-rep" then
				prog_position := "RPRT";
				if Argument(arg_pt + 1)(1) = '-' then 
					put_line("FEHLER : Name der Report-Datei muss Option '-rep' folgen !");
					raise constraint_error;
				end if;
				report_csv:=to_bounded_string(check_space_semicolon(Argument(arg_pt + 1)));
				report_action := true;
			end if;

			if argument(arg_pt) = "-monat" then
				prog_position := "RPR3";
				month_given:= natural'value(Argument(arg_pt + 1));
			end if;

			if argument(arg_pt) = "-quartal" then
				prog_position := "RPR1";
				quarter_given:= natural'value(Argument(arg_pt + 1));
			end if;

			if argument(arg_pt) = "-rv" then 
				prog_position := "RPR2";
				report_rv_figures:= true;
			end if;

			if argument(arg_pt) = "-man" then
				prog_position := "NAME";
				if Argument(arg_pt + 1)(1) = '-' then 
					put_line("FEHLER : Name des anzulegenden Mandanten muss Option '-man' folgen !");
					raise constraint_error;
				end if;
				name_given:=to_bounded_string(check_semicolon(Argument(arg_pt + 1)));
			end if;

			if argument(arg_pt) = "-stnr" then
				prog_position := "TXID";
				if Argument(arg_pt + 1)(1) = '-' then 
					put_line("FEHLER : Steuernummer muss Option '-stnr' folgen !");
					raise constraint_error;
				end if;
				--if Argument(arg_pt + 1)'length
				tax_id_given:= Argument(arg_pt + 1);
				tax_id_given:= check_tax_id(Argument(arg_pt + 1));
			end if;

			if argument(arg_pt) = "-ui" then
				prog_position := "VTID";
				if Argument(arg_pt + 1)(1) = '-' then 
					put_line("FEHLER : Umsatzsteuer-IdNr. muss Option '-ui' folgen !");
					raise constraint_error;
				end if;
				--if Argument(arg_pt + 1)'length
				vat_id_given:= Argument(arg_pt + 1);
				vat_id_given:= check_vat_id(Argument(arg_pt + 1));
			end if;

			if argument(arg_pt) = "-wj" then
				prog_position := "FJ01";
				if Argument(arg_pt + 1)(1) = '-' then 
					put_line("FEHLER : Wirtschaftsjahr muss Option '-wj' folgen !");
					raise constraint_error;
				end if;
				--if Argument(arg_pt + 1)'length
				fiscal_year_given:= check_year(Argument(arg_pt + 1));
			end if;


			if argument(arg_pt) = "-ein" then
				--takings_csv:=to_bounded_string(Argument(arg_pt + 1));
				take_action := true;
			end if;

			if argument(arg_pt) = "-ed" then
				prog_position := "TAF0";
				if Argument(arg_pt + 1)(1) = '-' then 
					raise constraint_error;
				end if;
-- 				prog_position := "TAF1";
-- 				if Argument(arg_pt + 1)'length = 0 then
-- 					put_line("FEHLER : Bitte Einnahmen-Datei mit Option '-ed' spezifizieren !");
-- 					raise constraint_error;
-- 				end if;

				takings_csv:=to_bounded_string(check_space_semicolon(Argument(arg_pt + 1)));
			end if;

			if argument(arg_pt) = "-aus" then
				--expenses_csv:=to_bounded_string(Argument(arg_pt + 1));
				expense_action := true;
			end if;

			if argument(arg_pt) = "-ad" then
				prog_position := "EXF0";
				if Argument(arg_pt + 1)(1) = '-' then 
					raise constraint_error;
				end if;
				expenses_csv:=to_bounded_string(check_space_semicolon(Argument(arg_pt + 1)));
				--expense_action := true;
			end if;



			if argument(arg_pt) = "-betrag" then
				prog_position := "AMT0";
				if Argument(arg_pt + 1)(1) = '-' then 
					put_line("FEHLER : Betrag muss Option '-betrag' folgen !");
					raise constraint_error;
				end if;
				amount_given:= money_positive'value(Argument(arg_pt + 1));
			end if;

			if argument(arg_pt) = "-datum" then
				prog_position := "DATE";
				if Argument(arg_pt + 1)(1) = '-' then 
					put_line("FEHLER : Datum 20JJ-MM-TT muss nach Option '-datum' folgen !");
					raise constraint_error;
				end if;
				date_given:= check_date(Argument(arg_pt + 1));
				date_given_ok := true;
			end if;

			if argument(arg_pt) = "-kunde" then
				prog_position := "CSTM";
				if Argument(arg_pt + 1)(1) = '-' then 
					put_line("FEHLER : Name des Kunden muss nach Option '-kunde' folgen !");
					raise constraint_error;
				end if;
				customer_given:= to_bounded_string(check_semicolon(Argument(arg_pt + 1)));
				customer_given_ok := true;
			end if;

			if argument(arg_pt) = "-empfaenger" then
				prog_position := "RCPT";
				if Argument(arg_pt + 1)(1) = '-' then 
					put_line("FEHLER : Name des Empfängers den muss nach Option '-empfaenger' folgen !");
					raise constraint_error;
				end if;
				receipient_given:= to_bounded_string(check_semicolon(Argument(arg_pt + 1)));
				receipient_given_ok := true;
			end if;

			if argument(arg_pt) = "-betreff" then
				prog_position := "ITSV";
				if Argument(arg_pt + 1)(1) = '-' then 
					put_line("FEHLER : Betreff muss nach Option '-betreff' folgen !");
					raise constraint_error;
				end if;
				subject_given:= to_bounded_string(check_semicolon(Argument(arg_pt + 1)));
				subject_given_ok := true;
			end if;

			if argument(arg_pt) = "-steuerschluessel" then
				prog_position := "VK01";
				if Argument(arg_pt + 1)(1) = '-' then 
					put_line("FEHLER : Steuerschlüssel muss nach Option '-steuerschluessel' folgen !");
					raise constraint_error;
				end if;
				vat_key_given:= natural'value(Argument(arg_pt + 1));
			end if;

			if argument(arg_pt) = "-rv_pfl" then
				prog_position := "RVPF";
				if Argument(arg_pt + 1)(1) = '-' then 
					put_line("FEHLER : Zeichen 'j/n' muss nach Option '-rv_pfl' folgen !");
					raise constraint_error;
				end if;
				rv_pflichtig_yes_no_given:= to_lower(Argument(arg_pt + 1)(1));
				if not is_in(rv_pflichtig_yes_no_given,yes_no_type) then
					raise constraint_error;
				end if;
			end if;

			if argument(arg_pt) = "-rv_teil" then
				prog_position := "RVTL";
				if Argument(arg_pt + 1)(1) = '-' then 
					put_line("FEHLER : Zeichen 'j/n' muss nach Option '-rv_teil' folgen !");
					raise constraint_error;
				end if;
				rv_anteilig_yes_no_given:= to_lower(Argument(arg_pt + 1)(1));
				if not is_in(rv_anteilig_yes_no_given,yes_no_type) then
					raise constraint_error;
				end if;
			end if;

			if argument(arg_pt) = "-rv_voll" then
				prog_position := "RVVO";
				if Argument(arg_pt + 1)(1) = '-' then 
					put_line("FEHLER : Zeichen 'j/n' muss nach Option '-rv_voll' folgen !");
					raise constraint_error;
				end if;
				rv_vollst_yes_no_given:= to_lower(Argument(arg_pt + 1)(1));
				if not is_in(rv_vollst_yes_no_given,yes_no_type) then
					raise constraint_error;
				end if;
			end if;

			if argument(arg_pt) = "-bem" then
				prog_position := "RMRK";
				if Argument(arg_pt + 1)(1) = '-' then 
					put_line("FEHLER : Bemerkung muss nach Option '-bem' folgen !");
					raise constraint_error;
				end if;
				remark_given:= to_bounded_string(check_semicolon(Argument(arg_pt + 1)));
			end if;
		end loop;

		if report_action then report;
		else
			if create_action then create;
				else if take_action or expense_action then take_expense_action; end if;
			end if;
		end if;

	end if;



	exception
		when others =>
			new_line;
			if prog_position = "DATE" then put_line("FEHLER : Gefordertes Datum Format ist 20JJ-MM-TT !"); end if;
			if prog_position = "AMNT" then put_line("FEHLER : Betrag muss größer null sein !"); end if;
			if prog_position = "CSTM" then put_line("FEHLER : Name des Kunden fehlt oder max. Länge von " & natural'image(customer_length) & " Zeichen überschritten !"); end if;
			if prog_position = "RCPT" then put_line("FEHLER : Name des Empfängers begrenzt auf" & natural'image(customer_length) & " Zeichen !"); end if;
			if prog_position = "ITSV" then put_line("FEHLER : Betreff fehlt oder max. Länge von " & natural'image(subject_length) & " Zeichen überschritten !"); end if;
			if prog_position = "TXID" then put_line("FEHLER : Steuernummer muß aus 13 Zeichen bestehen. Format 111/222/333333 !"); end if;
			if prog_position = "VTID" then put_line("FEHLER : Umsatzsteuer ID Nr. muß aus 11 Zeichen bestehen. Format DE123456789 !"); end if;
			if prog_position = "NAME" then put_line("FEHLER : Firmenname begrenzt auf" & natural'image(customer_length) & " Zeichen !"); end if;
			if prog_position = "RMRK" then put_line("FEHLER : Bemerkungen begrenzt auf" & natural'image(remark_length) & " Zeichen !"); end if;
			if prog_position = "VT10" then 
				put_line("FEHLER : MwSt. Schlüssel darf nur 0 (keine Steuer),");
				put_line("                                  1 (" & money_positive'image(vat_1*100.00) & "% ) oder");
				put_line("                                  2 (" & money_positive'image(vat_2*100.00) & "% ) sein !"); 
			end if;
			if prog_position = "RVPF" then put_line("FEHLER : RV_pflichtig wird nur durch j oder n spezifiziert !"); end if;
			if prog_position = "RPRT" then put_line("FEHLER : Report Datei nicht spezifiziert !"); end if;
			if prog_position = "RPR1" then put_line("FEHLER : Ungültiges Quartal angegeben. Quartal bitte mit Nummer 1..4 spezifizieren !"); end if; -- inc v005
			if prog_position = "NBKG" or 
			   prog_position = "NCRT" or
			   prog_position = "NCRE" then put_line("BUCHUNG ABGEBROCHEN"); end if;
			if prog_position = "RTA3" then put_line("FEHLER : Einnahmen-Datei enhält keine Steuernummer !"); end if;
			if prog_position = "TAF0" then put_line("FEHLER : Name der Einnahmen-Datei muss Option '-ed' folgen !"); end if;
			if prog_position = "EXF0" then put_line("FEHLER : Name der Ausgaben-Datei muss Option '-ad' folgen !"); end if;
			if prog_position = "RP11" then put_line("FEHLER : Keine Schreibberechtigung auf Report Datei !"); end if;
			if prog_position = "ENV0" then put_line("FEHLER : Keine $HOME Umgebungsvariable gefunden !"); end if;
			if prog_position = "ENV1" then put_line("FEHLER : Konfigurationsdatei " & to_string(home_directory) & conf_directory & conf_file_name & " nicht gefunden !"); end if;
			if prog_position = "ENV2" then put_line("FEHLER : Hilfe-Datei " & to_string(home_directory) & conf_directory & help_file_name_german & " nicht gefunden !"); end if;
			new_line;
			put_line("Programm Abbruch an Position : " & prog_position);
			set_exit_status(1);
end guv;

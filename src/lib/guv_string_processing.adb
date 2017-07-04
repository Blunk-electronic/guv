------------------------------------------------------------------------------
--                                                                          --
--                         SYSTEM M-1 COMPONENTS                            --
--                                                                          --
--                                 M-1                                      --
--                                                                          --
--                               B o d y                                    --
--                                                                          --
--         Copyright (C) 2017 Mario Blunk, Blunk electronic                 --
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
--


with ada.text_io;				use ada.text_io;
with ada.strings.unbounded; 	use ada.strings.unbounded;


package body guv_string_processing is


	function is_field	
		(
		-- version 1.0 / mbl
		line	: unbounded_string;  	-- given line to examine
		value 	: string ; 				-- given value to be tested for
		field	: natural				-- field number to expect value in
		) 
		return boolean is 

		r			: 	boolean := false; 			-- on match return true, else return false
		line_length	:	natural;					-- length of given line
		char_pt		:	natural := 1;				-- charcter pointer (points to character being processed inside the given line)
		value_length:	natural;					-- length of given value
		ifs1		: 	constant character := ' '; 				-- field separator space
		ifs2		: 	constant character := character'val(9); -- field separator tabulator
		field_ct	:	natural := 0;				-- field counter (the first field found gets number 1 assigned)
		field_pt	:	natural := 1;				-- field pointer (points to the charcter being processed inside the current field)
		inside_field:	boolean := true;			-- true if char_pt points inside a field
		char_current:	character;					-- holds current character being processed
		char_last	:	character := ' ';			-- holds character processed previous to char_current

		begin
			--put ("line  : "& Line); new_line;
			--put ("field : "); put (Field); new_line;
			--put ("value : "& Value); new_line;
			line_length:=(Length(Line));
			value_length:=(Length(To_Unbounded_String(Value)));
			while char_pt <= line_length
				loop
					--put (char_pt);
					char_current:=(To_String(Line)(char_pt)); 
					if char_current = IFS1 or char_current = IFS2 then
						inside_field := false;
					else
						inside_field := true;
					end if;
	
					-- count fields if character other than IFS found
					if ((char_last = IFS1 or char_last = IFS2) and (char_current /= IFS1 and char_current /= IFS2)) then
						field_ct:=field_ct+1;
					end if;

					if (Field = field_ct) then
						--put ("target field found"); new_line;
						if (inside_field = true) then -- if field entered
							--put ("target field entered"); 

							-- if Value is too short (to avoid constraint error at runtime)
							if field_pt > value_length then
								R := false;
								return R;
							end if;

							-- if character in value matches
							if Value(field_pt) = char_current then
								--put (field_pt); put (Value(field_pt)); new_line;
								field_pt:=field_pt+1;
							else
								-- on first mismatch exit
								--put ("mismatch"); new_line;
								R := false;
								return R;
							end if;

							-- in case the last field matches
							if char_pt = line_length then
								if (field_pt-1) = value_length then
									--put ("match at line end"); new_line;
									R := true;
									return R;
								end if;
							end if;

						else -- once field is left
							if (field_pt-1) = value_length then
								--put ("field left"); new_line;
								R := true;
								return R;
							end if;
						end if;
					end if;
						
					-- save last character
					char_last:=char_current;

					-- advance character pointer by one
					char_pt:=char_pt+1; 

					--put (char_current); put (" --"); new_line;
				end loop;

			R:=false;
			return R;
		end is_field;

end guv_string_processing;


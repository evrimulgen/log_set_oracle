CREATE OR REPLACE PACKAGE BODY Trapit AS
/***************************************************************************************************
Name: trapit.pkb                       Author: Brendan Furey                       Date: 26-May-2019

Package body component in the trapit_oracle_tester module. It requires a minimum Oracle 
database version of 12.2, owing to the use of v12.2 PL/SQL JSON features.

This module facilitates unit testing following 'The Math Function Unit Testing design pattern'.

    GitHub: https://github.com/BrenPatF/trapit_oracle_tester

====================================================================================================
|  Package     |  Notes                                                                            |
|===================================================================================================
| *Trapit*     |  Unit test utility package (Definer rights)                                       |
----------------------------------------------------------------------------------------------------
|  Trapit_Run  |  Unit test utility runner package (Invoker rights)                                |
====================================================================================================

This file has the Trapit package body. See README for API specification, and the other modules
mentioned there for examples of use.

***************************************************************************************************/
META                          CONSTANT VARCHAR2(10) := 'meta';
SCENARIOS                     CONSTANT VARCHAR2(10) := 'scenarios';
INP                           CONSTANT VARCHAR2(10) := 'inp';
OUT                           CONSTANT VARCHAR2(10) := 'out';
EXP                           CONSTANT VARCHAR2(10) := 'exp';
ACT                           CONSTANT VARCHAR2(10) := 'act';

/***************************************************************************************************

get_JSON_Obj: Gets the JSON object from table tt_units

***************************************************************************************************/
FUNCTION get_JSON_Obj(
            p_package_nm                   VARCHAR2,        -- package name
            p_procedure_nm                 VARCHAR2)        -- procedure name
            RETURN                         JSON_Object_T IS -- JSON object
  l_input_json            CLOB;
  l_json_elt              JSON_Element_T;
  l_json_obj              JSON_Object_T;
BEGIN

  SELECT input_json
    INTO l_input_json
    FROM tt_units
   WHERE package_nm     = p_package_nm
     AND procedure_nm   = p_procedure_nm;

  l_json_elt := JSON_Element_T.parse(l_input_json);
  IF NOT l_json_elt.is_Object THEN
    Utils.Raise_Error('Invalid JSON');
  END IF;

  RETURN treat(l_json_elt AS JSON_Object_T);

END get_JSON_Obj;
/***************************************************************************************************

Get_Inputs: Gets the input JSON scenarios object from table, and converts it into a 4-level list of
  lists, with levels as follows:
  - Scenario
  - Group
  - Record
  - Field
Requires Oracle database 12.2 or higher

***************************************************************************************************/
FUNCTION Get_Inputs(
            p_package_nm                   VARCHAR2,        -- package name
            p_procedure_nm                 VARCHAR2)        -- procedure name
            RETURN                         scenarios_rec IS -- scenarios as 4-level list of lists, preceded by delim
  l_json_obj              JSON_Object_T;
  l_met_obj               JSON_Object_T;
  l_sce_obj               JSON_Object_T;
  l_rec_list              JSON_Array_T;
  l_keys                  JSON_Key_List;
  l_groups                JSON_Key_List;
  l_recs_2lis             L2_chr_arr := L2_chr_arr();
  l_grps_3lis             L3_chr_arr := L3_chr_arr();
  l_sces_4lis             L4_chr_arr := L4_chr_arr();
  l_delim                 VARCHAR2(10);
  l_scenarios             scenarios_rec;
  Invalid_JSON            EXCEPTION;
BEGIN

  l_json_obj := get_JSON_Obj(p_package_nm   => p_package_nm,
                             p_procedure_nm => p_procedure_nm);
  l_met_obj := l_json_obj.get_Object(META);
  l_delim := l_met_obj.get_String('delimiter');
  l_scenarios.delim := l_delim;
  l_sce_obj := l_json_obj.get_Object(SCENARIOS);
  l_keys := l_sce_obj.get_Keys;
  FOR i IN 1..l_keys.COUNT LOOP

    IF l_sce_obj.get_Object(l_keys(i)).get_String('active_yn') = 'N' THEN
      CONTINUE;
    END IF;

    l_sces_4lis.EXTEND;
    l_groups := l_sce_obj.get_Object(l_keys(i)).get_Object(INP).get_Keys;
    l_grps_3lis := L3_chr_arr();
    l_grps_3lis.EXTEND(l_groups.COUNT);
    FOR j IN 1..l_groups.COUNT LOOP

      l_rec_list := l_sce_obj.get_Object(l_keys(i)).get_Object(INP).get_Array(l_groups(j));
      l_recs_2lis := L2_chr_arr();
      l_recs_2lis.EXTEND(l_rec_list.get_Size);

      FOR k IN 0..l_rec_list.get_Size-1 LOOP
        l_recs_2lis(k + 1) := Utils.Split_Values(l_rec_list.get_String(k), Nvl(l_delim, Utils.DELIM));
      END LOOP;
      l_grps_3lis(j) := l_recs_2lis;

    END LOOP;
    l_sces_4lis(l_sces_4lis.COUNT) := l_grps_3lis;

  END LOOP;
  l_scenarios.scenarios_4lis := l_sces_4lis;
  RETURN l_scenarios;

END Get_Inputs;

/***************************************************************************************************

Set_Outputs: Gets the input JSON scenarios object from table, and converts it into a 3-level list of
  lists, with levels as follows:
  - Scenario
  - Group
  - Record (with fields as delimited strings)
Requires Oracle database 12.2 or higher

***************************************************************************************************/
PROCEDURE Set_Outputs(
            p_package_nm                   VARCHAR2,      -- package name
            p_procedure_nm                 VARCHAR2,      -- procedure name
            p_act_3lis                     L3_chr_arr) IS -- actuals as 3-level list of lists
  l_json_obj              JSON_Object_T;
  l_out_obj               JSON_Object_T := JSON_Object_T();
  l_scenarios_out_obj     JSON_Object_T := JSON_Object_T();
  l_out_sce_obj           JSON_Object_T;
  l_scenario_out_obj      JSON_Object_T;
  l_sce_obj               JSON_Object_T;
  l_result_obj            JSON_Object_T;
  l_grp_out_obj           JSON_Object_T;
  l_exp_list              JSON_Array_T;
  l_act_list              JSON_Array_T;
  l_scenarios             JSON_Key_List;
  l_groups                JSON_Key_List;
  l_out_clob              CLOB;
  i_act                   PLS_INTEGER := 0;

BEGIN

  l_json_obj := get_JSON_Obj(p_package_nm   => p_package_nm,
                             p_procedure_nm => p_procedure_nm);
  l_out_obj.put(META, l_json_obj.get_Object(META));
  l_sce_obj := l_json_obj.get_Object(SCENARIOS);
  l_scenarios := l_sce_obj.get_Keys;

  FOR i IN 1..l_scenarios.COUNT LOOP

    IF l_sce_obj.get_Object(l_scenarios(i)).get_String('active_yn') = 'N' THEN
      CONTINUE;
    END IF;

    i_act := i_act + 1;
    l_scenario_out_obj := JSON_Object_T();
    l_scenario_out_obj.put(INP, l_sce_obj.get_Object(l_scenarios(i)).get_Object(INP));
    l_groups := l_sce_obj.get_Object(l_scenarios(i)).get_Object(OUT).get_Keys;
    l_grp_out_obj := JSON_Object_T();
    FOR j IN 1..l_groups.COUNT LOOP

      l_exp_list := l_sce_obj.get_Object(l_scenarios(i)).get_Object(OUT).get_Array(l_groups(j));
      l_act_list := JSON_Array_T();
      IF p_act_3lis(i_act)(j) IS NOT NULL THEN

        FOR k IN 1..p_act_3lis(i_act)(j).COUNT LOOP
          l_act_list.Append(Nvl(p_act_3lis(i_act)(j)(k), ''));
        END LOOP;

      END IF;
      l_result_obj := JSON_Object_T();
      l_result_obj.Put(EXP, l_exp_list);
      l_result_obj.Put(ACT, l_act_list);
      l_grp_out_obj.Put(l_groups(j), l_result_obj);

    END LOOP;
    l_scenario_out_obj.put(OUT, l_grp_out_obj);
    l_scenarios_out_obj.put(l_scenarios(i), l_scenario_out_obj);

  END LOOP;
  l_out_obj.put(SCENARIOS, l_scenarios_out_obj);
  l_out_clob := l_out_obj.to_clob();

  UPDATE tt_units
     SET output_json    = l_out_clob
   WHERE package_nm     = p_package_nm
     AND procedure_nm   = p_procedure_nm;
  DBMS_XSLPROCESSOR.clob2file(l_out_clob, 'INPUT_DIR', Lower(p_package_nm || '.' || p_procedure_nm) || '_out.json');

END Set_Outputs;
/***************************************************************************************************

Add_Ttu: Add a record to tt_units, reading in input_json from JSON file

***************************************************************************************************/

PROCEDURE Add_Ttu(
            p_package_nm                   VARCHAR2,    -- test package name 
            p_procedure_nm                 VARCHAR2,    -- test procedure name 
            p_group_nm                     VARCHAR2,    -- test group
            p_active_yn                    VARCHAR2,    -- test active Y/N
            p_input_file                   VARCHAR2) IS -- input file name

  l_src_file      BFILE := BFileName('INPUT_DIR', p_input_file);
  l_dest_lob      CLOB;
  l_dest_offset   INTEGER := 1;
  l_src_offset    INTEGER := 1;
  l_lang_context  NUMBER := DBMS_LOB.Default_Lang_Ctx;
  l_warning       NUMBER;

BEGIN

  DBMS_LOB.CreateTemporary(l_dest_lob,true);

  DBMS_LOB.Open(l_src_file, DBMS_LOB.Lob_readonly);
  DBMS_LOB.LoadCLOBFromFile( 
              dest_lob     => l_dest_lob,
              src_bfile    => l_src_file,
              amount       => DBMS_LOB.LOBMAXSIZE,
              dest_offset  => l_dest_offset,
              src_offset   => l_src_offset,
              bfile_csid   => DBMS_LOB.Default_Csid,
              lang_context => l_lang_context,
              warning      => l_warning );


  MERGE INTO tt_units tgt
  USING (SELECT p_package_nm    package_nm, 
                p_procedure_nm  procedure_nm,
                p_group_nm      group_nm,
                p_active_yn     active_yn, 
                l_dest_lob      input_json 
           FROM DUAL) src
     ON (tgt.package_nm   = src.package_nm 
    AND  tgt.procedure_nm = src.procedure_nm)
  WHEN NOT MATCHED THEN
    INSERT (tgt.package_nm, tgt.procedure_nm, tgt.group_nm, tgt.active_yn, tgt.input_json)
    VALUES (src.package_nm, src.procedure_nm, src.group_nm, src.active_yn, src.input_json)
  WHEN MATCHED THEN
    UPDATE
       SET tgt.group_nm   = src.group_nm,
           tgt.active_yn  = src.active_yn,
           tgt.input_json = src.input_json;
  COMMIT;
  DBMS_LOB.FreeTemporary(l_dest_lob);
  DBMS_LOB.Close(l_src_file);

END Add_Ttu;

BEGIN

  DBMS_Session.Set_Context('TRAPIT_CTX', 'MODE', 'UT');
  DBMS_Session.Set_NLS('nls_date_format', '''DD-MON-YYYY''');--c_date_fmt); - constant did not work

END Trapit;
/
SHO ERR
CREATE OR REPLACE TRIGGER TRG_MANIPULACION_BOLETA
AFTER INSERT OR DELETE OR UPDATE OF MONTO_BOLETA ON BOLETA
FOR EACH ROW
--WHEN (NEW.MONTO_BOLETA > 0)
BEGIN

    IF INSERTING THEN
    
        INSERT INTO COMISION_VENTA (NRO_BOLETA, VALOR_COMISION)
        VALUES (:NEW.NRO_BOLETA, ROUND(:NEW.MONTO_BOLETA * 0.15));
    
    ELSIF UPDATING THEN
    
        IF (:NEW.MONTO_BOLETA > :OLD.MONTO_BOLETA) THEN
        
            UPDATE COMISION_VENTA SET valor_comision = ROUND(:NEW.MONTO_BOLETA * 0.15)
            WHERE nro_boleta = :NEW.NRO_BOLETA;
        
        END IF;
    
    ELSIF DELETING THEN
    
        DELETE FROM COMISION_VENTA WHERE NRO_BOLETA = :OLD.NRO_BOLETA;
    
    END IF;


END TRG_MANIPULACION_BOLETA;

CREATE OR REPLACE PACKAGE PKG_HABER_REMUN
IS

    v_asig_esp      NUMBER;
    PROCEDURE SP_INSERT_ERROR (p_sub_pro  VARCHAR2, p_msj_err  VARCHAR2);
    
END PKG_HABER_REMUN;

CREATE OR REPLACE PACKAGE BODY PKG_HABER_REMUN
IS

    PROCEDURE SP_INSERT_ERROR 
    (p_sub_pro  VARCHAR2, p_msj_err  VARCHAR2)
    IS
    BEGIN
        
        EXECUTE IMMEDIATE 'INSERT INTO error_calc_remun VALUES (:id_err,:subpro,:msjerr)'
        USING SEQ_ERROR.nextval,p_sub_pro,p_msj_err;                 
    
    END SP_INSERT_ERROR;


END PKG_HABER_REMUN;


CREATE OR REPLACE FUNCTION FN_OBTEN_PORC_ANIOS
(p_annios_emp  NUMBER) RETURN NUMBER
IS
    v_porc_bon  NUMBER;
    v_msj_err   VARCHAR2(200);
BEGIN
    EXECUTE IMMEDIATE 'SELECT porc_bonif FROM PORC_BONIF_ANNOS_CONTRATO
                        WHERE :ANNIOS BETWEEN ANNOS_INFERIOR AND ANNOS_SUPERIOR'
    INTO v_porc_bon USING p_annios_emp;

    RETURN v_porc_bon;
    
EXCEPTION
    WHEN OTHERS THEN
        v_msj_err :=SQLERRM;
        pkg_haber_remun.sp_insert_error('ERROR EN FN CALCULO PORCENTAJE BONIFICACION AÑOS CONTRATO',v_msj_err);
    
    RETURN 0;

END FN_OBTEN_PORC_ANIOS;


CREATE OR REPLACE FUNCTION FN_CALC_COM_VENTA
(p_id_emp NUMBER, p_mes NUMBER, p_annio NUMBER) RETURN NUMBER 
IS
    v_com_vta       NUMBER;
    v_msj_err   VARCHAR2(200);
BEGIN
    SELECT  NVL( SUM(c.valor_comision) , 0)
    INTO v_com_vta
    FROM comision_venta c  JOIN  boleta b
    ON c.nro_boleta = b.nro_boleta
    WHERE b.numrut_emp = p_id_emp AND 
    EXTRACT (MONTH FROM  b.fecha_boleta) = p_mes AND 
    EXTRACT (YEAR FROM  b.fecha_boleta ) = p_annio ;

    RETURN v_com_vta;
    
EXCEPTION
    WHEN OTHERS THEN
        v_msj_err :=SQLERRM;
        pkg_haber_remun.sp_insert_error('ERROR EN FN CALCULO COMISION VENTAS',v_msj_err);
    
    RETURN 0;

END FN_CALC_COM_VENTA;



CREATE OR REPLACE PROCEDURE SP_PRINCIPAL
(p_mes NUMBER, p_anio NUMBER) AUTHID CURRENT_USER
IS

-- DECLARACION DE CURSORES
    CURSOR C_EMPLEADO IS
        SELECT numrut_emp, sueldo_base_emp, fecing_emp,
        ROUND(MONTHS_BETWEEN(SYSDATE,fecing_emp)/12) ANNIOS
        FROM empleado;
-- DECLARACION DE VARIABLES
    v_filas     NUMBER :=0;
    v_msj_err   VARCHAR2(200);
BEGIN

    BEGIN
        SELECT COUNT(*)
        INTO  v_filas
        FROM USER_OBJECTS
        WHERE OBJECT_NAME = 'HABERES_'||p_anio||'_'||p_mes;
        
        IF v_filas > 0 THEN
    
            EXECUTE IMMEDIATE 'TRUNCATE TABLE HABERES_'||p_anio||'_'||p_mes;
        
        ELSE
        
            EXECUTE IMMEDIATE 'CREATE TABLE HABERES_'||p_anio||'_'||p_mes||' AS SELECT * FROM HABER_CALC_MES';
            
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            v_msj_err :=SQLERRM;
            pkg_haber_remun.sp_insert_error('ERROR AL CREAR LA TABLA HABERES DEL PERIODO',v_msj_err);

    END; 
    
    BEGIN
        SELECT COUNT(*)
        INTO  v_filas
        FROM USER_OBJECTS
        WHERE OBJECT_NAME = 'SEQ_ERROR';
    
        IF v_filas > 0 THEN    
    
            EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_ERROR';
            EXECUTE IMMEDIATE 'CREATE SEQUENCE SEQ_ERROR';
        ELSE
        
            EXECUTE IMMEDIATE 'CREATE SEQUENCE SEQ_ERROR';
        
        END IF;
        
    EXCEPTION
        WHEN OTHERS THEN
            v_msj_err :=SQLERRM;
            pkg_haber_remun.sp_insert_error('ERROR EL REINICIAR SECUENCIA',v_msj_err);


    END;
    
    FOR REG_EMP IN C_EMPLEADO LOOP
    
        DBMS_OUTPUT.PUT_LINE('EMPLEADO '||REG_EMP.NUMRUT_EMP||' PORCENTAJE DE AÑOS '||to_char(fn_obten_porc_anios(REG_EMP.ANNIOS)));
    
    END LOOP;
    
    
EXCEPTION
    WHEN OTHERS THEN
        v_msj_err :=SQLERRM;
        pkg_haber_remun.sp_insert_error('ERROR EN SP PRINCIPAL',v_msj_err);

END SP_PRINCIPAL;



alter table error_calc_remun drop constraint PK_ERROR_CALC_REMUN;


EXEC SP_PRINCIPAL(&MES,&ANIO);

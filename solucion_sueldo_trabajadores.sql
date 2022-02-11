-- DECLARACION DE VARIABLES BIND O HOST O EXTERNAS
VARIABLE b_mes   NUMBER;
VARIABLE b_annio NUMBER;
-- ASIGNAR VALORES PARA EL PERIODO A PROCESAR EN VARIABLES BIND
EXEC    :b_mes := &mes;
EXEC    :b_annio := &annio;

DECLARE
-- DECLARACION DE CURSORES
    CURSOR C_VEND IS
        SELECT numrut_vend, sueldo_base_vend, fecing_vend,
        ROUND(MONTHS_BETWEEN(SYSDATE,fecing_vend)/12) ANNIOS
        FROM vendedor
        ORDER BY numrut_vend;
        
-- DECLARACION DE VARIABLES
    v_msg_err       VARCHAR2(200);
    v_tot_haberes   NUMBER :=0;
    v_num_carga     NUMBER :=0;
    v_com_vta       NUMBER :=0;
    v_val_cf        NUMBER :=0;
    v_val_mov       NUMBER :=0;
    v_asig_annios   NUMBER :=0;
    v_mes           NUMBER;
    v_anio          NUMBER;
    
-- DECLARACION DE CONSTANTES
    c_asi_fam       NUMBER :=3800;
    c_colacion      NUMBER :=30000;
    c_porc_mov      NUMBER :=0.156;
    
BEGIN    
-- LIMPIAR LA TABLA HABERES ANTES DEL PROCESO    
    DELETE FROM haberes_periodo;
    
-- INICIO DEL PROCESO CON CURSOR PRINCIPAL VENDEDOR
    FOR REG_VEND IN C_VEND LOOP

-- APLICAMOS REGLA DE NEGOCIO 1 CALCULO DE VALOR CARGA FAMILIAR
        BEGIN
            SELECT COUNT( DISTINCT numrut_carga)
            INTO v_num_carga
            FROM carga_familiar
            WHERE numrut_vend = REG_VEND.numrut_vend;
-- MANEJO ERROR CALCULO ASIGNACION CARGA FAMILIAR
        EXCEPTION
            WHEN OTHERS THEN
                v_num_carga := 0;
                v_msg_err := SQLERRM; --ERROR DEL SERVER ORACLE
                INSERT INTO tabla_de_errores 
                VALUES (SEQ_ERROR.nextval,'ERROR EN CALCULO DE ASIGNACION CARGA FAMILIAR, RUT CON PROBLEMA: '||REG_VEND.numrut_vend,v_msg_err);                 
        END;
-- VALOR CARGA FAMILIAR        
        v_val_cf := v_num_carga * c_asi_fam;

-- APLICAMOS REGLA DE NEGOCIO 3 CALCULO VALOR TOTAL COMISION VENTA TICKET DEL PERIODO
        BEGIN
            SELECT  NVL( SUM(c.valor_comision) , 0)
            INTO v_com_vta
            FROM com_venta_ticket c  JOIN  venta_tickets v
            ON c.nro_ticket = v.nro_ticket
            WHERE v.numrut_vend = REG_VEND.numrut_vend AND 
            EXTRACT (MONTH FROM  v.fecha_ticket) = :b_mes AND 
            EXTRACT (YEAR FROM  v.fecha_ticket ) = :b_annio ;
-- MANEJO ERROR CALCULO COMISION VENTA
        EXCEPTION
            WHEN OTHERS THEN
                v_com_vta := 0;
                v_msg_err := SQLERRM; --ERROR DEL SERVER ORACLE
                INSERT INTO tabla_de_errores 
                VALUES (SEQ_ERROR.nextval,'ERROR EN CALCULO DE COMISION VENTA, RUT CON PROBLEMA: '||REG_VEND.numrut_vend,v_msg_err);                
        END;     
        
-- APLICAMOS REGLA DE NEGOCIO 4 CALCULO VALOR MOVILIZACION        
        v_val_mov := (REG_VEND.sueldo_base_vend + v_com_vta) * c_porc_mov;
       
-- APLICAMOS LA REGLA DE NEGOCIO 5 CALCULO ASIGNACION POR AÑOS DE SERVICIO
        BEGIN            
            SELECT ROUND( porcentaje * REG_VEND.sueldo_base_vend )
            INTO v_asig_annios
            FROM bono_antiguedad
            WHERE REG_VEND.ANNIOS BETWEEN LIMITE_INFERIOR AND limite_superior;
-- MANEJO DE ERROR EN CLACULO DE BONO ANTIGUEDAD       
        EXCEPTION
            WHEN OTHERS THEN
                v_asig_annios := 0;
                v_msg_err := SQLERRM; --ERROR DEL SERVER ORACLE
                INSERT INTO tabla_de_errores 
                VALUES (SEQ_ERROR.nextval,'ERROR EN CALCULO BONO ANTIGUEDAD, RUT CON PROBLEMA: '||REG_VEND.numrut_vend,v_msg_err);
        END;    

-- CALCULO DEL TOTAL DE HABERES PARA EL VENDEDOR EN EL PERIODO   
        v_tot_haberes := REG_VEND.sueldo_base_vend + v_asig_annios + v_val_cf + v_val_mov + c_colacion + v_com_vta;

-- SENTENCIA INSERT QUE INGRESA LOS VALORES A LA TABLA HABERES_PERIODO        
        DECLARE
        -- DECLARACION DE EXCEPCIONES
            NO_ROWS_INSERT        EXCEPTION;
        
        BEGIN        
            INSERT INTO haberes_periodo
            VALUES (REG_VEND.numrut_vend,:b_mes,:b_annio,REG_VEND.sueldo_base_vend,v_asig_annios,v_val_cf,v_val_mov,c_colacion,v_com_vta,v_tot_haberes);
        
            IF SQL%NOTFOUND THEN
            
                RAISE NO_ROWS_INSERT;
                
            END IF;
-- MANEJO DE ERROR EN EL INGRESO DE HABERES DEL PERIODO      
        EXCEPTION
            WHEN NO_ROWS_INSERT THEN
                v_msg_err := SQLERRM; --ERROR DEL SERVER ORACLE
                INSERT INTO tabla_de_errores 
                VALUES (SEQ_ERROR.nextval,'ERROR AL INGRESAR HABERES, RUT CON PROBLEMA: '||REG_VEND.numrut_vend,v_msg_err);              
        END;    
    END LOOP;    
EXCEPTION
    WHEN OTHERS THEN
        v_msg_err := SQLERRM;
        INSERT INTO TABLA_DE_ERRORES
        VALUES(SEQ_ERROR.NEXTVAL,'ERROR EN BLOQUE PRINCIPAL',v_msg_err);
END;







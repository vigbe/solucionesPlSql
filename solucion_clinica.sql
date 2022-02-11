
-- DECLARACION DE LA VARIABLE BIND
VARIABLE b_cant_cirugias_act NUMBER;
VARIABLE b_porc_iva NUMBER;
VARIABLE b_porc_dcto_stgo NUMBER;
VARIABLE b_porc_dcto_nunoa NUMBER;
VARIABLE b_porc_dcto_dia NUMBER;
VARIABLE b_porc_cargo_dom NUMBER;
VARIABLE b_porc_cargo_sab NUMBER;
VARIABLE b_perio_dcto VARCHAR2;


EXEC :b_porc_iva := 19;
EXEC :b_porc_dcto_dia := 5;
EXEC :b_porc_dcto_stgo := 5;
EXEC :b_porc_dcto_nunoa := 3;
EXEC :b_porc_cargo_dom := 10;
EXEC :b_porc_cargo_sab := 5;
EXEC :b_perio_dcto := '05/2015';


DECLARE
-- DECLARACION DE VARIABLES LOCALES DEL BLOQUE

    v_desc_old      cirugias.descuento%TYPE;
    v_total_old     cirugias.total%TYPE;
    v_iva_old       cirugias.iva%TYPE;
    v_neto_old      cirugias.neto%TYPE;
    v_pordesc       descuento.porc_desc%TYPE;
    v_nomdia        VARCHAR2(20); 
    v_periodo       VARCHAR2(10);
    v_descuento     cirugias.descuento%TYPE;
    v_total         cirugias.total%TYPE;
    v_iva           cirugias.iva%TYPE;
    v_valneto       cirugias.neto%TYPE;
    v_fol_min       cirugias.folio%TYPE;
    v_fol_max       cirugias.folio%TYPE;
    v_nom_centro    centro_med.nombre%TYPE;
    v_nom_suc       sucursal.nombre_suc%TYPE;
    v_valneto_new   cirugias.neto%TYPE;

    
BEGIN
-- INICIO DEL BLOQUE DE EJECUCION    

-- CONSULTA PARA OBTENER LOS VALORES MAXIMOS Y MINIMOS DE LAS CIRUGIAS PARA USAR EN EL CICLO FOR
    SELECT MIN(folio), MAX(folio)
    INTO v_fol_min, v_fol_max
    FROM cirugias;
-- INICIALIZACION DE LA VARIABLE BIND PARA UTILIZAR EN EL CONTEO DE CIRUGIAS QUE SE ACTUALIZAN
    :b_cant_cirugias_act := 0;
-- INICIO DEL CICLO FOR PARA RECORRER TODAS LAS CIRUGIAS
    FOR j IN v_fol_min .. v_fol_max LOOP
-- CONSULTA PARA OBTENER LOS VALORES ACTUALES DE LA TABLA CIRUGIAS    
        SELECT descuento, total, iva, neto
        INTO v_desc_old, v_total_old, v_iva_old, v_neto_old
        FROM cirugias
        WHERE folio = j;
-- CONSULTA PARA REALIZAR LA SUMATORIA DE TODOS LOS SERVICIOS ASOCIADOS A LA CIRUGIA    
        SELECT SUM(s.precio)
        INTO v_valneto
        FROM cirugias c JOIN det_servicio d
        ON c.folio = d.folio
        JOIN servicio s
        ON s.codigo_serv = d.codigo_serv
        WHERE c.folio = j
        GROUP BY c.folio;
-- AQUI SE APLICA LA REGLA 1,OBTENER EL PORCENTAJE DE DESCUENTO SEGUN EL MONTO NETO DE LA CIRUGIA EN TABLA DESCUENTO       
        SELECT porc_desc  
        INTO v_pordesc
        FROM descuento
        WHERE v_valneto BETWEEN valor_ini AND valor_fin;
-- CONSULTA PARA OBTENER EL DIA Y PERIODO SEGUN FECHA DE LA CIRUGIA        
        SELECT RTRIM(TO_CHAR(fecha_operacion,'DAY')), TO_CHAR(fecha_operacion,'mm/yyyy')
        INTO v_nomdia, v_periodo
        FROM cirugias
        WHERE folio = j;
-- CONSULTA PARA OBTENER EL NOMBRE DEL CENTRO MEDICO DONDE SE REALIZA LA CIRUGIA       
        SELECT cm.nombre
        INTO    v_nom_centro
        FROM cirugias c join medico m
        ON c.id_medico = m.id_medico
        JOIN sucursal s
        ON m.codigo_suc = s.codigo_suc
        JOIN centro_med cm
        ON s.cod_centro = cm.cod_centro
        WHERE c.folio = j;
-- AQUI SE APLICA LA REGA DE NEGOCIO 2        
        IF v_pordesc = 0 AND UPPER(v_nomdia) IN ('MARTES','JUEVES') THEN
        
            v_pordesc := v_pordesc + :b_porc_dcto_dia;
            
        END IF;
-- AQUI SE APLICA LA REGLA DE NEGOCIO 3        
        IF v_pordesc > 20 THEN 
        
            IF UPPER(v_nomdia) = 'DOMINGO' THEN
            
                v_pordesc := v_pordesc - :b_porc_cargo_dom;

            ELSIF UPPER(v_nomdia) = 'SÁBADO' THEN
            
                v_pordesc := v_pordesc - :b_porc_cargo_sab;

            END IF;
            
        END IF;
-- AQUI SE APLICA LA REGLA DE NEGOCIO 4 
-- SE RECUPERA NOMBRE SUCURSAL DE CENTRO MEDICO
        SELECT s.nombre_suc
        INTO    v_nom_suc
        FROM cirugias c join medico m
        ON c.id_medico = m.id_medico
        JOIN sucursal s
        ON m.codigo_suc = s.codigo_suc
        WHERE c.folio = j;

        IF v_periodo = :b_perio_dcto THEN 
        
            IF UPPER(v_nom_suc) = 'ÑUÑOA' THEN
            
                v_pordesc := v_pordesc + :b_porc_dcto_nunoa;
          
            ELSIF UPPER(v_nom_suc) = 'SANTIAGO' THEN
            
                v_pordesc := v_pordesc + :b_porc_dcto_stgo;
            
            END IF;
            
        END IF;
-- AQUI SE REALIZAN LOS CALCULOS DE LOS NUEVOS VALORES        
        v_descuento := ROUND(v_valneto *(v_pordesc/100));
        v_valneto_new := ROUND(v_valneto - v_descuento);
        v_iva := ROUND(v_valneto_new * (:b_porc_iva/100));
        v_total := ROUND(v_valneto_new + v_iva);
-- AQUI SE VERIFICA SI HAY DIFERENCIA ENTRE LOS VALORES ACTUALES Y LOS NUEVOS VALORES EN LA TABLA CIRUGIAS        
        IF (v_desc_old != v_descuento) OR (v_neto_old != v_valneto_new) OR (v_iva_old != v_iva) OR (v_total_old != v_total) THEN

            UPDATE cirugias  SET descuento = v_descuento, neto = v_valneto_new, 
                                iva = v_iva, total = v_total
            WHERE folio = j;
        
           -- COMMIT;
-- AQUI SE GENERA LA SALIDA DBMS DEL VOUCHER RECALCULADO        
            DBMS_OUTPUT.put_line(LPAD('VOUCHER DE CIRUGIA Nº '||j||' ACTUALIZADO',63,'-')||RPAD('-',30,'-'));

        
            DBMS_OUTPUT.put_line(RPAD('** LA CIRUGIA FUE REALIZADA UN DIA: ',60,'_')||v_nomdia);
            DBMS_OUTPUT.put_line(RPAD('** SE ATENDIO EN EL CENTRO MEDICO: ',60,'_')||v_nom_centro);
            DBMS_OUTPUT.put_line(RPAD('** EL VALOR NETO SIN DESCUENTOS ES: ',60,'_')||v_valneto);
            DBMS_OUTPUT.put_line(RPAD('** EL PORCENTAJE DE DESCUENTO A APLICAR ES: ',60,'_')||v_pordesc||'%');
            DBMS_OUTPUT.put_line(RPAD('** EL MONTO A DESCONTAR ES DE: ',60,'_')||v_descuento);
            DBMS_OUTPUT.put_line(RPAD('** EL VALOR NETO APLICADO EL DESCUENTO ES: ',60,'_')||v_valneto_new);
            DBMS_OUTPUT.put_line(RPAD('** EL VALOR IVA: ',60,'_')||v_iva);
            DBMS_OUTPUT.put_line(RPAD('** EL VALOR TOTAL ACTUALIZADO A PAGAR ES: ',60,'_')||v_total);
            DBMS_OUTPUT.put_line(LPAD('-',93,'-'));
-- AQUI SE CONTABILIZAN LAS MANTENCIONES ACTUALIZADAS            
            :b_cant_cirugias_act := :b_cant_cirugias_act + 1;
            
        END IF;
        
    END LOOP;
-- AQUI SE VALIDA SI HAY ACTUALIZACIONES Y SE PRESENTA UN MENSAJE EN LA SALIDA DBMS    
    IF :b_cant_cirugias_act != 0 THEN
    
        DBMS_OUTPUT.PUT_LINE('SE REALIZARON '||:b_cant_cirugias_act||' ACTUALIZACIONES');
    ELSE
        DBMS_OUTPUT.PUT_LINE('NO SE REALIZARON ACTUALIZACIONES');
    END IF;
--EXCEPTION


END;
/
-- SE FINALIZA EL BLOQUE

-- AQUI SE IMPRIME EL NUMERO DE ACTUALIZACIONES EN LA SALIDA SCRIPT FUERA DEL BLOQUE CON EL VALOR DE LA VARIABLE BIND
PRINT b_cant_cirugias_act
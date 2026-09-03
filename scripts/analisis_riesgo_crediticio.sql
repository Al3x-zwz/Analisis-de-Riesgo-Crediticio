-- Verificar valores faltantes en la tabla principal --
SELECT COUNT(*) AS MissingValues
FROM TB_CLIENTE_RIESGO
WHERE ACC_NO IS NULL;

-- Eliminar las filas nulas importadas del archivo CSV --
DELETE FROM TB_CLIENTE_RIESGO
WHERE ACC_NO IS NULL;

-- Verificar valores duplicados en el número de cuenta del cliente --
SELECT ACC_NO, COUNT(*) AS Frecuencia
FROM TB_CLIENTE_RIESGO
GROUP BY ACC_NO
HAVING COUNT(*) > 1;

-- 1. Distribución de Cartera: Volumen, saldo promedio y cantidad de créditos por tipo de cliente
SELECT 
    CLIENT_TYPE AS Tipo_Cliente,
    COUNT(ACC_NO) AS Cantidad_Prestamos,
    SUM(INVESTMENT_TOTAL) AS Volumen_Invertido_Total,
    ROUND(AVG(ACCCURRENTBALANCE), 2) AS Saldo_Actual_Promedio
FROM TB_CLIENTE_RIESGO
WHERE CLIENT_TYPE IS NOT NULL AND CLIENT_TYPE <> '0'
GROUP BY CLIENT_TYPE
ORDER BY Volumen_Invertido_Total DESC;


-- 2. Estado Civil y Riesgo: Volumen de créditos y tasa de morosidad por estado civil
SELECT 
    INF_MARITAL_STATUS AS Estado_Civil,
    COUNT(ACC_NO) AS Total_Prestamos,
    SUM(CASE WHEN QUALITY_OF_LOAN = 'B' THEN 1 ELSE 0 END) AS Prestamos_Mora,
    CAST((SUM(CASE WHEN QUALITY_OF_LOAN = 'B' THEN 1.0 ELSE 0 END) * 100.0) / COUNT(ACC_NO) AS DECIMAL(5, 2)) AS Tasa_Morosidad_Pct
FROM TB_CLIENTE_RIESGO
WHERE INF_MARITAL_STATUS IS NOT NULL
GROUP BY INF_MARITAL_STATUS
ORDER BY Tasa_Morosidad_Pct DESC;


-- 3. Top 5 Deudores: Clientes en mora con el mayor monto adeudado
SELECT TOP 5
    ACC_NO AS Numero_Cuenta,
    CLIENT_TYPE AS Tipo_Cliente,
    INF_MARITAL_STATUS AS Estado_Civil,
    INVESTMENT_TOTAL AS Monto_Prestamo,
    ACCCURRENTBALANCE AS Saldo_Actual,
    DUE_PAYMENT AS Monto_Atrasado,
    QUALITY_OF_LOAN AS Calificacion
FROM TB_CLIENTE_RIESGO
WHERE QUALITY_OF_LOAN = 'B'
ORDER BY DUE_PAYMENT DESC;


-- 4. Impacto de Cuotas: Segmentación por tamaño de cuota y tasa de morosidad
SELECT 
    CASE 
        WHEN INSTALL_SIZE = 0 THEN '0. Sin Cuota Fija'
        WHEN INSTALL_SIZE BETWEEN 0.01 AND 5000 THEN '1. Cuota Baja (<= 5K)'
        WHEN INSTALL_SIZE BETWEEN 5000.01 AND 20000 THEN '2. Cuota Media (5K - 20K)'
        ELSE '3. Cuota Alta (> 20K)'
    END AS Rango_Cuota,
    COUNT(ACC_NO) AS Total_Creditos,
    SUM(CASE WHEN QUALITY_OF_LOAN = 'B' THEN 1 ELSE 0 END) AS Creditos_Mora,
    CAST((SUM(CASE WHEN QUALITY_OF_LOAN = 'B' THEN 1.0 ELSE 0 END) * 100.0) / COUNT(ACC_NO) AS DECIMAL(5, 2)) AS Tasa_Morosidad_Pct
FROM TB_CLIENTE_RIESGO
WHERE INSTALL_SIZE IS NOT NULL
GROUP BY 
    CASE 
        WHEN INSTALL_SIZE = 0 THEN '0. Sin Cuota Fija'
        WHEN INSTALL_SIZE BETWEEN 0.01 AND 5000 THEN '1. Cuota Baja (<= 5K)'
        WHEN INSTALL_SIZE BETWEEN 5000.01 AND 20000 THEN '2. Cuota Media (5K - 20K)'
        ELSE '3. Cuota Alta (> 20K)'
    END
ORDER BY Rango_Cuota;


-- 5. Penalidad y Género: Total de pagos atrasados para clientes con compensación
SELECT 
    INF_GENDER AS Genero,
    COUNT(ACC_NO) AS Clientes_Penalizados,
    SUM(DUE_PAYMENT) AS Total_Pagos_Atrasados
FROM TB_CLIENTE_RIESGO
WHERE COMPENSATION_CHARGED = 'Y' 
  AND INF_GENDER IS NOT NULL
GROUP BY INF_GENDER
ORDER BY Total_Pagos_Atrasados DESC;


-- 6. Detección de Anomalías: Clientes con saldo actual mayor a la inversión inicial
SELECT 
    COUNT(ACC_NO) AS Clientes_Con_Anomalia,
    SUM(INVESTMENT_TOTAL) AS Inversion_Original_Total,
    SUM(ACCCURRENTBALANCE) AS Saldo_Actual_Total,
    SUM(ACCCURRENTBALANCE - INVESTMENT_TOTAL) AS Diferencia_Excedente
FROM TB_CLIENTE_RIESGO
WHERE ACCCURRENTBALANCE > INVESTMENT_TOTAL;


-- 7. Impacto del Riesgo: Clientes morosos ('B') con deuda superior al promedio general
SELECT 
    COUNT(ACC_NO) AS Morosos_Criticos,
    ROUND(AVG(DUE_PAYMENT), 2) AS Promedio_Atraso_De_Este_Grupo,
    ROUND((SELECT AVG(DUE_PAYMENT) FROM TB_CLIENTE_RIESGO), 2) AS Promedio_Atraso_Global
FROM TB_CLIENTE_RIESGO
WHERE QUALITY_OF_LOAN = 'B' 
  AND DUE_PAYMENT > (SELECT AVG(DUE_PAYMENT) FROM TB_CLIENTE_RIESGO);


  -- 8. Análisis de Mora (CTE): Promedio de cuota en el sector rural por modo de pago
WITH Clientes_Rurales AS (
    SELECT 
        ACC_NO,
        REPAY_MODE,
        INSTALL_SIZE
    FROM TB_CLIENTE_RIESGO
    WHERE CLIENT_TYPE = 'Rural' 
      AND INSTALL_SIZE IS NOT NULL
)
SELECT 
    REPAY_MODE AS Modo_Pago,
    COUNT(ACC_NO) AS Total_Clientes_Rurales,
    ROUND(AVG(INSTALL_SIZE), 2) AS Promedio_Cuota
FROM Clientes_Rurales
GROUP BY REPAY_MODE
ORDER BY Promedio_Cuota DESC;


-- 9. Ranking de Deudores Críticos: Top de clientes con mayor atraso por segmento
SELECT 
    CLIENT_TYPE AS Tipo_Cliente,
    ACC_NO AS Numero_Cuenta,
    DUE_PAYMENT AS Monto_Atrasado,
    ROW_NUMBER() OVER (PARTITION BY CLIENT_TYPE ORDER BY DUE_PAYMENT DESC) AS Ranking_Riesgo
FROM TB_CLIENTE_RIESGO
WHERE DUE_PAYMENT > 0
  AND CLIENT_TYPE IS NOT NULL 
  AND CLIENT_TYPE <> '0'
ORDER BY Tipo_Cliente, Ranking_Riesgo;


-- 10. Acumulado de Inversión en Riesgo (Running Total para préstamos malos)
SELECT 
    ACC_NO AS Numero_Cuenta,
    CLIENT_TYPE AS Tipo_Cliente,
    ACCCURRENTBALANCE AS Saldo_Actual,
    INVESTMENT_TOTAL AS Inversion_Original,
    SUM(INVESTMENT_TOTAL) OVER (ORDER BY ACCCURRENTBALANCE DESC) AS Inversion_Acumulada_Riesgo
FROM TB_CLIENTE_RIESGO
WHERE QUALITY_OF_LOAN = 'B'
ORDER BY Saldo_Actual DESC;
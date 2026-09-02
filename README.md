
# Proyecto SQL: Análisis de Riesgo Crediticio y Morosidad

![Banner Riesgo Crediticio](images/Banner%20riesgo%20Crediticio.jpg)

## Resumen (Overview)

El departamento de Riesgos de una institución financiera busca optimizar su política de originación y cobranzas. Sin embargo, carecían de una visión granular sobre cómo interactúan las variables demográficas y los términos de los préstamos con la probabilidad de incumplimiento (*default*). Mi objetivo en este proyecto es utilizar **SQL** dentro de **SQL Server Management Studio (SSMS)** para auditar la integridad de la base de datos, estructurar consultas financieras complejas y extraer *insights* estratégicos que permitan mitigar la severidad de pérdida (*Loss Given Default*) y focalizar los esfuerzos de recuperación de cartera.

---

## Estructura del Proyecto

* [Sobre los Datos](#sobre-los-datos)
* [Tareas (Task)](#tareas-task)
* [Limpieza de Datos](#limpieza-de-datos)
* [Análisis Exploratorio de Datos e Insights](#análisis-exploratorio-de-datos-eda-e-insights)

---

## Sobre los Datos

Los datos originales simulan el *core* bancario de una entidad financiera, consolidando información demográfica (estado civil, género, ubicación) y métricas financieras (monto de inversión, tamaño de cuota, saldos actuales y pagos en mora) de miles de clientes.

![Muestra de la base de datos](images/imagetop5.png)

---

## Tareas (Task)

En este análisis, resolvemos 10 preguntas de negocio de dificultad progresiva (aplicando desde agregaciones básicas hasta *Window Functions*) para evaluar el riesgo de la cartera:

1. **Distribución de Cartera:** ¿Cuál es el volumen total invertido y el saldo promedio según el tipo de cliente?
2. **Estado Civil y Riesgo:** ¿Cuál es la cantidad total de préstamos y cuántos de ellos están clasificados como malos agrupados por estado civil?
3. **Top 5 Deudores:** ¿Quiénes son los 5 clientes con el mayor pago atrasado que tienen una mala calificación crediticia?
4. **Impacto de Cuotas (Bandas):** ¿Cómo varía la calidad del préstamo si clasificamos el tamaño de la cuota en rangos personalizados?
5. **Penalidad y Género:** ¿Cuál es la suma total de pagos atrasados agrupada por género para clientes con compensación cobrada?
6. **Detección de Anomalías:** ¿Cuántos clientes presentan un saldo actual que supera su préstamo inicial?
7. **Impacto del Riesgo (Subconsultas):** ¿Los clientes en mora tienen un pago atrasado superior al promedio general de toda la cartera?
8. **Análisis de Mora (CTE):** ¿Cuál es el promedio de cuota en el sector rural según su modo de pago?
9. **Ranking de Deudores Críticos:** Generar un ranking de los prestatarios con mayor deuda dentro de cada tipo de cliente.
10. **Acumulado de Inversión en Riesgo (Running Total):** ¿Cuál es la evolución del monto total invertido acumulado para los préstamos malos?

---

## Limpieza de Datos

Antes de realizar el análisis, es fundamental asegurar la consistencia de los datos. El trabajo se centró en la validación de la tabla `TB_CLIENTE_RIESGO`, limpiando las filas vacías generadas durante la importación del archivo plano (CSV) y validando la unicidad de las cuentas.

**Valores Nulos o Faltantes:**
Se identificaron y eliminaron filas donde el identificador único (`ACC_NO`) era nulo para evitar sesgos en el cálculo de provisiones.

```sql
-- Verificar valores faltantes en la tabla principal
SELECT COUNT(*) AS MissingValues
FROM TB_CLIENTE_RIESGO
WHERE ACC_NO IS NULL;

-- Eliminar las filas nulas importadas del archivo CSV
DELETE FROM TB_CLIENTE_RIESGO
WHERE ACC_NO IS NULL;
```

##  Análisis Exploratorio de Datos (EDA) e Insights

### Pregunta #1: ¿Cuál es el volumen total invertido y el saldo promedio según el tipo de cliente?

Encontré la distribución de la cartera utilizando las funciones de agregación `SUM`, `AVG` y `COUNT`, agrupando los resultados con `GROUP BY`. Dado que arrastrábamos valores nulos de la importación, utilicé la cláusula `WHERE` para limpiar el campo categórico antes del cálculo.

```sql
-- Distribución de Cartera: Volumen, saldo promedio y cantidad de créditos --

SELECT 
    CLIENT_TYPE AS Tipo_Cliente,
    COUNT(ACC_NO) AS Cantidad_Prestamos,
    SUM(INVESTMENT_TOTAL) AS Volumen_Invertido_Total,
    ROUND(AVG(ACCCURRENTBALANCE), 2) AS Saldo_Actual_Promedio
FROM TB_CLIENTE_RIESGO
WHERE CLIENT_TYPE IS NOT NULL AND CLIENT_TYPE <> '0'
GROUP BY CLIENT_TYPE
ORDER BY Volumen_Invertido_Total DESC;
```

![Resultados Pregunta 1](images/image.png)


*Volumen invertido y saldo actual promedio segmentado por zona*

El análisis revela una altísima concentración de la cartera en el sector Rural, el cual representa el núcleo duro del negocio con más de 26,000 préstamos activos y el mayor volumen de capital invertido.

Sin embargo, es vital monitorear este segmento de cerca, ya que también presenta el saldo actual promedio más alto (1.29 millones) en comparación con los sectores Urbano y Semi-urbano, lo que indica una exposición significativamente mayor al riesgo crediticio en estas zonas.

## Pregunta #2: ¿Cuál es la cantidad total de préstamos y la tasa de morosidad por estado civil?
Para calcular el índice de default exacto, utilicé un conteo condicional anidando la función CASE WHEN dentro de un SUM. Además, apliqué la función CAST transformando el resultado a DECIMAL(5, 2) para asegurar que la tasa porcentual se visualice de forma limpia con dos decimales.

```sql
-- Volumen de créditos y tasa de morosidad por estado civil --

SELECT 
    INF_MARITAL_STATUS AS Estado_Civil,
    COUNT(ACC_NO) AS Total_Prestamos,
    SUM(CASE WHEN QUALITY_OF_LOAN = 'B' THEN 1 ELSE 0 END) AS Prestamos_Mora,
    CAST((SUM(CASE WHEN QUALITY_OF_LOAN = 'B' THEN 1.0 ELSE 0 END) * 100.0) / COUNT(ACC_NO) AS DECIMAL(5, 2)) AS Tasa_Morosidad_Pct
FROM TB_CLIENTE_RIESGO
WHERE INF_MARITAL_STATUS IS NOT NULL
GROUP BY INF_MARITAL_STATUS
ORDER BY Tasa_Morosidad_Pct DESC;
```
![Resultados Pregunta 2](images/image2.png)

*Tasa de morosidad porcentual por categoría de estado civil*

El segmento M (Casados) concentra la gran mayoría de la cartera con 35,412 préstamos y presenta la tasa de morosidad más alta de la tabla con un 11.23%, registrando casi 4,000 créditos en estado crítico.

En contraste, el segmento U (Solteros) muestra un índice de impago menor (9.02%). Esto evidencia estadísticamente que el mayor volumen de pérdida crediticia esperada para la entidad se concentra de forma desproporcionada en los prestatarios casados.

### Pregunta #3: ¿Quiénes son los 5 clientes con el mayor pago atrasado en mala calificación?

Para identificar a los mayores deudores de la cartera, utilicé la cláusula `TOP 5` combinada con un ordenamiento descendente (`ORDER BY DESC`). Filtré específicamente a aquellos clientes con calificación crediticia 'B' (en mora) para aislar el riesgo real.

```sql
-- Top 5 Deudores: Clientes en mora con el mayor monto adeudado --

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
```

![Resultados Pregunta 3](images/image3.png)

*Identificación nominal de los 5 mayores prestatarios en mora*

Los 5 principales deudores en mora pertenecen en su totalidad al segmento Rural y al estado civil Casado (M), encabezados por un cliente que registra un monto atrasado superior a los 155 millones.

Esta coincidencia demográfica en los casos más extremos confirma que el riesgo de severidad de pérdida (Loss Given Default - LGD) está altamente concentrado. Este grupo requiere planes de reestructuración y cobranza judicial prioritaria para contener el deterioro de provisiones.

## Pregunta #4: ¿Cómo varía la calidad del préstamo según rangos del tamaño de cuota?
El objetivo de esta consulta fue transformar un dato continuo (monto de la cuota) en dimensiones categóricas. Utilicé la sentencia CASE WHEN para crear rangos personalizados ("Bandas") y anidé un conteo condicional para obtener la tasa de morosidad exacta por cada nivel de exigencia de pago.

```sql
-- Impacto de Cuotas: Segmentación por tamaño de cuota y tasa de morosidad --

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
```
![Resultados Pregunta 4](images/image4.png)

*Porcentaje de morosidad distribuido por exigencia de pago mensual*

El análisis revela un riesgo concentrado en dos perfiles opuestos. El grueso de la cartera (más de 30,000 créditos) cae en la categoría "Sin Cuota Fija" presentando la mayor tasa de morosidad (11.61%), un hallazgo estructural que exige revisar las políticas de originación para este producto atípico.

Por otro lado, en los créditos regulares existe una relación directa entre el tamaño de la obligación y el impago: la morosidad es de apenas 1.57% para cuotas bajas, sube al 5.19% en cuotas medias, y se dispara al 10.49% en cuotas altas, evidenciando que obligaciones por encima de 20,000 estrangulan el flujo de caja del cliente.

## Pregunta #5: ¿Cuál es la suma total de pagos atrasados por género para clientes penalizados?
Aislé la cartera utilizando un filtro estricto (WHERE COMPENSATION_CHARGED = 'Y') para analizar únicamente a los clientes que recibieron una penalidad económica, sumando su deuda vencida y agrupándola por la variable demográfica de género.

```sql
-- Penalidad y Género: Total de pagos atrasados para clientes con compensación --

SELECT 
    INF_GENDER AS Genero,
    COUNT(ACC_NO) AS Clientes_Penalizados,
    SUM(DUE_PAYMENT) AS Total_Pagos_Atrasados
FROM TB_CLIENTE_RIESGO
WHERE COMPENSATION_CHARGED = 'Y' 
  AND INF_GENDER IS NOT NULL
GROUP BY INF_GENDER
ORDER BY Total_Pagos_Atrasados DESC;
```
![Resultados Pregunta 5](images/image5.png)

*Volumen de deuda en mora y cantidad de clientes penalizados por género*

Al observar a los clientes penalizados, el género masculino (M) concentra el mayor volumen absoluto de deuda vencida, acumulando más de 3.6 mil millones en 12,818 operaciones.

Sin embargo, el segmento femenino (F) representa un riesgo crítico oculto: con menos de un tercio de clientes (3,887), su deuda promedio por prestatario en mora es casi el doble frente a la de los hombres. La severidad del impago individual es significativamente más agresiva en este grupo.

## Pregunta #6: ¿Cuántos clientes presentan un saldo actual que supera su préstamo inicial?
Para detectar anomalías transaccionales, utilicé operadores lógicos de comparación cruzada entre dos columnas numéricas de la misma fila (ACCCURRENTBALANCE > INVESTMENT_TOTAL), y apliqué una operación matemática dentro de la función de agregación para cuantificar el desfase.

```sql
-- Detección de Anomalías: Clientes con saldo actual mayor a la inversión inicial --

SELECT 
    COUNT(ACC_NO) AS Clientes_Con_Anomalia,
    SUM(INVESTMENT_TOTAL) AS Inversion_Original_Total,
    SUM(ACCCURRENTBALANCE) AS Saldo_Actual_Total,
    SUM(ACCCURRENTBALANCE - INVESTMENT_TOTAL) AS Diferencia_Excedente
FROM TB_CLIENTE_RIESGO
WHERE ACCCURRENTBALANCE > INVESTMENT_TOTAL;
```
![Resultados Pregunta 6](images/image6.png)

*Desfase total en cuentas donde la deuda actual excede el desembolso inicial* 

La auditoría de datos identificó 3,050 operaciones donde el saldo deudor actual excede el monto original invertido, generando un gigantesco desfase acumulado de más de 20.9 mil millones.

Financieramente, esto puede explicarse por una capitalización sumamente agresiva de intereses compensatorios y moratorios, o bien por una falla estructural en el registro del sistema core bancario. En cualquier escenario corporativo, este subgrupo requiere una conciliación inmediata.

## Pregunta #7: ¿Los clientes en mora tienen un pago atrasado superior al promedio global?
Para dar escalabilidad al modelo, utilicé una Subconsulta Escalar. En lugar de filtrar la deuda contra un número estático, la cláusula WHERE compara la mora de cada cliente contra el promedio global dinámico (SELECT AVG...), permitiendo que el reporte se auto-actualice si ingresan nuevos datos.

```sql
-- Impacto del Riesgo: Clientes morosos ('B') con deuda superior al promedio general --

SELECT 
    COUNT(ACC_NO) AS Morosos_Criticos,
    ROUND(AVG(DUE_PAYMENT), 2) AS Promedio_Atraso_De_Este_Grupo,
    ROUND((SELECT AVG(DUE_PAYMENT) FROM TB_CLIENTE_RIESGO), 2) AS Promedio_Atraso_Global
FROM TB_CLIENTE_RIESGO
WHERE QUALITY_OF_LOAN = 'B' 
  AND DUE_PAYMENT > (SELECT AVG(DUE_PAYMENT) FROM TB_CLIENTE_RIESGO);
```  
![Resultados Pregunta 7](images/image7.png)

*Comparativa del riesgo extremo versus el atraso promedio de toda la cartera*

El uso de la subconsulta revela una disparidad alarmante. Hemos aislado a 318 "morosos críticos" cuya deuda supera la media general.

Mientras el atraso promedio global se sitúa en aproximadamente 375 mil, este subgrupo específico mantiene una deuda vencida promedio superior a 4.7 millones (más de 12 veces la media general), demostrando que una ínfima fracción de la cartera requiere provisiones de capital extremadamente fuertes.

## Pregunta #8: ¿Cuál es el promedio de cuota en el sector rural según su modo de pago?
Para mejorar la eficiencia y legibilidad de la consulta, estructuré una Expresión de Tabla Común (CTE) utilizando la cláusula WITH AS. Primero aislé toda la información pertinente al sector 'Rural' en una tabla temporal en memoria, sobre la cual luego ejecuté las funciones de agregación.

```sql
-- Análisis de Mora (CTE): Promedio de cuota en el sector rural por modo de pago --

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
```
![Resultados Pregunta 8](images/image8.png)

*Tamaño de cuota mensual promedio por modo de pago en el segmento Rural*

La estructuración mediante CTE expone una dicotomía radical dentro del portafolio rural. La inmensa mayoría de la cartera (24,125 clientes) opera bajo el modo de pago 'N' con cuotas promedio sumamente manejables de 354.36.

En contraste, existe un nicho hiperconcentrado de 1,530 operaciones bajo el modo 'I' cuyas cuotas promedio se disparan por encima de 171,000. Esto sugiere la coexistencia de dos productos (microcréditos masivos frente a financiamientos corporativos/agrícolas), exigiendo políticas de evaluación de riesgo separadas.

## Pregunta #9: Generar un ranking de los prestatarios con mayor deuda dentro de cada tipo de cliente.
Para aislar a los deudores críticos sin perder la perspectiva regional, implementé Funciones de Ventana (Window Functions). Utilicé ROW_NUMBER() combinado con la cláusula OVER(PARTITION BY) para reiniciar el ranking automáticamente cada vez que el sistema evalúa una nueva zona demográfica.
```sql
-- Ranking regionalizado de deudores críticos --

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
```
![Resultados Pregunta 9](images/image9.png)

*Top de clientes con mayor monto atrasado particionado por segmento*

La partición de los datos demuestra su enorme valor analítico al permitir descentralizar la gestión de cobranza. Al generar un ranking interno, garantizamos que los gerentes de las zonas Urbanas puedan visualizar y atacar a sus propios "peores clientes" con estrategias focalizadas.

Si aplicáramos un filtro global simple, los gigantescos montos en mora del área rural (donde el cliente número uno adeuda más de 370 millones) ocultarían por completo el riesgo de los demás sectores, sesgando la toma de decisiones.

### Pregunta #10: ¿Cuál es la evolución del monto total invertido acumulado para los préstamos malos?

Para calcular el riesgo acumulado progresivo (*Running Total*), implementé una Función de Ventana avanzada. A diferencia de un `SUM` tradicional que colapsa los datos, utilizar `SUM() OVER(ORDER BY ...)` permite sumar el capital de forma acumulativa fila por fila, reteniendo el nivel de detalle transaccional de cada cuenta en mora para facilitar la construcción de curvas de Pareto.

```sql
-- Acumulado de Inversión en Riesgo (Running Total para préstamos malos) --

SELECT 
    ACC_NO AS Numero_Cuenta,
    CLIENT_TYPE AS Tipo_Cliente,
    ACCCURRENTBALANCE AS Saldo_Actual,
    INVESTMENT_TOTAL AS Inversion_Original,
    SUM(INVESTMENT_TOTAL) OVER (ORDER BY ACCCURRENTBALANCE DESC) AS Inversion_Acumulada_Riesgo
FROM TB_CLIENTE_RIESGO
WHERE QUALITY_OF_LOAN = 'B'
ORDER BY Saldo_Actual DESC;
```
![Resultados Pregunta 10](images/image10.png)

*Evolución acumulada del capital original en riesgo ordenado por saldo deudor actual*

El cálculo del Running Total expone la agresiva velocidad a la que se concentra el capital en pérdida dentro del portafolio. Al ordenar de mayor a menor saldo deudor, el modelo revela que apenas las primeras 19 operaciones morosas acumulan por sí solas una exposición original superior a los 504 millones.

Adicionalmente, el comportamiento del motor SQL al agrupar los empates exactos en los saldos actuales (por ejemplo, múltiples cuentas compartiendo un saldo exacto de 72,172,616) sugiere fuertemente que un mismo cliente o grupo económico rural mantiene múltiples líneas de crédito simultáneas en estado de default. Esta altísima concentración evidencia la necesidad de establecer topes de exposición máxima por titular para proteger el patrimonio institucional.

---
## Conclusiones Clave

* **Se identificó una concentración crítica de riesgo en el sector rural:** Aunque este segmento concentra el mayor volumen de cartera, también reúne los saldos promedio más altos y los principales clientes en *default*, evidenciando la necesidad de fijar topes de exposición por titular y diversificar hacia zonas urbanas.

* **Se comprobó que cuotas elevadas detonan el impago:** La morosidad escala del 1.57% en cuotas bajas a más del 10.49% cuando el pago supera los 20,000, demostrando que compromisos de pago altos asfixian la liquidez y exigiendo ajustar el ratio cuota/ingreso en originación.

* **Se aislaron los casos críticos que concentran la pérdida de capital:** Apenas 318 clientes morosos mantienen una deuda 12 veces superior al promedio global, y las primeras 19 cuentas del *running total* acumulan más de 504 millones, permitiendo priorizar la cobranza judicial en este grupo clave.

* **Se detectó mayor severidad de deuda en el segmento femenino:** Pese a que los hombres concentran el mayor volumen total adeudado, las mujeres con penalidades registran una deuda promedio por persona sustancialmente más alta, lo que amerita alertas tempranas específicas para este perfil.

* **Se descubrieron inconsistencias contables en el core bancario:** Se hallaron 3,050 registros donde el saldo actual excede el monto desembolsado (con un desfase acumulado de 20.9 mil millones), haciendo urgente implementar validaciones automáticas de datos y conciliar la capitalización de intereses.
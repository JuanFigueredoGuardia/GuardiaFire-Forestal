# GuardiaFire - Estación de Monitoreo Forestal LoRa

**GuardiaFire** es una aplicación web estática, autónoma y táctica diseñada para monitorear localmente sistemas de alerta temprana de incendios forestales. No requiere backend, bases de datos remotas ni servidores centralizados: todo el procesamiento, visualización cartográfica y almacenamiento ocurre directamente en el navegador del usuario mediante tecnologías web estándar.

---

## 📋 Estructura del Proyecto

El repositorio está diseñado para ejecutarse directamente como sitio estático en **GitHub Pages** con los siguientes archivos:

* `index.html`: Estructura semántica, lógica en JavaScript vanilla, integración con Web Serial API, Leaflet cartográfico y Web Audio API.
* `styles.css`: Hoja de estilos moderna con diseño oscuro táctico, paleta de colores para prevención de incendios y adaptabilidad responsiva para PC y dispositivos móviles.
* `nodes.json`: Catálogo de configuración de nodos iniciales de demostración.
* `README.md`: Documentación completa de instalación, despliegue y operación.

---

## 🚀 Cómo Publicar en GitHub Pages

Para publicar este proyecto sin necesidad de compilación o instalación de dependencias:

1. **Crear un nuevo repositorio en GitHub**:
   * Entra a [github.com/new](https://github.com/new).
   * Asigna un nombre a tu repositorio (por ejemplo, `guardiafire`).
   * Déjalo como **Público** y pulsa **Create repository**.

2. **Subir los archivos a la rama principal (`main`)**:
   * Puedes usar la interfaz web de GitHub haciendo clic en **Add file > Upload files**, seleccionando `index.html`, `styles.css`, `nodes.json` y `README.md`, y haciendo commit directo.
   * O mediante la consola de Git:
     ```bash
     git init
     git add index.html styles.css nodes.json README.md
     git commit -m "Inicializar estación GuardiaFire"
     git branch -M main
     git remote add origin https://github.com/TU_USUARIO/guardiafire.git
     git push -u origin main
     ```

3. **Activar GitHub Pages**:
   * En tu repositorio en GitHub, ve a la pestaña **Settings** (Configuración).
   * En el menú lateral izquierdo, haz clic en **Pages**.
   * Bajo la sección **Build and deployment**:
     * **Source**: Selecciona `Deploy from a branch`.
     * **Branch**: Selecciona `main` y la carpeta `/(root)`.
     * Haz clic en **Save** (Guardar).
   * En 1 o 2 minutos, GitHub te proporcionará una URL pública segura (HTTPS), por ejemplo:  
     `https://TU_USUARIO.github.io/guardiafire/`

---

## 🌐 Compatibilidad de Navegadores

* **Web Serial API** requiere navegadores basados en Chromium ejecutándose en una computadora de escritorio:
  * **Google Chrome** (versión 89 o superior).
  * **Microsoft Edge** (versión 89 o superior).
  * **Opera** / **Brave** (con Web Serial habilitado).
* *Nota:* En navegadores móviles (iOS Safari, Android Chrome) o Firefox de escritorio, la visualización del mapa, el catálogo de nodos y el historial funcionan con normalidad, pero la conexión física USB estará desactivada mostrando una advertencia informativa. Para pruebas sin hardware físico, la interfaz incluye el botón **Simular Lectura**.

---

## 🔌 Conexión del Nodo Base por USB

1. Conecta tu placa **ESP32**, **LilyGO T-Beam** o módulo LoRa Gateway a cualquier puerto USB de tu computadora.
2. Abre la página de **GuardiaFire** en Google Chrome o Microsoft Edge.
3. Haz clic en el botón **"Conectar Nodo Base USB"** en la barra superior.
4. El navegador abrirá una ventana emergente del sistema operativo con los puertos serie disponibles:
   * Selecciona el puerto correspondiente a tu placa (ejemplo: `Silicon Labs CP210x`, `CH340`, o `USB-Serial`).
   * Pulsa **Conectar**.
5. La aplicación abrirá automáticamente el puerto a una velocidad de **115200 baudios** y el indicador cambiará a **"USB Conectado"**.
6. A medida que el Nodo Base reciba paquetes de los nodos forestales distribuidos en el campo, el indicador se iluminará en azul parpadeante (**"Recibiendo Datos LoRa"**) y las lecturas se actualizarán en tiempo real en la tabla y en el mapa.

---

## 📦 Formato de Datos Esperado por USB (JSON)

El firmware del Nodo Base debe transmitir una línea de texto JSON terminada en salto de línea (`\n`) por cada paquete LoRa recibido a **115200 baudios**:

```json
{
  "type": "reading",
  "reading": {
    "node_id": "0001",
    "mq5": 420,
    "temperature_c": 31.5,
    "battery_percent": 82,
    "battery_voltage": 4.02,
    "alarm": false,
    "counter": 15
  },
  "gateway": {
    "rssi": -94,
    "snr": 7.5
  }
}
```

### Reglas de Clasificación de Estados:
* **Alarma (`alarm` - Rojo)**: Se activa inmediatamente si `alarm: true`, o si la concentración de gas `mq5 >= 1800`, o si la temperatura `temperature_c >= 55.0°C`. Despliega el banner rojo superior, emite una sirena acústica sintetizada en el navegador y activa la vibración en dispositivos compatibles.
* **Advertencia (`warning` - Amarillo)**: Batería baja (`battery_percent <= 20%`).
* **Normal (`normal` - Verde)**: Valores dentro de umbrales seguros y paquete recibido recientemente.
* **Sin Señal (`offline` - Gris)**: Nodos registrados que no han emitido reporte durante más de 10 minutos.
* **No Registrado (`unknown` - Azul)**: Tramas LoRa válidas recibidas con un `node_id` que aún no ha sido dado de alta en la administración de nodos.

---

## 💾 Persistencia de Datos en LocalStorage

Toda la configuración de nodos (coordenadas, nombres, notas de terreno) y el registro de alertas recientes se almacenan localmente en el navegador mediante **HTML5 LocalStorage**:
* Clave `guardiafire_nodes`: Listado de nodos administrados. Al abrir por primera vez, si el almacenamiento está vacío, carga automáticamente el contenido de `nodes.json`.
* Clave `guardiafire_alerts`: Historial cronológico de eventos y alarmas de incendio.
* Las configuraciones persisten entre reinicios y cierres del navegador sin necesidad de ninguna base de datos en la nube.

import 'package:flutter/material.dart';
import 'package:map/map.dart';
import 'package:latlng/latlng.dart';
import 'dart:js' as js;
import 'dart:convert';
import 'dart:html' as html;

void main() {
  runApp(const GuardiaFireApp());
}

class GuardiaFireApp extends StatelessWidget {
  const GuardiaFireApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GuardiaFire Forest',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
        cardTheme: const CardTheme(
          color: Color(0xFF161E2D),
          elevation: 4,
        ),
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // Map Controller
  late final MapController _mapController;

  // Telemetry variables (100% Dynamic, updated from incoming T-Beam data)
  String _nodeId = "Esperando Conexión...";
  double _lat = -31.375000;
  double _lng = -58.006900;
  String _battery = "N/A";
  double _voltage = 0.0;
  double _rssi = 0.0;
  double _temp = 0.0;
  bool _hasDynamicNode = false;

  // Real-time operations base at UTN Concordia
  final LatLng _utnBaseLocation = const LatLng(-31.375000, -58.006900);

  // Connection status & Log stream bounded logger
  String _serialStatus = "Desconectado";
  final List<String> _logs = [
    "[SISTEMA] Estación de Monitoreo GuardiaFire iniciada.",
    "[INFO] Esperando activación del puerto USB para enlazar T-Beam..."
  ];

  // Selected marker state for popup HUD
  bool _showNodePopup = false;
  bool _showBasePopup = false;

  @override
  void initState() {
    super.initState();

    // Centered exactly in Concordia, Entre Ríos (defaulting to Command Center UTN coords)
    _mapController = MapController(
      location: _utnBaseLocation,
      zoom: 15.0,
    );

    _setupWebSerialAPI();
  }

  // Interperobability with Web Serial API via dynamic JavaScript execution
  void _setupWebSerialAPI() {
    // 1. Dynamic JS Callback injection: Listen to browser window events
    js.context['onSerialLineReceived'] = (String line) {
      _processSerialRawLine(line);
    };

    js.context['onSerialError'] = (String error) {
      _handleSerialFault(error);
    };

    // 2. Inject helper scripts into the main document head to establish 115200 baud pipeline
    final html.ScriptElement script = html.ScriptElement()
      ..text = '''
        window.startSerialConnection = async function() {
          if (!("serial" in navigator)) {
            window.onSerialError("Web Serial API no está soportada en este navegador. Recomienda Chrome/Chromed-based.");
            return;
          }
          try {
            const port = await navigator.serial.requestPort();
            await port.open({ baudRate: 115200 });
            
            window.onSerialLineReceived("PUERTO CONECTADO EXITOSAMENTE.");
            
            const textDecoder = new TextDecoderStream();
            const readableStreamClosed = port.readable.pipeTo(textDecoder.writable);
            const reader = textDecoder.readable.getReader();
            
            let buffer = '';
            while (true) {
              const { value, done } = await reader.read();
              if (done) break;
              
              buffer += value;
              let lines = buffer.split('\\n');
              buffer = lines.pop(); // Hold onto the last incomplete chunk
              
              for (let line of lines) {
                line = line.trim();
                if (line.length > 0) {
                  window.onSerialLineReceived(line);
                }
              }
            }
          } catch (error) {
            window.onSerialError(error.toString());
          }
        };
      ''';
    html.document.head?.append(script);
  }

  // Activa la conexión con la Web Serial API
  void _initiateSerialPortConnection() {
    setState(() {
      _serialStatus = "Conectando...";
      _logs.add("[SISTEMA] Solicitando selección de puerto receptor (115200 bps)...");
    });

    try {
      js.context.callMethod('startSerialConnection');
    } catch (e) {
      _handleSerialFault(e.toString());
    }
  }

  // Manejador del flujo crudo entrante
  void _processSerialRawLine(String line) {
    if (line == "PUERTO CONECTADO EXITOSAMENTE.") {
      setState(() {
        _serialStatus = "Conectado";
        _logs.add("[CONEXIÓN] Enlace físico establecido con LilyGO T-Beam.");
      });
      return;
    }

    // Agregar entrada al panel de logs del operador (mantener acotado)
    setState(() {
      if (_logs.length > 80) {
        _logs.removeAt(0);
      }
      _logs.add("📻 $line");
    });

    // Control de Errores Críticos (bloques try-catch estrictos)
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map<String, dynamic>) {
        _updateIncomingTelemetry(decoded);
      }
    } catch (e) {
      // Ignora silenciosamente paquetes fallidos o ruidos
      debugPrint("Ruido o ráfaga de texto corrupto ignorado: $e");
    }
  }

  // Parser JSON robusto, actualiza el estado dinámico y reposiciona el mapa
  void _updateIncomingTelemetry(Map<String, dynamic> data) {
    final rawId = data['id']?.toString() ?? "NODO_TBEAM";
    final rawLatStr = data['lat']?.toString() ?? "0.0";
    final rawLngStr = data['lng']?.toString() ?? "0.0";
    
    // Convert numerical states
    final double parsedLat = double.tryParse(rawLatStr) ?? 0.0;
    final double parsedLng = double.tryParse(rawLngStr) ?? 0.0;
    
    final rawVoltStr = data['v']?.toString() ?? data['voltage']?.toString() ?? "0.0";
    final double parsedVolt = double.tryParse(rawVoltStr) ?? 0.0;

    final rawTempStr = data['temp']?.toString() ?? "0.0";
    final double parsedTemp = double.tryParse(rawTempStr) ?? 0.0;

    final rawRssiStr = data['rssi']?.toString() ?? "0.0";
    final double parsedRssi = double.tryParse(rawRssiStr) ?? 0.0;

    final rawBatt = data['battery']?.toString() ?? "OK";

    setState(() {
      _nodeId = rawId;
      _battery = rawBatt;
      _voltage = parsedVolt;
      _rssi = parsedRssi;
      _temp = parsedTemp;

      // Filtro de seguridad: validación de coordenadas reales del GPS de exterior
      if (parsedLat != 0.0 && parsedLng != 0.0 && !parsedLat.isNaN && !parsedLng.isNaN) {
        _lat = parsedLat;
        _lng = parsedLng;
        _hasDynamicNode = true;

        // Auto-enfoque al recibir coordenadas de nodo válidas (mapa se mueve suavemente)
        _mapController.center = LatLng(_lat, _lng);
      } else {
        // Log system warning message
        _logs.add("[ADVERTENCIA] Coordenadas inválidas (GPS buscando satélites...)");
      }
    });
  }

  void _handleSerialFault(String error) {
    setState(() {
      _serialStatus = "Error de Enlace";
      _logs.add("[ERROR] Comunicación interrumpida: $error");
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isGpsFixed = _hasDynamicNode && _lat != 0.0 && _lng != 0.0;

    return Scaffold(
      body: Row(
        children: [
          // PANEL LATERAL IZQUIERDO: Dashboard de Telemetría (Slate/Carbón)
          Container(
            width: 380,
            color: const Color(0xFF0F172A),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header del Sistema
                Row(
                  children: [
                    const Icon(Icons.gpp_maybe_rounded, color: Colors.orangeAccent, size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'GUARDIAFIRE',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'FOREST MONITORING STATION',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: Colors.greenAccent.shade400,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24, color: Colors.white10),

                // Tarjeta 1: Control de Comunicación Serie
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "RECEPCIÓN SERIE LORA",
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _serialStatus == "Conectado"
                                    ? Colors.green.withOpacity(0.15)
                                    : _serialStatus == "Conectando..."
                                        ? Colors.orange.withOpacity(0.15)
                                        : Colors.red.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _serialStatus.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: _serialStatus == "Conectado"
                                      ? Colors.greenAccent
                                      : _serialStatus == "Conectando..."
                                          ? Colors.orangeAccent
                                          : Colors.redAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _serialStatus == "Conectado" ? null : _initiateSerialPortConnection,
                          icon: const Icon(Icons.usb_rounded),
                          label: const Text("CONECTAR PUERTO SERIE"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.white10,
                            disabledForegroundColor: Colors.white30,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Baudrate fijo: 115200 bps (Multiplexado)",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 9, color: Colors.white30, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Tarjeta 2: Telemetría de Nodo de Campo (18650 Voltaje y GPS)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "MONITOREO DE NODO LILYGO T-BEAM",
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orangeAccent),
                        ),
                        const SizedBox(height: 12),
                        _buildStatRow("ID del Nodo:", _nodeId, isMonospace: true),
                        _buildStatRow(
                          "Voltaje Celda (18650):",
                          _voltage > 0 ? "${_voltage.toStringAsFixed(2)} V" : "Esperando...",
                        ),
                        _buildStatRow(
                          "Temperatura Celda:",
                          _temp > 0 ? "${_temp.toStringAsFixed(1)} °C" : "Esperando...",
                        ),
                        _buildStatRow("Señal de Radio RSSI:", "${_rssi.toStringAsFixed(0)} dBm"),
                        const SizedBox(height: 8),
                        const Divider(color: Colors.white12),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text(
                              "Sincronismo GPS:",
                              style: TextStyle(fontSize: 12, color: Colors.white54),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isGpsFixed
                                    ? Colors.green.withOpacity(0.15)
                                    : Colors.orange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isGpsFixed ? "FIJADO" : "BUSCANDO SATÉLITES...",
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                  color: isGpsFixed ? Colors.greenAccent : Colors.orangeAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (!isGpsFixed) ...[
                          const SizedBox(height: 8),
                          Text(
                            "El GPS de la T-Beam necesita cielo abierto directo para sincronizar en exterior.",
                            style: TextStyle(fontSize: 10, color: Colors.orangeAccent.withOpacity(0.8), height: 1.3),
                          ),
                        ] else ...[
                          const SizedBox(height: 8),
                          Text(
                            "LAT: ${_lat.toStringAsFixed(6)}\nLNG: ${_lng.toStringAsFixed(6)}",
                            style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.greenAccent),
                          ),
                        ]
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Tarjeta 3: Radio Streams Consola Operaciones
                const Text(
                  "REGISTRO DE OPERACIONES TÁCTICAS",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white60, letterSpacing: 0.5),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF030712),
                      border: Border.all(color: Colors.white10),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.all(8.0),
                    child: ListView.builder(
                      itemCount: _logs.length,
                      reverse: true,
                      itemBuilder: (context, index) {
                        // Traverse list backward to show newest logs at the bottom/scrolling
                        final logItem = _logs[_logs.length - 1 - index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3.0),
                          child: Text(
                            logItem,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: logItem.contains("[ERROR]")
                                  ? Colors.redAccent
                                  : logItem.contains("[SISTEMA]")
                                      ? Colors.blueAccent
                                      : logItem.contains("Radio warning")
                                          ? Colors.orangeAccent
                                          : Colors.grey.shade400,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          // PANEL DERECHO: El mapa expandido (Usa el paquete 'map')
          Expanded(
            child: Stack(
              children: [
                // Renderizado de capas de mapa mediante MapLayout y TileLayer
                MapLayout(
                  controller: _mapController,
                  builder: (context, transformer) {
                    return GestureDetector(
                      onPanUpdate: (details) {
                        // Custom dragging math (Independent and flawless)
                        final centerOffset = transformer.toOffset(_mapController.center);
                        final newCenterOffset = centerOffset - details.delta;
                        _mapController.center = transformer.toLatLng(newCenterOffset);
                        setState(() {});
                      },
                      onDoubleTap: () {
                        _mapController.zoom = (_mapController.zoom + 1).clamp(1.0, 20.0);
                        setState(() {});
                      },
                      child: Stack(
                        children: [
                          // OpenStreetMap standard tile tiles layer 
                          TileLayer(
                            builder: (context, x, y, z) {
                              final url = 'https://tile.openstreetmap.org/$z/$x/$y.png';
                              return Image.network(
                                url,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(color: const Color(0xFF1E293B));
                                },
                              );
                            },
                          ),

                          // 1. PIN DE DIRECCIÓN FIJO (UTN Concordia Centro de Comando)
                          _buildFixedBaseMarker(transformer),

                          // 2. MARCADOR DINÁMICO DEL NODO DE CAMPO (L.circleMarker verde equivalente)
                          if (isGpsFixed) _buildDynamicNodeMarker(transformer),

                          // popup para Base UTN
                          if (_showBasePopup) _buildBasePopupWidget(transformer),

                          // popup para Nodo de Campo
                          if (_showNodePopup && isGpsFixed) _buildNodePopupWidget(transformer),
                        ],
                      ),
                    );
                  },
                ),

                // Barra de control flotante del mapa
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    padding: const EdgeInsets.all(4.0),
                    child: Column(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add, color: Colors.white),
                          tooltip: 'Zoom In',
                          onPressed: () {
                            setState(() {
                              _mapController.zoom = (_mapController.zoom + 1).clamp(1.0, 20.0);
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove, color: Colors.white),
                          tooltip: 'Zoom Out',
                          onPressed: () {
                            setState(() {
                              _mapController.zoom = (_mapController.zoom - 1).clamp(1.0, 20.0);
                            });
                          },
                        ),
                        const Divider(color: Colors.white10, height: 8),
                        IconButton(
                          icon: const Icon(Icons.my_location_rounded, color: Colors.blueAccent),
                          tooltip: 'Recentrar Comando UTN',
                          onPressed: () {
                            setState(() {
                              _mapController.center = _utnBaseLocation;
                              _mapController.zoom = 15.0;
                              _showBasePopup = true;
                              _showNodePopup = false;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Genera un regstros de telemetría de forma limpia
  Widget _buildStatRow(String label, String value, {bool isMonospace = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                fontFamily: isMonospace ? 'monospace' : null,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Render para el Marcador de Base Fijo de UTN Concordia
  Widget _buildFixedBaseMarker(MapTransformer transformer) {
    final offset = transformer.toOffset(_utnBaseLocation);
    return Positioned(
      left: offset.dx - 18,
      top: offset.dy - 36,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _showBasePopup = !_showBasePopup;
            _showNodePopup = false;
          });
        },
        child: const MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Icon(
            Icons.location_on_rounded,
            color: Colors.red,
            size: 36,
            shadows: [
              Shadow(color: Colors.black45, offset: Offset(2, 2)),
            ],
          ),
        ),
      ),
    );
  }

  // Render para el Marcador de Círculo Dinámico del Nodo conectado (L.circleMarker equivalente)
  Widget _buildDynamicNodeMarker(MapTransformer transformer) {
    final offset = transformer.toOffset(LatLng(_lat, _lng));
    return Positioned(
      left: offset.dx - 14,
      top: offset.dy - 14,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _showNodePopup = !_showNodePopup;
            _showBasePopup = false;
          });
        },
        child: const MouseRegion(
          cursor: SystemMouseCursors.click,
          child: DynamicRadarDotWidget(),
        ),
      ),
    );
  }

  // Popup flotante para el Centro de Comando UTN Concordia
  Widget _buildBasePopupWidget(MapTransformer transformer) {
    final offset = transformer.toOffset(_utnBaseLocation);
    return Positioned(
      left: offset.dx - 110,
      top: offset.dy - 100,
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
        ),
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Centro de Comando UTN",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.red, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 2),
            const Text(
              "Salta 277",
              style: TextStyle(fontSize: 10, color: Colors.black87),
            ),
            const SizedBox(height: 4),
            Text(
              "Base Operaciones Concordia\nCoord: -31.3750, -58.0069",
              style: TextStyle(fontSize: 8.5, color: Colors.blueGrey.shade800, fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }

  // Popup flotante dinámico interactivo al cliquear el nodo verde
  Widget _buildNodePopupWidget(MapTransformer transformer) {
    final offset = transformer.toOffset(LatLng(_lat, _lng));
    return Positioned(
      left: offset.dx - 110,
      top: offset.dy - 145,
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.greenAccent),
          boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 3))],
        ),
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sensors_rounded, color: Colors.greenAccent, size: 14),
                const SizedBox(width: 4),
                Text(
                  _nodeId,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.greenAccent, fontFamily: 'monospace'),
                ),
              ],
            ),
            const Divider(height: 8, color: Colors.greenAccent),
            _buildPopupItem("Batería:", _voltage > 0 ? "${_voltage.toStringAsFixed(2)} V ($_battery)" : "Esperando..."),
            _buildPopupItem("Temperatura:", "${_temp.toStringAsFixed(1)} °C"),
            _buildPopupItem("Señal RSSI:", "${_rssi.toStringAsFixed(0)} dBm"),
            const SizedBox(height: 2),
            Text(
              "LAT: ${_lat.toStringAsFixed(6)}\nLNG: ${_lng.toStringAsFixed(6)}",
              style: TextStyle(fontSize: 8, color: Colors.white.withOpacity(0.6), fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPopupItem(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.white70)),
          Text(val, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

// Widget animado que emula un punto de radar pulsante de color verde de 24x24 px
class DynamicRadarDotWidget extends StatefulWidget {
  const DynamicRadarDotWidget({super.key});

  @override
  State<DynamicRadarDotWidget> createState() => _DynamicRadarDotWidgetState();
}

class _DynamicRadarDotWidgetState extends State<DynamicRadarDotWidget> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Onda del Radar pulsante exterior
            Container(
              width: 14 + (20 * _animationController.value),
              height: 14 + (20 * _animationController.value),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.greenAccent.withOpacity(1.0 - _animationController.value),
              ),
            ),
            // Círculo central fijo verde de alta densidad
            Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF00FF41),
                boxShadow: [
                  BoxShadow(color: Colors.greenAccent, blurRadius: 4, spreadRadius: 1),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

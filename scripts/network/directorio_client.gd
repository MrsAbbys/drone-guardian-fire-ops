extends Node

signal sala_creada(datos: Dictionary)
signal salas_recibidas(salas: Array)
signal sala_encontrada(datos: Dictionary)
signal error_directorio(mensaje: String)

enum Operacion { CREAR_SALA, LISTAR_SALAS, OBTENER_SALA }

const TIEMPO_LIMITE_SEGUNDOS: float = 8.0

func crear_sala(
	url_base: String,
	escenario: String,
	dificultad: String,
	max_jugadores: int
) -> void:
	_solicitar(
		url_base,
		"/salas",
		Operacion.CREAR_SALA,
		HTTPClient.METHOD_POST,
		{
			"escenario": escenario,
			"dificultad": dificultad,
			"max_jugadores": max_jugadores,
		}
	)

func listar_salas(url_base: String) -> void:
	_solicitar(url_base, "/salas", Operacion.LISTAR_SALAS, HTTPClient.METHOD_GET)

func obtener_sala(url_base: String, codigo: String) -> void:
	var codigo_limpio := codigo.strip_edges().uri_encode()
	_solicitar(
		url_base,
		"/salas/%s" % codigo_limpio,
		Operacion.OBTENER_SALA,
		HTTPClient.METHOD_GET
	)

func _solicitar(
	url_base: String,
	ruta: String,
	operacion: Operacion,
	metodo: HTTPClient.Method,
	datos: Dictionary = {}
) -> void:
	var base_limpia := url_base.strip_edges().trim_suffix("/")
	if not base_limpia.begins_with("http://") and not base_limpia.begins_with("https://"):
		error_directorio.emit("La dirección del directorio debe comenzar con http:// o https://.")
		return
	var solicitud := HTTPRequest.new()
	solicitud.timeout = TIEMPO_LIMITE_SEGUNDOS
	solicitud.request_completed.connect(_al_completar.bind(solicitud, operacion))
	add_child(solicitud)

	var cabeceras := PackedStringArray()
	var cuerpo := ""
	if metodo == HTTPClient.METHOD_POST:
		cabeceras.append("Content-Type: application/json")
		cuerpo = JSON.stringify(datos)
	var resultado := solicitud.request(base_limpia + ruta, cabeceras, metodo, cuerpo)
	if resultado != OK:
		solicitud.queue_free()
		error_directorio.emit("No se pudo enviar la solicitud al directorio (error %d)." % resultado)

func _al_completar(
	resultado: int,
	codigo_http: int,
	_cabeceras: PackedStringArray,
	cuerpo: PackedByteArray,
	solicitud: HTTPRequest,
	operacion: Operacion
) -> void:
	if resultado != HTTPRequest.RESULT_SUCCESS:
		if resultado == HTTPRequest.RESULT_TIMEOUT:
			error_directorio.emit("El directorio no respondió a tiempo.")
		else:
			error_directorio.emit("No se pudo conectar con el directorio (resultado %d)." % resultado)
		solicitud.queue_free()
		return

	var texto := cuerpo.get_string_from_utf8()
	var respuesta: Variant = JSON.parse_string(texto)
	if codigo_http < 200 or codigo_http >= 300:
		var mensaje := "El directorio respondió con HTTP %d." % codigo_http
		if respuesta is Dictionary:
			mensaje = str(respuesta.get("error", mensaje))
		error_directorio.emit(mensaje)
		solicitud.queue_free()
		return
	if not respuesta is Dictionary:
		error_directorio.emit("El directorio devolvió una respuesta inválida.")
		solicitud.queue_free()
		return

	match operacion:
		Operacion.CREAR_SALA:
			sala_creada.emit(respuesta)
		Operacion.LISTAR_SALAS:
			var salas: Variant = respuesta.get("salas", [])
			if salas is Array:
				salas_recibidas.emit(salas)
			else:
				error_directorio.emit("La lista de salas recibida no es válida.")
		Operacion.OBTENER_SALA:
			sala_encontrada.emit(respuesta)
	solicitud.queue_free()

extends Node

signal sala_creada(datos: Dictionary)
signal salas_recibidas(salas: Array)
signal sala_encontrada(datos: Dictionary)
signal error_directorio(mensaje: String)
signal error_creacion_sala(mensaje: String)

enum Operacion { CREAR_SALA, LISTAR_SALAS, OBTENER_SALA }

const TIEMPO_LIMITE_SEGUNDOS: float = 8.0

var _solicitudes_activas: Array[HTTPRequest] = []


func _exit_tree() -> void:
	cancelar_solicitudes()


func cancelar_solicitudes() -> void:
	for solicitud in _solicitudes_activas.duplicate():
		if not is_instance_valid(solicitud):
			continue
		if solicitud.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
			solicitud.cancel_request()
		if not solicitud.is_queued_for_deletion():
			solicitud.queue_free()
	_solicitudes_activas.clear()


func crear_sala(
	url_base: String,
	nombre_sala: String,
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
			"nombre": nombre_sala.strip_edges(),
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
		_emitir_error_directorio(
			"La dirección del directorio debe comenzar con http:// o https://.",
			operacion
		)
		return
	var solicitud := HTTPRequest.new()
	solicitud.timeout = TIEMPO_LIMITE_SEGUNDOS
	solicitud.request_completed.connect(_al_completar.bind(solicitud, operacion))
	add_child(solicitud)
	_solicitudes_activas.append(solicitud)

	var cabeceras := PackedStringArray()
	var cuerpo := ""
	if metodo == HTTPClient.METHOD_POST:
		cabeceras.append("Content-Type: application/json")
		cuerpo = JSON.stringify(datos)
	var resultado := solicitud.request(base_limpia + ruta, cabeceras, metodo, cuerpo)
	if resultado != OK:
		_finalizar_solicitud(solicitud)
		_emitir_error_directorio(
			"No se pudo enviar la solicitud al directorio (error %d)." % resultado,
			operacion
		)

func _al_completar(
	resultado: int,
	codigo_http: int,
	_cabeceras: PackedStringArray,
	cuerpo: PackedByteArray,
	solicitud: HTTPRequest,
	operacion: Operacion
) -> void:
	if not is_instance_valid(solicitud):
		return
	if resultado != HTTPRequest.RESULT_SUCCESS:
		if resultado == HTTPRequest.RESULT_TIMEOUT:
			_emitir_error_directorio("El directorio no respondió a tiempo.", operacion)
		else:
			_emitir_error_directorio(
				"No se pudo conectar con el directorio (resultado %d)." % resultado,
				operacion
			)
		_finalizar_solicitud(solicitud)
		return

	var texto := cuerpo.get_string_from_utf8()
	var respuesta: Variant = JSON.parse_string(texto)
	if codigo_http < 200 or codigo_http >= 300:
		var mensaje := "El directorio respondió con HTTP %d." % codigo_http
		if respuesta is Dictionary:
			mensaje = str(respuesta.get("error", mensaje))
		_emitir_error_directorio(mensaje, operacion)
		_finalizar_solicitud(solicitud)
		return
	if not respuesta is Dictionary:
		_emitir_error_directorio("El directorio devolvió una respuesta inválida.", operacion)
		_finalizar_solicitud(solicitud)
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
	_finalizar_solicitud(solicitud)


func _emitir_error_directorio(mensaje: String, operacion: Operacion) -> void:
	error_directorio.emit(mensaje)
	if operacion == Operacion.CREAR_SALA:
		error_creacion_sala.emit(mensaje)


func _finalizar_solicitud(solicitud: HTTPRequest) -> void:
	if not is_instance_valid(solicitud):
		return
	_solicitudes_activas.erase(solicitud)
	if not solicitud.is_queued_for_deletion():
		solicitud.queue_free()

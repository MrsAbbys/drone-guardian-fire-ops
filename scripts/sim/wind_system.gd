extends Node

signal viento_proximo(direccion: Vector2, velocidad: float, segundos: float)
signal viento_cambiado(direccion: Vector2, velocidad: float)

const SCRIPT_CONFIGURACION_VIENTO: Script = preload("res://scripts/sim/configuracion_viento.gd")
const PASO_TEMPORIZADOR: float = 0.1
const AVISO_ANTICIPADO: float = 10.0
const DURACION_TRANSICION: float = 3.0
const INTERVALO_RACHAS: float = 45.0
const INTERVALO_ERRATICO: float = 15.0
const MULTIPLICADOR_ERRATICO: float = 1.8

enum Modo { CONSTANTE, RACHAS, ERRATICO }

var direccion: Vector2 = Vector2.RIGHT
var velocidad: float = 0.0

var _temporizador: Timer
var _rng := RandomNumberGenerator.new()
var _configurado: bool = false
var _modo: int = Modo.CONSTANTE
var _direccion_base: Vector2 = Vector2.RIGHT
var _velocidad_base: float = 0.0
var _amplitud_direccion: float = 0.0
var _amplitud_velocidad: float = 0.0
var _intervalo: float = 0.0
var _tiempo_total: float = 0.0
var _siguiente_cambio: float = 0.0
var _aviso_emitido: bool = false
var _objetivo_elegido: bool = false
var _transicionando: bool = false
var _tiempo_transicion: float = 0.0
var _direccion_inicial: Vector2 = Vector2.RIGHT
var _velocidad_inicial: float = 0.0
var _direccion_objetivo: Vector2 = Vector2.RIGHT
var _velocidad_objetivo: float = 0.0

func _ready() -> void:
	_temporizador = Timer.new()
	_temporizador.name = "TemporizadorViento"
	_temporizador.wait_time = PASO_TEMPORIZADOR
	_temporizador.one_shot = false
	_temporizador.timeout.connect(_al_transcurrir_temporizador)
	add_child(_temporizador)

func configurar(configuracion: Resource, semilla: int) -> bool:
	if not is_instance_valid(configuracion) or configuracion.get_script() != SCRIPT_CONFIGURACION_VIENTO:
		push_error("WindSystem requiere un Resource ConfiguracionViento.")
		return false
	var direccion_configurada: Variant = configuracion.get("direccion")
	if not direccion_configurada is Vector2 or direccion_configurada.length_squared() <= 0.0:
		push_error("ConfiguracionViento requiere una dirección no nula.")
		return false
	var modo_configurado := int(configuracion.get("modo"))
	if modo_configurado < Modo.CONSTANTE or modo_configurado > Modo.ERRATICO:
		push_error("ConfiguracionViento contiene un modo desconocido.")
		return false

	_temporizador.stop()
	_modo = modo_configurado
	_direccion_base = direccion_configurada.normalized()
	_velocidad_base = maxf(float(configuracion.get("velocidad_base")), 0.0)
	_amplitud_direccion = deg_to_rad(float(configuracion.get("amplitud_direccion_grados")))
	_amplitud_velocidad = maxf(float(configuracion.get("amplitud_velocidad")), 0.0)
	_rng.seed = semilla
	_tiempo_total = 0.0
	_siguiente_cambio = INTERVALO_ERRATICO if _modo == Modo.ERRATICO else INTERVALO_RACHAS
	_aviso_emitido = false
	_objetivo_elegido = false
	_transicionando = false
	_tiempo_transicion = 0.0
	direccion = _direccion_base
	velocidad = _velocidad_base
	_configurado = true
	viento_cambiado.emit(direccion, velocidad)
	if _modo != Modo.CONSTANTE:
		_temporizador.start(PASO_TEMPORIZADOR)
	return true

func detener() -> void:
	if _temporizador:
		_temporizador.stop()
	_configurado = false
	_transicionando = false
	_objetivo_elegido = false

func avanzar(delta: float) -> void:
	if not _configurado or _modo == Modo.CONSTANTE or delta <= 0.0:
		return
	_tiempo_total += delta
	if not _aviso_emitido and _tiempo_total >= _siguiente_cambio - AVISO_ANTICIPADO:
		_elegir_rafaga()
		_aviso_emitido = true
		viento_proximo.emit(_direccion_objetivo, _velocidad_objetivo, AVISO_ANTICIPADO)
	if not _transicionando and _tiempo_total >= _siguiente_cambio:
		if not _objetivo_elegido:
			_elegir_rafaga()
		_iniciar_transicion()
		_siguiente_cambio += _intervalo
		_aviso_emitido = false
	if _transicionando:
		_actualizar_transicion(delta)

func obtener_vector_viento() -> Vector2:
	return direccion * velocidad

func _al_transcurrir_temporizador() -> void:
	avanzar(PASO_TEMPORIZADOR)

func _elegir_rafaga() -> void:
	var multiplicador := MULTIPLICADOR_ERRATICO if _modo == Modo.ERRATICO else 1.0
	var angulo_base := _direccion_base.angle()
	var variacion_angular := _rng.randf_range(-_amplitud_direccion, _amplitud_direccion) * multiplicador
	_direccion_objetivo = Vector2.RIGHT.rotated(angulo_base + variacion_angular).normalized()
	_velocidad_objetivo = maxf(
		_velocidad_base + _rng.randf_range(-_amplitud_velocidad, _amplitud_velocidad) * multiplicador,
		0.0
	)
	_objetivo_elegido = true

func _iniciar_transicion() -> void:
	_intervalo = INTERVALO_ERRATICO if _modo == Modo.ERRATICO else INTERVALO_RACHAS
	_direccion_inicial = direccion
	_velocidad_inicial = velocidad
	_tiempo_transicion = 0.0
	_transicionando = true

func _actualizar_transicion(delta: float) -> void:
	_tiempo_transicion = minf(_tiempo_transicion + delta, DURACION_TRANSICION)
	var progreso := clampf(_tiempo_transicion / DURACION_TRANSICION, 0.0, 1.0)
	var angulo := lerp_angle(_direccion_inicial.angle(), _direccion_objetivo.angle(), progreso)
	direccion = Vector2.RIGHT.rotated(angulo).normalized()
	velocidad = lerpf(_velocidad_inicial, _velocidad_objetivo, progreso)
	viento_cambiado.emit(direccion, velocidad)
	if progreso >= 1.0:
		_transicionando = false
		_objetivo_elegido = false

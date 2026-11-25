extends Node

signal fuegos_actualizados(restantes: int, total: int)
signal arbol_apagado(total_apagados: int)
signal incendio_controlado
signal incendio_descontrolado

var fuegos_restantes: int = 0
var fuegos_totales: int = 0
var _apagados: int = 0
var _estados_anteriores: PackedByteArray = PackedByteArray()
var _incendio_finalizado: bool = false

func _ready() -> void:
	FireGridServer.celdas_modificadas.connect(_al_modificarse_celdas)
	FireGridServer.estado_inicial.connect(_al_recibir_estado_inicial)
	FireGridServer.incendio_descontrolado.connect(_al_descontrolarse)
	if FireGridServer.activa:
		_sincronizar_estado()

func _exit_tree() -> void:
	if FireGridServer.celdas_modificadas.is_connected(_al_modificarse_celdas):
		FireGridServer.celdas_modificadas.disconnect(_al_modificarse_celdas)
	if FireGridServer.estado_inicial.is_connected(_al_recibir_estado_inicial):
		FireGridServer.estado_inicial.disconnect(_al_recibir_estado_inicial)
	if FireGridServer.incendio_descontrolado.is_connected(_al_descontrolarse):
		FireGridServer.incendio_descontrolado.disconnect(_al_descontrolarse)

func _al_recibir_estado_inicial(_datos: PackedByteArray) -> void:
	_sincronizar_estado()

func _sincronizar_estado() -> void:
	if not FireGridServer.activa:
		return
	_estados_anteriores = FireGridServer.obtener_estado_celdas().duplicate()
	_apagados = 0
	_incendio_finalizado = false
	_actualizar_conteos()

func _al_modificarse_celdas(deltas: Array) -> void:
	if not FireGridServer.activa:
		return
	var arboles_apagados_en_lote: int = 0
	for cambio in deltas:
		if not cambio is Array or cambio.size() != 2:
			continue
		var indice := int(cambio[0])
		var nuevo_estado := int(cambio[1])
		if indice < 0 or indice >= _estados_anteriores.size():
			continue
		var estado_anterior := int(_estados_anteriores[indice])
		if (
			estado_anterior == 1
			and nuevo_estado != 1
			and FireGridServer.es_celda_arbol_foco(indice)
		):
			_apagados += 1
			arboles_apagados_en_lote += 1
		_estados_anteriores[indice] = nuevo_estado
	_actualizar_conteos()
	if arboles_apagados_en_lote > 0:
		arbol_apagado.emit(_apagados)

func _actualizar_conteos() -> void:
	fuegos_restantes = FireGridServer.obtener_cantidad_ardiendo()
	fuegos_totales = FireGridServer.obtener_total_ignitado()
	fuegos_actualizados.emit(fuegos_restantes, fuegos_totales)
	if fuegos_restantes == 0 and fuegos_totales > 0 and not _incendio_finalizado:
		_incendio_finalizado = true
		FireGridServer.finalizar_objetivos_criticos()
		incendio_controlado.emit()

func _al_descontrolarse() -> void:
	FireGridServer.finalizar_objetivos_criticos()
	incendio_descontrolado.emit()

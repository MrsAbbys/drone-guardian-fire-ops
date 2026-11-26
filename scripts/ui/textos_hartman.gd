class_name TextosHartman
extends RefCounted

const FRASES: Dictionary = {
	"bienvenida": [
		"Piloto, revise el sector y mantenga el chorro sobre los focos. Vigile el agua y regrese al helipuerto al terminar.",
		"Atento: localice el incendio, controle los focos y cuide la aeronave. Recargue en la fuente de agua cuando lo necesite."
	],
	"regreso_urgente": [
		"¡Piloto, regrese al helipuerto y aterrice de inmediato!",
		"¡Deje de dar vueltas y vuelva al helipuerto, piloto!"
	],
	"recargando": [
		"Recargando en la fuente de agua. Mantenga la posición, piloto.",
		"Depósito en recarga. Manténgase firme junto a la fuente de agua."
	],
	"fuera_de_alcance_antes_disparo": [
		"Aún no, piloto. El foco está fuera de alcance.",
		"Espere, piloto. Acérquese; el chorro no llega."
	],
	"inactividad": [
		"¡Piloto, mueva esa aeronave! El incendio no espera.",
		"¡Atento a los mandos! El sector necesita su intervención."
	],
	"sin_fuente": [
		"Está lejos de la fuente de agua. Regrese al punto de recarga.",
		"Piloto, acérquese a la fuente de agua para recargar."
	],
	"tanque_vacio": [
		"¡Depósito vacío! Regrese a la fuente de agua y recargue.",
		"¡Sin agua, piloto! Vuelva al punto de recarga."
	],
	"desperdicio_fuera_de_alcance": [
		"¡Alto! El foco está fuera de alcance. Acérquese.",
		"El chorro no llega al incendio. Acérquese antes de disparar."
	],
	"desperdicio_punto_muy_bajo": [
		"Está apuntando muy bajo, piloto. Suba la boquilla.",
		"Suba la puntería; el foco está más alto."
	],
	"desperdicio_punto_muy_alto": [
		"Está apuntando muy alto. Baje la boquilla.",
		"Baje la puntería, piloto. Mantenga el foco a la vista."
	],
	"desperdicio_desviado_lateral": [
		"El chorro pasa al lado del foco. Corrija la puntería.",
		"Está desviando el chorro, piloto. Centre el incendio."
	],
	"desperdicio_pasto_limpio": [
		"¡Está rociando terreno limpio! Centre el foco en la retícula.",
		"¡No desperdicie agua en terreno sin fuego! Corrija la puntería."
	],
	"danio_colision": [
		"¡Cuidado con la aeronave! Controle el vuelo antes de dañar el equipo.",
		"¡Mire por dónde vuela, piloto! Proteja la aeronave."
	],
	"alarma_termica": [
		"¡Alarma térmica! Aléjese de las llamas y gane altura.",
		"¡Está demasiado cerca del fuego! Suba y proteja los motores."
	],
	"demora_regreso": [
		"¡El incendio está controlado! Regrese al helipuerto de inmediato.",
		"¡Misión de extinción terminada! Aterrice en el helipuerto, piloto."
	],
	"foco_neutralizado": [
		"¡Foco neutralizado! Mantenga el chorro sobre el siguiente.",
		"¡Buen trabajo! Pase al siguiente foco y mantenga la presión."
	],
	"chorro_efectivo": [
		"¡Chorro efectivo! Manténgalo sobre el foco.",
		"¡Así se hace! Sostenga el chorro sobre las llamas."
	],
	"objetivo_en_mira": [
		"¡Objetivo en mira, suelta el agua ahora!"
	],
	"buena_posicion_descarga": [
		"¡Buena posición, descarga!"
	],
	"fuego_controlado": [
		"¡Así se hace piloto, fuego controlado!"
	],
	"incendio_controlado": [
		"¡Incendio controlado! Regrese al helipuerto.",
		"¡Todos los focos están controlados! Vuelva al helipuerto."
	],
	"incendio_descontrolado": [
		"¡El incendio se extendió demasiado! Misión fallida, piloto.",
		"¡No pudimos contener el incendio! La misión ha terminado."
	],
	"aterrizaje_exitoso": [
		"¡Misión cumplida! Aeronave asegurada. Buen trabajo, piloto.",
		"¡Buen aterrizaje! El sector está protegido. Puede descansar, piloto."
	],
	"guia_izquierda": [
		"Gire a la izquierda, piloto.",
		"Un poco más a la izquierda. Corrija el rumbo."
	],
	"guia_derecha": [
		"Gire a la derecha, piloto.",
		"Un poco más a la derecha. Corrija el rumbo."
	],
	"guia_subir": [
		"Suba, el fuego está más alto.",
		"Eleve la boquilla, piloto. El foco está arriba."
	],
	"guia_bajar": [
		"Baje la boquilla, el fuego está más bajo.",
		"Apunte más abajo, piloto. Corrija la elevación."
	],
	"guia_acercarse": [
		"Acérquese. Está fuera de alcance.",
		"El chorro no llega, piloto. Avance hacia el foco."
	],
	"guia_en_blanco": [
		"¡Así, mantenga el chorro!",
		"¡Buen blanco! Sostenga la puntería."
	],
	"guia_correccion": [
		"Ajuste la puntería, piloto. Centre el foco.",
		"Corrija el rumbo y alinee el chorro con las llamas."
	],
	"menu_flota": [
		"Flota Guardian lista. Elija su aeronave y cumpla la tarea, piloto.",
		"Unidades de respuesta disponibles. Seleccione su aeronave y prepárese."
	],
	"menu_ruleta": [
		"¿Ruleta para valientes? El viento puede complicar el vuelo. Domine los mandos antes de despegar.",
		"En esta prueba, el viento pondrá a prueba su control. Mantenga la cabeza fría, piloto."
	],
	"menu_misiones": [
		"Operación activa. Proteja el sector y controle los focos del incendio.",
		"Prioridad: contener el incendio y proteger la zona. Prepárese para despegar."
	],
	"menu_ajustes": [
		"Ajustes de vuelo listos. Calibre los mandos antes de entrar en acción.",
		"Revise los controles y deje la aeronave lista para la misión."
	]
}

var _ultima_variante_por_clave: Dictionary = {}

func obtener(clave: String, parametros: Dictionary = {}) -> String:
	if not FRASES.has(clave):
		push_error("No existe la frase de Hartman con clave: " + clave)
		return ""

	var variantes: Array = FRASES[clave]
	if variantes.is_empty():
		push_error("La clave de Hartman no tiene variantes: " + clave)
		return ""

	var indice: int = randi_range(0, variantes.size() - 1)
	var indice_anterior: int = int(_ultima_variante_por_clave.get(clave, -1))
	if variantes.size() > 1 and indice == indice_anterior:
		indice = (indice + 1) % variantes.size()
	_ultima_variante_por_clave[clave] = indice

	var texto: String = tr(str(variantes[indice]))
	for nombre: String in parametros:
		texto = texto.replace("{" + nombre + "}", str(parametros[nombre]))
	return "«%s»" % texto

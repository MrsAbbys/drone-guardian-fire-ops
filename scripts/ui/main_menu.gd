extends Control

const RETRATO_NORMAL := preload("res://imagenes_sargento/bien.jpg")

@onready var bg_rect: TextureRect = $MenuArtBackground
@onready var lbl_hartman_dialogue: Label = $FrontUILayer/LeftTacticalPanel/HartmanCard/DialogueText
@onready var hartman_portrait: TextureRect = $FrontUILayer/LeftTacticalPanel/HartmanCard/PortraitBox

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	hartman_portrait.texture = RETRATO_NORMAL
	load_art()

func load_art() -> void:
	var background_texture = ResourceLoader.load("res://assets/ui/menu_background.png")
	if background_texture is Texture2D:
		bg_rect.texture = background_texture
	else:
		push_error("No se pudo cargar el fondo del menú: res://assets/ui/menu_background.png")

func _on_btn_1_iniciar_pressed() -> void:
	var target = "res://scenes/levels/escena_aguarague.tscn"
	if ResourceLoader.exists(target):
		get_tree().change_scene_to_file(target)
	else:
		get_tree().change_scene_to_file("res://scenes/gameplay/mission_01_yacuiba.tscn")

func _on_btn_2_drones_pressed() -> void:
	if lbl_hartman_dialogue:
		lbl_hartman_dialogue.text = "«Flota Guardian: S1 Scout (50L), S2 Response (100L), H8 Aqua Lift (350L). Tu unidad activa es el S1 Scout, novato.»"

func _on_btn_3_ruleta_pressed() -> void:
	if lbl_hartman_dialogue:
		lbl_hartman_dialogue.text = "«¿Ruleta para Valientes? Vientos de 30 km/h en la quebrada. No entres si no dominas el vuelo con ratón.»"

func _on_btn_4_misiones_pressed() -> void:
	if lbl_hartman_dialogue:
		lbl_hartman_dialogue.text = "«Operación Activa: Faldas de la Serranía del Aguaragüe (-21.5000, -63.6000). Prioridad: Proteger los bosques secos.»"

func _on_btn_5_config_pressed() -> void:
	if lbl_hartman_dialogue:
		lbl_hartman_dialogue.text = "«Ajustes de vuelo: Sensibilidad de rotación y cámara calibradas para máxima respuesta en combate.»"

func _on_btn_6_salir_pressed() -> void:
	get_tree().quit()

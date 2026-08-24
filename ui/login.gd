extends CanvasLayer

@onready var name_edit: LineEdit = %NameEdit
@onready var password_edit: LineEdit = %PasswordEdit
@onready var login_button: Button = %LoginButton
@onready var register_button: Button = %RegisterButton
@onready var status_label: Label = %StatusLabel
@onready var login_panel: CenterContainer = %Center
@onready var register_center: CenterContainer = %RegisterCenter
@onready var reg_name_edit: LineEdit = %RegNameEdit
@onready var reg_password_edit: LineEdit = %RegPasswordEdit
@onready var back_button: Button = %BackButton
@onready var register_submit: Button = %RegisterSubmit
@onready var reg_status_label: Label = %RegStatusLabel
@onready var character_creator: CharacterCreator = %CharacterCreator

var _registering := false


func _ready() -> void:
	# Se estiver rodando em modo headless (como no Render), inicia o host automaticamente.
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		print("Servidor headless detectado. Iniciando host automaticamente...")
		call_deferred("_auto_start_host")
		return

	login_button.pressed.connect(_on_login_pressed)
	register_button.pressed.connect(_on_open_register_pressed)
	back_button.pressed.connect(_on_back_pressed)
	register_submit.pressed.connect(_on_register_submit_pressed)

	name_edit.text_changed.connect(func(_t: String) -> void: status_label.text = "")
	reg_name_edit.text_changed.connect(_on_reg_fields_changed)
	reg_password_edit.text_changed.connect(_on_reg_fields_changed)

	character_creator.confirmed.connect(_on_appearance_confirmed)
	character_creator.cancelled.connect(_on_creator_cancelled)

	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.auth_failed.connect(_on_auth_failed)
	NetworkManager.register_result.connect(_on_register_result)
	NetworkManager.needs_character_creation.connect(_on_needs_character_creation)
	_refresh_register_button()


func _auto_start_host() -> void:
	NetworkManager.join_or_host("Servidor")


# ---------- Página de LOGIN ----------

func _on_login_pressed() -> void:
	var p_name := name_edit.text.strip_edges()
	var password := password_edit.text
	if p_name.is_empty():
		status_label.text = "Digite um nome."
		return
	if password.length() < NetworkManager.MIN_PASSWORD_LENGTH:
		status_label.text = "A senha precisa ter pelo menos %d caracteres." % NetworkManager.MIN_PASSWORD_LENGTH
		return
	status_label.text = ""
	NetworkManager.join_or_host(p_name, password)


# ---------- Página de REGISTRO ----------

func _on_open_register_pressed() -> void:
	login_panel.visible = false
	register_center.visible = true
	reg_name_edit.text = name_edit.text
	_refresh_register_button()
	reg_name_edit.grab_focus()


func _on_back_pressed() -> void:
	if _registering:
		return
	register_center.visible = false
	login_panel.visible = true
	reg_status_label.text = ""


func _on_reg_fields_changed(_text: String = "") -> void:
	_refresh_register_button()
	if not reg_status_label.text.is_empty():
		reg_status_label.text = ""


## Registrar só libera com os dois campos preenchidos.
func _refresh_register_button() -> void:
	var fields_ok := not reg_name_edit.text.strip_edges().is_empty() \
			and reg_password_edit.text.length() >= NetworkManager.MIN_PASSWORD_LENGTH
	register_submit.disabled = _registering or not fields_ok


func _on_register_submit_pressed() -> void:
	if register_submit.disabled:
		return
	var p_name := reg_name_edit.text.strip_edges()
	var password := reg_password_edit.text
	if p_name.is_empty() or password.length() < NetworkManager.MIN_PASSWORD_LENGTH:
		return
	_registering = true
	_refresh_register_button()
	back_button.disabled = true
	reg_status_label.text = "Criando conta..."
	NetworkManager.start_register(p_name, password)


func _on_register_result(ok: bool, message: String) -> void:
	_registering = false
	back_button.disabled = false
	_refresh_register_button()
	if ok:
		# Volta para a tela principal de login.
		password_edit.text = ""
		name_edit.text = reg_name_edit.text
		register_center.visible = false
		login_panel.visible = true
		status_label.text = "Conta criada! Entre com sua senha."
		password_edit.grab_focus()
	else:
		reg_status_label.text = message


# ---------- Criação de personagem (contas novas, pós-login) ----------

func _on_needs_character_creation() -> void:
	character_creator.open(NetworkManager.local_player_name)


func _on_appearance_confirmed(appearance: Dictionary) -> void:
	character_creator.visible = false
	NetworkManager.complete_character_creation(appearance)


func _on_creator_cancelled() -> void:
	# Desiste da criação: encerra a sessão e volta ao login.
	NetworkManager.abort_session()
	character_creator.visible = false
	login_panel.visible = true
	status_label.text = ""


# ---------- Erros ----------

func _show_error(reason: String) -> void:
	if character_creator.visible:
		character_creator.set_busy(false)
		character_creator.set_status(reason)
		return
	status_label.text = reason


func _on_connection_failed(reason: String) -> void:
	if _registering:
		_on_register_result(false, reason)
		return
	status_label.text = reason


func _on_auth_failed(reason: String) -> void:
	status_label.text = reason

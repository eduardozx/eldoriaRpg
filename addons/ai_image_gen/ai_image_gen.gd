# AI Image Generator Plugin for Eldoria RPG
# Connects to AI services to generate 2D images with auto-crop and reference support

# TO USE WITH REAL AI SERVICE:
# 1. Replace the _generate_image_thread function with actual API calls to your AI service
# 2. Update AI_SERVICE_URL constant with your endpoint
# 3. Add any required authentication headers
# 4. Parse the response to get the generated image data

@tool
extends EditorPlugin

# Configuration
const AI_SERVICE_URL := "https://api.example.com/generate"  # REPLACE WITH YOUR AI SERVICE URL
const DEFAULT_PROMPT := "fantasy character portrait, high detail, 2D game art"
const SUPPORTED_TYPES := ["woman", "warrior", "mage", "archer", "knight", "elf", "dwarf"]
const OUTPUT_SIZE := Vector2i(512, 512)
const CROP_MARGIN := 0.1  # 10% margin for auto-crop

# UI elements
var popup_window: WindowDialog
var prompt_input: LineEdit
var type_option: OptionButton
var reference_input: LineEdit
var generate_button: Button
var progress_bar: ProgressBar
var result_preview: TextureRect
var status_label: Label

func _enter_tree() -> void:
	# Create plugin UI
	_create_editor_interface()
	
	# Add menu item
	add_tool_menu_item("AI Image Generator", "_show_ai_generator")
	
	print("AI Image Generator plugin loaded")

func _exit_tree() -> void:
	remove_tool_menu_item("AI Image Generator")
	_queue_free_popup()

func _create_editor_interface() -> void:
	# Create popup window
	popup_window = WindowDialog.new()
	popup_window.title = "AI Image Generator"
	popup_window.size = Vector2i(500, 400)
	popup_window.popup_centered_ratio = 0.8
	popup_window.hide_on_ok_clicked = true
	
	var main_vbox = VBoxContainer.new()
	main_vbox.vertical_alignment = VBoxContainer.ALIGNMENT_TOP
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.margin_all = 10
	main_vbox.spacing = 10
	popup_window.add_child(main_vbox)
	
	# Title
	var title_label = Label.new()
	title_label.text = "Generate 2D Game Art with AI"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color(0.2, 0.8, 1.0))
	main_vbox.add_child(title_label)
	
	# Prompt input
	main_vbox.add_child(_create_label("Prompt:"))
	prompt_input = LineEdit.new()
	prompt_input.placeholder_text = DEFAULT_PROMPT
	prompt_input.min_size = Vector2i(400, 30)
	main_vbox.add_child(prompt_input)
	
	# Character type selection
	main_vbox.add_child(_create_label("Character Type:"))
	type_option = OptionButton.new()
	for type in SUPPORTED_TYPES:
		type_option.add_item(type.capitalize())
	type_option.select(0)  # Default to first option
	type_option.min_size = Vector2i(200, 30)
	main_vbox.add_child(type_option)
	
	# Reference image input (optional)
	main_vbox.add_child(_create_label("Reference Image (URL or path, optional):"))
	reference_input = LineEdit.new()
	reference_input.placeholder_text = "Leave blank for no reference"
	reference_input.min_size = Vector2i(400, 30)
	main_vbox.add_child(reference_input)
	
	# Generate button
	generate_button = Button.new()
	generate_button.text = "Generate Image"
	generate_button.min_size = Vector2i(200, 40)
	generate_button.connect("pressed", Callable(self, "_on_generate_pressed"))
	main_vbox.add_child(generate_button)
	
	# Progress bar
	progress_bar = ProgressBar.new()
	progress_bar.min_size = Vector2i(400, 20)
	progress_bar.visible = false
	main_vbox.add_child(progress_bar)
	
	# Status label
	status_label = Label.new()
	status_label.text = "Ready to generate"
	status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	main_vbox.add_child(status_label)
	
	# Result preview
	var preview_vbox = VBoxContainer.new()
	preview_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(preview_vbox)
	
	var preview_label = Label.new()
	preview_label.text = "Generated Image Preview:"
	preview_label.add_theme_font_size_override("font_size", 14)
	preview_vbox.add_child(preview_label)
	
	result_preview = TextureRect.new()
	result_preview.min_size = Vector2i(256, 256)
	result_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result_preview.expand = true
	preview_vbox.add_child(result_preview)
	
	# Add popup to editor
	get_editor_interface().get_editor_view().add_child(popup_window)
	popup_window.hide()

func _create_label(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	return label

func _show_ai_generator() -> void:
	if popup_window:
		popup_window.popup_centered()
		prompt_input.grab_focus()

func _on_generate_pressed() -> void:
	var prompt := prompt_input.text.strip_edges()
	if prompt == "":
		prompt = DEFAULT_PROMPT
	
	var char_type := type_option.get_selected_text().lowercase()
	var reference := reference_input.text.strip_edges()
	
	# Enhance prompt with character type
	if char_type != "" and char_type not in prompt:
		prompt = "%s, %s" % [prompt, char_type]
	
	# Add reference if provided
	if reference != "":
		prompt = "%s, reference image: %s" % [prompt, reference]
	
	# Disable UI during generation
	generate_button.disabled = true
	progress_bar.visible = true
	progress_bar.value = 0
	status_label.text = "Generating..."
	result_preview.texture = null
	
	# Start generation in background thread
	var thread = Thread.new()
	thread.start(Callable(self, "_generate_image_thread"), prompt)
	
	# Start progress update timer
	var timer = Timer.new()
	timer.wait_time = 0.1
	timer.one_shot = false
	timer.connect("timeout", Callable(self, "_update_progress"))
	add_child(timer)
	timer.start()

func _generate_image_thread(prompt: String) -> void:
	# TODO: REPLACE THIS WITH ACTUAL AI SERVICE INTEGRATION
	# Example implementation for a hypothetical AI service:
	#
	# var http = HTTPRequest.new()
	# add_child(http)
	# 
	# var payload = {
	#     "prompt": prompt,
	#     "width": OUTPUT_SIZE.x,
	#     "height": OUTPUT_SIZE.y,
	#     # Add other parameters as needed by your service
	# }
	# 
	# var headers = [
	#     "Content-Type: application/json",
	#     # Add authentication headers if needed
	#     # "Authorization: Bearer YOUR_API_KEY"
	# ]
	#
	# var result = http.request(
	#     AI_SERVICE_URL,
	#     headers,
	#     HTTPClient.METHOD_POST,
	#     JSON.print(payload)
	# )
	# 
	# # Wait for response and handle errors
	# # Extract image data from response
	# # For now, we'll simulate with a placeholder
	
	# SIMULATED AI RESPONSE (REMOVE WHEN INTEGRATING REAL SERVICE)
	var image := Image.new()
	image.create(OUTPUT_SIZE.x, OUTPUT_SIZE.y, false, Image.FORMAT_RGBA8)
	
	# Fill with a gradient based on prompt for demo purposes
	for x in image.get_width():
		for y in image.get_height():
			var color_val := float(x) / image.get_width()
			var color := Color(color_val, 0.5, 1.0 - color_val, 1.0)
			image.set_pixel(x, y, color)
	
	# Simulate processing delay
	Thread.delay_milli(2000)  # 2 seconds
	
	# Send result back to main thread
	call_deferred("_on_image_generated", image)

func _on_image_generated(generated_image: Image) -> void:
	# Auto-crop the image
	var cropped_image := _auto_crop_image(generated_image)
	
	# Convert to texture
	var texture := ImageTexture.create_from_image(cropped_image)
	result_preview.texture = texture
	
	# Re-enable UI
	generate_button.disabled = false
	progress_bar.visible = false
	status_label.text = "Image generated successfully!"
	
	# Offer to save the image
	var save_dialog = FileDialog.new()
	save_dialog.mode = FileDialog.MODE_SAVE_FILE
	save_dialog.title = "Save Generated Image"
	save_dialog.current_dir = "user://"
	save_dialog.file_type = "png"
	save_dialog.connect("file_selected", Callable(self, "_on_save_image"), [cropped_image])
	save_dialog.popup_centered()

func _auto_crop_image(image: Image) -> Image:
	# Simple auto-crop: find non-transparent borders and crop with margin
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	
	var width := image.get_width()
	var height := image.get_height()
	
	# Find bounds of non-transparent pixels
	var min_x := width
	var max_x := 0
	var min_y := height
	var max_y := 0
	
	var found_content := false
	
	for x in width:
		for y in height:
			var color := image.get_pixel(x, y)
			if color.a > 0.1:  # Not fully transparent
				min_x = min(min_x, x)
				max_x = max(max_x, x)
				min_y = min(min_y, y)
				max_y = max(max_y, y)
				found_content = true
	
	if not found_content:
		# If no content found, return original with margin
		var margin_x := int(width * CROP_MARGIN)
		var margin_y := int(height * CROP_MARGIN)
		var rect := Rect2i(margin_x, margin_y, width - 2 * margin_x, height - 2 * margin_y)
		return image.get_rect(rect)
	
	# Add margin
	var margin_x := int((max_x - min_x) * CROP_MARGIN)
	var margin_y := int((max_y - min_y) * CROP_MARGIN)
	
	min_x = max(0, min_x - margin_x)
	max_x = min(width - 1, max_x + margin_x)
	min_y = max(0, min_y - margin_y)
	max_y = min(height - 1, max_y + margin_y)
	
	var crop_width := max_x - min_x + 1
	var crop_height := max_y - min_y + 1
	
	if crop_width <= 0 or crop_height <= 0:
		return image  # Return original if crop invalid
	
	var rect := Rect2i(min_x, min_y, crop_width, crop_height)
	return image.get_rect(rect)

func _on_save_image(image: Image, path: String) -> void:
	# Ensure .png extension
	if not path.ends_with(".png"):
		path = path + ".png"
	
	# Save image
	var error := image.save_png(path)
	if error == OK:
		status_label.text = "Image saved to: %s" % [path]
	else:
		status_label.text = "Failed to save image: %s" % [error]
	
	# Show notification in editor
	get_editor_interface().show_notification("Image saved successfully!", Color(0.2, 0.8, 0.2))

func _update_progress() -> void:
	# Simulate progress (in real implementation, this would come from API)
	var progress := progress_bar.value + 10
	if progress >= 100:
		progress = 100
		# Create a one-shot timer to stop progress updates
		var stop_timer = Timer.new()
		stop_timer.wait_time = 0.1
		stop_timer.one_shot = true
		stop_timer.connect("timeout", Callable(self, "_stop_progress_updates"))
		add_child(stop_timer)
		stop_timer.start()
	progress_bar.value = progress

func _stop_progress_updates() -> void:
	# Stop updating progress - the timer will be automatically freed
	pass

func _queue_free_popup() -> void:
	if popup_window and !popup_window.is_queued_for_deletion():
		popup_window.queue_free()
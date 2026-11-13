# MIT License. 
# Made by Dylearn

# Node for ease of editing shader globals

@tool
extends Node

@export var cloud_contrast: float = 3.845:
	set(value):
		cloud_contrast = value
		RenderingServer.global_shader_parameter_set("cloud_contrast", value)

@export var cloud_direction: Vector2 = Vector2(0, -1):
	set(value):
		cloud_direction = value
		RenderingServer.global_shader_parameter_set("cloud_direction", value)

@export var cloud_diverge_angle: float = 20.0:
	set(value):
		cloud_diverge_angle = value
		RenderingServer.global_shader_parameter_set("cloud_diverge_angle", value)

@export var cloud_scale: float = 40.0:
	set(value):
		cloud_scale = value
		RenderingServer.global_shader_parameter_set("cloud_scale", value)

@export var cloud_speed: float = -0.01:
	set(value):
		cloud_speed = value
		RenderingServer.global_shader_parameter_set("cloud_speed", value)

@export var cloud_threshold: float = 0.27:
	set(value):
		cloud_threshold = value
		RenderingServer.global_shader_parameter_set("cloud_threshold", value)

@export var cloud_shadow_min: float = 0.2:
	set(value):
		cloud_shadow_min = value
		RenderingServer.global_shader_parameter_set("cloud_shadow_min", value)

@export var cloud_world_y: float = 50.0:
	set(value):
		cloud_world_y = value
		RenderingServer.global_shader_parameter_set("cloud_world_y", value)


